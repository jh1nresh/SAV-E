import assert from "node:assert/strict";
import test from "node:test";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type KeyLike } from "jose";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  APPLE_IDENTITY_AUDIENCES,
  APPLE_IDENTITY_ISSUER,
  AppleIdentityTokenError,
  verifiedAppleIdentity,
  verifiedAppleIdentitySubject,
} from "./appleIdentityToken.js";

async function appleFixture() {
  const { publicKey, privateKey } = await generateKeyPair("ES256");
  const jwk = await exportJWK(publicKey);
  jwk.kid = "test-apple-kid";
  jwk.alg = "ES256";
  const jwks = createLocalJWKSet({ keys: [jwk] });
  return { privateKey, jwks };
}

async function signApple(
  privateKey: KeyLike,
  claims: { iss?: string; aud?: string; sub?: string; exp?: string; email?: string } = {},
) {
  return new SignJWT(claims.email ? { email: claims.email } : {})
    .setProtectedHeader({ alg: "ES256", kid: "test-apple-kid" })
    .setIssuer(claims.iss ?? APPLE_IDENTITY_ISSUER)
    .setAudience(claims.aud ?? "com.wanderly.app.Clip")
    .setSubject(claims.sub ?? "001234.apple-user")
    .setIssuedAt()
    .setExpirationTime(claims.exp ?? "5m")
    .sign(privateKey);
}

test("verifiedAppleIdentitySubject accepts a signed Apple identity token", async () => {
  const { privateKey, jwks } = await appleFixture();
  const token = await signApple(privateKey);
  assert.equal(
    await verifiedAppleIdentitySubject(token, { jwks }),
    "001234.apple-user",
  );
});

test("verifiedAppleIdentity keeps an optional email off the identity subject", async () => {
  const { privateKey, jwks } = await appleFixture();
  const token = await signApple(privateKey, { email: "hidden@privaterelay.appleid.com" });
  assert.deepEqual(await verifiedAppleIdentity(token, { jwks }), {
    subject: "001234.apple-user",
    email: "hidden@privaterelay.appleid.com",
  });
});

test("verifiedAppleIdentitySubject accepts the full-app audience", async () => {
  const { privateKey, jwks } = await appleFixture();
  const token = await signApple(privateKey, { aud: "com.wanderly.app" });
  assert.equal(await verifiedAppleIdentitySubject(token, { jwks }), "001234.apple-user");
});

test("verifiedAppleIdentitySubject rejects a wrong issuer", async () => {
  const { privateKey, jwks } = await appleFixture();
  const token = await signApple(privateKey, { iss: "privy.io" });
  await assert.rejects(
    () => verifiedAppleIdentitySubject(token, { jwks }),
    AppleIdentityTokenError,
  );
});

test("verifiedAppleIdentitySubject rejects a wrong audience", async () => {
  const { privateKey, jwks } = await appleFixture();
  const token = await signApple(privateKey, { aud: "com.other.app" });
  await assert.rejects(
    () => verifiedAppleIdentitySubject(token, { jwks }),
    AppleIdentityTokenError,
  );
});

test("verifiedAppleIdentitySubject rejects a token signed by another key", async () => {
  const { jwks } = await appleFixture();
  const other = await generateKeyPair("ES256");
  const token = await signApple(other.privateKey);
  await assert.rejects(
    () => verifiedAppleIdentitySubject(token, { jwks }),
    AppleIdentityTokenError,
  );
});

test("server resolveUserId verifies Apple identity tokens before Privy", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  assert.match(server, /verifiedAppleIdentity/);
  assert.match(server, /findUserForApple/);
  assert.match(server, /ensureUserForApple/);
  assert.match(server, /lookupAppleLinkedPrivySubject/);
  assert.match(server, /verifiedAppleLinkedPrivySubject/);
  assert.match(server, /verifiedBearerPrivySubject/);
  assert.match(server, /verifiedPrivyAccessSubject/);
  assert.match(server, /APPLE_IDENTITY_ISSUER/);
  assert.match(server, /decodeJwt\(token\)\.iss === APPLE_IDENTITY_ISSUER/);
  assert.match(server, /Apple identity linking unavailable/);
  assert.match(server, /clip-apple-session/);
  assert.match(server, /Apple identity token required/);
  assert.match(server, /Privy bearer token required/);
  assert.doesNotMatch(server, /profileIdForPrivySubject\(appleSubject\)/);
  const sessionRoute = server.indexOf('resource === "clip-apple-session"');
  const sessionEnd = server.indexOf('if (isV0 && resource === "account-status")');
  const sessionBlock = server.slice(sessionRoute, sessionEnd);
  assert.match(sessionBlock, /lookupAppleLinkedPrivySubject/);
  assert.doesNotMatch(sessionBlock, /ensureUserForApple/);
  assert.doesNotMatch(sessionBlock, /verifiedAppleLinkedPrivySubject/);
  const authGate = server.indexOf("const userId = await resolveUserId(request)");
  assert.ok(sessionRoute >= 0 && sessionRoute < authGate);
  const statusStart = server.indexOf('if (isV0 && resource === "account-status")');
  const statusBlock = server.slice(
    statusStart,
    server.indexOf('if (isV0 && resource === "share-extension")'),
  );
  assert.match(statusBlock, /verifiedPrivyAccessSubject/);
  assert.doesNotMatch(statusBlock, /verifiedBearerPrivySubject/);
  const accountStart = server.indexOf('if (isV0 && resource === "account" && !id)');
  const accountBlock = server.slice(accountStart, server.indexOf("await ensureProfile(userId)"));
  assert.match(accountBlock, /verifiedPrivyAccessSubject\(token\)/);
  assert.doesNotMatch(accountBlock, /verifiedBearerPrivySubject/);
  const shareHandler = server.slice(
    server.indexOf("async function handleShareExtension"),
    server.indexOf("function requiredShareExtensionToken"),
  );
  assert.match(shareHandler, /verifiedPrivyAccessSubject\(bearer\)/);
  assert.doesNotMatch(shareHandler, /verifiedBearerPrivySubject/);
  const resolver = server.slice(
    server.indexOf("async function resolveUserId"),
    server.indexOf("async function profileIdForPrivySubject"),
  );
  assert.match(resolver, /verifiedBearerPrivySubject/);
  assert.doesNotMatch(resolver, /profileIdForPrivySubject\(appleSubject\)/);
  const lookup = server.slice(
    server.indexOf("async function lookupAppleLinkedPrivySubject"),
    server.indexOf("async function verifiedAppleLinkedPrivySubject"),
  );
  assert.match(lookup, /findUserForApple/);
  assert.doesNotMatch(lookup, /ensureUserForApple/);
  const provision = server.slice(
    server.indexOf("async function verifiedAppleLinkedPrivySubject"),
    server.indexOf("async function verifiedPrivyAccessSubject"),
  );
  assert.match(provision, /ensureUserForApple\(identity\.subject\)/);
  assert.doesNotMatch(provision, /identity\.email/);
  const audiences = APPLE_IDENTITY_AUDIENCES.join(" ");
  assert.match(audiences, /com\.wanderly\.app\.Clip/);
  const source = readFileSync(
    fileURLToPath(new URL("../src/appleIdentityToken.ts", import.meta.url)),
    "utf8",
  );
  assert.match(source, /appleid\.apple\.com\/auth\/keys/);
  const privyUsers = readFileSync(new URL("../src/privyUsers.ts", import.meta.url), "utf8");
  assert.match(privyUsers, /\/v1\/users\/apple\/subject/);
  assert.doesNotMatch(privyUsers, /\/v1\/users\?limit/);
  assert.doesNotMatch(privyUsers, /searchParams\.set\("limit", "100"\)/);
});
