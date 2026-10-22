export const FREE_LIST_SAVE_LIMIT = 50;

export type ClipListSavePlan = {
  toInsert: Record<string, unknown>[];
  alreadyExisting: Record<string, unknown>[];
  newlySaved: number;
  alreadySaved: number;
  overCap: number;
  remaining: number;
  limit: number;
};

export function clipListPlaceIdentities(place: {
  id?: unknown;
  name?: unknown;
  latitude?: unknown;
  longitude?: unknown;
  google_place_id?: unknown;
  provider_place_id?: unknown;
}): string[] {
  const keys: string[] = [];
  if (typeof place.id === "string" && place.id.trim()) {
    keys.push(`id:${place.id.trim().toLowerCase()}`);
  }
  const google = typeof place.google_place_id === "string" ? place.google_place_id.trim() : "";
  const provider = typeof place.provider_place_id === "string" ? place.provider_place_id.trim() : "";
  if (google) {
    keys.push(`g:${google}`);
    keys.push(`p:${google}`);
  }
  if (provider) {
    keys.push(`p:${provider}`);
    keys.push(`g:${provider}`);
  }
  const name = String(place.name ?? "").trim().toLowerCase();
  const lat = Number(place.latitude);
  const lng = Number(place.longitude);
  if (name && Number.isFinite(lat) && Number.isFinite(lng)) {
    keys.push(`n:${name}|${lat.toFixed(4)}|${lng.toFixed(4)}`);
  }
  return keys;
}

function isPlaceObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function mergeClipListPlace(
  kept: Record<string, unknown>,
  incoming: Record<string, unknown>,
): Record<string, unknown> {
  const result = { ...kept };
  const taken = new Set(
    [result.id, result.provider_place_id, result.google_place_id]
      .filter((value): value is string => typeof value === "string" && value.trim() !== "")
      .map((value) => value.trim()),
  );
  for (const field of ["provider_place_id", "google_place_id", "id"] as const) {
    const value = incoming[field];
    if (typeof value !== "string" || !value.trim()) continue;
    const trimmed = value.trim();
    if (taken.has(trimmed)) continue;
    if (
      (typeof result.provider_place_id !== "string" || !String(result.provider_place_id).trim())
      && (typeof result.id !== "string" || !String(result.id).trim())
    ) {
      result.provider_place_id = trimmed;
      taken.add(trimmed);
      continue;
    }
    if (typeof result.google_place_id !== "string" || !String(result.google_place_id).trim()) {
      result.google_place_id = trimmed;
      taken.add(trimmed);
    }
  }
  return result;
}

/// Collapse transitive duplicates (A↔B↔C) into one retained item.
export function uniqueClipListItems(items: unknown[]): Record<string, unknown>[] {
  const indexByKey = new Map<string, number>();
  let unique: Record<string, unknown>[] = [];
  for (const raw of items) {
    if (!isPlaceObject(raw)) continue;
    const keys = clipListPlaceIdentities(raw);
    if (keys.length === 0) continue;
    const matched = [...new Set(keys.map((key) => indexByKey.get(key)).filter((index): index is number => index !== undefined))]
      .sort((left, right) => left - right);
    if (matched.length === 0) {
      const index = unique.length;
      unique.push({ ...raw });
      for (const key of keys) indexByKey.set(key, index);
      continue;
    }
    const keep = matched[0];
    let merged = mergeClipListPlace(unique[keep], raw);
    for (const other of matched.slice(1)) {
      merged = mergeClipListPlace(merged, unique[other]);
    }
    unique[keep] = merged;
    if (matched.length === 1) {
      for (const key of clipListPlaceIdentities(merged)) indexByKey.set(key, keep);
      continue;
    }
    const remove = new Set(matched.slice(1));
    unique = unique.filter((_, index) => !remove.has(index));
    indexByKey.clear();
    unique.forEach((item, index) => {
      for (const key of clipListPlaceIdentities(item)) indexByKey.set(key, index);
    });
  }
  return unique;
}

/// SL1: walk the list once, skip intra-list and account duplicates first.
/// SL2: fill remaining free slots in list order; overflow is over_cap (#293 B).
export function planClipListSave(input: {
  items: unknown[];
  existingIdentities: Iterable<string>;
  existingPlaces?: Record<string, unknown>[];
  savedPlaceCount: number;
  limit?: number;
}): ClipListSavePlan {
  const limit = input.limit ?? FREE_LIST_SAVE_LIMIT;
  const existing = new Set(input.existingIdentities);
  const rowByKey = new Map<string, Record<string, unknown>>();
  for (const row of input.existingPlaces ?? []) {
    for (const key of clipListPlaceIdentities(row)) {
      if (!rowByKey.has(key)) rowByKey.set(key, row);
    }
  }
  const countable = input.items.filter((raw) => isPlaceObject(raw) && clipListPlaceIdentities(raw).length > 0);
  const unique = uniqueClipListItems(input.items);
  let alreadySaved = Math.max(0, countable.length - unique.length);
  const alreadyExisting: Record<string, unknown>[] = [];
  const novel: Record<string, unknown>[] = [];

  for (const raw of unique) {
    const identities = clipListPlaceIdentities(raw);
    if (identities.some((key) => existing.has(key))) {
      alreadySaved += 1;
      const matched = identities.map((key) => rowByKey.get(key)).find(Boolean);
      if (matched && !alreadyExisting.includes(matched)) {
        alreadyExisting.push(matched);
      }
      continue;
    }
    novel.push(raw);
  }

  const remainingSlots = Math.max(0, limit - Math.max(0, input.savedPlaceCount));
  const toInsert = novel.slice(0, remainingSlots);
  return {
    toInsert,
    alreadyExisting,
    newlySaved: toInsert.length,
    alreadySaved,
    overCap: novel.length - toInsert.length,
    remaining: remainingSlots - toInsert.length,
    limit,
  };
}

/// One confirmed place: insert, already saved, or cap. Fail closed.
export function clipOnePlaceQuotaDecision(
  plan: ClipListSavePlan,
): "insert" | "duplicate" | "cap" {
  if (plan.newlySaved > 0) return "insert";
  if (plan.alreadySaved > 0) return "duplicate";
  return "cap";
}

export const clipSavedPlaceLimitBody = {
  error: "saved_place_limit",
  code: "over_free_limit",
  limit: FREE_LIST_SAVE_LIMIT,
} as const;

export type ClipListSavedIdentity = {
  id: string;
  provider_place_id?: string;
  name?: string;
  latitude?: number;
  longitude?: number;
  category?: string;
};

export function clipListSavedIdentity(row: Record<string, unknown>): ClipListSavedIdentity {
  const identity: ClipListSavedIdentity = { id: String(row.id ?? "") };
  if (typeof row.provider_place_id === "string" && row.provider_place_id.trim()) {
    identity.provider_place_id = row.provider_place_id;
  }
  if (typeof row.name === "string" && row.name.trim()) {
    identity.name = row.name;
  }
  const lat = Number(row.latitude);
  const lng = Number(row.longitude);
  if (Number.isFinite(lat)) identity.latitude = lat;
  if (Number.isFinite(lng)) identity.longitude = lng;
  if (typeof row.category === "string" && row.category.trim()) {
    identity.category = row.category;
  }
  return identity;
}

export function clipListSaveResponse(
  plan: ClipListSavePlan,
  inserted: Record<string, unknown>[] = [],
): {
  newly_saved: number;
  already_saved: number;
  over_cap: number;
  remaining: number;
  limit: number;
  saved: ClipListSavedIdentity[];
  already: ClipListSavedIdentity[];
} {
  return {
    newly_saved: plan.newlySaved,
    already_saved: plan.alreadySaved,
    over_cap: plan.overCap,
    remaining: plan.remaining,
    limit: plan.limit,
    saved: inserted.map(clipListSavedIdentity),
    already: plan.alreadyExisting.map(clipListSavedIdentity),
  };
}
