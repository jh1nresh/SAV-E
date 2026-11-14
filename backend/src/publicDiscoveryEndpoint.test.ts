import { test } from "node:test";
import assert from "node:assert/strict";
import { evaluatePublicDiscoveryRequest } from "./publicDiscoveryEndpoint.js";
import { PublicDiscoveryError } from "./publicDiscovery.js";

test("public discovery rejects missing, malformed or unverified bearer before index reads", async () => {
  for (const authorization of [undefined, "Basic fixture", "Bearer two tokens", "Bearer expired"]) {
    let reads = 0;
    const result = await evaluatePublicDiscoveryRequest({ method: "GET", authorization,
      url: new URL("https://fixture.invalid/v0/discovery/posts?bbox=1,2,3,4"),
      verifySubject: async () => { throw new Error("expired fixture"); },
      readPosts: async () => { reads++; throw new Error("must not read"); } });
    assert.equal(result.statusCode, 401);
    assert.equal(reads, 0);
  }
});

test("verified subject reads only the public index without provisioning a profile", async () => {
  let verified = 0, reads = 0;
  const result = await evaluatePublicDiscoveryRequest({ method: "GET", authorization: "Bearer fixture",
    url: new URL("https://fixture.invalid/v0/discovery/posts?bbox=1,2,3,4"),
    verifySubject: async token => { assert.equal(token, "fixture"); verified++; return "unprovisioned-subject"; },
    readPosts: async () => { reads++; throw new PublicDiscoveryError(503); } });
  assert.equal(verified, 1); assert.equal(reads, 1);
  assert.deepEqual(result, { statusCode: 503, body: { error: "public_discovery_unavailable" } });
});

test("non-read routes never reach discovery index and unexpected file errors are redacted", async () => {
  for (const [method, path] of [["POST", "/v0/discovery/posts"], ["GET", "/v0/discovery/posts/extra"]]) {
    const result = await evaluatePublicDiscoveryRequest({ method, authorization: "Bearer fixture",
      url: new URL(`https://fixture.invalid${path}`), verifySubject: async () => "fixture-subject",
      readPosts: async () => { assert.fail("non-read route must not reach index"); } });
    assert.equal(result.statusCode, 405);
  }
  const result = await evaluatePublicDiscoveryRequest({ method: "GET", authorization: "Bearer fixture",
    url: new URL("https://fixture.invalid/v0/discovery/posts"), verifySubject: async () => "fixture-subject",
    readPosts: async () => { throw new Error("/private/operator/index.json: sensitive path"); } });
  assert.deepEqual(result, { statusCode: 503, body: { error: "public_discovery_unavailable" } });
});
