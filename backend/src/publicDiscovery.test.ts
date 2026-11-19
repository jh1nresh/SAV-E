import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import {
  listPublicDiscoveryPosts, PublicDiscoveryError, publicDiscoveryMaxFileBytes,
  validatePublicDiscoveryManifest, type PublicDiscoveryPost,
} from "./publicDiscovery.js";

const now = new Date("2026-11-14T12:00:00.000Z");
const iso = (delta: number) => new Date(now.getTime() + delta).toISOString();
const day = 86_400_000;
function post(id = "POST1", overrides: Partial<PublicDiscoveryPost> = {}): PublicDiscoveryPost {
  return {
    id: `threads:${id}`, platform: "threads", sourceURL: `https://www.threads.com/@fixture/post/${id}`,
    authorName: "Fixture publisher", authorHandle: "fixture", title: "Synthetic public post",
    publishedAt: null, verifiedAt: now.toISOString(), visibility: "public", locationEvidence: "reviewed_match",
    cover: null, place: { provider: "apple_maps", providerPlaceID: `fixture-venue-${id}`, name: "Fixture cafe",
      address: "1 Fixture Street", latitude: 25.03, longitude: 121.54, coordinateSystem: "WGS84", category: "cafe" },
    ...overrides,
  };
}
// Deliberately untrusted JSON shapes, not a second typed implementation of the validator.
function manifest(posts: unknown[] = [post()]): Record<string, any> {
  const connected = new Set(posts.map(value => (value as Record<string, unknown>)?.platform));
  return { schemaVersion: 1, generatedAt: now.toISOString(), expiresAt: iso(day),
    coverage: ["instagram", "threads", "xiaohongshu"].map(platform => ({ platform,
      status: connected.has(platform) ? "connected" : "not_connected" })), posts };
}
const failure = (status: 400 | 503) => (error: unknown) => error instanceof PublicDiscoveryError
  && error.statusCode === status && error.code === (status === 503 ? "public_discovery_unavailable" : "public_discovery_invalid_query");
const validate = (input: unknown) => validatePublicDiscoveryManifest(input, now);
const url = (query = "bbox=121,25,122,26&limit=2") => new URL(`https://fixture.invalid/v0/discovery/posts?${query}`);
async function indexFile(t: TestContext, input: unknown): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "savvy-public-discovery-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filePath = join(directory, "index.json");
  await writeFile(filePath, typeof input === "string" || Buffer.isBuffer(input) ? input : JSON.stringify(input));
  return filePath;
}
async function read(filePath: string, query?: string) {
  return listPublicDiscoveryPosts(url(query), { filePath, now });
}

test("exact Google venues are opt-in, scoped by ID and incompatible with alias collisions", async t => {
  const apple = post("APPLE");
  const googleID = "ChIJ_exact_101";
  const googlePlace: PublicDiscoveryPost["place"] = {
    ...apple.place, provider: "google_places", providerPlaceID: googleID,
  };
  const googlePosts = [post("GOOGLE1", { place: googlePlace }), post("GOOGLE2", { place: googlePlace })];
  const index = manifest([apple, ...googlePosts]);
  const filePath = await indexFile(t, index);
  const explicit = (query: string) => listPublicDiscoveryPosts(url(query), { filePath, now, googleVenues: true });
  const query = "bbox=121,25,122,26";
  const exact = query + "&provider=google_places&placeID=" + googleID;
  const legacy = await read(filePath, query);
  assert.deepEqual(legacy.posts, [apple]);
  assert.equal(legacy.coverage.find(row => row.platform === "threads")?.indexedPostCount, 1);
  assert.deepEqual((await read(filePath, exact)).posts, []);
  assert.equal((await explicit(query)).posts.length, 3);
  const scoped = await explicit(exact + "&limit=1");
  assert.deepEqual(scoped.posts, [googlePosts[0]]);
  assert.equal(scoped.googlePlaceMatch, undefined);
  assert.ok(scoped.nextCursor);
  const nextQuery = exact + "&limit=1&cursor=" + scoped.nextCursor;
  assert.deepEqual((await explicit(nextQuery)).posts, [googlePosts[1]]);
  await assert.rejects(read(filePath, nextQuery), failure(400));
  assert.deepEqual((await explicit(query + "&provider=google_places&placeID=" + googleID.toLowerCase())).posts, []);
  const collision = { ...index, googlePlaceAliases: [{
    googlePlaceID: googleID, provider: "apple_maps", providerPlaceID: apple.place.providerPlaceID,
  }] };
  assert.throws(() => validate(collision), failure(503));
  const badPlace = { ...googlePlace, providerPlaceID: "not a place ID" };
  assert.throws(() => validate(manifest([post("GOOGLE", { place: badPlace })])), failure(503));
});

test("dedicated file is required; empty/missing configuration is not a seeded success", async t => {
  await assert.rejects(listPublicDiscoveryPosts(url(), { filePath: "", now }), failure(503));
  const path = await indexFile(t, manifest());
  await assert.rejects(read(join(path, "missing")), failure(503));
  const prior = process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE;
  t.after(() => { if (prior === undefined) delete process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE; else process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE = prior; });
  process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE = path;
  assert.equal((await listPublicDiscoveryPosts(url(), { now })).posts.length, 1);
});

test("malformed JSON, invalid UTF-8, unsupported schema and oversized files fail closed", async t => {
  for (const input of ["{", Buffer.from([0xff, 0xfe]), { ...manifest(), schemaVersion: 2 }, Buffer.alloc(publicDiscoveryMaxFileBytes + 1)]) {
    await assert.rejects(read(await indexFile(t, input)), failure(503));
  }
});

test("only regular files are read and configured symlinks are rejected", async t => {
  const path = await indexFile(t, manifest());
  const alias = `${path}.link`, directory = `${path}.directory`;
  await symlink(path, alias);
  await mkdir(directory);
  await assert.rejects(read(alias), failure(503));
  await assert.rejects(read(directory), failure(503));
});

test("strict keys reject accidental private exports at every manifest depth", () => {
  const mutations: Array<(input: Record<string, any>) => void> = [
    value => { value.captures = []; }, value => { value.ownerSubject = "PRIVATE"; },
    value => { value.posts[0].note = "PRIVATE"; }, value => { value.posts[0].caption = "PRIVATE"; },
    value => { value.posts[0].userId = "PRIVATE"; }, value => { value.posts[0].place.rating = 5; },
    value => { value.posts[0].place.sourceUrl = "https://example.invalid/PRIVATE"; },
    value => { value.coverage[0].indexedPostCount = 99; },
    value => { value.posts[0].cover = { url: "https://scontent.fbcdn.net/fixture.jpg", expiresAt: iso(60_000), permission: "author", privatePhoto: true }; },
  ];
  for (const mutate of mutations) { const input = manifest(); mutate(input); assert.throws(() => validate(input), failure(503)); }
  const polluted = JSON.parse(JSON.stringify(manifest()).replace('"schemaVersion":1', '"schemaVersion":1,"__proto__":{"private":true}'));
  assert.throws(() => validate(polluted), failure(503));
});

test("all three coverage entries are required, unique and consistent with actual indexed posts", () => {
  const valid = validate(manifest());
  assert.deepEqual(valid.coverage, [
    { platform: "instagram", status: "not_connected", indexedPostCount: 0 },
    { platform: "threads", status: "connected", indexedPostCount: 1 },
    { platform: "xiaohongshu", status: "not_connected", indexedPostCount: 0 },
  ]);
  for (const change of [
    (value: Record<string, any>) => { value.coverage.pop(); },
    (value: Record<string, any>) => { value.coverage[0] = value.coverage[1]; },
    (value: Record<string, any>) => { value.coverage[1].status = "not_connected"; },
    (value: Record<string, any>) => { value.coverage[1].status = ["connected"]; },
  ]) { const input = manifest(); change(input); assert.throws(() => validate(input), failure(503)); }
});

test("future, stale, overlong and impossible manifest/source timestamps are rejected", () => {
  const changes: Array<(value: Record<string, any>) => void> = [
    value => { value.generatedAt = iso(1); }, value => { value.generatedAt = iso(-day); },
    value => { value.expiresAt = now.toISOString(); }, value => { value.expiresAt = iso(day + 1); },
    value => { value.posts[0].verifiedAt = iso(1); }, value => { value.posts[0].verifiedAt = iso(-day); },
    value => { value.posts[0].publishedAt = iso(1); }, value => { value.posts[0].verifiedAt = "2026-02-30T12:00:00Z"; },
    value => { value.posts[0].verifiedAt = "November 14, 2026"; },
  ];
  for (const change of changes) { const input = manifest(); change(input); assert.throws(() => validate(input), failure(503)); }
});

test("response expires at the earliest manifest, source check, cover or five-minute deadline", async t => {
  assert.equal((await read(await indexFile(t, manifest()))).expiresAt, iso(300_000));
  const short = manifest(); short.expiresAt = iso(1_000);
  assert.equal((await read(await indexFile(t, short))).expiresAt, iso(1_000));
  const source = manifest([post("OLD", { verifiedAt: iso(-day + 2_000) })]);
  assert.equal((await read(await indexFile(t, source))).expiresAt, iso(2_000));
  const cover = manifest([post("COVER", { cover: { url: "https://scontent.fbcdn.net/fixture.jpg", expiresAt: iso(3_000), permission: "provider" } })]);
  assert.equal((await read(await indexFile(t, cover))).expiresAt, iso(3_000));
});

test("an expired post and cover do not remove other venues from a current snapshot", async t => {
  const old = post("OLD", { verifiedAt: iso(-day + 2_000) });
  const fresh = post("FRESH", { cover: {
    url: "https://scontent.fbcdn.net/fixture.jpg", expiresAt: iso(3_000), permission: "author",
  } });
  const input = manifest([post("NEW"), old, fresh]);
  input.googlePlaceAliases = [
    { googlePlaceID: "ChIJOld", provider: "apple_maps", providerPlaceID: old.place.providerPlaceID },
    { googlePlaceID: "ChIJFresh", provider: "apple_maps", providerPlaceID: fresh.place.providerPlaceID },
  ];
  const filePath = await indexFile(t, input);
  const first = await read(filePath, "bbox=121,25,122,26&limit=1");
  assert.ok(first.nextCursor);
  const expired = new Date(iso(2_000));
  const active = await listPublicDiscoveryPosts(url(), { filePath, now: expired });
  assert.deepEqual(active.posts.map(post => post.id), ["threads:FRESH", "threads:NEW"]);
  assert.equal(active.coverage.find(row => row.platform === "threads")?.indexedPostCount, 2);
  assert.notEqual(active.indexRevision, first.indexRevision);
  assert.equal(active.expiresAt, iso(3_000));
  await assert.rejects(listPublicDiscoveryPosts(
    url(`bbox=121,25,122,26&limit=1&cursor=${first.nextCursor}`), { filePath, now: expired },
  ), failure(400));

  const oldSaved = await listPublicDiscoveryPosts(
    url("bbox=121,25,122,26&provider=google_places&placeID=ChIJOld"), { filePath, now: expired },
  );
  assert.deepEqual(oldSaved.posts, []);
  assert.equal(oldSaved.googlePlaceMatch, undefined);
  const currentTime = new Date(iso(3_000));
  const freshSaved = await listPublicDiscoveryPosts(
    url("bbox=121,25,122,26&provider=google_places&placeID=ChIJFresh"), { filePath, now: currentTime },
  );
  assert.equal(freshSaved.googlePlaceMatch?.providerPlaceID, fresh.place.providerPlaceID);
  assert.deepEqual(freshSaved.posts, [{ ...fresh, cover: null }]);
  assert.notEqual(freshSaved.indexRevision, active.indexRevision);

  // Validate hidden rows too, and never extend a legacy artifact's declared deadline.
  input.posts[1].note = "PRIVATE";
  await writeFile(filePath, JSON.stringify(input));
  await assert.rejects(listPublicDiscoveryPosts(url(), { filePath, now: currentTime }), failure(503));
  delete input.posts[1].note;
  input.expiresAt = iso(2_000);
  await writeFile(filePath, JSON.stringify(input));
  await assert.rejects(listPublicDiscoveryPosts(url(), { filePath, now: currentTime }), failure(503));
});

test("source URLs canonicalize only supported real post paths and retain no tracking", () => {
  const inputs = [
    post("REEL_1", { id: "instagram:REEL_1", platform: "instagram", sourceURL: "https://instagram.com/reels/REEL_1?igsh=tracking#fragment" }),
    post("THREAD_1", { sourceURL: "https://threads.net/@fixture/post/THREAD_1/?utm_source=fixture#fragment" }),
    post("abcdef123456abcdef123456", { id: "xiaohongshu:abcdef123456abcdef123456", platform: "xiaohongshu",
      sourceURL: "https://www.xiaohongshu.com/discovery/item/ABCDEF123456ABCDEF123456?utm_source=fixture" }),
  ];
  const normalized = new Map(validate(manifest(inputs)).posts.map(post => [post.platform, post.sourceURL]));
  assert.equal(normalized.get("instagram"), "https://www.instagram.com/reel/REEL_1/");
  assert.equal(normalized.get("threads"), "https://www.threads.com/@fixture/post/THREAD_1");
  assert.equal(normalized.get("xiaohongshu"), "https://www.xiaohongshu.com/explore/abcdef123456abcdef123456");
});

test("profile, search, login, short share, foreign host and credential source URLs are rejected", () => {
  const values = ["https://threads.com/@fixture", "https://threads.com/search?q=fixture", "https://threads.com/login",
    "https://threads.net/t/POST1", "http://threads.com/@fixture/post/POST1", "https://threads.com.evil.invalid/@fixture/post/POST1",
    "https://user:password@threads.com/@fixture/post/POST1", "https://threads.com:8443/@fixture/post/POST1",
    "https://threads.com/@fixture/post/POST1%2fOTHER"];
  for (const sourceURL of values) assert.throws(() => validate(manifest([post("POST1", { sourceURL })])), failure(503), sourceURL);
  for (const sourceURL of ["https://instagram.com/fixture/", "https://instagram.com/share/reel/POST1"])
    assert.throws(() => validate(manifest([post("POST1", { id: "instagram:POST1", platform: "instagram", sourceURL })])), failure(503));
  assert.throws(() => validate(manifest([post("abcdef123456abcdef123456", { id: "xiaohongshu:abcdef123456abcdef123456",
    platform: "xiaohongshu", sourceURL: "https://xhslink.com/fixture" })])), failure(503));
});

test("access-token-style query and fragment keys are rejected rather than laundered by normalization", () => {
  for (const suffix of ["?access_token=PRIVATE", "?accessToken=PRIVATE", "?%61ccess_token=PRIVATE", "?xsec_token=PRIVATE",
    "?api-key=PRIVATE", "?auth=PRIVATE", "?session=PRIVATE", "#access_token=PRIVATE", "#token=PRIVATE"]) {
    assert.throws(() => validate(manifest([post("POST1", { sourceURL: post().sourceURL + suffix })])), failure(503));
  }
});

test("post identity, public status, reliable geo association and field types are mandatory", () => {
  const changes: Array<(value: Record<string, any>) => void> = [
    value => { value.posts[0].id = "threads:OTHER"; }, value => { value.posts[0].visibility = "friends"; },
    value => { value.posts[0].visibility = "private"; }, value => { value.posts[0].locationEvidence = "unresolved"; },
    value => { value.posts[0].locationEvidence = ["reviewed_match"]; }, value => { value.posts[0].title = "a".repeat(161); },
    value => { value.posts[0].authorName = "a".repeat(81); }, value => { value.posts[0].authorHandle = "a".repeat(101); },
    value => { value.posts[0].place.coordinateSystem = "GCJ-02"; }, value => { value.posts[0].place.provider = "unverified_provider"; },
    value => { value.posts[0].place.provider = ["apple_maps"]; }, value => { value.posts[0].place.providerPlaceID = " "; },
    value => { value.posts[0].place.address = ""; }, value => { value.posts[0].place.latitude = NaN; },
    value => { value.posts[0].place.longitude = Infinity; }, value => { value.posts[0].place.latitude = 91; },
    value => { value.posts[0].place.longitude = 181; }, value => { value.posts[0].place.latitude = 0; value.posts[0].place.longitude = 0; },
  ];
  for (const change of changes) { const input = manifest(); change(input); assert.throws(() => validate(input), failure(503)); }
});

test("unavailable authors and original publication time stay null; no invented author or date", () => {
  const normalized = validate(manifest([post("POST1", { authorName: null, authorHandle: null, publishedAt: null })])).posts[0];
  assert.equal(normalized.authorName, null); assert.equal(normalized.authorHandle, null); assert.equal(normalized.publishedAt, null);
  assert.equal(normalized.cover, null);
  const input = manifest(); delete input.posts[0].cover;
  assert.equal(validate(input).posts[0].cover, null);
});

test("covers require preview grant, freshness and the matching platform's recognized image CDN", () => {
  const valid = { url: "https://scontent.fbcdn.net/fixture.jpg?oh=public-preview-signature", expiresAt: iso(60_000), permission: "author" };
  assert.equal(validate(manifest([post("POST1", { cover: valid as PublicDiscoveryPost["cover"] })])).posts[0].cover?.url, valid.url);
  const bad = [
    { ...valid, permission: null }, { ...valid, permission: "none" }, { ...valid, permission: ["author"] },
    { ...valid, expiresAt: now.toISOString() }, { ...valid, url: "https://images.example.invalid/fixture.jpg" },
    { ...valid, url: "https://127.0.0.1/fixture.jpg" }, { ...valid, url: "https://localhost/fixture.jpg" },
    { ...valid, url: "https://scontent.fbcdn.net.evil.invalid/fixture.jpg" },
    { ...valid, url: "https://user:secret@scontent.fbcdn.net/fixture.jpg" },
    { ...valid, url: "https://scontent.fbcdn.net/fixture.jpg?access_token=PRIVATE" },
    { ...valid, url: "http://scontent.fbcdn.net/fixture.jpg" }, { ...valid, url: "https://sns-img.xhscdn.com/fixture.jpg" },
  ];
  for (const cover of bad) assert.throws(() => validate(manifest([{ ...post(), cover }])), failure(503));
  const xhs = post("abcdef123456abcdef123456", { id: "xiaohongshu:abcdef123456abcdef123456", platform: "xiaohongshu",
    sourceURL: "https://www.xiaohongshu.com/explore/abcdef123456abcdef123456" });
  for (const host of ["sns-img-bd.xhscdn.com", "ci.xiaohongshu.com", "sns-webpic-qc.xiaohongshu.com"])
    assert.ok(validate(manifest([{ ...xhs, cover: { ...valid, url: `https://${host}/fixture.jpg` } }])).posts[0].cover);
  for (const host of ["www.xiaohongshu.com", "xiaohongshu.com", "scontent.fbcdn.net"])
    assert.throws(() => validate(manifest([{ ...xhs, cover: { ...valid, url: `https://${host}/fixture.jpg` } }])), failure(503));
});

test("duplicate post IDs and inconsistent fields for the same provider/place identity reject the entire index", () => {
  assert.throws(() => validate(manifest([post(), post()])), failure(503));
  const first = post("FIRST");
  for (const difference of [{ name: "Another cafe" }, { address: "Other branch" }, { category: "shopping" },
    { latitude: 25.030001 }, { longitude: 121.540001 }]) {
    assert.throws(() => validate(manifest([first, post("SECOND", { place: { ...first.place, ...difference } })])), failure(503));
  }
  const shared = validate(manifest([first, post("SECOND", { place: first.place, authorName: "Another publisher" })]));
  assert.equal(shared.posts.length, 2);
  assert.equal(validate(manifest([first, post("SECOND", { place: { ...first.place, provider: "amap", name: "Other provider venue" } })])).posts.length, 2);
});

test("post count is bounded before per-record processing", () => {
  assert.throws(() => validate(manifest(Array(5_001).fill(post()))), failure(503));
});

test("a valid empty viewport is successful and coverage counts remain index-wide", async t => {
  const response = await read(await indexFile(t, manifest()), "bbox=0,0,10,10");
  assert.deepEqual(response.posts, []);
  assert.equal(response.nextCursor, null);
  assert.equal(response.coverage.find(value => value.platform === "threads")?.indexedPostCount, 1);
  const disconnected = await read(await indexFile(t, manifest([])));
  assert.equal(disconnected.coverage.length, 3);
  assert.ok(disconnected.coverage.every(value => value.status === "not_connected" && value.indexedPostCount === 0));
});

function located(id: string, longitude: number, latitude = 25.03): PublicDiscoveryPost {
  return post(id, { place: { ...post(id).place, longitude, latitude } });
}
test("viewport is inclusive and handles dateline crossing and equivalent +/-180 edges", async t => {
  const path = await indexFile(t, manifest([located("EAST", 175), located("WEST", -175), located("MIDDLE", 0),
    located("EDGE_E", 180), located("EDGE_W", -180), located("OUT_LAT", 175, 40)]));
  const crossing = await read(path, "bbox=170,20,-170,30&limit=50");
  assert.deepEqual(crossing.posts.map(value => value.id), ["threads:EAST", "threads:EDGE_E", "threads:EDGE_W", "threads:WEST"]);
  const edge = await read(path, "bbox=-180,20,-170,30&limit=50");
  assert.deepEqual(edge.posts.map(value => value.id), ["threads:EDGE_E", "threads:EDGE_W", "threads:WEST"]);
  const point = await read(await indexFile(t, manifest([located("BOUNDARY", 121, 25)])), "bbox=121,25,122,26");
  assert.equal(point.posts.length, 1);
});

test("query syntax, duplicates, unknown fields and invalid limits fail 400 before index I/O", async () => {
  const invalid = ["", "bbox=1,2,3", "bbox=1,2,3,2", "bbox=1,NaN,3,4", "bbox=181,2,3,4", "bbox=1,-91,3,4",
    "bbox=1,2,3,Infinity", "bbox=1,,3,4", "bbox=1,2,3,4&limit=0", "bbox=1,2,3,4&limit=51",
    "bbox=1,2,3,4&limit=1.5", "bbox=1,2,3,4&limit=01", "bbox=1,2,3,4&limit=",
    "bbox=1,2,3,4&bbox=1,2,3,4", "bbox=1,2,3,4&limit=2&limit=2", "bbox=1,2,3,4&owner=PRIVATE",
    "bbox=1,2,3,4&cursor=", "bbox=1,2,3,4&cursor=garbage"];
  for (const query of invalid) await assert.rejects(listPublicDiscoveryPosts(url(query), { filePath: "", now }), failure(400), query);
});

test("pagination is deterministic, complete and retryable for equivalent normalized bounds", async t => {
  const posts = [post("C"), post("B"), post("A"), post("D", { verifiedAt: iso(-1_000) }), post("E", { verifiedAt: iso(-2_000) })];
  const path = await indexFile(t, manifest(posts));
  const first = await read(path);
  assert.deepEqual(first.posts.map(value => value.id), ["threads:A", "threads:B"]);
  assert.match(first.nextCursor!, /^[A-Za-z0-9_-]{43}$/);
  const second = await read(path, `limit=2&bbox=121.000,25.0,122,26&cursor=${first.nextCursor}`);
  assert.deepEqual(second.posts.map(value => value.id), ["threads:C", "threads:D"]);
  assert.deepEqual(await read(path, `bbox=121,25,122,26&limit=2&cursor=${first.nextCursor}`), second);
  const last = await read(path, `bbox=121,25,122,26&limit=2&cursor=${second.nextCursor}`);
  assert.deepEqual(last.posts.map(value => value.id), ["threads:E"]);
  assert.equal(last.nextCursor, null);
});

test("reviewed multi-venue originals page independently while legacy readers keep unique IDs", async t => {
  const first = post("SHARED", { multiVenue: true });
  const second = { ...first, place: { ...first.place, providerPlaceID: "other-branch", address: "2 Fixture Street" } };
  const miss = { ...second, multiVenue: undefined };
  assert.throws(() => validate(manifest([first, miss])), failure(503));
  assert.throws(() => validate(manifest([first, first])), failure(503));
  assert.throws(() => validate(manifest([first, { ...second, authorHandle: "changed" }])), failure(503));
  assert.throws(() => validate(manifest([first, { ...second, locationEvidence: "explicit_geotag" }])), failure(503));
  for (const providerPlaceID of ["Caf\u00e9", "Cafe\u0301", "branch,1"]) {
    assert.throws(() => validate(manifest([first, { ...second, place: { ...second.place, providerPlaceID } }])), failure(503));
  }
  const path = await indexFile(t, manifest([second, first, post("THIRD")]));
  const opts = { filePath: path, now, multiVenue: true };
  const single = url("bbox=121,25,122,26&limit=1");
  const legacy = await listPublicDiscoveryPosts(single, { filePath: path, now });
  const modern = await listPublicDiscoveryPosts(single, opts);
  assert.equal(legacy.coverage.find(item => item.platform === "threads")?.indexedPostCount, 2);
  assert.equal(modern.coverage.find(item => item.platform === "threads")?.indexedPostCount, 3);
  assert.equal(modern.posts[0]?.place.providerPlaceID, first.place.providerPlaceID);
  assert.ok(modern.nextCursor && legacy.nextCursor);
  single.searchParams.set("cursor", modern.nextCursor);
  const after = await listPublicDiscoveryPosts(single, opts);
  assert.equal(after.posts[0]?.id, first.id);
  assert.equal(after.posts[0]?.place.providerPlaceID, second.place.providerPlaceID);
  await assert.rejects(listPublicDiscoveryPosts(single, { filePath: path, now }), failure(400));
  const saved = await read(path, "bbox=121,25,122,26&provider=apple_maps&placeID=other-branch");
  assert.deepEqual(saved.posts, [second]);
  assert.deepEqual((await read(path)).posts.map(p => p.id), ["threads:SHARED", "threads:THIRD"]);
});

test("cursor cannot be replayed against another viewport, limit, index revision or an invented page", async t => {
  const body = manifest([post("A"), post("B"), post("C")]);
  const path = await indexFile(t, body);
  const first = await read(path);
  for (const query of [`bbox=120,24,123,27&limit=2&cursor=${first.nextCursor}`,
    `bbox=121,25,122,26&limit=1&cursor=${first.nextCursor}`, `bbox=121,25,122,26&limit=2&cursor=${"A".repeat(43)}`])
    await assert.rejects(read(path, query), failure(400));
  body.posts[0].title = "Changed public metadata";
  await writeFile(path, JSON.stringify(body));
  await assert.rejects(read(path, `bbox=121,25,122,26&limit=2&cursor=${first.nextCursor}`), failure(400));
});

test("normalized manifest order and tracking changes preserve revision, meaningful changes do not", async t => {
  const body = manifest([post("B"), post("A")]);
  const path = await indexFile(t, body);
  const first = await read(path);
  body.posts.reverse(); body.coverage.reverse(); body.posts[0].sourceURL += "?utm_source=another#tracking";
  await writeFile(path, JSON.stringify(body, null, 2));
  const second = await read(path);
  assert.equal(second.indexRevision, first.indexRevision);
  assert.deepEqual(second.posts, first.posts);
});

test("invalid replacements are rejected rather than serving a last-known-good cached index", async t => {
  const path = await indexFile(t, manifest());
  assert.equal((await read(path)).posts.length, 1);
  await writeFile(path, JSON.stringify({ ...manifest(), privateRecords: ["PRIVATE"] }));
  await assert.rejects(read(path), failure(503));
  await writeFile(path, JSON.stringify(manifest()));
  assert.equal((await read(path)).posts.length, 1);
  await assert.rejects(listPublicDiscoveryPosts(url(), { filePath: path, now: new Date(now.getTime() + day) }), failure(503));
});
