import assert from "node:assert/strict";
import test from "node:test";
import {
  buildSourceRecoveryQueries,
  candidatesFromSearchResults,
  parseDuckDuckGoResults,
  runSourceSearchRecovery,
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
