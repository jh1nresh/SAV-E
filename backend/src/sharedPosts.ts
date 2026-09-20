import type { Pool, PoolClient } from "pg";
import { FriendRatingError } from "./friendRatings.js";
import { sharedPostPhotos } from "./sharedPostPhotos.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function requireID(id: string) {
  if (!uuid.test(id)) throw new FriendRatingError("Invalid place id", 400);
}
// Venue identity only: private status, note, photos, ratings and timestamps never
// enter a post. The explicitly authored status and caption are separate memory.
const venue = `p.latitude between -90 and 90 and p.longitude between -180 and 180
  and not (p.latitude = 0 and p.longitude = 0)
  and (nullif(trim(p.google_place_id), '') is not null
    or (nullif(trim(p.provider_place_id), '') is not null
      and p.location_provider in ('apple_maps', 'google_places', 'amap', 'baidu')))`;
const audience = `pv.visibility in ('friends', 'public_link', 'public_guide') and pv.allow_friend_signal = true`;
const joins = `from friend_restaurant_ratings r
  join places p on (p.id, p.user_id) = (r.place_id, r.user_id)
  join profiles actor on actor.id = r.user_id
  join place_visibility pv on (pv.place_id, pv.user_id) = (p.id, p.user_id)`;
const visible = `r.shared_at is not null and ${venue} and ${audience}
  and exists (select 1 from follows f where f.follower_id = $1 and f.following_id = r.user_id)`;
const projection = `p.id, p.name, p.address, p.latitude, p.longitude, p.category,
  p.google_place_id, p.coordinate_system, p.location_provider, p.provider_place_id, p.provider_map_url,
  r.shared_status as status, r.stars, r.caption, r.shared_at,
  cardinality(r.photo_data) as photo_count, r.updated_at as photo_version,
  actor.id as author_id, coalesce(actor.display_name, actor.handle, 'Savvy User') as author_name,
  actor.handle as author_handle, actor.avatar_url as author_avatar_url,
  (${audience}) as visible_to_followers`;
type Queryable = Pick<Pool, "query">;

function pageOptions(user: string, route: string, url: URL) {
  const limit = Number(url.searchParams.get("limit") ?? 20);
  const status = url.searchParams.get("status") ?? "all";
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new FriendRatingError("Invalid limit", 400);
  if (!["all", "wantToGo", "visited"].includes(status)) throw new FriendRatingError("Invalid status", 400);
  let date: string | null = null, id: string | null = null;
  const cursor = url.searchParams.get("cursor");
  if (cursor) {
    try {
      if (cursor.length > 2048) throw new Error();
      const value = JSON.parse(Buffer.from(cursor, "base64url").toString());
      if (value.user !== user || value.route !== route || value.status !== status
        || typeof value.id !== "string" || !uuid.test(value.id)
        || typeof value.date !== "string" || !Number.isFinite(Date.parse(value.date))) throw new Error();
      date = value.date; id = value.id;
    } catch { throw new FriendRatingError("Invalid cursor", 400); }
  }
  return { user, route, status, limit, date, id };
}

export async function listSharedPosts(pool: Queryable, userId: string, url: URL, mode: "feed" | "mine" = "feed", authorId?: string) {
  const options = pageOptions(userId, authorId === undefined ? mode : `passport:${authorId}`, url);
  // Mine includes paused posts for the owner. Author passports show only active
  // audience-visible posts, including when the owner previews their passport.
  const access = authorId === undefined && mode === "mine"
    ? `r.shared_at is not null and r.user_id = $1 and ${venue}`
    : authorId === userId
      ? `r.shared_at is not null and r.user_id = $1 and ${venue} and ${audience}`
      : visible;
  const { rows } = await pool.query(`select ${projection} ${joins} where ${access}
    and ($2::text = 'all' or r.shared_status = $2)
    and ($3::timestamptz is null or (r.shared_at, p.id) < ($3::timestamptz, $4::uuid))
    and ($5::text is null or r.user_id = $5)
    order by r.shared_at desc, p.id desc limit $6`,
  [userId, options.status, options.date, options.id, authorId ?? null, options.limit + 1]);
  const items = rows.slice(0, options.limit), last = items.at(-1);
  return { items, nextCursor: rows.length > options.limit && last
    ? Buffer.from(JSON.stringify({ user: userId, route: options.route, status: options.status, date: last.shared_at, id: last.id })).toString("base64url") : null };
}

export async function getSharedPost(pool: Queryable, userId: string, placeID: string) {
  requireID(placeID);
  const { rows } = await pool.query(`select ${projection} ${joins}
    where p.id = $2 and r.shared_at is not null and ${venue}
      and (r.user_id = $1 or (${visible}))`, [userId, placeID]);
  if (!rows[0]) throw new FriendRatingError("Shared post not found", 404);
  return rows[0];
}

export async function getSharedPostPhoto(pool: Queryable, userId: string, placeID: string, index: string) {
  requireID(placeID);
  if (!/^[0-2]$/.test(index)) throw new FriendRatingError("Photo not found", 404);
  // Read authorization and bytes in one statement snapshot. No public URL or cache.
  const { rows } = await pool.query(`select r.photo_data[$3::int + 1] as data ${joins}
    where p.id = $2 and r.shared_at is not null and ${venue}
      and (r.user_id = $1 or (${visible}))`, [userId, placeID, Number(index)]);
  if (!rows[0]?.data) throw new FriendRatingError("Photo not found", 404);
  return rows[0].data as Buffer;
}

export async function putSharedPost(pool: Pool, userId: string, placeID: string, body: Record<string, unknown>) {
  requireID(placeID);
  if (Object.keys(body).some(key => !["status", "stars", "caption", "photos"].includes(key))
    || typeof body.status !== "string" || !["wantToGo", "visited"].includes(body.status)
    || (body.stars !== null && (typeof body.stars !== "number" || !Number.isFinite(body.stars) || body.stars < 1 || body.stars > 5))
    || (body.status === "wantToGo" && body.stars !== null)
    || (body.caption !== null && (typeof body.caption !== "string" || [...body.caption].length > 500))) {
    throw new FriendRatingError("Choose a post status, optional caption and optional visited rating", 400);
  }
  const photos = sharedPostPhotos(body.photos);
  return transaction(pool, async client => {
    const { rows } = await client.query(`select p.id from places p where p.id = $1 and p.user_id = $2 and ${venue} for update`, [placeID, userId]);
    if (!rows[0]) throw new FriendRatingError("Confirmed place not found", 404);
    await client.query(`insert into friend_restaurant_ratings (place_id, user_id, stars, caption, shared_status, shared_at, photo_data)
      values ($1,$2,$3,$4,$5,date_trunc('milliseconds', now()),coalesce($6::bytea[], '{}'::bytea[]))
      on conflict (place_id) do update set stars = excluded.stars, caption = excluded.caption,
        shared_status = excluded.shared_status,
        photo_data = coalesce($6::bytea[], friend_restaurant_ratings.photo_data),
        shared_at = coalesce(friend_restaurant_ratings.shared_at, excluded.shared_at), updated_at = now()`,
    [placeID, userId, body.stars, body.caption, body.status, photos ?? null]);
    await client.query(`insert into place_visibility (place_id, user_id, visibility, allow_friend_signal, published_at)
      values ($1,$2,'friends',true,now()) on conflict (place_id) do update set
      visibility = case when place_visibility.visibility = 'private' then 'friends' else place_visibility.visibility end,
      allow_friend_signal = true, published_at = coalesce(place_visibility.published_at, now()), updated_at = now()`, [placeID, userId]);
    return getSharedPost(client, userId, placeID);
  });
}

export async function withdrawSharedPost(pool: Pool, userId: string, placeID: string) {
  requireID(placeID);
  const { rows } = await pool.query(`update friend_restaurant_ratings set shared_at = null, photo_data = '{}', updated_at = now()
    where place_id = $1 and user_id = $2 returning place_id`, [placeID, userId]);
  if (!rows[0]) throw new FriendRatingError("Shared post not found", 404);
}

export async function saveSharedPost(pool: Pool, userId: string, placeID: string) {
  requireID(placeID);
  return transaction(pool, async client => {
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [userId]);
    const { rows } = await client.query(`select ${projection} ${joins}
      where ${visible} and p.id = $2 for share of r, p, pv`, [userId, placeID]);
    const source = rows[0];
    if (!source) throw new FriendRatingError("Shared post not found", 404);
    const follow = await client.query(`select id from follows where follower_id = $1 and following_id = $2 for share`, [userId, source.author_id]);
    if (!follow.rows[0]) throw new FriendRatingError("Shared post not found", 404);
    const existing = await client.query(`select * from places where user_id = $1
      and ((google_place_id is not null and google_place_id = $2)
        or (provider_place_id is not null and provider_place_id = $3 and location_provider = $4))
      order by created_at, id limit 1`, [userId, source.google_place_id, source.provider_place_id, source.location_provider]);
    let place = existing.rows[0];
    if (!place) {
      const inserted = await client.query(`insert into places
        (user_id,name,address,latitude,longitude,google_place_id,category,coordinate_system,location_provider,provider_place_id,provider_map_url,status)
        values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'wantToGo') returning *`,
      [userId, source.name, source.address, source.latitude, source.longitude, source.google_place_id, source.category,
        source.coordinate_system, source.location_provider, source.provider_place_id, source.provider_map_url]);
      place = inserted.rows[0];
    }
    await client.query(`insert into friend_rating_saves (recipient_place_id, source_place_id) values ($1,$2) on conflict do nothing`, [place.id, placeID]);
    return place;
  });
}

export async function savedPostAttributions(pool: Pool, userId: string) {
  const { rows } = await pool.query(`select s.recipient_place_id, ${projection} ${joins}
    join friend_rating_saves s on s.source_place_id = r.place_id
    join places recipient on recipient.id = s.recipient_place_id
    where recipient.user_id = $1 and ${visible}`, [userId]);
  return rows;
}

export async function getPassport(pool: Pool, userId: string, authorId: string, url: URL) {
  // One statement snapshot prevents an unfollow between profile and posts reads
  // from disclosing an author projection after the access check.
  return transaction(pool, async client => {
    await client.query("set transaction isolation level repeatable read, read only");
    const { rows } = await client.query(`select profile.id, coalesce(profile.display_name, profile.handle, 'Savvy User') as "displayName",
      profile.handle, profile.avatar_url as "avatarUrl",
      (select count(*)::int ${joins} where r.user_id = profile.id and r.shared_at is not null and ${venue} and ${audience}) as "postCount"
      from profiles profile where profile.id = $2 and (profile.id = $1 or exists
        (select 1 from follows f where f.follower_id = $1 and f.following_id = profile.id))`, [userId, authorId]);
    if (!rows[0]) throw new FriendRatingError("Passport not found", 404);
    const page = await listSharedPosts(client, userId, url, "feed", authorId);
    return { profile: rows[0], ...page };
  });
}

export async function getSocialProfile(pool: Pool, userId: string) {
  const { rows } = await pool.query(`select
    (select count(*)::int ${joins} where r.user_id = $1 and r.shared_at is not null and ${venue}) as "postCount",
    (select count(*)::int from follows where follower_id = $1) as "followingCount",
    (select count(*)::int from follows where following_id = $1) as "followerCount"`, [userId]);
  return rows[0];
}

async function transaction<T>(pool: Pool, operation: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const result = await operation(client);
    await client.query("commit");
    return result;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally { client.release(); }
}
