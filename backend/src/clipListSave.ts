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
  if (typeof place.google_place_id === "string" && place.google_place_id.trim()) {
    keys.push(`g:${place.google_place_id.trim()}`);
  }
  if (typeof place.provider_place_id === "string" && place.provider_place_id.trim()) {
    keys.push(`p:${place.provider_place_id.trim()}`);
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
  const seen = new Set<string>();
  let alreadySaved = 0;
  const alreadyExisting: Record<string, unknown>[] = [];
  const novel: Record<string, unknown>[] = [];

  for (const raw of input.items) {
    if (!isPlaceObject(raw)) continue;
    const identities = clipListPlaceIdentities(raw);
    if (identities.length === 0) continue;
    if (identities.some((key) => seen.has(key))) {
      alreadySaved += 1;
      continue;
    }
    for (const key of identities) seen.add(key);
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
