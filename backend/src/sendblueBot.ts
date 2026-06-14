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
import type { SavedPlace, SendbluePlaceStore } from "./sendbluePlaceStore.js";

const geminiEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models";
const defaultGeminiModel = "gemini-3.5-flash";
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

async function defaultGeminiText(prompt: string): Promise<string> {
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
  client: Pick<SendblueClient, "sendMessage" | "markRead" | "sendTypingIndicator">;
  store: SendbluePlaceStore;
};

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
  // fetch + extract. These never throw into the main flow (client wraps them),
  // so a Sendblue outage here can't block the reply.
  await deps.client.markRead(from);
  await deps.client.sendTypingIndicator(from);

  const chinese = looksChinese(text);
  let reply: string;
  try {
    const url = firstUrlInText(text);
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
    } else {
      // No URL: recall/recommend flow. Detect an area by matching the user's OWN
      // saved areas against the text (no GPS — area is text-based on their data).
      let savedAreas: string[] = [];
      try {
        savedAreas = await deps.store.distinctAreas(from);
      } catch (storeError) {
        console.error("[sendblue] store.distinctAreas error", storeError);
      }
      const area = detectArea(text, savedAreas);

      if (isRecommendIntent(text)) {
        // Recommend: pick ONE saved place (area-filtered if detected, else all).
        let places: SavedPlace[];
        try {
          places = await deps.store.list(from, area ? { area } : undefined);
        } catch (storeError) {
          console.error("[sendblue] store.list error", storeError);
          places = [];
        }
        const picked = pickRecommendation(places);
        console.log(
          `[sendblue] recommend intent area=${area ?? "(any)"} picked=${picked?.name ?? "(none)"}`,
        );
        if (picked) {
          reply = formatRecommendReply(picked, chinese);
        } else if (area) {
          reply = formatNoAreaMatch(area, chinese);
        } else {
          reply = emptyListReply;
        }
      } else if (isListIntent(text) || isBareAreaMention(text, area)) {
        // List flow: a "show me my places" intent OR a bare area mention.
        let places: SavedPlace[];
        try {
          places = await deps.store.list(from, area ? { area } : undefined);
        } catch (storeError) {
          console.error("[sendblue] store.list error", storeError);
          places = [];
        }
        console.log(`[sendblue] list intent for ${from} area=${area ?? "(any)"} count=${places.length}`);
        reply = area ? formatAreaList(places, area, chinese) : formatPlaceList(places, chinese);
      } else {
        console.log("[sendblue] no URL / no recommend / no list intent → hint");
        reply = noUrlReply;
      }
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
