import assert from "node:assert/strict";
import { canonicalSource, validatePublicDiscoveryManifest, validatePublicDiscoveryPlace, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import type { checkStreetDrafts } from "./publicDiscoveryDraftEvidence.js";
import { activateReviewGeneration, isDigest, record, resumeReviewGeneration, type ReadInventoryRevision } from "./publicDiscoveryGenerationTransition.js";
import { approvedSourceState, readActiveApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { compileApprovedPublicBatch } from "./publicDiscoveryReviewedBatch.js";

type DraftCheck = Awaited<ReturnType<typeof checkStreetDrafts>>;
type Receipt = DraftCheck["counts"] & { checkedAt: string; baseIndexSHA256: string };
type Options = {
  now: Date;
  clock?: () => Date;
  verify: (archive: unknown) => Promise<DraftCheck>;
  inventory?: { revision: string; currentRevision: ReadInventoryRevision };
};

const journal = "pending-admission.json";
const placeKey = (place: PublicDiscoveryPlace) => `${place.provider}:${place.providerPlaceID}`;

function sourceID(raw: unknown) {
  const row = record(raw);
  if (row.platform !== "instagram" && row.platform !== "threads") throw new Error("Unsupported draft source platform");
  return `${row.platform}:${canonicalSource(row.sourceURL, row.platform).postID}`;
}

function replayReceipt(value: unknown, baseIndexSHA256: string, checkedAt: string): Receipt {
  const row = record(value);
  if (row.baseIndexSHA256 !== baseIndexSHA256 || row.checkedAt !== checkedAt
    || (row.nextCursor !== null && (typeof row.nextCursor !== "string" || row.nextCursor.length > 800))) {
    throw new Error("Invalid draft approval receipt");
  }
  const counters = [
    "admitted", "alreadyIndexed", "branchConflict", "placeMismatch", "unsupportedOriginal", "deferred", "checked", "backoffUntil",
  ] as const;
  if (Object.keys(row).length !== counters.length + 4) throw new Error("Invalid draft approval receipt fields");
  for (const field of counters) {
    if (typeof row[field] !== "number" || !Number.isSafeInteger(row[field]) || row[field] < 0) {
      throw new Error("Invalid draft approval counter");
    }
  }
  const outcomes = record(row.outcomes);
  if (Object.entries(outcomes).some(([key, count]) => !/^[a-z_]+$/.test(key)
    || typeof count !== "number" || !Number.isSafeInteger(count) || count < 0)) throw new Error("Invalid draft approval outcomes");
  return row as Receipt;
}

function mergeReviews(raw: unknown, verified: DraftCheck["verified"]) {
  const existing = record(raw);
  if (!Array.isArray(existing.venues)) throw new Error("Invalid active review archive");
  const additions = new Map<string, { place: PublicDiscoveryPlace; candidates: Map<string, unknown> }>();
  for (const { place, candidates } of verified) {
    const key = placeKey(place);
    const entry = additions.get(key) ?? { place, candidates: new Map<string, unknown>() };
    assert.deepEqual(place, entry.place);
    for (const candidate of candidates) {
      const id = sourceID(candidate);
      if (entry.candidates.has(id)) throw new Error("Duplicate approved draft");
      entry.candidates.set(id, candidate);
    }
    additions.set(key, entry);
  }
  const inserted = new Set<string>();
  const venues = existing.venues.flatMap((value: unknown) => {
    const row = record(value);
    const place = validatePublicDiscoveryPlace(row.place);
    const key = placeKey(place);
    const update = additions.get(key);
    if (!update) return [row];
    assert.deepEqual(place, update.place, "Draft venue differs from the reviewed identity");
    if (!Array.isArray(row.candidates)) throw new Error("Invalid active review venue");
    const candidates = row.candidates.filter((rawCandidate: unknown) => {
      if (!update.candidates.has(sourceID(rawCandidate))) return true;
      if (record(rawCandidate).review !== null) throw new Error("Draft would replace an approved source");
      return false;
    });
    if (!inserted.has(key)) candidates.push(...update.candidates.values());
    inserted.add(key);
    return candidates.length ? [{ place, candidates }] : [];
  });
  for (const [key, { place, candidates }] of additions) {
    if (!inserted.has(key)) venues.push({ place, candidates: [...candidates.values()] });
  }
  const keys = new Set([...additions].flatMap(([key, entry]) => [...entry.candidates.keys()].map(id => `${key}:${id}`)));
  return { archive: { ...existing, venues }, keys };
}

/** Recover a durable approval without opening originals or changing provider cooldowns. */
export async function resumePendingDraftApproval(root: string, descriptor: number, clock = () => new Date(),
  currentInventory?: ReadInventoryRevision) {
  const state = approvedSourceState(root, descriptor);
  const active = await readActiveApprovedGeneration(state);
  return resumeReviewGeneration(state, journal, active.indexSHA256, { clock, readReceipt: replayReceipt, currentInventory });
}

/** Approve a verified draft batch. The caller holds the same lock as refresh and serving publication. */
export async function approveReviewedDrafts(root: string, descriptor: number, options: Options) {
  const state = approvedSourceState(root, descriptor);
  const { now, clock = () => new Date(), inventory } = options;
  if (inventory && !isDigest(inventory.revision)) throw new Error("Invalid trusted draft inventory revision");
  const active = await readActiveApprovedGeneration(state);
  const transition = { clock, readReceipt: replayReceipt, currentInventory: inventory?.currentRevision };
  const recovered = await resumeReviewGeneration(state, journal, active.indexSHA256, transition);
  if (recovered) return recovered;

  const { indexSHA256: baseIndexSHA256, raw, projectedAt, envelope } = active;
  validatePublicDiscoveryManifest(raw, now);
  assert.deepEqual(validatePublicDiscoveryManifest(compileApprovedPublicBatch(envelope.archive, envelope.held, projectedAt), projectedAt),
    validatePublicDiscoveryManifest(raw, projectedAt), "Active review snapshot does not match its archive");
  const { verified, counts } = await options.verify(structuredClone(envelope.archive));
  const receipt = { checkedAt: now.toISOString(), baseIndexSHA256, ...counts };
  if (!verified.length) return { activated: false, indexSHA256: baseIndexSHA256, ...receipt };
  const { archive, keys } = mergeReviews(envelope.archive, verified);
  const manifest = compileApprovedPublicBatch(archive, envelope.held, now);
  const admitted = manifest.posts.filter(({ place, id }) => keys.has(`${placeKey(place)}:${id}`));
  if (keys.size !== receipt.admitted || admitted.length !== keys.size) throw new Error("Approved drafts did not match the serving snapshot");
  return activateReviewGeneration(state, journal, { manifest, archive, quarantine: envelope.quarantine, receipt },
    { ...transition, ...(inventory ? { inventoryRevision: inventory.revision } : {}) });
}
