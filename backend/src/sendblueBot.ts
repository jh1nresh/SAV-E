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
  private readonly fromNumber: string;
  private readonly fetchImpl: SendblueFetch;
  private readonly endpoint: string;

  constructor(options?: {
    apiKeyId?: string;
    apiSecret?: string;
    fromNumber?: string;
    fetchImpl?: SendblueFetch;
    endpoint?: string;
  }) {
    this.apiKeyId = options?.apiKeyId ?? requireEnv("SENDBLUE_API_KEY_ID");
    this.apiSecret = options?.apiSecret ?? requireEnv("SENDBLUE_API_SECRET");
    // The Sendblue line the bot sends FROM (your provisioned Sendblue number).
    this.fromNumber = options?.fromNumber ?? requireEnv("SENDBLUE_FROM_NUMBER");
    this.fetchImpl = options?.fetchImpl ?? fetch;
    this.endpoint = options?.endpoint ?? "https://api.sendblue.co/api/send-message";
  }

  async sendMessage(toNumber: string, content: string): Promise<string> {
    const response = await this.fetchImpl(this.endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "sb-api-key-id": this.apiKeyId,
        "sb-api-secret-key": this.apiSecret,
      },
      body: JSON.stringify({ number: toNumber, from_number: this.fromNumber, content }),
    });
    const body = await response.text().catch(() => "");
    if (!response.ok) {
      throw new Error(`Sendblue send-message failed: ${response.status} ${body.slice(0, 400)}`);
    }
    return body;
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

export function formatVenueReply(venue: ExtractedVenue): string {
  const emoji = emojiForCategory(venue.category);
  const where = venue.area ? `${venue.name} in ${venue.area}` : venue.name;
  const second = venue.category ? `\n${venue.category}` : "";
  return `Found ${where} ${emoji}${second}`;
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
  client: Pick<SendblueClient, "sendMessage">;
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
  if (!isInboundMessage(body)) return { replied: false };

  const from = inboundFrom(body);
  const text = inboundText(body);
  if (!from || !text) return { replied: false };

  let reply: string;
  try {
    const url = firstUrlInText(text);
    if (!url) {
      reply = noUrlReply;
    } else {
      const { caption } = await fetchLinkCaption(url, deps.fetchText);
      const venue = caption ? await extractVenueFromCaption(caption, deps.gemini) : null;
      reply = venue ? formatVenueReply(venue) : noVenueReply;
    }
  } catch (error) {
    // Spike: degrade gracefully, never bubble up to the webhook.
    console.error("sendblue inbound processing error", error);
    reply = noVenueReply;
  }

  await deps.client.sendMessage(from, reply);
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
