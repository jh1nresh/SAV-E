import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { listPublicDiscoveryPosts, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { maintainPublicSourceDrafts } from "./publicDiscoveryDraftMaintenance.js";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";

const now = new Date("2026-11-23T08:00:00.000Z");
const place: PublicDiscoveryPlace = { provider: "apple_maps", providerPlaceID: "BranchA", name: "測試茶點店",
  address: "臺北市萬華區貴陽街二段116號", latitude: 25.04, longitude: 121.50, coordinateSystem: "WGS84", category: "food" };
const draft = (code: string) => ({ platform: "instagram", authorHandle: null, title: "", review: null,
  sourceURL: `https://www.instagram.com/p/${code}/` });
const embed = (url: string) => `<div class="Embed"><a class="EmbeddedMedia" href="${url.replace(/embed\/captioned\/$/, "")}">Read</a>
  <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>原作者到${place.name}喝茶。地址：${place.address}。</div></div>`;

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), "savvy-draft-maintenance-"));
  const state = join(root, "state");
  const lockPath = join(state, "refresh.lock");
  const active = join(state, "active-index.json");
  const inventory = join(root, "inventory.json");
  await mkdir(join(state, "generations"), { recursive: true });
  await mkdir(join(root, "drafts"));
  const lock = await open(lockPath, "wx+");
  t.after(async () => { await lock.close(); await rm(root, { recursive: true }); });
  const archive = { venues: [{ place, candidates: [{ platform: "threads", authorHandle: "example",
    sourceURL: "https://www.threads.com/@example/post/EXISTING", title: place.name, review: {
      checkedAt: now.toISOString(), origin: "public_web_index", branchEvidence: "Confirmed place address.",
    } }] }] };
  const { manifest } = compileReviewedPublicBatch(archive, now);
  const bytes = JSON.stringify(manifest) + "\n";
  const hash = createHash("sha256").update(bytes).digest("hex");
  await writeFile(active, bytes);
  await writeFile(join(state, "generations", hash + ".json"), JSON.stringify({ indexSHA256: hash, archive, quarantine: [] }));
  await writeFile(inventory, JSON.stringify([{ place, missing: ["instagram", "threads"] }]));
  const draftID = createHash("sha256").update(JSON.stringify([place.provider, place.providerPlaceID])).digest("hex");
  const writeReport = (codes: string[], threadCodes: string[] = []) => writeFile(join(root, "drafts", draftID + ".json"),
    JSON.stringify({ place, checkedAt: now.toISOString(), coverage: { instagram: "searched", threads: "deferred" },
      candidates: [...codes.map(draft), ...threadCodes.map(code => ({ ...draft(code), platform: "threads",
        sourceURL: `https://www.threads.com/@example/post/${code}` }))] }));
  const run = (time: Date, fetchEmbed: (url: string) => Promise<string>) =>
    maintainPublicSourceDrafts(root, lock.fd, { clock: () => time, fetchEmbed });
  return { active, bytes, inventory, run, writeReport, hold: join(state, "shared-provider-hold.json"),
    index: join(root, "serving", "index.json") };
}

test("processes saved drafts in bounded batches and wakes for a new report", async t => {
  const { hold, index, writeReport, run } = await fixture(t);
  const requests: string[] = [];
  const fetchEmbed = async (url: string) => {
    const marker = JSON.parse(await readFile(hold, "utf8"));
    assert.ok(marker.until > +now);
    requests.push(url);
    return embed(url);
  };
  await writeReport(["ONE", "TWO", "THREE"]);
  const first = await run(now, fetchEmbed);
  assert.equal(first.requests, 2);
  const waiting = await run(new Date(+now + 500), fetchEmbed);
  assert.equal(waiting.state, "cadence_wait");
  assert.equal(waiting.requests, 0);
  const second = await run(new Date(first.nextAllowedAt), fetchEmbed);
  assert.equal(second.requests, 1);
  const idle = await run(new Date(second.nextAllowedAt), fetchEmbed);
  assert.equal(idle.state, "idle");
  await writeReport(["ONE", "TWO", "THREE", "FOUR"]);
  const fresh = await run(new Date(idle.nextAllowedAt), fetchEmbed);
  assert.equal(fresh.requests, 1);
  assert.equal(new Set(requests).size, 4);
  const url = new URL("http://localhost/v0/discovery/posts?bbox=121,25,122,26&provider=apple_maps&placeID=BranchA");
  const { posts } = await listPublicDiscoveryPosts(url, { filePath: index, now: new Date(idle.nextAllowedAt) });
  assert.deepEqual(posts.map(post => post.id).sort(),
    ["instagram:FOUR", "instagram:ONE", "instagram:THREE", "instagram:TWO", "threads:EXISTING"]);
});

test("persists a provider 403 pause across runs without additional requests", async t => {
  const { active, bytes, hold, run, writeReport } = await fixture(t);
  await writeReport(["FIRST", "NEXT"]);
  const first = await run(now, async () => { throw new Error("HTTP 403"); });
  assert.equal(first.requests, 1);
  assert.equal(first.nextAllowedAt, +now + 60 * 60_000);
  assert.equal(JSON.parse(await readFile(hold, "utf8")).until, first.nextAllowedAt);
  const waiting = await run(new Date(+now + 59 * 60_000), async () => assert.fail("Cooldown reached the provider"));
  assert.equal(waiting.state, "provider_hold");
  assert.equal(waiting.requests, 0);
  assert.equal(await readFile(active, "utf8"), bytes);
});

test("accepts a combined two-platform report without increasing the per-cycle request limit", async t => {
  const { run, writeReport } = await fixture(t);
  await writeReport(Array.from({ length: 20 }, (_, i) => `IG_${i}`), Array.from({ length: 20 }, (_, i) => `TH_${i}`));
  const result = await run(now, async url => embed(url));
  assert.equal(result.requests, 2);
  assert.equal("approval" in result ? result.approval?.deferred : undefined, 38);
});

test("rejects an approval if the trusted inventory changes during the original read", async t => {
  const { active, bytes, hold, inventory, run, writeReport } = await fixture(t);
  await writeReport(["ONE"]);
  await assert.rejects(run(now, async url => {
    await writeFile(inventory, JSON.stringify([{ place: { ...place, longitude: 121.51 }, missing: ["instagram"] }]));
    return embed(url);
  }), /Trusted source inventory changed/);
  assert.equal(await readFile(active, "utf8"), bytes);
  assert.equal(JSON.parse(await readFile(hold, "utf8")).until, +now + 60 * 60_000);
});
