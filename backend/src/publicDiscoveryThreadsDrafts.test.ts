import assert from "node:assert/strict";
import test from "node:test";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";
import { collectThreadsDiscoveryDrafts } from "./publicDiscoveryThreadsDrafts.js";

const now = new Date("2026-11-20T02:00:00Z");
const place = {
  provider: "apple_maps", providerPlaceID: "ExactBranch", name: "Sample cafe",
  address: "10 Example Road, 2F", latitude: 25.03, longitude: 121.56, coordinateSystem: "WGS84", category: "cafe",
};
const second = { ...place, providerPlaceID: "SecondBranch", name: "Second sample", address: "10 Example Road, 3F" };
const alias = { ...place, provider: "google_places", providerPlaceID: "ChIJ_exact_branch" };
const review = { checkedAt: "2026-11-20T01:00:00Z", origin: "public_web_index", branchEvidence: "Sample branch verified." };
const instagram = { platform: "instagram", authorHandle: "sample", title: "Sample",
  sourceURL: "https://www.instagram.com/p/OldPhoto/", review };
const { manifest } = compileReviewedPublicBatch({
  venues: [{ place, candidates: [instagram] }],
  googlePlaceAliases: [{
    googlePlaceID: alias.providerPlaceID, provider: place.provider, providerPlaceID: place.providerPlaceID,
    branchEvidence: "Identical sample branch.",
  }],
}, now);
const firstPost = { username: "sample", permalink: "https://threads.net/@sample/post/SourceOne?xmt=tracking" };
const secondPost = { username: "sample", permalink: "https://www.threads.com/@sample/post/SourceTwo" };
const modes = ["RECENT", "TOP"];

test("queries the exact missing branch via both modes and outputs only deduplicated pending originals", async () => {
  const seen: string[] = [];
  const result = await collectThreadsDiscoveryDrafts({ publicVenues: [alias, place] }, manifest, {
    now, token: "fake-private-token",
    fetchImpl: async (input, options) => {
      const url = new URL(String(input));
      assert.equal(url.origin + url.pathname, "https://graph.threads.net/v1.0/keyword_search");
      assert.equal(url.searchParams.get("q"), place.name);
      assert.equal(url.searchParams.get("limit"), "20");
      assert.equal(options?.redirect, "error");
      assert.equal(new Headers(options?.headers).get("Authorization"), "Bearer fake-private-token");
      assert.equal(url.toString().includes("fake-private-token"), false);
      const mode = url.searchParams.get("search_type")!;
      seen.push(mode);
      return Response.json({
        data: [firstPost, {
          ...firstPost, permalink: "https://www.threads.com/@sample/post/SourceOne", text: "provider raw text",
        }, { ...firstPost, permalink: firstPost.permalink + "&access_token=captured" },
        { ...firstPost, username: "different" }, { ...firstPost, permalink: "https://threads.com.example.org/@sample/post/SourceOne" },
        ...(mode === "TOP" ? [secondPost] : [])],
        paging: { next: "https://remote.example/?access_token=do-not-follow" },
      });
    },
  });
  assert.deepEqual(seen, modes);
  assert.deepEqual(result.draft.venues.map(({ place: target }) => target.providerPlaceID), [place.providerPlaceID]);
  assert.deepEqual(result.draft.venues[0]?.candidates, ["SourceOne", "SourceTwo"].map(id => ({
    platform: "threads", sourceURL: `https://www.threads.com/@sample/post/${id}`,
    authorHandle: "sample", title: "", review: null,
  })));
  const rebuilt = compileReviewedPublicBatch(result.draft, now);
  assert.equal(rebuilt.withheld, 2);
  assert.deepEqual(rebuilt.manifest.posts, []);
  assert.equal(result.coverage.publicSearchAccessVerified, false);
  assert(result.coverage.searches[0]?.modes.every(run => run.hasMoreResults));
  assert.doesNotMatch(JSON.stringify(result), /private-token|provider raw text|captured|do-not-follow/);
});

test("a missing token records each search as unconfigured and never requests data", async () => {
  const result = await collectThreadsDiscoveryDrafts({ publicVenues: [alias, second] }, manifest, {
    now, fetchImpl: async () => assert.fail("unconfigured requests must never run"),
  });
  assert.deepEqual(result.draft.venues, []);
  assert.equal(result.coverage.totalMissing, 2);
  assert.equal(result.coverage.nextOffset, null);
  assert.deepEqual(result.coverage.searches.flatMap(row => row.modes.map(run => run.status)),
    Array(4).fill("not_configured"));
});

test("public web search covers canonical missing branches and keeps search hits pending", async () => {
  const queries: string[] = [];
  const out = await collectThreadsDiscoveryDrafts({ publicVenues: [alias, place, second] }, manifest, {
    now, fetchImpl: async () => assert.fail("public web mode does not call Meta"),
    webSearch: async query => {
      queries.push(query);
      return [
        "https://threads.net/@sample/post/SourceOne/%E5%B0%8F%E5%90%83?xmt=tracking",
        "https://www.threads.com/@sample/post/SourceOne",
        "https://www.threads.com/@sample/post/SourceTwo?access_token=private",
        "https://www.threads.com.example.org/@sample/post/SourceOther/caption",
        "https://www.threads.com/@sample/post/SourceConflict/",
        "https://www.threads.com/@other/post/SourceConflict",
        "https://www.threads.com/@sample",
      ].map(url => ({ query, url, title: "unchecked search text" }));
    },
  });
  assert.deepEqual(queries, [
    "site:threads.com Second sample 10 Example Road 3F",
    "site:threads.com Sample cafe 10 Example Road 2F",
  ]);
  assert.deepEqual(out.draft.venues.map(({ place }) => place.providerPlaceID), ["SecondBranch", "ExactBranch"]);
  for (const { candidates } of out.draft.venues) {
    assert.deepEqual(candidates, [{ platform: "threads",
      sourceURL: "https://www.threads.com/@sample/post/SourceOne", authorHandle: "sample", title: "", review: null }]);
  }
  assert.equal(compileReviewedPublicBatch(out.draft, now).withheld, 2);
  assert.equal(out.coverage.publicSearchAccessVerified, false);
  assert.deepEqual(out.coverage.searches.map(x => x.modes[0]?.mode), ["PUBLIC_WEB", "PUBLIC_WEB"]);
  assert.doesNotMatch(JSON.stringify(out), /tracking|private|unchecked search text/);
});

test("a web search challenge, rate limit, or failure stops further requests and preserves pending hits", async () => {
  for (const [message, expected] of [
    ["Public search requires verification", "access_required"],
    ["HTTP 429", "rate_limited"],
    ["Provider unavailable", "unavailable"],
  ] as const) {
    let calls = 0;
    const third = { ...second, providerPlaceID: "ThirdBranch" };
    const result = await collectThreadsDiscoveryDrafts({ publicVenues: [place, second, third] }, manifest, {
      now, webSearch: async query => {
        if (++calls > 1) throw new Error(message);
        return [{ query, url: secondPost.permalink, title: "known pending result" }];
      },
    });
    assert.equal(calls, 2);
    assert.equal(result.draft.venues.length, 1);
    assert.deepEqual(result.coverage.searches.map(x => x.modes[0]?.status),
      ["searched", expected, "not_attempted"]);
    assert.equal(result.coverage.nextOffset, null);
    assert.doesNotMatch(JSON.stringify(result), /known pending result|Provider unavailable/);
  }
});

test("web drafts with conflicting authors for one shortcode are withheld across branches", async () => {
  const result = await collectThreadsDiscoveryDrafts({ publicVenues: [place, second] }, manifest, {
    now, webSearch: async query => [{
      query, title: "unchecked",
      url: `https://www.threads.com/@${query.includes(place.name) ? "alpha" : "beta"}/post/SameCode`,
    }, { query, title: "unchanged", url: secondPost.permalink }],
  });
  assert.equal(result.draft.venues.length, 2);
  assert(result.draft.venues.every(venue => venue.candidates.length === 1
    && venue.candidates[0]?.sourceURL === secondPost.permalink));
});

test("access and rate errors stop the rest of the batch while preserving earlier pending candidates", async () => {
  for (const [status, code, expected] of [
    [400, 190, "access_required"], [403, 10, "access_required"], [429, 4, "rate_limited"],
  ] as const) {
    let called = 0;
    const result = await collectThreadsDiscoveryDrafts({ publicVenues: [alias, second] }, manifest, {
      now, token: "fixture", fetchImpl: async () => ++called === 1
        ? Response.json({ data: [firstPost] })
        : Response.json({ error: { code, message: "private upstream response" } }, { status }),
    });
    assert.equal(called, 2);
    assert.equal(result.draft.venues.length, 1);
    assert.deepEqual(result.coverage.searches.flatMap(row => row.modes.map(run => run.status)),
      ["searched", expected, "not_attempted", "not_attempted"]);
    assert.equal(result.coverage.nextOffset, null);
    assert.doesNotMatch(JSON.stringify(result), /private upstream response/);
  }
});

test("invalid input or expired coverage never launches provider requests", async () => {
  const options = { now, token: "fixture", fetchImpl: async () => assert.fail("invalid inputs never request data") };
  await assert.rejects(collectThreadsDiscoveryDrafts({ publicVenues: [{ ...place, privateNote: "secret" }] }, manifest, options));
  await assert.rejects(collectThreadsDiscoveryDrafts({ publicVenues: [place] }, manifest, {
    ...options, now: new Date(manifest.expiresAt),
  }));
  await assert.rejects(collectThreadsDiscoveryDrafts({ publicVenues: [place] }, manifest, { ...options, offset: -1 }));
});

test("takes the next bounded page only after healthy provider responses", async () => {
  const inventory = { publicVenues: Array.from({ length: 21 }, (_, i) => ({
    ...second, providerPlaceID: `Nearby${i}`,
  })) };
  let count = 0;
  const options = { now, token: "fixture", fetchImpl: async () => {
    count += 1;
    return Response.json({ data: [] });
  } };
  const page = await collectThreadsDiscoveryDrafts(inventory, manifest, options);
  assert.equal(count, 40);
  assert.equal(page.coverage.totalMissing, 21);
  assert.equal(page.coverage.nextOffset, 20);
  const next = await collectThreadsDiscoveryDrafts(inventory, manifest, { ...options, offset: 20 });
  assert.equal(count, 42);
  assert.equal(next.coverage.searches[0]?.placeKey, "apple_maps:Nearby20");
  assert.equal(next.coverage.nextOffset, null);

  const unavailable = await collectThreadsDiscoveryDrafts({ publicVenues: [place] }, manifest, {
    ...options, fetchImpl: async () => new Response("x".repeat(256_001)),
  });
  assert.deepEqual(unavailable.coverage.searches[0]?.modes.map(run => run.status), ["unavailable", "unavailable"]);
});
