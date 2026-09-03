export type JsonObject = Record<string, unknown>;

export type SaveSocialLens = "forYou" | "friends" | "trending";
export type FollowSource = "manual" | "referral" | "app_clip_handoff";
export type PlaceVisibility = "private" | "friends" | "public_link" | "public_guide";

const lenses = new Set<SaveSocialLens>(["forYou", "friends", "trending"]);
const followSources = new Set<FollowSource>(["manual", "referral", "app_clip_handoff"]);
const visibilities = new Set<PlaceVisibility>(["private", "friends", "public_link", "public_guide"]);

export interface FollowRequest {
  followingId?: string;
  handle?: string;
  referralCode?: string;
  lens: SaveSocialLens;
  source: FollowSource;
}

export interface VisibilityRequest {
  visibility: PlaceVisibility;
  allowFriendSignal: boolean;
  allowTrendingSignal: boolean;
}

export interface CommunityRecommendationSignal extends JsonObject {
  kind: "community_recommendation";
  lens: "forYou";
  friendNames: never[];
  friendCount: 0;
  saveCount: 0;
  trendingRank: null;
  categoryRank: null;
  sourceLabel: string;
  referrerId: string | null;
  referralCode: null;
}

export function parseLens(value: unknown, fallback: SaveSocialLens = "friends"): SaveSocialLens {
  return typeof value === "string" && lenses.has(value as SaveSocialLens)
    ? value as SaveSocialLens
    : fallback;
}

export function normalizeFollowRequest(body: JsonObject): FollowRequest {
  const referralCode = stringValue(body.referral_code);
  return {
    followingId: stringValue(body.following_id),
    handle: normalizedHandle(body.handle),
    referralCode,
    lens: parseLens(body.lens, "friends"),
    source: parseFollowSource(body.source, referralCode ? "referral" : "manual"),
  };
}

export function normalizeVisibilityRequest(body: JsonObject): VisibilityRequest {
  const visibility = parseVisibility(body.visibility);
  const isPrivate = visibility === "private";
  return {
    visibility,
    allowFriendSignal: isPrivate ? false : booleanValue(body.allow_friend_signal),
    allowTrendingSignal: isPrivate ? false : booleanValue(body.allow_trending_signal),
  };
}

export function socialSignalKindForLens(lens: SaveSocialLens): "friend_saved" | "trending" {
  return lens === "trending" ? "trending" : "friend_saved";
}

export function publicRecommendationRow(row: JsonObject): JsonObject {
  return {
    ...row,
    note: null,
    source_image_url: null,
    source_url: publicRecommendationSourceURL(row.source_url),
  };
}

export function communityRecommendationSignal(
  sourceLabel: string,
  referrerId: string | null,
): CommunityRecommendationSignal {
  return {
    kind: "community_recommendation",
    lens: "forYou",
    friendNames: [],
    friendCount: 0,
    saveCount: 0,
    trendingRank: null,
    categoryRank: null,
    sourceLabel,
    referrerId,
    referralCode: null,
  };
}

function parseFollowSource(value: unknown, fallback: FollowSource): FollowSource {
  return typeof value === "string" && followSources.has(value as FollowSource)
    ? value as FollowSource
    : fallback;
}

function parseVisibility(value: unknown): PlaceVisibility {
  return typeof value === "string" && visibilities.has(value as PlaceVisibility)
    ? value as PlaceVisibility
    : "private";
}

function booleanValue(value: unknown): boolean {
  return value === true;
}

function normalizedHandle(value: unknown): string | undefined {
  const text = stringValue(value);
  return text?.replace(/^@+/, "").toLowerCase();
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function publicRecommendationSourceURL(value: unknown): string | null {
  const text = stringValue(value);
  if (!text || text.length > 2_048) return null;
  try {
    const url = new URL(text);
    if ((url.protocol !== "https:" && url.protocol !== "http:") ||
        !url.hostname || url.username || url.password) return null;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
