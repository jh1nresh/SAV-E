import type { JsonObject } from "./socialContracts.js";

const defaultPageSize = 20;
const maximumPageSize = 50;
const legacyPageSize = 100;
const maximumSearchLength = 64;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface FollowedFriend {
  id: string;
  displayName: string;
  handle: string | null;
  avatarUrl: string | null;
}

export interface FollowedFriendPage {
  items: FollowedFriend[];
  nextCursor: string | null;
}

export interface FollowListOptions {
  search: string;
  limit: number;
  cursor: string | null;
}

interface DecodedCursor {
  createdAt: string;
  id: string;
  search: string;
}

interface FollowListQueryResult {
  rows: JsonObject[];
}

type FollowListQuery = (sql: string, values: readonly unknown[]) => Promise<FollowListQueryResult>;

export class FollowListInputError extends Error {}

export function normalizeFollowListOptions(input: {
  search: string | null;
  limit: string | null;
  cursor: string | null;
}): FollowListOptions {
  const search = normalizeSearch(input.search);
  const limit = normalizeLimit(input.limit);
  const cursor = input.cursor?.trim() || null;
  if (cursor) decodeCursor(cursor, search);
  return { search, limit, cursor };
}

export async function listFollowedFriendsPage(
  userId: string,
  options: FollowListOptions,
  query: FollowListQuery,
): Promise<FollowedFriendPage> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");

  const cursor = options.cursor ? decodeCursor(options.cursor, options.search) : null;
  const searchPattern = options.search ? `%${escapeLike(options.search)}%` : null;
  const { rows } = await query(
    `select
       f.id::text as follow_id,
       f.created_at,
       followed.display_name,
       followed.handle,
       followed.avatar_url
     from follows f
     join profiles followed on followed.id = f.following_id
     where f.follower_id = $1
       and (
         $2::text is null
         or coalesce(followed.display_name, '') ilike $2 escape '\\'
         or coalesce(followed.handle, '') ilike $2 escape '\\'
       )
       and (
         $3::timestamptz is null
         or (f.created_at, f.id) < ($3::timestamptz, $4::uuid)
       )
     order by f.created_at desc, f.id desc
     limit $5`,
    [
      userId,
      searchPattern,
      cursor?.createdAt ?? null,
      cursor?.id ?? null,
      options.limit + 1,
    ],
  );

  const mapped = rows.flatMap((row) => {
    const id = stringValue(row.follow_id);
    const createdAt = timestampValue(row.created_at);
    if (!id || !createdAt) return [];

    return [{
      friend: {
        id,
        displayName: stringValue(row.display_name) ?? stringValue(row.handle) ?? "SAV-E User",
        handle: stringValue(row.handle) ?? null,
        avatarUrl: stringValue(row.avatar_url) ?? null,
      },
      createdAt,
    }];
  });
  const pageRows = mapped.slice(0, options.limit);
  const last = pageRows.at(-1);

  return {
    items: pageRows.map((row) => row.friend),
    nextCursor: mapped.length > options.limit && last
      ? encodeCursor({ createdAt: last.createdAt, id: last.friend.id, search: options.search })
      : null,
  };
}

export async function listFollowedFriends(
  userId: string,
  query: FollowListQuery,
): Promise<FollowedFriend[]> {
  const page = await listFollowedFriendsPage(
    userId,
    { search: "", limit: legacyPageSize, cursor: null },
    query,
  );
  return page.items;
}

export async function unfollowByRelationshipId(
  userId: string,
  followId: string,
  query: FollowListQuery,
): Promise<void> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");
  if (!uuidPattern.test(followId)) throw new FollowListInputError("Follow id must be a UUID");

  await query(
    `delete from follows
     where id = $1
       and follower_id = $2
     returning id`,
    [followId, userId],
  );
}

function normalizeSearch(value: string | null): string {
  const normalized = (value ?? "")
    .trim()
    .replace(/^@+/, "")
    .replace(/\s+/g, " ")
    .trim();
  if ([...normalized].length > maximumSearchLength) {
    throw new FollowListInputError(`Search must be ${maximumSearchLength} characters or fewer`);
  }
  return normalized;
}

function normalizeLimit(value: string | null): number {
  if (value === null || value.trim() === "") return defaultPageSize;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximumPageSize) {
    throw new FollowListInputError(`Limit must be an integer from 1 to ${maximumPageSize}`);
  }
  return parsed;
}

function encodeCursor(cursor: DecodedCursor): string {
  return Buffer.from(JSON.stringify({
    v: 1,
    createdAt: cursor.createdAt,
    id: cursor.id,
    search: cursor.search,
  })).toString("base64url");
}

function decodeCursor(value: string, expectedSearch: string): DecodedCursor {
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as Record<string, unknown>;
    const createdAt = timestampValue(decoded.createdAt);
    const id = stringValue(decoded.id);
    const search = typeof decoded.search === "string" ? decoded.search : undefined;
    if (decoded.v !== 1 || !createdAt || !id || !uuidPattern.test(id) || search !== expectedSearch) {
      throw new Error("invalid cursor payload");
    }
    return { createdAt, id, search };
  } catch {
    throw new FollowListInputError("Invalid or mismatched follow cursor");
  }
}

function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (character) => `\\${character}`);
}

function timestampValue(value: unknown): string | undefined {
  const date = value instanceof Date ? value : typeof value === "string" ? new Date(value) : undefined;
  if (!date || Number.isNaN(date.getTime())) return undefined;
  return date.toISOString();
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}
