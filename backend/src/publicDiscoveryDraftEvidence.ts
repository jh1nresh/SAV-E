import { isDeepStrictEqual } from "node:util";
import { canonicalSource, isPublicDiscoveryVenueID, validatePublicDiscoveryPlace, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { readTaipeiFeatureProof, verifyPublicTaipeiCatalogCandidate } from "./publicDiscoveryCatalogEvidence.js";
import { preflightTaipeiStreet, publicStreetKey, publicTaipeiStreetInventory,
  verifyPublicTaipeiStreetCandidate } from "./publicDiscoveryStreetEvidence.js";
import { publicProfileCandidateLimit } from "./publicDiscoveryProfileDrafts.js";
import { publicReviewEmbedURL } from "./publicPostReverification.js";
import { defaultFetchText } from "./sourceSearchWorker.js";

type Options = {
  now: Date;
  maxOriginals?: number;
  cursor?: string | null;
  backoffUntil?: number;
  fetchEmbed?: (url: string) => Promise<string>;
  localizedAddresses?: unknown;
  officialFeatures?: unknown;
};
type Platform = "instagram" | "threads";
type ReviewedVenue = {
  place: PublicDiscoveryPlace;
  candidates: {
    platform: Platform; sourceURL: string; authorHandle: string; title: string;
    review: { origin: "public_web_index"; checkedAt: string; contentFingerprint: string; branchEvidence: string };
  }[];
};

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid public draft row");
  return value as Record<string, unknown>;
}

function placeKey(row: Record<string, unknown> | PublicDiscoveryPlace): string {
  if (typeof row.provider !== "string" || !isPublicDiscoveryVenueID(row.providerPlaceID)) {
    throw new Error("Invalid trusted place identity");
  }
  return `${row.provider}:${row.providerPlaceID}`;
}

function source(candidate: Record<string, unknown>) {
  const { platform } = candidate;
  if (platform !== "instagram" && platform !== "threads") throw new Error("Unsupported public draft platform");
  const { url, postID } = canonicalSource(candidate.sourceURL, platform);
  return { url, platform, post: `${platform}:${postID}` } as const;
}

export function localizedPublicDiscoveryPlaces(
  inventory: ReadonlyMap<string, PublicDiscoveryPlace>, localized: unknown,
) {
  if (!Array.isArray(localized) || localized.length > inventory.size) throw new Error("Invalid localized address inventory");
  const evidencePlaces = new Map(inventory);
  for (const value of localized) {
    const row = record(value);
    const identity = placeKey(row);
    const place = inventory.get(identity);
    if (Object.keys(row).length !== 4 || !place || row.expectedAddress !== place.address
      || evidencePlaces.get(identity) !== place || typeof row.address !== "string" || publicStreetKey(place)) {
      throw new Error("Invalid localized address evidence");
    }
    const evidencePlace = validatePublicDiscoveryPlace({ ...place, address: row.address });
    if (!publicStreetKey(evidencePlace)) throw new Error("Localized address needs a full Taipei street number");
    evidencePlaces.set(identity, evidencePlace);
  }
  return evidencePlaces;
}

function trustedInventory(raw: unknown, localized: unknown, features: unknown) {
  if (!Array.isArray(raw)) throw new Error("Invalid trusted place inventory");
  const inventory = new Map<string, PublicDiscoveryPlace>();
  for (const value of raw) {
    const place = validatePublicDiscoveryPlace(value);
    const identity = placeKey(place);
    if (inventory.has(identity)) throw new Error("Duplicate trusted place");
    inventory.set(identity, place);
  }
  const evidencePlaces = localizedPublicDiscoveryPlaces(inventory, localized);
  if (!Array.isArray(features) || features.length > inventory.size) throw new Error("Invalid official feature inventory");
  const official = new Map<string, ReturnType<typeof readTaipeiFeatureProof>>();
  const catalogIDs = new Set<string>();
  for (const value of features) {
    const row = record(value);
    const identity = placeKey(row);
    const place = inventory.get(identity);
    if (Object.keys(row).length !== 6 || !place || official.has(identity)
      || typeof row.catalogID !== "string" || catalogIDs.has(row.catalogID)) throw new Error("Invalid official feature evidence");
    official.set(identity, readTaipeiFeatureProof(row, place));
    catalogIDs.add(row.catalogID);
  }
  return { inventory, evidencePlaces, official };
}

/** Read at most one original per unambiguous draft, before an operator commits any state. */
export async function checkStreetDrafts(
  rawArchive: unknown, reports: Iterable<unknown> | AsyncIterable<unknown>, trustedPlaces: unknown, options: Options,
) {
  const { now, maxOriginals = 30, cursor = null, fetchEmbed = defaultFetchText } = options;
  let { backoffUntil = 0 } = options;
  if (!Number.isFinite(now.getTime()) || !Number.isInteger(maxOriginals) || maxOriginals < 1 || maxOriginals > 30
    || !Number.isSafeInteger(backoffUntil) || backoffUntil < 0
    || (cursor !== null && (typeof cursor !== "string" || cursor.length > 800))) throw new Error("Invalid public review window");
  const { inventory, evidencePlaces, official } = trustedInventory(
    trustedPlaces, options.localizedAddresses ?? [], options.officialFeatures ?? [],
  );
  const colocated = publicTaipeiStreetInventory([...evidencePlaces.values()]);
  const prior = new Map<string, Set<string>>();
  const archive = record(rawArchive);
  if (!Array.isArray(archive.venues)) throw new Error("Invalid approved place archive");
  for (const value of archive.venues) {
    const { place, candidates } = record(value);
    if (!Array.isArray(candidates)) throw new Error("Invalid approved venue");
    const identity = placeKey(record(place));
    for (const value of candidates) {
      const candidate = record(value);
      if (!candidate.review) continue;
      const { post } = source(candidate);
      const identities = prior.get(post) ?? new Set<string>();
      identities.add(identity);
      prior.set(post, identities);
    }
  }

  const claimed = new Map<string, Set<string>>();
  const jobs: { place: PublicDiscoveryPlace; identity: string; post: string; url: string; platform: Platform; token: string; author?: string }[] = [];
  const seen = new Set<string>();
  const counts = { admitted: 0, alreadyIndexed: 0, branchConflict: 0, placeMismatch: 0,
    unsupportedOriginal: 0, deferred: 0, checked: 0 };
  const outcomes: Record<string, number> = {};
  for await (const value of reports) {
    const report = record(value);
    const place = validatePublicDiscoveryPlace(report.place);
    const identity = placeKey(place);
    // One saved-place report can combine profile results from Instagram and Threads.
    if (!Array.isArray(report.candidates) || report.candidates.length > 2 * publicProfileCandidateLimit) {
      throw new Error("Invalid public draft report");
    }
    for (const value of report.candidates) {
      const candidate = record(value);
      const { authorHandle } = candidate;
      if (candidate.review !== null || (authorHandle !== null
        && (typeof authorHandle !== "string" || !/^[A-Za-z0-9._]{1,30}$/.test(authorHandle)))) {
        throw new Error("Draft must contain an unapproved public source");
      }
      const { post, url, platform } = source(candidate);
      if (platform === "threads" && authorHandle
        && new URL(url).pathname.split("/")[1]!.slice(1).toLowerCase() !== authorHandle.toLowerCase()) {
        outcomes.invalid_attribution = (outcomes.invalid_attribution ?? 0) + 1;
        continue;
      }
      if (!isDeepStrictEqual(inventory.get(identity), place)) {
        counts.placeMismatch++;
        continue;
      }
      const token = JSON.stringify([identity, post]);
      if (seen.has(token)) continue;
      seen.add(token);
      const identities = claimed.get(post) ?? new Set<string>();
      identities.add(identity);
      claimed.set(post, identities);
      jobs.push({ place, identity, post, url, platform, token, ...(authorHandle ? { author: authorHandle } : {}) });
    }
  }

  const verified: ReviewedVenue[] = [];
  const ordered = jobs.sort((a, b) => a.token === b.token ? 0 : a.token < b.token ? -1 : 1);
  const position = cursor === null ? 0 : Math.max(0, ordered.findIndex(job => job.token > cursor));
  let nextCursor = cursor;
  for (const { place, identity, post, url, platform, token, author } of [...ordered.slice(position), ...ordered.slice(0, position)]) {
    const existing = prior.get(post);
    if (existing?.has(identity)) { counts.alreadyIndexed++; continue; }
    if (existing?.size || claimed.get(post)!.size !== 1) { counts.branchConflict++; continue; }
    if (platform === "instagram" && new URL(url).pathname.startsWith("/tv/")) { counts.unsupportedOriginal++; continue; }
    const evidencePlace = evidencePlaces.get(identity)!;
    const peers = colocated(evidencePlace);
    const proof = official.get(identity);
    const ineligible = proof ? undefined : preflightTaipeiStreet(evidencePlace, peers);
    if (ineligible) {
      outcomes[ineligible] = (outcomes[ineligible] ?? 0) + 1;
      continue;
    }
    if (backoffUntil > now.getTime() || counts.checked >= maxOriginals) { counts.deferred++; continue; }
    counts.checked++;
    nextCursor = token;
    let html;
    try {
      html = await fetchEmbed(publicReviewEmbedURL(platform, url));
    } catch (error) {
      if (error instanceof Error && /^(?:Provider )?HTTP (?:401|403|429)$/.test(error.message)) backoffUntil = now.getTime() + 15 * 60_000;
      outcomes.original_unavailable = (outcomes.original_unavailable ?? 0) + 1;
      continue;
    }
    const context = { html, platform, sourceURL: url, place, ...(author ? { author } : {}) };
    const evidence = proof
      ? verifyPublicTaipeiCatalogCandidate({ ...context, proof })
      : verifyPublicTaipeiStreetCandidate({ ...context, placesAtAddress: peers, evidenceAddress: evidencePlace.address });
    outcomes[evidence.status] = (outcomes[evidence.status] ?? 0) + 1;
    if (!("contentFingerprint" in evidence) || !evidence.contentFingerprint || !evidence.authorHandle) continue;
    verified.push({ place, candidates: [{ platform, sourceURL: url, authorHandle: evidence.authorHandle, title: place.name,
      review: {
        origin: "public_web_index", checkedAt: now.toISOString(), contentFingerprint: evidence.contentFingerprint,
        branchEvidence: evidence.status === "exact_catalog_feature"
          ? "Canonical public original names the same Taipei feature and links its exact official destination page."
          : "Canonical public original names the venue and its full Taipei street address. One known venue at that street number.",
      },
    }] });
    counts.admitted++;
  }
  return { verified, counts: { ...counts, outcomes, nextCursor, backoffUntil } };
}
