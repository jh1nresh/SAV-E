import assert from "node:assert/strict";
import test from "node:test";
import { runSourceSearchRecovery, semanticRecoveryCandidates, sourceMetadataFromHTML, defaultFetchMetadataHTML } from "./sourceSearchWorker.js";
import { AnalysisControlError } from "./analysisUsage.js";
import type { SemanticAnalysisResult } from "./socialSemanticExtraction.js";
const caption = "商業午餐\n火山排骨\n📍初泰Pikul  信義象山門市\n📍臺北市信義區信義路五段122號\n (近捷運象山站2號出口)";
const field = (value: string) => ({ value, quote: value, source: "caption" as const });
const extracted: SemanticAnalysisResult = { status: "ready", venues: [{ name: field("初泰Pikul"), branch: field("信義象山門市"), address: field("臺北市信義區信義路五段122號"), transport: field("近捷運象山站2號出口"), mapStatus: "unverified", matches: [] }] };
const input = { sourceUrl: "https://www.instagram.com/p/fixture/", rawText: caption };
const noPublicSearch = async (url: string) => { assert.ok(url.includes("instagram.com"), "must not use regex/public search as venue fallback"); return ""; };
test("complete social caption reaches semantic analysis before any media or regex recovery", async () => {
  const result = await runSourceSearchRecovery(input, noPublicSearch, async () => { throw new Error("unexpected OCR"); }, {
    semanticAnalyzer: async value => { assert.equal(value.caption, caption); assert.equal(value.ocrText, undefined); return structuredClone(extracted); },
    videoVenueRecovery: async () => { throw new Error("unexpected video"); },
  });
  assert.equal(result.candidates.length, 1);
  assert.equal(result.candidates[0].name, "初泰Pikul 信義象山門市");
  assert.equal(result.candidates[0].latitude, undefined);
  assert.deepEqual(result.queries, []);
  assert.ok(result.candidates[0].evidence.some(line => line.includes("近捷運象山站2號出口")));
});
test("AI outage preserves source, never regex guesses or unnecessary media", async () => {
  let calls = 0;
  const result = await runSourceSearchRecovery(input, noPublicSearch, async () => { calls++; return []; }, {
    semanticAnalyzer: async () => ({ status: "analysis_pending", venues: [] }),
  });
  assert.equal(calls, 0); assert.deepEqual(result.candidates, []); assert.deepEqual(result.searchResults, []);
  assert.equal(result.receipt.output, "source_only_clue"); assert.match(result.receipt.nextBestClue, /pending/);
  assert.ok(result.errors.length > 0, "failed analysis cannot be cached as successful");
});
test("OCR supplements insufficient text through same analyzer; failures preserve earlier extraction", async () => {
  let calls = 0; const partial = structuredClone(extracted); partial.venues[0].address = null;
  const result = await runSourceSearchRecovery(input,
    async () => '<meta property="og:image" content="https://example.com/cover.jpg">',
    async metadata => { assert.equal(metadata.videoURL, undefined); return [{ kind: "thumbnail", url: metadata.imageURL!, text: "visible address", textSource: "ocr" }]; }, {
      semanticAnalyzer: async value => { if (++calls === 1) return partial; assert.equal(value.ocrText, "visible address"); return { status: "analysis_pending", venues: [] }; },
    });
  assert.equal(calls, 2); assert.equal(result.candidates[0].name, "初泰Pikul 信義象山門市"); assert.equal(result.candidates[0].latitude, undefined);
});
test("ambiguous Maps alternatives stay separate and conflicts retain source identity", () => {
  const result = structuredClone(extracted); result.venues[0].mapStatus = "ambiguous";
  result.venues[0].matches = ["A", "B"].map(id => ({ id, name: `初泰Pikul ${id}`, address: `地址${id}`, latitude: 25, longitude: 121 }));
  const candidates = semanticRecoveryCandidates(result);
  assert.deepEqual(candidates.map(row => row.placeId), ["A", "B"]);
  assert.ok(candidates.every(row => row.missingInfo.includes("Choose the correct map candidate")));
  result.venues[0].mapStatus = "conflict";
  const conflict = semanticRecoveryCandidates(result)[0]; assert.equal(conflict.name, "初泰Pikul 信義象山門市"); assert.equal(conflict.latitude, undefined);
  assert.ok(conflict.evidence.some(line => line.includes("地址B")));
});
test("budget controls cannot fall through to heuristics", async () => {
  await assert.rejects(runSourceSearchRecovery(input, noPublicSearch, async () => [], {
    semanticAnalyzer: async () => { throw new AnalysisControlError(429, "analysis_budget", "budget exhausted"); },
  }), AnalysisControlError);
});
test("full embedded caption wins over teaser with paragraph boundaries intact", () => {
  const full = "開始\n" + "上下文。".repeat(650) + "\n" + caption + "\n結尾";
  assert.equal(sourceMetadataFromHTML(`<meta property="og:description" content="teaser"><script>{"caption":{"text":${JSON.stringify(full)}}}</script>`).description, full);
});

test("oversized social documents fail instead of analyzing a silently clipped caption", async () => {
  await assert.rejects(defaultFetchMetadataHTML("https://www.instagram.com/p/oversize-semantic/", 1000,
    async () => new Response('<head><meta property="og:description" content="teaser"></head>' + "x".repeat(2000))), /Response too large/);
});
