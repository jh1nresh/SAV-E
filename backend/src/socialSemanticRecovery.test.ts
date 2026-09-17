import assert from "node:assert/strict";
import test from "node:test";
import { runSourceSearchRecovery, semanticRecoveryCandidates, sourceMetadataFromHTML, defaultFetchMetadataHTML } from "./sourceSearchWorker.js";
import { AnalysisControlError } from "./analysisUsage.js";
import { analyzeSocialCaption, type SemanticAnalysisResult } from "./socialSemanticExtraction.js";
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
  assert.equal(result.candidates[0].evidence[0], `Source URL: ${input.sourceUrl}`);
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
  const candidates = semanticRecoveryCandidates(result, input.sourceUrl);
  assert.deepEqual(candidates.map(row => row.placeId), ["A", "B"]);
  assert.ok(candidates.every(row => row.evidence[0] === `Source URL: ${input.sourceUrl}`));
  assert.ok(candidates.every(row => row.missingInfo.includes("Choose the correct map candidate")));
  result.venues[0].mapStatus = "conflict";
  const conflict = semanticRecoveryCandidates(result, input.sourceUrl)[0]; assert.equal(conflict.name, "初泰Pikul 信義象山門市"); assert.equal(conflict.latitude, undefined);
  assert.ok(conflict.evidence.some(line => line.includes("地址B")));
  assert.equal(conflict.evidence[0], `Source URL: ${input.sourceUrl}`);
});
test("budget controls cannot fall through to heuristics", async () => {
  await assert.rejects(runSourceSearchRecovery(input, noPublicSearch, async () => [], {
    semanticAnalyzer: async () => { throw new AnalysisControlError(429, "analysis_budget", "budget exhausted"); },
  }), AnalysisControlError);
});
test("full embedded caption wins over teaser with paragraph boundaries intact", () => {
  const full = "開始\n" + "上下文。".repeat(650) + "\n" + caption + "\n結尾";
  assert.equal(sourceMetadataFromHTML(`<meta property="og:description" content="teaser"><script>{"shortcode":"fixture","caption":{"text":${JSON.stringify(full)}}}</script>`, input.sourceUrl).description, full);
});

test("oversized social documents preserve only a complete bounded metadata head", async () => {
  const head = '<head><meta property="og:description" content="Fixture Cafe&#10;1 Main Street"></head>';
  const html = await defaultFetchMetadataHTML("https://www.instagram.com/p/oversize-semantic-head/", 1000,
    async () => new Response(head + '<script>{"caption":"incomplete' + "x".repeat(2000), { headers: { "content-length": "5000" } }));
  assert.equal(html, head, "partial body caption must never become evidence");
  assert.equal(sourceMetadataFromHTML(html, input.sourceUrl).description, "Fixture Cafe\n1 Main Street");
  await assert.rejects(defaultFetchMetadataHTML("https://www.instagram.com/p/oversize-semantic-no-head/", 1000,
    async () => new Response('<head><meta property="og:description" content="' + "x".repeat(2000))), /Response too large/);
});

test("queued Threads sources use semantic recovery and cannot fall back to venue guesses", async () => {
  for (const host of ["www.threads.net", "www.threads.com"]) {
    let calls = 0;
    const result = await runSourceSearchRecovery({ ...input, sourceUrl: `https://${host}/@savvy/post/fixture` },
      async () => "", async () => { throw new Error("no OCR during outage"); }, {
        semanticAnalyzer: async value => { calls++; assert.equal(value.caption, caption); return { status: "analysis_pending", venues: [] }; },
      });
    assert.equal(calls, 1); assert.deepEqual(result.candidates, []); assert.deepEqual(result.queries, []);
  }
});

test("generated capture titles and legacy unscoped captions are not original evidence", async () => {
  let fetched = 0;
  await runSourceSearchRecovery({ ...input, title: "Earlier guessed restaurant" }, async () => { fetched++; return ""; }, async () => [], {
    persistedSourceResolution: { original_url: input.sourceUrl, resolved_url: input.sourceUrl, redirect_chain: [input.sourceUrl], status: "resolved", caption: "Earlier unrelated embedded caption" },
    semanticAnalyzer: async value => { assert.equal(value.caption, caption); return structuredClone(extracted); },
  });
  assert.equal(fetched, 1);
});

test("embedded captions must belong to the requested social post", () => {
  const item = (id: string, text: string) => ({ shortcode: id, caption: { text } });
  const html = `<meta property="og:description" content="page description"><script>${JSON.stringify({ recommendations: [item("other", "Unrelated venue")], target: item("fixture", caption) })}</script>`;
  assert.equal(sourceMetadataFromHTML(html, input.sourceUrl).description, caption);
  assert.equal(sourceMetadataFromHTML(html, "https://example.com/post/fixture").description, "page description");
  assert.equal(sourceMetadataFromHTML(html, "https://instagram.com/p/missing/").description, "page description");
  const conflicting = `<meta property="og:description" content="page description"><script>${JSON.stringify([item("fixture", caption), item("fixture", "Conflicting caption")])}</script>`;
  assert.equal(sourceMetadataFromHTML(conflicting, input.sourceUrl).description, "page description");
  const unknown = '<meta property="og:description" content="page description"><script>{"caption":{"text":"Unbound venue"}}</script>';
  assert.equal(sourceMetadataFromHTML(unknown, input.sourceUrl).description, "page description");
});


test("OCR empty or omitted venues cannot erase a grounded caption candidate", async () => {
  const partial = structuredClone(extracted); partial.venues[0].address = null;
  for (const next of [{ status: "no_place_evidence" as const, venues: [] }, { status: "ready" as const, venues: [] }, extracted]) {
    let calls = 0;
    const result = await runSourceSearchRecovery(input,
      async () => '<meta property="og:image" content="https://example.com/cover.jpg">',
      async metadata => [{ kind: "thumbnail", url: metadata.imageURL!, text: "visible address", textSource: "ocr" }], {
        semanticAnalyzer: async () => ++calls === 1 ? partial : structuredClone(next),
        videoVenueRecovery: async () => { throw new Error("existing caption venue must prevent video recovery"); },
      });
    assert.equal(calls, 2); assert.equal(result.candidates[0].name, "初泰Pikul 信義象山門市");
    assert.equal(result.candidates[0].latitude, undefined);
    if (next === extracted) assert.equal(result.candidates[0].address, "臺北市信義區信義路五段122號");
  }
});

test("a unique name match without a source address never becomes a coordinate candidate", async () => {
  const original = structuredClone(extracted); original.venues[0].address = null;
  const { mapStatus, matches, ...fields } = original.venues[0];
  const result = await analyzeSocialCaption({ caption }, {
    extract: async () => ({ venues: [fields] }),
    search: async () => ["初泰Pikul 信義象山門市", "Unrelated venue"].map((name, i) => ({ id: String(i), name, address: "Provider address", latitude: 25, longitude: 121 })),
  });
  const candidate = semanticRecoveryCandidates(result, input.sourceUrl)[0];
  assert.equal(candidate.latitude, undefined); assert.equal(candidate.longitude, undefined);
  assert.equal(candidate.name, "初泰Pikul 信義象山門市");
});


test("legacy merged raw text is excluded when persisted source provenance is absent", async () => {
  const result = await runSourceSearchRecovery({ ...input, rawText: "Generated guess", semanticSourceText: null },
    async () => '<meta property="og:description" content="Actual original caption">', async () => [], {
      semanticAnalyzer: async value => { assert.equal(value.caption, "Actual original caption"); return { status: "no_place_evidence", venues: [] }; },
      videoVenueRecovery: async () => [],
    });
  assert.equal(result.semanticStatus, "no_place_evidence"); assert.deepEqual(result.errors, []);
  assert.deepEqual(result.candidates, []); assert.ok(!result.receipt.missing.includes("Analysis pending"));
});


test("Google identity and types propagate only from matched or ambiguous provider alternatives", () => {
  for (const status of ["matched", "ambiguous", "unverified", "conflict"] as const) {
    const result = structuredClone(extracted); result.venues[0].mapStatus = status;
    result.venues[0].matches = [{ id: "real-google-id", name: "初泰Pikul 信義象山門市", address: "臺北市信義區信義路五段122號",
      latitude: 25, longitude: 121, types: ["restaurant", "food"] }];
    const candidate = semanticRecoveryCandidates(result, input.sourceUrl)[0];
    assert.equal(candidate.evidence[0], `Source URL: ${input.sourceUrl}`);
    if (status === "matched" || status === "ambiguous") {
      assert.equal(candidate.placeId, "real-google-id"); assert.deepEqual(candidate.types, ["restaurant", "food"]);
      assert.equal(candidate.latitude, 25); assert.equal(candidate.longitude, 121);
    } else {
      assert.equal(candidate.placeId, undefined); assert.equal(candidate.types, undefined);
      assert.equal(candidate.latitude, undefined); assert.equal(candidate.longitude, undefined);
    }
  }
});

test("HTML metadata entities are decoded before grounding without changing JSON caption text", async () => {
  const html = '<meta property="og:title" content="A&amp;W"><meta property="og:description" content="Joe&#39;s&#10;1 Main Street&#10;A&amp;W">';
  const metadata = sourceMetadataFromHTML(html, input.sourceUrl);
  assert.equal(metadata.title, "A&W"); assert.equal(metadata.description, "Joe's\n1 Main Street\nA&W");
  await runSourceSearchRecovery({ sourceUrl: input.sourceUrl }, async () => html, async () => [], {
    semanticAnalyzer: async value => {
      assert.ok(value.caption.includes("Joe's\n1 Main Street\nA&W"));
      return { status: "no_place_evidence", venues: [] };
    }, includeMediaEvidence: false,
  });
  const literal = 'Literal &amp;W';
  assert.equal(sourceMetadataFromHTML(html + `<script>{"shortcode":"fixture","caption":{"text":${JSON.stringify(literal)}}}</script>`, input.sourceUrl).description, literal);
  assert.equal(sourceMetadataFromHTML('<meta property="og:description" content="Joe&#99999999;s">').description, "Joe\uFFFDs");
});

test("unavailable URL-only sources stay pending with their source failure and no empty semantic calls", async () => {
  for (const [status, reason] of [["blocked_login", "login_required"], ["expired", "expired"], ["opaque_unresolved", "unresolved_source"], ["resolved", "caption_missing"]] as const) {
    const result = await runSourceSearchRecovery({ sourceUrl: input.sourceUrl, rawText: input.sourceUrl }, noPublicSearch, async () => [], {
      sourceDocumentResolver: async () => ({ html: "", resolution: { originalURL: input.sourceUrl, resolvedURL: input.sourceUrl, redirectChain: [input.sourceUrl], status } }),
      semanticAnalyzer: async () => { throw new Error("Empty unavailable text must not be reported as analyzed"); },
      videoVenueRecovery: async () => [],
    });
    assert.equal(result.semanticStatus, "analysis_pending"); assert.ok(result.errors.length);
    assert.deepEqual(result.receipt.failureReason, { kind: "insufficient_source", reason });
    assert.deepEqual(result.receipt.tried, []); assert.deepEqual(result.candidates, []);
  }
  const captured = await runSourceSearchRecovery(input, noPublicSearch, async () => [], {
    sourceDocumentResolver: async () => ({ html: "", resolution: { originalURL: input.sourceUrl, resolvedURL: input.sourceUrl, redirectChain: [input.sourceUrl], status: "blocked_login" } }),
    semanticAnalyzer: async value => { assert.equal(value.caption, caption); return structuredClone(extracted); },
  });
  assert.equal(captured.semanticStatus, "ready", "actual captured text remains usable behind a login wall");
});

test("semantic identity survives canonical Maps names and requires explicit source address", () => {
  const result = structuredClone(extracted);
  const source = { name: "初泰Pikul", branch: "信義象山門市", address: "臺北市信義區信義路五段122號" };
  assert.deepEqual(semanticRecoveryCandidates(result, input.sourceUrl)[0].semanticSource, source);
  result.venues[0].mapStatus = "matched";
  result.venues[0].matches = [{ id: "pikul", name: "初泰 信義店", address: "110台灣台北市信義區信義路五段122號", latitude: 25, longitude: 121 }];
  const verified = semanticRecoveryCandidates(result, input.sourceUrl)[0];
  assert.equal(verified.name, "初泰 信義店"); assert.deepEqual(verified.semanticSource, source);
  result.venues[0].address = null;
  assert.equal(semanticRecoveryCandidates(result, input.sourceUrl)[0].semanticSource, undefined);
});

test("source transport outage stays a source provider failure while captured text remains usable", async () => {
  const resolver = async () => { throw new Error("DNS or HTTP outage"); };
  const empty = await runSourceSearchRecovery({ sourceUrl: input.sourceUrl }, noPublicSearch, async () => [], {
    sourceDocumentResolver: resolver,
    semanticAnalyzer: async () => { throw new Error("Empty source must not invoke semantic analysis"); },
  });
  assert.equal(empty.semanticStatus, "analysis_pending"); assert.deepEqual(empty.candidates, []);
  assert.deepEqual(empty.receipt.failureReason, { kind: "provider_failure", stage: "source" });
  const captured = await runSourceSearchRecovery(input, noPublicSearch, async () => [], {
    sourceDocumentResolver: resolver,
    semanticAnalyzer: async value => { assert.equal(value.caption, caption); return structuredClone(extracted); },
  });
  assert.equal(captured.semanticStatus, "ready"); assert.equal(captured.candidates.length, 1);
  assert.equal(captured.receipt.failureReason, undefined);
  assert.deepEqual(captured.errors, [], "nonfatal metadata outage cannot block successful successor persistence");
  const emptyAnalysis = await runSourceSearchRecovery(input, noPublicSearch, async () => [], {
    sourceDocumentResolver: resolver, includeMediaEvidence: false,
    semanticAnalyzer: async () => ({ status: "no_place_evidence", venues: [] }),
  });
  assert.equal(emptyAnalysis.semanticStatus, "no_place_evidence");
  assert.deepEqual(emptyAnalysis.errors, [], "completed empty analysis also clears its own pending marker");
});

test("oversized source recovery retains input failure instead of claiming provider outage", async () => {
  const result = await runSourceSearchRecovery({ ...input, rawText: "x".repeat(20_001) }, async () => "", async () => [], { includeMediaEvidence: false });
  assert.equal(result.semanticStatus, "analysis_pending");
  assert.deepEqual(result.receipt.failureReason, { kind: "insufficient_source", reason: "source_out_of_bounds" });
  assert.deepEqual(result.candidates, []);
  assert.match(result.receipt.nextBestClue!, /shorter/);
});
