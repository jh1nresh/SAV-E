#!/usr/bin/env node

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(__dirname, "../..");
const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-in-app-browser-"));

execFileSync(
  path.join(repoRoot, "node_modules", ".bin", "tsc"),
  [
    "--ignoreConfig",
    "--target",
    "ES2022",
    "--module",
    "node16",
    "--moduleResolution",
    "node16",
    "--types",
    "node",
    "--skipLibCheck",
    "--outDir",
    outDir,
    path.join(repoRoot, "src", "inAppBrowser.ts"),
  ],
  { stdio: "inherit" },
);

const {
  isInAppShareBrowser,
  isShareFallbackPath,
  safariOpenURL,
  shareFallbackCopy,
  usesTraditionalChinese,
  publicOwnedPhotoURL,
  clipBundleId,
  smartAppBannerContent,
} = require(path.join(outDir, "inAppBrowser.js"));

assert.equal(isInAppShareBrowser("Mozilla/5.0 (iPhone) Line/14.0.0"), true);
assert.equal(isInAppShareBrowser("Mozilla/5.0 (iPhone) Instagram 192.168.1.2"), true);
assert.equal(isInAppShareBrowser("Mozilla/5.0 (iPad) MicroMessenger/8.0"), true);
assert.equal(isInAppShareBrowser("Mozilla/5.0 Safari/605.1.15"), false);
assert.equal(isInAppShareBrowser("Mozilla/5.0 iPhone Messages"), false);

assert.equal(isShareFallbackPath("https://sav-e-app.vercel.app/p/AbC123_x"), true);
assert.equal(isShareFallbackPath("https://sav-e-app.vercel.app/list?c=AbC123_x"), true);
assert.equal(isShareFallbackPath("https://sav-e-app.vercel.app/trip/abc"), false);

assert.equal(
  safariOpenURL("https://sav-e-app.vercel.app/p/AbC123_x", "Mozilla/5.0 (iPhone) Line/14.0.0"),
  "https://sav-e-app.vercel.app/p/AbC123_x?openExternalBrowser=1",
);
assert.equal(
  safariOpenURL("https://sav-e-app.vercel.app/p/AbC123_x", "Safari/605"),
  null,
);
for (const app of ["Line/14.0.0", "Instagram", "MicroMessenger/8.0"]) {
  assert.equal(isInAppShareBrowser(`Mozilla/5.0 (Linux; Android 14) ${app}`), false);
}
for (const app of ["Instagram", "MicroMessenger/8.0"]) {
  assert.equal(safariOpenURL("https://sav-e-app.vercel.app/p/AbC123_x", `Mozilla/5.0 (iPhone) ${app}`), null);
}
assert.equal(isInAppShareBrowser("Mozilla/5.0 (Macintosh) Mobile/15E148 Instagram"), true);

assert.equal(usesTraditionalChinese("zh-Hant-TW"), true);
assert.match(shareFallbackCopy("zh-Hant").button, /Safari/);
assert.match(shareFallbackCopy("en").button, /Open in Safari/);
assert.match(shareFallbackCopy("zh-Hant").note, /完整 Savvy App.*登入.*確認/);
assert.match(shareFallbackCopy("en").note, /sign in to the full Savvy App and confirm/);
for (const language of ["zh-Hant", "en"]) {
  assert.doesNotMatch(Object.values(shareFallbackCopy(language)).join(" "), /免安裝就能存|no install/i);
}
assert.equal(publicOwnedPhotoURL([
  "https://maps.googleapis.com/maps/api/place/photo?photo_reference=x",
  "https://example.com/own.jpg",
]), "https://example.com/own.jpg");
assert.equal(publicOwnedPhotoURL([
  "https://maps.googleapis.com/maps/api/place/photo?photo_reference=x",
]), null);

assert.equal(clipBundleId, "com.wanderly.app.Clip");
const project = fs.readFileSync(path.join(workspaceRoot, "project.yml"), "utf8");
assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER: com\.wanderly\.app\.Clip/);
assert.equal(
  smartAppBannerContent,
  "app-id=6769216556, app-clip-bundle-id=com.wanderly.app.Clip",
);
assert.doesNotMatch(smartAppBannerContent, /app-clip-display/);

const patch = fs.readFileSync(path.join(repoRoot, "scripts/patch-web-bundle.js"), "utf8");
assert.match(patch, /app-clip-bundle-id=\$\{smartBannerAppClipBundleId\}/);
assert.match(patch, /const appClipBundleId = "com\.wanderly\.app\.Clip"/);
const routeWriter = patch.slice(
  patch.indexOf("function writeShareRouteFallbacks()"),
  patch.indexOf("function writeAppClipSmartBanner()"),
);
const copiedRoutes = [];
vm.runInNewContext(`${routeWriter}\nwriteShareRouteFallbacks();`, {
  path,
  distRoot: "/fixture-export",
  fs: {
    existsSync: () => true,
    mkdirSync: () => {},
    copyFileSync: (source, destination) => copiedRoutes.push([source, destination]),
  },
});
assert.ok(copiedRoutes.some(([source, destination]) =>
  source === "/fixture-export/index.html" && destination === "/fixture-export/p/index.html"));
assert.doesNotMatch(patch, /app-clip-display=card/);

const fallback = fs.readFileSync(path.join(repoRoot, "src/ShareClipFallback.tsx"), "utf8");
assert.match(fallback, /testID="web.clip.fallback"/);
assert.doesNotMatch(fallback, /Save to my Savvy/);
assert.doesNotMatch(fallback, /googleapis/);

console.log("Validated in-app browser fallback detection and Smart App Banner bundle id.");
