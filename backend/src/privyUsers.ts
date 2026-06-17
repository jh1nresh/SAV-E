export type PrivyUser = {
  id: string;
};

export type PrivyUserProvisioner = {
  ensureUserForPhone(phoneE164: string): Promise<PrivyUser | null>;
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

  const request = async (path: string, body: unknown): Promise<Response> =>
    fetchImpl(`${endpoint}${path}`, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${auth}`,
        "Content-Type": "application/json",
        "privy-app-id": appId,
      },
      body: JSON.stringify(body),
    });

  const parseUser = async (response: Response): Promise<PrivyUser | null> => {
    const parsed = (await response.json().catch(() => null)) as unknown;
    if (!parsed || typeof parsed !== "object") return null;
    const id = (parsed as Record<string, unknown>).id;
    return typeof id === "string" && id.trim() ? { id: id.trim() } : null;
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
  };
}
