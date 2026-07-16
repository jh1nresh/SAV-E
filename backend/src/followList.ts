import type { JsonObject } from "./socialContracts.js";

export interface FollowedFriend {
  id: string;
  displayName: string;
  handle: string | null;
  avatarUrl: string | null;
}

interface FollowListQueryResult {
  rows: JsonObject[];
}

type FollowListQuery = (sql: string, values: readonly unknown[]) => Promise<FollowListQueryResult>;

export async function listFollowedFriends(
  userId: string,
  query: FollowListQuery,
): Promise<FollowedFriend[]> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");

  const { rows } = await query(
    `select
       f.id::text as follow_id,
       followed.display_name,
       followed.handle,
       followed.avatar_url
     from follows f
     join profiles followed on followed.id = f.following_id
     where f.follower_id = $1
     order by f.created_at desc, f.id desc
     limit 100`,
    [userId],
  );

  return rows.flatMap((row) => {
    const id = stringValue(row.follow_id);
    if (!id) return [];

    return [{
      id,
      displayName: stringValue(row.display_name) ?? stringValue(row.handle) ?? "SAV-E User",
      handle: stringValue(row.handle) ?? null,
      avatarUrl: stringValue(row.avatar_url) ?? null,
    }];
  });
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}
