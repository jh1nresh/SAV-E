import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

export const APPLE_IDENTITY_ISSUER = "https://appleid.apple.com";
export const APPLE_IDENTITY_AUDIENCES = [
  "com.wanderly.app",
  "com.wanderly.app.Clip",
] as const;
const APPLE_JWKS_URL = new URL("https://appleid.apple.com/auth/keys");

const appleJWKS = createRemoteJWKSet(APPLE_JWKS_URL);

export class AppleIdentityTokenError extends Error {
  readonly status = 401;
  constructor(message = "Invalid Apple identity token") {
    super(message);
    this.name = "AppleIdentityTokenError";
  }
}

export async function verifiedAppleIdentitySubject(
  token: string,
  options?: {
    jwks?: JWTVerifyGetKey;
    audiences?: readonly string[];
    now?: Date;
  },
): Promise<string> {
  const trimmed = token.trim();
  if (!trimmed) {
    throw new AppleIdentityTokenError("Missing Apple identity token");
  }

  try {
    const { payload } = await jwtVerify(trimmed, options?.jwks ?? appleJWKS, {
      issuer: APPLE_IDENTITY_ISSUER,
      audience: [...(options?.audiences ?? APPLE_IDENTITY_AUDIENCES)],
      currentDate: options?.now,
    });
    if (typeof payload.sub !== "string" || payload.sub.length === 0) {
      throw new AppleIdentityTokenError("Invalid Apple subject");
    }
    return payload.sub;
  } catch (error) {
    if (error instanceof AppleIdentityTokenError) throw error;
    throw new AppleIdentityTokenError();
  }
}
