import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { unlink } from "node:fs/promises";
import { join } from "node:path";
import {
  canonicalSource, publicDiscoveryMaxFileBytes, readPublicDiscoveryFile, timestamp, validatePublicDiscoveryManifest,
  validatePublicDiscoveryPlace, type PublicDiscoveryPlace,
} from "./publicDiscovery.js";
import type { checkStreetDrafts } from "./publicDiscoveryDraftEvidence.js";
import { approvedSourceState, readActiveApprovedGeneration, readReviewEnvelope } from "./publicDiscoveryPublishGeneration.js";
import { compileApprovedPublicBatch } from "./publicDiscoveryReviewedBatch.js";
import { writePublicSourceJSON } from "./publicDiscoverySaveQueue.js";

type DraftCheck = Awaited<ReturnType<typeof checkStreetDrafts>>;
type Receipt = DraftCheck["counts"] & { checkedAt: string; baseIndexSHA256: string };
type Pending = { baseIndexSHA256: string; indexSHA256: string; owner?: string };
type Options = {
  now: Date;
  clock?: () => Date;
  verify: (archive: unknown) => Promise<DraftCheck>;
};

const digest = (value: unknown) => createHash("sha256").update(JSON.stringify(value) + "\n").digest("hex");
const isDigest = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const isOwner = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);
const absent = (error: NodeJS.ErrnoException) => {
  if (error.code !== "ENOENT") throw error;
  return undefined;
};
const placeKey = (place: PublicDiscoveryPlace) => `${place.provider}:${place.providerPlaceID}`;
const journalPath = (state: string) => join(state, "pending-admission.json");
const envelopePath = (state: string, indexSHA256: string) => join(state, "generations", indexSHA256 + ".json");

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid draft approval data");
  return value as Record<string, unknown>;
}

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

async function finishPending(state: string, pending: Pending, active: string, clock: () => Date) {
  if (active !== pending.baseIndexSHA256 && active !== pending.indexSHA256) {
    // A newer active generation supersedes this journal, even after retention.
    await unlink(journalPath(state));
    return;
  }
  const path = envelopePath(state, pending.indexSHA256);
  const envelope = await readReviewEnvelope(path, pending.indexSHA256);
  if (envelope.activationComplete !== undefined && envelope.activationComplete !== true) {
    throw new Error("Invalid staged review activation marker");
  }
  if (active === pending.baseIndexSHA256 && envelope.activationComplete) {
    // An operator rolled back a previously activated approval.
    await unlink(journalPath(state));
    return;
  }
  const manifest = record(envelope.retainedManifest);
  if (digest(manifest) !== pending.indexSHA256) throw new Error("Pending draft manifest does not match its digest");
  const checkedAt = timestamp(manifest.generatedAt);
  const receipt = replayReceipt(envelope.receipt, pending.baseIndexSHA256, checkedAt);
  if (pending.owner && envelope.managedBy !== undefined && envelope.managedBy !== pending.owner) {
    throw new Error("Staged review history has a different owner");
  }
  if (active !== pending.indexSHA256) {
    const projectedAt = new Date(checkedAt);
    const replay = compileApprovedPublicBatch(envelope.archive, envelope.held, projectedAt);
    assert.deepEqual(replay, manifest, "Pending review snapshot does not match its archive");
    validatePublicDiscoveryManifest(manifest, projectedAt);
    const now = clock();
    if (!Number.isFinite(now.getTime()) || now < projectedAt) throw new Error("Invalid draft publication clock");
    try {
      validatePublicDiscoveryManifest(manifest, now);
    } catch {
      // Only time changed after successful validation at the generation timestamp.
      await unlink(journalPath(state));
      return;
    }
    await writePublicSourceJSON(join(state, "active-index.json"), manifest);
  }
  // Mark history ownership only after activation so a separate retention pass
  // cannot delete an approval that still needs to be resumed.
  if (!envelope.activationComplete) {
    const managedBy = pending.owner ?? envelope.managedBy;
    await writePublicSourceJSON(path, { indexSHA256: pending.indexSHA256, archive: envelope.archive,
      quarantine: envelope.quarantine, receipt, retainedManifest: manifest, activationComplete: true,
      ...(managedBy ? { managedBy } : {}) }, Infinity);
  }
  await unlink(journalPath(state));
  return { activated: true, indexSHA256: pending.indexSHA256, ...receipt };
}

async function resume(state: string, active: string, clock: () => Date) {
  const pending = await readPublicDiscoveryFile(journalPath(state)).catch(absent);
  if (pending === undefined) return;
  const { baseIndexSHA256, indexSHA256, owner } = record(pending);
  if (!isDigest(baseIndexSHA256) || !isDigest(indexSHA256) || baseIndexSHA256 === indexSHA256
    || (owner !== undefined && !isOwner(owner))) {
    throw new Error("Invalid pending approval generation");
  }
  return finishPending(state, { baseIndexSHA256, indexSHA256, ...(owner ? { owner } : {}) }, active, clock);
}

/** Recover a durable approval without opening originals or changing provider cooldowns. */
export async function resumePendingDraftApproval(root: string, descriptor: number, clock = () => new Date()) {
  const state = approvedSourceState(root, descriptor);
  const active = await readActiveApprovedGeneration(state);
  return resume(state, active.indexSHA256, clock);
}

/** Approve a verified draft batch. The caller holds the same lock as refresh and serving publication. */
export async function approveReviewedDrafts(root: string, descriptor: number, options: Options) {
  const state = approvedSourceState(root, descriptor);
  const { now, clock = () => new Date() } = options;
  const active = await readActiveApprovedGeneration(state);
  const recovered = await resume(state, active.indexSHA256, clock);
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
  if (Buffer.byteLength(JSON.stringify(manifest) + "\n") > publicDiscoveryMaxFileBytes) throw new Error("Approved snapshot is too large");
  validatePublicDiscoveryManifest(manifest, clock());
  assert.equal((await readActiveApprovedGeneration(state)).indexSHA256, baseIndexSHA256);

  const indexSHA256 = digest(manifest);
  const history = await readPublicDiscoveryFile(join(state, "managed-index-history.json")).catch(absent);
  let owner;
  if (history !== undefined) {
    const managed = record(history);
    if (managed.version !== 1 || !isOwner(managed.owner) || !isDigest(managed.anchor) || !isDigest(managed.active)
      || (managed.previous !== null && !isDigest(managed.previous)) || managed.active === managed.previous) {
      throw new Error("Invalid managed review history policy");
    }
    owner = managed.owner;
  }
  const metadata = { indexSHA256, archive, quarantine: envelope.quarantine, receipt, retainedManifest: manifest };
  const path = envelopePath(state, indexSHA256);
  const previous = await readReviewEnvelope(path, indexSHA256).catch(absent);
  if (previous) {
    assert.deepEqual({ archive: previous.archive, quarantine: previous.quarantine, retainedManifest: previous.retainedManifest, receipt: previous.receipt },
      { archive, quarantine: envelope.quarantine, retainedManifest: manifest, receipt }, "Existing draft approval differs");
  } else {
    // Private review metadata includes the archive as well as the public snapshot.
    await writePublicSourceJSON(path, metadata, Infinity);
  }
  const staged = { baseIndexSHA256, indexSHA256, ...(owner ? { owner } : {}) };
  await writePublicSourceJSON(journalPath(state), staged);
  const activated = await finishPending(state, staged, baseIndexSHA256, clock);
  if (!activated) throw new Error("Verified draft approval expired before activation");
  return activated;
}
