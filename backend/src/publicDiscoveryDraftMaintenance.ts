import { createHash } from "node:crypto";
import { lstat, readdir } from "node:fs/promises";
import { join } from "node:path";
import { readPublicDiscoveryBytes, readPublicDiscoveryFile } from "./publicDiscovery.js";
import { approveReviewedDrafts, resumePendingDraftApproval } from "./publicDiscoveryApproveDrafts.js";
import { checkStreetDrafts } from "./publicDiscoveryDraftEvidence.js";
import { approvedSourceState, publishApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { parsePublicSourceIntakeInventory } from "./publicDiscoverySaveIntake.js";
import { writePublicSourceJSON } from "./publicDiscoverySaveQueue.js";
import { defaultFetchText } from "./sourceSearchWorker.js";

const minute = 60_000;
const maxOriginals = 2;
const revisionHash = /^[a-f0-9]{64}$/;
const draftName = /^[a-f0-9]{64}\.json$/;
const absent = (error: NodeJS.ErrnoException) => {
  if (error.code !== "ENOENT") throw error;
  return undefined;
};

const isTime = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
const parse = (bytes: Buffer) => JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid draft maintenance record");
  return value as Record<string, unknown>;
}

async function providerHold(state: string) {
  const raw = await readPublicDiscoveryFile(join(state, "shared-provider-hold.json")).catch(absent);
  if (raw === undefined) {
    const legacy = await readPublicDiscoveryFile(join(state, "freshness-next.json")).catch(absent);
    if (legacy === undefined) return { until: 0, cadenceUntil: 0 };
    const row = record(legacy);
    if (row.version !== 1 || !isTime(row.nextAllowedAt)) throw new Error("Invalid public source freshness hold");
    return { until: row.nextAllowedAt, cadenceUntil: 0 };
  }
  const { version, until, cadenceUntil = 0 } = record(raw);
  if (version !== 1 || !isTime(until) || !isTime(cadenceUntil)) throw new Error("Invalid public source provider hold");
  return { until, cadenceUntil };
}

async function workerCheckpoint(path: string) {
  const raw = await readPublicDiscoveryFile(path).catch(absent);
  if (raw === undefined) return { revision: null, remaining: 0, cursor: null, backoffUntil: 0 };
  const { revision, remaining, cursor, backoffUntil } = record(raw);
  if ((revision !== null && (typeof revision !== "string" || !revisionHash.test(revision)))
    || !isTime(remaining) || !isTime(backoffUntil) || (cursor !== null && (typeof cursor !== "string" || cursor.length > 800))) {
    throw new Error("Invalid public source draft checkpoint");
  }
  return { revision, remaining, cursor, backoffUntil };
}

async function trustedInputs(root: string) {
  const [inventory, localized, official] = await Promise.all([
    readPublicDiscoveryBytes(join(root, "inventory.json")),
    readPublicDiscoveryBytes(join(root, "localized-addresses.json")).catch(absent),
    readPublicDiscoveryBytes(join(root, "official-features.json")).catch(absent),
  ]);
  const revision = createHash("sha256")
    .update(JSON.stringify([inventory, localized ?? null, official ?? null].map(bytes => bytes && createHash("sha256").update(bytes).digest("hex"))))
    .digest("hex");
  return { revision, inventory, localized, official };
}

async function draftReports(root: string, inputs: string) {
  const directory = join(root, "drafts");
  if (!(await lstat(directory)).isDirectory()) throw new Error("Expected a public source draft directory");
  const entries = (await readdir(directory, { withFileTypes: true }))
    .filter(file => file.isFile() && draftName.test(file.name)).map(file => file.name).sort();
  const hash = createHash("sha256").update(inputs);
  const files: string[] = [];
  for (const name of entries) {
    const file = join(directory, name);
    const info = await lstat(file, { bigint: true }).catch(absent);
    if (!info?.isFile()) continue;
    hash.update(JSON.stringify([name, String(info.ino), String(info.size), String(info.mtimeNs)]) + "\n");
    files.push(file);
  }
  async function* readReports() {
    for (const file of files) {
      const report = await readPublicDiscoveryFile(file).catch(absent);
      if (report !== undefined) yield report;
    }
  }
  return { revision: hash.digest("hex"), readReports };
}

/** Run once under the maintenance lock. Discovery drafts are immutable reports written by intake. */
export async function maintainPublicSourceDrafts(root: string, descriptor: number, options: {
  clock?: () => Date;
  fetchEmbed?: (url: string) => Promise<string>;
} = {}) {
  const state = approvedSourceState(root, descriptor);
  const { clock = () => new Date(), fetchEmbed = defaultFetchText } = options;
  const now = clock();
  const holdPath = join(state, "shared-provider-hold.json");
  const persistHold = (until: number, cadenceUntil: number) => writePublicSourceJSON(holdPath, { version: 1, until, cadenceUntil });
  const currentInventory = async () => (await trustedInputs(root).catch(absent))?.revision;
  const recovered = await resumePendingDraftApproval(root, descriptor, clock, currentInventory);
  const initialPublication = await publishApprovedGeneration(root, descriptor, clock);
  const hold = await providerHold(state);
  const blockedUntil = Math.max(hold.until, hold.cadenceUntil);
  if (recovered || blockedUntil > +now) {
    const status = recovered ? "recovered" : hold.until > +now ? "provider_hold" : "cadence_wait";
    return { state: status, nextAllowedAt: Math.max(blockedUntil, +now + minute), requests: 0,
      publication: initialPublication, ...(recovered ? { recovered } : {}) };
  }
  const checkpointPath = join(state, "street-worker.json");
  const checkpoint = await workerCheckpoint(checkpointPath);
  if (checkpoint.backoffUntil > +now) {
    return { state: "provider_hold", nextAllowedAt: checkpoint.backoffUntil, requests: 0, publication: initialPublication };
  }
  const inputs = await trustedInputs(root);
  const reports = await draftReports(root, inputs.revision);
  const changed = checkpoint.revision !== reports.revision;
  if (!changed && checkpoint.remaining === 0) {
    return { state: "idle", nextAllowedAt: +now + minute, requests: 0, publication: initialPublication };
  }
  const inventory = [...parsePublicSourceIntakeInventory(parse(inputs.inventory)).values()].map(venue => venue.place);
  let requests = 0;
  let cooldown = 0;
  let holdFailure: unknown;
  let fallbackHold = 0;
  const result = await approveReviewedDrafts(root, descriptor, {
    now, clock, inventory: { revision: inputs.revision, currentRevision: currentInventory }, verify: async archive => {
      const checked = await checkStreetDrafts(archive, reports.readReports(), inventory, {
        now, cursor: checkpoint.cursor,
        maxOriginals: changed ? maxOriginals : Math.min(maxOriginals, checkpoint.remaining),
        localizedAddresses: inputs.localized ? parse(inputs.localized) : [],
        officialFeatures: inputs.official ? parse(inputs.official) : [],
        fetchEmbed: async url => {
          // Persist a conservative hold before reaching any provider. A killed
          // process can complete local recovery while new requests stay paused.
          if (holdFailure !== undefined) throw holdFailure;
          if (cooldown > +clock()) throw new Error("Public source provider is cooling down");
          if (!requests) {
            fallbackHold = +clock() + 60 * minute;
            try { await persistHold(fallbackHold, 0); }
            catch (error) { holdFailure = error; throw error; }
          }
          requests++;
          try {
            return await fetchEmbed(url);
          } catch (error) {
            const status = error instanceof Error ? /^(?:Provider )?HTTP (401|403|429)$/.exec(error.message)?.[1] : undefined;
            if (status) {
              cooldown = +clock() + (status === "429" ? 15 : 60) * minute;
              try { await persistHold(Math.max(cooldown, fallbackHold), 0); }
              catch (error) { holdFailure = error; }
            }
            throw error;
          }
        },
      });
      if (holdFailure !== undefined) throw holdFailure;
      if (await currentInventory() !== inputs.revision) throw new Error("Trusted source inventory changed during draft verification");
      return checked;
    },
  });
  const available = result.checked + result.deferred;
  const pending = changed ? available : Math.min(available, checkpoint.remaining);
  const consumed = result.checked - Number(cooldown > +now && result.checked > 0);
  const nextAllowedAt = Math.max(+clock() + minute, cooldown);
  await writePublicSourceJSON(checkpointPath, { revision: reports.revision, remaining: Math.max(0, pending - consumed),
    cursor: result.nextCursor, backoffUntil: cooldown });
  if (requests) await persistHold(cooldown, nextAllowedAt);
  const publication = result.activated ? await publishApprovedGeneration(root, descriptor, clock) : initialPublication;
  return { state: "checked", nextAllowedAt, requests, approval: result, publication };
}
