import type { Pool, PoolClient } from "pg";

export class FriendRatingError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireID(id: string): void {
  if (!uuid.test(id)) throw new FriendRatingError("Invalid place id", 400);
}

// Explicit allowlist: no private note, source, photo, visit time, profile fields,
// imported rating, or materialized social signal can enter this projection.
const projection = `p.id, p.name, p.address, p.latitude, p.longitude,
  p.google_place_id, p.category, p.coordinate_system, p.location_provider,
  p.provider_place_id, p.provider_map_url, r.stars, r.shared_at,
  actor.display_name as author_name, actor.handle as author_handle`;

const joins = `from friend_restaurant_ratings r
  join places p on (p.id, p.user_id) = (r.place_id, r.user_id)
  join profiles actor on actor.id = r.user_id
  join place_visibility pv on (pv.place_id, pv.user_id) = (p.id, p.user_id)`;

const legacyRating = `r.stars is not null and coalesce(to_jsonb(r)->>'shared_status', 'visited') = 'visited'`;

const visible = `r.shared_at is not null and p.status = 'visited' and ${legacyRating}
  and pv.visibility in ('friends', 'public_link', 'public_guide')
  and pv.allow_friend_signal = true
  and exists (select 1 from follows f where f.follower_id = $1 and f.following_id = r.user_id)`;

const restaurant = `p.category in ('food', 'cafe', 'bar')
  and p.latitude between -90 and 90 and p.longitude between -180 and 180
  and not (p.latitude = 0 and p.longitude = 0)
  and (nullif(trim(p.google_place_id), '') is not null
    or (nullif(trim(p.provider_place_id), '') is not null
      and p.location_provider in ('apple_maps', 'google_places', 'amap', 'baidu')))`;

export async function listFriendRatings(pool: Pool, userId: string, url: URL) {
  const limit = Number(url.searchParams.get("limit") ?? 20);
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new FriendRatingError("Invalid limit", 400);
  let before: string | null = null;
  let beforeID: string | null = null;
  const cursor = url.searchParams.get("cursor");
  if (cursor) {
    try {
      if (cursor.length > 512) throw new Error();
      const value = JSON.parse(Buffer.from(cursor, "base64url").toString());
      if (value.user !== userId || !uuid.test(value.id) || !Number.isFinite(Date.parse(value.date))) throw new Error();
      before = value.date; beforeID = value.id;
    } catch { throw new FriendRatingError("Invalid cursor", 400); }
  }
  const { rows } = await pool.query(
    `select ${projection} ${joins} where ${visible} and ${restaurant}
      and ($2::timestamptz is null or (r.shared_at, p.id) < ($2::timestamptz, $3::uuid))
      order by r.shared_at desc, p.id desc limit $4`, [userId, before, beforeID, limit + 1]);
  const items = rows.slice(0, limit);
  const last = items.at(-1);
  return { items, nextCursor: rows.length > limit && last
    ? Buffer.from(JSON.stringify({ user: userId, date: last.shared_at, id: last.id })).toString("base64url") : null };
}

export async function getFriendRating(pool: Pool, userId: string, placeID: string) {
  requireID(placeID);
  const { rows } = await pool.query(`select ${projection} ${joins}
    where ${visible} and ${restaurant} and p.id = $2`, [userId, placeID]);
  if (!rows[0]) throw new FriendRatingError("Shared rating not found", 404);
  return rows[0];
}

export async function ownFriendRatings(pool: Pool, userId: string) {
  // Owners manage explicit sharing consent even when the place is currently
  // private or unvisited. Recipient reads still enforce every visibility gate.
  const { rows } = await pool.query(`select r.place_id, p.name as place_name, r.stars,
    (r.shared_at is not null) as shared
    from friend_restaurant_ratings r
    join places p on (p.id, p.user_id) = (r.place_id, r.user_id)
    where r.user_id = $1 and ${legacyRating} and ${restaurant} order by r.updated_at desc`, [userId]);
  return rows;
}

export async function putFriendRating(pool: Pool, userId: string, placeID: string, body: Record<string, unknown>) {
  requireID(placeID);
  if (Object.keys(body).some((key) => !["stars", "eaten", "shared"].includes(key))) {
    throw new FriendRatingError("Unsupported rating field", 400);
  }
  if (typeof body.stars !== "number" || !Number.isFinite(body.stars) || body.stars < 1 || body.stars > 5
      || body.eaten !== true || typeof body.shared !== "boolean") {
    throw new FriendRatingError("Choose 1–5 stars and confirm you have eaten here", 400);
  }
  return transaction(pool, async (client) => {
    const { rows } = await client.query(`select p.id from places p
      where p.id = $1 and p.user_id = $2 and ${restaurant} for update`, [placeID, userId]);
    if (!rows[0]) throw new FriendRatingError("Confirmed restaurant not found", 404);
    await client.query(`update places set status = 'visited', updated_at = now()
      where id = $1 and user_id = $2`, [placeID, userId]);
    // Keep legacy clients usable before and after the additive post migration.
    const columns = await client.query(`select exists (select 1 from pg_attribute
      where attrelid = 'friend_restaurant_ratings'::regclass and attname = 'shared_status' and not attisdropped) as posts`);
    const statusColumn = columns.rows[0]?.posts ? ", shared_status" : "";
    const statusValue = columns.rows[0]?.posts ? ", 'visited'" : "";
    const statusUpdate = columns.rows[0]?.posts ? "shared_status = 'visited'," : "";
    await client.query(`insert into friend_restaurant_ratings (place_id, user_id, stars, shared_at${statusColumn})
      values ($1, $2, $3, case when $4 then date_trunc('milliseconds', now()) else null end${statusValue})
      on conflict (place_id) do update set stars = excluded.stars, ${statusUpdate}
        shared_at = case when $4 then coalesce(friend_restaurant_ratings.shared_at, date_trunc('milliseconds', now())) else null end,
        updated_at = now()`, [placeID, userId, body.stars, body.shared]);
    if (body.shared) {
      await client.query(`insert into place_visibility (place_id, user_id, visibility, allow_friend_signal, published_at)
        values ($1, $2, 'friends', true, now())
        on conflict (place_id) do update set
          visibility = case when place_visibility.visibility = 'private' then 'friends' else place_visibility.visibility end,
          allow_friend_signal = true, published_at = coalesce(place_visibility.published_at, now()), updated_at = now()`,
      [placeID, userId]);
    }
    return { place_id: placeID, stars: body.stars, shared: body.shared };
  });
}

export async function withdrawFriendRating(pool: Pool, userId: string, placeID: string) {
  requireID(placeID);
  const result = await pool.query(`update friend_restaurant_ratings set shared_at = null, updated_at = now()
    where place_id = $1 and user_id = $2 returning place_id`, [placeID, userId]);
  if (!result.rows[0]) throw new FriendRatingError("Rating not found", 404);
}

export async function saveFriendRating(pool: Pool, userId: string, placeID: string) {
  requireID(placeID);
  return transaction(pool, async (client) => {
    // Serialize saves by recipient, including different friends sharing the same
    // canonical venue. Recheck current access inside the save transaction.
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [userId]);
    const { rows } = await client.query(`select p.id, p.name, p.address, p.latitude, p.longitude,
      p.google_place_id, p.category, p.coordinate_system, p.location_provider,
      p.provider_place_id, p.provider_map_url ${joins}
      where ${visible} and ${restaurant} and p.id = $2 for share of r, p, pv`, [userId, placeID]);
    const source = rows[0];
    if (!source) throw new FriendRatingError("Shared rating not found", 404);
    const existing = await client.query(`select * from places where user_id = $1
      and ((google_place_id is not null and google_place_id = $2)
        or (provider_place_id is not null and provider_place_id = $3 and location_provider = $4))
      order by created_at, id limit 1`, [userId, source.google_place_id, source.provider_place_id, source.location_provider]);
    let place = existing.rows[0];
    if (!place) {
      const inserted = await client.query(`insert into places
        (user_id, name, address, latitude, longitude, google_place_id, category,
          coordinate_system, location_provider, provider_place_id, provider_map_url, status)
        values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'wantToGo') returning *`,
      [userId, source.name, source.address, source.latitude, source.longitude, source.google_place_id,
        source.category, source.coordinate_system, source.location_provider, source.provider_place_id, source.provider_map_url]);
      place = inserted.rows[0];
    }
    await client.query(`insert into friend_rating_saves (recipient_place_id, source_place_id)
      values ($1, $2) on conflict do nothing`, [place.id, placeID]);
    return place;
  });
}

export async function savedFriendAttributions(pool: Pool, userId: string) {
  const { rows } = await pool.query(`select s.recipient_place_id, ${projection} ${joins}
    join friend_rating_saves s on s.source_place_id = r.place_id
    join places recipient on recipient.id = s.recipient_place_id
    where recipient.user_id = $1 and ${visible} and ${restaurant}`, [userId]);
  return rows;
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
