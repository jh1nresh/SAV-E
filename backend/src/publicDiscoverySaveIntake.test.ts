import assert from "node:assert/strict";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { createPublicDiscoverySaveIntake, loadPublicDiscoverySaveIntake, writePublicSourceIntakeDraft } from "./publicDiscoverySaveIntake.js";
import type { PublicDiscoveryPlace } from "./publicDiscovery.js";
import { parsePublicSourceQueue, type QueueState } from "./publicDiscoverySaveQueue.js";

const place: PublicDiscoveryPlace = {
  provider: "google_places", providerPlaceID: "PublicStore", name: "Public Cafe",
  address: "臺北市萬華區華西街146號", latitude: 25.039, longitude: 121.498, coordinateSystem: "WGS84", category: "food",
};
const identity = JSON.stringify([place.provider, place.providerPlaceID]);
const saved = { google_place_id: place.providerPlaceID, name: "SENSITIVE NAME", note: "SENSITIVE NOTE", user_id: "SENSITIVE OWNER" };
const second = { ...place, providerPlaceID: "AnotherStore" };
const inventory = () => new Map<string, { place: PublicDiscoveryPlace; missing: ("instagram" | "threads")[] }>([
  [identity, { place, missing: ["instagram", "threads"] }],
  [JSON.stringify([second.provider, second.providerPlaceID]), { place: second, missing: ["instagram"] }],
]);

test("loads new public venues during provider cooldown and drops removed pending venues", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  const minute = 60_000;
  let now = at;
  let inventoryReads = 0;
  const queries: string[] = [];
  const errors: string[] = [];
  const next = { ...second, name: "New Public Venue" };
  const nextKey = JSON.stringify([next.provider, next.providerPlaceID]);
  const worker = createPublicDiscoverySaveIntake({
    inventory: new Map([[identity, { place, missing: ["instagram"] }]]),
    catalogScan: true,
    now: () => now,
    async reloadInventory() {
      if (++inventoryReads === 1) throw new Error("Invalid inventory during file replacement");
      return new Map([[nextKey, { place: next, missing: ["instagram"] }]]);
    },
    async search(query) {
      queries.push(query);
      if (queries.length === 1) throw new Error("HTTP 429");
      return [];
    },
    async write() {},
    retryableFailure: () => { errors.push("inventory"); },
  });
  await worker.idle();
  assert.equal(queries.length, 1);
  await worker.afterSave({ google_place_id: next.providerPlaceID, note: "PRIVATE NOTE" });
  now += minute;
  await worker.idle();
  assert.equal(inventoryReads, 1);
  assert.deepEqual(errors, ["inventory"]);
  assert.equal(queries.length, 1);
  now += minute;
  await worker.idle();
  assert.equal(inventoryReads, 2);
  assert.equal(queries.length, 1);

  now = at + 15 * minute;
  await worker.idle();
  assert.equal(queries.length, 2);
  assert.match(queries[1]!, /New Public Venue/);
  assert.doesNotMatch(queries.join(" "), /PRIVATE NOTE/);
  await worker.idle();
  assert.equal(queries.length, 2);
});

test("refreshes the catalog between searches even with a pending backlog", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  let now = at;
  const venues = inventory();
  const queries: string[] = [];
  const worker = createPublicDiscoverySaveIntake({
    inventory: venues,
    now: () => now,
    initialState: { version: 1, backoffUntil: 0, jobs: [...venues.keys()].map(key =>
      ({ identity: key, pending: true, dueAt: at })) },
    async reloadInventory() { return new Map(); },
    async search(query) {
      queries.push(query);
      now += 60_001;
      return [];
    },
    async write() {},
  });
  // The first venue makes both of its already-started platform checks. The
  // second venue never starts after its catalog entry is removed.
  await worker.idle();
  assert.equal(queries.length, 2);
  assert.ok(queries.every(query => query.includes(place.name)));
});

test("stops lookups when a valid retirement cannot be persisted and retries the validated snapshot", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  const minute = 60_000;
  let now = at;
  let reads = 0;
  let writes = 0;
  let lookups = 0;
  let drafts = 0;
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(),
    now: () => now,
    initialState: { version: 1, backoffUntil: 0, jobs: [{ identity, pending: true, dueAt: at + minute }] },
    async reloadInventory() {
      if (++reads === 1) return new Map();
      throw new Error("Malformed inventory replacement");
    },
    async persist(next) {
      assert.deepEqual(next.jobs, []);
      writes++;
      if (writes === 1) {
        now += minute + 1;
        throw new Error("ENOSPC");
      }
    },
    async search() { lookups++; return []; },
    async write() { drafts++; },
  });
  await worker.idle();
  now += minute;
  await worker.idle();
  assert.equal(writes, 1);
  now += minute - 1;
  await worker.idle();
  assert.equal(writes, 1);
  now++;
  await worker.idle();
  assert.equal(reads, 2);
  assert.equal(writes, 2);
  assert.equal(lookups, 0);
  assert.equal(drafts, 0);
});

test("deduplicates saves by exact public identity and persists only draft links", async () => {
  const queries: string[] = [];
  const results: unknown[] = [];
  let release!: () => void;
  const latch = new Promise<void>(resolve => { release = resolve; });
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(),
    async search(query) {
      queries.push(query);
      await latch;
      const links = query.includes("instagram.com")
        ? ["https://www.instagram.com/p/FixtureIG/?igsh=abc", "https://instagram.com/p/FixtureIG/",
          "https://www.instagram.com/p/Signed/?token=secret", "https://example.com/p/fake"]
        : ["https://www.threads.net/@Author/post/FixtureTh/caption", "https://www.threads.com/@author"];
      return links.map(url => ({ query, url, title: "DO NOT RETAIN" }));
    },
    async write(id, result) {
      assert.equal(id, identity);
      results.push(result);
    },
  });
  worker.afterSave({ name: place.name, address: place.address });
  worker.afterSave({ ...saved, location_provider: "apple_maps", provider_place_id: "WrongBranch" });
  worker.afterSave(saved);
  await Promise.resolve();
  worker.afterSave({ ...saved, user_id: "other account" });
  release();
  await worker.idle();
  worker.afterSave(saved);
  await worker.idle();
  assert.equal(queries.length, 2);
  assert.ok(queries.every(query => query.includes("Public Cafe") && query.includes("華西街146號")));
  for (const forbidden of ["SENSITIVE", "DO NOT RETAIN", "igsh", "secret"]) {
    assert.doesNotMatch(JSON.stringify({ queries, results }), new RegExp(forbidden));
  }
  assert.equal(results.length, 1);
  assert.deepEqual((results[0] as { candidates: unknown[] }).candidates, [
    { platform: "instagram", sourceURL: "https://www.instagram.com/p/FixtureIG/", authorHandle: null, title: "", review: null },
    { platform: "threads", sourceURL: "https://www.threads.com/@author/post/FixtureTh", authorHandle: "author", title: "", review: null },
  ]);
});

test("restores provider backoff and resumes both jobs without another save", async () => {
  const reports: unknown[] = [];
  const at = Date.parse("2026-11-23T05:00:00Z");
  const backoff = 15 * 60 * 1_000;
  let calls = 0;
  let snapshot: QueueState | undefined;
  const first = createPublicDiscoverySaveIntake({
    inventory: inventory(), now: () => at,
    async search() {
      calls++;
      throw new Error("HTTP 429");
    },
    async write(_, report) { reports.push(report.coverage); },
    async persist(state) { snapshot = state; },
  });
  await first.afterSave(saved, { google_place_id: second.providerPlaceID });
  await first.idle();
  assert.equal(calls, 1);
  assert.deepEqual(reports, [{ instagram: "rate_limited", threads: "deferred" }]);
  assert.ok(snapshot);
  assert.equal(snapshot.backoffUntil, at + backoff);
  assert.equal(snapshot.jobs.filter(job => job.pending).length, 2);

  let now = at + backoff - 1;
  const restarted = createPublicDiscoverySaveIntake({
    inventory: inventory(), initialState: snapshot, now: () => now,
    async search() { calls++; return []; },
    async write(_, report) { reports.push(report.coverage); },
  });
  await restarted.idle();
  assert.equal(calls, 1);
  now++;
  await restarted.idle();
  assert.equal(calls, 4);
  assert.deepEqual(reports.slice(1), [
    { instagram: "searched", threads: "searched" },
    { instagram: "searched", threads: "deferred" },
  ]);
});

test("failed draft storage does not reject save notification or wedge the queue", async () => {
  let savedReports = 0;
  let errors = 0;
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(), search: async () => [],
    retryableFailure: () => { errors++; },
    async write(id) {
      if (id === identity) throw new Error("ENOSPC");
      savedReports++;
    },
  });
  assert.doesNotThrow(() => worker.afterSave(saved));
  assert.doesNotThrow(() => worker.afterSave({ google_place_id: second.providerPlaceID }));
  await worker.idle();
  assert.equal(errors, 1);
  assert.equal(savedReports, 1);
});

test("uses a reviewed author hint ahead of general search without promoting the candidate", async () => {
  const queryInput: unknown[] = [];
  const candidates: unknown[] = [];
  const profiles = [{ platform: "instagram" as const, handle: "fixture", branchTerms: ["華西街"] }];
  const profileLead = {
    platform: "instagram" as const, sourceURL: "https://www.instagram.com/p/ProfileFixture/",
    authorHandle: "fixture", title: "", review: null, observedIn: "https://www.instagram.com/fixture/",
  };
  const venues = new Map([[identity, { place, missing: ["instagram" as const], profiles }]]);
  const worker = createPublicDiscoverySaveIntake({
    inventory: venues,
    async profileLookup(input) {
      queryInput.push(input);
      return { draft: { venues: [{ place, candidates: [profileLead] }] },
        profiles: [{ platform: "instagram", handle: "fixture", status: "read", readablePosts: 1 }] };
    },
    async search() { assert.fail("General web search should not run when a profile yielded candidates"); },
    async write(_, report) { candidates.push(...report.candidates); },
  });
  worker.afterSave(saved);
  await worker.idle();
  assert.deepEqual(queryInput, [{ venues: [{ place, profiles: [{ ...profiles[0], terms: [place.name] }] }] }]);
  assert.deepEqual(candidates, [profileLead]);
});

test("queue validation retains only current public IDs and rejects duplicate or invalid jobs", () => {
  const job = { identity, pending: true, dueAt: 1 };
  const valid = { version: 1, backoffUntil: 0, jobs: [job, { ...job, identity: "retired" }] };
  const allowed = new Set([identity]);
  assert.deepEqual(parsePublicSourceQueue(valid, allowed).jobs, [job]);
  assert.throws(() => parsePublicSourceQueue({ ...valid, jobs: [job, job] }, allowed), /Invalid public source queue job/);
  assert.throws(() => parsePublicSourceQueue({ ...valid, jobs: [{ ...job, catalogDueAt: -1 }] }, allowed),
    /Invalid public source queue job/);
  assert.throws(() => parsePublicSourceQueue({ ...valid, backoffUntil: -1 }, allowed), /Invalid public source queue state/);
});

test("queues a saved official destination only with its exact WGS84 identity", async () => {
  const official: PublicDiscoveryPlace = {
    provider: "taipei_catalog", providerPlaceID: "Attraction_379000000A_002265",
    name: "白石湖休閒農業區", address: "臺北市內湖區", latitude: 25.105136,
    longitude: 121.594043, coordinateSystem: "WGS84", category: "area",
  };
  const id = JSON.stringify([official.provider, official.providerPlaceID]);
  const queries: string[] = [];
  const worker = createPublicDiscoverySaveIntake({
    inventory: new Map([[id, { place: official, missing: ["threads"] }]]),
    async search(query) { queries.push(query); return []; },
    async write(identity, result) {
      assert.equal(identity, id);
      assert.deepEqual(result.place, official);
    },
  });
  const row = { location_provider: null, google_place_id: null, provider_place_id: official.providerPlaceID,
    coordinate_system: "WGS84", name: "PRIVATE ENTRY" };
  await worker.afterSave({ ...row, coordinate_system: "GCJ-02" },
    { ...row, provider_place_id: "Attraction_379000000A_999999" });
  await worker.idle();
  assert.equal(queries.length, 0);
  await worker.afterSave(row);
  await worker.idle();
  assert.equal(queries.length, 1);
  assert.match(queries[0]!, /白石湖休閒農業區/);
  assert.doesNotMatch(queries[0]!, /PRIVATE ENTRY/);
});

test("requires a configured serving index before starting discovery intake", async () => {
  await assert.rejects(loadPublicDiscoverySaveIntake("/unused-savvy-intake-fixture"), /Expected a public discovery index/);
});

test("persistent state can restore more than 5000 exact configured places", () => {
  const jobs = Array.from({ length: 5_001 }, (_, index) => ({
    identity: JSON.stringify(["apple_maps", "venue-" + index]), pending: true, dueAt: 0,
  }));
  const state = { version: 1, backoffUntil: 0, jobs };
  assert.deepEqual(parsePublicSourceQueue(state, new Set(jobs.map(job => job.identity))), state);
});

test("a failed admission write creates no lookup and allows a later save to requeue", async () => {
  let persisted = 0;
  let calls = 0;
  let errors = 0;
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(),
    async persist() {
      if (++persisted === 1) throw new Error("ENOSPC");
    },
    async write() {},
    async search() { calls++; return []; },
    retryableFailure: () => { errors++; },
  });
  await worker.afterSave(saved);
  await worker.idle();
  assert.equal(calls, 0);
  assert.equal(errors, 1);
  await worker.afterSave(saved);
  await worker.idle();
  assert.equal(calls, 2);
  assert.equal(persisted, 3);
});

test("an Instagram profile cooldown leaves the independent Threads lookup available", async () => {
  const profiles = [
    { platform: "instagram" as const, handle: "fixture", branchTerms: ["華西街"] },
    { platform: "threads" as const, handle: "fixture", branchTerms: ["華西街"] },
  ];
  const lead = {
    platform: "threads" as const, sourceURL: "https://www.threads.com/@fixture/post/Independent",
    authorHandle: "fixture", title: "", review: null, observedIn: "https://www.threads.com/@fixture",
  };
  const at = Date.parse("2026-11-23T05:00:00Z");
  let now = at;
  const calls: string[] = [];
  const reports: unknown[] = [];
  const worker = createPublicDiscoverySaveIntake({
    inventory: new Map([[identity, { place, missing: ["instagram", "threads"], profiles }]]),
    now: () => now,
    async profileLookup(input) {
      const profile = (input as { venues: { profiles: typeof profiles }[] }).venues[0]!.profiles[0]!;
      calls.push(profile.platform);
      const fromThreads = profile.platform === "threads";
      return {
        draft: { venues: fromThreads ? [{ place, candidates: [lead] }] : [] },
        profiles: [{ platform: profile.platform, handle: profile.handle,
          status: fromThreads ? "read" : "rate_limited", readablePosts: fromThreads ? 1 : 0 }],
      };
    },
    async search() { assert.fail("Do not fall back on the rate-limited profile"); },
    async write(_, report) { reports.push({ coverage: report.coverage, candidates: report.candidates }); },
  });
  await worker.afterSave(saved);
  await worker.idle();
  now += 15 * 60_000 - 1;
  await worker.idle();
  assert.deepEqual(calls, ["instagram", "threads"]);
  now++;
  await worker.idle();
  assert.deepEqual(calls, ["instagram", "threads", "instagram", "threads"]);
  assert.deepEqual(reports, Array.from({ length: 2 }, () => ({
    coverage: { instagram: "rate_limited", threads: "searched" }, candidates: [lead],
  })));
});

for (const [failure, status] of [
  ["Public search requires verification", "access_required"],
  ["Provider HTTP 429", "rate_limited"],
] as const) {
  test(`a halted general search leaves the independent Threads author lookup available (${status})`, async () => {
    const profiles = [
      { platform: "instagram" as const, handle: "fixture", branchTerms: ["華西街"] },
      { platform: "threads" as const, handle: "fixture", branchTerms: ["華西街"] },
    ];
    const venues = new Map([[identity, { place, missing: ["instagram" as const, "threads" as const], profiles }]]);
    const lead = {
      platform: "threads" as const, sourceURL: "https://www.threads.com/@fixture/post/ProfileFixture",
      authorHandle: "fixture", title: "", review: null, observedIn: "https://www.threads.com/@fixture",
    };
    const calls: string[] = [];
    const reports: unknown[] = [];
    const worker = createPublicDiscoverySaveIntake({
      inventory: venues,
      async profileLookup(input) {
        const profile = (input as { venues: { profiles: typeof profiles }[] }).venues[0]!.profiles[0]!;
        calls.push(profile.platform);
        return {
          draft: { venues: profile.platform === "threads" ? [{ place, candidates: [lead] }] : [] },
          profiles: [{ platform: profile.platform, handle: profile.handle, status: "read", readablePosts: 1 }],
        };
      },
      async search(query) {
        calls.push(query.includes("instagram.com") ? "search instagram" : "search threads");
        throw new Error(failure);
      },
      async write(_, report) { reports.push({ coverage: report.coverage, candidates: report.candidates }); },
    });
    await worker.afterSave(saved);
    await worker.idle();
    assert.deepEqual(calls, ["instagram", "search instagram", "threads"]);
    assert.deepEqual(reports, [{ coverage: { instagram: status, threads: "searched" }, candidates: [lead] }]);
  });
}

test("scans configured public gaps without a save and preserves its rate across restart", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  let now = at;
  const reports: string[] = [];
  let lastState: QueueState | undefined;
  const catalog = [...inventory()].reverse();
  const options = {
    inventory: new Map(catalog), catalogScan: true, now: () => now,
    async search() { return []; },
    async write(id: string) { reports.push(id); },
    async persist(state: QueueState) { lastState = state; },
  };
  await createPublicDiscoverySaveIntake(options).idle();
  assert.deepEqual(reports, [identity], "visit places with neither platform first");
  assert.ok(lastState);
  const restored = parsePublicSourceQueue(JSON.parse(JSON.stringify(lastState)), new Set(options.inventory.keys()));
  now = at + 59 * 1_000;
  const restarted = createPublicDiscoverySaveIntake({ ...options, initialState: restored });
  await restarted.idle();
  assert.deepEqual(reports, [identity]);
  now = at + 60 * 1_000;
  await restarted.idle();
  assert.deepEqual(reports, [identity, catalog[0]![0]]);
  now += 3 * 24 * 60 * 60 * 1_000;
  await restarted.idle();
  assert.equal(reports.length, 2, "do not rescan a completed catalog pass");
});

test("catalog scan waits for the saved-place queue and restores a provider limit", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  let now = at;
  const secondIdentity = JSON.stringify([second.provider, second.providerPlaceID]);
  const known = new Set(inventory().keys());
  const initial: QueueState = { version: 1, backoffUntil: 0, jobs: [{ identity: secondIdentity, pending: true, dueAt: at }] };
  const attempts: string[] = [];
  const reports: string[] = [];
  let snapshot: QueueState | undefined;
  const first = createPublicDiscoverySaveIntake({
    inventory: inventory(), catalogScan: true, initialState: initial, now: () => now,
    async search(query) { attempts.push(query); throw Error("Provider HTTP 429"); },
    async write(id) { reports.push(id); },
    async persist(state) { snapshot = state; },
  });
  await first.idle();
  assert.deepEqual(reports, [secondIdentity]);
  assert.equal(attempts.length, 1);
  assert.ok(snapshot);
  assert.deepEqual(snapshot.jobs.map(job => job.identity), [secondIdentity]);
  const restored = parsePublicSourceQueue(JSON.parse(JSON.stringify(snapshot)), known);
  const secondWorker = createPublicDiscoverySaveIntake({
    inventory: inventory(), catalogScan: true, initialState: restored, now: () => now,
    async search(query) { attempts.push(query); return []; },
    async write(id) { reports.push(id); },
  });
  await secondWorker.idle();
  assert.equal(attempts.length, 1);
  now = at + 15 * 60 * 1_000;
  await secondWorker.idle();
  assert.deepEqual(reports, [secondIdentity, secondIdentity, identity]);
});

test("rechecks catalog gaps after a week across restart without re-saving the place", async () => {
  const week = 7 * 24 * 60 * 60 * 1_000;
  const minute = 60 * 1_000;
  const start = Date.parse("2026-11-23T05:00:00Z");
  let now = start;
  const reports: { id: string; links: string[] }[] = [];
  let snapshot: QueueState | undefined;
  const options = {
    inventory: inventory(), catalogScan: true, now: () => now,
    async search(query: string) {
      return now >= start + week && query.includes("instagram.com")
        ? [{ query, url: "https://www.instagram.com/p/NewPublicOriginal/", title: "New original" }]
        : [];
    },
    async write(id: string, result: { candidates: { sourceURL: string }[] }) {
      reports.push({ id, links: result.candidates.map(row => row.sourceURL) });
    },
    async persist(state: QueueState) { snapshot = state; },
  };
  const first = createPublicDiscoverySaveIntake(options);
  await first.idle();
  now += minute;
  await first.idle();
  const secondIdentity = JSON.stringify([second.provider, second.providerPlaceID]);
  assert.deepEqual(reports, [{ id: identity, links: [] }, { id: secondIdentity, links: [] }]);
  assert.ok(snapshot);

  now = start + week - 1;
  const restored = parsePublicSourceQueue(JSON.parse(JSON.stringify(snapshot)), new Set(options.inventory.keys()));
  const restarted = createPublicDiscoverySaveIntake({ ...options, initialState: restored });
  await restarted.idle();
  assert.equal(reports.length, 2);
  now++;
  await restarted.idle();
  assert.deepEqual(reports.map(row => row.id), [identity, secondIdentity, identity]);
  assert.deepEqual(reports[2]?.links, ["https://www.instagram.com/p/NewPublicOriginal/"]);
  now += minute;
  await restarted.idle();
  assert.deepEqual(reports.map(row => row.id), [identity, secondIdentity, identity, secondIdentity]);
});

test("rechecks existing version-one completed jobs after their legacy cooldown", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  const week = 7 * 24 * 60 * 60 * 1_000;
  const initial: QueueState = { version: 1, backoffUntil: 0, jobs: [{ identity, pending: false, dueAt: at }] };
  const knownInventory = new Map([[identity, inventory().get(identity)!]]);
  const restored = parsePublicSourceQueue(initial, new Set(knownInventory.keys()));
  let now = at + week - 1;
  let reads = 0;
  const worker = createPublicDiscoverySaveIntake({
    inventory: knownInventory, catalogScan: true, initialState: restored, now: () => now,
    async search() { reads++; return []; },
    async write() {},
  });
  await worker.idle();
  assert.equal(reads, 0);
  now++;
  await worker.idle();
  assert.equal(reads, 2);
});

test("reads current platform coverage on each save without replacing the worker", async () => {
  const day = 24 * 60 * 60 * 1_000;
  let now = Date.parse("2026-11-23T05:00:00Z");
  const venue = inventory().get(identity)!;
  let missing: typeof venue.missing = ["threads"];
  const queries: string[] = [];
  const drafts: string[] = [];
  const worker = createPublicDiscoverySaveIntake({
    inventory: new Map([[identity, { ...venue, missing: ["instagram", "threads"] }]]),
    now: () => now,
    async readMissingPlatforms(placeToRead) {
      assert.deepEqual(placeToRead, place);
      return missing;
    },
    async search(query) { queries.push(query); return []; },
    async write(id) { drafts.push(id); },
  });
  await worker.afterSave(saved);
  await worker.idle();
  assert.equal(queries.length, 1);
  assert.match(queries[0]!, /threads\.com|threads\.net/);

  now += day;
  missing = [];
  await worker.afterSave(saved);
  await worker.idle();
  assert.equal(queries.length, 1);
  assert.deepEqual(drafts, [identity]);

  now += day;
  missing = ["instagram"];
  await worker.afterSave(saved);
  await worker.idle();
  assert.equal(queries.length, 2);
  assert.match(queries[1]!, /instagram\.com/);
  assert.deepEqual(drafts, [identity, identity]);
});

test("persists a provider cooldown before publishing a catalog draft", async () => {
  const at = Date.parse("2026-11-23T05:00:00Z");
  let lastState: QueueState | undefined;
  let stateDuringDraft: QueueState | undefined;
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(), catalogScan: true, now: () => at,
    async search() { throw Error("Public search requires verification"); },
    async persist(state) { lastState = state; },
    async write() { stateDuringDraft = lastState; },
  });
  await worker.idle();
  assert.ok(stateDuringDraft, "draft must be written");
  assert.equal(stateDuringDraft.backoffUntil, at + 15 * 60 * 1_000);
  assert.equal(stateDuringDraft.jobs[0]?.pending, true);
  assert.equal(lastState?.jobs[0]?.pending, false);
});

test("a retry with no search results retains its earlier unreviewed draft", async t => {
  const directory = await mkdtemp(join(tmpdir(), "public-source-intake-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const sourceURL = "https://www.instagram.com/p/RetryFixture/";
  const initialTime = Date.parse("2026-11-23T05:00:00Z");
  let now = initialTime;
  const worker = createPublicDiscoverySaveIntake({
    inventory: inventory(),
    now: () => now,
    async search(query) {
      if (now !== initialTime) return [];
      if (query.includes("instagram.com")) return [{ query, url: sourceURL, title: "Public draft" }];
      throw new Error("HTTP 429");
    },
    write: (id, report) => writePublicSourceIntakeDraft(directory, id, report),
  });
  await worker.afterSave(saved);
  await worker.idle();
  now += 15 * 60_000;
  await worker.idle();
  const readReports = async () => Promise.all((await readdir(directory)).map(async file =>
    JSON.parse(await readFile(join(directory, file), "utf8"))));
  const reports = await readReports();
  assert.ok(reports.some(report => report.coverage.threads === "searched" && report.candidates.length === 0));
  const candidates = reports.flatMap(report => report.candidates);
  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].sourceURL, sourceURL);
  assert.equal(candidates[0].review, null);
  await writePublicSourceIntakeDraft(directory, identity, {
    ...reports.find(report => report.candidates.length),
    checkedAt: new Date(now).toISOString(),
  });
  assert.equal((await readReports()).length, 2, "an identical candidate batch reuses its filename");
});
