import { listPublicDiscoveryPosts, PublicDiscoveryError, type PublicDiscoveryResponse } from "./publicDiscovery.js";

export async function evaluatePublicDiscoveryRequest(input: {
  method: string | undefined;
  authorization: string | undefined;
  url: URL;
  verifySubject: (token: string) => Promise<string>;
  readPosts?: (url: URL) => Promise<PublicDiscoveryResponse>;
}): Promise<{ statusCode: number; body: unknown }> {
  const token = input.authorization?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return { statusCode: 401, body: { error: "Account bearer required" } };
  try {
    if (!(await input.verifySubject(token))) throw new Error("Missing verified subject");
  } catch { return { statusCode: 401, body: { error: "Account bearer required" } }; }
  if (input.method !== "GET" || input.url.pathname !== "/v0/discovery/posts") {
    return { statusCode: 405, body: { error: "Method not allowed" } };
  }
  try {
    return { statusCode: 200, body: await (input.readPosts ?? listPublicDiscoveryPosts)(input.url) };
  } catch (error) {
    if (error instanceof PublicDiscoveryError) return { statusCode: error.statusCode, body: { error: error.code } };
    return { statusCode: 503, body: { error: "public_discovery_unavailable" } };
  }
}
