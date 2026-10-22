import type { Pool } from "pg";
import { entitlementTier, isEntitlementSchemaUnavailable } from "./entitlementPersistence.js";

export const freeSavedPlaceLimit = 50;

export type SavedPlaceLimitDecision = "allowed" | "over_free_limit";

export type SavedPlaceLimitBody = {
  error: "saved_place_limit";
  code: "over_free_limit";
  limit: number;
};

/// Free: 50 confirmed places. Pro is unlimited. Existing accounts already
/// over 50 keep every row; only a *new* insert is gated. Dedup / same-id
/// retries are not new inserts.
export function decideSavedPlaceInsert(input: {
  tier: "free" | "pro";
  savedPlaceCount: number;
  isNewPlace: boolean;
  limit?: number;
}): SavedPlaceLimitDecision {
  if (!input.isNewPlace) return "allowed";
  if (input.tier === "pro") return "allowed";
  const limit = input.limit ?? freeSavedPlaceLimit;
  return input.savedPlaceCount < limit ? "allowed" : "over_free_limit";
}

export class SavedPlaceLimitError extends Error {
  readonly status = 403;
  readonly code = "over_free_limit" as const;
  readonly body: SavedPlaceLimitBody;

  constructor(limit: number = freeSavedPlaceLimit) {
    super("saved_place_limit");
    this.body = { error: "saved_place_limit", code: "over_free_limit", limit };
  }
}

type Queryable = Pick<Pool, "query">;

/// Caller must already hold a per-user transaction lock so the count and
/// insert cannot race a second save past the free cap.
export async function assertNewSavedPlaceAllowed(
  client: Queryable,
  userId: string,
  incomingPlace?: SavedPlaceIdentity,
): Promise<void> {
  const tier = await savedPlaceTierForTransaction(client, userId);
  if (tier === undefined) return;

  if (tier === "pro") return;
  const { rows } = await client.query(
    `select id, name, address, latitude, longitude, google_place_id,
       coordinate_system, location_provider, provider_place_id, created_at
     from places where user_id = $1 order by created_at, id`,
    [userId],
  );
  const canonicalCount = consolidatedSavedPlaces(rows).length;
  // Compare the complete projected collection. A backdated incoming row can
  // become the first representative and change which rows consolidate.
  const projectedCount = incomingPlace
    ? consolidatedSavedPlaces([...rows, { ...incomingPlace, created_at: incomingPlace.created_at ?? new Date() }]).length
    : canonicalCount + 1;
  const isNewPlace = projectedCount > canonicalCount;
  const savedPlaceCount = Math.max(canonicalCount, projectedCount - 1);
  if (decideSavedPlaceInsert({ tier, savedPlaceCount, isNewPlace }) === "over_free_limit") {
    throw new SavedPlaceLimitError();
  }
}

async function savedPlaceTierForTransaction(
  client: Queryable, userId: string,
): Promise<"free" | "pro" | undefined> {
  let tier: "free" | "pro" = "free";
  // Probe inside a savepoint. A missing entitlement table/column aborts the
  // surrounding transaction in PostgreSQL; without this, every save 500s.
  await client.query("savepoint saved_place_entitlement");
  try {
    tier = await entitlementTier(client, userId);
    await client.query("release savepoint saved_place_entitlement");
  } catch (error) {
    await client.query("rollback to savepoint saved_place_entitlement");
    if (!isEntitlementSchemaUnavailable(error)) throw error;
    // Schema missing: cannot tell Pro from Free. Fail open like
    // ai_usage_events — do not apply the free cap as if every account is free.
    return undefined;
  }

  return tier;
}

/** Caller holds the raw-owner advisory transaction lock before any row locks.
 * Snapshot the canonical count so legacy over-limit accounts can still make
 * changes that do not grow their collection. Undefined preserves Pro/fail-open. */
export async function savedPlaceGrowthSnapshot(client: Queryable, userId: string): Promise<number | undefined> {
  const tier = await savedPlaceTierForTransaction(client, userId);
  if (tier !== "free") return undefined;
  return consolidatedSavedPlaces((await client.query(
    `select id, name, address, latitude, longitude, google_place_id,
       coordinate_system, location_provider, provider_place_id, created_at
     from places where user_id = $1 order by created_at, id`, [userId],
  )).rows).length;
}

/** Check actual tentative database rows before the existing transaction commits.
 * Any failure must roll back the whole transaction, including capture provenance. */
export async function assertSavedPlaceGrowthAllowed(
  client: Queryable, userId: string, previousCount: number | undefined,
): Promise<void> {
  if (previousCount === undefined) return;
  const projectedCount = consolidatedSavedPlaces((await client.query(
    `select id, name, address, latitude, longitude, google_place_id,
       coordinate_system, location_provider, provider_place_id, created_at
     from places where user_id = $1 order by created_at, id`, [userId],
  )).rows).length;
  if (projectedCount > previousCount && projectedCount > freeSavedPlaceLimit) throw new SavedPlaceLimitError();
}

/** Update under the same owner lock as inserts. Project from the database's
 * RETURNING row, not raw request fields: SQL owns writable-field filtering,
 * numeric coercion and earliest-created_at semantics. Rejection rolls back
 * the tentative update before any commit or response. */
export async function updateSavedPlaceWithinLimit(
  database: Pick<Pool, "connect">,
  userId: string,
  placeId: string,
  update: { sql: string; values: unknown[] },
): Promise<Record<string, unknown> | undefined> {
  const client = await database.connect();
  try {
    await client.query("begin");
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [userId]);
    const current = await client.query(
      "select * from places where id = $1 and user_id = $2 for update",
      [placeId, userId],
    );
    if (!current.rows[0]) {
      await client.query("rollback");
      return undefined;
    }
    const before = await savedPlaceGrowthSnapshot(client, userId);
    const values = [...update.values, placeId, userId];
    const result = await client.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    const replacement: Record<string, unknown> | undefined = result.rows[0];
    if (!replacement) {
      await client.query("rollback");
      return undefined;
    }
    await assertSavedPlaceGrowthAllowed(client, userId, before);
    await client.query("commit");
    return replacement;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

export function isSavedPlaceLimitError(error: unknown): error is SavedPlaceLimitError {
  return error instanceof SavedPlaceLimitError;
}

// Mirrors Place.matches / Place.consolidated: provider identity is authoritative;
// only missing identity falls back to normalized name and location/address.
export type SavedPlaceIdentity = {
  id?: unknown; name?: unknown; address?: unknown;
  latitude?: unknown; longitude?: unknown; google_place_id?: unknown;
  coordinate_system?: unknown; location_provider?: unknown; provider_place_id?: unknown;
  created_at?: unknown;
};

function nonEmpty(value: unknown): string | undefined {
  return typeof value === "string" ? value.trim() || undefined : undefined;
}

function normalized(value: unknown): string {
  return typeof value === "string"
    ? value.normalize("NFKD").toLowerCase().replace(/ß/g, "ss").replace(/ς/g, "σ")
      .replace(/[^\p{L}\p{N}]/gu, "")
    : "";
}

function coordinate(place: SavedPlaceIdentity): [number, number] | undefined {
  const { latitude, longitude } = place;
  if (typeof latitude !== "number" || typeof longitude !== "number"
    || !Number.isFinite(latitude) || !Number.isFinite(longitude)
    || Math.abs(latitude) > 90 || Math.abs(longitude) > 180
    || (latitude === 0 && longitude === 0)) return undefined;
  return [latitude, longitude];
}

// WGS84 inverse geodesic (Vincenty). Unlike a spherical distance, this keeps
// the app's 120 m boundary at high latitudes. Nonconvergent antipodal points
// are necessarily far outside this identity radius.
function distanceMeters(left: [number, number], right: [number, number]): number {
  const radians = Math.PI / 180, a = 6378137, f = 1 / 298.257223563, b = (1 - f) * a;
  const u1 = Math.atan((1 - f) * Math.tan(left[0] * radians));
  const u2 = Math.atan((1 - f) * Math.tan(right[0] * radians));
  const L = (right[1] - left[1]) * radians;
  let lambda = L, sinSigma = 0, cosSigma = 0, sigma = 0, cosSqAlpha = 0, cos2SigmaM = 0;
  for (let i = 0; i < 100; i++) {
    const sinLambda = Math.sin(lambda), cosLambda = Math.cos(lambda);
    sinSigma = Math.hypot(Math.cos(u2) * sinLambda,
      Math.cos(u1) * Math.sin(u2) - Math.sin(u1) * Math.cos(u2) * cosLambda);
    if (sinSigma === 0) return 0;
    cosSigma = Math.sin(u1) * Math.sin(u2) + Math.cos(u1) * Math.cos(u2) * cosLambda;
    sigma = Math.atan2(sinSigma, cosSigma);
    const sinAlpha = Math.cos(u1) * Math.cos(u2) * sinLambda / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    cos2SigmaM = cosSqAlpha === 0 ? 0 : cosSigma - 2 * Math.sin(u1) * Math.sin(u2) / cosSqAlpha;
    const C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha));
    const previous = lambda;
    lambda = L + (1 - C) * f * sinAlpha * (sigma + C * sinSigma
      * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
    if (Math.abs(lambda - previous) <= 1e-12) {
      const uSq = cosSqAlpha * (a * a - b * b) / (b * b);
      const A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
      const B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
      const delta = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma
        * (-1 + 2 * cos2SigmaM ** 2) - B / 6 * cos2SigmaM
        * (-3 + 4 * sinSigma ** 2) * (-3 + 4 * cos2SigmaM ** 2)));
      return b * A * (sigma - delta);
    }
  }
  return Infinity;
}

export function savedPlacesMatch(left: SavedPlaceIdentity, right: SavedPlaceIdentity): boolean {
  if (nonEmpty(left.id) && left.id === right.id) return true;
  const lp = nonEmpty(left.provider_place_id), rp = nonEmpty(right.provider_place_id);
  if (left.location_provider != null && left.location_provider === right.location_provider && lp && rp) return lp === rp;
  const lg = nonEmpty(left.google_place_id), rg = nonEmpty(right.google_place_id);
  if (lg && rg) return lg === rg;
  const name = normalized(left.name);
  if (!name || name !== normalized(right.name)) return false;
  const lc = coordinate(left), rc = coordinate(right);
  if (lc && rc) {
    if ((left.coordinate_system ?? "WGS84") !== (right.coordinate_system ?? "WGS84")) return false;
    return distanceMeters(lc, rc) < 120;
  }
  const address = normalized(left.address);
  return !!address && address === normalized(right.address);
}

export type SavedPlaceGroup = { representative: SavedPlaceIdentity; memberIDs: string[] };

// Keep membership alongside the exact same ordered representative matching used
// for collection counts. Do not transitively merge groups through a later alias.
export function consolidatedSavedPlaceGroups(places: SavedPlaceIdentity[]): SavedPlaceGroup[] {
  const result: SavedPlaceGroup[] = [];
  const timestamp = (value: unknown) => value instanceof Date ? value.getTime() : new Date(String(value)).getTime() || 0;
  for (const place of [...places].sort((a, b) => timestamp(a.created_at) - timestamp(b.created_at)
    || String(a.id).localeCompare(String(b.id)))) {
    const existing = result.find(group => savedPlacesMatch(group.representative, place));
    const memberID = typeof place.id === "string" ? place.id : undefined;
    if (existing) {
      // Place.mergingSources retains the original venue fields and fills only
      // a missing Google identity; empty strings are preserved just as in Swift.
      existing.representative.google_place_id ??= place.google_place_id;
      if (memberID !== undefined) existing.memberIDs.push(memberID);
    } else result.push({ representative: { ...place }, memberIDs: memberID === undefined ? [] : [memberID] });
  }
  return result;
}

export function consolidatedSavedPlaces(places: SavedPlaceIdentity[]): SavedPlaceIdentity[] {
  return consolidatedSavedPlaceGroups(places).map(group => group.representative);
}

/** Delete the displayed venue, including its saved aliases, atomically. The app
 * already deletes every savedID in that venue. Missing/previously deleted IDs
 * are successful no-ops so older clients can finish their sequential requests. */
export async function deleteSavedPlaceGroup(
  database: Pick<Pool, "connect">, userId: string, placeId: string,
): Promise<void> {
  const client = await database.connect();
  try {
    await client.query("begin");
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [userId]);
    const current = await client.query(
      "select * from places where id = $1 and user_id = $2 for update", [placeId, userId],
    );
    if (current.rows[0]) {
      const { rows } = await client.query(
        `select id, name, address, latitude, longitude, google_place_id,
           coordinate_system, location_provider, provider_place_id, created_at
         from places where user_id = $1 order by created_at, id`, [userId],
      );
      // Use the database's canonical UUID spelling, not the raw request ID.
      const group = consolidatedSavedPlaceGroups(rows).find(value => value.memberIDs.includes(current.rows[0].id));
      if (!group) throw new Error("Owned saved place missing from its canonical group");
      await client.query("delete from places where user_id = $1 and id = any($2::uuid[])", [userId, group.memberIDs]);
    }
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
