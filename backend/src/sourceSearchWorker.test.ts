import assert from "node:assert/strict";
import test from "node:test";
import {
  buildSourceRecoveryQueries,
  candidatesFromSearchResults,
  defaultFetchMetadataHTML,
  parseDuckDuckGoResults,
  parsePersistedSourceResolution,
  resolveSourceDocument,
  runSourceSearchRecovery,
  sourceResolutionResponseBody,
} from "./sourceSearchWorker.js";

test("buildSourceRecoveryQueries strips Instagram tracking query", () => {
  const queries = buildSourceRecoveryQueries({
    sourceUrl: "https://www.instagram.com/reel/DWmzyodgbuv/?igsh=tracking",
  });

  assert.deepEqual(queries, [
    "instagram reel DWmzyodgbuv place",
    "DWmzyodgbuv restaurant venue",
    "\"https://www.instagram.com/reel/DWmzyodgbuv/\"",
  ]);
});

test("buildSourceRecoveryQueries adds city venue and handle recovery queries", () => {
  const queries = buildSourceRecoveryQueries({
    sourceUrl: "https://www.instagram.com/reel/DZSU9JsSkB1/",
    rawText: `這次讓我念念不忘的是高雄的賀鴨郎
@houyacantoneserestaurant`,
  });

  assert.ok(queries.includes("賀鴨郎 高雄 地址"));
  assert.ok(queries.includes("houyacantoneserestaurant 賀鴨郎"));
  assert.ok(queries.includes("賀鴨郎 官方 餐廳 訂位"));
});

test("buildSourceRecoveryQueries does not promote generic city creator handle clues", () => {
  const queries = buildSourceRecoveryQueries({
    sourceUrl: "https://www.instagram.com/reel/DGenericCityOnly/",
    rawText: `這次讓我念念不忘的是高雄的那間店
@keke_travel`,
  });

  assert.ok(!queries.some((query) => query.includes("那間店") && query.includes("地址")));
});

test("defaultFetchMetadataHTML reads social metadata without failing on large pages", async () => {
  const html = `<!doctype html><html><head>
    <meta name="description" content="287 likes - google.foodie: &quot;&lt;樂葵法式鐵板燒-微風南山店&gt; 📍台北101&quot;">
    <meta name="twitter:image" content="https://example.com/thumb.jpg">
  </head><body>${"x".repeat(1_500_000)}</body></html>`;
  const fetcher = async () =>
    new Response(html, {
      status: 200,
      headers: {
        "content-length": String(html.length),
        "content-type": "text/html; charset=utf-8",
      },
    });

  const head = await defaultFetchMetadataHTML("https://93.184.216.34/p/DZpDN5zkrH4/", 512_000, fetcher);
  assert.match(head, /樂葵法式鐵板燒-微風南山店/);
  assert.doesNotMatch(head, /x{1000}/);
});

test("defaultFetchMetadataHTML follows safe social short-link redirects", async () => {
  const html = `<!doctype html><html><head>
    <meta name="description" content="【京都 先斗町】 先斗町しゃぶしゃぶすき焼き きらく 位于京都先斗町的人气和牛寿喜烧名店。地址：京都府京都市中京区先斗町通四条上る柏屋町169-2">
  </head><body>${"x".repeat(1_000_000)}</body></html>`;
  const seen: string[] = [];
  const fetcher = async (url: string | URL | Request) => {
    const value = url.toString();
    seen.push(value);
    if (value === "http://xhslink.com/m/66nsbd6V2We") {
      return new Response(null, {
        status: 302,
        headers: {
          "location": "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
        },
      });
    }
    return new Response(html, { status: 200 });
  };

  const head = await defaultFetchMetadataHTML("http://xhslink.com/m/66nsbd6V2We", 512_000, fetcher);
  assert.deepEqual(seen, [
    "http://xhslink.com/m/66nsbd6V2We",
    "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
  ]);
  assert.match(head, /先斗町しゃぶしゃぶすき焼き きらく/);
  assert.doesNotMatch(head, /x{1000}/);
});

test("defaultFetchMetadataHTML blocks redirects to private hosts", async () => {
  const fetcher = async () =>
    new Response(null, {
      status: 302,
      headers: { "location": "http://127.0.0.1/private" },
    });

  await assert.rejects(
    defaultFetchMetadataHTML("https://example.com/short", 512_000, fetcher),
    /Blocked non-public URL/,
  );
});

test("source resolution contract preserves redirect chain and canonical content id", async () => {
  const originalURL = "http://xhslink.com/m/sourceContract88";
  const resolvedURL = "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00";
  const html = `<!doctype html><html><head>
    <meta property="og:title" content="先斗町しゃぶしゃぶすき焼き きらく" />
    <meta property="og:description" content="京都府京都市中京区先斗町通四条上る柏屋町169-2" />
    <meta property="og:image" content="https://example.com/kiraku.jpg" />
  </head></html>`;
  const fetcher = async (url: string | URL | Request) => {
    if (url.toString() === originalURL) {
      return new Response(null, { status: 302, headers: { location: resolvedURL } });
    }
    return new Response(html, { status: 200 });
  };

  const document = await resolveSourceDocument(originalURL, 512_000, fetcher);

  assert.equal(document.resolution.status, "resolved");
  assert.equal(document.resolution.originalURL, originalURL);
  assert.equal(document.resolution.resolvedURL, resolvedURL);
  assert.deepEqual(document.resolution.redirectChain, [originalURL, resolvedURL]);
  assert.equal(document.resolution.canonicalContentID, "6a20eacb000000000f03ac00");
  assert.equal(document.resolution.title, "先斗町しゃぶしゃぶすき焼き きらく");
  assert.equal(document.resolution.caption, "京都府京都市中京区先斗町通四条上る柏屋町169-2");
  assert.equal(document.resolution.thumbnailURL, "https://example.com/kiraku.jpg");
  assert.deepEqual(sourceResolutionResponseBody(document.resolution), {
    original_url: originalURL,
    resolved_url: resolvedURL,
    redirect_chain: [originalURL, resolvedURL],
    canonical_content_id: "6a20eacb000000000f03ac00",
    status: "resolved",
    title: "先斗町しゃぶしゃぶすき焼き きらく",
    caption: "京都府京都市中京区先斗町通四条上る柏屋町169-2",
    thumbnail_url: "https://example.com/kiraku.jpg",
  });
});

test("source resolution caches successful short-link documents", async () => {
  const sourceURL = "https://93.184.216.34/cache-source-contract";
  let fetchCount = 0;
  const fetcher = async () => {
    fetchCount += 1;
    return new Response(`
      <html><head><meta property="og:title" content="Cache Source Cafe" /></head></html>
    `, { status: 200 });
  };

  const first = await resolveSourceDocument(sourceURL, 512_000, fetcher);
  const second = await resolveSourceDocument(sourceURL, 512_000, fetcher);

  assert.equal(first.resolution.status, "resolved");
  assert.deepEqual(second, first);
  assert.equal(fetchCount, 1);
});

test("source resolution cache keeps fragment merchant ids isolated", async () => {
  let fetchCount = 0;
  const fetcher = async (url: string | URL | Request) => {
    fetchCount += 1;
    const merchantID = new URL(url.toString()).hash.slice("#id=".length);
    return new Response(`
      <html><head><meta property="og:title" content="Merchant ${merchantID}" /></head></html>
    `, { status: 200 });
  };

  const first = await resolveSourceDocument("https://h5.ele.me/shop/#id=merchant111", 512_000, fetcher);
  const second = await resolveSourceDocument("https://h5.ele.me/shop/#id=merchant222", 512_000, fetcher);

  assert.equal(first.resolution.canonicalContentID, "merchant111");
  assert.equal(second.resolution.canonicalContentID, "merchant222");
  assert.equal(fetchCount, 2);
});

test("source recovery reports login wall without creating a review candidate", async () => {
  const sourceURL = "https://93.184.216.34/login-required";
  const output = await runSourceSearchRecovery(
    { sourceUrl: sourceURL, maxQueries: 0 },
    async () => "",
    async () => [],
    {
      sourceDocumentResolver: async () => resolveSourceDocument(
        sourceURL,
        512_000,
        async () => new Response(`
          <html><head></head>
          <body>请先登录后在美团 App 中查看</body></html>
        `, { status: 200 }),
      ),
    },
  );

  assert.equal(output.sourceResolution?.status, "blocked_login");
  assert.equal(output.candidates.length, 0);
  assert.equal(output.receipt.output, "source_only_clue");
});

test("source resolution distinguishes expired and opaque unresolved pages", async () => {
  const expired = await resolveSourceDocument(
    "https://93.184.216.34/expired",
    512_000,
    async () => new Response("链接已失效", { status: 410 }),
  );
  const opaque = await resolveSourceDocument(
    "https://93.184.216.34/opaque-code?id=not-a-platform-id",
    512_000,
    async () => new Response("<html><body></body></html>", { status: 200 }),
  );

  assert.equal(expired.resolution.status, "expired");
  assert.equal(opaque.resolution.status, "opaque_unresolved");
  assert.equal(opaque.resolution.canonicalContentID, undefined);
});

test("source resolution ignores a malformed canonical URL", async () => {
  const sourceURL = "https://93.184.216.34/malformed-canonical";
  const document = await resolveSourceDocument(
    sourceURL,
    512_000,
    async () => new Response(`
      <html><head>
        <link rel="canonical" href="http://[invalid" />
        <meta property="og:title" content="Readable Source Cafe" />
      </head></html>
    `, { status: 200 }),
  );

  assert.equal(document.resolution.status, "resolved");
  assert.equal(document.resolution.resolvedURL, sourceURL);
  assert.equal(document.resolution.title, "Readable Source Cafe");
});

test("source recovery reuses a persisted resolution after the short link expires", async () => {
  const originalURL = "https://xhslink.com/m/persisted88";
  const persisted = parsePersistedSourceResolution({
    original_url: originalURL,
    resolved_url: "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
    redirect_chain: [
      originalURL,
      "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
    ],
    canonical_content_id: "6a20eacb000000000f03ac00",
    status: "resolved",
    title: "Kiraku Kyoto",
    caption: "2415 Park Ave, Tustin, CA 92782",
  }, originalURL);
  let fetchCount = 0;

  const output = await runSourceSearchRecovery(
    { sourceUrl: originalURL, maxQueries: 0 },
    async () => {
      fetchCount += 1;
      throw new Error("expired short link");
    },
    async () => [],
    { persistedSourceResolution: persisted },
  );

  assert.equal(fetchCount, 0);
  assert.equal(output.sourceResolution?.canonicalContentID, "6a20eacb000000000f03ac00");
  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0]?.name, "Kiraku Kyoto");
  assert.match(output.candidates[0]?.address ?? "", /2415 Park Ave, Tustin/);
});

test("persisted source resolution rejects mismatched or unsafe URLs", () => {
  const originalURL = "https://xhslink.com/m/persisted99";
  const base = {
    original_url: originalURL,
    resolved_url: "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
    redirect_chain: [originalURL],
    status: "resolved",
  };

  assert.equal(parsePersistedSourceResolution(base, "https://xhslink.com/m/different"), undefined);
  assert.equal(parsePersistedSourceResolution({ ...base, resolved_url: "http://127.0.0.1/private" }, originalURL), undefined);
  assert.equal(parsePersistedSourceResolution({ ...base, resolved_url: "https://user:secret@example.com/place" }, originalURL), undefined);
  assert.equal(parsePersistedSourceResolution({ ...base, status: "invented" }, originalURL), undefined);
});

test("parseDuckDuckGoResults extracts titles snippets and canonical target URLs", () => {
  const html = `
    <div class="result">
      <a class="result__a" href="/l/?uddg=https%3A%2F%2Fwww.theranchlb.com%2Fdining%2Fthe-porch">The Porch at The Ranch at Laguna Beach - Official</a>
      <a class="result__snippet">31106 Coast Hwy, Laguna Beach, CA. Outdoor dining and reservations.</a>
    </div>
  `;

  const results = parseDuckDuckGoResults(html, "DWmzyodgbuv restaurant venue");

  assert.equal(results.length, 1);
  assert.equal(results[0].title, "The Porch at The Ranch at Laguna Beach - Official");
  assert.equal(results[0].url, "https://www.theranchlb.com/dining/the-porch");
  assert.match(results[0].snippet ?? "", /31106 Coast Hwy/);
});

test("candidatesFromSearchResults keeps search-derived candidates review scoped", () => {
  const candidates = candidatesFromSearchResults([
    {
      query: "DWmzyodgbuv restaurant venue",
      title: "The Porch at The Ranch at Laguna Beach - Official",
      url: "https://www.theranchlb.com/dining/the-porch",
      snippet: "31106 Coast Hwy, Laguna Beach, CA",
    },
  ]);

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].name, "The Porch at The Ranch at Laguna Beach");
  assert.equal(candidates[0].address, "31106 Coast Hwy, Laguna Beach");
  assert.equal(candidates[0].confidence, 0.52);
  assert.ok(candidates[0].missingInfo.includes("Verified coordinates"));
  assert.ok(candidates[0].missingInfo.includes("Search-derived candidate; verify source before saving"));
});

test("candidatesFromSearchResults rejects generic social maps and list results", () => {
  const candidates = candidatesFromSearchResults([
    {
      query: "instagram reel DYmFHrizV3E place",
      title: "Instagram",
      url: "https://www.instagram.com/reels/",
    },
    {
      query: "DYJuEzgTy79 restaurant venue",
      title: "Google Maps",
      url: "https://maps.google.com/",
    },
    {
      query: "DYmFHrizV3E restaurant venue",
      title: "THE BEST 10 Venues & Event Spaces in IRVINE, CA - Yelp",
      url: "https://www.yelp.com/search?cflt=venues&find_loc=Irvine,+CA",
    },
    {
      query: "DWmzyodgbuv restaurant venue",
      title: "Restaurant Venues for Rent in Los Angeles, CA - Tagvenue USA",
      url: "https://www.tagvenue.com/us/hire/restaurant-venues/los-angeles",
    },
  ]);

  assert.equal(candidates.length, 0);
});

test("candidatesFromSearchResults allows official venue evidence without coordinates", () => {
  const candidates = candidatesFromSearchResults([
    {
      query: "venue official",
      title: "Fabel Friet - Official Site",
      url: "https://fabelfriet.com/",
      snippet: "Fresh Dutch fries with truffle mayonnaise in Amsterdam.",
    },
  ]);

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].name, "Fabel Friet");
  assert.equal(candidates[0].address, "");
  assert.equal(candidates[0].confidence, 0.38);
});

test("candidatesFromSearchResults extracts Taiwanese official venue and address evidence", () => {
  const candidates = candidatesFromSearchResults([
    {
      query: "賀鴨郎 高雄 地址",
      title: "賀鴨郎｜粵菜烤鴨中餐廳-承億酒店",
      url: "https://www.taiurbanresort.com.tw/restaurant-detail/HOU_YA/",
      snippet: "賀鴨郎 粵菜烤鴨中餐廳｜B1。餐廳地點 高雄市前鎮區林森四路189號B1。電話訂位 07-3333999。",
    },
  ]);

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].name, "賀鴨郎");
  assert.equal(candidates[0].address, "高雄市前鎮區林森四路189號B1");
  assert.ok(candidates[0].missingInfo.includes("Verified coordinates"));
});

test("runSourceSearchRecovery uses injected fetcher and returns candidates", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DWmzyodgbuv/?igsh=tracking",
      maxQueries: 1,
    },
    async () => `
      <div class="result">
        <a class="result__a" href="https://example.com/place">The Porch at The Ranch at Laguna Beach - Official</a>
        <div class="result__snippet">31106 Coast Hwy, Laguna Beach, CA</div>
      </div>
    `,
  );

  assert.deepEqual(output.queries, ["instagram reel DWmzyodgbuv place"]);
  assert.equal(output.searchResults.length, 1);
  assert.equal(output.candidates[0].name, "The Porch at The Ranch at Laguna Beach");
  assert.equal(output.receipt.input, "social_url");
  assert.equal(output.receipt.capabilityLevel, "public_search_recovery");
  assert.equal(output.receipt.output, "review_candidate");
  assert.ok(output.receipt.found.includes("review_candidate"));
  assert.ok(output.receipt.tried.includes("public_search"));
  assert.ok(output.receipt.missing.includes("Verified coordinates"));
});

test("source recovery classifies mainland place platforms without treating Taobao products as place links", async () => {
  const emptyFetcher = async () => "";
  const noMedia = async () => [];
  const meituan = await runSourceSearchRecovery(
    { sourceUrl: "https://i.waimai.meituan.com/restaurant/123456789", maxQueries: 0 },
    emptyFetcher,
    noMedia,
  );
  const taobaoInstantCommerce = await runSourceSearchRecovery(
    { sourceUrl: "https://h5.ele.me/shop/#id=987654321", maxQueries: 0 },
    emptyFetcher,
    noMedia,
  );
  const taobaoProduct = await runSourceSearchRecovery(
    { sourceUrl: "https://m.tb.cn/h.exampleProduct", maxQueries: 0 },
    emptyFetcher,
    noMedia,
  );
  const meituanLookalike = await runSourceSearchRecovery(
    { sourceUrl: "https://meituan.com.evil.example/restaurant/123456789", maxQueries: 0 },
    emptyFetcher,
    noMedia,
  );
  const elemeLookalike = await runSourceSearchRecovery(
    { sourceUrl: "https://ele.me.evil.example/shop/#id=987654321", maxQueries: 0 },
    emptyFetcher,
    noMedia,
  );

  assert.equal(meituan.receipt.input, "social_url");
  assert.equal(taobaoInstantCommerce.receipt.input, "social_url");
  assert.equal(taobaoProduct.receipt.input, "web_url");
  assert.equal(meituanLookalike.receipt.input, "web_url");
  assert.equal(elemeLookalike.receipt.input, "web_url");
});

test("runSourceSearchRecovery creates review candidate from explicit source metadata address", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DWmzyodgbuv/?igsh=tracking",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="Lorna: OC Insider on Instagram: &quot;&#x1f4cd; The Porch at The Ranch at Laguna Beach &#064;theranchlb
31106 Coast Hwy, Laguna Beach&quot;">
          <meta property="og:description" content="6,930 likes - thescenesouthoc: &quot;&#x1f4cd; The Porch at The Ranch at Laguna Beach &#064;theranchlb
31106 Coast Hwy, Laguna Beach. Tucked inside Aliso Canyon.&quot;">
        `;
      }

      return `
        <div class="result">
          <a class="result__a" href="https://www.instagram.com/reels/">Instagram</a>
        </div>
      `;
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "The Porch at The Ranch at Laguna Beach");
  assert.equal(output.candidates[0].address, "31106 Coast Hwy, Laguna Beach");
  assert.equal(output.candidates[0].confidence, 0.62);
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("Source metadata contains explicit place/address evidence")));
  assert.equal(output.receipt.capabilityLevel, "metadata_enrichment");
  assert.equal(output.receipt.output, "review_candidate");
  assert.ok(output.receipt.found.includes("public_metadata"));
  assert.ok(output.receipt.found.includes("explicit_address"));
});

test("runSourceSearchRecovery binds Instagram caption venue handle to explicit address", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DOpenaireLA/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="michelle rome on Instagram: &quot;&#064;openaire_la 🌿 LA’s Greenhouse Culinary Haven
operated by Two Michelin-starred chef Josiah Citrin.

Located on the second floor of The LINE Hotel in Koreatown &#064;thelinehotel

📍3515 Wilshire Blvd
Los Angeles, CA 90010
United States&quot;">
        `;
      }

      return `
        <div class="result">
          <a class="result__a" href="https://www.instagram.com/reels/">Instagram</a>
        </div>
      `;
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "Openaire");
  assert.equal(output.candidates[0].address, "3515 Wilshire Blvd, Los Angeles, CA 90010");
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("@openaire_la")));
  assert.doesNotMatch(output.candidates[0].name, /michelle/i);
  assert.doesNotMatch(output.candidates[0].name, /line hotel/i);
  assert.equal(output.receipt.output, "review_candidate");
  assert.ok(output.receipt.found.includes("explicit_address"));
});

test("runSourceSearchRecovery blocks private source metadata URLs before fetch", async () => {
  const fetchedURLs: string[] = [];
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "http://127.0.0.1:5432/internal",
      maxQueries: 0,
    },
    async (url) => {
      fetchedURLs.push(url);
      return "";
    },
  );

  assert.deepEqual(fetchedURLs, []);
  assert.equal(output.searchResults.length, 0);
  assert.equal(output.candidates.length, 0);
  assert.ok(!output.receipt.found.includes("public_metadata"));
});

test("runSourceSearchRecovery skips hours and uses venue line before non-US address", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DYmFHrizV3E/?igsh=tracking",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="城市記憶 on Instagram: &quot;跑了幾次Jo &amp; Dawson的延南洞店
-
👉🏻Jo &amp; Dawson 光化門店
🍽️07:30-20:00
📍首爾特別市 鐘路區 淸進洞 70&quot;">
        `;
      }

      return "";
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "Jo & Dawson 光化門店");
  assert.equal(output.candidates[0].address, "首爾特別市 鐘路區 淸進洞 70");
});

test("runSourceSearchRecovery keeps generic live search pages diagnostic-only", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DYJuEzgTy79/?igsh=tracking",
      maxQueries: 1,
    },
    async () => `
      <div class="result">
        <a class="result__a" href="https://www.instagram.com/reels/">Instagram</a>
      </div>
      <div class="result">
        <a class="result__a" href="https://www.yelp.com/search?cflt=venues&find_loc=Orange,+CA">THE BEST 10 VENUES & EVENT SPACES in ORANGE, CA - Yelp</a>
      </div>
    `,
  );

  assert.equal(output.searchResults.length, 2);
  assert.equal(output.candidates.length, 0);
  assert.equal(output.receipt.output, "source_only_clue");
  assert.ok(output.receipt.found.includes("source_url"));
  assert.ok(output.receipt.found.includes("search_results"));
  assert.ok(output.receipt.tried.includes("public_search"));
  assert.ok(output.receipt.missing.includes("Verified venue name"));
  assert.match(output.receipt.nextBestClue, /screenshot/);
});


test("runSourceSearchRecovery records bounded server media fetch and keyframe evidence", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DZM8vmZBuNM/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="Food reel on Instagram">
          <meta property="og:image" content="https://cdn.example.test/reel-cover.jpg">
          <meta property="og:video" content="https://cdn.example.test/reel-video.mp4">
        `;
      }
      return "";
    },
    async (metadata) => {
      assert.equal(metadata.imageURL, "https://cdn.example.test/reel-cover.jpg");
      assert.equal(metadata.videoURL, "https://cdn.example.test/reel-video.mp4");
      return [
        {
          kind: "thumbnail",
          url: metadata.imageURL ?? "",
          contentType: "image/jpeg",
          byteLength: 1234,
          sha256: "thumbnail-hash",
        },
        {
          kind: "video_keyframe",
          url: metadata.videoURL ?? "",
          contentType: "image/jpeg",
          byteLength: 2345,
          sha256: "frame-hash",
          frameSecond: 1,
        },
      ];
    },
  );

  assert.deepEqual(output.mediaEvidence.map((item) => item.kind), ["thumbnail", "video_keyframe"]);
  assert.ok(output.receipt.found.includes("public_thumbnail_url"));
  assert.ok(output.receipt.found.includes("public_video_url"));
  assert.ok(output.receipt.found.includes("server_keyframe_extraction"));
  assert.ok(output.receipt.tried.includes("public_media_fetch"));
  assert.ok(output.receipt.tried.includes("server_keyframe_extraction"));
  assert.equal(output.receipt.capabilityLevel, "media_evidence_recovery");
});

test("runSourceSearchRecovery turns keyframe OCR and Places corroboration into cited review candidate", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DThinMetaOnly/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="Food reel on Instagram">
          <meta property="og:image" content="https://cdn.example.test/thin-cover.jpg">
          <meta property="og:video" content="https://cdn.example.test/thin-video.mp4">
        `;
      }
      return `
        <div class="result">
          <a class="result__a" href="https://www.instagram.com/reels/">Instagram</a>
        </div>
      `;
    },
    async (metadata) => [
      {
        kind: "video_keyframe",
        url: metadata.videoURL ?? "",
        contentType: "image/jpeg",
        byteLength: 2345,
        sha256: "frame-hash",
        frameSecond: 1,
        textSource: "ocr",
        text: "🏠 Utopia Euro Caffe\n地址 2489 Park Ave, Tustin, CA",
      },
    ],
    {
      placesCorroborator: async (candidate) => {
        assert.equal(candidate.name, "Utopia Euro Caffe");
        assert.equal(candidate.address, "2489 Park Ave, Tustin");
        return {
          name: "Utopia Euro Caffe",
          address: "2489 Park Ave, Tustin, CA 92782",
          latitude: 33.7001,
          longitude: -117.8273,
          placeId: "google_utopia",
          confidenceBoost: 0.24,
          evidence: ["Places resolver matched OCR name/address"],
        };
      },
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "Utopia Euro Caffe");
  assert.equal(output.candidates[0].address, "2489 Park Ave, Tustin, CA 92782");
  assert.equal(output.candidates[0].latitude, 33.7001);
  assert.equal(output.candidates[0].longitude, -117.8273);
  assert.ok(output.candidates[0].confidence > 0.7);
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("Keyframe OCR at 1s")));
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("Places resolver matched OCR name/address")));
  assert.ok(output.candidates[0].evidence.some((item) => item === "Rubric verdict: corroborated"));
  assert.ok(output.candidates[0].evidence.some((item) => item.startsWith("Confidence reason:")));
  assert.ok(!output.candidates[0].missingInfo.includes("Verified coordinates"));
  assert.ok(output.candidates[0].missingInfo.includes("User confirmation before saving as Map Stamp"));
  assert.equal(output.receipt.output, "review_candidate");
  assert.equal(output.receipt.capabilityLevel, "media_evidence_recovery");
});

test("runSourceSearchRecovery sends safe projection to external rubric adapter", async () => {
  const originalFetch = globalThis.fetch;
  const originalRubricURL = process.env.SAVE_EVIDENCE_RUBRIC_URL;
  const originalRubricToken = process.env.SAVE_EVIDENCE_RUBRIC_TOKEN;
  const originalPlacesKey = process.env.GOOGLE_PLACES_API_KEY;
  const postedBodies: unknown[] = [];
  process.env.SAVE_EVIDENCE_RUBRIC_URL = "https://example.com/save-evidence-rubric";
  process.env.SAVE_EVIDENCE_RUBRIC_TOKEN = "test-token";
  delete process.env.GOOGLE_PLACES_API_KEY;
  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    assert.equal(init?.method, "POST");
    assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer test-token");
    postedBodies.push(JSON.parse(String(init?.body)));
    return new Response(JSON.stringify({
      evidence_tier: "likely",
      confidence_reason: "LLM rubric saw source text and ASR text pointing to the same venue",
      missing_info: ["Verified coordinates", "User confirmation before saving as Map Stamp"],
    }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;

  try {
    const output = await runSourceSearchRecovery(
      {
        sourceUrl: "https://www.instagram.com/reel/DExternalRubric/",
        maxQueries: 1,
      },
      async (url) => {
        if (url.includes("instagram.com")) {
          return `
            <meta property="og:title" content="Utopia Euro Caffe on Instagram">
            <meta property="og:description" content="Utopia Euro Caffe 2489 Park Ave, Tustin">
            <meta property="og:video" content="https://cdn.example.test/reel.mp4">
          `;
        }
        return "";
      },
      async () => [
        {
          kind: "video",
          url: "https://cdn.example.test/reel.mp4",
          textSource: "asr",
          text: "We are at Utopia Euro Caffe in Tustin for coffee.",
        },
      ],
    );

    const candidate = output.candidates.find((item) => item.name === "Utopia Euro Caffe");
    assert.ok(candidate);
    assert.ok(candidate.evidence.includes("Rubric verdict: likely"));
    assert.ok(candidate.evidence.some((item) => item.includes("LLM rubric saw source text")));
    const metadataBody = postedBodies.find((item) => {
      const body = item as { candidate?: { name?: string } };
      return body.candidate?.name === "Utopia Euro Caffe";
    }) as {
      source?: { title?: string; resolved_url_host?: string };
      candidate?: { name?: string; evidence?: string[] };
      media_evidence?: Array<{ text_source?: string; text?: string }>;
    } | undefined;
    const asrBody = postedBodies.find((item) => {
      const body = item as { media_evidence?: Array<{ text_source?: string }> };
      return body.media_evidence?.some((media) => media.text_source === "asr");
    });
    assert.ok(metadataBody);
    assert.equal(metadataBody.source?.title, "Utopia Euro Caffe on Instagram");
    assert.equal(metadataBody.source?.resolved_url_host, "www.instagram.com");
    assert.equal(metadataBody.candidate?.name, "Utopia Euro Caffe");
    assert.ok(asrBody);
    assert.ok(!JSON.stringify(postedBodies).includes("cdn.example.test/reel.mp4"));
  } finally {
    globalThis.fetch = originalFetch;
    if (originalRubricURL === undefined) delete process.env.SAVE_EVIDENCE_RUBRIC_URL;
    else process.env.SAVE_EVIDENCE_RUBRIC_URL = originalRubricURL;
    if (originalRubricToken === undefined) delete process.env.SAVE_EVIDENCE_RUBRIC_TOKEN;
    else process.env.SAVE_EVIDENCE_RUBRIC_TOKEN = originalRubricToken;
    if (originalPlacesKey === undefined) delete process.env.GOOGLE_PLACES_API_KEY;
    else process.env.GOOGLE_PLACES_API_KEY = originalPlacesKey;
  }
});
