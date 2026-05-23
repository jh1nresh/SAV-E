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
});
