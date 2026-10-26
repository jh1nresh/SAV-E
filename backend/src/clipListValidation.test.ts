import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import ts from "typescript";

// Execute the actual private handler and validator without booting server.ts
// or connecting a database. Valid input stops at the mocked connection boundary.
const source = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
const start = source.indexOf("async function saveClipListPlaces(");
const end = source.indexOf("async function handlePlaceRelatedSources(", start);
assert.ok(start >= 0 && end > start);
const compiled = ts.transpileModule(source.slice(start, end), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
}).outputText;
const validAmap = {
  id: "one", name: "Amap place", latitude: 39.9, longitude: 116.4,
  coordinate_system: "GCJ-02", location_provider: "amap",
  provider_place_id: "amap-one", provider_map_url: "https://uri.amap.com/marker?position=116.4,39.9",
};

async function invoke(items: unknown[]) {
  let connects = 0;
  let result: { body: unknown; status: number } | undefined;
  const boundary = new Error("validated input reached database boundary");
  const handler = new Function("pool", "sendJson", "listMaxItems", `${compiled}; return saveClipListPlaces;`)(
    { connect: async () => { connects += 1; throw boundary; } },
    (_response: unknown, body: unknown, status: number) => { result = { body, status }; },
    100,
  ) as (response: unknown, userId: string, items: unknown[]) => Promise<void>;
  try { await handler({}, "test-owner", items); } catch (error) {
    if (error !== boundary) throw error;
  }
  return { connects, result };
}

test("valid Amap batch reaches persistence validation boundary", async () => {
  assert.deepEqual(await invoke([validAmap]), { connects: 1, result: undefined });
});

for (const invalid of [
  { ...validAmap, location_provider: "apple_maps" },
  { ...validAmap, provider_place_id: "" },
  { ...validAmap, provider_map_url: "https://attacker.example/map" },
  { ...validAmap, coordinate_system: "unknown" },
  null,
  "not a place",
]) {
  test(`invalid batch row rejects the entire batch before any write: ${JSON.stringify(invalid)}`, async () => {
    const result = await invoke([validAmap, invalid]);
    assert.equal(result.connects, 0);
    assert.equal(result.result?.status, 400);
  });
}
