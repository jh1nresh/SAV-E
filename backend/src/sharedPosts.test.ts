import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import pg from "pg";
import { getPassport, getSharedPost, getSocialProfile, listSharedPosts, putSharedPost, savedPostAttributions, saveSharedPost, withdrawSharedPost } from "./sharedPosts.js";
import { getFriendRating, listFriendRatings, ownFriendRatings, putFriendRating, savedFriendAttributions } from "./friendRatings.js";
import { listFollowedFriendsPage, normalizeFollowListOptions } from "./followList.js";

const first = "a1111111-1111-4111-8111-111111111111", second = "a2222222-2222-4222-8222-222222222222";
const A = "posts-test-A", B = "posts-test-B", C = "posts-test-C";
const body = { status: "wantToGo", stars: null, caption: "A place to explore" };
const url = new URL("http://localhost/v0/shared-posts?limit=1");

test("posts reject spoofed authors, private fields, invalid status/rating/caption before database access", async () => {
  for (const input of [
    { ...body, user_id: B }, { ...body, note: "private" }, { ...body, status: "unknown" },
    { ...body, stars: 4 }, { ...body, status: "visited", stars: 6 }, { ...body, stars: undefined },
    { ...body, caption: "😀".repeat(501) }, { ...body, caption: {} },
  ]) await assert.rejects(putSharedPost({} as pg.Pool, A, first, input), { status: 400 });
});

test("post pagination binds viewer, route, author and status with timestamp/id ties", async () => {
  const pool = { query: async () => ({ rows: [
    { id: second, shared_at: "2026-09-16T00:00:00.000Z" },
    { id: first, shared_at: "2026-09-16T00:00:00.000Z" },
  ] }) } as unknown as pg.Pool;
  const page = await listSharedPosts(pool, A, url);
  assert.ok(page.nextCursor);
  const next = new URL(url); next.searchParams.set("cursor", page.nextCursor!);
  await listSharedPosts(pool, A, next);
  await assert.rejects(listSharedPosts(pool, B, next), { status: 400 });
  await assert.rejects(listSharedPosts(pool, A, next, "mine"), { status: 400 });
  await assert.rejects(listSharedPosts(pool, A, next, "feed", B), { status: 400 });
  next.searchParams.set("status", "visited");
  await assert.rejects(listSharedPosts(pool, A, next), { status: 400 });
});

test("failed post publication rolls back and releases its connection", async () => {
  const calls: string[] = [];
  const pool = { connect: async () => ({
    query: async (sql: string) => { calls.push(sql); if (sql.includes("insert into friend")) throw new Error("write failed"); return { rows: [{ id: first }] }; },
    release: () => calls.push("release"),
  }) } as unknown as pg.Pool;
  await assert.rejects(putSharedPost(pool, B, first, body), /write failed/);
  assert.equal(calls[0], "begin");
  assert.deepEqual(calls.slice(-2), ["rollback", "release"]);
  assert.ok(!calls.includes("commit"));
});

const databaseURL = process.env.SAVE_FRIENDS_TEST_DATABASE_URL;
test("PostgreSQL: generalized posts preserve private memory and all live audience boundaries", { skip: !databaseURL }, async () => {
  const database = new URL(databaseURL!);
  assert.ok(["127.0.0.1", "localhost", "[::1]"].includes(database.hostname));
  assert.equal(database.pathname, "/savvy_friends_test");
  const pool = new pg.Pool({ connectionString: databaseURL });
  try {
    for (const path of ["../sql/schema.sql", "../../supabase/migrations/20260815010000_places_provider_coordinates.sql", "../sql/friend-ratings.sql", "../sql/shared-posts.sql"])
      await pool.query(await readFile(new URL(path, import.meta.url), "utf8"));
    await pool.query("delete from profiles where id = any($1)", [[A, B, C]]);
    for (const user of [A, B, C]) await pool.query("insert into profiles(id,display_name,handle,email) values($1,$1,$1,'PRIVATE@example.invalid')", [user]);
    await pool.query(`insert into places(id,user_id,name,address,latitude,longitude,google_place_id,category,status,note,rating)
      values ($1,$3,'Museum','Fixture Street',25,121,'posts-museum','museum','wantToGo','PRIVATE NOTE',2),
      ($2,$3,'Cafe','Fixture Street',26,122,'posts-cafe','cafe','wantToGo','PRIVATE NOTE',3)`, [first, second, B]);
    await pool.query("insert into follows(follower_id,following_id) values($1,$2)", [A, B]);
    await assert.rejects(putSharedPost(pool, A, first, body), { status: 404 });
    assert.equal((await listSharedPosts(pool, A, url)).items.length, 0);
    const shared = await putSharedPost(pool, B, first, body);
    assert.equal(shared.status, "wantToGo"); assert.equal(shared.stars, null);
    assert.equal((await getSharedPost(pool, A, first)).author_id, B);
    assert.doesNotMatch(JSON.stringify(shared), /PRIVATE|email|note|visited_at|photo|created_at|rating"/);
    await assert.rejects(getSharedPost(pool, C, first), { status: 404 });
    await assert.rejects(getPassport(pool, C, B, url), { status: 404 });
    await assert.rejects(saveSharedPost(pool, C, first), { status: 404 });
    await assert.rejects(withdrawSharedPost(pool, A, first), { status: 404 });
    const edited = await putSharedPost(pool, B, first, { status: "visited", stars: 4, caption: "Seen it" });
    assert.equal(new Date(edited.shared_at).getTime(), new Date(shared.shared_at).getTime());
    assert.equal((await pool.query("select status from places where id = $1", [first])).rows[0].status, "wantToGo");
    await putSharedPost(pool, B, second, body);
    await pool.query("update friend_restaurant_ratings set shared_at = '2026-09-16T00:00:00Z' where user_id=$1", [B]);
    const page = await listSharedPosts(pool, A, url); assert.equal(page.items[0].id, second);
    const next = new URL(url); next.searchParams.set("cursor", page.nextCursor!);
    assert.equal((await listSharedPosts(pool, A, next)).items[0].id, first);
    const filtered = new URL(url); filtered.searchParams.set("status", "wantToGo");
    assert.deepEqual((await listSharedPosts(pool, A, filtered)).items.map(x => x.id), [second]);
    assert.equal((await getPassport(pool, A, B, url)).profile.postCount, 2);
    assert.deepEqual(await getSocialProfile(pool, B), { postCount: 2, followingCount: 0, followerCount: 1 });
    const following = await listFollowedFriendsPage(A, normalizeFollowListOptions({ search: null, limit: null, cursor: null }), (sql, args) => pool.query(sql, [...args]));
    assert.equal(following.items[0].profileId, B); assert.notEqual(following.items[0].id, B);
    const followers = await listFollowedFriendsPage(B, normalizeFollowListOptions({ search: null, limit: null, cursor: null }), (sql, args) => pool.query(sql, [...args]), "followers");
    assert.equal(followers.items[0].profileId, A);
    assert.equal((await listFriendRatings(pool, A, url)).items.length, 0);
    assert.deepEqual(await ownFriendRatings(pool, B), [{ place_id: first, place_name: "Museum", stars: 4, shared: true }],
      "the withdrawal-only legacy owner list accepts rated posts; it must not hide consent after category edits");
    const [saved, repeated] = await Promise.all([saveSharedPost(pool, A, first), saveSharedPost(pool, A, first)]);
    assert.equal(saved.id, repeated.id); assert.equal(saved.status, "wantToGo"); assert.equal(saved.note, null); assert.equal(saved.rating, null);
    assert.equal((await savedPostAttributions(pool, A))[0].recipient_place_id, saved.id);
    assert.deepEqual(await savedFriendAttributions(pool, A), []);
    await pool.query("update places set status='visited',note='MY MEMORY',rating=1 where id=$1", [saved.id]);
    const retained = await saveSharedPost(pool, A, first);
    assert.equal(retained.note, "MY MEMORY"); assert.equal(retained.rating, 1); assert.equal(retained.status, "visited");
    await pool.query("update place_visibility set visibility='private' where place_id=$1", [first]);
    assert.equal((await getSharedPost(pool, B, first)).visible_to_followers, false);
    assert.ok((await listSharedPosts(pool, B, new URL("http://localhost?limit=50"), "mine")).items.some(x => x.id === first && !x.visible_to_followers));
    assert.equal((await getPassport(pool, B, B, url)).profile.postCount, 1);
    assert.equal((await getSocialProfile(pool, B)).postCount, 2, "owner count matches mine, including paused posts");
    await assert.rejects(getSharedPost(pool, A, first), { status: 404 });
    await assert.rejects(saveSharedPost(pool, A, first), { status: 404 });
    assert.deepEqual(await savedPostAttributions(pool, A), []);
    await putSharedPost(pool, B, first, body);
    await withdrawSharedPost(pool, B, first);
    await assert.rejects(getSharedPost(pool, B, first), { status: 404 });
    await assert.rejects(getSharedPost(pool, A, first), { status: 404 });
    assert.deepEqual(await savedPostAttributions(pool, A), []);
    await putSharedPost(pool, B, first, body);
    await pool.query("delete from follows where follower_id=$1", [A]);
    assert.equal((await listSharedPosts(pool, A, url)).items.length, 0);
    await assert.rejects(getPassport(pool, A, B, url), { status: 404 });
    await assert.rejects(getSharedPost(pool, A, first), { status: 404 });
    await assert.rejects(saveSharedPost(pool, A, first), { status: 404 });
    assert.deepEqual(await savedPostAttributions(pool, A), []);
    assert.deepEqual((await pool.query("select status,note,rating from places where id=$1", [saved.id])).rows[0], { status: "visited", note: "MY MEMORY", rating: 1 });
    // Legacy PUT must turn a want-to-go post into a compatible visited rating.
    await putFriendRating(pool, B, second, { stars: 4.5, eaten: true, shared: true });
    assert.equal((await getSharedPost(pool, B, second)).status, "visited");
    await pool.query("insert into follows(follower_id,following_id) values($1,$2)", [A, B]);
    assert.equal((await getFriendRating(pool, A, second)).stars, 4.5);
    assert.equal((await ownFriendRatings(pool, B)).length, 1);
  } finally { await pool.end(); }
});
