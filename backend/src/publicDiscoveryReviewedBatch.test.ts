import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { compileReviewedPublicBatch, compileReviewedPublicFiles,
  makeReviewedPublicPreview, publicVenueSourceCoverage, recheckReviewedPublicBatch,
  refreshReviewedPublicFiles } from "./publicDiscoveryReviewedBatch.js";
import { listPublicDiscoveryPosts, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { publicPostEvidenceFingerprint } from "./publicPostReverification.js";
import { evaluatePublicDiscoveryRequest } from "./publicDiscoveryEndpoint.js";

const now = new Date("2026-11-18T12:00:00Z");
const review = { checkedAt: "2026-11-18T10:00:00Z", origin: "public_web_index", branchEvidence: "Store name and floor matched." };
const threads = { platform: "threads", sourceURL: "https://threads.net/@example/post/TER_1?xmt=discard",
  authorHandle: null, title: "Store A", review };
const instagram = { platform: "instagram", sourceURL: "https://instagram.com/p/IG_1", authorHandle: "example",
  title: "Store A", review };
const place = { provider: "apple_maps", providerPlaceID: "BranchA", name: "Store A",
  address: "10 Example Rd, ground floor", latitude: 25.03, longitude: 121.56, coordinateSystem: "WGS84", category: "cafe" };
const other = { ...place, providerPlaceID: "Branch+B", name: "Store B", address: "10 Example Rd, basement" };
const batch = (...candidates: object[]) => ({ venues: [{ place, candidates }] });

test("Threads reply fingerprints bind the selected reply and optionally require its embedded parent", async () => {
  const permalink = "https://www.threads.com/@reply.author/post/REPLY";
  const parent = `<div class="OuterContainer">
    <div class="AuthorIdentity"><a class="HeaderLink" href="/@parent.author">parent</a></div>
    <div class="BodyContainerParent"><span class="BodyTextContainer">Parent asks for recommendations.</span></div>
    </div>`;
  const reply = `<div class="OuterContainer OuterContainerFull">
    <div class="AuthorIdentity"><a class="HeaderLink" href="/@reply.author">reply</a></div>
    <div class="BodyContainerNoThreadLine"><span class="BodyTextContainer">Store A is the exact branch mentioned.</span></div>
    </div>`;
  const html = `<div class="Embed"><div class="LinkContainer"><a href="${permalink}"></a></div>
    <div class="EmbedContainer">${parent}${reply}</div></div>`;
  const fingerprint = (markup: string, author = "reply.author") =>
    publicPostEvidenceFingerprint(markup, "threads", permalink, author, place as PublicDiscoveryPlace);
  const baseline = fingerprint(html);
  assert.ok(baseline);
  assert.equal(fingerprint(html.replace("Parent asks for recommendations.", "The parent has a new caption.")), baseline);
  assert.notEqual(fingerprint(html.replace("Store A is the exact branch mentioned.", "The reply names a different branch now.")), baseline);
  assert.equal(fingerprint(html, "parent.author"), undefined);
  assert.equal(fingerprint(html.replace("/post/REPLY", "/post/OTHER")), undefined);
  assert.equal(fingerprint(html.replace(reply, reply + reply)), undefined);
  assert.equal(fingerprint(html.replace(parent + reply, reply + parent)), undefined);
  assert.equal(fingerprint(html.replace("BodyContainerNoThreadLine", "BodyContainerParent")), undefined);
  assert.equal(fingerprint(html.replace(
    '<div class="BodyContainerNoThreadLine"><span class="BodyTextContainer">Store A is the exact branch mentioned.</span></div>',
    '<div class="BodyContainerNoThreadLine"></div><span class="BodyTextContainer">Unbound pretend reply body.</span>',
  )), undefined);

  const withContext = (markup: string) =>
    publicPostEvidenceFingerprint(markup, "threads", permalink, "reply.author", place as PublicDiscoveryPlace, true);
  const contextHash = withContext(html);
  assert.match(contextHash ?? "", /^threads-parent-v1:[a-f0-9]{64}$/);
  assert.notEqual(withContext(html.replace("Parent asks for recommendations.", "A different brand is being discussed.")), contextHash);
  assert.notEqual(withContext(html.replace("/@parent.author", "/@other.author")), contextHash);
  assert.equal(withContext(html.replace("/@parent.author", "https://www.threads.com.evil.example/@parent.author")), undefined);
  assert.equal(withContext(html.replace(parent, "")), undefined);
  assert.equal(withContext(html.replace(parent, parent.replace('class="OuterContainer"', 'class="OuterContainer" hidden'))), undefined);
  const contextual = { ...review, contentFingerprint: contextHash };
  assert.throws(() => compileReviewedPublicBatch(batch({ ...instagram, review: contextual }), now), /Invalid reviewed content fingerprint/);
  const input = batch({ ...threads, sourceURL: permalink, authorHandle: "reply.author", review: contextual });
  for (const [markup, expectedRefresh] of [
    [html, 1],
    [html.replace("Parent asks for recommendations.", "A different brand is being discussed."), 0],
    [html.replace(parent, ""), 0],
  ] as const) {
    const rechecked = await recheckReviewedPublicBatch(input, { now, fetchEmbed: async () => markup });
    assert.equal(rechecked.summary.refreshed, expectedRefresh);
    const resolved = compileReviewedPublicBatch(rechecked.batch, now).manifest.posts[0];
    assert.equal(resolved?.verifiedAt, expectedRefresh ? now.toISOString() : new Date(review.checkedAt).toISOString());
    assert.equal(Object.hasOwn(resolved!, "contentFingerprint"), false);
  }
});

test("venue highlights preserve all originals and compare only current likes on recent same-platform posts", () => {
  const observation = (count: number) => ({ count, observedAt: "2026-11-18T11:30:00Z" });
  const candidate = (code: string, publishedAt: string, publicLikes?: object) => ({
    ...instagram, sourceURL: `https://www.instagram.com/p/${code}/`,
    review: { ...review, publishedAt, ...(publicLikes ? { publicLikes } : {}) },
  });
  const noMetric = candidate("UNKNOWN", "2026-11-17T00:00:00Z");
  const newer = candidate("NEWER", "2026-11-16T00:00:00Z", observation(2));
  const higher = candidate("HIGHER", "2026-11-15T00:00:00Z", observation(5));
  const staleMetric = candidate("STALE", "2026-10-01T00:00:00Z", {
    count: 50_000, observedAt: "2026-10-10T00:00:00Z",
  });
  const oldest = candidate("OLD", "2025-11-12T00:00:00Z", observation(500_000));
  const ranked = (posts: ReturnType<typeof compileReviewedPublicBatch>["manifest"]["posts"]) =>
    posts.filter(row => row.highlightRank).sort((a, b) => a.highlightRank! - b.highlightRank!).map(row => row.id);
  const onlyInstagram = compileReviewedPublicBatch(batch(noMetric, newer, higher, oldest, staleMetric), now).manifest;
  assert.deepEqual(ranked(onlyInstagram.posts), ["instagram:UNKNOWN", "instagram:HIGHER", "instagram:NEWER"]);

  const oldThreads = { ...threads, review: { ...review, publishedAt: "2025-10-02T00:00:00Z", publicLikes: observation(10_000) } };
  const samePlace = compileReviewedPublicBatch(batch(noMetric, newer, higher, oldest, staleMetric, oldThreads), now).manifest;
  assert.equal(samePlace.posts.length, 6);
  assert.deepEqual(ranked(samePlace.posts), ["instagram:UNKNOWN", "instagram:HIGHER", "threads:TER_1"]);
  assert.equal(samePlace.posts.find(row => row.id === "threads:TER_1")?.publishedAt, "2025-10-02T00:00:00.000Z");
  assert.ok(samePlace.posts.every(row => !Object.hasOwn(row, "publicLikes")));
  assert.deepEqual(ranked(compileReviewedPublicBatch(batch(threads), now).manifest.posts), ["threads:TER_1"]);
});

test("publication time and likes observations must be independently valid", async () => {
  for (const invalid of [
    { publishedAt: "2026-11-18T10:00:01Z" },
    { publishedAt: "2026-02-30T00:00:00Z" },
    { publicLikes: { count: 1, observedAt: "2026-11-18T00:00:00Z" } },
    { publishedAt: "2026-11-01T00:00:00Z", publicLikes: { count: -1, observedAt: "2026-11-02T00:00:00Z" } },
    { publishedAt: "2026-11-01T00:00:00Z", publicLikes: { count: 1, observedAt: "2026-11-19T00:00:00Z" } },
    { publishedAt: "2026-11-01T00:00:00Z", publicLikes: { count: 1, observedAt: "2026-10-01T00:00:00Z" } },
  ]) {
    const input = batch({ ...threads, review: { ...review, ...invalid } });
    assert.throws(() => compileReviewedPublicBatch(input, now));
    await assert.rejects(recheckReviewedPublicBatch(input, { now, fetchEmbed: async () => assert.fail("invalid review must not fetch") }));
  }
});

test("conflicting observations for the same original are rejected regardless of venue order", () => {
  const candidate = (count: number, observedAt: string) => ({
    ...instagram, review: {
      ...review, multiVenue: true, publishedAt: "2026-11-17T00:00:00Z", publicLikes: { count, observedAt },
    },
  });
  const past = "2026-11-18T07:00:00Z";
  const recent = "2026-11-18T08:00:00Z";
  const first = { place, candidates: [candidate(3, past)] };
  const conflicting = { place: other, candidates: [candidate(5, "2026-11-18T07:00:00.000Z")] };
  const latest = { place: { ...place, providerPlaceID: "BranchC" }, candidates: [candidate(1, recent)] };
  for (const venues of [[first, conflicting, latest], [latest, first, conflicting]]) {
    assert.throws(() => compileReviewedPublicBatch({ venues }, now), /Conflicting public likes observations/);
  }
  const agreeing = { ...conflicting, candidates: [candidate(3, past)] };
  assert.equal(compileReviewedPublicBatch({ venues: [latest, first, agreeing] }, now).manifest.posts.length, 3);
});

test("publication days stay calendar-only and inform highlights", () => {
  const older = { ...instagram, review: { ...review, publishedAt: "2026-11-12T23:59:59Z" } };
  const calendarOnly = { ...threads, review: { ...review, publishedOn: "2026-11-13",
    publicLikes: { count: 12, observedAt: "2026-11-17T00:00:00Z" } } };
  const { manifest } = compileReviewedPublicBatch(batch(older, calendarOnly), now);
  const source = manifest.posts.find(row => row.id === "threads:TER_1");
  assert.equal(source?.publishedAt, null);
  assert.equal(source?.publishedOn, "2026-11-13");
  assert.equal(source?.highlightRank, 1);
  assert.equal(Object.hasOwn(source!, "publicLikes"), false);
});

test("rejects invalid or conflicting calendar publication days before fetching originals", async () => {
  for (const invalid of [
    { publishedOn: "2026-02-30" },
    { publishedOn: "2026-11-19" },
    { publishedOn: "2026-11-19", checkedAt: "2026-11-19T02:00:00Z" },
    { publishedOn: "2026-11-13T00:00:00Z" },
    { publishedOn: "2026-11-13", publishedAt: "2026-11-13T10:00:00Z" },
    { publishedOn: "2026-11-13", publicLikes: { count: 1, observedAt: "2026-11-12T23:59:59Z" } },
  ]) {
    const ready = { ...instagram, review: { ...review, contentFingerprint: "a".repeat(64) } };
    const input = batch(ready, { ...threads, review: { ...review, ...invalid } });
    assert.throws(() => compileReviewedPublicBatch(input, now));
    await assert.rejects(recheckReviewedPublicBatch(input, { now, fetchEmbed: async () => assert.fail("invalid review must not fetch") }));
  }
});

test("offline preview keeps the manifest deadline and preserves individual review timestamps", () => {
  const alias = { googlePlaceID: "ChIJ_venue", provider: place.provider, providerPlaceID: place.providerPlaceID,
    branchEvidence: "Named storefront and exact address independently agree." };
  const { manifest, withheld } = compileReviewedPublicBatch({
    ...batch(threads, { ...instagram, review: null }), googlePlaceAliases: [alias],
  }, now);
  const preview = makeReviewedPublicPreview(manifest, now);
  assert.equal(withheld, 1);
  assert.deepEqual(preview.snapshot.posts.map(row => row.id), ["threads:TER_1"]);
  assert.equal(preview.snapshot.expiresAt, "2026-11-19T12:00:00.000Z");
  assert.equal(preview.snapshot.posts[0]?.verifiedAt, "2026-11-18T10:00:00.000Z");
  assert.equal(preview.snapshot.nextCursor, null);
  assert.match(preview.snapshot.indexRevision, /^[0-9a-f]{64}$/);
  assert.equal(preview.snapshot.coverage.find(row => row.platform === "threads")?.indexedPostCount, 1);
  assert.deepEqual(preview.googlePlaceAliases, [{
    googlePlaceID: alias.googlePlaceID, provider: alias.provider, providerPlaceID: alias.providerPlaceID,
  }]);
  assert.throws(() => makeReviewedPublicPreview(manifest, new Date(preview.snapshot.expiresAt)));
});

test("offline preview includes associations beyond the API's first page", () => {
  const venues = Array.from({ length: 51 }, (_, i) => ({
    place: { ...place, providerPlaceID: `Branch${i}` },
    candidates: [{ ...threads, sourceURL: `https://threads.net/@example/post/Post${i}` }],
  }));
  const { manifest } = compileReviewedPublicBatch({ venues }, now);
  const preview = makeReviewedPublicPreview(manifest, now);
  assert.equal(preview.snapshot.posts.length, 51);
  assert.equal(preview.snapshot.nextCursor, null);
  assert.deepEqual(preview.snapshot.posts, manifest.posts);
});

test("venue coverage joins exact saved IDs, counts both platforms, and batches uncovered places", () => {
  const legacy = { ...place, provider: "google_places", providerPlaceID: "ChIJ_venue" };
  const alias = { googlePlaceID: legacy.providerPlaceID, provider: place.provider, providerPlaceID: place.providerPlaceID,
    branchEvidence: "The address and storefront agree." };
  const directGoogle = { ...legacy, providerPlaceID: "ChIJ_independent", name: "Store C" };
  const { manifest } = compileReviewedPublicBatch({
    venues: [
      { place, candidates: [threads, instagram] },
      { place: directGoogle, candidates: [{ ...instagram, sourceURL: "https://instagram.com/p/IG_2" }] },
      { place: other, candidates: [{ ...instagram, review: null }] },
    ],
    googlePlaceAliases: [alias],
  }, now);
  const unnamedBranches = Array.from({ length: 20 }, (_, index) => ({
    ...place, providerPlaceID: `DifferentBranch${index}`,
  }));
  const inventory = { publicVenues: [legacy, directGoogle, other, ...unnamedBranches] };
  const report = publicVenueSourceCoverage(inventory, manifest, now);
  assert.deepEqual(report.venues.slice(0, 3), [
    { key: "google_places:ChIJ_venue", canonicalKey: "apple_maps:BranchA", posts: { instagram: 1, threads: 1 } },
    { key: "google_places:ChIJ_independent", canonicalKey: "google_places:ChIJ_independent", posts: { instagram: 1, threads: 0 } },
    { key: "apple_maps:Branch+B", canonicalKey: "apple_maps:Branch+B", posts: { instagram: 0, threads: 0 } },
  ]);
  assert.equal(report.requestedPlaces, 23);
  assert.equal(report.withSources, 2);
  assert.equal(report.withBothPlatforms, 1);
  assert.equal(report.withoutSources, 21);
  assert.deepEqual(report.nextDrafts.map(row => row.publicVenues.length), [20, 1]);
  assert.deepEqual(report.nextDrafts.flatMap(row => row.publicVenues), [other, ...unnamedBranches]);
  assert.deepEqual(report.nextPlatformDrafts, [{ platforms: ["threads"], publicVenues: [directGoogle] }]);
  assert.throws(() => publicVenueSourceCoverage({ ...inventory, ownerID: "private" }, manifest, now));
  assert.throws(() => publicVenueSourceCoverage({ publicVenues: [{ ...place, note: "private" }] }, manifest, now));
  assert.throws(() => publicVenueSourceCoverage({ publicVenues: [place, place] }, manifest, now));
  assert.throws(() => publicVenueSourceCoverage({ publicVenues: [{ ...place, providerPlaceID: " BranchA " }] }, manifest, now));
  assert.throws(() => publicVenueSourceCoverage(inventory, manifest, new Date(manifest.expiresAt)));
});

test("venue coverage drops expired posts without losing a still-current snapshot", () => {
  const input = batch(
    { ...threads, review: { ...review, checkedAt: "2026-11-18T09:00:00Z" } },
    instagram,
  );
  const legacy = { ...place, provider: "google_places", providerPlaceID: "ChIJ_venue" };
  const { manifest } = compileReviewedPublicBatch({ ...input, googlePlaceAliases: [
    { googlePlaceID: legacy.providerPlaceID, provider: place.provider, providerPlaceID: place.providerPlaceID,
      branchEvidence: "The address and storefront agree." },
  ] }, now);
  const later = new Date("2026-11-19T09:01:00Z");
  const report = publicVenueSourceCoverage({ publicVenues: [place, other] }, manifest, later);
  assert.deepEqual(report.venues[0]?.posts, { instagram: 1, threads: 0 });
  assert.equal(report.withSources, 1);
  assert.equal(report.withBothPlatforms, 0);
  assert.deepEqual(report.nextDrafts, [{ publicVenues: [other] }]);
  assert.deepEqual(publicVenueSourceCoverage({ publicVenues: [legacy, place] }, manifest, later).nextPlatformDrafts,
    [{ platforms: ["threads"], publicVenues: [place] }]);
  const nextHour = new Date("2026-11-19T10:01:00Z");
  const expired = publicVenueSourceCoverage({ publicVenues: [legacy, place, other] }, manifest, nextHour);
  assert.equal(expired.withoutSources, 3);
  assert.deepEqual(expired.nextDrafts, [{ publicVenues: [place, other] }]);
  assert.deepEqual(expired.nextPlatformDrafts, []);

  const unchecked = { ...manifest, posts: manifest.posts.map(post => ({ ...post, locationEvidence: "explicit_geotag" })) };
  assert.equal(publicVenueSourceCoverage({ publicVenues: [place] }, unchecked, later).withoutSources, 1);
});

test("review batch emits canonical attributed public metadata and withholds uncertain candidates", () => {
  const { manifest, withheld } = compileReviewedPublicBatch(batch(instagram, threads,
    { ...threads, sourceURL: "https://www.threads.com/@example/post/UNCERTAIN", review: null }), now);
  assert.equal(withheld, 1);
  assert.deepEqual(manifest.posts.map(({ id, sourceURL, authorHandle }) => [id, sourceURL, authorHandle]), [
    ["instagram:IG_1", "https://www.instagram.com/p/IG_1/", "example"],
    ["threads:TER_1", "https://www.threads.com/@example/post/TER_1", "example"],
  ]);
  assert.equal(manifest.expiresAt, "2026-11-19T12:00:00.000Z");
  assert.ok(manifest.posts.every(post => !Object.hasOwn(post, "review") && post.cover === null));
  assert.equal(manifest.coverage.find(row => row.platform === "xiaohongshu")?.status, "not_connected");
});

test("review files combine venue coverage and reject conflicting or unreadable inputs", async t => {
  const dir = await mkdtemp(join(tmpdir(), "savvy-review-files-"));
  t.after(() => rm(dir, { recursive: true }));
  const first = join(dir, "first.json"), second = join(dir, "second.json");
  await writeFile(first, JSON.stringify(batch(threads)));
  await writeFile(second, JSON.stringify({ venues: [{ place: other, candidates: [instagram] }] }));
  const { manifest } = await compileReviewedPublicFiles([first, second], now);
  assert.deepEqual(manifest.posts.map(post => post.place.providerPlaceID), [other.providerPlaceID, place.providerPlaceID]);
  await assert.rejects(compileReviewedPublicFiles([first, first], now));
  await assert.rejects(compileReviewedPublicFiles([first, join(dir, "missing.json")], now));
});

test("recheck renews only unchanged public originals with existing branch fingerprints", async () => {
  const igHTML = `
    <div class="Embed">
    <a class="EmbeddedMedia" href="https://www.instagram.com/p/IG_1/?utm_source=embed">post</a>
    <div><a class="Location" href="/explore/locations/1/?ig_rid=old">Store A</a></div>
    <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>
      Store A at 10 Example Rd, ground floor <span>this weekend</span>
      <div class="CaptionComments"><a href="#">View all comments</a></div>
    </div></div>`;
  const threadsHTML = `
    <div class="Embed"><div class="LinkContainer"><a href="https://www.threads.com/@example/post/TER_1">post</a></div>
      <div class="AuthorIdentity"><a class="HeaderLink" href="https://www.threads.com/@example">example</a></div>
      <a class="Location" href="/locations/1">Store A</a>
      <span class="BodyTextContainer"><span>Store A</span> at 10 Example Rd, ground floor</span></div>`;
  const venue = place as PublicDiscoveryPlace;
  const igHash = publicPostEvidenceFingerprint(igHTML, "instagram", instagram.sourceURL, "example", venue);
  const threadsHash = publicPostEvidenceFingerprint(threadsHTML, "threads", threads.sourceURL, "example", venue);
  assert.ok(igHash && threadsHash);
  const input = batch(
    { ...instagram, review: { ...review, contentFingerprint: igHash, publishedAt: "2026-11-15T00:00:00Z",
      publicLikes: { count: 4, observedAt: "2026-11-16T06:00:00Z" } } },
    { ...threads, authorHandle: "example", review: { ...review, contentFingerprint: threadsHash } },
    { ...instagram, sourceURL: "https://www.instagram.com/p/MANUAL", review },
    { ...instagram, sourceURL: "https://www.instagram.com/p/WAITING", review: null },
  );
  const requests: string[] = [];
  const updated = await recheckReviewedPublicBatch(input, {
    now, fetchEmbed: async url => {
      requests.push(url);
      return url.includes("instagram")
        ? igHTML.replace("View all comments", "View all 60 comments").replace("ig_rid=old", "ig_rid=new")
        : threadsHTML.replace("ground floor", "basement");
    },
  });
  assert.deepEqual(requests, ["https://www.instagram.com/p/IG_1/embed/captioned/", "https://www.threads.com/@example/post/TER_1/embed"]);
  assert.deepEqual(updated.summary, { refreshed: 1, unconfirmed: 1, unconfigured: 1, pending: 1 });
  const reviewed = compileReviewedPublicBatch(updated.batch, now);
  assert.equal(reviewed.manifest.posts.find(post => post.id === "instagram:IG_1")?.verifiedAt, now.toISOString());
  assert.equal(reviewed.manifest.posts.find(post => post.id === "instagram:IG_1")?.publishedAt, "2026-11-15T00:00:00.000Z");
  assert.ok(JSON.stringify(updated.batch).includes("2026-11-16T06:00:00Z"));
  assert.equal(reviewed.manifest.posts.find(post => post.id === "threads:TER_1")?.verifiedAt, "2026-11-18T10:00:00.000Z");
  assert.ok(!JSON.stringify(reviewed).includes(igHash));
  assert.ok(!JSON.stringify(updated).includes("this weekend"));
  for (const malformed of [
    igHTML.replace("/p/IG_1/", "/p/OTHER/"), igHTML.replace("/example/", "/different/"),
    `<!--${igHTML}-->`, `<script>${igHTML}</script>`, `<template>${igHTML}</template>`,
    `<div hidden>${igHTML}</div>`, `<div style="DISPLAY: none !important">${igHTML}</div>`, `<textarea>${igHTML}</textarea>`,
    `<template><template></template>${igHTML}</template>`,
    `<div style="opacity:0">${igHTML}</div>`, `<details><summary>Details</summary>${igHTML}</details>`,
  ]) assert.equal(publicPostEvidenceFingerprint(malformed, "instagram", instagram.sourceURL, "example", venue), undefined);
  assert.notEqual(publicPostEvidenceFingerprint(igHTML.replace("/locations/1/", "/locations/2/"),
    "instagram", instagram.sourceURL, "example", venue), igHash);
  assert.notEqual(publicPostEvidenceFingerprint(igHTML, "instagram", instagram.sourceURL, "example", other as PublicDiscoveryPlace), igHash);
  assert.notEqual(publicPostEvidenceFingerprint(igHTML, "instagram", instagram.sourceURL, "example",
    { ...venue, latitude: venue.latitude + 0.001 }), igHash);
  assert.notEqual(publicPostEvidenceFingerprint(threadsHTML.replace("/locations/1", "/locations/2"),
    "threads", threads.sourceURL, "example", venue), threadsHash);
  const wrongThread = threadsHTML.replace("/post/TER_1", "/post/OTHER")
    .replace('<div class="AuthorIdentity">', '<a href="https://www.threads.com/@example/post/TER_1">secondary</a><div class="AuthorIdentity">');
  assert.equal(publicPostEvidenceFingerprint(wrongThread, "threads", threads.sourceURL, "example", venue), undefined);
  const linked = igHTML.replace("<span>this weekend</span>", '<a href="reviews">this weekend</a>');
  assert.notEqual(publicPostEvidenceFingerprint(linked, "instagram", instagram.sourceURL, "example", venue),
    publicPostEvidenceFingerprint(linked.replace('"reviews"', '"/reviews"'), "instagram", instagram.sourceURL, "example", venue));
  assert.equal(publicPostEvidenceFingerprint('<base href="https://example.com/">' + igHTML,
    "instagram", instagram.sourceURL, "example", venue), undefined);
  assert.equal(publicPostEvidenceFingerprint('<head hidden><base hidden href="https://example.com/"></head>' + igHTML,
    "instagram", instagram.sourceURL, "example", venue), undefined);
});

test("recheck reads a shared original once without sharing a venue verification", async () => {
  const html = `
    <div class="Embed">
      <div class="LinkContainer"><a href="https://www.threads.com/@example/post/TER_1">Original</a></div>
      <div class="AuthorIdentity"><a class="HeaderLink" href="/@example">example</a></div>
      <span class="BodyTextContainer">Both branches reviewed.</span>
    </div>`;
  const source = { ...threads, authorHandle: "example" };
  const fingerprint = publicPostEvidenceFingerprint(html, "threads", source.sourceURL, "example", place as PublicDiscoveryPlace);
  assert.ok(fingerprint);
  const written = { ...review, multiVenue: true, contentFingerprint: fingerprint };
  const requests: string[] = [];
  const result = await recheckReviewedPublicBatch({ venues: [
    { place, candidates: [{ ...source, review: written }] },
    { place: other, candidates: [{ ...source, review: written }] },
  ] }, { now, fetchEmbed: async url => { requests.push(url); return html; } });
  assert.deepEqual(requests, ["https://www.threads.com/@example/post/TER_1/embed"]);
  assert.deepEqual(result.summary, { refreshed: 1, unconfirmed: 1, unconfigured: 0, pending: 0 });
  assert.equal(compileReviewedPublicBatch(result.batch, now).manifest.posts.find(post =>
    post.place.providerPlaceID === other.providerPlaceID)?.verifiedAt, new Date(review.checkedAt).toISOString());
});

test("refresh validates every file then recovers only reproven expired review rows", async t => {
  const dir = await mkdtemp(join(tmpdir(), "savvy-refresh-reviewed-"));
  t.after(() => rm(dir, { recursive: true }));
  const first = join(dir, "first.json"), second = join(dir, "second.json");
  const html = `
    <div class="Embed">
      <div class="LinkContainer"><a href="https://www.threads.com/@example/post/TER_1">Original</a></div>
      <div class="AuthorIdentity"><a class="HeaderLink" href="/@example">example</a></div>
      <span class="BodyTextContainer">Published list of both venues.</span>
    </div>`;
  const source = { ...threads, authorHandle: "example" };
  const fingerprint = publicPostEvidenceFingerprint(html, "threads", source.sourceURL, "example", place as PublicDiscoveryPlace);
  assert.ok(fingerprint);
  const written = { ...review, checkedAt: "2026-11-12T10:00:00Z", multiVenue: true, contentFingerprint: fingerprint };
  await writeFile(first, JSON.stringify(batch({ ...source, review: written })));
  await writeFile(second, JSON.stringify({ venues: [{ place: other, candidates: [
    { ...source, review: written },
    { ...instagram, review: null },
  ] }], googlePlaceAliases: [{ googlePlaceID: "ChIJ_stale_branch", provider: other.provider,
    providerPlaceID: other.providerPlaceID, branchEvidence: "Exact branch independently reviewed." }] }));
  await assert.rejects(compileReviewedPublicFiles([first, second], now), /No current reviewed posts/);
  const requests: string[] = [];
  const read = async (url: string) => { requests.push(url); return html; };
  await assert.rejects(refreshReviewedPublicFiles([first, first], { now, fetchEmbed: read }));
  const pending = join(dir, "pending.json");
  for (const malformed of [
    { authorHandle: [] }, { title: { text: "untrusted" } }, { title: "x".repeat(161) }, { title: "control\x07" },
  ]) {
    await writeFile(pending, JSON.stringify({ venues: [{ place: other, candidates: [
      { ...instagram, ...malformed, review: null },
    ] }] }));
    await assert.rejects(refreshReviewedPublicFiles([first, pending], { now, fetchEmbed: read }), /Invalid attribution/);
  }
  await writeFile(pending, JSON.stringify({ venues: [{ place: other, candidates: [{ ...instagram, review: null }] }] }));
  await assert.rejects(refreshReviewedPublicFiles([first, pending, pending], { now, fetchEmbed: read }),
    /Duplicate reviewed association/);
  await writeFile(pending, JSON.stringify({ venues: [{ place: { ...place, address: "Conflicting door number" },
    candidates: [{ ...instagram, review: null }] }] }));
  await assert.rejects(refreshReviewedPublicFiles([first, pending], { now, fetchEmbed: read }), /Conflicting reviewed venue/);
  assert.deepEqual(requests, []);
  const result = await refreshReviewedPublicFiles([first, second], { now, fetchEmbed: read });
  assert.deepEqual(requests, ["https://www.threads.com/@example/post/TER_1/embed"]);
  assert.deepEqual(result.summary, { refreshed: 1, unconfirmed: 1, unconfigured: 0, pending: 1 });
  assert.equal(result.expired, 1);
  assert.equal(result.withheld, 1);
  const preview = makeReviewedPublicPreview(result.manifest, now);
  assert.deepEqual(preview.snapshot.posts.map(row => [row.place.providerPlaceID, row.verifiedAt]),
    [[place.providerPlaceID, now.toISOString()]]);
  assert.deepEqual(preview.googlePlaceAliases, []);
  await assert.rejects(refreshReviewedPublicFiles([first, second], { now,
    fetchEmbed: async () => { throw new Error("Unavailable original"); } }), /No current reviewed posts/);
  await assert.rejects(compileReviewedPublicFiles([first, second], now), /No current reviewed posts/);
});

test("refresh budgets count unique originals and support larger explicitly bounded archives", async t => {
  const storage = await mkdtemp(join(tmpdir(), "savvy-recheck-budget-"));
  t.after(() => rm(storage, { recursive: true }));
  const path = join(storage, "review.json");
  const places = [place, other, { ...place, providerPlaceID: "BranchC", name: "Store C" }] as PublicDiscoveryPlace[];
  const markup = new Map<string, string>();
  function reviewed(post: number, venue: PublicDiscoveryPlace) {
    const sourceURL = `https://www.threads.com/@example/post/Budget_${post}`;
    const html = `
      <div class="Embed">
        <div class="LinkContainer"><a href="${sourceURL}">Original</a></div>
        <div class="AuthorIdentity"><a class="HeaderLink" href="/@example">example</a></div>
        <span class="BodyTextContainer">Public recommendations cover the reviewed venues.</span>
      </div>`;
    markup.set(sourceURL + "/embed", html);
    return { ...threads, sourceURL, authorHandle: "example", review: { ...review, multiVenue: true,
      contentFingerprint: publicPostEvidenceFingerprint(html, "threads", sourceURL, "example", venue) } };
  }
  const rows = [
    { place: places[0]!, candidates: Array.from({ length: 50 }, (_, i) => reviewed(i, places[0]!)) },
    { place: places[1]!, candidates: Array.from({ length: 50 }, (_, i) => reviewed(i + 50, places[1]!)) },
    { place: places[2]!, candidates: [reviewed(0, places[2]!)] },
  ];
  const requests: string[] = [];
  let running = 0;
  let peak = 0;
  const fetchEmbed = async (url: string) => {
    requests.push(url);
    peak = Math.max(peak, ++running);
    await Promise.resolve();
    running--;
    return markup.get(url)!;
  };
  await writeFile(path, JSON.stringify({ venues: rows }));
  const shared = await refreshReviewedPublicFiles([path], { now, fetchEmbed });
  assert.equal(requests.length, 100);
  assert.equal(new Set(requests).size, requests.length);
  assert.equal(shared.summary.refreshed, 101);
  assert.equal(shared.manifest.posts.length, 101);
  assert.equal(peak, 3);

  rows[2]!.candidates.push(reviewed(100, places[2]!));
  await writeFile(path, JSON.stringify({ venues: rows }));
  requests.length = 0;
  await assert.rejects(refreshReviewedPublicFiles([path], { now, fetchEmbed }), /100.*originals/i);
  await assert.rejects(refreshReviewedPublicFiles([path], { now, fetchEmbed, maxOriginals: 5001 }), /Invalid.*budget/i);
  await assert.rejects(refreshReviewedPublicFiles([path], { now, fetchEmbed, maxOriginals: null as unknown as number }), /Invalid.*budget/i);
  assert.equal(requests.length, 0);
  const expanded = await refreshReviewedPublicFiles([path], { now, fetchEmbed, maxOriginals: 101 });
  assert.equal(requests.length, 101);
  assert.equal(expanded.summary.refreshed, 102);
  assert.equal(expanded.manifest.posts.length, 102);
  assert.equal(peak, 3);
});

test("review batch rejects conflicts, unsigned matches, bad attribution and stale or malformed dates", () => {
  assert.throws(() => compileReviewedPublicBatch({ venues: [
    { place, candidates: [threads] }, { place: other, candidates: [threads] },
  ] }, now));
  for (const providerPlaceID of ["咖", "Café", "Cafe\u0301", "x".repeat(201)]) {
    assert.throws(() => compileReviewedPublicBatch({ venues: [
      { place: { ...place, providerPlaceID }, candidates: [threads] },
    ] }, now));
  }
  for (const candidate of [
    { ...threads, sourceURL: "https://www.threads.com/@example/post/TER_1?access_token=bad" },
    { ...threads, authorHandle: "different" },
    { ...threads, review: { ...review, branchEvidence: " " } },
    { ...threads, review: { ...review, checkedAt: "2026-11-17T11:59:59Z" } },
    { ...threads, review: { ...review, checkedAt: "bad" } },
    { ...threads, review: { ...review, checkedAt: "2026-11-18T12:00:01Z" } },
    { ...threads, review: { ...review, loggedInCookie: "private" } },
  ]) assert.throws(() => compileReviewedPublicBatch(batch(candidate), now));
});

test("compiling a mixed-age review archive preserves fresh sources and drops stale-only aliases", () => {
  const staleThread = { ...threads, review: { ...review, checkedAt: "2026-11-17T12:00:00Z" } };
  const staleElsewhere = { ...threads, sourceURL: "https://www.threads.com/@example/post/Lapsed",
    review: { ...review, checkedAt: "2026-10-01T10:00:00Z" } };
  const archive = {
    venues: [{ place, candidates: [staleThread, instagram] }, { place: other, candidates: [staleElsewhere] }],
    googlePlaceAliases: [
      { googlePlaceID: "ChIJBranch_A", provider: "apple_maps", providerPlaceID: "BranchA", branchEvidence: "Exact storefront" },
      { googlePlaceID: "ChIJBranch_B", provider: "apple_maps", providerPlaceID: "Branch+B", branchEvidence: "Exact storefront" },
    ],
  };
  const { manifest, expired, withheld } = compileReviewedPublicBatch(archive, now);
  assert.equal(withheld, 0);
  assert.equal(expired, 2);
  assert.deepEqual(manifest.posts.map(row => [row.id, row.verifiedAt]), [["instagram:IG_1", "2026-11-18T10:00:00.000Z"]]);
  assert.deepEqual(manifest.googlePlaceAliases?.map(alias => alias.googlePlaceID), ["ChIJBranch_A"]);
  assert.equal(manifest.coverage.find(row => row.platform === "threads")?.status, "not_connected");
  assert.equal(makeReviewedPublicPreview(manifest, now).snapshot.posts.length, 1);
  assert.throws(() => compileReviewedPublicBatch(batch(staleThread), now), /No current reviewed posts/);

  for (const malformed of [
    { ...staleThread, review: { ...staleThread.review, checkedAt: "2025-02-31T12:00:00Z" } },
    { ...staleThread, title: "a".repeat(161) },
    { ...staleThread, review: { ...staleThread.review, branchEvidence: "" } },
  ]) assert.throws(() => compileReviewedPublicBatch(batch(instagram, malformed), now));
  assert.throws(() => compileReviewedPublicBatch({ ...archive,
    venues: [{ place, candidates: [staleThread, instagram] }, { place: other, candidates: [staleThread] }],
  }, now));
  assert.throws(() => compileReviewedPublicBatch({ ...archive,
    googlePlaceAliases: [archive.googlePlaceAliases[0], { ...archive.googlePlaceAliases[1], googlePlaceID: "ChIJBranch_A" }],
  }, now));
});

test("Map and Saved receive the same indexed posts and a cursor stays tied to the venue", async t => {
  const dir = await mkdtemp(join(tmpdir(), "savvy-batch-test-"));
  t.after(() => rm(dir, { recursive: true }));
  const filePath = join(dir, "index.json");
  const { manifest } = compileReviewedPublicBatch({ googlePlaceAliases: [
    { googlePlaceID: "ChIJBranch_A", provider: "apple_maps", providerPlaceID: "BranchA",
      branchEvidence: "Google and Apple public store listings show the same floor and shop." },
    { googlePlaceID: "ChIJBranch_B", provider: "apple_maps", providerPlaceID: "Branch+B",
      branchEvidence: "The other shop is the basement tenant." },
  ], venues: [
    { place, candidates: [instagram, threads] },
    { place: other, candidates: [
      { ...threads, sourceURL: "https://www.threads.com/@example/post/OTHER" },
      { ...instagram, sourceURL: "https://www.instagram.com/p/OTHER" },
    ] },
  ] }, now);
  await writeFile(filePath, JSON.stringify(manifest));
  const read = (query: string, authenticated = true) => evaluatePublicDiscoveryRequest({
    method: "GET", url: new URL("https://savvy.example/v0/discovery/posts?bbox=121.5,25,121.6,25.1" + query),
    authorization: authenticated ? "Bearer fixture" : undefined, verifySubject: async () => "fixture",
    readPosts: url => listPublicDiscoveryPosts(url, { filePath, now }),
  });
  const map = await read("");
  const saved = await read("&provider=apple_maps&placeID=BranchA");
  assert.equal(map.statusCode, 200);
  assert.equal(saved.statusCode, 200);
  const posts = (body: unknown) => (body as { posts: typeof manifest.posts }).posts;
  assert.deepEqual(posts(saved.body), posts(map.body).filter(post => post.place.providerPlaceID === "BranchA"));
  assert.equal(posts(map.body).length, 4);
  assert.equal(posts(saved.body).length, 2);
  const google = await read("&provider=google_places&placeID=ChIJBranch_A");
  assert.deepEqual(posts(google.body), posts(saved.body));
  assert.deepEqual((google.body as { googlePlaceMatch: unknown }).googlePlaceMatch,
    { googlePlaceID: "ChIJBranch_A", provider: "apple_maps", providerPlaceID: "BranchA" });
  assert.equal(Object.hasOwn(map.body as object, "googlePlaceMatch"), false);
  assert.equal(Object.hasOwn(map.body as object, "googlePlaceAliases"), false);
  assert.deepEqual(posts((await read("&provider=google_places&placeID=Unknown")).body), []);
  assert.deepEqual(posts((await read("&provider=amap&placeID=BranchA")).body), []);
  assert.deepEqual(posts((await read("&provider=apple_maps&placeID=brancha")).body), []);
  assert.equal(posts((await read("&provider=apple_maps&placeID=Branch%2BB")).body).length, 2);
  assert.equal((await read("&provider=apple_maps&placeID=Branch+B")).statusCode, 400);
  assert.equal((await read("&provider=apple_maps&placeID=Caf%C3%A9")).statusCode, 400);
  assert.equal((await read("&placeID=BranchA")).statusCode, 400);
  assert.equal((await read("&provider=apple_maps&placeID=BranchA", false)).statusCode, 401);
  const first = await read("&provider=apple_maps&placeID=BranchA&limit=1");
  const { nextCursor } = first.body as { nextCursor: string };
  assert.ok(nextCursor);
  assert.equal((await read("&provider=apple_maps&placeID=BranchA&limit=1&cursor=" + nextCursor)).statusCode, 200);
  assert.equal((await read("&provider=apple_maps&placeID=Branch%2BB&limit=1&cursor=" + nextCursor)).statusCode, 400);
  assert.equal((await read("&limit=1&cursor=" + nextCursor)).statusCode, 400);
  const googleFirst = await read("&provider=google_places&placeID=ChIJBranch_A&limit=1");
  const googleCursor = (googleFirst.body as { nextCursor: string }).nextCursor;
  assert.ok(googleCursor);
  assert.equal((await read("&provider=google_places&placeID=ChIJBranch_A&limit=1&cursor=" + googleCursor)).statusCode, 200);
  assert.equal((await read("&provider=google_places&placeID=ChIJBranch_B&limit=1&cursor=" + googleCursor)).statusCode, 400);
  assert.equal((await read("&provider=apple_maps&placeID=BranchA&limit=1&cursor=" + googleCursor)).statusCode, 400);
});

test("reviewed Google aliases reject duplicate, orphaned and unsupported crosswalks", () => {
  const alias = { googlePlaceID: "ChIJBranch_A", provider: "apple_maps", providerPlaceID: "BranchA",
    branchEvidence: "The same floor and venue in Google and Apple listings." };
  for (const aliases of [
    [alias, { ...alias, providerPlaceID: "Branch+B" }],
    [{ ...alias, providerPlaceID: "Unindexed" }],
    [{ ...alias, googlePlaceID: "private_url?subject=person" }],
    [{ ...alias, branchEvidence: "" }],
    [{ ...alias, provider: "google_places" }],
  ]) assert.throws(() => compileReviewedPublicBatch({ ...batch(instagram, threads), googlePlaceAliases: aliases }, now));
});
