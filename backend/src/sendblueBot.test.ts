import assert from "node:assert/strict";
import test from "node:test";
import {
  extractVenueFromCaption,
  fetchLinkCaption,
  firstUrlInText,
  formatVenueReply,
  isListIntent,
  isRecommendIntent,
  isOrderIntent,
  orderQuery,
  isLocationIntent,
  parseLocationQuery,
  detectArea,
  looksChinese,
  processSendblueInbound,
  decideRecall,
  phrasePlaceRec,
  pickBestPlace,
  looksLikeReceipt,
  extractReceipt,
  type GeminiCaller,
  type DiscoveredPlace,
  type ConversationStore,
  type ConversationState,
} from "./sendblueBot.js";
import type { ExtractedVenue } from "./sendblueBot.js";
import type { ListOpts, SavedPlace, SendbluePlaceStore, StoredLocation } from "./sendbluePlaceStore.js";
import type { VerifiedVisit, VerifiedVisitStore } from "./sendblueReceiptStore.js";

function htmlWithOG(description: string, title = "Some Reel"): string {
  return `<!doctype html><html><head>
    <meta property="og:title" content="${title}" />
    <meta property="og:description" content="${description}" />
    <meta property="og:image" content="https://example.com/thumb.jpg" />
  </head><body></body></html>`;
}

function fakeGemini(json: object): GeminiCaller {
  return async () => JSON.stringify(json);
}

class FakeSendblueClient {
  public calls: { to: string; content: string }[] = [];
  public markReadCalls: string[] = [];
  public typingCalls: string[] = [];
  async sendMessage(to: string, content: string): Promise<string> {
    this.calls.push({ to, content });
    return "";
  }
  async markRead(to: string): Promise<void> {
    this.markReadCalls.push(to);
  }
  async sendTypingIndicator(to: string): Promise<void> {
    this.typingCalls.push(to);
  }
}

// In-memory store: keyed by phone, de-dups by lower(name) like the pg impl.
class FakeStore implements SendbluePlaceStore {
  public byPhone = new Map<string, SavedPlace[]>();
  async save(phone: string, venue: ExtractedVenue, sourceUrl?: string): Promise<number> {
    const places = this.byPhone.get(phone) ?? [];
    const existing = places.find((p) => p.name.toLowerCase() === venue.name.toLowerCase());
    if (existing) {
      existing.area = venue.area ?? existing.area;
      existing.category = venue.category ?? existing.category;
    } else {
      places.unshift({ name: venue.name, area: venue.area, category: venue.category, sourceUrl });
    }
    this.byPhone.set(phone, places);
    return new Set(places.map((p) => p.name.toLowerCase())).size;
  }
  async list(phone: string, opts?: number | ListOpts): Promise<SavedPlace[]> {
    const limit = typeof opts === "number" ? opts : opts?.limit ?? 15;
    const area = typeof opts === "number" ? undefined : opts?.area;
    let places = this.byPhone.get(phone) ?? [];
    if (area) {
      const needle = area.toLowerCase();
      places = places.filter((p) => (p.area ?? "").toLowerCase().includes(needle));
    }
    return places.slice(0, limit);
  }
  async distinctAreas(phone: string): Promise<string[]> {
    const areas = (this.byPhone.get(phone) ?? [])
      .map((p) => p.area)
      .filter((a): a is string => Boolean(a && a.trim()));
    return [...new Set(areas)];
  }
  public locations = new Map<string, StoredLocation>();
  async getLocation(phone: string): Promise<StoredLocation | null> {
    return this.locations.get(phone) ?? null;
  }
  async setLocation(phone: string, location: StoredLocation): Promise<void> {
    this.locations.set(phone, location);
  }
}

test("fetchLinkCaption parses og:description and HTML-unescapes it", async () => {
  const fetchText = async () =>
    htmlWithOG("Dinner at Aquarela &amp; sunset views 🌅");
  const result = await fetchLinkCaption("https://www.instagram.com/reel/X/", fetchText);
  assert.equal(result.caption, "Dinner at Aquarela & sunset views 🌅");
  assert.equal(result.imageURL, "https://example.com/thumb.jpg");
});

test("fetchLinkCaption falls back to og:title when no description", async () => {
  const fetchText = async () =>
    `<meta property="og:title" content="Cafe Bola at Roma Norte" />`;
  const result = await fetchLinkCaption("https://example.com/x", fetchText);
  assert.equal(result.caption, "Cafe Bola at Roma Norte");
});

test("extractVenueFromCaption returns venue for an English Aquarela caption", async () => {
  const caption = "Best sunset dinner in Cabo — go to Aquarela in San Jose del Cabo.";
  const gemini = fakeGemini({
    name: "Aquarela",
    area: "San Jose del Cabo",
    category: "restaurant",
    confidence: 0.9,
  });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.ok(venue);
  assert.equal(venue?.name, "Aquarela");
  assert.equal(venue?.area, "San Jose del Cabo");
  assert.equal(venue?.category, "restaurant");
});

test("extractVenueFromCaption handles a Spanish caption (Tec de Monterrey)", async () => {
  const caption = "Comimos riquísimo en el campus del Tec de Monterrey, en la cafetería Las Palmas.";
  const gemini = fakeGemini({
    name: "Las Palmas",
    area: "Monterrey",
    category: "cafetería",
    confidence: 0.7,
  });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.ok(venue);
  assert.equal(venue?.name, "Las Palmas");
});

test("extractVenueFromCaption rejects a hallucinated name not in the caption", async () => {
  const caption = "Amazing tacos somewhere in CDMX, you have to try them.";
  const gemini = fakeGemini({
    name: "El Califa de León",
    area: "CDMX",
    category: "taqueria",
    confidence: 0.8,
  });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.equal(venue, null);
});

test("extractVenueFromCaption rejects a @handle as the venue name", async () => {
  const caption = "Loved this spot, follow @aquarela_cabo for more.";
  const gemini = fakeGemini({
    name: "@aquarela_cabo",
    area: null,
    category: "restaurant",
    confidence: 0.6,
  });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.equal(venue, null);
});

test("extractVenueFromCaption returns null when gemini reports no venue", async () => {
  const caption = "Just vibes today, no spot in particular.";
  const gemini = fakeGemini({ name: null, area: null, category: null, confidence: 0 });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.equal(venue, null);
});

test("extractVenueFromCaption matches case- and diacritic-insensitively", async () => {
  const caption = "Cena increíble en Café Régis, en Roma Norte.";
  const gemini = fakeGemini({
    name: "cafe regis",
    area: "Roma Norte",
    category: "cafe",
    confidence: 0.8,
  });
  const venue = await extractVenueFromCaption(caption, gemini);
  assert.ok(venue);
  assert.equal(venue?.name, "cafe regis");
});

test("firstUrlInText extracts the first http(s) URL and trims trailing punctuation", () => {
  assert.equal(
    firstUrlInText("check this https://www.instagram.com/reel/ABC123/!"),
    "https://www.instagram.com/reel/ABC123/",
  );
  assert.equal(firstUrlInText("no link here"), undefined);
});

test("formatVenueReply builds a short friendly reply", () => {
  const reply = formatVenueReply({ name: "Aquarela", area: "Cabo", category: "restaurant" });
  assert.match(reply, /Found Aquarela in Cabo/);
  assert.match(reply, /restaurant/);
});

test("webhook flow: inbound IG link saves the place and confirms with a count", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const fetchText = async () =>
    htmlWithOG("Sunset dinner at Aquarela in San Jose del Cabo was unreal.");
  const gemini = fakeGemini({
    name: "Aquarela",
    area: "San Jose del Cabo",
    category: "restaurant",
    confidence: 0.9,
  });

  const result = await processSendblueInbound(
    {
      from_number: "+15551234567",
      content: "yo find this place https://www.instagram.com/reel/ABC123/",
    },
    { client, store, fetchText, gemini },
  );

  assert.equal(result.replied, true);
  assert.equal(client.calls.length, 1);
  assert.equal(client.calls[0]?.to, "+15551234567");
  assert.match(client.calls[0]?.content ?? "", /Saved Aquarela/);
  assert.match(client.calls[0]?.content ?? "", /saved 1 place\b/);
  // The place is now remembered for this number.
  assert.equal((await store.list("+15551234567")).length, 1);
});

test("webhook flow: read receipt + typing indicator fire on a valid inbound", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await processSendblueInbound(
    { from_number: "+15550000001", content: "hello there" },
    { client, store },
  );
  assert.deepEqual(client.markReadCalls, ["+15550000001"]);
  assert.deepEqual(client.typingCalls, ["+15550000001"]);
});

test("webhook flow: message with no URL and no intent replies with the hint", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const result = await processSendblueInbound(
    { from_number: "+15550000000", content: "hello there" },
    { client, store },
  );
  assert.equal(result.replied, true);
  assert.equal(client.calls.length, 1);
  assert.match(client.calls[0]?.content ?? "", /Instagram\/TikTok link/);
});

test("webhook flow: 'my places' lists saved places", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15552223333", { name: "Cafe Leon Dore", area: "West Hollywood" });
  await store.save("+15552223333", { name: "Aquarela", area: "Cabo" });

  const result = await processSendblueInbound(
    { from_number: "+15552223333", content: "my places" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /Aquarela — Cabo/);
  assert.match(content, /Cafe Leon Dore — West Hollywood/);
});

test("webhook flow: Chinese list intent replies in 中文", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+886900000000", { name: "鼎泰豐", area: "台北" });

  const result = await processSendblueInbound(
    { from_number: "+886900000000", content: "我存了哪些" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /你存過的地點/);
  assert.match(content, /鼎泰豐/);
});

test("decideRecall: grounded reply from saved places", async () => {
  const places: SavedPlace[] = [
    { name: "Cafe Leon Dore", area: "West Hollywood", category: "cafe" },
    { name: "Aquarela", area: "Cabo", category: "restaurant" },
  ];
  let seenPrompt = "";
  const gemini: GeminiCaller = async (prompt) => {
    seenPrompt = prompt;
    return JSON.stringify({ reply: "Cafe Leon Dore in West Hollywood ☕" });
  };
  const decision = await decideRecall("which cafe did I save?", places, gemini, false);
  assert.deepEqual(decision, { kind: "reply", reply: "Cafe Leon Dore in West Hollywood ☕" });
  // Grounded: both saved places appear in the prompt context.
  assert.match(seenPrompt, /Cafe Leon Dore/);
  assert.match(seenPrompt, /Aquarela/);
});

test("decideRecall: search decision when user wants something new nearby", async () => {
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ search: { query: "coffee", area: "Santa Monica" } });
  const decision = await decideRecall(
    "that one's too far, anything in Santa Monica?",
    [{ name: "Cafe Leon Dore", area: "West Hollywood" }],
    gemini,
    false,
  );
  assert.deepEqual(decision, { kind: "search", query: "coffee", area: "Santa Monica" });
});

test("decideRecall: search with no location → area null", async () => {
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ search: { query: "ramen", area: null } });
  const decision = await decideRecall("find me ramen nearby", [], gemini, false);
  assert.deepEqual(decision, { kind: "search", query: "ramen", area: null });
});

test("decideRecall: null on unusable / thrown model output", async () => {
  const places: SavedPlace[] = [{ name: "Tartine", area: "San Francisco" }];
  assert.equal(await decideRecall("hi", places, async () => "not json", false), null);
  assert.equal(
    await decideRecall("hi", places, async () => {
      throw new Error("boom");
    }, false),
    null,
  );
});

test("phrasePlaceRec falls back to a template when the model fails", async () => {
  const place: DiscoveredPlace = { name: "Maru Coffee", address: "1936 Hillhurst Ave", rating: 4.6 };
  const reply = await phrasePlaceRec(place, "Los Feliz", async () => {
    throw new Error("down");
  }, false);
  assert.match(reply, /Maru Coffee/);
  assert.match(reply, /Los Feliz/);
});

test("pickBestPlace skips already-shown names, then picks highest rating", () => {
  const found: DiscoveredPlace[] = [
    { name: "Ayer Coffee", rating: 4.8 },
    { name: "Kean Coffee", rating: 4.5 },
    { name: "Maru Coffee", rating: 4.7 },
  ];
  // Nothing shown → highest rating.
  assert.equal(pickBestPlace(found, [])?.name, "Ayer Coffee");
  // Ayer shown → next highest unshown.
  assert.equal(pickBestPlace(found, ["Ayer Coffee"])?.name, "Maru Coffee");
  // All shown → falls back to highest overall (better than dead-end).
  assert.equal(pickBestPlace(found, ["Ayer Coffee", "Kean Coffee", "Maru Coffee"])?.name, "Ayer Coffee");
});

test("webhook flow: agentic reply used when a gemini is injected", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15557778888", { name: "Cafe Leon Dore", area: "West Hollywood", category: "cafe" });
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ reply: "Go grab coffee at Cafe Leon Dore ☕" });

  const result = await processSendblueInbound(
    { from_number: "+15557778888", content: "i feel like coffee, ideas?" },
    { client, store, gemini },
  );
  assert.equal(result.replied, true);
  assert.equal(client.calls[0]?.content, "Go grab coffee at Cafe Leon Dore ☕");
});

test("webhook flow: discovery searches Google when the model asks for it", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15551112222", { name: "Cafe Leon Dore", area: "West Hollywood" });
  let searchedQuery = "";
  const placesSearch = async (query: string): Promise<DiscoveredPlace[]> => {
    searchedQuery = query;
    return [{ name: "Maru Coffee", address: "Los Feliz", rating: 4.6 }];
  };
  // 1st gemini call = decision (search); 2nd = phrasing.
  let call = 0;
  const gemini: GeminiCaller = async () => {
    call += 1;
    return call === 1
      ? JSON.stringify({ search: { query: "coffee", area: "Los Feliz" } })
      : JSON.stringify({ reply: "Try Maru Coffee in Los Feliz ☕" });
  };

  const result = await processSendblueInbound(
    { from_number: "+15551112222", content: "that's too far, coffee in Los Feliz?" },
    { client, store, gemini, placesSearch },
  );
  assert.equal(result.replied, true);
  assert.match(searchedQuery, /coffee in Los Feliz/);
  assert.equal(client.calls[0]?.content, "Try Maru Coffee in Los Feliz ☕");
});

test("webhook flow: discovery with no location asks where you are", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ search: { query: "coffee", area: null } });

  const result = await processSendblueInbound(
    { from_number: "+15553334444", content: "find me a coffee place nearby" },
    { client, store, gemini },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /Where are you|你現在在哪/);
});

test("decideRecall: a bare location resumes the pending discovery query", async () => {
  let sawContext = false;
  const gemini: GeminiCaller = async (prompt) => {
    sawContext = prompt.includes("LOCATION FOLLOW-UP");
    return JSON.stringify({ search: { query: "coffee", area: "Tustin" } });
  };
  const decision = await decideRecall("Tustin", [], gemini, false, { pendingQuery: "coffee" });
  assert.equal(sawContext, true);
  assert.deepEqual(decision, { kind: "search", query: "coffee", area: "Tustin" });
});

test("decideRecall: a follow-up about a recommended place is grounded in its data", async () => {
  let sawRecent = false;
  const gemini: GeminiCaller = async (prompt) => {
    sawRecent = prompt.includes("THE PLACE YOU JUST RECOMMENDED is: Ayer Coffee");
    return JSON.stringify({
      reply: "I don't have Ayer Coffee's menu, but it's rated 4.8★ — want me to save it?",
    });
  };
  const decision = await decideRecall("what's their best coffee", [], gemini, false, {
    lastRecommended: { name: "Ayer Coffee", rating: 4.8, address: "Tustin" },
  });
  assert.equal(sawRecent, true);
  assert.equal(decision?.kind, "reply");
});

// Minimal in-memory ConversationStore for webhook tests.
function fakeConversation(): { store: ConversationStore; map: Map<string, ConversationState> } {
  const map = new Map<string, ConversationState>();
  const get = (p: string) => map.get(p);
  const store: ConversationStore = {
    get,
    setPending: (p, q) => map.set(p, { ...(get(p) ?? { at: 0 }), pendingQuery: q, at: 0 }),
    setPlaces: (p, places) => map.set(p, { ...(get(p) ?? { at: 0 }), lastPlaces: places.slice(0, 5), at: 0 }),
    setRecommended: (p, place) => map.set(p, { ...(get(p) ?? { at: 0 }), lastRecommended: place, at: 0 }),
    setArea: (p, area) => map.set(p, { ...(get(p) ?? { at: 0 }), lastArea: area, at: 0 }),
    addShown: (p, name) =>
      map.set(p, { ...(get(p) ?? { at: 0 }), shownNames: [...(get(p)?.shownNames ?? []), name], at: 0 }),
    clearPending: (p) => {
      const v = get(p);
      if (v) map.set(p, { ...v, pendingQuery: undefined, at: 0 });
    },
  };
  return { store, map };
}

test("webhook flow: ask location → bare place name resumes search (conversation memory)", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation, map } = fakeConversation();
  let searched = "";
  const placesSearch = async (q: string): Promise<DiscoveredPlace[]> => {
    searched = q;
    return [{ name: "Kean Coffee", address: "Tustin", rating: 4.5 }];
  };
  const gemini: GeminiCaller = async (prompt) => {
    if (prompt.includes("Recommend this ONE place")) return JSON.stringify({ reply: "Try Kean Coffee in Tustin ☕" });
    if (prompt.includes("LOCATION FOLLOW-UP")) return JSON.stringify({ search: { query: "coffee", area: "Tustin" } });
    return JSON.stringify({ search: { query: "coffee", area: null } });
  };

  // Turn 1: "find coffee nearby" → asks for location, sets pending.
  const t1 = await processSendblueInbound(
    { from_number: "+15557779999", content: "find me coffee nearby" },
    { client, store, gemini, placesSearch, conversation },
  );
  assert.match(t1.reply ?? "", /Where are you|你現在在哪/);
  assert.equal(map.get("+15557779999")?.pendingQuery, "coffee");

  // Turn 2: bare "Tustin" → resumes the pending coffee search + remembers the result.
  const t2 = await processSendblueInbound(
    { from_number: "+15557779999", content: "Tustin" },
    { client, store, gemini, placesSearch, conversation },
  );
  assert.match(searched, /coffee in Tustin/);
  assert.equal(t2.reply, "Try Kean Coffee in Tustin ☕");
  assert.equal(map.get("+15557779999")?.pendingQuery, undefined); // pending cleared
  assert.equal(map.get("+15557779999")?.lastPlaces?.[0]?.name, "Kean Coffee"); // remembered
});

test("webhook flow: follow-up about the recommended place is answered (not 'not saved')", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation } = fakeConversation();
  // Seed: the bot already recommended Maru Coffee to this number.
  conversation.setPlaces("+15551230000", [{ name: "Maru Coffee", rating: 4.7, address: "Los Feliz" }]);
  const gemini: GeminiCaller = async (prompt) => {
    assert.ok(prompt.includes("Maru Coffee"), "recommended place must be in the prompt context");
    return JSON.stringify({ reply: "Maru Coffee is rated 4.7★ in Los Feliz — I don't have their menu though." });
  };

  const result = await processSendblueInbound(
    { from_number: "+15551230000", content: "what's their best coffee" },
    { client, store, gemini, conversation },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls.at(-1)?.content ?? "", /Maru Coffee/);
});

test("webhook flow: 'something else' reuses last location and returns a DIFFERENT place", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation } = fakeConversation();
  // Seed: we already recommended Ayer Coffee near Tustin.
  conversation.setArea("+15552345678", "Tustin");
  conversation.addShown("+15552345678", "Ayer Coffee");
  let searched = "";
  let askedLocation = false;
  const placesSearch = async (q: string): Promise<DiscoveredPlace[]> => {
    searched = q;
    return [
      { name: "Ayer Coffee", rating: 4.8 },
      { name: "Kean Coffee", rating: 4.6, address: "Tustin" },
    ];
  };
  const gemini: GeminiCaller = async (prompt) => {
    if (prompt.includes("Recommend this ONE place")) {
      return JSON.stringify({ reply: "Try Kean Coffee in Tustin ☕" });
    }
    // decideRecall: the LAST KNOWN LOCATION context must be present so it reuses it.
    assert.ok(prompt.includes("LAST KNOWN LOCATION"), "last location must be in context");
    return JSON.stringify({ search: { query: "coffee", area: "Tustin" } });
  };

  const result = await processSendblueInbound(
    { from_number: "+15552345678", content: "Recommend something else" },
    { client, store, gemini, placesSearch, conversation },
  );
  const out = client.calls.at(-1)?.content ?? "";
  askedLocation = /Where are you|你現在在哪/.test(out);
  assert.equal(askedLocation, false, "must NOT re-ask for location");
  assert.match(searched, /coffee in Tustin/); // reused the area
  assert.match(out, /Kean Coffee/); // different place, not Ayer again
  assert.doesNotMatch(out, /Ayer Coffee/);
  assert.equal(result.replied, true);
});

test("webhook flow: agentic falls back to keyword list when model yields nothing", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15559990000", { name: "Aquarela", area: "Cabo" });
  // Model returns unusable output → keyword 'my places' list takes over.
  const gemini: GeminiCaller = async () => "garbage, not json";

  const result = await processSendblueInbound(
    { from_number: "+15559990000", content: "my places" },
    { client, store, gemini },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /Aquarela/);
});

test("webhook flow: list intent with empty store replies with a friendly empty message", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const result = await processSendblueInbound(
    { from_number: "+15554445555", content: "what have I saved?" },
    { client, store },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /haven't saved any places yet/);
});

test("webhook flow: Chinese save confirmation localizes", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const fetchText = async () => htmlWithOG("超讚的鼎泰豐 在 台北 信義區");
  const gemini = fakeGemini({ name: "鼎泰豐", area: "台北", category: "restaurant", confidence: 0.9 });
  const result = await processSendblueInbound(
    { from_number: "+886911111111", content: "找這間 https://www.instagram.com/reel/ABC/" },
    { client, store, fetchText, gemini },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /已存 鼎泰豐/);
  assert.match(content, /你已存 1 個地點/);
});

test("webhook flow: outbound/status event produces NO reply", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const result = await processSendblueInbound(
    {
      is_outbound: true,
      from_number: "+15550000000",
      content: "https://www.instagram.com/reel/ABC123/",
    },
    { client, store },
  );
  assert.equal(result.replied, false);
  assert.equal(client.calls.length, 0);
  assert.equal(client.markReadCalls.length, 0);
});

test("webhook flow: venue not found replies with the graceful message", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const fetchText = async () => htmlWithOG("just some vibes, no place named");
  const gemini = fakeGemini({ name: null, area: null, category: null, confidence: 0 });
  const result = await processSendblueInbound(
    {
      from_number: "+15551112222",
      content: "https://www.instagram.com/reel/XYZ/",
    },
    { client, store, fetchText, gemini },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /Couldn't find a clear place/);
});

test("webhook flow: alternate field names (body/from) are accepted", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const result = await processSendblueInbound(
    { from: "+15559998888", body: "no link" },
    { client, store },
  );
  assert.equal(result.replied, true);
  assert.equal(client.calls[0]?.to, "+15559998888");
});

test("isListIntent matches English + 中文 phrases, ignores plain text", () => {
  assert.equal(isListIntent("my places"), true);
  assert.equal(isListIntent("WHAT HAVE I SAVED?"), true);
  assert.equal(isListIntent("我存了哪些"), true);
  assert.equal(isListIntent("清單"), true);
  assert.equal(isListIntent("hello there"), false);
});

test("looksChinese detects CJK", () => {
  assert.equal(looksChinese("我存了哪些"), true);
  assert.equal(looksChinese("my places"), false);
});

test("isRecommendIntent matches English + 中文, ignores plain text", () => {
  assert.equal(isRecommendIntent("recommend somewhere in LA"), true);
  assert.equal(isRecommendIntent("where should I go tonight"), true);
  assert.equal(isRecommendIntent("推薦台北的"), true);
  assert.equal(isRecommendIntent("附近有什麼"), true);
  assert.equal(isRecommendIntent("hello there"), false);
});

test("detectArea matches the user's own saved areas (longest wins)", () => {
  const saved = ["West Hollywood", "Los Angeles", "LA"];
  // "I'm in LA" → some saved area is detected.
  assert.ok(detectArea("I'm in LA right now", saved));
  // "near West Hollywood" → the longest match.
  assert.equal(detectArea("near West Hollywood", saved), "West Hollywood");
  // No match against saved areas.
  assert.equal(detectArea("I'm in Tokyo", saved), undefined);
});

test("webhook flow: recommend intent names a saved place in the detected area", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15551110000", { name: "Cafe Leon Dore", area: "Los Angeles", category: "cafe" });
  await store.save("+15551110000", { name: "Rolo's", area: "Brooklyn", category: "restaurant" });

  const result = await processSendblueInbound(
    { from_number: "+15551110000", content: "recommend somewhere in Los Angeles" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /Go to Cafe Leon Dore in Los Angeles/);
  assert.doesNotMatch(content, /Rolo's/);
});

test("webhook flow: Chinese recommend intent picks a place in that area", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+886900000001", { name: "鼎泰豐", area: "台北", category: "restaurant" });

  const result = await processSendblueInbound(
    { from_number: "+886900000001", content: "推薦台北的" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /去 鼎泰豐（台北）/);
});

test("webhook flow: recommend with an area where nothing is saved → haven't-saved reply", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  // Saved area is "Los Angeles"; the user asks about it but has nothing there yet.
  // To trigger detection without a match we save the area on a different place,
  // then filter to a sub-area that matches detection but yields no rows.
  await store.save("+15552220000", { name: "Tartine", area: "San Francisco", category: "bakery" });

  const result = await processSendblueInbound(
    { from_number: "+15552220000", content: "where should I go in San Francisco for sushi" },
    { client, store },
  );
  // Area "San Francisco" is detected and Tartine matches, so it recommends.
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /Go to Tartine in San Francisco/);
});

test("webhook flow: recommend with empty store → friendly empty reply", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const result = await processSendblueInbound(
    { from_number: "+15553330000", content: "recommend somewhere" },
    { client, store },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /haven't saved any places yet/);
});

test("webhook flow: recommend in a saved area with no match → haven't-saved-there reply", async () => {
  const client = new FakeSendblueClient();
  // Custom store: distinctAreas reports an area, but list(area) returns nothing.
  const store: SendbluePlaceStore = {
    async save() {
      return 0;
    },
    async list() {
      return [];
    },
    async distinctAreas() {
      return ["Los Angeles"];
    },
    async getLocation() {
      return null;
    },
    async setLocation() {},
  };
  const result = await processSendblueInbound(
    { from_number: "+15554440000", content: "recommend somewhere in Los Angeles" },
    { client, store },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /haven't saved anything in Los Angeles yet/);
});

test("webhook flow: area-filtered list ('my places in LA')", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15555550000", { name: "Cafe Leon Dore", area: "LA" });
  await store.save("+15555550000", { name: "Rolo's", area: "Brooklyn" });

  const result = await processSendblueInbound(
    { from_number: "+15555550000", content: "my places in LA" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /Your saved places in LA/);
  assert.match(content, /Cafe Leon Dore/);
  assert.doesNotMatch(content, /Rolo's/);
});

test("webhook flow: bare area mention lists that area", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+886900000002", { name: "鼎泰豐", area: "台北" });

  const result = await processSendblueInbound(
    { from_number: "+886900000002", content: "我在台北存了哪些" },
    { client, store },
  );
  assert.equal(result.replied, true);
  const content = client.calls[0]?.content ?? "";
  assert.match(content, /你在 台北 存的/);
  assert.match(content, /鼎泰豐/);
});

test("isOrderIntent + orderQuery", () => {
  assert.equal(isOrderIntent("order iced latte from raposa"), true);
  assert.equal(isOrderIntent("下單 一杯拿鐵"), true);
  assert.equal(isOrderIntent("buy me a cold brew"), true);
  assert.equal(isOrderIntent("recommend somewhere nearby"), false);
  assert.equal(isOrderIntent("in order to plan my trip"), false);
  assert.equal(orderQuery("order iced latte"), "iced latte");
  assert.equal(orderQuery("下單 拿鐵"), "拿鐵");
});

test("webhook flow: order intent (with known location) routes to the SLL-R order dep (not saved)", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.setLocation("+15551112222", { label: "Miami Beach", lat: 25.79, lng: -80.13 });
  let received = "";
  let receivedLoc: StoredLocation | undefined;
  const result = await processSendblueInbound(
    { from_number: "+15551112222", content: "order iced latte" },
    {
      client,
      store,
      order: async (q, _from, loc) => {
        received = q;
        receivedLoc = loc;
        return "✅ Ordered Iced latte ($6.50) at Raposa Coffee. I'll text you when it's confirmed.";
      },
    },
  );
  assert.equal(received, "iced latte");
  assert.equal(receivedLoc?.label, "Miami Beach"); // location threaded through
  assert.equal(result.replied, true);
  assert.match(client.calls[0]?.content ?? "", /Ordered Iced latte/);
  assert.equal((await store.list("+15551112222")).length, 0); // ordering ≠ saving a place
});

test("webhook flow: order with NO known location asks for the area", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  let orderCalled = false;
  const result = await processSendblueInbound(
    { from_number: "+15559990000", content: "order iced latte" },
    { client, store, order: async () => { orderCalled = true; return "x"; } },
  );
  assert.equal(orderCalled, false); // didn't order without a location
  assert.match(client.calls[0]?.content ?? "", /what area/i);
  assert.equal(result.replied, true);
});

test("webhook flow: 'I'm in X' geocodes + stores the location", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  let geocoded = "";
  const result = await processSendblueInbound(
    { from_number: "+15551112222", content: "I'm in Santa Monica" },
    {
      client,
      store,
      geocode: async (area) => { geocoded = area; return { label: "Santa Monica, CA", lat: 34.0195, lng: -118.4912 }; },
    },
  );
  assert.equal(geocoded, "Santa Monica");
  assert.equal((await store.getLocation("+15551112222"))?.label, "Santa Monica, CA");
  assert.match(client.calls[0]?.content ?? "", /Santa Monica/);
  assert.equal(result.replied, true);
});

test("isLocationIntent + parseLocationQuery", () => {
  assert.equal(isLocationIntent("I'm in Miami Beach"), true);
  assert.equal(isLocationIntent("area: downtown LA"), true);
  assert.equal(isLocationIntent("我在台北"), true);
  assert.equal(isLocationIntent("order iced latte"), false);
  assert.equal(parseLocationQuery("I'm in Miami Beach"), "Miami Beach");
  assert.equal(parseLocationQuery("area: downtown LA"), "downtown LA");
});

// --- Receipts → verified visits ------------------------------------------

class FakeReceiptStore implements VerifiedVisitStore {
  public byPhone = new Map<string, VerifiedVisit[]>();
  async save(phone: string, visit: VerifiedVisit): Promise<number> {
    const list = this.byPhone.get(phone) ?? [];
    list.unshift(visit);
    this.byPhone.set(phone, list);
    return list.length;
  }
  async list(phone: string, limit = 15): Promise<VerifiedVisit[]> {
    return (this.byPhone.get(phone) ?? []).slice(0, limit);
  }
}

test("looksLikeReceipt gates receipt-ish text and ignores normal chat", () => {
  assert.equal(looksLikeReceipt("Thank you for your order! Total: $24.50"), true);
  assert.equal(looksLikeReceipt("Subtotal 18.00 Tax 1.62"), true);
  assert.equal(looksLikeReceipt("收據 金額 NT$320"), true);
  assert.equal(looksLikeReceipt("recommend coffee nearby"), false);
  assert.equal(looksLikeReceipt("what did I save"), false);
});

test("extractReceipt returns merchant only when the model confirms a receipt", async () => {
  const yes: GeminiCaller = async () =>
    JSON.stringify({ is_receipt: true, merchant: "Blue Bottle", total: "$8.50", date: "2026-06-14" });
  assert.deepEqual(await extractReceipt("...", yes), {
    merchant: "Blue Bottle",
    total: "$8.50",
    date: "2026-06-14",
  });
  const no: GeminiCaller = async () => JSON.stringify({ is_receipt: false, merchant: null });
  assert.equal(await extractReceipt("just a chat", no), null);
});

test("webhook flow: a forwarded receipt is logged as a verified visit", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const receiptStore = new FakeReceiptStore();
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ is_receipt: true, merchant: "Ayer Coffee", total: "$6.25", date: null });

  const result = await processSendblueInbound(
    { from_number: "+15558889999", content: "Thanks for your order at Ayer Coffee! Total $6.25" },
    { client, store, gemini, receiptStore },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls.at(-1)?.content ?? "", /verified visit/i);
  assert.match(client.calls.at(-1)?.content ?? "", /Ayer Coffee/);
  assert.equal(receiptStore.byPhone.get("+15558889999")?.[0]?.merchant, "Ayer Coffee");
  assert.equal(receiptStore.byPhone.get("+15558889999")?.[0]?.total, "$6.25");
});

test("webhook flow: a non-receipt message is NOT logged as a visit", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  await store.save("+15557776666", { name: "Cafe Leon Dore", area: "West Hollywood" });
  const receiptStore = new FakeReceiptStore();
  // Heuristic won't even fire for this, but make the model say "not a receipt" too.
  const gemini: GeminiCaller = async (prompt) =>
    prompt.includes("is_receipt")
      ? JSON.stringify({ is_receipt: false, merchant: null })
      : JSON.stringify({ reply: "You saved Cafe Leon Dore." });

  const result = await processSendblueInbound(
    { from_number: "+15557776666", content: "what did I save" },
    { client, store, gemini, receiptStore },
  );
  assert.equal(result.replied, true);
  assert.equal(receiptStore.byPhone.get("+15557776666"), undefined); // nothing logged
});

// --- Location coherence + recommended-place grounding --------------------

test("decideRecall: a bare location with nothing pending → location decision", async () => {
  const gemini: GeminiCaller = async () =>
    JSON.stringify({ location: { area: "Tustin, CA" } });
  const decision = await decideRecall("16267 Stella Cir, Tustin, CA", [], gemini, false, {});
  assert.deepEqual(decision, { kind: "location", area: "Tustin, CA" });
});

test("webhook flow: stating a location stores it and asks what they want (no hollow 'I'll remember')", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation, map } = fakeConversation();
  const gemini: GeminiCaller = async () => JSON.stringify({ location: { area: "Tustin" } });

  const result = await processSendblueInbound(
    { from_number: "+15551112222", content: "16267 Stella Cir, Tustin, CA" },
    { client, store, gemini, conversation },
  );
  assert.equal(result.replied, true);
  assert.match(client.calls.at(-1)?.content ?? "", /what are you looking for|要找什麼/);
  assert.equal(map.get("+15551112222")?.lastArea, "Tustin"); // actually remembered
});

test("decideRecall: a follow-up answers about THE recommended place, not another option", async () => {
  let prompt = "";
  const gemini: GeminiCaller = async (p) => {
    prompt = p;
    return JSON.stringify({ reply: "I don't have Jam Jam Tea Lab's menu, but it's 4.7★." });
  };
  const decision = await decideRecall("what's their popular drink", [], gemini, false, {
    lastRecommended: { name: "Jam Jam Tea Lab", rating: 4.7, address: "Irvine" },
    lastPlaces: [
      { name: "Jam Jam Tea Lab", rating: 4.7 },
      { name: "3CAT Handcrafted Beverage", rating: 4.0 },
    ],
  });
  // The recommended place is singled out; the model is told not to switch places.
  assert.match(prompt, /THE PLACE YOU JUST RECOMMENDED is: Jam Jam Tea Lab/);
  assert.match(prompt, /never silently switch/);
  assert.equal(decision?.kind, "reply");
});

test("webhook flow: discovery records THE recommended place as lastRecommended", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation, map } = fakeConversation();
  conversation.setArea("+15553339999", "Tustin");
  const placesSearch = async (): Promise<DiscoveredPlace[]> => [
    { name: "Jam Jam Tea Lab", rating: 4.7, address: "Irvine" },
    { name: "3CAT", rating: 4.0 },
  ];
  const gemini: GeminiCaller = async (p) =>
    p.includes("Recommend this ONE place")
      ? JSON.stringify({ reply: "Try Jam Jam Tea Lab ✨" })
      : JSON.stringify({ search: { query: "boba", area: "Tustin" } });

  await processSendblueInbound(
    { from_number: "+15553339999", content: "recommend a boba place" },
    { client, store, gemini, placesSearch, conversation },
  );
  assert.equal(map.get("+15553339999")?.lastRecommended?.name, "Jam Jam Tea Lab");
});

test("webhook flow: known location is reused even when the model returns a null area (deterministic)", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const { store: conversation } = fakeConversation();
  conversation.setArea("+15554443210", "Tustin"); // we already know where they are
  let searched = "";
  const placesSearch = async (q: string): Promise<DiscoveredPlace[]> => {
    searched = q;
    return [{ name: "Jam Jam Tea Lab", rating: 4.7 }];
  };
  const gemini: GeminiCaller = async (p) =>
    p.includes("Recommend this ONE place")
      ? JSON.stringify({ reply: "Try Jam Jam Tea Lab ✨" })
      : // Model "forgets" to fill the area — code must reuse lastArea anyway.
        JSON.stringify({ search: { query: "boba", area: null } });

  const result = await processSendblueInbound(
    { from_number: "+15554443210", content: "recommend me a boba place" },
    { client, store, gemini, placesSearch, conversation },
  );
  assert.match(searched, /boba in Tustin/); // reused area, did NOT re-ask
  assert.doesNotMatch(client.calls.at(-1)?.content ?? "", /Where are you|你現在在哪/);
  assert.match(client.calls.at(-1)?.content ?? "", /Jam Jam Tea Lab/);
  assert.equal(result.replied, true);
});
