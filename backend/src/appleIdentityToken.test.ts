import assert from "node:assert/strict";
import test from "node:test";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type KeyLike } from "jose";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  APPLE_IDENTITY_AUDIENCES,
  APPLE_IDENTITY_ISSUER,
  AppleIdentityTokenError,
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
  claims: { iss?: string; aud?: string; sub?: string; exp?: string } = {},
) {
  return new SignJWT({})
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
  assert.match(server, /verifiedAppleIdentitySubject/);
  assert.match(server, /APPLE_IDENTITY_ISSUER/);
  assert.match(server, /decodeJwt\(token\)\.iss === APPLE_IDENTITY_ISSUER/);
  const audiences = APPLE_IDENTITY_AUDIENCES.join(" ");
  assert.match(audiences, /com\.wanderly\.app\.Clip/);
  const source = readFileSync(
    fileURLToPath(new URL("../src/appleIdentityToken.ts", import.meta.url)),
    "utf8",
  );
  assert.match(source, /appleid\.apple\.com\/auth\/keys/);
});
