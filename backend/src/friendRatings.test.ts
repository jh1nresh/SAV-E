import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import pg from "pg";
import {
  listFriendRatings, getFriendRating, ownFriendRatings, putFriendRating,
  saveFriendRating, savedFriendAttributions, withdrawFriendRating,
} from "./friendRatings.js";

const placeID = "11111111-1111-4111-8111-111111111111";
const secondID = "22222222-2222-4222-8222-222222222222";

test("rating rejects spoofed owners and missing affirmation before querying", async () => {
  const noDatabase = {} as pg.Pool;
  for (const body of [
    { stars: 4, shared: true }, { stars: 4, eaten: false, shared: true },
    { stars: 6, eaten: true, shared: true }, { stars: "5", eaten: true, shared: true },
    { stars: 4, eaten: true, shared: true, user_id: "B" },
  ]) {
    await assert.rejects(putFriendRating(noDatabase, "A", placeID, body));
  }
});

const databaseURL = process.env.SAVE_FRIENDS_TEST_DATABASE_URL;
test("authenticated HTTP Friends and legacy revocation boundaries", { skip: !databaseURL, timeout: 30000 }, async () => {
  await promisify(execFile)(process.execPath, [new URL("../scripts/friends-local-fixture.mjs", import.meta.url).pathname], {
    env: process.env, timeout: 25000,
  });
});

test("PostgreSQL: explicit share, pagination, recipient save and revocation", { skip: !databaseURL }, async () => {
  const url = new URL(databaseURL!);
  assert.ok(["127.0.0.1", "localhost", "[::1]"].includes(url.hostname), "test database must be local");
  assert.equal(url.pathname, "/savvy_friends_test", "dedicated test database required");
  const pool = new pg.Pool({ connectionString: databaseURL });
  try {
    await pool.query(await readFile(new URL("../sql/schema.sql", import.meta.url), "utf8"));
    await pool.query(await readFile(new URL("../../supabase/migrations/20260815010000_places_provider_coordinates.sql", import.meta.url), "utf8"));
    await pool.query(await readFile(new URL("../sql/friend-ratings.sql", import.meta.url), "utf8"));
    await pool.query("delete from profiles where id in ('friends-test-A', 'friends-test-B', 'friends-test-C')");
    await pool.query(`insert into profiles (id, display_name, handle, email) values
      ('friends-test-A','A','friends-test-a','private-a@example.invalid'),
      ('friends-test-B','B','friends-test-b','private-b@example.invalid'),
      ('friends-test-C','C','friends-test-c','private-c@example.invalid')`);
    await pool.query(`insert into places (id,user_id,name,address,latitude,longitude,google_place_id,category,rating,note)
      values ($1,'friends-test-B','Test restaurant','Test street',25,121,'test-canonical-1','food',2,'PRIVATE NOTE'),
      ($2,'friends-test-B','Second restaurant','Test street',26,122,'test-canonical-2','food',3,'PRIVATE RECEIPT')`, [placeID, secondID]);
    await pool.query("insert into follows (follower_id,following_id) values ('friends-test-A','friends-test-B')");
    const A = "friends-test-A", B = "friends-test-B", C = "friends-test-C";
    const pageURL = new URL("http://localhost/v0/friend-ratings?limit=1");
    const page = () => listFriendRatings(pool, A, pageURL);
    await putFriendRating(pool, B, placeID, { stars: 4.5, eaten: true, shared: false });
    assert.equal((await page()).items.length, 0, "private rating invisible to follower");
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 });
    await assert.rejects(putFriendRating(pool, A, placeID, { stars: 1, eaten: true, shared: true }), { status: 404 });
    await putFriendRating(pool, B, placeID, { stars: 4.5, eaten: true, shared: true });
    assert.equal((await page()).items[0].stars, 4.5);
    assert.equal((await listFriendRatings(pool, C, pageURL)).items.length, 0);
    await assert.rejects(getFriendRating(pool, C, placeID), { status: 404 });
    await assert.rejects(saveFriendRating(pool, C, placeID), { status: 404 });
    const publicRating = await getFriendRating(pool, A, placeID);
    assert.doesNotMatch(JSON.stringify(publicRating), /PRIVATE|private-b|note|source_url|rating"|created_at|visited_at|email/);
    assert.equal(publicRating.author_name, "B");
    const [saved, repeated] = await Promise.all([saveFriendRating(pool, A, placeID), saveFriendRating(pool, A, placeID)]);
    assert.equal(saved.id, repeated.id, "concurrent save is idempotent");
    assert.equal(saved.user_id, A);
    assert.equal(saved.status, "wantToGo");
    assert.equal(saved.rating, null);
    assert.equal(saved.note, null);
    assert.equal(saved.recommender, null);
    assert.equal((await savedFriendAttributions(pool, A))[0].author_name, "B");
    await putFriendRating(pool, B, placeID, { stars: 3.5, eaten: true, shared: true });
    assert.equal((await getFriendRating(pool, A, placeID)).stars, 3.5);
    await putFriendRating(pool, B, secondID, { stars: 5, eaten: true, shared: true });
    const firstPage = await page();
    assert.equal(firstPage.items[0].id, secondID);
    assert.ok(firstPage.nextCursor);
    const nextURL = new URL(pageURL);
    nextURL.searchParams.set("cursor", firstPage.nextCursor!);
    assert.equal((await listFriendRatings(pool, A, nextURL)).items[0].id, placeID);
    await assert.rejects(listFriendRatings(pool, C, nextURL), { status: 400 });
    await withdrawFriendRating(pool, B, placeID);
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 });
    await assert.rejects(saveFriendRating(pool, A, placeID), { status: 404 });
    assert.equal((await savedFriendAttributions(pool, A)).length, 0);
    assert.equal((await ownFriendRatings(pool, B)).find((r) => r.place_id === placeID)?.shared, false);
    await putFriendRating(pool, B, placeID, { stars: 4, eaten: true, shared: true });
    await pool.query("update place_visibility set visibility = 'private' where place_id = $1", [placeID]);
    const ownerShare = (await ownFriendRatings(pool, B)).find((r) => r.place_id === placeID);
    assert.equal(ownerShare?.shared, true, "private place must retain owner-visible explicit consent for withdrawal");
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 });
    assert.equal(ownerShare?.place_name, "Test restaurant");
    await withdrawFriendRating(pool, B, placeID);
    assert.equal((await ownFriendRatings(pool, B)).find((r) => r.place_id === placeID)?.shared, false);
    assert.equal((await pool.query("select visibility from place_visibility where place_id = $1", [placeID])).rows[0].visibility, "private");
    await pool.query("update place_visibility set visibility = 'friends' where place_id = $1", [placeID]);
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 }, "restoring place visibility cannot restore withdrawn consent");
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 });
    assert.equal((await savedFriendAttributions(pool, A)).length, 0);
    await putFriendRating(pool, B, placeID, { stars: 4, eaten: true, shared: true });
    await pool.query("delete from follows where follower_id = $1", [A]);
    assert.equal((await page()).items.length, 0);
    await assert.rejects(getFriendRating(pool, A, placeID), { status: 404 });
    assert.equal((await savedFriendAttributions(pool, A)).length, 0);
    const retained = await pool.query("select status, rating, note from places where id = $1 and user_id = $2", [saved.id, A]);
    assert.deepEqual(retained.rows, [{ status: "wantToGo", rating: null, note: null }]);
    await pool.query("insert into follows (follower_id,following_id) values ($1,$2)", [A, B]);
    await pool.query("update places set status = 'visited', rating = 1, note = 'A OWN NOTE' where id = $1", [saved.id]);
    const savedAgain = await saveFriendRating(pool, A, placeID);
    assert.equal(savedAgain.id, saved.id);
    assert.equal(savedAgain.status, "visited", "existing recipient visit is preserved");
    assert.equal(savedAgain.rating, 1, "author stars cannot overwrite recipient stars");
    assert.equal(savedAgain.note, "A OWN NOTE");
    await assert.rejects(withdrawFriendRating(pool, A, placeID), { status: 404 });
    await pool.query("update places set google_place_id = null, provider_place_id = null where id = $1", [secondID]);
    await assert.rejects(putFriendRating(pool, B, secondID, { stars: 4, eaten: true, shared: true }), { status: 404 });
  } finally { await pool.end(); }
});
