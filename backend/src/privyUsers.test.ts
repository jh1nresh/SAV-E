import assert from "node:assert/strict";
import test from "node:test";
import { createPrivyUserProvisioner, PrivyUserProvisioningError } from "./privyUsers.js";

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

test("ensureUserForPhone imports a missing phone user with Savvy metadata", async () => {
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

test("findUserForApple looks up the official Apple subject path", async () => {
  const calls: Array<{ url: string; method?: string; body: unknown }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: url.toString(),
      method: init?.method,
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    return Response.json({ id: "did:privy:linked" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.findUserForApple("001234.clip-apple-user");

  assert.equal(user?.id, "did:privy:linked");
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, "https://privy.test/v1/users/apple/subject");
  assert.equal(calls[0]?.method, "POST");
  assert.deepEqual(calls[0]?.body, { subject: "001234.clip-apple-user" });
});

test("findUserForApple returns null when the Apple subject is missing", async () => {
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl: async () => new Response(JSON.stringify({ error: "not found" }), { status: 404 }),
  });

  assert.equal(await provisioner?.findUserForApple("001234.clip-apple-user"), null);
});

test("ensureUserForApple returns the Privy DID for an exact apple_oauth subject", async () => {
  const calls: Array<{ url: string; method?: string; body: unknown }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: url.toString(),
      method: init?.method,
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    return Response.json({ id: "did:privy:linked" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForApple("001234.clip-apple-user");

  assert.equal(user?.id, "did:privy:linked");
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, "https://privy.test/v1/users/apple/subject");
  assert.deepEqual(calls[0]?.body, { subject: "001234.clip-apple-user" });
});

test("ensureUserForApple never attaches email or merges a same-email account", async () => {
  const calls: Array<{ url: string; method?: string; body: unknown }> = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    const value = url.toString();
    calls.push({
      url: value,
      method: init?.method,
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    if (value.endsWith("/v1/users/apple/subject")) {
      return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    }
    return Response.json({ id: "did:privy:imported" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForApple("001234.clip-apple-user");

  assert.equal(user?.id, "did:privy:imported");
  assert.equal(calls[1]?.url, "https://privy.test/v1/users");
  assert.deepEqual(calls[1]?.body, {
    linked_accounts: [{
      type: "apple_oauth",
      subject: "001234.clip-apple-user",
    }],
    custom_metadata: { save_origin: "appclip" },
  });
  assert.equal(JSON.stringify(calls[1]?.body).includes("email"), false);
});

test("ensureUserForApple does not scan the Privy user list", async () => {
  const urls: string[] = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    urls.push(url.toString());
    if (url.toString().endsWith("/v1/users/apple/subject")) {
      return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    }
    if (url.toString().endsWith("/v1/users") && String(init?.method).toUpperCase() === "POST") {
      return Response.json({ id: "did:privy:new-apple" });
    }
    return new Response(null, { status: 500 });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForApple("001234.clip-apple-user");
  assert.equal(user?.id, "did:privy:new-apple");
  assert.equal(urls.some((value) => value.includes("/v1/users?")), false);
});

test("ensureUserForApple imports a missing Apple subject instead of using the raw sub", async () => {
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    if (url.toString().endsWith("/v1/users/apple/subject")) {
      return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    }
    return Response.json({ id: "did:privy:new-apple" });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForApple("001234.clip-apple-user");
  assert.equal(user?.id, "did:privy:new-apple");
  assert.notEqual(user?.id, "001234.clip-apple-user");
});

test("ensureUserForApple retries the exact subject after a create conflict", async () => {
  let created = false;
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    if (url.toString().endsWith("/v1/users") && String(init?.method).toUpperCase() === "POST") {
      created = true;
      return new Response(JSON.stringify({ error: "already linked" }), { status: 409 });
    }
    if (url.toString().endsWith("/v1/users/apple/subject")) {
      if (!created) {
        return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
      }
      return Response.json({ id: "did:privy:raced" });
    }
    return new Response(null, { status: 500 });
  };
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    endpoint: "https://privy.test",
    fetchImpl,
  });

  const user = await provisioner?.ensureUserForApple("001234.clip-apple-user");
  assert.equal(user?.id, "did:privy:raced");
});

test("ensureUserForApple returns 409 instead of 503 when a conflict cannot be resolved", async () => {
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    fetchImpl: async (url, init) => {
      if (url.toString().endsWith("/v1/users") && String(init?.method).toUpperCase() === "POST") {
        return new Response(JSON.stringify({ error: "already linked" }), { status: 409 });
      }
      return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    },
  });

  await assert.rejects(
    () => provisioner!.ensureUserForApple("001234.clip-apple-user"),
    (error: unknown) => error instanceof PrivyUserProvisioningError
      && error.status === 409
      && /Privy Apple user import failed: HTTP 409/.test(error.message),
  );
});

test("ensureUserForApple fails closed on an empty subject", async () => {
  const provisioner = createPrivyUserProvisioner({
    appId: "app_123",
    appSecret: "secret_456",
    fetchImpl: async () => {
      throw new Error("must not call Privy");
    },
  });

  await assert.rejects(
    () => provisioner!.ensureUserForApple("   "),
    /Missing Apple subject/,
  );
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
