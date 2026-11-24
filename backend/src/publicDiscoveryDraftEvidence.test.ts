import assert from "node:assert/strict";
import test from "node:test";
import { checkStreetDrafts } from "./publicDiscoveryDraftEvidence.js";
import type { PublicDiscoveryPlace } from "./publicDiscovery.js";

const now = new Date("2026-11-23T08:00:00.000Z");
const place: PublicDiscoveryPlace = { provider: "apple_maps", providerPlaceID: "BranchA", name: "測試茶點店",
  address: "臺北市萬華區貴陽街二段116號", latitude: 25.04, longitude: 121.50, coordinateSystem: "WGS84", category: "food" };
const noArchive = { venues: [] };
const ig = (code: string) => ({ platform: "instagram", sourceURL: `https://www.instagram.com/p/${code}/`,
  authorHandle: null, title: "", review: null });
const caption = `今天去${place.name}吃早點。地址：${place.address}。`;
const embed = (url: string, text: string) =>
  `<div class="Embed"><a class="EmbeddedMedia" href="${url}">Read original</a>
  <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>${text}</div></div>`;

test("leaves an address shared by two storefronts and an unknown place unverified without reading originals", async () => {
  const neighbor = { ...place, providerPlaceID: "Neighbor", address: place.address + "2樓" };
  const unsupported = { ...place, providerPlaceID: "Unnumbered", address: "Wanhua, Taipei" };
  const moved = { ...place, latitude: 26 };
  const report = [
    { place, candidates: [ig("A")] },
    { place: moved, candidates: [ig("B")] },
    { place: unsupported, candidates: [ig("C")] },
  ];
  const result = await checkStreetDrafts(noArchive, report, [place, neighbor, unsupported], {
    now, fetchEmbed: async () => assert.fail("Preflight rejections should not read an original"),
  });
  assert.equal(result.counts.placeMismatch, 1);
  assert.deepEqual(result.counts.outcomes, { shared_address: 1, unsupported_address: 1 });
  assert.equal(result.counts.checked, 0);
  assert.deepEqual(result.verified, []);
});

test("keeps exact canonical associations, rejects competing branch claims, and retains only review evidence", async () => {
  const other = { ...place, providerPlaceID: "BranchB", address: place.address.replace("116", "120") };
  const visible = ig("CHECKED");
  const shared = ig("CLAIMED");
  const calls: string[] = [];
  const result = await checkStreetDrafts(noArchive, [
    { place, candidates: [visible, shared, visible] },
    { place: other, candidates: [shared] },
  ], [place, other], {
    now, fetchEmbed: async url => { calls.push(url); return embed(visible.sourceURL, caption); },
  });
  assert.equal(calls.length, 1);
  assert.equal(result.counts.branchConflict, 2);
  assert.equal(result.counts.admitted, 1);
  const [reviewed] = result.verified;
  assert.deepEqual(reviewed?.place, place);
  assert.equal(reviewed?.candidates[0]?.sourceURL, visible.sourceURL);
  assert.match(reviewed?.candidates[0]?.review.contentFingerprint ?? "", /^[a-f0-9]{64}$/);
  assert.doesNotMatch(JSON.stringify(result), /今天去|CaptionUsername/);
});

test("a draft with a competing Threads author cannot block other valid originals", async () => {
  const wrong = { ...ig("WRONG"), platform: "threads",
    sourceURL: "https://www.threads.com/@example/post/WRONG", authorHandle: "different" };
  const right = ig("RIGHT");
  const calls: string[] = [];
  const result = await checkStreetDrafts(noArchive, [{ place, candidates: [wrong, right] }], [place], {
    now, fetchEmbed: async url => {
      calls.push(url);
      if (url.includes("RIGHT")) return embed(right.sourceURL, caption);
      return `<div class="Embed"><div class="LinkContainer"><a href="${wrong.sourceURL}">Read</a></div>
        <div class="AuthorIdentity"><a class="HeaderLink" href="/@different">different</a></div>
        <span class="BodyTextContainer">${caption}</span></div>`;
    },
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0]!, /RIGHT/);
  assert.equal(result.counts.admitted, 1);
  assert.deepEqual(result.counts.outcomes, { invalid_attribution: 1, exact_street_match: 1 });
});

test("retained author claims for the same original do not depend on report order", async () => {
  const source = ig("RENAMED");
  const report = (authorHandle: string | null) => ({ place, candidates: [{ ...source, authorHandle }] });
  const old = report("oldhandle");
  const current = report("Example");
  let calls = 0;
  const fetchEmbed = async () => { calls++; return embed(source.sourceURL, caption); };
  for (const drafts of [[old, current], [current, old], [old, report(null)]]) {
    const result = await checkStreetDrafts(noArchive, drafts, [place], { now, fetchEmbed });
    assert.equal(result.counts.checked, 1);
    assert.equal(result.counts.admitted, 1);
    assert.equal(result.verified[0]?.candidates[0]?.authorHandle, "example");
  }
  const unmatched = await checkStreetDrafts(noArchive, [old], [place], { now, fetchEmbed });
  assert.equal(unmatched.counts.admitted, 0);
  assert.deepEqual(unmatched.counts.outcomes, { original_unavailable: 1 });
  assert.equal(calls, 4);
});

test("a provider cooldown stops new reads and the next window continues after the recorded cursor", async () => {
  const report = [{ place, candidates: [ig("FIRST"), ig("NEXT")] }];
  const calls: string[] = [];
  const denied = await checkStreetDrafts(noArchive, report, [place], { now, fetchEmbed: async url => {
    calls.push(url);
    throw new Error("HTTP 429");
  } });
  assert.equal(calls.length, 1);
  assert.match(calls[0]!, /FIRST/);
  assert.equal(denied.counts.deferred, 1);
  assert.equal(denied.counts.backoffUntil, now.getTime() + 15 * 60_000);
  const after = await checkStreetDrafts(noArchive, report, [place], {
    now: new Date(denied.counts.backoffUntil), cursor: denied.counts.nextCursor,
    backoffUntil: denied.counts.backoffUntil, maxOriginals: 1, fetchEmbed: async url => {
      calls.push(url);
      return embed(ig("NEXT").sourceURL, caption);
    },
  });
  assert.equal(after.counts.admitted, 1);
  assert.match(calls[1]!, /NEXT/);
});

test("a Taipei destination requires the exact visible official link and its own name in the public original", async () => {
  const park = { ...place, providerPlaceID: "Park", category: "attractions", name: "象山公園", address: "Taipei" };
  const url = "https://www.travel.taipei/zh-tw/attraction/details/380";
  const officialFeatures = [{ provider: park.provider, providerPlaceID: park.providerPlaceID,
    expectedName: park.name, catalogID: "Attraction_379000000A_000380", names: [park.name], authorityURLs: [url] }];
  const draft = ig("PARK");
  const lookup = (body: string) => checkStreetDrafts(noArchive, [{ place: park, candidates: [draft] }], [park], {
    now, officialFeatures, fetchEmbed: async () => embed(draft.sourceURL, body),
  });
  const body = "台北信義區象山公園有步道和休息區。";
  const link = `<a href="${url}">臺北旅遊網</a>`;
  assert.equal((await lookup(body + link)).counts.admitted, 1);
  assert.deepEqual((await lookup(body + link.replace("<a ", "<a hidden "))).counts.outcomes, { no_catalog_link: 1 });
  assert.deepEqual((await lookup(body + link + link.replace("380", "381"))).counts.outcomes, { multiple_catalog_features: 1 });
  assert.deepEqual((await lookup("台北信義區象山公園附近的另一個景點。 " + link)).counts.outcomes, { feature_name_unconfirmed: 1 });
  for (const nearby of [
    "象山公園的附近有一家咖啡店，今天專程來吃甜點。",
    "今天去鄰近象山公園的咖啡店。",
    "咖啡店在（象山公園）的對面。",
    "The cafe is near 象山公園.",
  ]) {
    const result = await lookup(nearby + " " + link);
    assert.deepEqual(result.counts.outcomes, { feature_name_unconfirmed: 1 }, nearby);
    assert.deepEqual(result.verified, []);
  }
  assert.equal((await lookup("象山公園的附近有一家咖啡店。今天走進象山公園散步。" + link)).counts.admitted, 1);
});

test("a shorter feature alias inherits the context of its full name", async () => {
  const zoo = { ...place, providerPlaceID: "ZooFixture", category: "attractions", name: "臺北市立動物園", address: "Taipei" };
  const url = "https://www.travel.taipei/zh-tw/attraction/details/386";
  const officialFeatures = [{ provider: zoo.provider, providerPlaceID: zoo.providerPlaceID,
    expectedName: zoo.name, catalogID: "Attraction_379000000A_000386",
    names: [zoo.name, "市立動物園"], authorityURLs: [url] }];
  const draft = ig("ZooFixture");
  const lookup = (text: string) => checkStreetDrafts(noArchive, [{ place: zoo, candidates: [draft] }], [zoo], {
    now, officialFeatures, fetchEmbed: async () => embed(draft.sourceURL, `${text}<a href="${url}">官方網站</a>`),
  });
  const nearby = "今天去鄰近臺北市立動物園的咖啡店。";
  assert.deepEqual((await lookup(nearby)).counts.outcomes, { feature_name_unconfirmed: 1 });
  assert.equal((await lookup(nearby + "下午走進市立動物園。")).counts.admitted, 1);
});

test("a travel-time landmark or unvisited place does not produce venue evidence", async () => {
  const street = ig("StreetLandmark");
  const park = { ...place, providerPlaceID: "ParkLandmark", category: "attractions", name: "象山公園", address: "Taipei" };
  const parkPost = ig("ParkLandmark");
  const authority = "https://www.travel.taipei/zh-tw/attraction/details/380";
  const feature = { provider: park.provider, providerPlaceID: park.providerPlaceID, expectedName: park.name,
    catalogID: "Attraction_379000000A_000380", names: [park.name], authorityURLs: [authority] };
  const articles = (store: string, attraction: string) => checkStreetDrafts(noArchive,
    [{ place, candidates: [street] }, { place: park, candidates: [parkPost] }], [place, park], {
      now, officialFeatures: [feature],
      fetchEmbed: async url => url.includes("StreetLandmark")
        ? embed(street.sourceURL, store)
        : embed(parkPost.sourceURL, attraction + `<a href="${authority}">官方網站</a>`),
    });
  const falseEvidence = await articles(
    `今天只去另一家咖啡店。步行五分鐘可到${place.name}，地標是${place.address}，我們沒有去。`,
    "今天只去了一間咖啡店，走路五分鐘可到象山公園，但我們沒去公園。"
  );
  assert.deepEqual(falseEvidence.verified, []);
  assert.deepEqual(falseEvidence.counts.outcomes, { name_unconfirmed: 1, feature_name_unconfirmed: 1 });
  const direct = await articles(caption, "從捷運走了五分鐘抵達象山公園散步。");
  assert.equal(direct.counts.admitted, 2);
});
