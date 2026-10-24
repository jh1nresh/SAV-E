import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = fileURLToPath(new URL("../../", import.meta.url));

function walkFiles(relativeDir: string, extensions: Set<string>): string[] {
  const abs = join(repoRoot, relativeDir);
  return readdirSync(abs, { recursive: true, encoding: "utf8" })
    .filter((name) => extensions.has(extname(name).toLowerCase()))
    .map((name) => join(relativeDir, name));
}

test("founder Google photo cleanup SQL is transactional and non-destructive", () => {
  const cleanup = readFileSync(new URL("../sql/google-photo-url-cleanup.sql", import.meta.url), "utf8");
  const verify = readFileSync(new URL("../sql/google-photo-url-verify.sql", import.meta.url), "utf8");
  const runbook = readFileSync(new URL("../../docs/operations/google-photo-url-cleanup.md", import.meta.url), "utf8");
  assert.match(cleanup, /^\s*begin;/m);
  assert.match(cleanup, /^\s*commit;/m);
  assert.doesNotMatch(cleanup, /drop\s+(table|column)/i);
  assert.match(cleanup, /business_photo_urls = '\{\}'/);
  assert.match(cleanup, /source_image_url = null/);
  assert.match(cleanup, /googleusercontent\.com%\/places\/%/);
  assert.match(cleanup, /googleusercontent\.com%\/place-photos\/%/);
  assert.match(cleanup, /googleusercontent\.com%\/p\/%/);
  assert.match(cleanup, /googleusercontent\.com%\/gps-cs-s\/%/);
  assert.match(cleanup, /googleusercontent\.com%\/gps-proxy\/%/);
  assert.match(verify, /googleusercontent\.com%\/places\/%/);
  assert.match(verify, /googleusercontent\.com%\/place-photos\/%/);
  assert.match(verify, /googleusercontent\.com%\/p\/%/);
  assert.match(verify, /googleusercontent\.com%\/gps-cs-s\/%/);
  assert.match(verify, /googleusercontent\.com%\/gps-proxy\/%/);
  assert.match(verify, /leftover_business_photo_urls/);
  assert.match(verify, /leftover_google_source_image_urls/);
  assert.match(runbook, /railway run --service save-backend/);
  assert.match(runbook, /pg_dump/);
  assert.match(runbook, /select id, business_photo_urls/);
  assert.match(runbook, /## 1\. BACKUP/);
  assert.match(runbook, /## 2\. CLEANUP/);
  assert.match(runbook, /## 3\. VERIFY/);
  assert.match(runbook, /Agents and this PR must \*\*not\*\* run/);

  const evidence = readFileSync(
    new URL("../../docs/evidence/pr306/README.md", import.meta.url),
    "utf8",
  );
  assert.match(evidence, /googleusercontent\.com%\/places\/%/);
  assert.match(evidence, /googleusercontent\.com%\/place-photos\/%/);
  assert.match(evidence, /googleusercontent\.com%\/p\/%/);
  assert.match(evidence, /googleusercontent\.com%\/gps-cs-s\/%/);
  assert.match(evidence, /googleusercontent\.com%\/gps-proxy\/%/);
  assert.match(evidence, /Do not treat avatar paths `\/a\/` or `\/a-\/`/);
});

test("public city atlas pages do not embed Google Places photo hosts", () => {
  const files = [
    ...walkFiles("SAV-E/Views/Atlas", new Set([".swift"])),
    ...walkFiles("Prototypes/AtlasPostcard", new Set([".md", ".swift", ".json"])),
    ...walkFiles("save-rn/src", new Set([".ts", ".tsx", ".js"])),
  ];
  assert.ok(files.length > 0, "expected public city page sources");
  const forbidden = /googleapis\.com|maps\.googleapis\.com|\/maps\/api\/place\/photo|photo_reference=/i;
  for (const name of files) {
    const text = readFileSync(join(repoRoot, name), "utf8");
    assert.doesNotMatch(text, forbidden, name);
  }
});

test("G7 N/A: no public unauthenticated city page route", () => {
  const vercel = readFileSync(join(repoRoot, "vercel.json"), "utf8");
  assert.doesNotMatch(vercel, /"source":\s*"\/city/);
  const saveRn = walkFiles("save-rn/src", new Set([".ts", ".tsx", ".js"]));
  for (const name of saveRn) {
    const text = readFileSync(join(repoRoot, name), "utf8");
    assert.doesNotMatch(text, /path:\s*['"`]\/city/, name);
    assert.doesNotMatch(text, /business_photo_urls/, name);
    assert.doesNotMatch(text, /photo_reference/, name);
  }
});
