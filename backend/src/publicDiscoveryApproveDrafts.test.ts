import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { listPublicDiscoveryPosts, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { approveReviewedDrafts, resumePendingDraftApproval } from "./publicDiscoveryApproveDrafts.js";
import { checkStreetDrafts } from "./publicDiscoveryDraftEvidence.js";
import { publishApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";

const now = new Date("2026-11-23T08:00:00.000Z");
const place: PublicDiscoveryPlace = { provider: "apple_maps", providerPlaceID: "BranchA", name: "測試茶點店",
  address: "臺北市萬華區貴陽街二段116號", latitude: 25.04, longitude: 121.50, coordinateSystem: "WGS84", category: "food" };
const existing = { platform: "threads", sourceURL: "https://www.threads.com/@example/post/EXISTING", authorHandle: "example",
  title: place.name, review: { origin: "public_web_index", checkedAt: now.toISOString(), branchEvidence: "Full address." } };
const draft = { platform: "instagram", sourceURL: "https://www.instagram.com/p/NEW/", authorHandle: null, title: "", review: null };
const html = `<div class="Embed"><a class="EmbeddedMedia" href="${draft.sourceURL}">Read</a>
  <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>今天去${place.name}喝茶。地址：${place.address}。</div></div>`;
const owner = "12345678-abcd-abcd-abcd-123456789012";

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), "savvy-draft-approval-"));
  const state = join(root, "state");
  const generations = join(state, "generations");
  await mkdir(generations, { recursive: true });
  const lock = await open(join(state, "refresh.lock"), "wx+");
  t.after(async () => { await lock.close(); await rm(root, { recursive: true }); });
  const archive = { venues: [{ place, candidates: [existing, draft] }] };
  const { manifest } = compileReviewedPublicBatch(archive, now);
  const bytes = JSON.stringify(manifest) + "\n";
  const digest = createHash("sha256").update(bytes).digest("hex");
  const active = join(state, "active-index.json");
  await writeFile(active, bytes);
  await writeFile(join(generations, digest + ".json"), JSON.stringify({ indexSHA256: digest, archive, quarantine: [] }));
  await writeFile(join(state, "managed-index-history.json"), JSON.stringify({ version: 1, owner, anchor: digest, active: digest, previous: null }));
  const input = (activeArchive: unknown, target = place) => checkStreetDrafts(
    activeArchive, [{ place: target, candidates: [draft] }], [target], { now, fetchEmbed: async () => html },
  );
  return { root, generations, lock, active, bytes, input, pending: join(state, "pending-admission.json") };
}

function interruptedClock() {
  let calls = 0;
  return () => {
    if (++calls === 2) throw new Error("interrupted after staging");
    return now;
  };
}

test("resumes a staged approval without reading originals and serves it at the exact saved place", async t => {
  const data = await fixture(t);
  const { root, lock, active, pending, generations, bytes, input } = data;
  let reads = 0;
  await assert.rejects(approveReviewedDrafts(root, lock.fd, { now, clock: interruptedClock(), verify: archive => {
    reads++;
    // A caller's candidate work must not mutate the approved archive.
    (archive as { venues: { candidates: unknown[] }[] }).venues[0]!.candidates.shift();
    return input(archive);
  } }), /interrupted after staging/);
  assert.equal(await readFile(active, "utf8"), bytes);
  const journal = await readFile(pending, "utf8");
  const { indexSHA256 } = JSON.parse(journal);
  const stored = JSON.parse(await readFile(join(generations, indexSHA256 + ".json"), "utf8"));
  assert.equal(stored.managedBy, undefined);
  assert.equal(stored.archive.venues[0].candidates.length, 2);

  const resumed = await resumePendingDraftApproval(root, lock.fd, () => now);
  assert.equal(resumed?.admitted, 1);
  assert.equal(resumed?.indexSHA256, indexSHA256);
  assert.equal(JSON.parse(await readFile(join(generations, indexSHA256 + ".json"), "utf8")).managedBy, owner);
  assert.equal(reads, 1);
  await assert.rejects(readFile(pending), { code: "ENOENT" });
  // If the active pointer was written before interruption, replay the receipt.
  const approved = await readFile(active);
  await writeFile(pending, journal);
  assert.deepEqual(await resumePendingDraftApproval(root, lock.fd, () => now), resumed);
  assert.deepEqual(await readFile(active), approved);

  const published = await publishApprovedGeneration(root, lock.fd, () => now);
  assert.equal(published.state, "published");
  const query = new URL("http://localhost/v0/discovery/posts?bbox=121,25,122,26&provider=apple_maps&placeID=BranchA");
  const { posts } = await listPublicDiscoveryPosts(query, { filePath: join(root, "serving", "index.json"), now });
  assert.deepEqual(posts.map(post => post.id).sort(), ["instagram:NEW", "threads:EXISTING"]);
});

test("does not activate an expired staged approval or overwrite an existing branch identity", async t => {
  const { root, lock, active, pending, bytes, input, generations } = await fixture(t);
  await assert.rejects(approveReviewedDrafts(root, lock.fd, { now, clock: () => now,
    verify: archive => input(archive, { ...place, longitude: 121.51 }),
  }), /differs from the reviewed identity/);
  await assert.rejects(readFile(pending), { code: "ENOENT" });
  await assert.rejects(approveReviewedDrafts(root, lock.fd, { now, clock: interruptedClock(), verify: input }), /interrupted after staging/);
  const { indexSHA256 } = JSON.parse(await readFile(pending, "utf8"));
  assert.equal(await resumePendingDraftApproval(root, lock.fd, () => new Date(+now + 86_400_000)), undefined);
  assert.equal(await readFile(active, "utf8"), bytes);
  await assert.rejects(readFile(pending), { code: "ENOENT" });
  assert.ok((await readFile(join(generations, indexSHA256 + ".json"))).length > 0);
});

test("a newer active generation does not depend on a pruned superseded approval", async t => {
  const { root, lock, active, pending, generations, input } = await fixture(t);
  await assert.rejects(approveReviewedDrafts(root, lock.fd, { now, clock: interruptedClock(), verify: input }), /interrupted after staging/);
  const { indexSHA256 } = JSON.parse(await readFile(pending, "utf8"));
  const archive = { venues: [{ place, candidates: [existing] }] };
  const { manifest } = compileReviewedPublicBatch(archive, new Date(+now + 1_000));
  const newer = JSON.stringify(manifest) + "\n";
  const digest = createHash("sha256").update(newer).digest("hex");
  await writeFile(join(generations, digest + ".json"), JSON.stringify({ indexSHA256: digest, archive, quarantine: [] }));
  await writeFile(active, newer);
  await rm(join(generations, indexSHA256 + ".json"));
  assert.equal(await resumePendingDraftApproval(root, lock.fd, () => new Date(+now + 1_000)), undefined);
  assert.equal(await readFile(active, "utf8"), newer);
  await assert.rejects(readFile(pending), { code: "ENOENT" });
});

test("does not replay an activated approval after an explicit rollback to its base", async t => {
  const { root, lock, active, pending, bytes, input } = await fixture(t);
  await assert.rejects(approveReviewedDrafts(root, lock.fd, { now, clock: interruptedClock(), verify: input }), /interrupted after staging/);
  const journal = await readFile(pending);
  assert.equal((await resumePendingDraftApproval(root, lock.fd, () => now))?.admitted, 1);
  await writeFile(pending, journal);
  await writeFile(active, bytes);
  assert.equal(await resumePendingDraftApproval(root, lock.fd, () => now), undefined);
  assert.equal(await readFile(active, "utf8"), bytes);
  await assert.rejects(readFile(pending), { code: "ENOENT" });
});
