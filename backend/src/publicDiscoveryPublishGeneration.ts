import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { constants, fstatSync, lstatSync } from "node:fs";
import { lstat, mkdtemp, open, rename, rm } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  combinePublicDiscoveryShards, publicDiscoveryShardDigests, readPublicDiscoveryBytes,
  readPublicDiscoveryFile, timestamp, validatePublicDiscoveryManifest,
  type PublicDiscoveryIndex, type PublicDiscoveryPost,
} from "./publicDiscovery.js";
import { compileApprovedPublicBatch, writeShardedPublicProjection } from "./publicDiscoveryReviewedBatch.js";
import { writePublicSourceJSON } from "./publicDiscoverySaveQueue.js";

const sha = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex");
const isDigest = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const placeKey = (place: { provider: string; providerPlaceID: string }) =>
  JSON.stringify([place.provider, place.providerPlaceID]);
const absent = (error: NodeJS.ErrnoException) => {
  if (error.code !== "ENOENT") throw error;
  return undefined;
};

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid reviewed generation data");
  return value as Record<string, unknown>;
}

export async function readReviewEnvelope(path: string, digest: string) {
  // The private envelope can include both the archive and a retained 6 MiB snapshot.
  const handle = await open(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    if (!(await handle.stat()).isFile()) throw new Error("Expected a review envelope file");
    const envelope = record(JSON.parse(await handle.readFile("utf8")));
    if (envelope.indexSHA256 !== digest || !Array.isArray(envelope.quarantine)) {
      throw new Error("Review envelope does not bind to the active snapshot");
    }
    const held = new Set(envelope.quarantine.map((row: unknown) => {
      const key = record(row).key;
      if (typeof key !== "string") throw new Error("Invalid quarantined association");
      return key;
    }));
    return { archive: envelope.archive, held, quarantine: envelope.quarantine as unknown[],
      retainedManifest: envelope.retainedManifest, receipt: envelope.receipt, managedBy: envelope.managedBy,
      activationComplete: envelope.activationComplete, inventoryRevision: envelope.inventoryRevision };
  } finally {
    await handle.close();
  }
}

function partition(index: PublicDiscoveryIndex) {
  const { posts, coverage, googlePlaceAliases = [], applePlaceAliases = [], ...version } = index;
  const buckets: PublicDiscoveryPost[][] = [[], []];
  // Keep one venue together and slice only after ranking across the full archive.
  for (const post of posts) {
    const bucket = createHash("sha256").update(placeKey(post.place)).digest()[0]! % buckets.length;
    buckets[bucket]!.push(post);
  }
  return buckets.filter((part, i) => part.length > 0 || (!posts.length && i === 0)).map(part => {
    const venues = new Set(part.map(post => placeKey(post.place)));
    const platforms = new Set(part.map(post => post.platform));
    return {
      ...version, posts: part,
      coverage: coverage.map(({ platform }) => ({ platform, status: platforms.has(platform) ? "connected" : "not_connected" })),
      googlePlaceAliases: googlePlaceAliases.filter(alias => venues.has(placeKey(alias))),
      applePlaceAliases: applePlaceAliases.filter(alias => venues.has(placeKey({ ...alias, provider: "apple_maps" }))),
    };
  });
}

async function confirmedPublication(directory: string, pointerSHA256: string) {
  const pointer = await readPublicDiscoveryFile(join(directory, "index.json"), pointerSHA256);
  for (const digest of publicDiscoveryShardDigests(pointer)) {
    await readPublicDiscoveryFile(join(directory, digest + ".json"), digest);
  }
  return true;
}

/** Check the inherited descriptor for an operation running under the writer's flock. */
export function approvedSourceState(root: string, descriptor: number) {
  const state = join(root, "state");
  if (!isAbsolute(root) || !Number.isSafeInteger(descriptor) || descriptor < 3
    || !lstatSync(root).isDirectory() || !lstatSync(state).isDirectory()
    || !lstatSync(join(state, "generations")).isDirectory()) throw new Error("Expected an initialized source root and inherited lock");
  const inherited = fstatSync(descriptor);
  const lock = lstatSync(join(state, "refresh.lock"));
  if (!inherited.isFile() || !lock.isFile() || inherited.dev !== lock.dev || inherited.ino !== lock.ino) {
    throw new Error("Expected the inherited source lock");
  }
  return state;
}

export async function readActiveApprovedGeneration(state: string) {
  const bytes = await readPublicDiscoveryBytes(join(state, "active-index.json"));
  const indexSHA256 = sha(bytes);
  const raw = record(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
  const projectedAt = new Date(timestamp(raw.generatedAt));
  const envelope = await readReviewEnvelope(join(state, "generations", indexSHA256 + ".json"), indexSHA256);
  return { indexSHA256, raw, projectedAt, envelope };
}

/** The caller must hold the supervisor's flock for the lifetime of this operation. */
export async function publishApprovedGeneration(root: string, descriptor: number, clock = () => new Date()) {
  const state = approvedSourceState(root, descriptor);
  const directory = join(root, "serving");
  const { indexSHA256, raw, projectedAt, envelope: { archive, held } } = await readActiveApprovedGeneration(state);
  const checkpoint = join(state, "sharded-publication.json");
  const existing = await lstat(directory).catch(absent);
  if (existing && !existing.isDirectory()) throw new Error("Expected a serving catalog directory");
  const previous = await readPublicDiscoveryFile(checkpoint).catch(absent);
  if (previous !== undefined && existing) {
    const last = record(previous);
    if (last.indexSHA256 === indexSHA256 && isDigest(last.pointerSHA256)
      && await confirmedPublication(directory, last.pointerSHA256).catch(absent)) {
      return { state: "unchanged" as const, indexSHA256, pointerSHA256: last.pointerSHA256 };
    }
  }

  const approved = validatePublicDiscoveryManifest(raw, projectedAt);
  const replay = compileApprovedPublicBatch(archive, held, projectedAt);
  assert.deepEqual(validatePublicDiscoveryManifest(replay, projectedAt), approved,
    "Sharded contents must match the approved generation");
  const parts = partition(approved);
  assert.deepEqual(combinePublicDiscoveryShards(parts.map(part => validatePublicDiscoveryManifest(part, projectedAt)), projectedAt), approved);
  const work = existing ? undefined : await mkdtemp(join(root, ".sharded-work-"));
  try {
    const target = work ? join(work, "catalog") : directory;
    const publication = await writeShardedPublicProjection(target, parts, projectedAt, { replace: !!existing, clock });
    if (work) {
      await rename(target, directory);
      const parent = await open(root, "r");
      try { await parent.sync(); } finally { await parent.close(); }
    }
    const pointerSHA256 = sha(await readPublicDiscoveryBytes(join(directory, "index.json")));
    await writePublicSourceJSON(checkpoint, { indexSHA256, pointerSHA256 });
    return { state: "published" as const, indexSHA256, pointerSHA256,
      shards: publication.shards, associations: publication.associations };
  } finally {
    if (work) await rm(work, { recursive: true });
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const [root, descriptor, mode, ...extra] = process.argv.slice(2);
  void (async () => {
    if (!root || !descriptor || extra.length || (mode !== undefined && mode !== "--maintain-drafts")) {
      throw new Error("Expected source root and lock descriptor");
    }
    const receipt = mode === "--maintain-drafts"
      ? await (await import("./publicDiscoveryDraftMaintenance.js")).maintainPublicSourceDrafts(root, Number(descriptor))
      : await publishApprovedGeneration(root, Number(descriptor));
    process.stdout.write(`${JSON.stringify(receipt)}\n`);
  })().catch(() => {
    process.stderr.write("Public source maintenance failed. Check the source lock, inputs and review generation.\n");
    process.exitCode = 1;
  });
}
