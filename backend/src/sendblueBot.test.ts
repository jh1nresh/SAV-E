import assert from "node:assert/strict";
import test from "node:test";
import {
  extractVenueFromCaption,
  fetchLinkCaption,
  firstUrlInText,
  formatVenueReply,
  isListIntent,
  looksChinese,
  processSendblueInbound,
  type GeminiCaller,
} from "./sendblueBot.js";
import type { ExtractedVenue } from "./sendblueBot.js";
import type { SavedPlace, SendbluePlaceStore } from "./sendbluePlaceStore.js";

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
  async list(phone: string, limit = 15): Promise<SavedPlace[]> {
    return (this.byPhone.get(phone) ?? []).slice(0, limit);
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
