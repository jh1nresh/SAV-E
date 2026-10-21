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
): Promise<void> {
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
    return;
  }

  const { rows } = await client.query(
    "select count(*)::int as count from places where user_id = $1",
    [userId],
  );
  const savedPlaceCount = Number(rows[0]?.count ?? 0);
  if (decideSavedPlaceInsert({ tier, savedPlaceCount, isNewPlace: true }) === "over_free_limit") {
    throw new SavedPlaceLimitError();
  }
}

export function isSavedPlaceLimitError(error: unknown): error is SavedPlaceLimitError {
  return error instanceof SavedPlaceLimitError;
}
