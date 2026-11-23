import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { unlink } from "node:fs/promises";
import { join } from "node:path";
import { publicDiscoveryMaxFileBytes, readPublicDiscoveryFile, timestamp, validatePublicDiscoveryManifest } from "./publicDiscovery.js";
import { readActiveApprovedGeneration, readReviewEnvelope } from "./publicDiscoveryPublishGeneration.js";
import { compileApprovedPublicBatch } from "./publicDiscoveryReviewedBatch.js";
import { writePublicSourceJSON } from "./publicDiscoverySaveQueue.js";

type GenerationReceipt = { checkedAt: string; baseIndexSHA256: string };
type Pending = { baseIndexSHA256: string; indexSHA256: string; owner?: string; inventoryRevision?: string };
export type ReadInventoryRevision = () => Promise<string | undefined>;
type Journal = "pending-admission.json" | "pending-renewal.json";
type TransitionOptions<T> = {
  clock: () => Date;
  readReceipt: (value: unknown, baseIndexSHA256: string, checkedAt: string) => T;
  currentInventory?: ReadInventoryRevision | undefined;
  inventoryRevision?: string;
};

const digest = (value: unknown) => createHash("sha256").update(JSON.stringify(value) + "\n").digest("hex");
export const isDigest = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const isOwner = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);
const absent = (error: NodeJS.ErrnoException) => {
  if (error.code !== "ENOENT") throw error;
  return undefined;
};
const envelopePath = (state: string, indexSHA256: string) => join(state, "generations", indexSHA256 + ".json");

export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid draft approval data");
  return value as Record<string, unknown>;
}

async function finishPending<T extends GenerationReceipt>(state: string, journal: Journal, pending: Pending, active: string, options: TransitionOptions<T>) {
  const { clock, currentInventory, readReceipt } = options;
  if (active !== pending.baseIndexSHA256 && active !== pending.indexSHA256) {
    // A newer active generation supersedes this journal, even after retention.
    await unlink(join(state, journal));
    return;
  }
  const path = envelopePath(state, pending.indexSHA256);
  const envelope = await readReviewEnvelope(path, pending.indexSHA256);
  if (envelope.inventoryRevision !== pending.inventoryRevision) throw new Error("Review inventory revision does not match the pending approval");
  if (envelope.activationComplete !== undefined && envelope.activationComplete !== true) {
    throw new Error("Invalid staged review activation marker");
  }
  if (active === pending.baseIndexSHA256 && envelope.activationComplete) {
    // An operator rolled back a previously activated approval.
    await unlink(join(state, journal));
    return;
  }
  const manifest = record(envelope.retainedManifest);
  if (digest(manifest) !== pending.indexSHA256) throw new Error("Pending draft manifest does not match its digest");
  const checkedAt = timestamp(manifest.generatedAt);
  const receipt = readReceipt(envelope.receipt, pending.baseIndexSHA256, checkedAt);
  if (pending.owner && envelope.managedBy !== undefined && envelope.managedBy !== pending.owner) {
    throw new Error("Staged review history has a different owner");
  }
  if (active !== pending.indexSHA256) {
    const projectedAt = new Date(checkedAt);
    const replay = compileApprovedPublicBatch(envelope.archive, envelope.held, projectedAt);
    assert.deepEqual(replay, manifest, "Pending review snapshot does not match its archive");
    validatePublicDiscoveryManifest(manifest, projectedAt);
    if (pending.inventoryRevision) {
      if (!currentInventory) throw new Error("Pending approval requires a current trusted inventory");
      if (await currentInventory() !== pending.inventoryRevision) {
        await unlink(join(state, journal));
        return;
      }
    }
    const now = clock();
    if (!Number.isFinite(now.getTime()) || now < projectedAt) throw new Error("Invalid draft publication clock");
    try {
      validatePublicDiscoveryManifest(manifest, now);
    } catch {
      // Only time changed after successful validation at the generation timestamp.
      await unlink(join(state, journal));
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
      ...(pending.inventoryRevision ? { inventoryRevision: pending.inventoryRevision } : {}),
      ...(managedBy ? { managedBy } : {}) }, Infinity);
  }
  await unlink(join(state, journal));
  return { activated: true, indexSHA256: pending.indexSHA256, ...receipt };
}

export async function resumeReviewGeneration<T extends GenerationReceipt>(state: string, journal: Journal, active: string, options: TransitionOptions<T>) {
  const pending = await readPublicDiscoveryFile(join(state, journal)).catch(absent);
  if (pending === undefined) return;
  const { baseIndexSHA256, indexSHA256, owner, inventoryRevision } = record(pending);
  if (!isDigest(baseIndexSHA256) || !isDigest(indexSHA256) || baseIndexSHA256 === indexSHA256
    || (owner !== undefined && !isOwner(owner)) || (inventoryRevision !== undefined && !isDigest(inventoryRevision))) {
    throw new Error("Invalid pending approval generation");
  }
  return finishPending(state, journal, { baseIndexSHA256, indexSHA256, ...(owner ? { owner } : {}),
    ...(inventoryRevision ? { inventoryRevision } : {}) }, active, options);
}

/** Commit under the shared source lock, staging the envelope for crash recovery first. */
export async function activateReviewGeneration<T extends GenerationReceipt>(state: string, journal: Journal, next: {
  archive: unknown; quarantine: unknown[]; manifest: ReturnType<typeof compileApprovedPublicBatch>; receipt: T;
}, options: TransitionOptions<T>) {
  const { archive, quarantine, manifest, receipt } = next;
  const { baseIndexSHA256 } = receipt;
  if (Buffer.byteLength(JSON.stringify(manifest) + "\n") > publicDiscoveryMaxFileBytes) throw new Error("Approved snapshot is too large");
  validatePublicDiscoveryManifest(manifest, options.clock());
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
  const inventoryBinding = options.inventoryRevision ? { inventoryRevision: options.inventoryRevision } : {};
  const metadata = { indexSHA256, archive, quarantine, receipt, retainedManifest: manifest, ...inventoryBinding };
  const path = envelopePath(state, indexSHA256);
  const previous = await readReviewEnvelope(path, indexSHA256).catch(absent);
  if (previous) {
    if (previous.inventoryRevision !== options.inventoryRevision) throw new Error("Existing draft approval has different inventory evidence");
    assert.deepEqual({ archive: previous.archive, quarantine: previous.quarantine, retainedManifest: previous.retainedManifest, receipt: previous.receipt },
      { archive, quarantine, retainedManifest: manifest, receipt }, "Existing draft approval differs");
  } else {
    // Private review metadata includes the archive as well as the public snapshot.
    await writePublicSourceJSON(path, metadata, Infinity);
  }
  const staged = { baseIndexSHA256, indexSHA256, ...(owner ? { owner } : {}), ...inventoryBinding };
  await writePublicSourceJSON(join(state, journal), staged);
  const activated = await finishPending(state, journal, staged, baseIndexSHA256, options);
  if (!activated) throw new Error("Verified draft approval is no longer current");
  return activated;
}
