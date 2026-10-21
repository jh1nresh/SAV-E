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
