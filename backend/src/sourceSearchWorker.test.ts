// Historical parser fixtures exercise the retained non-social/legacy helper.
// socialSemanticRecovery.test.ts covers the production social routing contract.
import assert from "node:assert/strict";
import test from "node:test";
import { AnalysisControlError, withAnalysisUsage, type AnalysisUsageStore } from "./analysisUsage.js";
import {
  buildSourceRecoveryQueries,
  candidatesFromSearchResults,
  defaultFetchMetadataHTML,
  defaultFetchText,
  defaultPlacesCorroborator,
  fetchBoundedMedia,
  parseDuckDuckGoResults,
  parsePersistedSourceResolution,
  resolveSourceDocument,
  runLegacySourceSearchRecovery as runSourceSearchRecovery,
  sourceResolutionResponseBody,
  searchPublicWebResults,
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
  </head><body><script>{"caption":{"text":"完整原文店名與地址"}}</script></body></html>`;
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
  assert.match(head, /完整原文店名與地址/);
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

test("runSourceSearchRecovery preserves address-local venue over earlier quoted clues", async () => {
  for (const introduction of ["今天吃「豚骨拉麵」", "昨天去「一蘭拉麵」，今天換這家"]) {
    const output = await runSourceSearchRecovery(
      { sourceUrl: "https://www.instagram.com/reel/addressLocalVenue/", maxQueries: 0 },
      async () => `<meta property="og:title" content="alice on Instagram: &quot;${introduction}
松阪亭別邸
📍台北市大安區安和路一段100號&quot;">`,
      async () => [],
      { placesCorroborator: async () => undefined },
    );
    assert.equal(output.candidates.length, 1);
    assert.equal(output.candidates[0].name, "松阪亭別邸", introduction);
    assert.equal(output.candidates[0].address, "台北市大安區安和路一段100號");
    assert.equal(output.receipt.output, "review_candidate");
  }
});

test("runSourceSearchRecovery retains explicitly labeled venue names resembling creator titles", async () => {
  for (const name of ["咖啡日記", "味蕾食堂", "coffee.diary"]) {
    for (const address of ["台北大安區", "台北市大安區安和路一段100號"]) {
      const output = await runSourceSearchRecovery(
        { sourceUrl: "https://www.instagram.com/reel/labeledVenue/", maxQueries: 0 },
        async () => `<meta property="og:title" content="alice on Instagram: &quot;店名「${name}」
📍${address}&quot;">`,
        async () => [],
        { placesCorroborator: async () => undefined },
      );
      assert.equal(output.candidates.length, 1, `${name}: ${address}`);
      assert.equal(output.candidates[0].name, name);
      assert.equal(output.candidates[0].address, address);
      assert.equal(output.receipt.output, "review_candidate");
      assert.ok(output.candidates[0].missingInfo.includes("Verified coordinates"));
    }
  }
});

test("runSourceSearchRecovery rejects empty venue labels near addresses", async () => {
  for (const label of ["店名「」", "店名："]) {
    const output = await runSourceSearchRecovery(
      { sourceUrl: "https://www.instagram.com/reel/emptyVenueLabel/", maxQueries: 0 },
      async () => `<meta property="og:title" content="alice on Instagram: &quot;${label}
📍台北市大安區安和路一段100號&quot;">`,
      async () => [],
      { placesCorroborator: async () => undefined },
    );
    assert.equal(output.candidates.length, 0, label);
  }
});

test("runSourceSearchRecovery keeps quoted CJK venue bound to street door number", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/DStreetQuotedVenue/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="pattie.eat on Instagram: &quot;店名「松阪亭別邸」
📍台北市大安區安和路一段100號&quot;">
        `;
      }
      return "";
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "松阪亭別邸");
  assert.equal(output.candidates[0].address, "台北市大安區安和路一段100號");
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("explicit place/address evidence")));
  assert.doesNotMatch(output.candidates[0].name, /pattie/i);
  assert.doesNotMatch(output.candidates[0].name, /味蕾/);
});

test("runSourceSearchRecovery emits weak review candidate from IG venue quote without street", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/Dcx98KTJL7n/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="pattie.eat on Instagram: &quot;店名「松阪亭別邸」📍台北大安區 #台北美食&quot;">
          <meta property="og:description" content="珮蒂的味蕾日記 on Instagram: &quot;店名「松阪亭別邸」📍台北大安區&quot;">
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
  assert.equal(output.candidates[0].name, "松阪亭別邸");
  assert.equal(output.candidates[0].address, "台北大安區");
  assert.ok(output.candidates[0].confidence < 0.62);
  assert.ok(output.candidates[0].evidence.some((item) => item.includes("venue name without a street address")));
  assert.ok(
    output.candidates[0].evidence.some((item) => item === "Rubric verdict: weak") ||
      output.candidates[0].evidence.some((item) => item === "Rubric verdict: likely"),
  );
  assert.ok(output.candidates[0].missingInfo.includes("Confirm exact street address"));
  assert.ok(output.candidates[0].missingInfo.includes("Verified coordinates"));
  assert.ok(output.candidates[0].missingInfo.some((item) => /Places|Maps refine|User confirmation/i.test(item)));
  assert.doesNotMatch(output.candidates[0].name, /pattie/i);
  assert.doesNotMatch(output.candidates[0].name, /味蕾/);
  assert.ok(!output.candidates.some((candidate) => /pattie|味蕾日記/i.test(candidate.name)));
  assert.equal(output.receipt.output, "review_candidate");
  assert.equal(output.receipt.capabilityLevel, "metadata_enrichment");
  assert.ok(output.queries.includes("松阪亭別邸 台北 地址"));
});

test("runSourceSearchRecovery does not promote IG creator diary title as venue", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/Dcx98CreatorOnly/",
      maxQueries: 1,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="珮蒂的味蕾日記｜台北美食 on Instagram: &quot;今天想吃什麼呢 #台北美食 @pattie.eat&quot;">
          <meta property="og:description" content="「珮蒂的味蕾日記」今天想吃什麼呢">
        `;
      }
      return "";
    },
  );

  assert.equal(output.candidates.length, 0);
  assert.ok(!output.receipt.found.includes("review_candidate"));
});

test("runSourceSearchRecovery keeps no-street IG venue as review candidate after Places refine", async () => {
  const output = await runSourceSearchRecovery(
    {
      sourceUrl: "https://www.instagram.com/reel/Dcx98KTJL7n/",
      maxQueries: 0,
    },
    async (url) => {
      if (url.includes("instagram.com")) {
        return `
          <meta property="og:title" content="pattie.eat on Instagram: &quot;店名「松阪亭別邸」📍台北大安區&quot;">
        `;
      }
      return "";
    },
    async () => [],
    {
      placesCorroborator: async (candidate) => {
        assert.equal(candidate.name, "松阪亭別邸");
        assert.match(candidate.address, /台北大安區/);
        return {
          name: "松阪亭別邸",
          address: "台北市大安區安和路一段",
          placeId: "places-matsuzaka-tei",
          confidenceBoost: 0.18,
          evidence: ["Places resolver matched the candidate by name/area query"],
        };
      },
    },
  );

  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "松阪亭別邸");
  assert.equal(output.candidates[0].address, "台北市大安區安和路一段");
  assert.equal(output.candidates[0].latitude, undefined);
  assert.ok(output.candidates[0].evidence.some((item) => item === "Rubric verdict: likely"));
  assert.ok(output.candidates[0].missingInfo.includes("Verified coordinates"));
  assert.ok(output.candidates[0].missingInfo.includes("User confirmation before saving as Map Stamp"));
  assert.equal(output.receipt.output, "review_candidate");
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

// Reported public Reel shapes; authors and tracking tokens omitted. The captions
// are evidence for extraction, not verification of current branches or decor.
const reelBranchCaption = "我心中很喜歡的店 CRO#FEE咖啡弄 打造韓系空間美學，連家具都很前衛🪑 餐點好吃格調也很獨特 在臺北這個城市顯得格外的鮮豔 有兩家分店，都在臺北市區 📍CRO_FEE 咖啡弄 復興店 📍CRO_FEE 咖啡弄 敦南店 影片是敦南店的前身，現在改裝潢了，依然值得去一趟！ ▪️ #咖啡弄 #台北下午茶";

async function recoverCaptionFixture(caption: string) {
  return runSourceSearchRecovery(
    { sourceUrl: "https://www.instagram.com/reel/BranchFixture/", maxQueries: 0 },
    async () => `<html><head><meta property="og:title" content="Food creator • Instagram reel"><meta property="og:description" content="${caption}"></head></html>`,
    async () => [],
    { placesCorroborator: async () => undefined },
  );
}

test("Reel metadata keeps explicitly pinned cafe branches as separate review candidates", async () => {
  const output = await recoverCaptionFixture(reelBranchCaption);
  assert.deepEqual(output.candidates.map(candidate => candidate.name), ["CRO_FEE 咖啡弄 復興店", "CRO_FEE 咖啡弄 敦南店"]);
  for (const candidate of output.candidates) {
    assert.equal(candidate.address, "台北");
    assert.equal(candidate.latitude, undefined);
    assert.ok(candidate.missingInfo.includes("User confirmation before saving as Map Stamp"));
    assert.ok(candidate.missingInfo.includes("Confirm exact street address"));
    assert.ok(candidate.evidence.some(line => line.includes("現在改裝潢了")));
  }
  assert.equal(output.receipt.output, "review_candidate");
});

test("Reel without a venue name remains a source clue and asks for a visible name", async () => {
  const output = await recoverCaptionFixture("敢開在台北拉麵一級戰區，這日本老闆到底哪來的膽子？ #日本人開的餐廳 #日本人開的拉麵 #台北拉麵推薦 #台北晚餐推薦 #台北美食推薦");
  assert.deepEqual(output.candidates, []);
  assert.equal(output.receipt.output, "source_only_clue");
  assert.ok(output.receipt.missing.includes("Verified venue name"));
  assert.match(output.receipt.nextBestClue, /screenshot.*venue name/);
});

test("generic pins and malformed pin prose never become venue names", async () => {
  for (const caption of ["📍台北市 📍信義區", "📍咖啡店 📍拉麵店", "📍台北咖啡店", "📍臺北市咖啡店", "📍附近的咖啡店", "📍飲料店", "📍台北拉麵推薦 📍咖啡店推薦", "📍這間店真的很好吃 今天一定要來！", "📍 @food_diary #台北咖啡"]) {
    const output = await recoverCaptionFixture(caption);
    assert.deepEqual(output.candidates, [], caption);
  }
});

test("pinned store parsing generalizes across line breaks and preserves repeated branch identity", async () => {
  const output = await recoverCaptionFixture("台中咖啡：\n📍小山咖啡 北區店\n📌小山咖啡 西區店\n📍小山咖啡 北區店");
  assert.deepEqual(output.candidates.map(candidate => candidate.name), ["小山咖啡 北區店", "小山咖啡 西區店"]);
});


test("store suffix within a brand does not swallow its explicit branch suffix", async () => {
  const output = await recoverCaptionFixture("台北兩間店 📍星光咖啡店 中山店 📍星光咖啡店 信義店");
  assert.deepEqual(output.candidates.map(candidate => candidate.name), ["星光咖啡店 中山店", "星光咖啡店 信義店"]);
});


function mediaStreamFixture(chunks: Uint8Array[], headers: Record<string, string> = {}, status = 200) {
  let reads = 0;
  let cancelled = false;
  let requestSignal: AbortSignal | undefined;
  let calls = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      const chunk = chunks[reads++];
      if (chunk) controller.enqueue(chunk);
      else controller.close();
    },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const response = new Response(body, { status, headers });
  const fetcher: typeof fetch = async (_url, init) => {
    calls += 1;
    requestSignal = init?.signal ?? undefined;
    assert.equal(init?.redirect, "manual");
    return response;
  };
  return { fetcher, response, get reads() { return reads; }, get cancelled() { return cancelled; },
    get calls() { return calls; }, get aborted() { return requestSignal?.aborted; } };
}

for (const contentLength of [undefined, "1", "invalid"]) {
  test(`fetchBoundedMedia stops oversized stream with content-length ${contentLength}`, async () => {
    const headers: Record<string, string> = contentLength === undefined ? {} : { "content-length": contentLength };
    const f = mediaStreamFixture([new Uint8Array(2), new Uint8Array(3), new Uint8Array(40)], headers);
    assert.equal(await fetchBoundedMedia("https://93.184.216.34/media", 4, f.fetcher), undefined);
    assert.equal(f.reads, 2, "must stop without consuming subsequent chunks");
    assert.equal(f.cancelled, true);
    assert.equal(f.aborted, true);
    assert.equal(f.response.body?.locked, false);
  });
}

test("fetchBoundedMedia cancels announced oversized body before reading", async () => {
  const f = mediaStreamFixture([new Uint8Array(10)], { "content-length": "10" });
  assert.equal(await fetchBoundedMedia("https://93.184.216.34/media", 4, f.fetcher), undefined);
  assert.equal(f.reads, 0);
  assert.equal(f.cancelled, true);
  assert.equal(f.aborted, true);
});

test("fetchBoundedMedia accepts exact byte limit across chunks without arrayBuffer", async () => {
  const f = mediaStreamFixture([Uint8Array.of(1, 2), Uint8Array.of(3, 4)], { "content-type": "image/png" });
  f.response.arrayBuffer = async () => { throw new Error("Unbounded arrayBuffer must not be used"); };
  const result = await fetchBoundedMedia("https://93.184.216.34/media", 4, f.fetcher);
  assert.deepEqual(result?.data, Uint8Array.of(1, 2, 3, 4));
  assert.equal(result?.contentType, "image/png");
  assert.equal(f.response.body?.locked, false);
});

for (const status of [302, 503]) {
  test(`fetchBoundedMedia cancels rejected HTTP ${status} response`, async () => {
    const f = mediaStreamFixture([new Uint8Array(2)], { location: "http://127.0.0.1/private" }, status);
    if(status >= 500) await assert.rejects(fetchBoundedMedia("https://93.184.216.34/media", 4, f.fetcher), /Provider HTTP 503/);
    else assert.equal(await fetchBoundedMedia("https://93.184.216.34/media", 4, f.fetcher), undefined);
    assert.equal(f.calls, 1, "redirect must never be followed");
    assert.equal(f.reads, 0);
    assert.equal(f.cancelled, true);
    assert.equal(f.aborted, true);
  });
}

test("fetchBoundedMedia blocks private and non-HTTP URLs before fetching", async () => {
  const f = mediaStreamFixture([]);
  for (const url of ["http://127.0.0.1/media", "http://10.0.0.1/media", "file:///tmp/media", "http://name:secret@93.184.216.34/media"]) {
    assert.equal(await fetchBoundedMedia(url, 4, f.fetcher), undefined);
  }
  assert.equal(f.calls, 0);
});

test("fetchBoundedMedia aborts and unlocks on stream errors", async () => {
  let requestSignal: AbortSignal | undefined;
  const response = new Response(new ReadableStream<Uint8Array>({
    pull(controller) { controller.error(new Error("broken stream")); },
  }, { highWaterMark: 0 }));
  const fetcher: typeof fetch = async (_url, init) => { requestSignal = init?.signal ?? undefined; return response; };
  await assert.rejects(fetchBoundedMedia("https://93.184.216.34/media", 4, fetcher), /broken stream/);
  assert.equal(requestSignal?.aborted, true);
  assert.equal(response.body?.locked, false);
});

test("fetchBoundedMedia timeout cancels a stalled body and aborts the request", async () => {
  let cancelled = false;
  let requestSignal: AbortSignal | undefined;
  const response = new Response(new ReadableStream<Uint8Array>({
    pull() { return new Promise<void>(() => {}); },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 }));
  const fetcher: typeof fetch = async (_url, init) => { requestSignal = init?.signal ?? undefined; return response; };
  await assert.rejects(fetchBoundedMedia("https://93.184.216.34/media", 4, fetcher, 5), { name: "AbortError" });
  assert.equal(cancelled, true);
  assert.equal(requestSignal?.aborted, true);
  assert.equal(response.body?.locked, false);
});

test("fetchBoundedMedia aborts a rejected fetch", async () => {
  let requestSignal: AbortSignal | undefined;
  const fetcher: typeof fetch = async (_url, init) => {
    requestSignal = init?.signal ?? undefined;
    throw new Error("fetch failed");
  };
  await assert.rejects(fetchBoundedMedia("https://93.184.216.34/media", 4, fetcher), /fetch failed/);
  assert.equal(requestSignal?.aborted, true);
});

const receiptSourceURL = "https://93.184.216.34/source";
function receiptDocument(status: "resolved" | "blocked_login" | "expired" | "opaque_unresolved" = "resolved", html = "") {
  return { html, resolution: { originalURL: receiptSourceURL, resolvedURL: receiptSourceURL, redirectChain: [receiptSourceURL], status } };
}
const receiptMediaHTML = '<meta property="og:title" content="Instagram"><meta property="og:image" content="https://93.184.216.34/image"><meta property="og:video" content="https://93.184.216.34/video">';

test("source recovery media option defaults on and false skips fetch and tried markers", async () => {
  for (const includeMediaEvidence of [undefined, false]) {
    let mediaCalls = 0;
    const output = await runSourceSearchRecovery(
      { sourceUrl: receiptSourceURL, maxQueries: 0 }, async () => "",
      async () => { mediaCalls += 1; return [{ kind: "thumbnail", url: "https://93.184.216.34/image", byteLength: 2 }]; },
      { includeMediaEvidence, sourceDocumentResolver: async () => receiptDocument("resolved", receiptMediaHTML) },
    );
    assert.equal(mediaCalls, includeMediaEvidence === false ? 0 : 1);
    assert.equal(output.mediaEvidence.length, mediaCalls);
    assert.equal(output.receipt.tried.includes("public_media_fetch"), includeMediaEvidence !== false);
    assert.equal(output.receipt.tried.includes("server_keyframe_extraction"), includeMediaEvidence !== false);
    assert.deepEqual(output.candidates, []);
    assert.deepEqual(output.receipt.failureReason, { kind: "insufficient_source", reason: "caption_missing" });
  }
});

test("source recovery classifies confirmed inaccessible source separately from provider failures", async () => {
  for (const [status, reason] of [["blocked_login", "login_required"], ["expired", "expired"], ["opaque_unresolved", "unresolved_source"]] as const) {
    const output = await runSourceSearchRecovery(
      { sourceUrl: receiptSourceURL, suggestedSearchQueries: ["fixture"], maxQueries: 1 },
      async () => { throw new Error("private provider failure detail"); }, async () => [],
      { sourceDocumentResolver: async () => receiptDocument(status) },
    );
    assert.deepEqual(output.receipt.failureReason, { kind: "insufficient_source", reason });
    assert.deepEqual(output.candidates, []);
    assert.ok(!JSON.stringify(output.receipt).includes("private provider failure detail"));
  }
});

test("source recovery identifies source media and public search provider failure stages", async () => {
  for (const stage of ["source", "media", "public_search"] as const) {
    const output = await runSourceSearchRecovery(
      { sourceUrl: receiptSourceURL, suggestedSearchQueries: ["fixture"], maxQueries: stage === "public_search" ? 1 : 0 },
      async () => { throw new Error("private failure"); },
      async () => { throw new Error("private failure"); },
      { sourceDocumentResolver: async () => {
        if (stage === "source") throw new Error("private failure");
        return receiptDocument("resolved", stage === "media" ? receiptMediaHTML : "");
      } },
    );
    assert.deepEqual(output.receipt.failureReason, { kind: "provider_failure", stage });
    assert.deepEqual(output.candidates, []);
    assert.ok(!JSON.stringify(output.receipt).includes("private failure"));
  }
});

test("source recovery preserves successful candidates despite media failure without failure receipt", async () => {
  const output = await runSourceSearchRecovery(
    { sourceUrl: receiptSourceURL, maxQueries: 0 }, async () => "",
    async () => { throw new Error("private media error"); },
    { sourceDocumentResolver: async () => receiptDocument("resolved", receiptMediaHTML + '<meta property="og:description" content="📍小山咖啡 北區店">'),
      placesCorroborator: async () => undefined,
      rubricEvaluator: () => ({ confidenceReason: "fixture", evidenceTier: "weak", missingInfo: [] }),
    },
  );
  assert.equal(output.candidates.length, 1);
  assert.equal(output.candidates[0].name, "小山咖啡 北區店");
  assert.equal(output.candidates[0].latitude, undefined);
  assert.equal(output.receipt.failureReason, undefined);
  assert.ok(!JSON.stringify(output.candidates).includes("private media error"));
});

test("source recovery with readable but non-place text is insufficient evidence", async () => {
  const output = await runSourceSearchRecovery({ rawText: "A lovely day outside", maxQueries: 0 }, async () => "", async () => []);
  assert.deepEqual(output.candidates, []);
  assert.deepEqual(output.receipt.failureReason, { kind: "insufficient_source", reason: "no_place_evidence" });
});


test("Places provider semantic failures remain retryable and zero results are valid", async () => {
  const originalFetch=globalThis.fetch, originalKey=process.env.GOOGLE_PLACES_API_KEY;
  process.env.GOOGLE_PLACES_API_KEY="synthetic";
  const candidate={name:"Fixture Cafe",address:"123 Main Street",evidence:[],confidence:0.5,missingInfo:[]};
  try {
    for(const body of [JSON.stringify({status:"REQUEST_DENIED",results:[]}),JSON.stringify({status:"OVER_QUERY_LIMIT",results:[]}),"malformed"]) {
      globalThis.fetch=async()=>new Response(body,{status:200});
      await assert.rejects(defaultPlacesCorroborator(candidate));
    }
    globalThis.fetch=async()=>Response.json({status:"ZERO_RESULTS",results:[]});
    assert.equal(await defaultPlacesCorroborator(candidate),undefined);
    globalThis.fetch=async()=>new Response("denied",{status:400});
    await assert.rejects(defaultPlacesCorroborator(candidate));
  } finally {
    globalThis.fetch=originalFetch;
    if(originalKey===undefined) delete process.env.GOOGLE_PLACES_API_KEY;else process.env.GOOGLE_PLACES_API_KEY=originalKey;
  }
});

function workerLedger(denied = false) {
  const events: string[] = [];
  const store = {
    async reserve(_owner: string, _id: string, input: { operation: string }) {
      events.push(`reserve:${input.operation}`);
      if (denied) throw new AnalysisControlError(429, "analysis_limit_exceeded", "fixture denial");
      return "event";
    },
    async settle(_owner: string, _id: string, _event: string, _input: unknown, outcome: string) { events.push(outcome); },
  } as unknown as AnalysisUsageStore;
  return { events, run: <T>(work: () => Promise<T>) => withAnalysisUsage(store, "owner", "analysis", work) };
}
function ledgerBody(events: string[], fail = false) {
  return new Response(new ReadableStream<Uint8Array>({
    pull(controller) {
      events.push("read");
      if (fail) controller.error(new Error("fixture body failed"));
      else { controller.enqueue(new TextEncoder().encode("fixture")); controller.close(); }
    },
  }, { highWaterMark: 0 }));
}

for (const fail of [true, false]) {
  test(`worker ledger settles public search after body ${fail ? "failure" : "success"}`, async () => {
    const ledger = workerLedger(); const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => { ledger.events.push("fetch"); return ledgerBody(ledger.events, fail); };
    try {
      const result = ledger.run(() => defaultFetchText("https://93.184.216.34/search"));
      if (fail) await assert.rejects(result, /fixture body failed/); else assert.equal(await result, "fixture");
      assert.deepEqual(ledger.events, ["reserve:public_search", "fetch", "read", fail ? "failure" : "success"]);
    } finally { globalThis.fetch = originalFetch; }
  });
}

test("worker ledger marks announced public search size rejection as failure", async () => {
  const ledger = workerLedger(); const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { ledger.events.push("fetch"); return new Response("fixture", { headers: { "content-length": "1000001" } }); };
  try {
    await assert.rejects(ledger.run(() => defaultFetchText("https://93.184.216.34/search")), /too large/);
    assert.deepEqual(ledger.events, ["reserve:public_search", "fetch", "failure"]);
  } finally { globalThis.fetch = originalFetch; }
});

for (const mode of ["read_error", "oversize", "success"] as const) {
  test(`worker ledger settles media ${mode} after reading`, async () => {
    const ledger = workerLedger();
    const fetcher: typeof fetch = async () => { ledger.events.push("fetch"); return ledgerBody(ledger.events, mode === "read_error"); };
    const result = ledger.run(() => fetchBoundedMedia("https://93.184.216.34/media", mode === "oversize" ? 2 : 10, fetcher));
    if (mode === "read_error") await assert.rejects(result, /fixture body failed/);
    else if (mode === "oversize") assert.equal(await result, undefined); else assert.equal((await result)?.data.byteLength, 7);
    assert.deepEqual(ledger.events, ["reserve:media_download", "fetch", "read", mode === "success" ? "success" : "failure"]);
  });
}

test("worker ledger records one operation for each validated metadata redirect attempt", async () => {
  const ledger = workerLedger(); let calls = 0;
  const fetcher: typeof fetch = async () => {
    ledger.events.push("fetch");
    return calls++ === 0 ? new Response(null, { status: 302, headers: { location: "https://93.184.216.34/ledger-target" } }) : ledgerBody(ledger.events, true);
  };
  await assert.rejects(ledger.run(() => resolveSourceDocument("https://93.184.216.34/ledger-redirect", 100, fetcher)), /fixture body failed/);
  assert.deepEqual(ledger.events, ["reserve:metadata", "fetch", "success", "reserve:metadata", "fetch", "read", "failure"]);
});

test("worker ledger treats readable login and expired pages as valid retrievals", async () => {
  for (const status of [401, 404]) {
    const ledger = workerLedger();
    const fetcher: typeof fetch = async () => { ledger.events.push("fetch"); return new Response("unavailable", { status }); };
    const result = await ledger.run(() => resolveSourceDocument(`https://93.184.216.34/ledger-${status}`, 100, fetcher));
    assert.equal(result.resolution.status, status === 401 ? "blocked_login" : "expired");
    assert.deepEqual(ledger.events, ["reserve:metadata", "fetch", "success"]);
  }
});

test("worker ledger rejects metadata truncated before a usable head", async () => {
  const ledger = workerLedger();
  const fetcher: typeof fetch = async () => { ledger.events.push("fetch"); return new Response("x".repeat(101)); };
  await assert.rejects(ledger.run(() => resolveSourceDocument("https://93.184.216.34/ledger-large", 100, fetcher)), /too large/);
  assert.deepEqual(ledger.events, ["reserve:metadata", "fetch", "failure"]);
});

for (const responseBody of ["malformed JSON", JSON.stringify({ evidence_tier: "unknown", confidence_reason: "fixture" })]) {
  test(`worker ledger marks malformed rubric ${responseBody.startsWith("{") ? "verdict" : "JSON"} as failure while retaining fallback`, async () => {
    const ledger = workerLedger(); const originalFetch = globalThis.fetch; const oldURL = process.env.SAVE_EVIDENCE_RUBRIC_URL;
    process.env.SAVE_EVIDENCE_RUBRIC_URL = "https://93.184.216.34/rubric";
    globalThis.fetch = async () => { ledger.events.push("fetch"); return new Response(responseBody); };
    try {
      const output = await ledger.run(() => runSourceSearchRecovery({ sourceUrl: receiptSourceURL, maxQueries: 0 }, async () => "", async () => [], {
        sourceDocumentResolver: async () => receiptDocument("resolved", '<meta property="og:description" content="📍小山咖啡 北區店">'),
        placesCorroborator: async () => undefined,
      }));
      assert.equal(output.candidates.length, 1);
      assert.deepEqual(ledger.events, ["reserve:rubric", "fetch", "failure"]);
    } finally {
      globalThis.fetch = originalFetch;
      if (oldURL === undefined) delete process.env.SAVE_EVIDENCE_RUBRIC_URL; else process.env.SAVE_EVIDENCE_RUBRIC_URL = oldURL;
    }
  });
}

test("worker ledger does not fetch or swallow admission denial", async () => {
  const ledger = workerLedger(true);
  await assert.rejects(ledger.run(() => fetchBoundedMedia("https://93.184.216.34/media", 10, async () => { throw new Error("must not fetch"); })), { code: "analysis_limit_exceeded" });
  assert.deepEqual(ledger.events, ["reserve:media_download"]);
});

test("worker ledger records a media body timeout as cancelled after fetch", async () => {
  const ledger = workerLedger();
  const fetcher: typeof fetch = async () => {
    ledger.events.push("fetch");
    return new Response(new ReadableStream<Uint8Array>({ pull() { return new Promise<void>(() => {}); } }, { highWaterMark: 0 }));
  };
  await assert.rejects(ledger.run(() => fetchBoundedMedia("https://93.184.216.34/timeout", 10, fetcher, 5)), { name: "AbortError" });
  assert.deepEqual(ledger.events, ["reserve:media_download", "fetch", "cancelled"]);
});

test("worker ledger does not swallow rubric admission denial in the fallback", async () => {
  const ledger = workerLedger(true); const originalFetch = globalThis.fetch; const oldURL = process.env.SAVE_EVIDENCE_RUBRIC_URL;
  process.env.SAVE_EVIDENCE_RUBRIC_URL = "https://93.184.216.34/rubric";
  globalThis.fetch = async () => { ledger.events.push("fetch"); throw new Error("must not fetch"); };
  try {
    await assert.rejects(ledger.run(() => runSourceSearchRecovery({ sourceUrl: receiptSourceURL, maxQueries: 0 }, async () => "", async () => [], {
      sourceDocumentResolver: async () => receiptDocument("resolved", '<meta property="og:description" content="📍小山咖啡 北區店">'),
      placesCorroborator: async () => undefined,
    })), { code: "analysis_limit_exceeded" });
    assert.deepEqual(ledger.events, ["reserve:rubric"]);
  } finally {
    globalThis.fetch = originalFetch;
    if (oldURL === undefined) delete process.env.SAVE_EVIDENCE_RUBRIC_URL; else process.env.SAVE_EVIDENCE_RUBRIC_URL = oldURL;
  }
});


test("metadata headless body accepts the exact byte limit and rejects only actual overflow", async () => {
  for (const overflow of [false, true]) {
    const ledger = workerLedger();
    let reads = 0;
    const fetcher: typeof fetch = async () => {
      ledger.events.push("fetch");
      return new Response(new ReadableStream<Uint8Array>({
        pull(controller) {
          if (reads++ === 0) controller.enqueue(new TextEncoder().encode("fixture"));
          else if (overflow && reads === 2) controller.enqueue(Uint8Array.of(120));
          else controller.close();
        },
      }, { highWaterMark: 0 }));
    };
    const result = ledger.run(() => resolveSourceDocument(`https://93.184.216.34/exact-headless-${overflow}`, 7, fetcher));
    if (overflow) await assert.rejects(result, /too large/);
    else assert.equal((await result).html, "fixture");
    assert.equal(reads, 2, "read EOF or the first overflowing chunk before settling");
    assert.deepEqual(ledger.events, ["reserve:metadata", "fetch", overflow ? "failure" : "success"]);
  }
});

const reportedReelMetadata = `<html><head>
<meta name="twitter:title" content="Wendy三分熟 (@wendyismediumrare) • Instagram reel">
<meta property="og:title" content="Wendy三分熟 on Instagram: &quot;日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃 #台北牛肉麵推薦&quot;">
<meta property="og:description" content="177 likes, 2 comments - wendyismediumrare on August 21, 2026: &quot;日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃 #台北牛肉麵推薦&quot;">
</head></html>`;

test("reported Reel uses its caption within four recovery searches without inventing a venue", async () => {
  const seen: string[] = [];
  const output = await runSourceSearchRecovery(
    { sourceUrl: "https://www.instagram.com/reel/DcTZXFrjfJG/?stkn=tracking" },
    async url => {
      if (url.includes("instagram.com")) return reportedReelMetadata;
      seen.push(new URL(url).searchParams.get("q") ?? "");
      return "";
    },
    async () => [],
  );
  assert.match(output.sourceResolution?.title ?? "", /日本人挑戰開牛肉麵店/);
  assert.ok(seen.some(query => query.includes("日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃") && !query.includes("Wendy")));
  assert.equal(seen.length, 4);
  assert.deepEqual(output.candidates, []);
  assert.equal(output.receipt.output, "source_only_clue");
});

test("caption recovery preserves caller search priority and the requested query cap", async () => {
  const output = await runSourceSearchRecovery(
    { sourceUrl: "https://www.instagram.com/reel/DcTZXFrjfJG/", suggestedSearchQueries: ["user supplied venue address"], maxQueries: 1 },
    async url => url.includes("instagram.com") ? reportedReelMetadata : "",
    async () => [],
  );
  assert.deepEqual(output.queries, ["user supplied venue address"]);
});

test("creator-only or hashtag-only titles do not create caption recovery queries", async () => {
  for (const title of ["Wendy (@wendyismediumrare) • Instagram reel", "Wendy on Instagram: &quot;#台北牛肉麵推薦 #中山區美食&quot;"]) {
    const output = await runSourceSearchRecovery(
      { sourceUrl: "https://www.instagram.com/reel/DcTZXFrjfJG/" },
      async url => url.includes("instagram.com") ? `<meta property="og:title" content="${title}">` : "",
      async () => [],
    );
    assert.equal(output.queries[0], "instagram reel DcTZXFrjfJG place");
    assert.deepEqual(output.candidates, []);
  }
});


test("public recovery uses the direct HTML endpoint without requiring redirects", async () => {
  let requestURL: URL | undefined;
  await searchPublicWebResults('"DcTZXFrjfJG"', async url => { requestURL = new URL(url); return ""; });
  assert.equal(requestURL?.origin, "https://html.duckduckgo.com");
  assert.equal(requestURL?.pathname, "/html/");
  assert.equal(requestURL?.searchParams.get("q"), '"DcTZXFrjfJG"');
});

test("retry of a persisted Reel recovers caption even when the old title was creator-only", async () => {
  const url = "https://www.instagram.com/reel/DcTZXFrjfJG/";
  const output = await runSourceSearchRecovery(
    { sourceUrl: url }, async () => "", async () => [],
    { persistedSourceResolution: {
      original_url: url, resolved_url: url, redirect_chain: [url], status: "resolved",
      title: "Wendy三分熟 (@wendyismediumrare) • Instagram reel",
      caption: '177 likes, 2 comments - wendyismediumrare on August 21, 2026: "日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃 #台北牛肉麵推薦".',
    } },
  );
  assert.equal(output.queries[0], '"日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃" place');
  assert.deepEqual(output.candidates, []);
});

test("video fallback upgrades the reported source-only Reel from its late storefront frame", async () => {
  const sourceUrl = "https://www.instagram.com/reel/DcTZXFrjfJG/";
  let videoCalls = 0;
  const output = await runSourceSearchRecovery({ sourceUrl },
    async url => url.includes("instagram.com") ? reportedReelMetadata : "", async () => [], {
      videoVenueRecovery: async url => {
        assert.equal(url, sourceUrl); videoCalls += 1;
        return [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24 }];
      },
      placesCorroborator: async candidate => {
        assert.equal(candidate.name, "江牛樓");
        return { name: "江牛樓", address: "臺北市大同區民樂街6號", latitude: 25.054, longitude: 121.51 };
      },
      rubricEvaluator: () => ({ confidenceReason: "Test fixture corroboration", evidenceTier: "corroborated", missingInfo: ["User confirmation"] }),
    });
  assert.equal(videoCalls, 1);
  assert.equal(output.candidates[0]?.name, "江牛樓");
  assert.ok(output.candidates[0]?.evidence.includes("Video frame at 24s: 江牛樓"));
  assert.ok(output.candidates[0]?.missingInfo.some(item => /User confirmation/.test(item)));
  assert.equal(output.receipt.output, "review_candidate");
  assert.equal(output.mediaEvidence[0]?.textSource, "vision");
});

test("video fallback uses the resolved Reel URL when the stored source is a share route", async () => {
  const shareUrl = "https://www.instagram.com/share/reel/ShareCode/";
  const resolvedUrl = "https://www.instagram.com/reel/DcTZXFrjfJG/";
  let videoCalls = 0;
  const output = await runSourceSearchRecovery(
    { sourceUrl: shareUrl },
    async () => "",
    async () => [],
    {
      persistedSourceResolution: {
        original_url: shareUrl,
        resolved_url: resolvedUrl,
        redirect_chain: [shareUrl, resolvedUrl],
        status: "resolved",
        title: "Wendy三分熟 (@wendyismediumrare) • Instagram reel",
        caption: '177 likes, 2 comments - wendyismediumrare on August 21, 2026: "日本人挑戰開牛肉麵店 榮獲米其林推薦 必吃 #台北牛肉麵推薦".',
      },
      videoVenueRecovery: async url => {
        assert.equal(url, resolvedUrl);
        videoCalls += 1;
        return [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24 }];
      },
      placesCorroborator: async candidate => {
        assert.equal(candidate.name, "江牛樓");
        return { name: "江牛樓", address: "臺北市大同區民樂街6號", latitude: 25.054, longitude: 121.51 };
      },
      rubricEvaluator: () => ({ confidenceReason: "Test fixture corroboration", evidenceTier: "corroborated", missingInfo: ["User confirmation"] }),
    },
  );
  assert.equal(videoCalls, 1);
  assert.equal(output.candidates[0]?.name, "江牛樓");
  assert.ok(output.candidates[0]?.evidence.includes(`Source video: ${resolvedUrl}`));
  assert.ok(!output.candidates[0]?.evidence.some(item => item.includes("/share/reel/")));
  assert.equal(output.mediaEvidence[0]?.url, resolvedUrl);
  assert.equal(output.mediaEvidence[0]?.kind, "video_keyframe");
  assert.equal(output.mediaEvidence[0]?.textSource, "vision");
  assert.equal(output.receipt.output, "review_candidate");
});

test("video fallback does no work when media is disabled or metadata already names a venue", async () => {
  for (const includeMediaEvidence of [false, true]) {
    let calls = 0;
    await runSourceSearchRecovery({sourceUrl: "https://www.instagram.com/reel/AlreadyNamed/"},
      async url => url.includes("instagram.com")
        ? '<meta property="og:description" content="店名：江牛樓 地址：台北市大同區民樂街6號">' : "",
      async () => [], {
        includeMediaEvidence,
        videoVenueRecovery: async () => { calls += 1; return []; },
        placesCorroborator: async () => undefined,
        rubricEvaluator: () => ({ confidenceReason: "Source", evidenceTier: "weak", missingInfo: ["User confirmation"] }),
      });
    assert.equal(calls, 0);
  }
});

test("video provider failure preserves clue and does not swallow quota denial", async () => {
  const input = {sourceUrl: "https://www.instagram.com/reel/DcTZXFrjfJG/"};
  const options = {videoVenueRecovery: async (): Promise<never> => { throw new Error("private upstream detail"); }};
  const output = await runSourceSearchRecovery(input, async () => "", async () => [], options);
  assert.equal(output.receipt.output, "source_only_clue");
  assert.deepEqual(output.receipt.failureReason, {kind:"provider_failure",stage:"media"});
  assert.ok(!JSON.stringify(output).includes("private upstream detail"));
  const denied = new AnalysisControlError(429,"analysis_budget_exceeded","Budget exceeded");
  await assert.rejects(runSourceSearchRecovery(input, async () => "", async () => [], {
    videoVenueRecovery: async () => { throw denied; },
  }), error => error === denied);
});

test("source-only media opt-out never invokes video recovery", async () => {
  let calls = 0;
  const output = await runSourceSearchRecovery(
    { sourceUrl: "https://www.instagram.com/reel/DcTZXFrjfJG/" },
    async () => "", async () => [], {
      includeMediaEvidence: false,
      videoVenueRecovery: async () => { calls += 1; return []; },
    },
  );
  assert.equal(output.receipt.output, "source_only_clue");
  assert.equal(calls, 0);
});
