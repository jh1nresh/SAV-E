// Sendblue iMessage bot (SPIKE).
//
// Flow: a user texts SAV-E's Sendblue number a message. If it contains a social
// link (Instagram/TikTok/小紅书/etc.), we fetch the link's public caption,
// extract the venue via Gemini, and text back the place. This bypasses the iOS
// app entirely so we can validate "text a reel -> get the place" with real users.
//
// This is a minimal synchronous spike: the webhook does the fetch+extract+reply
// work inline and always returns 200 to Sendblue (even on internal errors).
//
// Required environment variables:
//   SENDBLUE_API_KEY_ID       - Sendblue API key id (header: sb-api-key-id)
//   SENDBLUE_API_SECRET       - Sendblue API secret (header: sb-api-secret-key)
//   SENDBLUE_SIGNING_SECRET   - optional; if set, inbound webhooks are HMAC-verified
//   GEMINI_API_KEY            - (or GOOGLE_GEMINI_API_KEY) for venue extraction
//   SAVE_MAAT_GEMINI_MODEL    - optional Gemini model override
//
// Reused backend pieces (SSRF-safe fetch + OG metadata parsing) come from
// sourceSearchWorker.ts so we don't duplicate the safe-fetch logic.

import { createHmac, timingSafeEqual } from "node:crypto";
import {
  decodeHTML,
  defaultFetchText,
  sourceMetadataFromHTML,
} from "./sourceSearchWorker.js";
import type { SavedPlace, SendbluePlaceStore, StoredLocation } from "./sendbluePlaceStore.js";
import type { VerifiedVisitStore } from "./sendblueReceiptStore.js";

const geminiEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models";
const defaultGeminiModel = "gemini-2.5-flash";
const maxCaptionChars = 4_000;

export type FetchText = (url: string) => Promise<string>;

export type LinkCaption = {
  caption: string;
  imageURL?: string;
  resolvedURL?: string;
};

/**
 * Fetch a social/web link and return its public caption (og:description ??
 * og:title, HTML-unescaped). SSRF-safe: reuses defaultFetchText which blocks
 * non-public / redirecting URLs. fetchText is injectable for tests.
 */
export async function fetchLinkCaption(
  url: string,
  fetchText: FetchText = defaultFetchText,
): Promise<LinkCaption> {
  const html = await fetchText(url);
  const metadata = sourceMetadataFromHTML(html, url);
  const rawCaption = metadata.description ?? metadata.title ?? "";
  const caption = decodeHTML(rawCaption).replace(/\s+/g, " ").trim().slice(0, maxCaptionChars);
  return {
    caption,
    imageURL: metadata.imageURL,
    resolvedURL: metadata.resolvedURL,
  };
}

export type ExtractedVenue = {
  name: string;
  area?: string;
  category?: string;
  confidence?: number;
};

export type GeminiCaller = (prompt: string) => Promise<string>;

/**
 * Extract a venue from a caption using Gemini. Mirrors the iOS extractor:
 * the venue name MUST literally appear in the caption, we never return a
 * @handle or #hashtag as the name, and we prefer the specific place over a
 * larger campus. gemini is injectable so tests run without network.
 *
 * Returns null when no clear venue is found OR when the model hallucinates a
 * name that does not appear in the caption / is a handle/hashtag.
 */
export async function extractVenueFromCaption(
  caption: string,
  gemini: GeminiCaller = defaultGeminiText,
): Promise<ExtractedVenue | null> {
  const trimmed = caption.trim();
  if (!trimmed) return null;

  const prompt = venueExtractionPrompt(trimmed);
  let raw: string;
  try {
    raw = await gemini(prompt);
  } catch {
    return null;
  }

  const parsed = parseVenueJson(raw);
  if (!parsed) return null;

  const name = typeof parsed.name === "string" ? parsed.name.trim() : "";
  if (!name) return null;
  // Guard: never surface a @handle or #hashtag as the venue name.
  if (name.startsWith("@") || name.startsWith("#")) return null;
  // Guard: the name must literally appear in the caption (hallucination guard),
  // case- and diacritic-insensitive.
  if (!captionContains(trimmed, name)) return null;

  const area = typeof parsed.area === "string" ? parsed.area.trim() : undefined;
  const category = typeof parsed.category === "string" ? parsed.category.trim() : undefined;
  const confidence = typeof parsed.confidence === "number" ? parsed.confidence : undefined;

  return {
    name,
    area: area || undefined,
    category: category || undefined,
    confidence,
  };
}

function venueExtractionPrompt(caption: string): string {
  return `You extract the single real-world venue (restaurant, cafe, bar, shop, hotel, attraction) mentioned in a social media caption for a travel app.

Rules:
- The venue "name" MUST be a substring that literally appears in the caption. Do not translate, normalize, or invent it.
- NEVER return a @handle or #hashtag as the name. Those are accounts/tags, not venues.
- Prefer the specific place over a larger campus or chain (e.g. a specific cafe inside a mall, not the mall).
- Captions may be in any language (English, Spanish, Chinese, etc.). Keep the name in its original language.
- "area" is the city / neighborhood / region if stated; otherwise null.
- "category" is a short label like "restaurant", "cafe", "rooftop bar", "hotel".
- "confidence" is 0.0-1.0.
- If there is no clear single venue, set name to null.

Return STRICT JSON only, no markdown, in this exact shape:
{"name": string|null, "area": string|null, "category": string|null, "confidence": number}

Caption:
${caption}`;
}

type ParsedVenue = {
  name?: unknown;
  area?: unknown;
  category?: unknown;
  confidence?: unknown;
};

function parseVenueJson(text: string): ParsedVenue | null {
  const tryParse = (value: string): ParsedVenue | null => {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (parsed && typeof parsed === "object") return parsed as ParsedVenue;
    } catch {
      // fall through
    }
    return null;
  };

  const direct = tryParse(text.trim());
  if (direct) return direct;
  const match = text.match(/\{[\s\S]*\}/);
  if (match) return tryParse(match[0]);
  return null;
}

/**
 * Case- and diacritic-insensitive substring check (the model may return the
 * name with different casing). Used as the hallucination guard.
 */
function captionContains(caption: string, name: string): boolean {
  return foldText(caption).includes(foldText(name));
}

function foldText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim();
}

// ---------------------------------------------------------------------------
// Receipts → verified visits (the receipt-gated-review primitive).
// A user forwards/texts a purchase receipt; we confirm it's a receipt, extract
// the merchant, and record a VERIFIED VISIT keyed by their phone number.
// ---------------------------------------------------------------------------

export type ExtractedReceipt = { merchant: string; total?: string; date?: string };

// Cheap pre-filter so we don't spend an LLM call on every message — only text
// that smells like a receipt/order/payment is sent on to the model to confirm.
const receiptSignals =
  /\b(receipt|invoice|subtotal|order\s*#?\d|order\s+confirmation|thank you for your (order|purchase|visit)|amount\s+(due|paid)|paid|tip|tax|grand\s+total|total)\b|收據|發票|訂單|消費明細|帳單|\$\s?\d|\d+\.\d{2}\b|NT\$|US\$/i;

export function looksLikeReceipt(text: string): boolean {
  return receiptSignals.test(text);
}

/**
 * Confirm + extract a receipt via Gemini. Returns null when the text is not a
 * receipt (a normal message, a place name, a question) or the model is
 * unavailable — so a false positive from the heuristic gate is harmless.
 */
export async function extractReceipt(
  text: string,
  gemini: GeminiCaller = defaultGeminiText,
): Promise<ExtractedReceipt | null> {
  const prompt = `Decide if this text message is a PURCHASE RECEIPT or an order / payment confirmation (from a restaurant, cafe, bar, shop, etc.). A normal chat message, a question, or a bare place name is NOT a receipt.

If it IS a receipt, extract:
- "merchant": the business/venue name on the receipt (keep its original language).
- "total": the total amount with currency if shown (e.g. "$24.50"), else null.
- "date": the purchase date if shown, else null.

Return STRICT JSON only, no markdown:
{"is_receipt": boolean, "merchant": string|null, "total": string|null, "date": string|null}

Text:
${text}`;
  let raw: string;
  try {
    raw = await gemini(prompt);
  } catch (error) {
    console.error("[sendblue] extractReceipt gemini error", error);
    return null;
  }
  const parsed = parseReplyJson(raw) as {
    is_receipt?: unknown;
    merchant?: unknown;
    total?: unknown;
    date?: unknown;
  } | null;
  if (!parsed || parsed.is_receipt !== true) return null;
  const merchant = typeof parsed.merchant === "string" ? parsed.merchant.trim() : "";
  if (!merchant) return null;
  const total = typeof parsed.total === "string" && parsed.total.trim() ? parsed.total.trim() : undefined;
  const date = typeof parsed.date === "string" && parsed.date.trim() ? parsed.date.trim() : undefined;
  return { merchant, total, date };
}

export function formatReceiptReply(receipt: ExtractedReceipt, count: number, chinese: boolean): string {
  const amount = receipt.total ? (chinese ? `（${receipt.total}）` : ` (${receipt.total})`) : "";
  return chinese
    ? `✓ 已記錄你在 ${receipt.merchant}${amount} 的訪問 — 這是一筆驗證訪問,你目前有 ${count} 筆。要留評論嗎?`
    : `✓ Logged your visit to ${receipt.merchant}${amount} — that's a verified visit. You have ${count} now. Want to leave a review?`;
}

export async function defaultGeminiText(prompt: string): Promise<string> {
  const apiKey = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_GEMINI_API_KEY;
  if (!apiKey) throw new Error("Missing GEMINI_API_KEY");
  const model = process.env.SAVE_MAAT_GEMINI_MODEL ?? defaultGeminiModel;
  const url = `${geminiEndpointBase}/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        // These tasks (venue extraction, recall routing, phrasing) are simple
        // structured outputs — deep reasoning adds ~2s/call for no quality gain.
        // Disabling the thinking budget cuts each call ~2.8s -> ~0.9s (measured).
        thinkingConfig: { thinkingBudget: 0 },
        maxOutputTokens: 1024,
      },
    }),
  });
  if (!response.ok) throw new Error(`Gemini request failed: ${response.status}`);
  const body = (await response.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const candidate = body.candidates?.[0];
  return candidate?.content?.parts?.map((part) => part.text ?? "").join("\n").trim() ?? "";
}

export type SendblueFetch = typeof fetch;

/**
 * Minimal Sendblue API client. sendMessage posts to the documented
 * send-message endpoint. fetch is injectable for tests.
 */
export class SendblueClient {
  private readonly apiKeyId: string;
  private readonly apiSecret: string;
  private readonly fromNumber: string | undefined;
  private readonly fetchImpl: SendblueFetch;
  private readonly endpoint: string;

  private readonly markReadEndpoint: string;
  private readonly typingEndpoint: string;

  constructor(options?: {
    apiKeyId?: string;
    apiSecret?: string;
    fromNumber?: string;
    fetchImpl?: SendblueFetch;
    endpoint?: string;
    markReadEndpoint?: string;
    typingEndpoint?: string;
  }) {
    this.apiKeyId = options?.apiKeyId ?? requireEnv("SENDBLUE_API_KEY_ID");
    this.apiSecret = options?.apiSecret ?? requireEnv("SENDBLUE_API_SECRET");
    // OPTIONAL: the Sendblue line to send FROM. Replying to an inbound message
    // doesn't need it (Sendblue infers the line); only cold outbound sends do.
    // Include it only when set so a missing env never breaks the reply path.
    this.fromNumber = options?.fromNumber ?? process.env.SENDBLUE_FROM_NUMBER ?? undefined;
    this.fetchImpl = options?.fetchImpl ?? fetch;
    this.endpoint = options?.endpoint ?? "https://api.sendblue.co/api/send-message";
    this.markReadEndpoint = options?.markReadEndpoint ?? "https://api.sendblue.co/api/mark-read";
    this.typingEndpoint = options?.typingEndpoint ?? "https://api.sendblue.co/api/send-typing-indicator";
  }

  private authHeaders(): Record<string, string> {
    return {
      "content-type": "application/json",
      "sb-api-key-id": this.apiKeyId,
      "sb-api-secret-key": this.apiSecret,
    };
  }

  async sendMessage(toNumber: string, content: string): Promise<string> {
    const payload: Record<string, string> = { number: toNumber, content };
    if (this.fromNumber) payload.from_number = this.fromNumber;
    const response = await this.fetchImpl(this.endpoint, {
      method: "POST",
      headers: this.authHeaders(),
      body: JSON.stringify(payload),
    });
    const body = await response.text().catch(() => "");
    if (!response.ok) {
      throw new Error(`Sendblue send-message failed: ${response.status} ${body.slice(0, 400)}`);
    }
    return body;
  }

  /**
   * Mark the user's inbound message as read (blue receipt). Best-effort: both
   * mark-read and typing-indicator require from_number per the Sendblue
   * dashboard, so they no-op when it's unset and never throw into the caller.
   */
  async markRead(toNumber: string): Promise<void> {
    await this.bestEffortPost(this.markReadEndpoint, toNumber, "mark-read");
  }

  /** Show a typing indicator to the user while we fetch + extract. Best-effort. */
  async sendTypingIndicator(toNumber: string): Promise<void> {
    await this.bestEffortPost(this.typingEndpoint, toNumber, "send-typing-indicator");
  }

  private async bestEffortPost(endpoint: string, toNumber: string, label: string): Promise<void> {
    if (!this.fromNumber) {
      console.log(`[sendblue] ${label} skipped (no from_number configured)`);
      return;
    }
    try {
      const response = await this.fetchImpl(endpoint, {
        method: "POST",
        headers: this.authHeaders(),
        body: JSON.stringify({ from_number: this.fromNumber, number: toNumber }),
      });
      if (!response.ok) {
        const body = await response.text().catch(() => "");
        console.warn(`[sendblue] ${label} failed: ${response.status} ${body.slice(0, 200)}`);
      }
    } catch (error) {
      console.warn(`[sendblue] ${label} error`, error);
    }
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

const urlPattern = /https?:\/\/[^\s<>"')]+/i;

export function firstUrlInText(text: string): string | undefined {
  const match = text.match(urlPattern);
  return match ? match[0].replace(/[.,!?]+$/, "") : undefined;
}

const categoryEmoji: Record<string, string> = {
  restaurant: "🍽️",
  cafe: "☕",
  coffee: "☕",
  bar: "🍸",
  rooftop: "🍸",
  hotel: "🏨",
  resort: "🏨",
  beach: "🏖️",
  museum: "🏛️",
  park: "🌳",
};

function emojiForCategory(category?: string): string {
  if (!category) return "📍";
  const lower = category.toLowerCase();
  for (const [key, emoji] of Object.entries(categoryEmoji)) {
    if (lower.includes(key)) return emoji;
  }
  return "📍";
}

const noUrlReply = "Send me an Instagram/TikTok link and I'll find the place 🗺️";
const noVenueReply =
  "Couldn't find a clear place in that one — try one with the spot named in the caption.";
const emptyListReply =
  "You haven't saved any places yet — send me an Instagram/TikTok link! / 你還沒存任何地點，傳個 IG/TikTok 連結給我！";

export function formatVenueReply(venue: ExtractedVenue): string {
  const emoji = emojiForCategory(venue.category);
  const where = venue.area ? `${venue.name} in ${venue.area}` : venue.name;
  const second = venue.category ? `\n${venue.category}` : "";
  return `Found ${where} ${emoji}${second}`;
}

/**
 * Heuristic: does the inbound text look like it's (primarily) Chinese? Used to
 * localize confirmations/lists. Any CJK ideograph present => reply in 繁中.
 */
export function looksChinese(text: string): boolean {
  return /[一-鿿]/.test(text);
}

// "Show me my saved places" intents, English + 中文. Matched as case-insensitive
// substrings so "show me my places" / "what have I saved?" still trigger.
const listIntentPhrases = [
  "what have i saved",
  "my places",
  "my saved",
  "saved places",
  "list",
  "我存了哪些",
  "存了哪些",
  "我的地點",
  "存了什麼",
  "我存過",
  "清單",
];

export function isListIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  return listIntentPhrases.some((phrase) => lower.includes(phrase));
}

// "Recommend somewhere" intents, English + 中文. Matched as case-insensitive
// substrings. "附近" doubles as both a recommend trigger and an area-ish hint.
const recommendIntentPhrases = [
  "recommend",
  "where should i go",
  "where to",
  "what should i",
  "somewhere to",
  "suggest",
  "推薦",
  "去哪",
  "要去哪",
  "吃什麼",
  "附近",
];

export function isRecommendIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  return recommendIntentPhrases.some((phrase) => lower.includes(phrase));
}

// "Order this for me" intents, English + 中文. Drives an SLL-R order (a real
// transaction), distinct from save/recall/recommend. Kept narrow to avoid
// false positives (e.g. "in order to").
const orderIntentPhrases = ["幫我點", "幫我買", "點餐", "點一", "下單", "buy me", "get me a"];
export function isOrderIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  if (lower.startsWith("order")) return true;
  return orderIntentPhrases.some((phrase) => lower.includes(phrase));
}

// Strip the order keyword so the rest is the item intent for SLL-R.
export function orderQuery(text: string): string {
  const stripped = text
    .trim()
    .replace(/^order[:\s]+/i, "")
    .replace(/^(下單|點餐|幫我點|幫我買|buy me|get me a)[:\s]*/i, "")
    .trim();
  return stripped || text.trim();
}

// "I'm in <area>" — sets the per-number location used for nearby orders.
const locationIntentPhrases = ["i'm in ", "i am in ", "im in ", "area:", "set area", "my area", "我在", "我人在"];
export function isLocationIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  return locationIntentPhrases.some((phrase) => lower.includes(phrase));
}
export function parseLocationQuery(text: string): string {
  const stripped = text
    .trim()
    .replace(/^(i'?m in|i am in|im in|set area|my area is|my area|area)[:\s]+/i, "")
    .replace(/^(我人在|我在)[:\s]*/, "")
    .trim();
  return stripped || text.trim();
}

// Geocode an area string → coordinates (Google Geocoding API; GOOGLE_PLACES_API_KEY
// works for it). Injectable so tests run offline.
export type Geocoder = (area: string) => Promise<StoredLocation | null>;
export async function defaultGeocode(area: string): Promise<StoredLocation | null> {
  const key = process.env.GOOGLE_PLACES_API_KEY ?? process.env.GOOGLE_GEOCODING_API_KEY;
  const query = area.trim();
  if (!key || !query) return null;
  const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(query)}&key=${key}`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const body = (await res.json()) as {
      results?: Array<{ formatted_address?: string; geometry?: { location?: { lat?: number; lng?: number } } }>;
    };
    const loc = body.results?.[0]?.geometry?.location;
    if (!loc || typeof loc.lat !== "number" || typeof loc.lng !== "number") return null;
    return { label: body.results?.[0]?.formatted_address ?? query, lat: loc.lat, lng: loc.lng };
  } catch {
    return null;
  }
}

/**
 * Detect which of the user's OWN saved areas the inbound text refers to.
 *
 * Location-via-text: a text bot can't auto-GPS, so instead of geocoding we match
 * the user's distinct saved area strings against the message as case-insensitive
 * substrings, longest match winning. "I'm in LA" matches a saved "LA"; "near
 * West Hollywood" matches "West Hollywood". Returns the stored area string
 * (original casing) so it round-trips back into the area filter + reply copy.
 */
export function detectArea(text: string, savedAreas: string[]): string | undefined {
  const folded = foldText(text);
  let best: string | undefined;
  for (const area of savedAreas) {
    const trimmed = area.trim();
    if (!trimmed) continue;
    if (folded.includes(foldText(trimmed))) {
      if (!best || trimmed.length > best.length) best = trimmed;
    }
  }
  return best;
}

/**
 * Is the text basically *just* an area mention (so we should list that area
 * rather than fall through to the hint)? True when a saved area was detected and
 * the remaining text is short filler ("in LA", "台北", "near West Hollywood").
 */
export function isBareAreaMention(text: string, detectedArea: string | undefined): boolean {
  if (!detectedArea) return false;
  const stripped = foldText(text).replace(foldText(detectedArea), " ");
  // Drop common location filler so "i'm in LA" counts as bare.
  const residual = stripped
    .replace(/\b(i'?m|im|in|near|at|around|the|me|to|go)\b/g, " ")
    .replace(/在|附近|有什麼|有什么/g, " ")
    .replace(/[^a-z0-9一-鿿]+/g, "")
    .trim();
  return residual.length === 0;
}

/**
 * Confirmation reply after a place is saved, with the running count.
 * Localizes to 繁中 when the inbound looked Chinese.
 */
export function formatSaveReply(venue: ExtractedVenue, count: number, chinese: boolean): string {
  if (chinese) {
    const where = venue.area ? `${venue.name}（${venue.area}）` : venue.name;
    return `已存 ${where} ✓\n你已存 ${count} 個地點，傳「我存了哪些」查看。`;
  }
  const where = venue.area ? `${venue.name} in ${venue.area}` : venue.name;
  const plural = count === 1 ? "" : "s";
  return `Saved ${where} ✓\nYou've saved ${count} place${plural} — text "my places" to see them.`;
}

/** Short numbered list of saved places, capped, localized. */
export function formatPlaceList(places: SavedPlace[], chinese: boolean, cap = 15): string {
  if (places.length === 0) return emptyListReply;
  const shown = places.slice(0, cap);
  const lines = shown.map((place, index) => {
    const where = place.area ? `${place.name} — ${place.area}` : place.name;
    return `${index + 1}. ${where}`;
  });
  const header = chinese ? "你存過的地點：" : "Your saved places:";
  let body = `${header}\n${lines.join("\n")}`;
  if (places.length > shown.length) {
    const more = places.length - shown.length;
    body += chinese ? `\n…還有 ${more} 個` : `\n…and ${more} more`;
  }
  return body;
}

/**
 * Warm one-place recommendation, localized. Drops the "from a … clip" tail when
 * category/source are missing. Area is included when known.
 */
export function formatRecommendReply(place: SavedPlace, chinese: boolean): string {
  const emoji = emojiForCategory(place.category);
  if (chinese) {
    const where = place.area ? `${place.name}（${place.area}）` : place.name;
    return `去 ${where} ${emoji} — 你存過的。`;
  }
  const where = place.area ? `${place.name} in ${place.area}` : place.name;
  const tail = place.category ? ` — you saved it from a ${place.category} clip.` : ".";
  return `Go to ${where} ${emoji}${tail}`;
}

/** Numbered list of saved places in a specific area, capped, localized. */
export function formatAreaList(
  places: SavedPlace[],
  area: string,
  chinese: boolean,
  cap = 15,
): string {
  if (places.length === 0) return formatNoAreaMatch(area, chinese);
  const shown = places.slice(0, cap);
  const lines = shown.map((place, index) => `${index + 1}. ${place.name}`);
  const header = chinese ? `你在 ${area} 存的：` : `Your saved places in ${area}:`;
  let body = `${header}\n${lines.join("\n")}`;
  if (places.length > shown.length) {
    const more = places.length - shown.length;
    body += chinese ? `\n…還有 ${more} 個` : `\n…and ${more} more`;
  }
  return body;
}

/** "You haven't saved anything in {area} yet" reply, localized. */
export function formatNoAreaMatch(area: string, chinese: boolean): string {
  return chinese
    ? `你還沒在 ${area} 存過 — 傳個那邊的連結給我！`
    : `You haven't saved anything in ${area} yet — send me a link from there!`;
}

/**
 * Choose one place to recommend from a most-recent-first list: pick randomly
 * among the top few so repeated asks vary, biased toward recent saves. Returns
 * undefined for an empty list.
 */
export function pickRecommendation(places: SavedPlace[]): SavedPlace | undefined {
  if (places.length === 0) return undefined;
  const top = places.slice(0, Math.min(3, places.length));
  return top[Math.floor(Math.random() * top.length)];
}

function parseReplyJson(text: string): { reply?: unknown } | null {
  const tryParse = (value: string): { reply?: unknown } | null => {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (parsed && typeof parsed === "object") return parsed as { reply?: unknown };
    } catch {
      // fall through
    }
    return null;
  };
  const direct = tryParse(text.trim());
  if (direct) return direct;
  const match = text.match(/\{[\s\S]*\}/);
  return match ? tryParse(match[0]) : null;
}

/** A place found via Google Places discovery (NOT one the user saved). */
export type DiscoveredPlace = {
  name: string;
  address?: string;
  rating?: number;
  category?: string;
};

/** Injectable Google Places text search (so tests don't hit the network). */
export type PlacesSearch = (query: string) => Promise<DiscoveredPlace[]>;

/**
 * Google Places text search. `query` is a natural phrase like "coffee in Santa
 * Monica". Uses GOOGLE_PLACES_API_KEY (already provisioned on the backend).
 */
export async function defaultPlacesSearch(query: string): Promise<DiscoveredPlace[]> {
  const apiKey = process.env.GOOGLE_PLACES_API_KEY;
  if (!apiKey) throw new Error("Missing GOOGLE_PLACES_API_KEY");
  const response = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
        "places.displayName,places.formattedAddress,places.rating,places.primaryType",
    },
    body: JSON.stringify({ textQuery: query, maxResultCount: 8 }),
  });
  if (!response.ok) throw new Error(`Places searchText failed: ${response.status}`);
  const body = (await response.json()) as {
    places?: {
      displayName?: { text?: string };
      formattedAddress?: string;
      rating?: number;
      primaryType?: string;
    }[];
  };
  return (body.places ?? [])
    .map((p) => ({
      name: p.displayName?.text ?? "",
      address: p.formattedAddress,
      rating: typeof p.rating === "number" ? p.rating : undefined,
      category: p.primaryType?.replace(/_/g, " "),
    }))
    .filter((p) => p.name.length > 0);
}

/**
 * Per-phone conversation memory. Two things:
 *  - `pendingQuery`: when we ask "where are you?", the search we'll resume once
 *    they reply with a location (so a bare "Tustin" continues the right search).
 *  - `lastPlaces`: the places we most recently recommended/discovered, so a
 *    follow-up ("what's their best coffee?", "address?", "save it") can be
 *    answered about the place we just named instead of falling back to saved.
 */
export type ConversationState = {
  pendingQuery?: string;
  lastPlaces?: DiscoveredPlace[];
  /** The single place we actually recommended (what "it/their/that place" means). */
  lastRecommended?: DiscoveredPlace;
  /** The last location the user gave — reused for "something else" follow-ups. */
  lastArea?: string;
  /** Names already recommended this conversation — excluded so "something else" varies. */
  shownNames?: string[];
  at: number;
};
export interface ConversationStore {
  get(phone: string): ConversationState | undefined;
  setPending(phone: string, query: string): void;
  setPlaces(phone: string, places: DiscoveredPlace[]): void;
  /** Remember THE place we recommended (for "what's their…?" follow-ups). */
  setRecommended(phone: string, place: DiscoveredPlace): void;
  /** Remember the user's last given location, for follow-up recommendations. */
  setArea(phone: string, area: string): void;
  /** Append a recommended place name (so we don't repeat it next time). */
  addShown(phone: string, name: string): void;
  /** Clear the pending location only; keep lastPlaces/lastArea for follow-ups. */
  clearPending(phone: string): void;
}

const CONVERSATION_TTL_MS = 10 * 60 * 1000;

class InMemoryConversationStore implements ConversationStore {
  private readonly map = new Map<string, ConversationState>();
  get(phone: string): ConversationState | undefined {
    const v = this.map.get(phone);
    if (!v) return undefined;
    if (Date.now() - v.at > CONVERSATION_TTL_MS) {
      this.map.delete(phone);
      return undefined;
    }
    return v;
  }
  private merge(phone: string, patch: Partial<ConversationState>): void {
    const prev = this.get(phone) ?? { at: Date.now() };
    this.map.set(phone, { ...prev, ...patch, at: Date.now() });
  }
  setPending(phone: string, query: string): void {
    this.merge(phone, { pendingQuery: query });
  }
  setPlaces(phone: string, places: DiscoveredPlace[]): void {
    this.merge(phone, { lastPlaces: places.slice(0, 5) });
  }
  setRecommended(phone: string, place: DiscoveredPlace): void {
    this.merge(phone, { lastRecommended: place });
  }
  setArea(phone: string, area: string): void {
    this.merge(phone, { lastArea: area });
  }
  addShown(phone: string, name: string): void {
    const prev = this.get(phone);
    const shownNames = [...(prev?.shownNames ?? []), name].slice(-20);
    this.merge(phone, { shownNames });
  }
  clearPending(phone: string): void {
    const prev = this.get(phone);
    if (prev) this.map.set(phone, { ...prev, pendingQuery: undefined, at: Date.now() });
  }
}

/** Process-wide conversation memory (single Railway instance, 10-min TTL). */
export const defaultConversationStore: ConversationStore = new InMemoryConversationStore();

/**
 * The agentic decision for a no-URL message: either answer from the user's saved
 * places ("reply"), or go DISCOVER new places near a location via Google
 * ("search"). `area` is null when the user wants nearby but gave no location.
 */
export type RecallDecision =
  | { kind: "reply"; reply: string }
  | { kind: "search"; query: string; area: string | null }
  // The user stated WHERE they are with no specific request — remember it.
  | { kind: "location"; area: string };

/**
 * Agentic router: hand the user's message + their saved places to the LLM and
 * let it decide whether it can answer from what they've saved (grounded, never
 * inventing one) OR whether it should search Google for NEW nearby places.
 * Returns null when there's nothing to work with or the model is unavailable.
 */
export async function decideRecall(
  text: string,
  places: SavedPlace[],
  gemini: GeminiCaller = defaultGeminiText,
  chinese = false,
  convo?: {
    pendingQuery?: string;
    lastPlaces?: DiscoveredPlace[];
    lastArea?: string;
    lastRecommended?: DiscoveredPlace;
  },
): Promise<RecallDecision | null> {
  const pendingQuery = convo?.pendingQuery;
  const lastPlaces = convo?.lastPlaces ?? [];
  const lastArea = convo?.lastArea;
  const lastRecommended = convo?.lastRecommended;
  const context =
    places.length > 0
      ? places
          .slice(0, 50)
          .map((p, i) => {
            const bits = [p.name];
            if (p.area) bits.push(`area: ${p.area}`);
            if (p.category) bits.push(p.category);
            return `${i + 1}. ${bits.join(" — ")}`;
          })
          .join("\n")
      : "(none saved yet)";
  const lang = chinese ? "繁體中文" : "the same language the user wrote in";
  // Conversation memory: if we just asked the user for their location (to run a
  // pending discovery), a bare "Tustin" / "92782" / "i'm in Culver City" reply
  // must RESUME that search, not be treated as a fresh, locationless message.
  const pendingBlock = pendingQuery
    ? `\nLOCATION FOLLOW-UP: You just asked the user where they are, because they want to find: "${pendingQuery}". If their message below is a location (city, neighborhood, ZIP code, or address) — even just a bare place name — return {"search":{"query":"${pendingQuery}","area":"<that location>"}}. Only ignore this if they clearly changed the subject.\n`
    : "";
  const placeFacts = (p: DiscoveredPlace): string => {
    const bits = [p.name];
    if (typeof p.rating === "number") bits.push(`${p.rating}★`);
    if (p.address) bits.push(p.address);
    return bits.join(" — ");
  };
  const recentBlock =
    lastRecommended || lastPlaces.length > 0
      ? `\n${
          lastRecommended
            ? `THE PLACE YOU JUST RECOMMENDED is: ${placeFacts(lastRecommended)}. When the user says "it", "their", "that place", "their popular drink", etc., they mean THIS place — answer about THIS one, never silently switch to a different place.\n`
            : ""
        }${
          lastPlaces.length > 0
            ? `Other nearby options you mentioned: ${lastPlaces.map((p) => p.name).join(", ")}.\n`
            : ""
        }When they ask about the recommended place, answer with {"reply"} using ONLY its known data (name/rating/address). If they ask something you do NOT have (menu items, "popular drink", prices, hours), say honestly you don't have that detail about <that place>, then offer what you do have (rating/address) or to save it. NEVER make up details and NEVER answer about a different place than the one they asked about.\n`
      : "";
  const prompt = `You are SAV-E, a friend who remembers places the user saved from Instagram/TikTok and can also find NEW places nearby. Decide EXACTLY ONE action:

1. Answer from their saved places OR about a place you recently recommended (see below). Use ONLY known data — NEVER invent a place, menu, or detail. Return {"reply":"<message>"}.
2. Find NEW places nearby — when they want a recommendation for somewhere not yet known (e.g. "somewhere nearby", "anywhere else", "that one's too far", "find me a coffee place", "推薦附近的") AND a location is given or clearly known. Return {"search":{"query":"<2-4 word search like 'coffee' or 'ramen'>","area":"<the location, e.g. 'Santa Monica'>"}}.
3. They want something nearby but gave NO location yet. Return {"search":{"query":"<2-4 word search>","area":null}} — a null area signals we still need their location. Do NOT phrase this as a reply.
4. The message is ONLY a location (a bare address, city, neighborhood, or ZIP) with no request, AND there is no pending search to resume. Return {"location":{"area":"<that location>"}} — never just acknowledge it in a reply; this records where they are for next time.
${pendingBlock}${recentBlock}${
    lastArea
      ? `\nLAST KNOWN LOCATION: the user is already near "${lastArea}". For ANY nearby request — "recommend a boba place", "find me coffee", "something else", "anything closer", "what else" — REUSE this location: return {"search":{"query":"<what they want>","area":"${lastArea}"}}. Do NOT ask where they are again (do NOT return a null area) unless they give a new place or say they moved.\n`
      : ""
  }
Keep any reply to 1-3 short sentences (a text message), in ${lang}, at most one emoji.

The user's saved places:
${context}

The user just texted: "${text}"

Return STRICT JSON only, no markdown.`;
  let raw: string;
  try {
    raw = await gemini(prompt);
  } catch (error) {
    console.error("[sendblue] decideRecall gemini error", error);
    return null;
  }
  const parsed = parseRecallJson(raw);
  if (!parsed) return null;
  if (parsed.search && typeof parsed.search.query === "string" && parsed.search.query.trim()) {
    const area =
      typeof parsed.search.area === "string" && parsed.search.area.trim()
        ? parsed.search.area.trim()
        : null;
    return { kind: "search", query: parsed.search.query.trim(), area };
  }
  if (parsed.location && typeof parsed.location.area === "string" && parsed.location.area.trim()) {
    return { kind: "location", area: parsed.location.area.trim() };
  }
  if (typeof parsed.reply === "string" && parsed.reply.trim()) {
    return { kind: "reply", reply: parsed.reply.trim() };
  }
  return null;
}

type ParsedRecall = {
  reply?: unknown;
  search?: { query?: unknown; area?: unknown };
  location?: { area?: unknown };
};

function parseRecallJson(text: string): ParsedRecall | null {
  return parseReplyJson(text) as ParsedRecall | null;
}

const askLocationReplyEn =
  "Where are you right now? Drop me an area or address and I'll find a spot nearby 📍";
const askLocationReplyZh = "你現在在哪?給我一個地區或地址,我幫你找附近的 📍";

function askLocationReply(chinese: boolean): string {
  return chinese ? askLocationReplyZh : askLocationReplyEn;
}

function noDiscoveryReply(area: string, chinese: boolean): string {
  return chinese
    ? `我在 ${area} 附近沒找到適合的,換個地區或描述試試?`
    : `Couldn't find a good match near ${area} — try another area or be more specific?`;
}

/**
 * Pick the best discovery result the user hasn't already been shown: highest
 * rating among names not in `exclude` (case-insensitive). Falls back to the
 * highest-rated overall if everything was already shown (better to repeat than
 * to dead-end). Returns undefined only for an empty result set.
 */
export function pickBestPlace(
  found: DiscoveredPlace[],
  exclude: string[] = [],
): DiscoveredPlace | undefined {
  if (found.length === 0) return undefined;
  const seen = new Set(exclude.map((n) => n.toLowerCase()));
  const byRating = (a: DiscoveredPlace, b: DiscoveredPlace) => (b.rating ?? 0) - (a.rating ?? 0);
  const fresh = found.filter((p) => !seen.has(p.name.toLowerCase())).sort(byRating);
  if (fresh.length > 0) return fresh[0];
  return [...found].sort(byRating)[0];
}

/**
 * Phrase a single chosen place naturally via the LLM (grounded in its real
 * data), with a deterministic template fallback so a recommendation never fails
 * just because phrasing did.
 */
export async function phrasePlaceRec(
  place: DiscoveredPlace,
  area: string,
  gemini: GeminiCaller = defaultGeminiText,
  chinese = false,
): Promise<string> {
  const stars = place.rating ? ` ${place.rating}★` : "";
  const template = (): string =>
    chinese
      ? `${area}附近可以試試 ${place.name}${stars} 📍${place.address ? `\n${place.address}` : ""}`
      : `Near ${area}, try ${place.name}${stars} 📍${place.address ? `\n${place.address}` : ""}`;
  const lang = chinese ? "繁體中文" : "the same language the user wrote in";
  const facts = `${place.name}${place.rating ? ` (${place.rating}★)` : ""}${place.address ? ` — ${place.address}` : ""}`;
  const prompt = `Recommend this ONE place to the user near ${area}, warmly, in ${lang}, 1-2 short sentences, at most one emoji. Use ONLY these facts — do not invent anything (no menu, no hours):

${facts}

Return STRICT JSON only: {"reply": string}`;
  try {
    const raw = await gemini(prompt);
    const parsed = parseReplyJson(raw);
    const reply = parsed && typeof parsed.reply === "string" ? parsed.reply.trim() : "";
    return reply.length > 0 ? reply : template();
  } catch (error) {
    console.error("[sendblue] phrasePlaceRec gemini error", error);
    return template();
  }
}

// Defensive field extraction: Sendblue inbound payloads vary, so accept several
// common field names for the message text and the sender number.
function inboundText(body: Record<string, unknown>): string | undefined {
  for (const key of ["content", "body", "message", "text"]) {
    const value = body[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return undefined;
}

function inboundFrom(body: Record<string, unknown>): string | undefined {
  for (const key of ["from_number", "number", "from", "fromNumber"]) {
    const value = body[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return undefined;
}

// Reply only to inbound user messages. Ignore Sendblue status callbacks /
// outbound echoes (is_outbound true, or direction/type indicating outbound).
function isInboundMessage(body: Record<string, unknown>): boolean {
  if (body.is_outbound === true || body.isOutbound === true) return false;
  const direction = typeof body.direction === "string" ? body.direction.toLowerCase() : "";
  if (direction === "outbound" || direction === "sent") return false;
  const type = typeof body.type === "string" ? body.type.toLowerCase() : "";
  if (type.includes("status") || type.includes("delivered") || type.includes("callback")) {
    return false;
  }
  return true;
}

export type ProcessResult = {
  /** false => recognized but no reply should be sent (e.g. outbound/status event). */
  replied: boolean;
  reply?: string;
};

export type ProcessDeps = {
  fetchText?: FetchText;
  gemini?: GeminiCaller;
  /** Google Places search for nearby DISCOVERY. Defaults to defaultPlacesSearch. */
  placesSearch?: PlacesSearch;
  /** Conversation memory (pending location + last recommended places). Defaults to the module singleton. */
  conversation?: ConversationStore;
  /** Verified-visit memory: forwarded receipts → proof-of-visit. Omitted = receipts disabled. */
  receiptStore?: VerifiedVisitStore;
  client: Pick<SendblueClient, "sendMessage" | "markRead" | "sendTypingIndicator">;
  store: SendbluePlaceStore;
  /** Place an SLL-R order for this number; returns the reply, or null to fall
   *  through to the normal save/recall flow. Omitted in tests / when SLL-R is off. */
  order?: (query: string, fromNumber: string, location?: StoredLocation) => Promise<string | null>;
  /** Geocode an area the user texts ("I'm in X") → coordinates, stored per number. */
  geocode?: Geocoder;
};

/**
 * Deterministic recall used when the LLM is unavailable: detect an area from the
 * user's OWN saved areas (no GPS), then match a recommend / list intent. This is
 * the pre-agentic keyword path, kept as a graceful fallback.
 */
async function keywordRecallReply(
  text: string,
  from: string,
  chinese: boolean,
  store: SendbluePlaceStore,
): Promise<string> {
  let savedAreas: string[] = [];
  try {
    savedAreas = await store.distinctAreas(from);
  } catch (storeError) {
    console.error("[sendblue] store.distinctAreas error", storeError);
  }
  const area = detectArea(text, savedAreas);

  if (isRecommendIntent(text)) {
    let places: SavedPlace[];
    try {
      places = await store.list(from, area ? { area } : undefined);
    } catch (storeError) {
      console.error("[sendblue] store.list error", storeError);
      places = [];
    }
    const picked = pickRecommendation(places);
    console.log(`[sendblue] recommend intent area=${area ?? "(any)"} picked=${picked?.name ?? "(none)"}`);
    if (picked) return formatRecommendReply(picked, chinese);
    if (area) return formatNoAreaMatch(area, chinese);
    return emptyListReply;
  }

  if (isListIntent(text) || isBareAreaMention(text, area)) {
    let places: SavedPlace[];
    try {
      places = await store.list(from, area ? { area } : undefined);
    } catch (storeError) {
      console.error("[sendblue] store.list error", storeError);
      places = [];
    }
    console.log(`[sendblue] list intent for ${from} area=${area ?? "(any)"} count=${places.length}`);
    return area ? formatAreaList(places, area, chinese) : formatPlaceList(places, chinese);
  }

  console.log("[sendblue] no URL / no recommend / no list intent → hint");
  return noUrlReply;
}

/**
 * Core webhook logic, decoupled from http for testing: parse the inbound
 * payload, run the link -> caption -> venue pipeline, and reply via the
 * provided Sendblue client. Never throws for expected input shapes.
 */
export async function processSendblueInbound(
  body: Record<string, unknown>,
  deps: ProcessDeps,
): Promise<ProcessResult> {
  if (!isInboundMessage(body)) {
    console.log("[sendblue] ignored non-inbound event", JSON.stringify(body).slice(0, 160));
    return { replied: false };
  }

  const from = inboundFrom(body);
  const text = inboundText(body);
  if (!from || !text) {
    console.log(`[sendblue] inbound missing from/text from=${from ?? "?"} text=${(text ?? "").slice(0, 60)}`);
    return { replied: false };
  }
  console.log(`[sendblue] inbound from=${from} text=${text.slice(0, 120)}`);

  // Best-effort: show the user a blue read receipt + typing indicator while we
  // fetch + extract. Fire-and-forget (not awaited) so two Sendblue round-trips
  // don't sit on the critical path — the typing dots show DURING processing,
  // which is exactly when we want them. The client wraps its own errors.
  void deps.client.markRead(from);
  void deps.client.sendTypingIndicator(from);

  const chinese = looksChinese(text);
  let reply: string;
  try {
    const url = firstUrlInText(text);
    // Receipt → verified visit (proof-of-visit). Checked FIRST: a receipt's
    // "thank you for your order" text must not be mistaken for an order intent.
    // Cheap heuristic gate, then the LLM confirms; only fires when wired in.
    if (deps.receiptStore && deps.gemini && looksLikeReceipt(text)) {
      const receipt = await extractReceipt(text, deps.gemini);
      if (receipt) {
        let count = 0;
        try {
          count = await deps.receiptStore.save(from, {
            merchant: receipt.merchant,
            total: receipt.total,
            visitDate: receipt.date,
            raw: text,
          });
        } catch (storeError) {
          console.error("[sendblue] receipt save error", storeError);
        }
        console.log(
          `[sendblue] receipt merchant="${receipt.merchant}" total="${receipt.total ?? ""}" count=${count}`,
        );
        reply = formatReceiptReply(receipt, count, chinese);
        await deps.client.sendMessage(from, reply);
        return { replied: true, reply };
      }
    }
    if (deps.geocode && !url && isLocationIntent(text)) {
      // Location set: "I'm in X" → geocode → remember per number for nearby orders.
      const loc = await deps.geocode(parseLocationQuery(text));
      if (loc) {
        await deps.store.setLocation(from, loc);
        reply = `📍 Got it — I'll use ${loc.label} for nearby orders.`;
      } else {
        reply = 'I couldn\'t find that area. Try a city/neighborhood, e.g. "I\'m in Santa Monica".';
      }
      await deps.client.sendMessage(from, reply);
      return { replied: true, reply };
    }
    if (deps.order && !url && isOrderIntent(text)) {
      // Order flow: needs the user's area to pick the nearest merchant.
      const loc = await deps.store.getLocation(from);
      if (!loc) {
        reply = '📍 What area are you in? Tell me e.g. "I\'m in Miami Beach" and I\'ll order from the nearest spot.';
        await deps.client.sendMessage(from, reply);
        return { replied: true, reply };
      }
      const orderReply = await deps.order(orderQuery(text), from, loc);
      if (orderReply) {
        await deps.client.sendMessage(from, orderReply);
        console.log(`[sendblue] order reply for ${from} near ${loc.label}`);
        return { replied: true, reply: orderReply };
      }
    }
    if (url) {
      // Save flow: link → caption → venue → remember it for this number.
      const { caption } = await fetchLinkCaption(url, deps.fetchText);
      console.log(`[sendblue] url=${url} captionLen=${caption.length}`);
      const venue = caption ? await extractVenueFromCaption(caption, deps.gemini) : null;
      console.log(`[sendblue] venue=${venue ? JSON.stringify(venue) : "(none)"}`);
      if (venue) {
        let count: number;
        try {
          count = await deps.store.save(from, venue, url);
        } catch (storeError) {
          // Degrade gracefully: still confirm the find even if persistence fails.
          console.error("[sendblue] store.save error", storeError);
          reply = formatVenueReply(venue);
          await deps.client.sendMessage(from, reply);
          console.log(`[sendblue] sent to ${from} (save failed, no count)`);
          return { replied: true, reply };
        }
        console.log(`[sendblue] saved place for ${from} count=${count}`);
        reply = formatSaveReply(venue, count, chinese);
      } else {
        reply = noVenueReply;
      }
    } else if (deps.gemini) {
      // No URL + an LLM is available: AGENTIC router. The model decides whether
      // to answer from the user's saved places (grounded, never invents one) OR
      // to DISCOVER new places nearby via Google Places. Falls back to
      // deterministic keyword intents if the model yields nothing usable.
      let places: SavedPlace[] = [];
      try {
        places = await deps.store.list(from, { limit: 50 });
      } catch (storeError) {
        console.error("[sendblue] store.list error", storeError);
      }
      // Conversation memory: pass the pending location query (so a bare "Tustin"
      // resumes the right search) AND the last places we recommended (so a
      // follow-up like "what's their best coffee?" is answered about that place).
      const convoStore = deps.conversation ?? defaultConversationStore;
      const convo = convoStore.get(from);
      const decision = await decideRecall(text, places, deps.gemini, chinese, {
        pendingQuery: convo?.pendingQuery,
        lastPlaces: convo?.lastPlaces,
        lastArea: convo?.lastArea,
        lastRecommended: convo?.lastRecommended,
      });
      if (!decision) {
        convoStore.clearPending(from);
        console.log(`[sendblue] agentic empty → keyword fallback for ${from}`);
        reply = await keywordRecallReply(text, from, chinese, deps.store);
      } else if (decision.kind === "location") {
        // Pure location, nothing pending → store it and ask what they want,
        // instead of a hollow "I'll remember" that loses the area.
        convoStore.setArea(from, decision.area);
        console.log(`[sendblue] location set for ${from} area="${decision.area}"`);
        reply = chinese
          ? `📍 收到,你在 ${decision.area} 附近 — 要找什麼?(咖啡、吃的、酒吧…)`
          : `📍 Got it, you're near ${decision.area} — what are you looking for? (coffee, food, a bar…)`;
      } else if (decision.kind === "reply") {
        convoStore.clearPending(from);
        console.log(
          `[sendblue] agentic reply for ${from} placeCount=${places.length} recentPlaces=${convo?.lastPlaces?.length ?? 0}`,
        );
        reply = decision.reply;
      } else if (!(decision.area ?? convo?.lastArea)) {
        // Wants nearby but we have NO location at all → remember query, ask where.
        convoStore.setPending(from, decision.query);
        console.log(`[sendblue] discovery wants location from ${from} (pending="${decision.query}")`);
        reply = askLocationReply(chinese);
      } else {
        // Discovery: search near the given area, OR — deterministically — the
        // last location we already know, so we never re-ask once we have it.
        const area = decision.area ?? convo!.lastArea!;
        convoStore.clearPending(from);
        const search = deps.placesSearch ?? defaultPlacesSearch;
        let found: DiscoveredPlace[] = [];
        try {
          found = await search(`${decision.query} in ${area}`);
        } catch (searchError) {
          console.error("[sendblue] places search error", searchError);
        }
        // Skip places we've already recommended this conversation so a
        // "something else" actually returns something else.
        const picked = pickBestPlace(found, convo?.shownNames ?? []);
        console.log(
          `[sendblue] discovery query="${decision.query}" area="${area}" results=${found.length} picked="${picked?.name ?? "(none)"}"` +
            (convo?.pendingQuery ? " (resumed pending)" : "") +
            (!decision.area && convo?.lastArea ? " (reused area)" : ""),
        );
        if (picked) {
          // Remember location + what we recommended for follow-ups / "something else".
          convoStore.setArea(from, area);
          convoStore.setPlaces(from, found);
          convoStore.setRecommended(from, picked);
          convoStore.addShown(from, picked.name);
          reply = await phrasePlaceRec(picked, area, deps.gemini, chinese);
        } else {
          reply = noDiscoveryReply(area, chinese);
        }
      }
    } else {
      // No LLM injected (e.g. tests): deterministic keyword recall.
      reply = await keywordRecallReply(text, from, chinese, deps.store);
    }
  } catch (error) {
    // Spike: degrade gracefully, never bubble up to the webhook.
    console.error("[sendblue] inbound processing error", error);
    reply = noVenueReply;
  }

  await deps.client.sendMessage(from, reply);
  console.log(`[sendblue] sent to ${from}`);
  return { replied: true, reply };
}

/**
 * Optional HMAC signature verification. If SENDBLUE_SIGNING_SECRET is not set,
 * verification is skipped (spike). Returns true when there is nothing to verify
 * or when the signature matches.
 */
export function verifySignature(rawBody: string, signature: string | undefined): boolean {
  const secret = process.env.SENDBLUE_SIGNING_SECRET?.trim();
  if (!secret) return true; // spike: signing not configured
  if (!signature) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
