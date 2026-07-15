#!/usr/bin/env node

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-friend-share-"));

execFileSync(
  path.join(repoRoot, "node_modules", ".bin", "tsc"),
  [
    "--target",
    "ES2022",
    "--module",
    "commonjs",
    "--moduleResolution",
    "node",
    "--skipLibCheck",
    "--outDir",
    outDir,
    path.join(repoRoot, "src", "models.ts"),
    path.join(repoRoot, "src", "sharedTrip.ts"),
    path.join(repoRoot, "src", "api.ts"),
  ],
  { stdio: "inherit" },
);

const {
  friendShareEventBody,
  placeCreateBody,
  runSingleFlight,
  sharedPlaceReceiptFromResponse,
} = require(path.join(outDir, "api.js"));
const {
  decodePlaceLink,
  findMatchingBookmark,
  sanitizeSharedPlaceData,
  sharedPlaceShortCode,
  sharedPlaceToBookmark,
} = require(path.join(outDir, "sharedTrip.js"));

async function main() {

const payload = {
  id: "place-1",
  name: "Kato",
  address: "777 S Alameda St, Los Angeles, CA",
  lat: 34.04,
  lng: -118.23,
  category: "Food",
  sourceLabel: "Instagram",
  sourceURL: "https://www.instagram.com/reel/kato/",
  photoURLs: [],
  note: "Try the tasting menu",
};

const embeddedToken = Buffer.from(JSON.stringify(payload), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${embeddedToken}`).name, "Kato");
const invalidGeoToken = Buffer.from(JSON.stringify({ ...payload, lat: 90.1 }), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${invalidGeoToken}`), null);
assert.equal(sharedPlaceShortCode(`https://sav-e-app.vercel.app/p/${embeddedToken}`), null);
assert.equal(sharedPlaceShortCode("https://sav-e-app.vercel.app/p/AbC123_x"), "AbC123_x");
assert.equal(sharedPlaceShortCode("https://sav-e-app.vercel.app/p/short"), null);
assert.equal(sharedPlaceShortCode(`https://sav-e-app.vercel.app/p/${"x".repeat(33)}`), null);

const unsafePayload = {
  ...payload,
  sourceURL: "https://user:secret@example.com/private",
  photoURLs: [
    "https://user:secret@example.com/private.jpg",
    "https://example.com/safe.jpg",
    "https://example.com/ignored.jpg",
  ],
  note: "Venue name: internal extraction clue",
};
const unsafeToken = Buffer.from(JSON.stringify(unsafePayload), "utf8").toString("base64url");
const sanitizedEmbedded = decodePlaceLink(`https://sav-e-app.vercel.app/p/${unsafeToken}`);
assert.equal(sanitizedEmbedded.sourceURL, null);
assert.deepEqual(sanitizedEmbedded.photoURLs, ["https://example.com/safe.jpg"]);
assert.equal(sanitizedEmbedded.note, null);
assert.equal(sanitizeSharedPlaceData({ ...payload, note: "😀".repeat(91) }).note, null);
assert.equal(sanitizeSharedPlaceData({ ...payload, note: "one\ntwo\nthree" }).note, null);
const querySecretPayload = sanitizeSharedPlaceData({
  ...payload,
  sourceURL: "https://example.com/source?token=secret#fragment",
  photoURLs: ["https://example.com/photo.jpg?signature=secret#fragment"],
});
assert.equal(querySecretPayload.sourceURL, "https://example.com/source");
assert.deepEqual(querySecretPayload.photoURLs, ["https://example.com/photo.jpg"]);
const oversizedToken = Buffer.from(JSON.stringify({ ...payload, name: "x".repeat(20_000) }), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${oversizedToken}`), null);

const verified = sharedPlaceReceiptFromResponse({
  code: "AbC123_x",
  url: "https://sav-e-app.vercel.app/p/AbC123_x",
  payload: { ...payload, id: "" },
  sender: { display_name: "Alice", handle: "alice_eats" },
  expires_at: "2026-08-14T00:00:00Z",
});
assert.deepEqual(verified.sender, { displayName: "Alice", handle: "alice_eats" });

const sanitizedReceipt = sharedPlaceReceiptFromResponse({
  code: "Unsafe1",
  url: "https://sav-e-app.vercel.app/p/Unsafe1",
  payload: { ...unsafePayload, note: "x".repeat(181) },
});
assert.equal(sanitizedReceipt.payload.sourceURL, null);
assert.deepEqual(sanitizedReceipt.payload.photoURLs, ["https://example.com/safe.jpg"]);
assert.equal(sanitizedReceipt.payload.note, null);

const generic = sharedPlaceReceiptFromResponse({
  code: "Generic1",
  url: "https://sav-e-app.vercel.app/p/Generic1",
  payload: { ...payload, id: "", sender: { display_name: "Payload forgery" } },
  sender: null,
});
assert.equal(generic.sender, undefined, "generic candidate links must stay neutral");
assert.throws(
  () => sharedPlaceReceiptFromResponse({
    code: "BadGeo1",
    url: "https://sav-e-app.vercel.app/p/BadGeo1",
    payload: { ...payload, lat: 999 },
  }),
  /malformed/,
);

const bookmark = sharedPlaceToBookmark(verified.payload, verified.sender.displayName);
assert.equal(bookmark.recommender, "Alice");
assert.equal(findMatchingBookmark([bookmark], { ...bookmark, id: "retry" }).id, bookmark.id);

const genericPlaceBody = placeCreateBody(bookmark);
assert.equal("friend_share_code" in genericPlaceBody, false);
assert.equal(placeCreateBody(bookmark, "AbC123_x").friend_share_code, "AbC123_x");
assert.throws(() => placeCreateBody(bookmark, "  "), /must not be empty/);

let mintCount = 0;
let releaseMint;
const inFlight = { current: null };
const mint = () => {
  mintCount += 1;
  return new Promise((resolve) => {
    releaseMint = resolve;
  });
};
const firstMint = runSingleFlight(inFlight, mint);
const secondMint = runSingleFlight(inFlight, mint);
assert.equal(mintCount, 1, "concurrent auth callers must share one guest mint");
releaseMint("guest-a");
assert.deepEqual(await Promise.all([firstMint, secondMint]), ["guest-a", "guest-a"]);
assert.equal(inFlight.current, null);
const failedFlight = { current: null };
await assert.rejects(
  runSingleFlight(failedFlight, async () => { throw new Error("mint failed"); }),
  /mint failed/,
);
assert.equal(failedFlight.current, null, "a failed mint must release the single-flight gate");

assert.deepEqual(friendShareEventBody("friend_share_receipt_opened"), {
  event_type: "friend_share_receipt_opened",
  surface: "web",
});
assert.deepEqual(friendShareEventBody("friend_share_open_failed", { reasonCode: "expired" }), {
  event_type: "friend_share_open_failed",
  surface: "web",
  reason_code: "expired",
});
const recipientPlaceId = "550e8400-e29b-41d4-a716-446655440000";
assert.deepEqual(friendShareEventBody("friend_share_open_failed", { reasonCode: "network_error" }), {
  event_type: "friend_share_open_failed",
  surface: "web",
  reason_code: "network_error",
});
assert.throws(
  () => friendShareEventBody("friend_share_saved", { recipientPlaceId }),
  /not allowed/,
);
assert.throws(
  () => friendShareEventBody("friend_share_save_tapped", { recipientPlaceId }),
  /not allowed/,
);

const appSource = fs.readFileSync(path.join(repoRoot, "App.tsx"), "utf8");
assert.equal(appSource.includes('recordIncomingFriendShareEvent(incomingPlaceCode, "friend_share_saved"'), false);
assert.equal(appSource.includes('recordIncomingFriendShareEvent(incomingPlaceCode, "friend_share_duplicate_blocked"'), false);
const apiSource = fs.readFileSync(path.join(repoRoot, "src", "api.ts"), "utf8");
assert.doesNotMatch(appSource, /recordPublicFriendShareEvent/);
assert.match(appSource, /recordIncomingFriendShareEvent\(code, "friend_share_receipt_opened"\)/);
assert.match(appSource, /recordIncomingFriendShareEvent\(code, "friend_share_open_failed", \{ reasonCode \}\)/);
assert.match(appSource, /incomingPlaceSaveStateRef\.current !== "idle"/);
assert.match(appSource, /disabled=\{incomingPlaceSaveState !== "idle"\}/);
assert.match(appSource, /createPlace\(auth, place, friendShareCode\)/);
assert.match(appSource, /updateIncomingPlaceSaveState\(result\.outcome\)/);
assert.doesNotMatch(appSource, /recipientPlaceId: result\.place\.id/);
assert.match(appSource, /guestSessionRequestRef = useRef<Promise<GuestSession> \| null>/);
assert.match(apiSource, /"\/v0\/friend-share-events"/);

console.log("Validated legacy, short-code, sender, duplicate, and event receipt fixtures.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
