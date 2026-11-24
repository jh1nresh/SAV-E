import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { listPublicDiscoveryPosts } from "./publicDiscovery.js";
import { publishApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";

const now = new Date("2026-11-18T12:00:00Z");
const place = { provider: "apple_maps", providerPlaceID: "BranchA", name: "Store A", address: "10 Example Rd",
  latitude: 25.03, longitude: 121.56, coordinateSystem: "WGS84", category: "cafe" };
const source = { platform: "instagram", sourceURL: "https://www.instagram.com/p/CHECKED/", title: "Visit to Store A",
  authorHandle: "reviewer", review: { checkedAt: now.toISOString(), origin: "public_web_index", branchEvidence: "Address matched." } };
const heldSource = { ...source, sourceURL: "https://www.instagram.com/p/WITHHELD/" };
const archive = { venues: [{ place, candidates: [source, heldSource] }],
  applePlaceAliases: [{ applePlaceID: "BranchAlias", providerPlaceID: place.providerPlaceID, branchEvidence: "Same storefront." }] };

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), "savvy-approved-generation-"));
  const state = join(root, "state");
  const index = join(root, "serving", "index.json");
  await mkdir(join(state, "generations"), { recursive: true });
  const handle = await open(join(state, "refresh.lock"), "wx+");
  t.after(async () => { await handle.close(); await rm(root, { recursive: true }); });
  const clock = () => now;
  return { root, state, index, handle, publish: () => publishApprovedGeneration(root, handle.fd, clock) };
}

async function approve(state: string, manifest: unknown, quarantine: { key: string }[] = []) {
  const data = JSON.stringify(manifest) + "\n";
  const indexSHA256 = createHash("sha256").update(data).digest("hex");
  const envelopePath = join(state, "generations", indexSHA256 + ".json");
  const envelope = { indexSHA256, archive, quarantine };
  await writeFile(envelopePath, JSON.stringify(envelope));
  await writeFile(join(state, "active-index.json"), data);
  return { envelope, envelopePath };
}

test("approved publication keeps valid aliases and suppresses the quarantined original", async t => {
  const { state, index, publish } = await fixture(t);
  const { manifest } = compileReviewedPublicBatch({ ...archive, venues: [{ place, candidates: [source] }] }, now);
  await approve(state, manifest, [{ key: "apple_maps:BranchA:instagram:WITHHELD" }]);
  const result = await publish();
  assert.equal(result.state, "published");
  const query = new URL("http://localhost/v0/discovery/posts?bbox=121,25,122,26&provider=apple_maps&placeID=BranchAlias");
  const page = await listPublicDiscoveryPosts(query, { filePath: index, now });
  assert.deepEqual(page.posts.map(post => post.id), ["instagram:CHECKED"]);
  const bytes = await readFile(index);
  assert.equal((await publish()).state, "unchanged");
  const { shards } = JSON.parse(bytes.toString("utf8"));
  await rm(join(index, "..", shards[0] + ".json"));
  assert.deepEqual(await publish(), result);
  assert.deepEqual(await readFile(index), bytes);
});

test("approval mismatches and the wrong lock descriptor preserve the prior serving catalog", async t => {
  const { root, state, index, publish } = await fixture(t);
  const { manifest } = compileReviewedPublicBatch(archive, now);
  await approve(state, manifest);
  await publish();
  const before = await readFile(index);
  const changed = { ...manifest, posts: manifest.posts.map(post => ({ ...post, title: "Not in the reviewed original" })) };
  await approve(state, changed);
  await assert.rejects(publish(), /must match the approved generation/);
  const other = await open(join(state, "active-index.json"), "r");
  try {
    await assert.rejects(publishApprovedGeneration(root, other.fd, () => now), /inherited source lock/);
  } finally {
    await other.close();
  }
  assert.deepEqual(await readFile(index), before);
});
