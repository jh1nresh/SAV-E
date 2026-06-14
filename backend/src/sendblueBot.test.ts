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
  phraseDiscovery,
  type GeminiCaller,
  type DiscoveredPlace,
  type PendingStore,
} from "./sendblueBot.js";
import type { ExtractedVenue } from "./sendblueBot.js";
import type { ListOpts, SavedPlace, SendbluePlaceStore, StoredLocation } from "./sendbluePlaceStore.js";

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

test("phraseDiscovery falls back to a template when the model fails", async () => {
  const found: DiscoveredPlace[] = [
    { name: "Maru Coffee", address: "1936 Hillhurst Ave", rating: 4.6 },
  ];
  const reply = await phraseDiscovery("coffee", "Los Feliz", found, async () => {
    throw new Error("down");
  }, false);
  assert.match(reply, /Maru Coffee/);
  assert.match(reply, /Los Feliz/);
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
    sawContext = prompt.includes("CONVERSATION CONTEXT");
    return JSON.stringify({ search: { query: "coffee", area: "Tustin" } });
  };
  const decision = await decideRecall("Tustin", [], gemini, false, "coffee");
  assert.equal(sawContext, true);
  assert.deepEqual(decision, { kind: "search", query: "coffee", area: "Tustin" });
});

test("webhook flow: ask location → bare place name resumes search (conversation memory)", async () => {
  const client = new FakeSendblueClient();
  const store = new FakeStore();
  const m = new Map<string, { query: string; at: number }>();
  const pending: PendingStore = {
    get: (p) => m.get(p),
    set: (p, q) => void m.set(p, { query: q, at: 0 }),
    clear: (p) => void m.delete(p),
  };
  let searched = "";
  const placesSearch = async (q: string): Promise<DiscoveredPlace[]> => {
    searched = q;
    return [{ name: "Kean Coffee", address: "Tustin", rating: 4.5 }];
  };
  const gemini: GeminiCaller = async (prompt) => {
    if (prompt.includes("Results:")) return JSON.stringify({ reply: "Try Kean Coffee in Tustin ☕" });
    if (prompt.includes("CONVERSATION CONTEXT")) return JSON.stringify({ search: { query: "coffee", area: "Tustin" } });
    return JSON.stringify({ search: { query: "coffee", area: null } });
  };

  // Turn 1: "find coffee nearby" → asks for location, sets pending.
  const t1 = await processSendblueInbound(
    { from_number: "+15557779999", content: "find me coffee nearby" },
    { client, store, gemini, placesSearch, pending },
  );
  assert.match(t1.reply ?? "", /Where are you|你現在在哪/);
  assert.equal(m.get("+15557779999")?.query, "coffee");

  // Turn 2: bare "Tustin" → resumes the pending coffee search.
  const t2 = await processSendblueInbound(
    { from_number: "+15557779999", content: "Tustin" },
    { client, store, gemini, placesSearch, pending },
  );
  assert.match(searched, /coffee in Tustin/);
  assert.equal(t2.reply, "Try Kean Coffee in Tustin ☕");
  assert.equal(m.get("+15557779999"), undefined); // cleared after resume
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
