import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  buildRelatedSourceQueries,
  discoverRelatedPlaceSources,
  normalizeRelatedPlaceSourcesRequest,
  RelatedPlaceSourcesInputError,
  relatedPlaceSourcePackResponseBody,
  type RelatedSourcePlaceIdentity,
} from "./relatedPlaceSources.js";

const confirmedPlace: RelatedSourcePlaceIdentity = {
  id: "11111111-1111-4111-8111-111111111111",
  name: "賀鴨郎",
  address: "高雄市鼓山區美術東二路",
  latitude: 22.655,
  longitude: 120.286,
  category: "food",
  googlePlaceId: "google-place-1",
};

test("normalizes a bounded related-source request", () => {
  assert.deepEqual(normalizeRelatedPlaceSourcesRequest({
    platforms: ["Instagram", "youtube", "instagram"],
    max_results_per_platform: 4,
  }), {
    platforms: ["instagram", "youtube"],
    maxResultsPerPlatform: 4,
  });
});

test("rejects malformed and unsupported request controls", () => {
  assert.throws(
    () => normalizeRelatedPlaceSourcesRequest({ platforms: "instagram" }),
    RelatedPlaceSourcesInputError,
  );
  assert.throws(
    () => normalizeRelatedPlaceSourcesRequest({ platforms: ["facebook"] }),
    /unsupported/,
  );
  assert.throws(
    () => normalizeRelatedPlaceSourcesRequest({ aliases: ["Alice Smith"] }),
    /not accepted/,
  );
  assert.throws(
    () => normalizeRelatedPlaceSourcesRequest({ max_results_per_platform: 20 }),
    /integer from 1-5/,
  );
});

test("builds platform-bounded queries only from confirmed identity", () => {
  const queries = buildRelatedSourceQueries(
    confirmedPlace,
    "xiaohongshu",
  );

  assert.equal(queries.length, 2);
  assert.equal(
    queries[0],
    'site:xiaohongshu.com "賀鴨郎" "高雄市"',
  );
  assert.equal(
    queries[1],
    'site:xiaohongshu.com "賀鴨郎"',
  );
  assert.ok(queries.every((query) => query.length <= 240));
});

test("returns an exact branch result as candidate-only same-place evidence", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["instagram"], maxResultsPerPlatform: 5 },
    {
      now: () => new Date("2026-07-24T12:00:00.000Z"),
      search: async (query) => [{
        query,
        title: "賀鴨郎｜高雄粵菜餐廳",
        url: "https://www.instagram.com/reel/exact88/?utm_source=test",
        snippet: "高雄市鼓山區美術東二路的烤鴨與港點",
      }],
    },
  );

  assert.equal(pack.sources.length, 1);
  assert.deepEqual(pack.sources[0], {
    platform: "instagram",
    url: "https://instagram.com/reel/exact88",
    title: "賀鴨郎｜高雄粵菜餐廳",
    snippet: "高雄市鼓山區美術東二路的烤鴨與港點",
    query: 'site:instagram.com "賀鴨郎" "高雄市"',
    relation: "same_place",
    identityStatus: "candidate",
    matchConfidence: 0.86,
  });
  assert.equal(pack.coverage[0]?.status, "searched");
  assert.equal(pack.coverage[0]?.resultCount, 1);
  assert.equal(pack.receipt.privacy, "owner_private");
  assert.equal(pack.receipt.checkedAt, "2026-07-24T12:00:00.000Z");
});

test("bounds third-party titles and snippets before returning them", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["instagram"] },
    {
      search: async (query) => [{
        query,
        title: `賀鴨郎 ${"T".repeat(400)}`,
        url: "https://instagram.com/reel/bounded88",
        snippet: `高雄市 ${"S".repeat(800)}`,
      }],
    },
  );

  assert.equal(pack.sources[0]?.title.length, 200);
  assert.equal(pack.sources[0]?.snippet?.length, 500);
  assert.ok((pack.sources[0]?.query.length ?? 0) <= 240);
});

test("keeps name-only results below same-place confidence", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["youtube"] },
    {
      search: async (query) => [{
        query,
        title: "賀鴨郎用餐紀錄",
        url: "https://youtube.com/watch?v=nameonly",
        snippet: "烤鴨與港點分享",
      }],
    },
  );

  assert.equal(pack.sources[0]?.relation, "mentions_place");
  assert.equal(pack.sources[0]?.matchConfidence, 0.62);
  assert.equal(pack.sources[0]?.identityStatus, "candidate");
});

test("keeps city-only evidence below same-place confidence", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["x"] },
    {
      search: async (query) => [{
        query,
        title: "賀鴨郎 高雄市",
        url: "https://x.com/food/status/cityonly",
        snippet: "高雄美食分享",
      }],
    },
  );

  assert.equal(pack.sources[0]?.relation, "mentions_place");
  assert.equal(pack.sources[0]?.matchConfidence, 0.62);
});

test("rejects a same-name result for another branch in the same city", async () => {
  const pack = await discoverRelatedPlaceSources(
    {
      ...confirmedPlace,
      name: "Starbucks",
      address: "台北市信義區松壽路",
    },
    { platforms: ["instagram"] },
    {
      search: async (query) => [{
        query,
        title: "Starbucks 台北市中山區門市",
        url: "https://instagram.com/reel/wrongbranch",
        snippet: "台北市中山區咖啡",
      }],
    },
  );

  assert.equal(pack.sources.length, 0);
});

test("accepts a Xiaohongshu note path while rejecting its generic explore page", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["xiaohongshu"], maxResultsPerPlatform: 5 },
    {
      search: async (query) => [
        {
          query,
          title: "賀鴨郎 高雄市探店",
          url: "https://www.xiaohongshu.com/explore/687df3a1000000000d0184a4",
          snippet: "高雄市鼓山區",
        },
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://www.xiaohongshu.com/explore/",
          snippet: "高雄市鼓山區",
        },
      ],
    },
  );

  assert.equal(pack.sources.length, 1);
  assert.equal(
    pack.sources[0]?.url,
    "https://xiaohongshu.com/explore/687df3a1000000000d0184a4",
  );
});

test("rejects a same-name result that explicitly names the wrong city", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["tiktok"] },
    {
      search: async (query) => [{
        query,
        title: "賀鴨郎 台南市新店",
        url: "https://tiktok.com/@food/video/wrongcity",
        snippet: "台南市中西區",
      }],
    },
  );

  assert.equal(pack.sources.length, 0);
  assert.deepEqual(pack.receipt.missing, [
    "tiktok: no same-place public source found",
  ]);
});

test("rejects generic and host-mismatched results, excludes the seed, and dedupes tracking URLs", async () => {
  const place = {
    ...confirmedPlace,
    sourceUrl: "https://instagram.com/reel/seed?igsh=original",
  };
  const pack = await discoverRelatedPlaceSources(
    place,
    { platforms: ["instagram"], maxResultsPerPlatform: 5 },
    {
      search: async (query) => [
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://instagram.com/reel/seed?igsh=duplicate",
          snippet: "高雄市鼓山區",
        },
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://instagram.com/explore/",
          snippet: "高雄市鼓山區",
        },
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://example.com/not-instagram",
          snippet: "高雄市鼓山區",
        },
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://www.instagram.com/reel/good/?utm_source=one",
          snippet: "高雄市鼓山區",
        },
        {
          query,
          title: "賀鴨郎 高雄市",
          url: "https://instagram.com/reel/good?igsh=two",
          snippet: "高雄市鼓山區",
        },
      ],
    },
  );

  assert.equal(pack.receipt.rawResultCount, 10);
  assert.equal(pack.sources.length, 1);
  assert.equal(pack.sources[0]?.url, "https://instagram.com/reel/good");
  assert.equal(pack.receipt.independentResultCount, 1);
});

test("isolates a partial public-search failure without discarding successful sources", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["instagram"] },
    {
      search: async (query) => {
        if (query === 'site:instagram.com "賀鴨郎"') {
          throw new Error("provider unavailable with secret details");
        }
        return [{
          query,
          title: "賀鴨郎 高雄市",
          url: "https://instagram.com/reel/partial88",
          snippet: "高雄市鼓山區",
        }];
      },
    },
  );

  assert.equal(pack.sources.length, 1);
  assert.deepEqual(pack.coverage[0], {
    platform: "instagram",
    method: "public_index",
    status: "partial",
    queries: [
      'site:instagram.com "賀鴨郎" "高雄市"',
      'site:instagram.com "賀鴨郎"',
    ],
    inspectedCount: 1,
    resultCount: 1,
    blockedReason: "public_search_failed",
  });
  assert.deepEqual(pack.receipt.failedPlatforms, []);
  assert.ok(!JSON.stringify(pack).includes("secret details"));
});

test("reports an all-query failure without leaking provider errors", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["threads"] },
    {
      search: async () => {
        throw new Error("API_KEY=must-not-leak");
      },
    },
  );

  assert.equal(pack.sources.length, 0);
  assert.equal(pack.coverage[0]?.status, "failed");
  assert.equal(pack.coverage[0]?.blockedReason, "public_search_failed");
  assert.deepEqual(pack.receipt.failedPlatforms, ["threads"]);
  assert.ok(!JSON.stringify(pack).includes("API_KEY"));
});

test("caps public-search concurrency and returns after the aggregate deadline", async () => {
  let active = 0;
  let peakActive = 0;
  const platforms = [
    "instagram",
    "tiktok",
    "youtube",
    "xiaohongshu",
    "douyin",
    "threads",
    "x",
  ] as const;

  const bounded = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: [...platforms] },
    {
      search: async () => {
        active += 1;
        peakActive = Math.max(peakActive, active);
        await new Promise((resolve) => setTimeout(resolve, 5));
        active -= 1;
        return [];
      },
    },
  );
  assert.ok(peakActive <= 3);
  assert.equal(bounded.coverage.length, 7);

  const startedAt = Date.now();
  const timedOut = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["instagram"] },
    {
      deadlineMs: 20,
      search: async () => await new Promise(() => {}),
    },
  );

  assert.ok(Date.now() - startedAt < 500);
  assert.equal(timedOut.coverage[0]?.status, "failed");
  assert.equal(timedOut.coverage[0]?.blockedReason, "public_search_failed");
});

test("caps returned sources at five per supported platform", async () => {
  const urlForPlatform = {
    instagram: (index: number) => `https://instagram.com/reel/${index}`,
    tiktok: (index: number) => `https://tiktok.com/@food/video/${index}`,
    youtube: (index: number) => `https://youtube.com/watch?v=${index}`,
    xiaohongshu: (index: number) => `https://xiaohongshu.com/explore/${index}`,
    douyin: (index: number) => `https://douyin.com/video/${index}`,
    threads: (index: number) => `https://threads.net/@food/post/${index}`,
    x: (index: number) => `https://x.com/food/status/${index}`,
  };
  const platforms = Object.keys(urlForPlatform) as Array<keyof typeof urlForPlatform>;
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms, maxResultsPerPlatform: 5 },
    {
      search: async (query, platform) => Array.from({ length: 8 }, (_, index) => ({
        query,
        title: `賀鴨郎 高雄市鼓山區 ${index}`,
        url: urlForPlatform[platform](index),
        snippet: "高雄市鼓山區美術東二路",
      })),
    },
  );

  assert.equal(pack.receipt.rawResultCount, 70);
  assert.equal(pack.sources.length, 35);
  assert.ok(pack.coverage.every((entry) => entry.resultCount === 5));
});

test("rejects private residences before running public discovery", async () => {
  let searched = false;

  await assert.rejects(
    discoverRelatedPlaceSources(
      {
        ...confirmedPlace,
        name: "My Home",
        category: "home",
      },
      { platforms: ["instagram"] },
      {
        search: async () => {
          searched = true;
          return [];
        },
      },
    ),
    /only supports public venues/,
  );
  assert.equal(searched, false);
});

test("serializes the agent-callable response without changing candidate status", async () => {
  const pack = await discoverRelatedPlaceSources(
    confirmedPlace,
    { platforms: ["youtube"], maxResultsPerPlatform: 1 },
    {
      now: () => new Date("2026-07-24T12:00:00.000Z"),
      search: async (query) => [{
        query,
        title: "賀鴨郎 高雄市",
        url: "https://youtube.com/shorts/receipt88",
        snippet: "高雄市鼓山區美術東二路",
      }],
    },
  );
  const body = relatedPlaceSourcePackResponseBody(pack) as {
    sources: Array<Record<string, unknown>>;
    receipt: Record<string, unknown>;
  };

  assert.equal(body.sources[0]?.identity_status, "candidate");
  assert.equal(body.sources[0]?.match_confidence, 0.86);
  assert.equal(body.receipt.source_boundary, "public_web_index");
  assert.equal(body.receipt.privacy, "owner_private");
});

test("the server route delegates through the owner-scoped endpoint service and does not persist results", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function handlePlaceRelatedSources"),
    serverSource.indexOf("async function fetchPlacesWithOptionalVisibility"),
  );
  const ownerIndex = handler.indexOf("await ownedPlaceForAnalysis(ownedPlaceId, ownerId)");
  const endpointIndex = handler.indexOf("await executeRelatedPlaceSourcesEndpoint");

  assert.ok(endpointIndex >= 0);
  assert.ok(ownerIndex > endpointIndex);
  assert.match(handler, /Bearer account required/);
  assert.match(handler, /relatedPlaceSourcesRateLimiter\.consume\(userId\)/);
  assert.match(handler, /verifyPublicVenue: verifyRelatedSourcesPublicVenue/);
  assert.doesNotMatch(handler, /\binsert\b|\bupdate\b|\bdelete\b/i);
  assert.match(handler, /Cache-Control", "private, no-store"/);
  assert.match(handler, /Vary", "Authorization"/);
  assert.match(
    serverSource,
    /isV0 && resource === "places" && id && segments\[2\] === "related-sources"/,
  );
});
