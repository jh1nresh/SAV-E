import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { collectPublicProfileDiscoveryDrafts } from "./publicDiscoveryProfileDrafts.js";
import { compileReviewedPublicBatch } from "./publicDiscoveryReviewedBatch.js";

const branch = {
  provider: "apple_maps", providerPlaceID: "ExampleSpot", name: "Example Kitchen",
  address: "10 Example Road, 2F", latitude: 25.04, longitude: 121.55,
  coordinateSystem: "WGS84", category: "food",
};
const otherBranch = { ...branch, providerPlaceID: "SecondSpot", name: "Example Kitchen West" };
const lookup = (platform: string, handle: string, ...terms: string[]) => ({ platform, handle, terms });
const post = (code: string, owner: string, caption: string) => ({
  code, user: { username: owner }, caption: { text: caption }, media_type: 2, product_type: "clips",
});
const title = (handle: string) => `<meta property="og:title" content="Example (@${handle}) • Social">`;
const profileData = (handle: string, posts: unknown[], platform = "threads", isPrivate = false) => ({
  __bbox: { result: { data: platform === "threads" ? {
    user: { username: handle, text_post_app_is_private: isPrivate },
    mediaData: { edges: [{ node: { thread_items: posts.map(value => ({ post: value })) } }] },
  } : {
    xig_user_by_username: { id: "12345", username: handle, is_private: isPrivate,
      polaris_ordered_timeline_connection: { edges: posts.map(value => ({ node: value })) } },
  } } },
});
const script = (data: unknown, attributes = 'type="application/json"') =>
  `<script ${attributes}>${JSON.stringify(data)}</script>`;
const html = (handle: string, posts: unknown[], platform = "threads", isPrivate = false) =>
  title(handle) + script(profileData(handle, posts, platform, isPrivate));
const page = (body: string, status = 200) => new Response(body, { status, headers: { "content-type": "text/html" } });

test("runs CLI argument validation when the executable path is a symlink", async t => {
  const directory = await mkdtemp(join(tmpdir(), "public-profile-command-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const alias = join(directory, "profile-drafts.js");
  await symlink(fileURLToPath(new URL("./publicDiscoveryProfileDrafts.js", import.meta.url)), alias);

  const result = spawnSync(process.execPath, [alias], { encoding: "utf8", timeout: 5_000 });
  assert.ifError(result.error);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /Check the batch file/);

  const module = new URL("./publicDiscoveryProfileDrafts.js", import.meta.url).href;
  const imported = spawnSync(process.execPath, [
    "--input-type=module", "--eval", `await import(${JSON.stringify(module)})`, alias,
  ], { encoding: "utf8", timeout: 5_000 });
  assert.ifError(imported.error);
  assert.equal(imported.status, 0);
  assert.equal(imported.stdout, "");
  assert.equal(imported.stderr, "");
});

test("stages same-owner originals from both platforms with one request per profile", async () => {
  const seen: string[] = [];
  const result = await collectPublicProfileDiscoveryDrafts({ venues: [
    { place: branch, profiles: [lookup("threads", "Example", "ＫＩＴＣＨＥＮ EAST"), lookup("instagram", "example", "Kitchen East")] },
    { place: otherBranch, profiles: [lookup("threads", "example", "Kitchen West")] },
  ] }, async (url, init) => {
    const path = String(url);
    seen.push(path);
    assert.equal(init?.redirect, "manual");
    assert.deepEqual([...new Headers(init?.headers).keys()], ["accept", "user-agent"]);
    assert.equal(new URL(path).search, "");
    if (path.includes("instagram")) return page(html("example", [post("ReelOne", "example", "Kitchen East raw caption")], "instagram"));
    return page(html("example", [
      post("EastOne", "example", "Kitchen\nEast raw caption"),
      post("EastOne", "example", "Kitchen\nEast raw caption"),
      post("WestOne", "Example", "Kitchen West"),
      post("Elsewhere", "someone_else", "Kitchen East"),
      post("Conflict", "example", "Kitchen East"),
      post("Conflict", "example", "Conflicting duplicate"),
      { ...post("Private", "example", "Kitchen East"), user: { username: "example", text_post_app_is_private: true } },
    ]));
  });
  assert.deepEqual(seen, ["https://www.threads.com/@example", "https://www.instagram.com/example/"]);
  assert.deepEqual(result.profiles.map(({ status, readablePosts }) => [status, readablePosts]), [["read", 2], ["read", 1]]);
  assert.deepEqual(result.draft.venues.map(({ candidates }) => candidates.map(p => p.sourceURL)), [
    ["https://www.threads.com/@example/post/EastOne", "https://www.instagram.com/reel/ReelOne/"],
    ["https://www.threads.com/@example/post/WestOne"],
  ]);
  assert(result.draft.venues.flatMap(v => v.candidates).every(p => p.review === null));
  const rebuilt = compileReviewedPublicBatch(result.draft);
  assert.equal(rebuilt.withheld, 3);
  assert.deepEqual(rebuilt.manifest.posts, []);
  assert.doesNotMatch(JSON.stringify(result), /raw caption|Kitchen East|Conflicting duplicate/);
});

test("separates readable empties and challenges and stops a rate-limited platform", async () => {
  const seen: string[] = [];
  const result = await collectPublicProfileDiscoveryDrafts({ venues: [
    { place: branch, profiles: [
      lookup("threads", "missing", "Kitchen"), lookup("threads", "empty", "Kitchen"),
      lookup("threads", "limited", "Kitchen"), lookup("threads", "skipped", "Kitchen"),
      lookup("instagram", "available", "Kitchen"),
    ] },
  ] }, async url => {
    const key = new URL(String(url)).pathname.replace(/[\/@]/g, "");
    seen.push(key);
    switch (key) {
      case "missing": return page("<title>Threads • Log in</title>");
      case "empty": return page(html("empty", []));
      case "limited": return page("rate limit", 429);
      case "available": return page(html("available", []));
      default: return assert.fail("No request expected");
    }
  });
  assert.deepEqual(seen, ["missing", "empty", "limited", "available"]);
  assert.deepEqual(result.profiles.map(p => p.status), [
    "access_required", "no_readable_posts", "rate_limited", "not_attempted", "no_readable_posts",
  ]);
  assert.deepEqual(result.draft.venues, []);
});

test("malformed, oversized, and mismatched-profile responses do not yield drafts", async () => {
  for (const body of [
    html("other", [post("WrongAccount", "example", "Kitchen")]),
    "x".repeat(3 * 1_024 * 1_024 + 1),
    "<script>".repeat(30_000),
  ]) {
    const result = await collectPublicProfileDiscoveryDrafts({
      venues: [{ place: branch, profiles: [lookup("threads", "example", "Kitchen")] }],
    }, async () => page(body));
    assert.deepEqual(result.draft.venues, []);
    assert.equal(result.profiles[0]?.status, "unavailable");
  }
});

test("uses only JSON scripts in active markup and a provider-owned timeline", async () => {
  const data = profileData("example", [post("ResultOne", "example", "Kitchen East")]);
  for (const markup of [
    `<!--${script(data)}-->`,
    `<template>${script(data)}</template>`,
    `<div hidden>${script(data)}</div>`,
    script(data, `data-note=' type="application/json"' type="text/plain"`),
    script(post("UnrelatedPayload", "example", "Kitchen East")),
  ]) {
    const result = await collectPublicProfileDiscoveryDrafts({
      venues: [{ place: branch, profiles: [lookup("threads", "example", "Kitchen")] }],
    }, async () => page(title("example") + markup));
    assert.deepEqual(result.draft.venues, []);
    assert.equal(result.profiles[0]?.status, "no_readable_posts");
  }
});

test("withholds the whole timeline when the profile is private or public access cannot be established", async () => {
  const posts = [post("HiddenPost", "example", "Kitchen East")];
  for (const platform of ["threads", "instagram"]) {
    const result = await collectPublicProfileDiscoveryDrafts({
      venues: [{ place: branch, profiles: [lookup(platform, "example", "Kitchen")] }],
    }, async () => page(html("example", posts, platform, true)));
    assert.deepEqual(result.draft.venues, []);
    assert.equal(result.profiles[0]?.status, "access_required");
  }
  const result = await collectPublicProfileDiscoveryDrafts({
    venues: [{ place: branch, profiles: [lookup("threads", "example", "Kitchen")] }],
  }, async () => page(title("example") + script({ __bbox: { result: { data: {
    mediaData: { edges: [{ node: { thread_items: posts.map(value => ({ post: value })) } }] },
  } } } })));
  assert.deepEqual(result.draft.venues, []);
  assert.equal(result.profiles[0]?.status, "no_readable_posts");
});

test("links split Instagram profile and timeline fragments through the exact account ID", async () => {
  const fragment = (owner: unknown) => ({
    __bbox: { result: { data: { xig_user_by_username: owner } } },
  });
  const posts = (id: string, code: string) => fragment({ id, polaris_ordered_timeline_connection: {
    edges: [{ node: post(code, "example", "Kitchen East") }],
  } });
  const responseBody = title("example") + [
    fragment({ id: "123", username: "example", is_private: false }),
    posts("456", "OtherAccount"),
    posts("123", "ExactAccount"),
  ].map(item => script(item)).join("");
  const result = await collectPublicProfileDiscoveryDrafts({
    venues: [{ place: branch, profiles: [lookup("instagram", "example", "Kitchen")] }],
  }, async () => page(responseBody));
  assert.deepEqual(result.draft.venues[0]?.candidates.map(p => p.sourceURL), ["https://www.instagram.com/reel/ExactAccount/"]);
});

test("classifies a first-party login redirect without following it or exposing its location", async () => {
  const result = await collectPublicProfileDiscoveryDrafts({
    venues: [{ place: branch, profiles: [lookup("instagram", "example", "Kitchen"), lookup("threads", "example", "Kitchen")] }],
  }, async (url, init) => {
    assert.equal(init?.redirect, "manual");
    const location = String(url).includes("instagram") ? "/accounts/login/?tracking=private-redirect" : "https://elsewhere.test/login";
    return new Response(null, { status: 302, headers: { location } });
  });
  assert.deepEqual(result.profiles.map(p => p.status), ["access_required", "unavailable"]);
  assert.deepEqual(result.draft.venues, []);
  assert.doesNotMatch(JSON.stringify(result), /private-redirect|elsewhere/);
});

test("rejects malformed scope and over-budget profiles before any request", async () => {
  const inspect = async () => assert.fail("Invalid batch must not reach a provider");
  for (const [place, profiles] of [
    [{ ...branch, privateNote: "value" }, [lookup("threads", "example", "Kitchen")]],
    [branch, [lookup("instagram", "../accounts", "Kitchen")]],
    [branch, [lookup("threads", "example", "")]],
    [branch, Array.from({ length: 31 }, (_, i) => lookup("threads", `example${i}`, "Kitchen"))],
  ]) {
    await assert.rejects(collectPublicProfileDiscoveryDrafts({ venues: [{ place, profiles }] }, inspect));
  }
  const queries = Array.from({ length: 18 }, (_, i) => lookup("threads", `example${i}`, "Kitchen"));
  const otherQueries = Array.from({ length: 18 }, (_, i) => lookup("instagram", `example${i}`, "Kitchen"));
  await assert.rejects(collectPublicProfileDiscoveryDrafts({
    venues: [{ place: branch, profiles: queries }, { place: otherBranch, profiles: otherQueries }],
  }, inspect));
});
