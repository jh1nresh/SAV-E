import assert from "node:assert/strict";
import { test } from "node:test";
import {
  classifyTaipeiStreetCaption, publicTaipeiStreetInventory, verifyPublicTaipeiStreetCandidate,
} from "./publicDiscoveryStreetEvidence.js";
import type { PublicDiscoveryPlace } from "./publicDiscovery.js";

const place: PublicDiscoveryPlace = {
  provider: "google_places", providerPlaceID: "FixtureBranch", name: "測試茶點店",
  address: "108臺灣臺北市萬華區貴陽街二段116號", latitude: 25.04, longitude: 121.50,
  coordinateSystem: "WGS84", category: "food",
};
const addr = "台北市萬華區貴陽街二段116號";
const caption = `測試茶點店的菠蘿包做得很好。地址：${addr}，電話可洽店家。`;
const expected = publicTaipeiStreetInventory([place])(place);

test("matches the exact name and full Taipei street address through safe normalization", () => {
  assert.equal(classifyTaipeiStreetCaption(caption, place, expected), "exact_street_match");
  assert.equal(classifyTaipeiStreetCaption(caption.replace("116", "１１６"), place, expected), "exact_street_match");
  const unit = { ...place, address: addr + "之1" };
  assert.equal(classifyTaipeiStreetCaption(caption.replace("116號", "116-1號"), unit, expected), "exact_street_match");
  assert.equal(classifyTaipeiStreetCaption(caption.replace("測試茶點店", "蜜糖甜點店"), place, expected), "name_unconfirmed");
});

test("rejects adjacent numbers, omitted lanes and addresses of a different branch", () => {
  for (const other of [addr.replace("116", "1160"), addr+"之1", addr.replace("116", "116巷2"),
    addr.replace("貴陽街二段", "貴陽街一段"), addr.replace("萬華區", "中正區")]) {
    assert.equal(classifyTaipeiStreetCaption(caption.replace(addr, other), place, expected), "different_branch", other);
  }
  assert.equal(classifyTaipeiStreetCaption(caption.replace("台北市萬華區", ""), place, expected), "no_exact_address");
});

test("holds venue changes, multi-location posts, stall units and a shared street number", () => {
  assert.equal(classifyTaipeiStreetCaption(caption+"這是搬家前的門面。", place, expected), "time_or_relocation");
  assert.equal(classifyTaipeiStreetCaption(caption+"另一間：台北市萬華區貴陽街二段192號。", place, expected), "ambiguous_address");
  assert.equal(classifyTaipeiStreetCaption(caption+"分店：新北市三重區文化路2號。", place, expected), "ambiguous_address");
  assert.equal(classifyTaipeiStreetCaption(caption+"另一門市：貴陽街一段23號。", place, expected), "ambiguous_address");
  assert.equal(classifyTaipeiStreetCaption(caption+"旗艦店：新竹縣竹北市光明六路東一段243號。", place, expected), "ambiguous_address");
  assert.equal(classifyTaipeiStreetCaption(caption+"聖露西亞美食節同步推出。", place, expected), "time_or_relocation");
  assert.equal(classifyTaipeiStreetCaption(caption.replace(addr, addr+"對面"), place, expected), "ambiguous_address");
  const neighbor = { ...place, providerPlaceID: "Neighbor", category: "mall", address: addr+"2樓" };
  const inventory = publicTaipeiStreetInventory([place, neighbor]);
  assert.equal(classifyTaipeiStreetCaption(caption, place, inventory(place)), "shared_address");
  assert.equal(classifyTaipeiStreetCaption(caption, {...place,address:"Taipei, Road No.116"}, expected), "unsupported_address");
});

test("checks an exact Instagram or Threads embed, never a hidden match or edited author", () => {
  const ig = "https://www.instagram.com/p/StreetFixture/";
  const html = `<div class="Embed"><a class="EmbeddedMedia" href="${ig}">View</a>
    <div class="Caption"><a class="CaptionUsername" href="/example/">example</a>${caption}</div></div>`;
  const request = { html, platform:"instagram" as const, sourceURL:ig, place, placesAtAddress:expected };
  const answer = verifyPublicTaipeiStreetCandidate(request);
  assert.equal(answer.status, "exact_street_match");
  assert.ok("contentFingerprint" in answer && /^[a-f0-9]{64}$/.test(answer.contentFingerprint??""));
  assert.doesNotMatch(JSON.stringify(answer), /菠蘿包|CaptionUsername/);
  assert.equal(verifyPublicTaipeiStreetCandidate({...request,author:"unmatched"}).status, "original_unavailable");
  const hidden = html.replace(addr, `<span hidden>${addr}</span>`);
  assert.equal(verifyPublicTaipeiStreetCandidate({...request,html:hidden}).status, "no_exact_address");
  const th = "https://www.threads.com/@example/post/StreetFixture";
  const threads = `<div class="Embed"><div class="LinkContainer"><a href="${th}">View</a></div>
    <div class="AuthorIdentity"><a class="HeaderLink" href="/@example">example</a></div>
    <span class="BodyTextContainer">${caption}</span></div>`;
  assert.equal(verifyPublicTaipeiStreetCandidate({...request,html:threads,platform:"threads",sourceURL:th}).status,"exact_street_match");
  const different = threads.replace('href="/@example"', 'href="/@different"');
  assert.equal(verifyPublicTaipeiStreetCandidate({
    ...request, html: different, platform: "threads", sourceURL: th, author: "different",
  }).status, "original_unavailable");
});

test("Instagram comments never contribute author evidence or a venue address", () => {
  const ig = "https://www.instagram.com/p/StreetFixture/";
  const shell = (body: string) => `<div class="Embed"><a class="EmbeddedMedia" href="${ig}">Read</a>
    <div class="Caption">${body}</div></div>`;
  const comments = `<div class="Layout CaptionComments Extra"><span>${caption}</span></div>`;
  const profile = '<a class="CaptionUsername" href="/example/">example</a>';
  const base = { platform: "instagram" as const, sourceURL: ig, place, placesAtAddress: expected };
  const authorCaption = "這是原作者留的一段長文字，內容沒有店家地址。";
  assert.equal(verifyPublicTaipeiStreetCandidate({ ...base, html: shell(profile + authorCaption + comments) }).status, "no_exact_address");
  assert.equal(verifyPublicTaipeiStreetCandidate({
    ...base, html: shell(caption + `<div class="CaptionComments">${profile}</div>`),
  }).status, "original_unavailable");
});
