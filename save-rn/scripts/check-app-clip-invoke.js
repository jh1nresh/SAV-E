#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "../..");

// Harbor Oven Pizza is not in-repo. Quarter Sheets is the LA pizza fixture
// already used by SocialPlacePipelineTests (1305 Portia St, 34.0779, -118.2543).
const invokePlace = {
  id: "quarter-sheets-pizza-club",
  name: "Quarter Sheets Pizza Club",
  address: "1305 Portia St, Los Angeles, CA 90026",
  lat: 34.0779,
  lng: -118.2543,
  category: "Food",
  rating: 4.6,
  reviewCount: 412,
  priceRange: "$$",
  hours: "Wed-Sun dinner",
  sourceLabel: "Google",
  sourceURL: "https://www.google.com/maps/place/Quarter+Sheets+Pizza+Club",
  photoURLs: [],
  note: "Save this for a slow dinner night",
};

const invokeToken = Buffer.from(JSON.stringify(invokePlace), "utf8")
  .toString("base64")
  .replaceAll("+", "-")
  .replaceAll("/", "_")
  .replaceAll("=", "");
const invokeURL = `https://sav-e-app.vercel.app/p/${invokeToken}`;

assert.ok(invokeToken.length >= 80, "embedded SharedPlaceData token must be >= 80 chars");
assert.ok(
  !/^[A-Za-z0-9_-]{6,32}$/.test(invokeToken),
  "invoke token must not look like a shortCode",
);
assert.notEqual(invokeURL, "https://sav-e-app.vercel.app/p/demo");

const decoded = JSON.parse(
  Buffer.from(invokeToken.replaceAll("-", "+").replaceAll("_", "/"), "base64").toString("utf8"),
);
assert.equal(decoded.name, "Quarter Sheets Pizza Club");
assert.equal(decoded.address, "1305 Portia St, Los Angeles, CA 90026");
assert.equal(decoded.lat, 34.0779);
assert.equal(decoded.lng, -118.2543);
assert.equal(decoded.category, "Food");

const projectYml = fs.readFileSync(path.join(repoRoot, "project.yml"), "utf8");
assert.match(
  projectYml,
  /SAVEClip:[\s\S]*?run:[\s\S]*?environmentVariables:[\s\S]*?_XCAppClipURL:/,
  "SAVEClip scheme must set _XCAppClipURL",
);
assert.ok(
  projectYml.includes(`_XCAppClipURL: ${invokeURL}`),
  "project.yml _XCAppClipURL must be the Quarter Sheets SharedPlaceData URL",
);

const schemePaths = [
  "SAV-E.xcodeproj/xcshareddata/xcschemes/SAVEClip.xcscheme",
  "Wanderly.xcodeproj/xcshareddata/xcschemes/SAVEClip.xcscheme",
];
for (const relativePath of schemePaths) {
  const scheme = fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
  assert.ok(scheme.includes('key = "_XCAppClipURL"'), `${relativePath} missing _XCAppClipURL`);
  assert.ok(scheme.includes(invokeURL), `${relativePath} _XCAppClipURL must match invoke URL`);
}

const expectedAssociation = {
  applinks: {
    details: [
      {
        appIDs: ["JC6858UYM9.com.wanderly.app"],
        components: [
          { "/": "/p/*", comment: "SAV-E shared place preview links" },
          { "/": "/trip/*", comment: "SAV-E shared trip preview links" },
          { "/": "/trip", comment: "Legacy SAV-E shared trip query links" },
          { "/": "/list", comment: "SAV-E collaborative list preview links" },
          { "/": "/r/*", comment: "SAV-E referral code preview links" },
          { "/": "/u/*", comment: "SAV-E referral profile preview links" },
          { "/": "/my/*", comment: "Private My SAV-E token links" },
        ],
      },
    ],
  },
  appclips: {
    apps: ["JC6858UYM9.com.wanderly.app.Clip"],
  },
};

const associationPaths = [
  "save-rn/public/.well-known/apple-app-site-association",
  "save-rn/public/apple-app-site-association",
];
for (const relativePath of associationPaths) {
  const association = JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), "utf8"));
  assert.deepEqual(association, expectedAssociation, `${relativePath} must match live Wanderly AASA`);
}

const vercel = JSON.parse(fs.readFileSync(path.join(repoRoot, "vercel.json"), "utf8"));
const headerSources = new Set((vercel.headers ?? []).map((entry) => entry.source));
assert.ok(headerSources.has("/.well-known/apple-app-site-association"));
assert.ok(headerSources.has("/apple-app-site-association"));
for (const entry of vercel.headers ?? []) {
  if (!headerSources.has(entry.source)) continue;
  if (
    entry.source === "/.well-known/apple-app-site-association" ||
    entry.source === "/apple-app-site-association"
  ) {
    assert.equal(entry.headers?.[0]?.key, "Content-Type");
    assert.equal(entry.headers?.[0]?.value, "application/json");
  }
}

const demoToken = "demo";
assert.ok(demoToken.length < 6, "demo is the known-bad 4-char fixture");
assert.equal(null, /^[A-Za-z0-9_-]{6,32}$/.test(demoToken) ? demoToken : null);

console.log(`SAVEClip invoke URL: ${invokeURL}`);
console.log("Validated SAVEClip _XCAppClipURL, AASA, and vercel.json Content-Type headers.");
