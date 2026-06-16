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
import type { ReviewStore } from "./sendblueReviewStore.js";

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

function compactPlaceText(value: string): string {
  return foldText(value).replace(/[^\p{L}\p{N}]+/gu, "");
}

function findSavedPlaceMatch(query: string, places: SavedPlace[]): SavedPlace | undefined {
  const needle = compactPlaceText(query);
  if (!needle) return undefined;
  return places
    .filter((place) => {
      const haystack = compactPlaceText(place.name);
      if (!haystack) return false;
      return haystack.includes(needle) || needle.includes(haystack);
    })
    .sort((a, b) => b.name.length - a.name.length)[0];
}

function savedPlaceLookupQuery(place: SavedPlace): string {
  return [place.name, place.area].filter(Boolean).join(" ").trim();
}

function savedPlaceAreaFallback(place: SavedPlace, chinese: boolean): string {
  // Google Places textSearch can miss a place (e.g. a Japanese-named shop in
  // Taiwan), but a Google Maps SEARCH link still resolves it on tap - strictly
  // more useful than asking the user for a map link. Add the post they saved it
  // from when we have it.
  const mapsSearch = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
    [place.name, place.area].filter(Boolean).join(" ").trim(),
  )}`;
  const area = place.area ? (chinese ? `（${place.area}）` : ` in ${place.area}`) : "";
  const src = place.sourceUrl
    ? chinese
      ? `\n你存它的貼文：${place.sourceUrl}`
      : `\nWhere you saved it: ${place.sourceUrl}`
    : "";
  return chinese
    ? `「${place.name}」${area}：我這邊查不到精確地址，在地圖上搜：\n${mapsSearch}${src}`
    : `"${place.name}"${area}: I don't have an exact address; find it on the map:\n${mapsSearch}${src}`;
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
  /\breceipt\b|\binvoice\b|\bsubtotal\b|\border\s*#?\s*\d+|\border\s+confirmation\b|thank you for your (order|purchase|visit)|\bamount\s+(due|paid)\b|\bpaid\b|\bgrand\s+total\b|\btotal\b|收據|發票|訂單|消費明細|帳單|\$\s?\d|\d+\.\d{2}\b|NT\$|US\$/i;

export function looksLikeReceipt(text: string): boolean {
  return receiptSignals.test(text);
}

// Known receipt / point-of-sale providers. A forwarded link from one of these is
// a RECEIPT, not a social place link — fetch + extract it as a verified visit
// instead of saving the venue. (Toast, Square, Clover, etc.)
const receiptLinkHosts =
  /(^|\.)(toasttab\.com|squareup\.com|square\.com|clover\.com|stripe\.com|paypal\.com|venmo\.com|grubhub\.com|doordash\.com|ubereats\.com|seamless\.com|olo\.com|chownow\.com)$/i;

// Cheap gate for the "reply to a review prompt" fallback: a leading 1-5 rating,
// a star mention, or clear sentiment. Avoids an LLM call on every message in the
// 30-min window after a visit.
const reviewSignals =
  /^\s*[1-5]\b|\b[1-5]\s*(?:stars?|\/\s*5)\b|\bstars?\b|\b(amazing|great|good|bad|terrible|loved|love it|delicious|awful|meh|solid|fire|mid|best|worst|tasty|overrated|underrated)\b|好吃|難吃|推|雷|星/i;

export function looksLikeReview(text: string): boolean {
  return reviewSignals.test(text);
}

export function isReceiptLink(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    if (receiptLinkHosts.test(host)) return true;
  } catch {
    // not a parseable URL
  }
  return /\/receipts?\//i.test(url);
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
  const prompt = `Decide if this text is a PURCHASE RECEIPT, an order confirmation, or a receipt page (from a restaurant, cafe, bar, shop, etc.). Signals: "receipt", "order #", "your receipt for X", a merchant + total, or text fetched from a receipt link (Toast/Square/etc.). A normal chat message, a question, or a bare place name is NOT a receipt.

If it IS a receipt/order, extract (a TOTAL is OPTIONAL — an order confirmation that names the merchant still counts):
- "merchant": the business/venue name (keep its original language). REQUIRED.
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
    ? `✓ 已記錄你在 ${receipt.merchant}${amount} 的訪問 — 這是一筆驗證訪問,你目前有 ${count} 筆。要留個評論嗎?(回覆 1-5 星 + 一句話)`
    : `✓ Logged your visit to ${receipt.merchant}${amount} — that's a verified visit. You have ${count} now. Want to leave a review? (reply 1-5 stars + a line)`;
}

// --- Receipt-gated reviews -------------------------------------------------
// After a receipt is logged the bot asks "want to review?"; the user's next
// message is read here as a rating + optional text for that exact merchant.

export type ExtractedReview = { rating?: number; text?: string };

/**
 * Read the user's reply to "want to review {merchant}?" as a review. Returns
 * null when they're NOT reviewing (declining or changing the subject) so the
 * caller falls through to the normal flow. The review is receipt-gated by
 * construction: we only ask after logging a verified visit.
 */
export async function extractReview(
  text: string,
  merchant: string,
  gemini: GeminiCaller = defaultGeminiText,
): Promise<ExtractedReview | null> {
  const prompt = `The user was just asked to review "${merchant}" (a place they have a receipt for). Read their message below.

If it IS a review (a rating and/or an opinion about ${merchant}), extract:
- "rating": 1-5 integer if they gave/implied one (5=loved it, 1=terrible), else null.
- "text": their own words about the place, else null.
If they are declining or changing the subject (e.g. "no", "later", "recommend something else"), it is NOT a review.

Return STRICT JSON only: {"is_review": boolean, "rating": number|null, "text": string|null}

Message:
${text}`;
  let raw: string;
  try {
    raw = await gemini(prompt);
  } catch (error) {
    console.error("[sendblue] extractReview gemini error", error);
    return null;
  }
  const parsed = parseReplyJson(raw) as {
    is_review?: unknown;
    rating?: unknown;
    text?: unknown;
  } | null;
  if (!parsed || parsed.is_review !== true) return null;
  const rating =
    typeof parsed.rating === "number" && parsed.rating >= 1 && parsed.rating <= 5
      ? Math.round(parsed.rating)
      : undefined;
  const reviewText = typeof parsed.text === "string" && parsed.text.trim() ? parsed.text.trim() : undefined;
  if (rating === undefined && !reviewText) return null; // nothing usable
  return { rating, text: reviewText };
}

export function formatReviewReply(
  merchant: string,
  review: ExtractedReview,
  count: number,
  chinese: boolean,
): string {
  const stars = review.rating ? (chinese ? `${review.rating}★ ` : `${review.rating}★ `) : "";
  return chinese
    ? `✅ 已存你對 ${merchant} 的評論 ${stars}— 收據驗證過的真實評論,你累積 ${count} 則了。`
    : `✅ Saved your ${stars}review of ${merchant} — receipt-verified, that's ${count} now.`;
}

// --- Taste profile (personalized ranking) ----------------------------------
// Lightweight per-person taste signal from what they've engaged with: places
// they SAVED + merchants they VISITED (receipts). Used to (a) not re-recommend
// places they already know, and (b) nudge ranking toward their categories.

export type TasteProfile = {
  /** lower-cased names of places the user already saved or visited. */
  knownNames: string[];
  /** category keywords the user engages with most (e.g. "cafe", "ramen"). */
  preferredCategories: string[];
};

export function buildTasteProfile(saved: SavedPlace[], visitedMerchants: string[]): TasteProfile {
  const knownNames = [
    ...saved.map((p) => p.name),
    ...visitedMerchants,
  ]
    .map((n) => n.trim().toLowerCase())
    .filter((n) => n.length > 0);
  const counts = new Map<string, number>();
  for (const p of saved) {
    const c = p.category?.trim().toLowerCase();
    if (c) counts.set(c, (counts.get(c) ?? 0) + 1);
  }
  const preferredCategories = [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([c]) => c);
  return { knownNames: [...new Set(knownNames)], preferredCategories };
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

// "Make this recurring" intents. Checked BEFORE isOrderIntent so "每天幫我點一杯"
// sets a subscription instead of a one-off order.
const recurringIntentPhrases = ["每天", "每日", "每週", "每周", "固定", "定期", "recurring", "every day", "every morning", "every week", "daily", "weekly", "set recurring", "subscribe"];
export function isRecurringIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  if (!lower) return false;
  return recurringIntentPhrases.some((phrase) => lower.includes(phrase));
}

// Confirm the pending recurring run (the "order your usual now?" reply).
const recurringConfirmPhrases = ["確認定期", "confirm recurring", "confirm my usual", "order my usual", "送出定期"];
export function isRecurringConfirmIntent(text: string): boolean {
  const lower = text.toLowerCase().trim();
  return recurringConfirmPhrases.some((phrase) => lower.includes(phrase));
}

// Parse a coarse weekly schedule. Defaults: every day at 08:00. Recognizes
// 平日/weekday (Mon-Fri), 週末/weekend, and an hour (8點 / 8am / 08:00). tz is a
// fixed default — SAV-E has no per-user tz yet.
export function parseRecurringSchedule(text: string, tz: string): { daysOfWeek: number[]; hour: number; minute: number; tz: string } {
  const lower = text.toLowerCase();
  let daysOfWeek = [0, 1, 2, 3, 4, 5, 6];
  if (/(平日|weekday|工作日|週一到週五|周一到周五|mon-fri)/i.test(lower)) daysOfWeek = [1, 2, 3, 4, 5];
  else if (/(週末|周末|weekend)/i.test(lower)) daysOfWeek = [0, 6];
  let hour = 8;
  let minute = 0;
  const hm = lower.match(/(\d{1,2})\s*[:點点]\s*(\d{2})/) || lower.match(/(\d{1,2})\s*(am|pm)/);
  if (hm) {
    hour = Number(hm[1]);
    if (/pm/.test(hm[0]) && hour < 12) hour += 12;
    if (/am/.test(hm[0]) && hour === 12) hour = 0;
    minute = hm[2] && /^\d{2}$/.test(hm[2]) ? Number(hm[2]) : 0;
    if (hour > 23) hour = 8;
  }
  return { daysOfWeek, hour, minute, tz };
}

// Strip recurring + order + time keywords → the "usual" item intent.
export function recurringQuery(text: string): string {
  return orderQuery(
    text
      .trim()
      .replace(/(每天|每日|每週|每周|平日|週末|周末|固定|定期|recurring|every day|every morning|every week|daily|weekly|set recurring|subscribe)/gi, " ")
      .replace(/(\d{1,2}\s*[:點点]\s*\d{2}|\d{1,2}\s*(am|pm)|早上|上午|下午|晚上|morning|afternoon|evening)/gi, " ")
      .replace(/\s+/g, " ")
      .trim(),
  );
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

function savedPlaceCountLabel(count: number, chinese: boolean): string {
  if (chinese) return `${count} 個已存地點`;
  return `${count} saved place${count === 1 ? "" : "s"}`;
}

function formatMySavesLinkHandoff(
  places: SavedPlace[],
  area: string | undefined,
  url: string,
  chinese: boolean,
): string {
  if (places.length === 0) return emptyListReply;
  if (chinese) {
    const scope = area ? `（${area}）` : "";
    return `找到 ${savedPlaceCountLabel(places.length, true)}${scope}。\n打開 My SAV-E 看卡片和地圖：\n${url}`;
  }
  const scope = area ? ` in ${area}` : "";
  return `I found ${savedPlaceCountLabel(places.length, false)}${scope}.\nOpen My SAV-E to browse cards and map:\n${url}`;
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
  priceRange?: string;
  category?: string;
  mapsUri?: string;
  lat?: number;
  lng?: number;
};

/**
 * Apple Maps deep link. On iMessage these render as a RICH native map card
 * (thumbnail + pin), unlike a bare google.com link. Prefer coordinates; fall
 * back to a name/address query.
 */
export function appleMapsUrl(place: DiscoveredPlace): string {
  const label = encodeURIComponent(place.name);
  if (typeof place.lat === "number" && typeof place.lng === "number") {
    return `https://maps.apple.com/?ll=${place.lat},${place.lng}&q=${label}`;
  }
  const q = encodeURIComponent([place.name, place.address].filter(Boolean).join(" "));
  return `https://maps.apple.com/?q=${q}`;
}

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
        "places.displayName,places.formattedAddress,places.rating,places.priceLevel,places.primaryType,places.googleMapsUri,places.location",
    },
    body: JSON.stringify({ textQuery: query, maxResultCount: 8 }),
  });
  if (!response.ok) throw new Error(`Places searchText failed: ${response.status}`);
  const body = (await response.json()) as {
    places?: {
      displayName?: { text?: string };
      formattedAddress?: string;
      rating?: number;
      priceLevel?: string | number;
      primaryType?: string;
      googleMapsUri?: string;
      location?: { latitude?: number; longitude?: number };
    }[];
  };
  return (body.places ?? [])
    .map((p) => ({
      name: p.displayName?.text ?? "",
      address: p.formattedAddress,
      rating: typeof p.rating === "number" ? p.rating : undefined,
      priceRange: googlePriceLevelToSymbol(p.priceLevel),
      category: p.primaryType?.replace(/_/g, " "),
      mapsUri: p.googleMapsUri,
      lat: typeof p.location?.latitude === "number" ? p.location.latitude : undefined,
      lng: typeof p.location?.longitude === "number" ? p.location.longitude : undefined,
    }))
    .filter((p) => p.name.length > 0);
}

function googlePriceLevelToSymbol(priceLevel: string | number | undefined): string | undefined {
  if (typeof priceLevel === "number" && priceLevel > 0) return "$".repeat(Math.min(Math.round(priceLevel), 4));
  if (typeof priceLevel !== "string") return undefined;
  const normalized = priceLevel.trim().toUpperCase();
  if (normalized === "PRICE_LEVEL_FREE") return "free";
  if (normalized === "PRICE_LEVEL_INEXPENSIVE") return "$";
  if (normalized === "PRICE_LEVEL_MODERATE") return "$$";
  if (normalized === "PRICE_LEVEL_EXPENSIVE") return "$$$";
  if (normalized === "PRICE_LEVEL_VERY_EXPENSIVE") return "$$$$";
  return undefined;
}

/** Google reviews + editorial summary for one place — evidence for "what to order". */
export type PlaceReviewEvidence = { name: string; editorial?: string; reviews: string[] };
export type PlacesReviews = (query: string) => Promise<PlaceReviewEvidence | null>;

/**
 * Fetch a place's editorial summary + recent review text (the "what to order"
 * evidence for a place the user did NOT save — e.g. one the bot just
 * recommended). Reviews are a pricier Places SKU, so this is only called on an
 * explicit "what should I order" question, never on every search.
 */
export async function defaultPlacesReviews(query: string): Promise<PlaceReviewEvidence | null> {
  const apiKey = process.env.GOOGLE_PLACES_API_KEY;
  if (!apiKey) throw new Error("Missing GOOGLE_PLACES_API_KEY");
  const response = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.displayName,places.editorialSummary,places.reviews",
    },
    body: JSON.stringify({ textQuery: query, maxResultCount: 1 }),
  });
  if (!response.ok) throw new Error(`Places reviews failed: ${response.status}`);
  const body = (await response.json()) as {
    places?: {
      displayName?: { text?: string };
      editorialSummary?: { text?: string };
      reviews?: { text?: { text?: string }; originalText?: { text?: string } }[];
    }[];
  };
  const p = body.places?.[0];
  if (!p) return null;
  const reviews = (p.reviews ?? [])
    .map((r) => r.text?.text ?? r.originalText?.text ?? "")
    .filter((t) => t.trim().length > 0)
    .slice(0, 5);
  return { name: p.displayName?.text ?? query, editorial: p.editorialSummary?.text, reviews };
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
  /** A merchant we just invited a review for (receipt-gated) — next msg is the review. */
  pendingReview?: string;
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
  /** Arm a receipt-gated review prompt for a merchant; next message is the review. */
  setReview(phone: string, merchant: string): void;
  /** Clear an armed review prompt. */
  clearReview(phone: string): void;
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
  setReview(phone: string, merchant: string): void {
    this.merge(phone, { pendingReview: merchant });
  }
  clearReview(phone: string): void {
    const prev = this.get(phone);
    if (prev) this.map.set(phone, { ...prev, pendingReview: undefined, at: Date.now() });
  }
  clearPending(phone: string): void {
    const prev = this.get(phone);
    if (prev) this.map.set(phone, { ...prev, pendingQuery: undefined, at: Date.now() });
  }
  /** Seed an entry verbatim (used to hydrate from a durable backing store). */
  restore(phone: string, state: ConversationState): void {
    this.map.set(phone, state);
  }
}

/** Process-wide conversation memory (single Railway instance, 10-min TTL). */
export const defaultConversationStore: ConversationStore = new InMemoryConversationStore();

export const conversationStateTableSql = `
create table if not exists sendblue_conversation_state (
  memory_key text primary key,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists sendblue_conversation_state_updated_idx
  on sendblue_conversation_state (updated_at);
`;

/**
 * Durable conversation memory: an in-memory store (fast, synchronous — so the
 * ConversationStore interface stays sync and call sites don't change) that
 * WRITES THROUGH to Postgres on every mutation and HYDRATES from Postgres at
 * boot. This makes the multi-turn state (pending location, last recommended
 * place, armed review, …) survive deploys/restarts — the "bot forgot what I just
 * said" class of bugs. Single Railway instance, so the in-memory layer is the
 * source of truth at runtime and the DB is the durable mirror.
 */
export class PgBackedConversationStore implements ConversationStore {
  private readonly mem = new InMemoryConversationStore();
  constructor(private readonly db: ConversationQueryable) {}

  /** Load recent (non-stale) state into memory. Call once at startup. */
  async hydrate(): Promise<void> {
    try {
      const { rows } = await this.db.query(
        `select memory_key, state, (extract(epoch from updated_at) * 1000)::bigint as at
         from sendblue_conversation_state
         where updated_at > now() - interval '${Math.round(CONVERSATION_TTL_MS / 60000)} minutes'`,
      );
      for (const row of rows) {
        const raw = typeof row.state === "string" ? JSON.parse(row.state) : row.state;
        this.mem.restore(String(row.memory_key), { ...(raw as object), at: Number(row.at) } as ConversationState);
      }
      console.log(`[sendblue] hydrated ${rows.length} conversation states`);
    } catch (error) {
      console.error("[sendblue] conversation hydrate failed", error);
    }
  }

  private persist(phone: string): void {
    const state = this.mem.get(phone);
    if (!state) {
      // Cleared/expired → drop the durable row too (best-effort).
      void this.db
        .query(`delete from sendblue_conversation_state where memory_key = $1`, [phone])
        .catch((error) => console.error("[sendblue] conversation delete failed", error));
      return;
    }
    const { at: _at, ...rest } = state;
    void this.db
      .query(
        `insert into sendblue_conversation_state (memory_key, state, updated_at)
         values ($1, $2::jsonb, now())
         on conflict (memory_key) do update set state = excluded.state, updated_at = now()`,
        [phone, JSON.stringify(rest)],
      )
      .catch((error) => console.error("[sendblue] conversation persist failed", error));
  }

  get(phone: string): ConversationState | undefined {
    return this.mem.get(phone);
  }
  setPending(phone: string, query: string): void {
    this.mem.setPending(phone, query);
    this.persist(phone);
  }
  setPlaces(phone: string, places: DiscoveredPlace[]): void {
    this.mem.setPlaces(phone, places);
    this.persist(phone);
  }
  setRecommended(phone: string, place: DiscoveredPlace): void {
    this.mem.setRecommended(phone, place);
    this.persist(phone);
  }
  setArea(phone: string, area: string): void {
    this.mem.setArea(phone, area);
    this.persist(phone);
  }
  addShown(phone: string, name: string): void {
    this.mem.addShown(phone, name);
    this.persist(phone);
  }
  setReview(phone: string, merchant: string): void {
    this.mem.setReview(phone, merchant);
    this.persist(phone);
  }
  clearReview(phone: string): void {
    this.mem.clearReview(phone);
    this.persist(phone);
  }
  clearPending(phone: string): void {
    this.mem.clearPending(phone);
    this.persist(phone);
  }
}

/** Minimal pg-pool-like surface for the conversation store. */
export type ConversationQueryable = {
  query: (sql: string, values?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;
};

/**
 * The agentic decision for a no-URL message: either answer from the user's saved
 * places ("reply"), or go DISCOVER new places near a location via Google
 * ("search"). `area` is null when the user wants nearby but gave no location.
 */
export type RecallDecision =
  | { kind: "reply"; reply: string }
  | { kind: "search"; query: string; area: string | null }
  // The user stated WHERE they are with no specific request — remember it.
  | { kind: "location"; area: string }
  // The user wants the address / map / "card" of a specific place — look it up.
  | { kind: "details"; placeName: string }
  // The user wants to know WHAT TO ORDER at a place — ground it in the saved post.
  | { kind: "order_advice"; placeName: string };

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
    if (p.priceRange) bits.push(p.priceRange);
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
5. The user wants the ADDRESS, exact location, map link, or "card" of a SPECIFIC place — either named (e.g. "where is 菊乃井's address", "give me X's card") or referenced ("it", "他", "that place" = the place you recently recommended/discussed above). Return {"details":{"placeName":"<the place's name>"}}. Do NOT answer the address from memory — this triggers a real lookup. Resolve pronouns to the recommended/last place above.
6. The user asks WHAT TO ORDER / what's good to eat / what's the must-try at a specific place ("要點什麼", "what should I order", "what's good here", "推薦什麼餐", "他們招牌是什麼"). Return {"order_advice":{"placeName":"<the place's name>"}}. Resolve pronouns to the recommended/last place above. Do NOT make up a dish — this triggers grounding in the post they saved.
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
  if (parsed.details && typeof parsed.details.placeName === "string" && parsed.details.placeName.trim()) {
    return { kind: "details", placeName: parsed.details.placeName.trim() };
  }
  if (
    parsed.order_advice &&
    typeof parsed.order_advice.placeName === "string" &&
    parsed.order_advice.placeName.trim()
  ) {
    return { kind: "order_advice", placeName: parsed.order_advice.placeName.trim() };
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
  details?: { placeName?: unknown };
  order_advice?: { placeName?: unknown };
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
 * True when a Places result is really just the searched location (a street
 * address echoed back as a "place"), not a business: its name equals the area,
 * or its name is a digit-bearing fragment of the area with no rating. Used to
 * avoid recommending the user's own address back to them.
 */
export function isSearchedAddress(place: DiscoveredPlace, area: string): boolean {
  const name = foldText(place.name);
  const a = foldText(area);
  if (!name) return true;
  if (name === a) return true;
  if (place.rating === undefined && /\d/.test(place.name) && a.includes(name)) return true;
  return false;
}

/**
 * Pick the best discovery result the user hasn't already been shown: highest
 * rating among names not in `exclude` (case-insensitive). Falls back to the
 * highest-rated overall if everything was already shown (better to repeat than
 * to dead-end). Returns undefined only for an empty result set.
 */
/**
 * Rank discovery results: taste-aware (Google rating + a boost for the user's
 * categories), excluded names dropped. Fresh (non-excluded) first; if everything
 * was excluded, falls back to the full set ranked. Returns a sorted copy.
 */
export function rankPlaces(
  found: DiscoveredPlace[],
  exclude: string[] = [],
  preferredCategories: string[] = [],
): DiscoveredPlace[] {
  const seen = new Set(exclude.map((n) => n.toLowerCase()));
  const score = (p: DiscoveredPlace): number => {
    const base = p.rating ?? 0;
    const cat = p.category?.toLowerCase() ?? "";
    const match = cat && preferredCategories.some((c) => cat.includes(c) || c.includes(cat));
    return base + (match ? 0.3 : 0);
  };
  const byScore = (a: DiscoveredPlace, b: DiscoveredPlace) => score(b) - score(a);
  const fresh = found.filter((p) => !seen.has(p.name.toLowerCase())).sort(byScore);
  return fresh.length > 0 ? fresh : [...found].sort(byScore);
}

/** The user's history used to justify a recommendation. */
export type TasteContext = {
  /** categories the user saves most (from saved places) */
  categories: string[];
  /** merchant names the user has a receipt for (verified visits) */
  visited: string[];
  /** names of places the user has saved */
  saved: string[];
};

/**
 * Recommend 2-3 real places with ONE personalized reason tied to the user's
 * history ("since you've been to X / you save a lot of cafes…"). Grounded: the
 * reason may only cite history actually passed in; the places are real Google
 * results. Deterministic multi-place template fallback when the model fails.
 */
export async function phraseRecommendations(
  query: string,
  area: string,
  picks: DiscoveredPlace[],
  taste: TasteContext,
  gemini: GeminiCaller = defaultGeminiText,
  chinese = false,
): Promise<string> {
  const top = picks.slice(0, 3);
  const template = (): string => {
    const head = chinese ? `${area} 附近評分最高的:` : `Top-rated near ${area}:`;
    const lines = top.map((p, i) => `${i + 1}. ${p.name}${p.rating ? ` ${p.rating}★` : ""}`);
    return [head, ...lines].join("\n");
  };
  if (top.length === 0) return template();
  const lang = chinese ? "繁體中文" : "the same language the user wrote in";
  const list = top
    .map(
      (p, i) =>
        `${i + 1}. ${p.name}${p.rating ? ` (${p.rating}★)` : ""}${p.priceRange ? ` ${p.priceRange}` : ""}${p.address ? ` — ${p.address}` : ""}${p.category ? ` [${p.category}]` : ""}`,
    )
    .join("\n");
  const history =
    [
      taste.visited.length ? `Places they have a receipt for (visited): ${taste.visited.slice(0, 5).join(", ")}` : "",
      taste.categories.length ? `Categories they save most: ${taste.categories.join(", ")}` : "",
      taste.saved.length ? `Places they've saved: ${taste.saved.slice(0, 8).join(", ")}` : "",
    ]
      .filter(Boolean)
      .join("\n") || "(no history yet)";
  const prompt = `Recommend 2-3 of these REAL Google results for "${query}" near ${area}, WITH one short personalized reason tied to the user's history.

The user's history:
${history}

If the history is relevant, LEAD with a reason like "Since you've been to <place> / you save a lot of <category>, …" — but ONLY cite history that is actually listed above; NEVER invent a visit, order, or saved place. If there is no relevant history, just say these are the top-rated spots near them. Then list the 2-3 places (name + rating). Use ONLY the results + history above; do not invent places, addresses, or menus. ${lang}, SMS-friendly, at most 4 short lines, at most one emoji.

Results:
${list}

Return STRICT JSON only: {"reply": string}`;
  try {
    const raw = await gemini(prompt);
    const parsed = parseReplyJson(raw);
    const reply = parsed && typeof parsed.reply === "string" ? parsed.reply.trim() : "";
    return reply.length > 0 ? reply : template();
  } catch (error) {
    console.error("[sendblue] phraseRecommendations gemini error", error);
    return template();
  }
}

export function pickBestPlace(
  found: DiscoveredPlace[],
  exclude: string[] = [],
  preferredCategories: string[] = [],
): DiscoveredPlace | undefined {
  return rankPlaces(found, exclude, preferredCategories)[0];
}

/**
 * Phrase a single chosen place naturally via the LLM (grounded in its real
 * data), with a deterministic template fallback so a recommendation never fails
 * just because phrasing did.
 */
/**
 * A compact place "card": name, rating, real address, and a Google Maps link.
 * Google is kept (over Apple Maps) because its iMessage preview surfaces the
 * business PHOTO — telling the user what the place actually looks like — whereas
 * an Apple Maps link only shows a map pin.
 */
export function formatPlaceCard(place: DiscoveredPlace, chinese: boolean): string {
  const lines = [place.name + (place.rating ? ` — ${place.rating}★` : "")];
  if (place.priceRange) lines[0] += ` — ${place.priceRange}`;
  if (place.address) lines.push(`📍 ${place.address}`);
  lines.push(place.mapsUri ?? appleMapsUrl(place));
  return lines.join("\n");
}

function isPriceIntent(text: string): boolean {
  return /\b(how much|price|prices|pricing|cost|costs|expensive|cheap)\b|多少錢|多少钱|價格|价钱|價錢|價位|貴嗎|贵吗/i.test(text);
}

function formatPriceReply(place: DiscoveredPlace, chinese: boolean): string {
  const known = [
    typeof place.rating === "number" ? `${place.rating}★` : "",
    place.address ? (chinese ? "地址/card" : "address/card") : "",
  ].filter(Boolean);
  if (place.priceRange) {
    return chinese
      ? `${place.name} 的大概價位是 ${place.priceRange}。\n我還沒有可靠的單品菜單價格。`
      : `${place.name} looks like ${place.priceRange}.\nI don't have reliable menu item prices yet.`;
  }
  const knownLine = known.length
    ? chinese
      ? `我目前只知道：${known.join("、")}。`
      : `I only have: ${known.join(", ")}.`
    : "";
  return chinese
    ? `我還沒有 ${place.name} 的可靠菜單價格。\n${knownLine}`.trim()
    : `I don't have menu prices for ${place.name} yet.\n${knownLine}`.trim();
}

/**
 * "What should I order?" answered from the social post the user SAVED this place
 * from (the caption that made them save it usually names the standout dish).
 * Grounded: only suggests what the caption actually mentions; returns null when
 * the caption names no specific dish, so the caller can decline honestly.
 */
export async function suggestOrderFromCaption(
  placeName: string,
  caption: string,
  gemini: GeminiCaller = defaultGeminiText,
  chinese = false,
): Promise<string | null> {
  if (!caption.trim()) return null;
  const lang = chinese ? "繁體中文" : "the same language the user wrote in";
  const prompt = `The user saved "${placeName}" from this social post. Based ONLY on the post's caption, what is the standout dish / drink / item to order there? If the caption does NOT name a specific dish or item, return {"reply": null}. Never invent a menu item. 1-2 short sentences, ${lang}, frame it as "from the post you saved…". At most one emoji.

Caption:
${caption}

Return STRICT JSON only: {"reply": string|null}`;
  let raw: string;
  try {
    raw = await gemini(prompt);
  } catch (error) {
    console.error("[sendblue] suggestOrderFromCaption gemini error", error);
    return null;
  }
  const parsed = parseReplyJson(raw);
  const reply = parsed && typeof parsed.reply === "string" ? parsed.reply.trim() : "";
  return reply.length > 0 ? reply : null;
}

/**
 * "What should I order?" for a place the user did NOT save (e.g. one the bot just
 * recommended) — grounded in Google reviews + editorial summary. Suggests only
 * what reviewers actually mention; returns null when nothing clear surfaces.
 */
export async function suggestOrderFromReviews(
  placeName: string,
  evidence: PlaceReviewEvidence,
  gemini: GeminiCaller = defaultGeminiText,
  chinese = false,
): Promise<string | null> {
  const corpus = [evidence.editorial ?? "", ...evidence.reviews].filter(Boolean).join("\n").slice(0, 4000);
  if (!corpus.trim()) return null;
  const lang = chinese ? "繁體中文" : "the same language the user wrote in";
  const prompt = `Based ONLY on these Google reviews / editorial summary for "${placeName}", what should the user order — the dishes or drinks reviewers actually rave about? If the text doesn't clearly name a specific item, return {"reply": null}. Never invent a menu item. 1-2 short sentences, ${lang}, frame it as "reviewers love…" / "people order…". At most one emoji.

Reviews / summary:
${corpus}

Return STRICT JSON only: {"reply": string|null}`;
  try {
    const raw = await gemini(prompt);
    const parsed = parseReplyJson(raw);
    const reply = parsed && typeof parsed.reply === "string" ? parsed.reply.trim() : "";
    return reply.length > 0 ? reply : null;
  } catch (error) {
    console.error("[sendblue] suggestOrderFromReviews gemini error", error);
    return null;
  }
}

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
  /** Google reviews/editorial for "what to order" at an unsaved place. Defaults to defaultPlacesReviews. */
  placesReviews?: PlacesReviews;
  /** Conversation memory (pending location + last recommended places). Defaults to the module singleton. */
  conversation?: ConversationStore;
  /** Verified-visit memory: forwarded receipts → proof-of-visit. Omitted = receipts disabled. */
  receiptStore?: VerifiedVisitStore;
  /** Receipt-gated review memory. Omitted = reviews disabled. */
  reviewStore?: ReviewStore;
  client: Pick<SendblueClient, "sendMessage" | "markRead" | "sendTypingIndicator">;
  store: SendbluePlaceStore;
  /** Place an SLL-R order for this number; returns the reply, or null to fall
   *  through to the normal save/recall flow. Omitted in tests / when SLL-R is off. */
  order?: (query: string, fromNumber: string, location?: StoredLocation) => Promise<string | null>;
  /** Set up a recurring order ("每天早上一杯…"); returns the reply. Omitted = off. */
  setRecurring?: (text: string, fromNumber: string, location?: StoredLocation) => Promise<string | null>;
  /** Confirm the buyer's pending recurring run(s) → charge saved card. Omitted = off. */
  confirmRecurring?: (fromNumber: string) => Promise<string | null>;
  /** Geocode an area the user texts ("I'm in X") → coordinates, stored per number. */
  geocode?: Geocoder;
  /** Private tokenized web page for the sender's saved places/visits/reviews. */
  mySavesUrl?: (memoryKey: string) => string | null | undefined;
  /**
   * Resolve the inbound phone/provider id to the canonical SAV-E vault key.
   * Unlinked numbers fall back to the phone so the public bot still works.
   */
  resolveMemoryKey?: (fromNumber: string) => Promise<string>;
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
  mySavesUrl?: (memoryKey: string) => string | null | undefined,
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
    const url = mySavesUrl?.(from);
    if (url) return formatMySavesLinkHandoff(places, area, url, chinese);
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
  let memoryKey = from;
  if (deps.resolveMemoryKey) {
    try {
      memoryKey = await deps.resolveMemoryKey(from);
    } catch (error) {
      console.error("[sendblue] resolveMemoryKey error", error);
    }
  }
  if (memoryKey !== from) console.log("[sendblue] resolved inbound channel to SAV-E profile");

  // Best-effort: show the user a blue read receipt + typing indicator while we
  // fetch + extract. Fire-and-forget (not awaited) so two Sendblue round-trips
  // don't sit on the critical path — the typing dots show DURING processing,
  // which is exactly when we want them. The client wraps its own errors.
  void deps.client.markRead(from);
  void deps.client.sendTypingIndicator(from);

  const chinese = looksChinese(text);
  // Conversation memory is loaded up front so the receipt/review branches and the
  // agentic branch all share one snapshot (pending location, last places, pending review).
  const convoStore = deps.conversation ?? defaultConversationStore;
  const convo = convoStore.get(memoryKey);
  let reply: string;
  try {
    const url = firstUrlInText(text);
    // Receipt → verified visit (proof-of-visit). Checked FIRST: a receipt's
    // "thank you for your order" text must not be mistaken for an order intent.
    // Cheap heuristic gate, then the LLM confirms; only fires when wired in.
    const receiptLink = url ? isReceiptLink(url) : false;
    if (deps.receiptStore && deps.gemini && (receiptLink || looksLikeReceipt(text))) {
      // A receipt can be plain text OR a link from a POS provider (Toast/Square/
      // etc.). For a link, fetch the receipt page so its merchant/total feed the
      // extractor — otherwise a bare receipt URL would fall through to the social
      // place-save path and get saved as a place instead of a verified visit.
      let receiptText = text;
      if (receiptLink && url) {
        try {
          const { caption } = await fetchLinkCaption(url, deps.fetchText);
          receiptText = `${text}\n${caption}`.trim();
          console.log(`[sendblue] receipt link ${url} captionLen=${caption.length}`);
        } catch (fetchErr) {
          console.error("[sendblue] receipt link fetch error", fetchErr);
        }
      }
      const receipt = await extractReceipt(receiptText, deps.gemini);
      if (receipt) {
        let count = 0;
        let dup = false;
        try {
          // Light dedup: the same receipt is often forwarded as two messages (an
          // order header + the link). If the most recent visit is the SAME
          // merchant within 10 minutes, don't double-count it.
          const recent = await deps.receiptStore.list(memoryKey, 1);
          const last = recent[0];
          const freshMs = last?.createdAt ? Date.now() - last.createdAt.getTime() : Infinity;
          if (last && freshMs < 10 * 60 * 1000 && last.merchant.toLowerCase() === receipt.merchant.toLowerCase()) {
            dup = true;
            count = (await deps.receiptStore.list(memoryKey, 1000)).length;
          } else {
            count = await deps.receiptStore.save(memoryKey, {
              merchant: receipt.merchant,
              total: receipt.total,
              visitDate: receipt.date,
              raw: receiptText,
            });
          }
        } catch (storeError) {
          console.error("[sendblue] receipt save error", storeError);
        }
        console.log(
          `[sendblue] receipt merchant="${receipt.merchant}" total="${receipt.total ?? ""}" count=${count} dup=${dup} link=${receiptLink}`,
        );
        // Arm a receipt-gated review: the next message is read as a review of
        // this exact (verified) merchant.
        if (deps.reviewStore) convoStore.setReview(memoryKey, receipt.merchant);
        reply = formatReceiptReply(receipt, count, chinese);
        await deps.client.sendMessage(from, reply);
        return { replied: true, reply };
      }
    }
    // Pending review: the previous turn logged a receipt and asked "want to
    // review?" — read this message as the rating/text for that merchant. Not a
    // review (declining / new topic) → clear it and fall through to normal flow.
    // Which merchant a review reply targets: the in-memory armed merchant, OR —
    // robust to process restarts (in-memory state is ephemeral) — the most recent
    // verified visit within 30 min, gated by a cheap review-ish heuristic.
    let reviewMerchant = convo?.pendingReview;
    if (!reviewMerchant && !url && deps.reviewStore && deps.receiptStore && looksLikeReview(text)) {
      try {
        const recent = await deps.receiptStore.list(memoryKey, 1);
        const last = recent[0];
        const freshMs = last?.createdAt ? Date.now() - last.createdAt.getTime() : Infinity;
        if (last && freshMs < 30 * 60 * 1000) reviewMerchant = last.merchant;
      } catch (storeError) {
        console.error("[sendblue] recent visit lookup error", storeError);
      }
    }
    if (deps.reviewStore && deps.gemini && reviewMerchant && !url) {
      const merchant = reviewMerchant;
      const review = await extractReview(text, merchant, deps.gemini);
      convoStore.clearReview(memoryKey);
      if (review) {
        let count = 0;
        try {
          count = await deps.reviewStore.save(memoryKey, {
            merchant,
            rating: review.rating,
            text: review.text,
          });
        } catch (storeError) {
          console.error("[sendblue] review save error", storeError);
        }
        console.log(
          `[sendblue] review merchant="${merchant}" rating=${review.rating ?? ""} count=${count}`,
        );
        reply = formatReviewReply(merchant, review, count, chinese);
        await deps.client.sendMessage(from, reply);
        return { replied: true, reply };
      }
      console.log(`[sendblue] pending review for "${merchant}" not a review → falling through`);
    }
    // Receipt-ish text we could NOT parse as a receipt (e.g. an order header like
    // "Review Order #214 at X" that precedes the receipt link). Don't let it fall
    // through to the place-recall path and answer "I don't have a place called X"
    // — ack softly and ask for the receipt instead.
    if (!url && looksLikeReceipt(text)) {
      console.log(`[sendblue] receipt-ish unparsed → soft ack for ${from}`);
      reply = chinese
        ? "📩 看起來像收據 — 把收據連結或完整內容傳給我,我就幫你記成驗證訪問。"
        : "📩 Looks like a receipt — forward the receipt link or full text and I'll log it as a verified visit.";
      await deps.client.sendMessage(from, reply);
      return { replied: true, reply };
    }
    if (!url && isPriceIntent(text) && convo?.lastRecommended) {
      reply = formatPriceReply(convo.lastRecommended, chinese);
      await deps.client.sendMessage(from, reply);
      return { replied: true, reply };
    }
    if (deps.geocode && !url && isLocationIntent(text)) {
      // Location set: "I'm in X" → geocode → remember per number for nearby orders.
      const loc = await deps.geocode(parseLocationQuery(text));
      if (loc) {
        await deps.store.setLocation(memoryKey, loc);
        reply = `📍 Got it — I'll use ${loc.label} for nearby orders.`;
      } else {
        reply = 'I couldn\'t find that area. Try a city/neighborhood, e.g. "I\'m in Santa Monica".';
      }
      await deps.client.sendMessage(from, reply);
      return { replied: true, reply };
    }
    // Confirm a pending recurring run ("confirm my usual") → charge saved card.
    if (deps.confirmRecurring && !url && isRecurringConfirmIntent(text)) {
      const confirmReply = await deps.confirmRecurring(from);
      if (confirmReply) {
        await deps.client.sendMessage(from, confirmReply);
        return { replied: true, reply: confirmReply };
      }
    }
    // Set up a recurring order ("每天早上一杯…"). Checked before isOrderIntent so a
    // recurring phrase doesn't fall through to a one-off order.
    if (deps.setRecurring && !url && isRecurringIntent(text)) {
      const loc = await deps.store.getLocation(memoryKey);
      const recurringReply = await deps.setRecurring(text, from, loc ?? undefined);
      if (recurringReply) {
        await deps.client.sendMessage(from, recurringReply);
        return { replied: true, reply: recurringReply };
      }
    }
    if (deps.order && !url && isOrderIntent(text)) {
      // Order flow: needs the user's area to pick the nearest merchant.
      const loc = await deps.store.getLocation(memoryKey);
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
    if (!url && isListIntent(text)) {
      reply = await keywordRecallReply(text, memoryKey, chinese, deps.store, deps.mySavesUrl);
    } else if (url) {
      // Save flow: link → caption → venue → remember it for this number.
      const { caption } = await fetchLinkCaption(url, deps.fetchText);
      console.log(`[sendblue] url=${url} captionLen=${caption.length}`);
      const venue = caption ? await extractVenueFromCaption(caption, deps.gemini) : null;
      console.log(`[sendblue] venue=${venue ? JSON.stringify(venue) : "(none)"}`);
      if (venue) {
        let count: number;
        try {
          count = await deps.store.save(memoryKey, venue, url);
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
        // Make the just-saved place the conversation's focus so a follow-up
        // ("where is it?", "京都哪裡?") resolves to THIS place instead of
        // "which place do you mean?". Enrich it with a Google Places lookup for a
        // real address — social captions rarely include one.
        let focus: DiscoveredPlace = {
          name: venue.name,
          address: venue.area,
          category: venue.category,
        };
        if (deps.placesSearch) {
          try {
            const hit = (await deps.placesSearch(`${venue.name} ${venue.area ?? ""}`.trim()))[0];
            if (hit) {
              focus = {
                name: venue.name,
                address: hit.address ?? venue.area,
                rating: hit.rating,
                priceRange: hit.priceRange,
                category: venue.category ?? hit.category,
              };
              console.log(`[sendblue] save enrich → "${hit.name}" ${hit.address ?? "(no addr)"}`);
            }
          } catch (enrichError) {
            console.error("[sendblue] save enrich error", enrichError);
          }
        }
        convoStore.setRecommended(memoryKey, focus);
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
        places = await deps.store.list(memoryKey, { limit: 50 });
      } catch (storeError) {
        console.error("[sendblue] store.list error", storeError);
      }
      // Personalization: build a taste profile from saved places + visited
      // merchants (receipts), to skip places they already know and nudge ranking.
      let visitedMerchants: string[] = [];
      if (deps.receiptStore) {
        try {
          visitedMerchants = (await deps.receiptStore.list(memoryKey, 50)).map((v) => v.merchant);
        } catch (storeError) {
          console.error("[sendblue] receiptStore.list error", storeError);
        }
      }
      const taste = buildTasteProfile(places, visitedMerchants);
      // (convoStore/convo are loaded once at the top of the handler.)
      const decision = await decideRecall(text, places, deps.gemini, chinese, {
        pendingQuery: convo?.pendingQuery,
        lastPlaces: convo?.lastPlaces,
        lastArea: convo?.lastArea,
        lastRecommended: convo?.lastRecommended,
      });
      if (!decision) {
        convoStore.clearPending(memoryKey);
        console.log(`[sendblue] agentic empty → keyword fallback for ${from}`);
        reply = await keywordRecallReply(text, memoryKey, chinese, deps.store, deps.mySavesUrl);
      } else if (decision.kind === "details") {
        // The user wants a specific place's address / map / "card" → look it up
        // live (Google Places) instead of answering "it's in <city>" from memory.
        const search = deps.placesSearch ?? defaultPlacesSearch;
        const savedMatch = findSavedPlaceMatch(decision.placeName, places);
        const lookupQuery = savedMatch ? savedPlaceLookupQuery(savedMatch) : decision.placeName;
        let found: DiscoveredPlace[] = [];
        try {
          found = await search(lookupQuery);
        } catch (searchError) {
          console.error("[sendblue] details lookup error", searchError);
        }
        const place = found[0];
        console.log(`[sendblue] details "${lookupQuery}" → ${place?.name ?? "(none)"}`);
        if (place) {
          convoStore.setRecommended(memoryKey, place); // make it the conversation focus
          reply = formatPlaceCard(place, chinese);
        } else if (savedMatch) {
          reply = savedPlaceAreaFallback(savedMatch, chinese);
        } else {
          reply = chinese
            ? `我查不到「${decision.placeName}」的地點資料 — 名字再給我精確一點?`
            : `I couldn't find details for "${decision.placeName}" — got a more exact name?`;
        }
      } else if (decision.kind === "order_advice") {
        // What to order: ground it in the post the user saved this place from.
        const match = places.find(
          (p) =>
            p.name.toLowerCase().includes(decision.placeName.toLowerCase()) ||
            decision.placeName.toLowerCase().includes(p.name.toLowerCase()),
        );
        let advice: string | null = null;
        let source = "none";
        // 1. If they SAVED this place, ground it in the post they saved it from
        //    (the most personal signal — usually why they saved it).
        if (match?.sourceUrl && deps.gemini) {
          try {
            const caption = (await fetchLinkCaption(match.sourceUrl, deps.fetchText)).caption;
            if (caption) advice = await suggestOrderFromCaption(decision.placeName, caption, deps.gemini, chinese);
            if (advice) source = "saved-post";
          } catch (fetchErr) {
            console.error("[sendblue] order_advice caption fetch error", fetchErr);
          }
        }
        // 2. Otherwise (e.g. a place the bot just RECOMMENDED, not saved) ground it
        //    in Google reviews / editorial summary.
        if (!advice && deps.gemini) {
          const reviewsFn = deps.placesReviews ?? defaultPlacesReviews;
          try {
            const evidence = await reviewsFn(decision.placeName);
            if (evidence) advice = await suggestOrderFromReviews(decision.placeName, evidence, deps.gemini, chinese);
            if (advice) source = "reviews";
          } catch (reviewsErr) {
            console.error("[sendblue] order_advice reviews error", reviewsErr);
          }
        }
        console.log(`[sendblue] order_advice "${decision.placeName}" source=${source} hasAdvice=${!!advice}`);
        if (advice) {
          reply = advice;
        } else {
          reply = chinese
            ? `${decision.placeName} 我目前找不到明確的招牌餐 😅 要不要我幫你查地址/card?`
            : `I couldn't find a clear must-order for ${decision.placeName} 😅 — want its address/card instead?`;
        }
      } else if (decision.kind === "location") {
        // Pure location, nothing pending → store it and ask what they want,
        // instead of a hollow "I'll remember" that loses the area.
        convoStore.setArea(memoryKey, decision.area);
        console.log(`[sendblue] location set for ${from} area="${decision.area}"`);
        reply = chinese
          ? `📍 收到,你在 ${decision.area} 附近 — 要找什麼?(咖啡、吃的、酒吧…)`
          : `📍 Got it, you're near ${decision.area} — what are you looking for? (coffee, food, a bar…)`;
      } else if (decision.kind === "reply") {
        convoStore.clearPending(memoryKey);
        console.log(
          `[sendblue] agentic reply for ${from} placeCount=${places.length} recentPlaces=${convo?.lastPlaces?.length ?? 0}`,
        );
        reply = decision.reply;
      } else if (!(decision.area ?? convo?.lastArea)) {
        // Wants nearby but we have NO location at all → remember query, ask where.
        convoStore.setPending(memoryKey, decision.query);
        console.log(`[sendblue] discovery wants location from ${from} (pending="${decision.query}")`);
        reply = askLocationReply(chinese);
      } else {
        // Discovery: search near the given area, OR — deterministically — the
        // last location we already know, so we never re-ask once we have it.
        const area = decision.area ?? convo!.lastArea!;
        convoStore.clearPending(memoryKey);
        const search = deps.placesSearch ?? defaultPlacesSearch;
        let found: DiscoveredPlace[] = [];
        try {
          found = await search(`${decision.query} in ${area}`);
        } catch (searchError) {
          console.error("[sendblue] places search error", searchError);
        }
        // A specific street address can make Google return the address ITSELF as
        // a "place" (a geocode/premise, no rating). Never recommend the user's own
        // location back to them — drop any result that is just the searched area.
        const businesses = found.filter((p) => !isSearchedAddress(p, area));
        // Personalized: skip places already recommended this conversation AND
        // places the user already knows (saved/visited), taste-rank, take a few.
        const exclude = [...(convo?.shownNames ?? []), ...taste.knownNames];
        const picks = rankPlaces(businesses, exclude, taste.preferredCategories).slice(0, 3);
        console.log(
          `[sendblue] discovery query="${decision.query}" area="${area}" results=${found.length} picks=[${picks.map((p) => p.name).join(" | ")}] known=${taste.knownNames.length} cats=[${taste.preferredCategories.join(",")}]` +
            (convo?.pendingQuery ? " (resumed pending)" : "") +
            (!decision.area && convo?.lastArea ? " (reused area)" : ""),
        );
        if (picks.length) {
          // Remember location + what we recommended for follow-ups / "something else".
          convoStore.setArea(memoryKey, area);
          convoStore.setPlaces(memoryKey, picks);
          convoStore.setRecommended(memoryKey, picks[0]); // the top pick is "the" place for follow-ups
          for (const p of picks) convoStore.addShown(memoryKey, p.name);
          reply = await phraseRecommendations(
            decision.query,
            area,
            picks,
            {
              categories: taste.preferredCategories,
              visited: visitedMerchants,
              saved: places.map((p) => p.name),
            },
            deps.gemini,
            chinese,
          );
        } else {
          reply = noDiscoveryReply(area, chinese);
        }
      }
     } else {
      // No LLM injected (e.g. tests): deterministic keyword recall.
      reply = await keywordRecallReply(text, memoryKey, chinese, deps.store, deps.mySavesUrl);
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
