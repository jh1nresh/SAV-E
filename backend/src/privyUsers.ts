export type PrivyUser = {
  id: string;
};

export class PrivyUserProvisioningError extends Error {
  readonly status: number;
  constructor(message: string, status = 503) {
    super(message);
    this.name = "PrivyUserProvisioningError";
    this.status = status;
  }
}

export type PrivyUserProvisioner = {
  ensureUserForPhone(phoneE164: string): Promise<PrivyUser | null>;
  ensureUserForApple(appleSubject: string, email?: string): Promise<PrivyUser>;
  deleteUser(userId: string): Promise<void>;
};

export type PrivyUserProvisionerConfig = {
  appId: string;
  appSecret?: string;
  endpoint?: string;
  fetchImpl?: typeof fetch;
};

export function createPrivyUserProvisioner(
  config: PrivyUserProvisionerConfig,
): PrivyUserProvisioner | null {
  const appId = config.appId.trim();
  const appSecret = config.appSecret?.trim();
  if (!appId || !appSecret) return null;

  const endpoint = (config.endpoint ?? "https://api.privy.io").replace(/\/+$/, "");
  const fetchImpl = config.fetchImpl ?? fetch;
  const auth = Buffer.from(`${appId}:${appSecret}`).toString("base64");

  const headers = {
    "Authorization": `Basic ${auth}`,
    "privy-app-id": appId,
  };
  const appleSubjectCache = new Map<string, string>();

  const request = async (path: string, body: unknown): Promise<Response> =>
    fetchImpl(`${endpoint}${path}`, {
      method: "POST",
      headers: {
        ...headers,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

  const parseUser = async (response: Response): Promise<PrivyUser | null> => {
    const parsed = (await response.json().catch(() => null)) as unknown;
    if (!parsed || typeof parsed !== "object") return null;
    const id = (parsed as Record<string, unknown>).id;
    return typeof id === "string" && id.trim() ? { id: id.trim() } : null;
  };

  const appleAccountMatches = (value: unknown, appleSubject: string): boolean => {
    if (!value || typeof value !== "object") return false;
    const account = value as Record<string, unknown>;
    return account.type === "apple_oauth" && account.subject === appleSubject;
  };

  const findUserByAppleSubject = async (appleSubject: string): Promise<PrivyUser | null> => {
    let cursor: string | undefined;
    const seenCursors = new Set<string>();
    for (let page = 0; page < 100; page += 1) {
      const url = new URL(`${endpoint}/v1/users`);
      url.searchParams.set("limit", "100");
      if (cursor) url.searchParams.set("cursor", cursor);
      const listed = await fetchImpl(url, {
        method: "GET",
        headers,
      });
      if (!listed.ok) {
        throw new PrivyUserProvisioningError(`Privy Apple user lookup failed: HTTP ${listed.status}`);
      }
      const parsed = (await listed.json().catch(() => null)) as unknown;
      if (!parsed || typeof parsed !== "object") {
        throw new PrivyUserProvisioningError("Privy Apple user lookup failed: invalid list");
      }
      const rows = (parsed as Record<string, unknown>).data;
      if (!Array.isArray(rows)) {
        throw new PrivyUserProvisioningError("Privy Apple user lookup failed: invalid list");
      }
      for (const row of rows) {
        if (!row || typeof row !== "object") continue;
        const record = row as Record<string, unknown>;
        const id = typeof record.id === "string" ? record.id.trim() : "";
        const accounts = record.linked_accounts;
        if (!id || !Array.isArray(accounts)) continue;
        if (accounts.some((account) => appleAccountMatches(account, appleSubject))) {
          return { id };
        }
      }
      const nextCursor = (parsed as Record<string, unknown>).next_cursor;
      if (typeof nextCursor !== "string" || !nextCursor || seenCursors.has(nextCursor)) {
        return null;
      }
      seenCursors.add(nextCursor);
      cursor = nextCursor;
    }
    return null;
  };

  return {
    async ensureUserForPhone(phoneE164: string): Promise<PrivyUser | null> {
      const existing = await request("/v1/users/phone/number", { number: phoneE164 });
      if (existing.ok) return await parseUser(existing);
      if (existing.status !== 404) {
        throw new Error(`Privy phone lookup failed: HTTP ${existing.status}`);
      }

      const created = await request("/v1/users", {
        linked_accounts: [{ type: "phone", number: phoneE164 }],
        custom_metadata: {
          save_origin: "imessage",
        },
      });
      if (created.ok) return await parseUser(created);

      // A concurrent worker may have imported the phone after our lookup.
      if (created.status === 409 || created.status === 400) {
        const retried = await request("/v1/users/phone/number", { number: phoneE164 });
        if (retried.ok) return await parseUser(retried);
      }

      throw new Error(`Privy user import failed: HTTP ${created.status}`);
    },
    async ensureUserForApple(appleSubject: string, email?: string): Promise<PrivyUser> {
      const subject = appleSubject.trim();
      if (!subject) {
        throw new PrivyUserProvisioningError("Missing Apple subject", 401);
      }
      const cached = appleSubjectCache.get(subject);
      if (cached) return { id: cached };

      const existing = await findUserByAppleSubject(subject);
      if (existing) {
        appleSubjectCache.set(subject, existing.id);
        return existing;
      }

      const createdAccount = email?.trim()
        ? { type: "apple_oauth", subject, email: email.trim() }
        : { type: "apple_oauth", subject };
      const created = await request("/v1/users", {
        linked_accounts: [createdAccount],
        custom_metadata: {
          save_origin: "appclip",
        },
      });
      if (created.ok) {
        const user = await parseUser(created);
        if (!user) {
          throw new PrivyUserProvisioningError("Privy Apple user import failed: missing id");
        }
        appleSubjectCache.set(subject, user.id);
        return user;
      }
      if (created.status === 409 || created.status === 400) {
        const retried = await findUserByAppleSubject(subject);
        if (retried) {
          appleSubjectCache.set(subject, retried.id);
          return retried;
        }
      }
      throw new PrivyUserProvisioningError(`Privy Apple user import failed: HTTP ${created.status}`);
    },
    async deleteUser(userId: string): Promise<void> {
      const response = await fetchImpl(`${endpoint}/v1/users/${encodeURIComponent(userId)}`, {
        method: "DELETE",
        headers: {
          "Authorization": `Basic ${auth}`,
          "privy-app-id": appId,
        },
      });
      if (response.ok || response.status === 404) return;
      throw new Error(`Privy user deletion failed: HTTP ${response.status}`);
    },
  };
}
