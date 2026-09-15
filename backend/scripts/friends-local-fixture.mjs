// Local-only authenticated HTTP fixture. Never reads production credentials.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Pool } from 'pg';
import { generateKeyPair, exportSPKI, SignJWT } from 'jose';
assert.ok(!process.argv.includes('--native'), 'Native Friends sharing fixture is retired; use --check for HTTP privacy verification.');
const databaseURL = process.env.SAVE_FRIENDS_TEST_DATABASE_URL;
const db = new URL(databaseURL ?? 'invalid:');
assert.ok(['127.0.0.1', 'localhost'].includes(db.hostname));
assert.equal(db.pathname, '/savvy_friends_test');
const port = 55442;
const base = `http://127.0.0.1:${port}`;
const pool = new Pool({ connectionString: databaseURL });
const placeID = '33333333-3333-4333-8333-333333333333';
const legacyID = '44444444-4444-4444-8444-444444444444';
const users = ['friends-http-A', 'friends-http-B', 'friends-http-C'];
const { privateKey, publicKey } = await generateKeyPair('ES256');
const tokens = await Promise.all(users.map(user => new SignJWT({}).setProtectedHeader({ alg: 'ES256' })
  .setSubject(user).setIssuer('privy.io').setAudience('friends-local-test').setIssuedAt().setExpirationTime('2h').sign(privateKey)));
const dir = await mkdtemp(join(tmpdir(), 'savvy-friends-http-'));
const hook = join(dir, 'local-only.mjs');
await writeFile(hook, `import { Server } from 'node:http';
const listen = Server.prototype.listen;
Server.prototype.listen = function(port, callback) { return listen.call(this, port, '127.0.0.1', callback); };
globalThis.fetch = async () => { throw new Error('External provider calls disabled in Friends fixture'); };
`);
async function seed() {
  await pool.query(await readFile(new URL('../sql/schema.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../../supabase/migrations/20260815010000_places_provider_coordinates.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../sql/friend-ratings.sql', import.meta.url), 'utf8'));
  await pool.query('delete from profiles where id = any($1)', [users]);
  for (const [i, user] of users.entries()) {
    await pool.query('insert into profiles(id,display_name,handle,referral_code) values($1,$2,$3,$4)',
      [user, `Local Friend ${'ABC'[i]}`, `local-friend-${'abc'[i]}`, `local-friend-${'abc'[i]}`]);
  }
  await pool.query(`insert into places(id,user_id,name,address,latitude,longitude,google_place_id,category,note,rating)
    values($1,$2,'Local Test Bistro','1 Fixture Street',25.033,121.565,'local-test-bistro','food','PRIVATE NOTE',2),
    ($3,$2,'Legacy Shared Cafe','2 Fixture Street',25.034,121.564,'local-test-legacy','cafe',null,null)`, [placeID, users[1], legacyID]);
  await pool.query(`insert into place_visibility(place_id,user_id,visibility,allow_friend_signal)
    values($1,$2,'friends',true)`, [legacyID, users[1]]);
  await pool.query('insert into follows(follower_id,following_id) values($1,$2)', [users[0], users[1]]);
}
await seed();
const child = spawn(process.execPath, ['--import', hook, new URL('../dist/server.js', import.meta.url).pathname], {
  env: { PATH: process.env.PATH, HOME: process.env.HOME, NODE_ENV: 'test', PORT: String(port),
    DATABASE_URL: databaseURL, PGSSLMODE: 'disable', PRIVY_APP_ID: 'friends-local-test',
    PRIVY_VERIFICATION_KEY: await exportSPKI(publicKey), SAVE_GUEST_SESSION_SECRET: 'local-fixture-only', SLLR_NOTIFY_INTERVAL_MS: '0' },
  stdio: ['ignore', 'pipe', 'pipe'],
});
const exited = once(child, 'exit');
let log = '';
child.stdout.on('data', data => { log = (log + data).slice(-20000); });
child.stderr.on('data', data => { log = (log + data).slice(-20000); });
async function api(who, path, method = 'GET', body) {
  const response = await fetch(base + path, { method, signal: AbortSignal.timeout(5000),
    headers: { 'Content-Type': 'application/json', ...(who === null ? {} : { Authorization: `Bearer ${tokens[who]}` }) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, cache: response.headers.get('cache-control') };
}
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error(log);
    try { if ((await api(null, '/')).status === 200) { ready = true; break; } } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(ready, log);
  assert.equal((await api(null, '/v0/friend-ratings')).status, 401);
  const path = `/v0/friend-ratings/${placeID}`;
  assert.equal((await api(0, path, 'PUT', { stars: 4, eaten: true, shared: true })).status, 404);
  assert.equal((await api(1, path, 'PUT', { stars: 4, eaten: true, shared: true, user_id: users[0] })).status, 400);
  const signals = async () => (await api(0, '/v0/social/signals?lens=friends')).body;
  assert.deepEqual((await signals()).map(p => p.id), [legacyID]);
  assert.equal((await api(1, path, 'PUT', { stars: 4.5, eaten: true, shared: true })).status, 200);
  const feed = await api(0, '/v0/friend-ratings');
  assert.equal(feed.body.items[0].id, placeID); assert.equal(feed.cache, 'private, no-store');
  assert.doesNotMatch(JSON.stringify(feed.body), /PRIVATE NOTE|note|recommender|visited_at/);
  assert.deepEqual((await signals()).map(p => p.id), [legacyID], 'shared rating cannot enter legacy save path');
  assert.equal((await api(2, path)).status, 404);
  assert.equal((await api(2, path + '/save', 'POST', {})).status, 404);
  const saved = await api(0, path + '/save', 'POST', {});
  assert.equal(saved.status, 201); assert.equal(saved.body.status, 'wantToGo');
  assert.equal(saved.body.recommender, null); assert.equal(saved.body.rating, null);
  assert.equal((await api(1, path, 'DELETE')).status, 204);
  assert.equal((await api(0, path)).status, 404);
  assert.equal((await api(0, path + '/save', 'POST', {})).status, 404);
  assert.deepEqual((await api(0, '/v0/friend-ratings/saved')).body, []);
  assert.deepEqual((await signals()).map(p => p.id), [legacyID], 'withdrawn identity cannot leak through social signals');
  await api(1, path, 'PUT', { stars: 4, eaten: true, shared: true });
  await api(1, path, 'PUT', { stars: 4, eaten: true, shared: false });
  assert.deepEqual((await signals()).map(p => p.id), [legacyID], 'private edit must revoke alternate surface too');
  assert.equal((await api(0, path)).status, 404);
  const retained = (await pool.query('select status,rating,note,recommender from places where id=$1', [saved.body.id])).rows[0];
  assert.deepEqual(retained, { status: 'wantToGo', rating: null, note: null, recommender: null });
  console.log('PASS authenticated HTTP: share/save/withdraw/private edit, nonfollower denial, legacy routing and independent legacy sharing preserved.');
} catch (error) { console.error(log); throw error; }
finally {
  child.kill('SIGTERM'); await exited;
  await pool.end();
  await writeFile(join(dir, 'server.log'), log);
}
