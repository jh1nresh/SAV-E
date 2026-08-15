import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  ChinaPlaceResolverConfigurationError,
  ChinaPlaceResolverInputError,
  normalizeChinaPlaceResolveRequest,
  resolveChinaPlace,
} from "./chinaPlaceResolver.js";

const restaurant = {
  id: "B0FFFAKEQINGDAO",
  name: "柳州肥姨妈大骨螺蛳粉(青大店)",
  address: "香港东路18号6号楼3号1层",
  location: "120.421421,36.064812",
  type: "餐饮服务;中餐厅",
};

test("normalizes a bounded authenticated China place query", () => {
  assert.deepEqual(normalizeChinaPlaceResolveRequest({
    query: "  柳州肥姨妈大骨螺蛳粉(青大店)   金家岭街道香港东路18号  ",
    provider: "china",
  }), {
    query: "柳州肥姨妈大骨螺蛳粉(青大店) 金家岭街道香港东路18号",
    provider: "china",
  });
  assert.throws(() => normalizeChinaPlaceResolveRequest({ query: "" }), ChinaPlaceResolverInputError);
  assert.throws(
    () => normalizeChinaPlaceResolveRequest({ query: "青岛", provider: "arbitrary" }),
    ChinaPlaceResolverInputError,
  );
});

test("prefers international Amap WGS84 results for the unified MapKit surface", async () => {
  const requested: URL[] = [];
  const result = await resolveChinaPlace(
    normalizeChinaPlaceResolveRequest({ query: `${restaurant.name} ${restaurant.address}` }),
    {
      usageAuthorized: true,
      internationalApiKey: "international-test-key",
      domesticApiKey: "domestic-test-key",
      fetcher: async (input) => {
        requested.push(new URL(String(input)));
        return Response.json({ status: "1", info: "OK", pois: [restaurant] });
      },
    },
  );

  assert.equal(requested.length, 1);
  assert.equal(requested[0]?.hostname, "sg-restapi.opnavi.com");
  assert.equal(requested[0]?.searchParams.get("key"), "international-test-key");
  assert.equal(result.matches[0]?.coordinateSystem, "WGS84");
  assert.equal(result.matches[0]?.provider, "amap");
  assert.equal(result.matches[0]?.name, restaurant.name);
  assert.equal(result.matches[0]?.latitude, 36.064812);
  assert.match(result.matches[0]?.mapURL ?? "", /^https:\/\/uri\.amap\.com\/marker\?/);
});

test("falls back to domestic GCJ-02 without relabeling it as MapKit-safe", async () => {
  const requestedHosts: string[] = [];
  const result = await resolveChinaPlace(
    normalizeChinaPlaceResolveRequest({ query: restaurant.name }),
    {
      usageAuthorized: true,
      internationalApiKey: "international-test-key",
      domesticApiKey: "domestic-test-key",
      fetcher: async (input) => {
        const url = new URL(String(input));
        requestedHosts.push(url.hostname);
        if (url.hostname === "sg-restapi.opnavi.com") {
          return Response.json({ status: "0", info: "INSUFFICIENT_PRIVILEGES", pois: [] });
        }
        return Response.json({ status: "1", info: "OK", pois: [restaurant] });
      },
    },
  );

  assert.deepEqual(requestedHosts, ["sg-restapi.opnavi.com", "restapi.amap.com"]);
  assert.equal(result.matches[0]?.coordinateSystem, "GCJ-02");
  assert.equal(result.matches[0]?.longitude, 120.421421);
});

test("rejects malformed provider data and missing server credentials", async () => {
  await assert.rejects(
    resolveChinaPlace(normalizeChinaPlaceResolveRequest({ query: restaurant.name }), { usageAuthorized: true }),
    ChinaPlaceResolverConfigurationError,
  );
  await assert.rejects(
    resolveChinaPlace(normalizeChinaPlaceResolveRequest({ query: restaurant.name }), {
      domesticApiKey: "domestic-test-key",
    }),
    ChinaPlaceResolverConfigurationError,
  );
  const result = await resolveChinaPlace(
    normalizeChinaPlaceResolveRequest({ query: restaurant.name }),
    {
      usageAuthorized: true,
      domesticApiKey: "domestic-test-key",
      fetcher: async () => Response.json({
        status: "1",
        pois: [
          { ...restaurant, location: "not-a-coordinate" },
          { ...restaurant, id: "", location: "120.4,36.0" },
          { ...restaurant, location: "181,36.0" },
        ],
      }),
    },
  );
  assert.deepEqual(result.matches, []);
});

test("server exposes the place resolver only after bearer account resolution", async () => {
  const server = await readFile(new URL("../src/server.ts", import.meta.url), "utf8");
  const authIndex = server.indexOf("const userId = await resolveUserId(request)");
  const routeIndex = server.indexOf('resource === "place-resolve"');
  assert.ok(authIndex >= 0);
  assert.ok(routeIndex > authIndex);
  assert.match(server, /handlePlaceResolve\(request, response\)/);
  assert.match(server, /"coordinate_system"/);
  assert.match(server, /"location_provider"/);
  assert.match(server, /"provider_place_id"/);
  assert.match(server, /"provider_map_url"/);
});
