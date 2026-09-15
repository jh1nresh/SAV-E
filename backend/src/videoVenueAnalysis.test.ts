import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AnalysisControlError, withAnalysisUsage, type AnalysisUsageStore } from "./analysisUsage.js";
import { recoverInstagramVideoVenues, sampleFrameSeconds, type VideoVenueAnalysisOptions } from "./videoVenueAnalysis.js";

const reel = "https://www.instagram.com/reel/DcTZXFrjfJG/?igsh=ignored";
const mediaURL = "https://video.cdninstagram.com/fixture.mp4?signature=fixture";
const duration = 26.496;
async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), "save-video-test-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const commands: Array<{ file: string; args: string[]; options: { timeout: number; maxBuffer: number } }> = [];
  let metadata: unknown = { formats: [{ url: mediaURL, ext: "mp4", protocol: "https", vcodec: "h264", height: 720 }] };
  let probe: unknown = { format: { duration: String(duration), format_name: "mov,mp4,m4a,3gp,3g2,mj2" }, streams: [{ codec_type: "video", width: 1080, height: 1920 }] };
  let output: unknown = { venues: [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24.84 }] };
  let status = 200; let providerCalls = 0; let mediaCalls = 0; let body: any;
  const options: VideoVenueAnalysisOptions = {
    env: { SAVE_ENABLE_VIDEO_VENUE_ANALYSIS: "true", GEMINI_API_KEY: "fixture-key" }, tempRoot: root,
    execFile: async (file, args, limits) => {
      commands.push({ file, args, options: limits });
      if (file === "yt-dlp") return { stdout: JSON.stringify(metadata) };
      if (file === "ffprobe") return { stdout: JSON.stringify(probe) };
      assert.equal(file, "ffmpeg");
      for (const path of args.filter(arg => arg.endsWith(".jpg"))) await writeFile(path, Buffer.from([255, 216, 1, 255, 217]));
      return { stdout: "" };
    },
    fetch: async (_url, init) => {
      providerCalls++; body = JSON.parse(String(init?.body));
      assert.equal(init?.redirect, "manual"); assert.ok(init?.signal);
      return Response.json({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: typeof output === "string" ? output : JSON.stringify(output) }] } }],
        usageMetadata: { promptTokenCount: 2000, candidatesTokenCount: 30, thoughtsTokenCount: 0, totalTokenCount: 2030 } }, { status });
    },
  };
  const fetchMedia = async (url: string, maxBytes: number) => { mediaCalls++; assert.equal(url, mediaURL); assert.equal(maxBytes, 24_000_000); return { data: Uint8Array.of(1, 2, 3), contentType: "video/mp4" }; };
  return { options, commands, root, fetchMedia, get body() { return body; }, get providerCalls() { return providerCalls; }, get mediaCalls() { return mediaCalls; },
    set metadata(value: unknown) { metadata = value; }, set probe(value: unknown) { probe = value; }, set output(value: unknown) { output = value; }, set status(value: number) { status = value; } };
}

test("frame sampling spans the entire 26.496 second Reel including its storefront near24s", () => {
  const samples = sampleFrameSeconds(duration);
  assert.equal(samples.length, 8); assert.ok(samples[0] < 2); assert.equal(samples[7], 24.84);
  assert.ok(samples.every((time, index) => time >= 0 && time < duration && (!index || time > samples[index - 1])));
  for (const invalid of [0, -1, NaN, Infinity, 90.001]) assert.throws(() => sampleFrameSeconds(invalid));
});

test("observed 江牛樓 storefront fixture survives the injected frames-only pipeline", async t => {
  const f = await fixture(t);
  assert.deepEqual(await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24.84 }]);
  assert.equal(f.providerCalls, 1); assert.equal(f.mediaCalls, 1);
  assert.equal(f.commands.filter(command => command.file === "ffmpeg").length, 1);
  const parts = f.body.contents[0].parts;
  assert.equal(parts.filter((part: any) => part.inlineData?.mimeType === "image/jpeg").length, 8);
  assert.match(JSON.stringify(parts), /24\.840/);
  assert.equal(f.body.generationConfig.maxOutputTokens, 512); assert.equal(f.body.generationConfig.thinkingConfig.thinkingBudget, 0);
  assert.equal(f.body.tools, undefined); assert.ok(!JSON.stringify(f.body).includes(mediaURL));
  assert.deepEqual(await readdir(f.root), []);
});

test("disabled and unsupported sources perform no I/O", async t => {
  const f = await fixture(t); f.options.env = {};
  assert.deepEqual(await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), []);
  f.options.env = { SAVE_ENABLE_VIDEO_VENUE_ANALYSIS: "true", GEMINI_API_KEY: "fixture" };
  for (const source of ["http://instagram.com/reel/abc/", "https://instagram.com.evil.test/reel/abc/", "https://name:pass@instagram.com/reel/abc/", "https://instagram.com:444/reel/abc/", "https://127.0.0.1/reel/abc/", "https://instagram.com/accounts/login", "https://instagram.com/reel/abc/extra", "https://instagram.com/reel/a%2Fb/"]) {
    assert.deepEqual(await recoverInstagramVideoVenues(source, f.fetchMedia, f.options), [], source);
  }
  assert.equal(f.commands.length, 0); assert.equal(f.providerCalls, 0); assert.equal(f.mediaCalls, 0);
});

test("enabled missing key fails closed before extraction", async t => {
  const f = await fixture(t); f.options.env = { SAVE_ENABLE_VIDEO_VENUE_ANALYSIS: "true" };
  await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), /Video venue analysis/);
  assert.equal(f.commands.length, 0);
});

test("commands are anonymous bounded local-only and source query is stripped", async t => {
  const f = await fixture(t); await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options);
  const metadata = f.commands[0]; assert.equal(metadata.file, "yt-dlp");
  for (const flag of ["--ignore-config", "--no-playlist", "--skip-download", "--dump-single-json"]) assert.ok(metadata.args.includes(flag));
  assert.ok(metadata.args.includes("https://www.instagram.com/reel/DcTZXFrjfJG/"));
  assert.ok(!metadata.args.some(arg => arg.includes("ignored") || arg.includes("cookies-from-browser")));
  for (const command of f.commands) { assert.ok(command.options.timeout > 0 && command.options.timeout <= 25_000); assert.ok(command.options.maxBuffer <= 2_000_000); }
  for (const command of f.commands.slice(1)) {
    assert.equal(command.args[command.args.indexOf("-protocol_whitelist") + 1], "file,pipe");
    assert.ok(!command.args.some(arg => arg.startsWith("https:")));
  }
  const frames = f.commands.find(command => command.file === "ffmpeg")!;
  assert.equal(frames.args.filter(arg => arg.endsWith(".jpg")).length, 8);
  assert.match(frames.args[frames.args.indexOf("-filter_complex") + 1], /512/);
});

test("untrusted metadata cannot select hostile hosts credentials ports or manifests", async t => {
  const f = await fixture(t);
  for (const url of ["http://video.cdninstagram.com/a.mp4", "https://cdninstagram.com.evil.test/a.mp4", "https://127.0.0.1/a.mp4", "https://name:pass@video.fbcdn.net/a.mp4", "https://video.fbcdn.net:8443/a.mp4", "https://video.cdninstagram.com/a.m3u8"]) {
    f.metadata = { formats: [{ url, ext: "mp4", protocol: "https", vcodec: "h264" }] };
    await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), /Video venue analysis/);
  }
  f.metadata = { formats: [{ url: mediaURL, ext: "mp4", protocol: "m3u8_native", vcodec: "h264" }] };
  await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
  assert.equal(f.mediaCalls, 0); assert.equal(f.providerCalls, 0); assert.deepEqual(await readdir(f.root), []);
});

test("bad overlong or oversized decoded video is rejected before Gemini", async t => {
  const f = await fixture(t);
  for (const probe of [{}, { format: { duration: "91" }, streams: [{ codec_type: "video", width: 512, height: 512 }] }, { format: { duration: "10" }, streams: [{ codec_type: "video", width: 99999, height: 99999 }] }]) {
    f.probe = probe; await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
    assert.deepEqual(await readdir(f.root), []);
  }
  assert.equal(f.providerCalls, 0);
});

test("valid no-venue response remains empty evidence", async t => {
  const f = await fixture(t); f.output = { venues: [] };
  assert.deepEqual(await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), []);
  assert.deepEqual(await readdir(f.root), []);
});

test("provider errors malformed and ungrounded responses reject without leaking details", async t => {
  const f = await fixture(t);
  for (const output of ["not JSON", { venues: [{ name: "江牛樓", quote: "another sign", timestampSeconds: 24.84 }] }, { venues: [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24 }] }, { venues: [{ name: "餐廳", quote: "餐廳", timestampSeconds: 24.84 }] }, { venues: Array(4).fill({ name: "江牛樓", quote: "江牛樓", timestampSeconds: 24.84 }) }]) {
    f.output = output; await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), error => error instanceof Error && /Video venue analysis/.test(error.message) && !error.message.includes("fixture-key"));
    assert.deepEqual(await readdir(f.root), []);
  }
  f.status = 429; await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
});

test("Gemini quota denial stops before fetch and temp files are removed", async t => {
  const f = await fixture(t); const denial = new AnalysisControlError(429, "analysis_limit_exceeded", "denied");
  const events: string[] = [];
  const store = { async reserve(_u: string, _a: string, input: { operation: string; reserveMicros?: number }) {
    events.push(input.operation); if (input.operation === "gemini") { assert.ok(input.reserveMicros! > 0); throw denial; } return "event";
  }, async settle() {} } as unknown as AnalysisUsageStore;
  await assert.rejects(withAnalysisUsage(store, "owner", "analysis", () => recoverInstagramVideoVenues(reel, f.fetchMedia, f.options)), error => error === denial);
  assert.deepEqual(events, ["metadata", "gemini"]); assert.equal(f.providerCalls, 0); assert.deepEqual(await readdir(f.root), []);
});

test("metadata quota denial stops before subprocesses or media", async t => {
  const f = await fixture(t); const denial = new AnalysisControlError(429, "analysis_limit_exceeded", "denied");
  const store = { async reserve() { throw denial; } } as unknown as AnalysisUsageStore;
  await assert.rejects(withAnalysisUsage(store, "owner", "analysis", () => recoverInstagramVideoVenues(reel, f.fetchMedia, f.options)), error => error === denial);
  assert.equal(f.commands.length, 0); assert.equal(f.mediaCalls, 0); assert.equal(f.providerCalls, 0);
});

test("failed probe and extraction commands sanitize stderr and clean temporary files", async t => {
  const f = await fixture(t); const original = f.options.execFile!;
  for (const failedCommand of ["ffprobe", "ffmpeg"]) {
    f.options.execFile = async (file, args, limits) => {
      if (file === failedCommand) throw new Error(`secret stderr ${mediaURL} fixture-key ${f.root}`);
      return original(file, args, limits);
    };
    await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options), error => error instanceof Error
      && /Video venue analysis/.test(error.message) && !error.message.includes("fixture-key") && !error.message.includes(f.root) && !error.message.includes(mediaURL));
    assert.deepEqual(await readdir(f.root), []);
  }
  assert.equal(f.providerCalls, 0);
});

test("oversized announced and actual Gemini bodies are cancelled before parsing", async t => {
  const f = await fixture(t);
  for (const announced of [true, false]) {
    let cancelled = false; let reads = 0;
    f.options.fetch = async () => new Response(new ReadableStream<Uint8Array>({
      pull(controller) { reads++; controller.enqueue(new Uint8Array(64_001)); },
      cancel() { cancelled = true; },
    }, { highWaterMark: 0 }), { headers: announced ? { "content-length": "64001" } : {} });
    await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
    assert.equal(cancelled, true); assert.equal(reads, announced ? 0 : 1); assert.deepEqual(await readdir(f.root), []);
  }
});

test("successful Gemini settlement includes tokens while malformed verdict settles failure", async t => {
  const f = await fixture(t); const settled: Array<{ operation: string; outcome: string; tokens?: any }> = [];
  const store = {
    async reserve(_u: string, _a: string, input: { operation: string; model?: string; reserveMicros?: number }) {
      if (input.operation === "gemini") { assert.equal(input.model, "gemini-2.5-flash"); assert.ok(input.reserveMicros! >= 2000); }
      return "event";
    },
    async settle(_u: string, _a: string, _event: string, input: any, outcome: string) { settled.push({ ...input, outcome }); },
  } as unknown as AnalysisUsageStore;
  await withAnalysisUsage(store, "owner", "analysis", () => recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
  assert.deepEqual(settled.map(value => [value.operation, value.outcome]), [["metadata", "success"], ["gemini", "success"]]);
  assert.equal(settled[1].tokens.input, 2000); assert.equal(settled[1].tokens.thinking, 0); assert.equal(settled[1].tokens.total, 2030);
  settled.length = 0; f.output = { venues: [{ name: "guessed", quote: "no matching name", timestampSeconds: 24.84 }] };
  await assert.rejects(withAnalysisUsage(store, "owner", "analysis", () => recoverInstagramVideoVenues(reel, f.fetchMedia, f.options)));
  assert.deepEqual(settled.map(value => [value.operation, value.outcome]), [["metadata", "success"], ["gemini", "failure"]]);
});

test("runtime command overrides and alternative Gemini key remain injectable", async t => {
  const f = await fixture(t); const original = f.options.execFile!; const invoked: string[] = [];
  f.options.env = { SAVE_ENABLE_VIDEO_VENUE_ANALYSIS: "true", GOOGLE_GEMINI_API_KEY: "fixture-alternative", SAVE_VIDEO_YTDLP_COMMAND: "/fixture/yt", SAVE_VIDEO_FFPROBE_COMMAND: "/fixture/probe", SAVE_VIDEO_FFMPEG_COMMAND: "/fixture/frames" };
  f.options.execFile = async (file, args, limits) => { invoked.push(file); return original(file === "/fixture/yt" ? "yt-dlp" : file === "/fixture/probe" ? "ffprobe" : "ffmpeg", args, limits); };
  await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options);
  assert.deepEqual(invoked, ["/fixture/yt", "/fixture/probe", "/fixture/frames"]);
});

test("media rejection and format manifests never reach Gemini", async t => {
  const f = await fixture(t);
  await assert.rejects(recoverInstagramVideoVenues(reel, async () => undefined, f.options));
  await assert.rejects(recoverInstagramVideoVenues(reel, async () => ({ data: new Uint8Array(24_000_001) }), f.options));
  f.metadata = { formats: [{ url: mediaURL, ext: "mp4", protocol: "https", vcodec: "h264", manifest_url: "https://video.cdninstagram.com/manifest.mpd" }] };
  await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
  assert.equal(f.providerCalls, 0); assert.deepEqual(await readdir(f.root), []);
});


test("short video timestamps cannot escape actual duration through matching tolerance", async t => {
  const f = await fixture(t);
  f.probe = { format: { duration: "0.1", format_name: "mov,mp4" }, streams: [{ codec_type: "video", width: 512, height: 512 }] };
  for (const timestampSeconds of [-0.1, 0.2]) {
    f.output = { venues: [{ name: "江牛樓", quote: "江牛樓", timestampSeconds }] };
    await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
  }
  f.output = { venues: [{ name: "江牛樓", quote: "江牛樓", timestampSeconds: 0.05 }] };
  assert.equal((await recoverInstagramVideoVenues(reel, f.fetchMedia, f.options))[0].timestampSeconds, 0.05);
});

test("MP4 filename cannot disguise another decoded container", async t => {
  const f = await fixture(t);
  f.probe = { format: { duration: "20", format_name: "matroska,webm" }, streams: [{ codec_type: "video", width: 512, height: 512 }] };
  await assert.rejects(recoverInstagramVideoVenues(reel, f.fetchMedia, f.options));
  assert.equal(f.providerCalls, 0); assert.deepEqual(await readdir(f.root), []);
});
