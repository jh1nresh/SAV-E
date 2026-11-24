import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import {
  canonicalIndexedThreadsSource, canonicalSource, indexedPublicPlatforms, isPublicDiscoveryVenueID,
  readPublicDiscoveryFile, validatePublicDiscoveryPlace, type PublicDiscoveryPlace,
} from "./publicDiscovery.js";
import { isCatalogDestinationID } from "./publicDiscoveryCatalog.js";
import { collectPublicProfileDiscoveryDrafts } from "./publicDiscoveryProfileDrafts.js";
import { emptyPublicSourceQueue, openPublicSourceQueue, parsePublicSourceQueue,
  writePublicSourceJSON, type QueueState } from "./publicDiscoverySaveQueue.js";
import { buildRelatedSourceQueries } from "./relatedPlaceSources.js";
import { searchPublicWebResults, type SourceSearchResult } from "./sourceSearchWorker.js";

const platforms = ["instagram", "threads"] as const;
type Platform = typeof platforms[number];
type Profile = { platform: Platform; handle: string; branchTerms: string[]; nameAliases?: string[] };
type Venue = { place: PublicDiscoveryPlace; missing: Platform[]; profiles?: Profile[] };
type Inventory = Map<string, Venue>;
type Candidate = { platform: Platform; sourceURL: string; authorHandle: string | null; title: string; review: null; observedIn?: string };
type SearchStatus = "searched" | "access_required" | "rate_limited" | "unavailable" | "deferred";
type Result = { place: PublicDiscoveryPlace; checkedAt: string; coverage: Record<Platform, SearchStatus>; candidates: Candidate[] };

const day = 24 * 60 * 60 * 1_000;
const searchBackoff = 15 * 60 * 1_000;
const catalogInterval = 60 * 1_000;
const catalogRetryInterval = 7 * day;

function key(provider: string, id: string): string {
  return JSON.stringify([provider, id]);
}

function savedIdentity(row: Record<string, unknown>): string | undefined {
  const provider = row.location_provider;
  if (typeof provider === "string" && isPublicDiscoveryVenueID(row.provider_place_id)) {
    return key(provider, row.provider_place_id);
  }
  if (provider == null && row.google_place_id == null && row.coordinate_system === "WGS84"
    && isCatalogDestinationID(row.provider_place_id)) {
    return key("taipei_catalog", row.provider_place_id);
  }
  if ((provider == null || provider === "google_places") && isPublicDiscoveryVenueID(row.google_place_id)) {
    return key("google_places", row.google_place_id);
  }
}

function extractDraft(platform: Platform, url: string | undefined): [string, Candidate] | undefined {
  try {
    const original = platform === "threads" ? canonicalIndexedThreadsSource(url) : canonicalSource(url, platform);
    if (!original) return;
    const path = new URL(original.url).pathname;
    if (platform === "instagram" && path.startsWith("/tv/")) return;
    const authorHandle = platform === "threads" ? path.split("/")[1]!.slice(1) : null;
    if (authorHandle && !/^[a-z0-9._]{1,30}$/i.test(authorHandle)) return;
    return [original.postID, { platform, sourceURL: original.url, authorHandle, title: "", review: null }];
  } catch {
    return;
  }
}

async function collect(
  venue: Venue,
  checkedAt: string,
  search: (query: string) => Promise<SourceSearchResult[]>,
  profileLookup: typeof collectPublicProfileDiscoveryDrafts,
): Promise<Result> {
  const { place, missing } = venue;
  const coverage: Result["coverage"] = { instagram: "deferred", threads: "deferred" };
  const candidates: Candidate[] = [];
  let sharedSearchHalted = false;
  for (const platform of missing) {
    const profiles = venue.profiles?.filter(profile => profile.platform === platform);
    if (profiles?.length) {
      const result = await profileLookup({ venues: [{ place, profiles: profiles.map(({ nameAliases = [], ...profile }) => ({
        ...profile, terms: [place.name, ...nameAliases],
      })) }] });
      const leads = result.draft.venues[0]?.candidates ?? [];
      candidates.push(...leads);
      if (result.profiles.some(profile => profile.status === "rate_limited")) {
        coverage[platform] = "rate_limited";
        continue;
      }
      if (leads.length) {
        coverage[platform] = "searched";
        continue;
      }
      if (result.profiles.every(profile => profile.status === "access_required")) {
        coverage[platform] = "access_required";
        continue;
      }
    }
    if (sharedSearchHalted) continue;
    const queries = buildRelatedSourceQueries({ id: place.providerPlaceID, name: place.name, address: place.address }, platform);
    const address = place.address.normalize("NFKC").replace(/[^\p{L}\p{N}.-]+/gu, " ").trim().slice(0, 100);
    const query = [queries.at(-1), address].filter(Boolean).join(" ");
    try {
      const hits = await search(query);
      const canonical = new Map<string, Candidate>();
      for (const hit of hits.slice(0, 10)) {
        const draft = extractDraft(platform, hit.url);
        if (draft && !canonical.has(draft[0])) canonical.set(...draft);
      }
      coverage[platform] = "searched";
      candidates.push(...canonical.values());
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      const status = ["HTTP 429", "Provider HTTP 429"].includes(message) ? "rate_limited"
        : ["HTTP 401", "HTTP 403", "Public search requires verification"].includes(message) ? "access_required"
        : "unavailable";
      coverage[platform] = status;
      // Stop shared search for this job, while leaving independent public author pages available.
      sharedSearchHalted = status !== "unavailable";
    }
  }
  return { place, checkedAt, coverage, candidates };
}

export function createPublicDiscoverySaveIntake(options: {
  inventory: Inventory;
  write: (identity: string, result: Result) => Promise<void>;
  initialState?: QueueState;
  catalogScan?: boolean;
  reloadInventory?: () => Promise<Inventory>;
  persist?: (state: QueueState) => Promise<void>;
  search?: (query: string) => Promise<SourceSearchResult[]>;
  readMissingPlatforms?: (place: PublicDiscoveryPlace) => Promise<Platform[]>;
  now?: () => number;
  profileLookup?: typeof collectPublicProfileDiscoveryDrafts;
  retryableFailure?: () => void;
}) {
  const now = options.now ?? Date.now;
  const search = options.search ?? searchPublicWebResults;
  const profileLookup = options.profileLookup ?? collectPublicProfileDiscoveryDrafts;
  const catalogOrder = (inventory: Inventory) => options.catalogScan ? [...inventory]
    .sort((a, b) => b[1].missing.length - a[1].missing.length).map(([identity]) => identity) : [];
  let inventory = options.inventory;
  let catalog = catalogOrder(inventory);
  let nextInventoryRead = options.reloadInventory ? now() + catalogInterval : Infinity;
  let pendingInventory: Inventory | undefined;
  let state = options.initialState ?? emptyPublicSourceQueue;
  let mutations = Promise.resolve();
  let drain: Promise<void> | undefined;
  let wake: ReturnType<typeof setTimeout> | undefined;
  let failedWriteUntil = 0;

  function change(update: (current: QueueState) => QueueState, afterCommit?: () => void) {
    const result = mutations.then(async () => {
      const next = update(state);
      if (next !== state) {
        await options.persist?.(next);
        state = next;
      }
      afterCommit?.();
    });
    mutations = result.catch(() => {});
    return result;
  }

  async function refreshInventory() {
    if (!options.reloadInventory || nextInventoryRead > now()) return;
    nextInventoryRead = now() + catalogInterval;
    try {
      pendingInventory = await options.reloadInventory();
    } catch {
      options.retryableFailure?.();
    }
    const snapshot = pendingInventory;
    if (!snapshot) return;
    try {
      const order = catalogOrder(snapshot);
      await change(current => {
        const jobs = current.jobs.filter(job => snapshot.has(job.identity));
        return jobs.length === current.jobs.length ? current : { ...current, jobs };
      }, () => {
        inventory = snapshot;
        catalog = order;
      });
      pendingInventory = undefined;
    } catch {
      // A replacement may retire queued venues. Pause lookups until the queue
      // and the last validated replacement can commit together.
      nextInventoryRead = now() + catalogInterval;
      options.retryableFailure?.();
    }
  }

  function nextCatalogPlace(current: QueueState) {
    if (!catalog.length || current.jobs.some(job => job.pending)) return;
    const recorded = new Map(current.jobs.map(job => [job.identity, job]));
    let next: { identity: string; dueAt: number } | undefined;
    for (const identity of catalog) {
      const job = recorded.get(identity);
      if (!job) return { identity, dueAt: 0 };
      // Existing state knows the save cooldown but may not know when the lookup ended.
      const dueAt = job.catalogDueAt ?? job.dueAt + catalogRetryInterval;
      if (!next || dueAt < next.dueAt) next = { identity, dueAt };
    }
    return next;
  }

  async function enqueueCatalogPlace() {
    let added = false;
    if ((state.catalogAfter ?? 0) > now() || (nextCatalogPlace(state)?.dueAt ?? Infinity) > now()) return added;
    await change(current => {
      const time = now();
      const place = nextCatalogPlace(current);
      if (!place || place.dueAt > time || (current.catalogAfter ?? 0) > time) return current;
      added = true;
      return { ...current, catalogAfter: time + catalogInterval,
        jobs: [...current.jobs.filter(job => job.identity !== place.identity),
          { identity: place.identity, pending: true, dueAt: time }] };
    });
    return added;
  }

  function start() {
    if (drain) return;
    clearTimeout(wake);
    wake = undefined;
    const firstDue = state.jobs.reduce((earliest, job) => job.pending ? Math.min(earliest, job.dueAt) : earliest, Infinity);
    const catalogDue = Math.max(state.catalogAfter ?? 0, nextCatalogPlace(state)?.dueAt ?? Infinity);
    const nextLookup = pendingInventory ? Infinity
      : Math.max(state.backoffUntil, failedWriteUntil, Math.min(firstDue, catalogDue));
    const nextDue = Math.min(nextLookup, nextInventoryRead);
    if (!Number.isFinite(nextDue)) return;
    const delay = nextDue - now();
    if (delay > 0) {
      wake = setTimeout(start, Math.min(delay, 2 ** 31 - 1)).unref();
      return;
    }
    drain = Promise.resolve().then(run);
  }

  async function run() {
    try {
      for (;;) {
        await refreshInventory();
        if (pendingInventory || now() < Math.max(state.backoffUntil, failedWriteUntil)) break;
        const job = state.jobs.find(row => row.pending && row.dueAt <= now());
        if (!job) {
          if (await enqueueCatalogPlace()) continue;
          break;
        }
        const { identity } = job;
        const venue = inventory.get(identity)!;
        let pending = false;
        let delay = searchBackoff;
        let providerBackoffUntil = 0;
        try {
          const missing = options.readMissingPlatforms ? await options.readMissingPlatforms(venue.place) : venue.missing;
          const report = missing.length
            ? await collect({ ...venue, missing }, new Date(now()).toISOString(), search, profileLookup)
            : undefined;
          const statuses = report ? missing.map(platform => report.coverage[platform]) : [];
          if (statuses.some(status => status === "rate_limited" || status === "access_required")) {
            // Keep the cooldown if the process stops after the draft is written.
            providerBackoffUntil = now() + searchBackoff;
            await change(current => ({
              ...current,
              backoffUntil: Math.max(current.backoffUntil, providerBackoffUntil),
            }));
          }
          if (statuses.every(status => status === "searched")) delay = day;
          if (statuses.includes("rate_limited")) pending = true;
          if (report) await options.write(identity, report);
        } catch {
          pending = true;
          delay = searchBackoff;
          options.retryableFailure?.();
        }
        const finishedAt = now();
        // Commit the draft first. If interrupted before this state write,
        // the next process can repeat the lookup without dropping the job.
        await change(current => ({
          ...current,
          backoffUntil: Math.max(current.backoffUntil, providerBackoffUntil),
          jobs: current.jobs.map(row => row.identity === identity
            ? { identity, pending, dueAt: finishedAt + delay,
              ...(!pending && options.catalogScan ? { catalogDueAt: finishedAt + catalogRetryInterval } : {}) }
            : row),
        }));
      }
    } catch {
      failedWriteUntil = now() + searchBackoff;
      options.retryableFailure?.();
    } finally {
      drain = undefined;
      start();
    }
  }

  start();
  return {
    async afterSave(...rows: Record<string, unknown>[]) {
      const identities = new Set(rows.map(savedIdentity).filter((identity): identity is string =>
        identity !== undefined && inventory.has(identity)));
      if (!identities.size) return;
      try {
        await change(current => {
          const admissionTime = now();
          const jobs = new Map(current.jobs.map(job => [job.identity, job]));
          let changed = false;
          for (const identity of identities) {
            if (!inventory.has(identity)) continue;
            const recorded = jobs.get(identity);
            if (recorded?.pending || (recorded && recorded.dueAt > admissionTime)) continue;
            jobs.set(identity, { identity, pending: true, dueAt: admissionTime });
            changed = true;
          }
          return changed ? { ...current, jobs: [...jobs.values()] } : current;
        });
      } catch {
        options.retryableFailure?.();
      }
      start();
    },
    async idle() {
      await mutations;
      // An admission awaiting the same mutations will schedule the drain
      // before this check or join it if it is already running.
      start();
      await drain;
    },
  };
}

function validProfileTerms(terms: unknown): terms is string[] {
  return Array.isArray(terms) && terms.length >= 1 && terms.length <= 4
    && terms.every((term: unknown) => typeof term === "string" && term.length <= 100
      && !/[\p{Cc}]/u.test(term) && Array.from(term.normalize("NFKC").trim()).length >= 2);
}

function validateProfiles(input: unknown, place: PublicDiscoveryPlace): Profile[] {
  if (!Array.isArray(input) || input.length > 4 || Array.from(place.name.normalize("NFKC")).length < 2
    || /[\p{Cc}]/u.test(place.name)) throw new Error("Invalid public source profile hints");
  return input.map(row => {
    if (!row || !platforms.includes(row.platform) || typeof row.handle !== "string"
      || !/^(?=.*[a-z0-9_])[a-z0-9._]{1,30}$/i.test(row.handle) || !validProfileTerms(row.branchTerms)
      || (row.nameAliases !== undefined && !validProfileTerms(row.nameAliases))) {
      throw new Error("Invalid public source profile hint");
    }
    return { platform: row.platform, handle: row.handle, branchTerms: row.branchTerms,
      ...(row.nameAliases === undefined ? {} : { nameAliases: row.nameAliases }) };
  });
}

async function readInventory(path: string): Promise<Inventory> {
  const input = await readPublicDiscoveryFile(path);
  if (!Array.isArray(input)) throw new Error("Invalid public source intake inventory");
  const inventory: Inventory = new Map();
  for (const row of input) {
    const place = validatePublicDiscoveryPlace(row?.place);
    const missing = Array.isArray(row.missing) ? platforms.filter(platform => row.missing.includes(platform)) : [];
    const identity = key(place.provider, place.providerPlaceID);
    if (!isPublicDiscoveryVenueID(place.providerPlaceID) || !Array.isArray(row.missing)
      || row.missing.length !== missing.length || inventory.has(identity)) {
      throw new Error("Invalid public source intake venue");
    }
    const profiles = row.profiles === undefined ? [] : validateProfiles(row.profiles, place);
    inventory.set(identity, { place, missing, profiles });
  }
  return inventory;
}

export async function writePublicSourceIntakeDraft(directory: string, identity: string, report: Result) {
  // A retry may produce fewer leads. Keep the earlier batch available to the verifier.
  const candidates = [...new Set(report.candidates.map(({ platform, sourceURL, authorHandle }) =>
    JSON.stringify([platform, sourceURL, authorHandle])))].sort();
  const digest = createHash("sha256").update(JSON.stringify([identity, report.place, candidates])).digest("hex");
  await writePublicSourceJSON(join(directory, digest + ".json"), report);
}

export async function loadPublicDiscoverySaveIntake(directory: string, indexFile?: string) {
  if (!isAbsolute(directory)) throw new Error("Expected an absolute public source intake directory");
  const currentIndexFile = indexFile?.trim();
  if (!currentIndexFile) throw new Error("Expected a public discovery index for source intake");
  const reloadInventory = () => readInventory(join(directory, "inventory.json"));
  const inventory = await reloadInventory();
  const drafts = join(directory, "drafts");
  await mkdir(drafts, { recursive: true, mode: 0o700 });
  const queue = await openPublicSourceQueue(directory, readPublicDiscoveryFile);
  const state = parsePublicSourceQueue(queue.value, new Set(inventory.keys()));
  return createPublicDiscoverySaveIntake({
    inventory,
    initialState: state,
    catalogScan: true,
    reloadInventory,
    persist: queue.save,
    async readMissingPlatforms(place) {
      const indexed = await indexedPublicPlatforms(currentIndexFile, place);
      return platforms.filter(platform => !indexed.has(platform));
    },
    retryableFailure: () => console.warn("[public-discovery] Could not complete save-source intake work"),
    write: (identity, report) => writePublicSourceIntakeDraft(drafts, identity, report),
  });
}
