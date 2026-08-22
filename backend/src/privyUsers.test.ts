import assert from "node:assert/strict";
import test from "node:test";
import { createPrivyUserProvisioner } from "./privyUsers.js";

test("createPrivyUserProvisioner is disabled without an app secret", () => {
  assert.equal(createPrivyUserProvisioner({ appId: "app_123" }), null);
});

test("ensureUserForPhone returns an existing Privy phone user", async () => {
  const calls: Array<{ url: string; body: unknown; auth: string | null; appId: string | null }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: url.toString(),
      body: JSON.parse(String(init?.body ?? "{}")) as unknown,
      auth: new Headers(init?.headers).get("authorization"),
      appId: new Headers(init?.headers).get("privy-app-id"),
    });
    return Response.json({ id: "did:privy:existing" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test/",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForPhone("+15551234567");

  assert.equal(user?.id, "did:privy:existing");
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, "https://privy.test/v1/users/phone/number");
  assert.deepEqual(calls[0]?.body, { number: "+15551234567" });
  assert.equal(calls[0]?.auth, `Basic ${Buffer.from("app_123:secret_456").toString("base64")}`);
  assert.equal(calls[0]?.appId, "app_123");
});

test("ensureUserForPhone imports a missing phone user with SAV-E metadata", async () => {
  const calls: Array<{ url: string; body: unknown }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    const value = url.toString();
    const body = JSON.parse(String(init?.body ?? "{}")) as unknown;
    calls.push({ url: value, body });
    if (value.endsWith("/v1/users/phone/number")) {
      return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    }
    return Response.json({ id: "did:privy:new" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForPhone("+15557654321");

  assert.equal(user?.id, "did:privy:new");
  assert.equal(calls.length, 2);
  assert.equal(calls[1]?.url, "https://privy.test/v1/users");
  assert.deepEqual(calls[1]?.body, {
    linked_accounts: [{ type: "phone", number: "+15557654321" }],
    custom_metadata: {
      save_origin: "imessage",
    },
  });
});

test("deleteUser removes the exact Privy user with server credentials", async () => {
  const calls: Array<{ url: string; method: string | undefined; auth: string | null }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: url.toString(),
      method: init?.method,
      auth: new Headers(init?.headers).get("authorization"),
    });
    return new Response(null, { status: 204 });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });
  assert.ok(provisioner);

  await provisioner.deleteUser("did:privy:user/one");

  assert.deepEqual(calls, [{
    url: "https://privy.test/v1/users/did%3Aprivy%3Auser%2Fone",
    method: "DELETE",
    auth: `Basic ${Buffer.from("app_123:secret_456").toString("base64")}`,
  }]);
});

test("deleteUser treats an already-missing Privy user as deleted", async () => {
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    fetchImpl: async () => new Response(null, { status: 404 }),
  });
  assert.ok(provisioner);

  await assert.doesNotReject(() => provisioner.deleteUser("did:privy:missing"));
});

test("deleteUser rejects upstream failures", async () => {
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    fetchImpl: async () => new Response(null, { status: 503 }),
  });
  assert.ok(provisioner);

  await assert.rejects(
    () => provisioner.deleteUser("did:privy:user"),
    /Privy user deletion failed: HTTP 503/,
  );
});
