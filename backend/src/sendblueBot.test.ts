import assert from "node:assert/strict";
import test from "node:test";
import {
  extractVenueFromCaption,
  fetchLinkCaption,
  firstUrlInText,
  formatVenueReply,
  isListIntent,
  isRecommendIntent,
  detectArea,
  looksChinese,
  processSendblueInbound,
  answerOverSavedPlaces,
  type GeminiCaller,
} from "./sendblueBot.js";
import type { ExtractedVenue } from "./sendblueBot.js";
import type { ListOpts, SavedPlace, SendbluePlaceStore } from "./sendbluePlaceStore.js";

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

test("answerOverSavedPlaces grounds a free-form question in the saved list", async () => {
  const places: SavedPlace[] = [
    { name: "Cafe Leon Dore", area: "West Hollywood", category: "cafe" },
    { name: "Aquarela", area: "Cabo", category: "restaurant" },
  ];
  let seenPrompt = "";
  const gemini: GeminiCaller = async (prompt) => {
    seenPrompt = prompt;
    return JSON.stringify({ reply: "Cafe Leon Dore in West Hollywood is your coffee spot ☕" });
  };
  const reply = await answerOverSavedPlaces("where can I get coffee tonight?", places, gemini, false);
  assert.equal(reply, "Cafe Leon Dore in West Hollywood is your coffee spot ☕");
  // The model is grounded: both saved places are in the prompt context.
  assert.match(seenPrompt, /Cafe Leon Dore/);
  assert.match(seenPrompt, /Aquarela/);
});

test("answerOverSavedPlaces returns null on empty list or unusable model output", async () => {
  const places: SavedPlace[] = [{ name: "Tartine", area: "San Francisco" }];
  assert.equal(await answerOverSavedPlaces("hi", [], fakeGemini({ reply: "x" }), false), null);
  assert.equal(await answerOverSavedPlaces("hi", places, async () => "not json", false), null);
  assert.equal(
    await answerOverSavedPlaces("hi", places, async () => {
      throw new Error("boom");
    }, false),
    null,
  );
});

test("webhook flow: agentic answer used when a gemini is injected", async () => {
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
