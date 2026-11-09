// Device check-in contract for Savvy v2-a.
// The server may store a verdict, a time, and a place id.
// It must not store the user's coordinates.

export const inkVisitVerifications = ["verified", "unverified"] as const;
export const inkVisitVisibilities = ["public", "private"] as const;

export const inkRadiusMeters = 150;
export const inkMaxAccuracyMeters = 100;
export const inkSamePlaceWindowMs = 6 * 60 * 60 * 1000;
export const inkDailyVerifiedCap = 20;
export const inkMaxSpeedKmh = 300;

const forbiddenKeys = new Set([
  "latitude",
  "longitude",
  "lat",
  "lng",
  "coordinate",
  "coordinates",
  "horizontalaccuracy",
  "altitude",
  "course",
  "speed",
]);

export class InkVisitContractError extends Error {}

export type InkVisitVerification = (typeof inkVisitVerifications)[number];
export type InkVisitVisibility = (typeof inkVisitVisibilities)[number];

export interface InkVisitRecord {
  placeId: string;
  visitedAt: string;
  verification: InkVisitVerification;
  visibility: InkVisitVisibility;
  comment: string;
}

export interface InkFriendVisit {
  authorId: string;
  placeId: string;
  visitedAt: string;
  verification: InkVisitVerification;
  visibility: InkVisitVisibility;
}

export interface InkFriendCard {
  authorId: string;
  placeId: string;
  verifiedCount: number;
  latestAt: string;
  segment: "verified" | "unverified";
}

type JsonBody = Record<string, unknown>;

export function normalizeInkVisit(body: JsonBody): InkVisitRecord {
  for (const key of Object.keys(body)) {
    if (forbiddenKeys.has(key.toLowerCase())) {
      throw new InkVisitContractError("coordinates are not stored");
    }
  }
  const verification = oneOf(body.verification, inkVisitVerifications, "verification");
  const visibility = oneOf(
    body.visibility ?? "public",
    inkVisitVisibilities,
    "visibility",
  );
  return {
    placeId: requiredString(body.placeId, "placeId"),
    visitedAt: requiredString(body.visitedAt, "visitedAt"),
    verification,
    visibility,
    comment: typeof body.comment === "string" ? body.comment.trim() : "",
  };
}

export function rankInkFriendVisits(visits: readonly InkFriendVisit[]): InkFriendCard[] {
  const visible = visits.filter((visit) => visit.visibility === "public");
  const groups = new Map<string, InkFriendVisit[]>();
  for (const visit of visible) {
    const key = `${visit.authorId}|${visit.placeId}`;
    const bucket = groups.get(key) ?? [];
    bucket.push(visit);
    groups.set(key, bucket);
  }
  const cards: InkFriendCard[] = [];
  for (const [key, bucket] of groups) {
    const [authorId, placeId] = key.split("|");
    const verified = bucket.filter((visit) => visit.verification === "verified");
    const segment = verified.length > 0 ? "verified" : "unverified";
    const pool = segment === "verified" ? verified : bucket;
    const latest = pool.reduce((best, visit) =>
      visit.visitedAt > best.visitedAt ? visit : best,
    );
    cards.push({
      authorId,
      placeId,
      verifiedCount: verified.length,
      latestAt: latest.visitedAt,
      segment,
    });
  }
  return cards.sort((lhs, rhs) => {
    if (lhs.segment !== rhs.segment) return lhs.segment === "verified" ? -1 : 1;
    if (lhs.segment === "verified" && lhs.verifiedCount !== rhs.verifiedCount) {
      return rhs.verifiedCount - lhs.verifiedCount;
    }
    if (lhs.latestAt !== rhs.latestAt) return rhs.latestAt > lhs.latestAt ? 1 : -1;
    return lhs.authorId < rhs.authorId ? -1 : 1;
  });
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], field: string): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new InkVisitContractError(`${field} is invalid`);
  }
  return value as T;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new InkVisitContractError(`${field} is required`);
  }
  return value.trim();
}
