import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { maintainPublicSourceDrafts } from "./publicDiscoveryDraftMaintenance.js";
import { readActiveApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";
import { renewApprovedSources } from "./publicDiscoverySourceRenewal.js";
import { publicPostEvidenceFingerprint } from "./publicPostReverification.js";

const now = new Date("2026-11-23T11:00:00.000Z");
const hour = 60 * 60_000;
const clock = () => now;
const venue = (providerPlaceID: string): PublicDiscoveryPlace => ({ provider: "apple_maps", providerPlaceID,
  name: providerPlaceID, address: "臺北市萬華區貴陽街二段116號", latitude: 25.04, longitude: 121.5,
  coordinateSystem: "WGS84", category: "food" });
const original = (id: string) => `https://www.instagram.com/p/${id}/`;
function markup(url: string, caption = "這是作者分享的完整原始文字。") {
  return `<div class="Embed"><a class="EmbeddedMedia" href="${url.replace(/embed\/captioned\/$/, "")}">Read</a>
    <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>${caption}</div></div>`;
}
function reviewed(place: PublicDiscoveryPlace, id: string, age: number, multiVenue = false) {
  const url = original(id);
  return { platform: "instagram", sourceURL: url, authorHandle: "example", title: place.name,
    review: { origin: "public_web_index", checkedAt: new Date(+now - age * hour).toISOString(),
      branchEvidence: "Exact reviewed venue.", contentFingerprint: publicPostEvidenceFingerprint(markup(url), "instagram", url, "example", place),
      ...(multiVenue ? { multiVenue: true } : {}) } };
}

async function fixture(t: TestContext, venues: { place: PublicDiscoveryPlace; candidates: unknown[] }[], generatedAt = now) {
  const root = await mkdtemp(join(tmpdir(), "savvy-renewal-"));
  const state = join(root, "state");
  await mkdir(join(state, "generations"), { recursive: true });
  await mkdir(join(root, "drafts"));
  const lock = await open(join(state, "refresh.lock"), "wx+");
  t.after(async () => { await lock.close(); await rm(root, { recursive: true }); });
  const archive = { venues };
  const { manifest } = compileReviewedPublicBatch(archive, generatedAt);
  const bytes = JSON.stringify(manifest) + "\n";
  const indexSHA256 = createHash("sha256").update(bytes).digest("hex");
  await writeFile(join(state, "active-index.json"), bytes);
  await writeFile(join(state, "generations", indexSHA256 + ".json"), JSON.stringify({ indexSHA256, archive, quarantine: [] }));
  return { root, state, descriptor: lock.fd, indexSHA256 };
}

test("renewal protects a venue's last source and reads a shared original only once", async t => {
  const a = venue("Alpha");
  const b = venue("Beta");
  const covered = venue("Covered");
  const crowded = Array.from({ length: 4 }, (_, i) => reviewed(covered, `OLDER_${i}`, 23));
  const { root, state, descriptor } = await fixture(t, [
    { place: a, candidates: [reviewed(a, "SHARED", 19, true)] },
    { place: b, candidates: [reviewed(b, "SHARED", 19, true)] },
    { place: covered, candidates: [...crowded, reviewed(covered, "FRESH", 1)] },
  ]);
  const calls: string[] = [];
  const result = await renewApprovedSources(root, descriptor, {
    clock, providerPaused: () => false, fetchEmbed: async url => { calls.push(url); return markup(url); },
  });
  assert.equal(calls.length, 4);
  assert.match(calls[0]!, /SHARED/);
  assert.equal(new Set(calls).size, 4);
  assert.equal(result.renewed, 5);
  const active = await readActiveApprovedGeneration(state);
  const posts = active.raw.posts as { id: string; verifiedAt: string }[];
  assert.equal(posts.filter(post => post.id === "instagram:SHARED" && post.verifiedAt === now.toISOString()).length, 2);
  assert.equal(posts.length, 7);
});

test("equal renewal deadlines prioritize originals that protect more uncovered places", async t => {
  const early = venue("Early");
  const singles = Array.from({ length: 4 }, (_, i) => venue(`Single_${i}`));
  const shared = Array.from({ length: 3 }, (_, i) => venue(`Shared_${i}`));
  const later = Array.from({ length: 4 }, (_, i) => venue(`Later_${i}`));
  const { root, descriptor } = await fixture(t, [
    { place: early, candidates: [reviewed(early, "EARLY", 22)] },
    ...singles.map((place, i) => ({ place, candidates: [reviewed(place, `A_${i}`, 20)] })),
    ...shared.map((place, i) => ({ place, candidates: [reviewed(place, "Z_SHARED", 20, true),
      ...(i < 2 ? [reviewed(place, "Z_OVERLAP", 20, true)] : [])] })),
    ...later.map(place => ({ place, candidates: [reviewed(place, "LATER", 19, true)] })),
  ]);
  const calls: string[] = [];
  const result = await renewApprovedSources(root, descriptor, {
    clock, providerPaused: () => false, fetchEmbed: async url => { calls.push(url); return markup(url); },
  });
  assert.deepEqual(calls, ["EARLY", "Z_SHARED", "A_0", "A_1"].map(id => original(id) + "embed/captioned/"));
  assert.equal(result.renewed, 6);
});

test("quarantines confirmed removal and changed originals while preserving temporarily unavailable posts", async t => {
  const place = venue("Branch");
  const { root, state, descriptor } = await fixture(t, [{
    place, candidates: ["MISSING", "CHANGED", "TIMEOUT"].map(id => reviewed(place, id, 20)),
  }]);
  const result = await renewApprovedSources(root, descriptor, {
    clock, providerPaused: () => false, fetchEmbed: async url => {
      if (url.includes("MISSING")) throw new Error("HTTP 410");
      if (url.includes("TIMEOUT")) throw new Error("Temporary network failure");
      return markup(url, "作者具名改寫了內容，需要另行確認。");
    },
  });
  assert.equal(result.quarantined, 2);
  assert.equal(result.unavailable, 1);
  const active = await readActiveApprovedGeneration(state);
  assert.deepEqual((active.raw.posts as { id: string }[]).map(post => post.id), ["instagram:TIMEOUT"]);
  assert.deepEqual([...active.envelope.held].sort(), ["apple_maps:Branch:instagram:CHANGED", "apple_maps:Branch:instagram:MISSING"]);
});

test("a renewal provider hold prevents new draft reads in the same cycle and on restart", async t => {
  const place = venue("Branch");
  const { root, state, descriptor, indexSHA256 } = await fixture(t, [{ place, candidates: [reviewed(place, "RENEW", 20)] }]);
  await writeFile(join(root, "inventory.json"), JSON.stringify([{ place, missing: ["instagram"] }]));
  await writeFile(join(root, "drafts", "a".repeat(64) + ".json"), JSON.stringify({ place, candidates: [{
    platform: "instagram", sourceURL: original("DRAFT"), authorHandle: null, title: "", review: null,
  }] }));
  const calls: string[] = [];
  const result = await maintainPublicSourceDrafts(root, descriptor, { clock, renewExisting: true, fetchEmbed: async url => {
    calls.push(url);
    throw new Error("HTTP 403");
  } });
  assert.equal(result.state, "provider_hold");
  assert.equal(result.requests, 1);
  assert.equal(calls.length, 1);
  assert.match(calls[0]!, /RENEW/);
  const saved = JSON.parse(await readFile(join(state, "shared-provider-hold.json"), "utf8"));
  assert.equal(saved.until, +now + hour);
  const retry = await maintainPublicSourceDrafts(root, descriptor, {
    clock: () => new Date(+now + 30_000), renewExisting: true, fetchEmbed: async () => assert.fail("Provider hold must survive restart"),
  });
  assert.equal(retry.requests, 0);
  assert.equal((await readActiveApprovedGeneration(state)).indexSHA256, indexSHA256);
});

test("temporarily unavailable originals do not consume the next cycle's renewal budget", async t => {
  const place = venue("Branch");
  const { root, descriptor } = await fixture(t, [{ place, candidates: Array.from({ length: 5 },
    (_, index) => reviewed(place, `POST_${index}`, 23)) }]);
  const tried = new Set<string>();
  const first = await renewApprovedSources(root, descriptor, {
    clock, providerPaused: () => false, fetchEmbed: async url => {
      tried.add(url);
      throw new Error("Temporary network failure");
    },
  });
  assert.equal(first.unavailable, 4);
  const next = await renewApprovedSources(root, descriptor, {
    clock: () => new Date(+now + 60_000), providerPaused: () => false, fetchEmbed: async url => {
      assert.equal(tried.has(url), false);
      return markup(url);
    },
  });
  assert.equal(next.renewed, 1);
});

test("a single cycle approves drafts against the generation its renewal just activated", async t => {
  const place = venue("Branch");
  const { root, state, descriptor } = await fixture(t, [{ place, candidates: [reviewed(place, "RENEW", 20)] }]);
  await writeFile(join(root, "inventory.json"), JSON.stringify([{ place, missing: ["instagram"] }]));
  await writeFile(join(root, "drafts", "a".repeat(64) + ".json"), JSON.stringify({ place, candidates: [{
    platform: "instagram", sourceURL: original("DRAFT"), authorHandle: null, title: "", review: null,
  }] }));
  let tick = 0;
  const result = await maintainPublicSourceDrafts(root, descriptor, {
    clock: () => new Date(+now + tick++), renewExisting: true, fetchEmbed: async url => url.includes("RENEW")
      ? markup(url)
      : markup(url, `在${place.name}喝茶。地址：${place.address}。`),
  });
  assert.equal(result.requests, 2);
  const { raw } = await readActiveApprovedGeneration(state);
  assert.deepEqual((raw.posts as { id: string }[]).map(post => post.id).sort(), ["instagram:DRAFT", "instagram:RENEW"]);
});

test("withdraws a removed original even when another source expires during the request", async t => {
  const place = venue("Branch");
  const legacy = { ...reviewed(place, "ALMOST_EXPIRED", 23), review: {
    origin: "public_web_index", checkedAt: new Date(+now - 24 * hour + 10).toISOString(),
    branchEvidence: "Previously reviewed original.",
  } };
  const { root, state, descriptor } = await fixture(t, [{ place, candidates: [legacy, reviewed(place, "GONE", 20)] }]);
  let wall = now;
  const result = await renewApprovedSources(root, descriptor, {
    clock: () => wall, providerPaused: () => false, fetchEmbed: async url => {
      assert.match(url, /GONE/);
      wall = new Date(+now + 50);
      throw new Error("HTTP 410");
    },
  });
  assert.equal(result.quarantined, 1);
  const active = await readActiveApprovedGeneration(state);
  assert.deepEqual(active.raw.posts, []);
  assert.ok(active.envelope.held.has("apple_maps:Branch:instagram:GONE"));
});
