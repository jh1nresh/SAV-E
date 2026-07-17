import { createHmac } from "node:crypto";

export type AccountStatusState = "ready" | "new" | "empty" | "recovery_required";

export interface AccountStatusResponse {
  version: "v0";
  state: AccountStatusState;
  account_ref: string | null;
  profile: {
    exists: boolean;
    customized: boolean | null;
  };
  counts: {
    stamps: number;
    review_items: number;
  } | null;
  recovery_reason: "split_profile_binding" | "conflicting_profile_binding" | null;
}

export interface AccountStatusHttpResult {
  statusCode: number;
  body: AccountStatusResponse | { error: string };
}

interface AccountStatusRow {
  profile_id: unknown;
  profile_customized: unknown;
  places_count: unknown;
  review_items_count: unknown;
  conflicting_binding: unknown;
}

interface AccountStatusRequestDependencies {
  method?: string;
  authorizationHeader?: string | string[];
  accountRefSecret?: string;
  verifySubject: (token: string) => Promise<string>;
  query: (sql: string, values: readonly unknown[]) => Promise<{ rows: unknown[] }>;
}

interface AccountConfirmationRequestDependencies extends AccountStatusRequestDependencies {
  expectedAccountRef: unknown;
  createProfile: (subject: string) => Promise<void>;
  beginTransaction: () => Promise<void>;
  lockSubject: (subject: string) => Promise<void>;
  commitTransaction: () => Promise<void>;
  rollbackTransaction: () => Promise<void>;
}

export interface ProfileSubjectResolution {
  profileId: string;
  conflictingRawBinding: boolean;
}

export const accountStatusSql = `
select
  p.id as profile_id,
  (
    (btrim(coalesce(p.display_name, '')) not in ('', 'SAV-E User'))
    or nullif(btrim(coalesce(p.email, '')), '') is not null
    or nullif(btrim(coalesce(p.avatar_url, '')), '') is not null
    or nullif(btrim(coalesce(p.handle, '')), '') is not null
    or nullif(btrim(coalesce(p.referral_code, '')), '') is not null
  ) as profile_customized,
  (select count(*)::int from places pl where pl.user_id = p.id) as places_count,
  (
    select count(*)::int
    from captures c
    join place_candidates pc on pc.capture_id = c.id
    where c.user_id = p.id
      and pc.status in ('review', 'confirmed', 'needs_more_evidence', 'source_only')
  ) as review_items_count,
  (
    p.id = $1
    and p.privy_user_id is not null
    and p.privy_user_id <> $1
  ) as conflicting_binding
from profiles p
where p.id = $1 or p.privy_user_id = $1
order by p.id
`;

export async function evaluateAccountStatusRequest(
  dependencies: AccountStatusRequestDependencies,
): Promise<AccountStatusHttpResult> {
  if (dependencies.method !== "GET") {
    return { statusCode: 405, body: { error: "Method not allowed" } };
  }

  const token = bearerToken(dependencies.authorizationHeader);
  if (!token) {
    return { statusCode: 401, body: { error: "Unauthorized" } };
  }

  let subject: string;
  try {
    subject = await dependencies.verifySubject(token);
  } catch {
    return { statusCode: 401, body: { error: "Unauthorized" } };
  }

  const secret = dependencies.accountRefSecret?.trim();
  if (!secret) {
    return { statusCode: 503, body: { error: "Account verification unavailable" } };
  }

  const { rows } = await dependencies.query(accountStatusSql, [subject]);
  return {
    statusCode: 200,
    body: accountStatusResponse(rows, subject, secret),
  };
}

export async function evaluateAccountConfirmationRequest(
  dependencies: AccountConfirmationRequestDependencies,
): Promise<AccountStatusHttpResult> {
  if (dependencies.method !== "POST") {
    return { statusCode: 405, body: { error: "Method not allowed" } };
  }

  const token = bearerToken(dependencies.authorizationHeader);
  if (!token) {
    return { statusCode: 401, body: { error: "Unauthorized" } };
  }

  let subject: string;
  try {
    subject = await dependencies.verifySubject(token);
  } catch {
    return { statusCode: 401, body: { error: "Unauthorized" } };
  }

  const expectedAccountRef = dependencies.expectedAccountRef;
  if (typeof expectedAccountRef !== "string" || !isOpaqueAccountRef(expectedAccountRef)) {
    return { statusCode: 400, body: { error: "Invalid account confirmation" } };
  }

  const secret = dependencies.accountRefSecret?.trim();
  if (!secret) {
    return { statusCode: 503, body: { error: "Account verification unavailable" } };
  }

  let transactionStarted = false;
  let transactionFinished = false;
  try {
    await dependencies.beginTransaction();
    transactionStarted = true;
    await dependencies.lockSubject(subject);

    const before = accountStatusResponse(
      (await dependencies.query(accountStatusSql, [subject])).rows,
      subject,
      secret,
    );
    if (before.state === "recovery_required" || before.account_ref !== expectedAccountRef) {
      await dependencies.rollbackTransaction();
      transactionFinished = true;
      return { statusCode: 409, body: { error: "Account recovery required" } };
    }

    if (before.state === "new") {
      await dependencies.createProfile(subject);
    }

    const after = accountStatusResponse(
      (await dependencies.query(accountStatusSql, [subject])).rows,
      subject,
      secret,
    );
    if (
      after.account_ref !== expectedAccountRef
      || (after.state !== "ready" && after.state !== "empty")
    ) {
      await dependencies.rollbackTransaction();
      transactionFinished = true;
      return { statusCode: 409, body: { error: "Account recovery required" } };
    }

    await dependencies.commitTransaction();
    transactionFinished = true;
    return { statusCode: 200, body: after };
  } catch (error) {
    if (transactionStarted && !transactionFinished) {
      try {
        await dependencies.rollbackTransaction();
      } catch {
        // Preserve the original failure; the client is released by the caller.
      }
    }
    throw error;
  }
}

export function accountStatusResponse(
  rawRows: unknown[],
  subject: string,
  accountRefSecret: string,
): AccountStatusResponse {
  const rows = rawRows.map(normalizeRow);
  if (rows.length === 0) {
    return {
      version: "v0",
      state: "new",
      account_ref: opaqueAccountRef(subject, accountRefSecret),
      profile: { exists: false, customized: false },
      counts: { stamps: 0, review_items: 0 },
      recovery_reason: null,
    };
  }

  if (rows.some((row) => row.conflictingBinding)) {
    return {
      version: "v0",
      state: "recovery_required",
      account_ref: null,
      profile: { exists: true, customized: null },
      counts: null,
      recovery_reason: "conflicting_profile_binding",
    };
  }

  const profileIds = new Set(rows.map((row) => row.profileId));
  if (profileIds.size !== 1) {
    return {
      version: "v0",
      state: "recovery_required",
      account_ref: null,
      profile: { exists: true, customized: null },
      counts: null,
      recovery_reason: "split_profile_binding",
    };
  }

  const row = rows[0];
  const isEmpty = !row.customized
    && row.placesCount === 0
    && row.reviewItemsCount === 0;
  return {
    version: "v0",
    state: isEmpty ? "empty" : "ready",
    account_ref: opaqueAccountRef(row.profileId, accountRefSecret),
    profile: { exists: true, customized: row.customized },
    counts: { stamps: row.placesCount, review_items: row.reviewItemsCount },
    recovery_reason: null,
  };
}

export function opaqueAccountRef(profileId: string, secret: string): string {
  const digest = createHmac("sha256", secret)
    .update("save-account-status-ref:v0\0")
    .update(profileId)
    .digest("base64url");
  return `save_account_${digest}`;
}

export function isOpaqueAccountRef(value: string): boolean {
  return /^save_account_[A-Za-z0-9_-]{43}$/.test(value);
}

export function stableAccountRefSecret(environment: NodeJS.ProcessEnv): string | undefined {
  return environment.SAVE_ACCOUNT_REF_SECRET?.trim()
    || environment.SAVE_MY_SAVES_SECRET?.trim()
    || undefined;
}

export async function resolveProfileSubject(
  subject: string,
  query: (sql: string, values: readonly unknown[]) => Promise<{ rows: unknown[] }>,
): Promise<ProfileSubjectResolution> {
  const mapped = await query(
    "select id from profiles where privy_user_id = $1 limit 1",
    [subject],
  );
  const mappedId = (mapped.rows[0] as { id?: unknown } | undefined)?.id;
  const raw = await query(
    "select privy_user_id from profiles where id = $1 limit 1",
    [subject],
  );
  const rawExists = raw.rows.length > 0;
  const rawBinding = (raw.rows[0] as { privy_user_id?: unknown } | undefined)?.privy_user_id;
  const mappedProfileId = typeof mappedId === "string" ? mappedId : undefined;
  return {
    profileId: mappedProfileId ?? subject,
    conflictingRawBinding: (
      rawExists
      && mappedProfileId !== undefined
      && mappedProfileId !== subject
    ) || (
      typeof rawBinding === "string"
      && rawBinding.length > 0
      && rawBinding !== subject
    ),
  };
}

function bearerToken(header: string | string[] | undefined): string | undefined {
  const value = Array.isArray(header) ? header[0] : header;
  const match = value?.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1];
}

function normalizeRow(value: unknown): {
  profileId: string;
  customized: boolean;
  placesCount: number;
  reviewItemsCount: number;
  conflictingBinding: boolean;
} {
  const row = (value ?? {}) as AccountStatusRow;
  if (typeof row.profile_id !== "string" || !row.profile_id) {
    throw new Error("Account status query returned an invalid profile");
  }
  return {
    profileId: row.profile_id,
    customized: row.profile_customized === true,
    placesCount: nonNegativeInteger(row.places_count),
    reviewItemsCount: nonNegativeInteger(row.review_items_count),
    conflictingBinding: row.conflicting_binding === true,
  };
}

function nonNegativeInteger(value: unknown): number {
  const number = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(number) || number < 0) {
    throw new Error("Account status query returned an invalid count");
  }
  return number;
}
