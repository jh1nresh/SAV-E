import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repair, validate } from '../../scripts/apply-account-repair.mjs';
const require = createRequire(new URL('../../backend/package.json', import.meta.url));
const { Client } = require('pg');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const date = '2026-01-01T00:00:00.000Z';
function bundle() {
  return { version: 1, mode: 'historical_account_repair', owner: 'owner',
    inserts: { places: [{ id: id(1), user_id: 'owner', name: 'Private', latitude: 1, longitude: 2, created_at: date }],
      captures: [{ id: id(2), user_id: 'owner', raw_text: 'Clue', created_at: date }],
      place_candidates: [{ id: id(3), capture_id: id(2), place_id: null, name: 'Unconfirmed', status: 'source_only',
        workflow_run_id: null, evidence: [{ legacy_workflow_provenance: { workflow_run_id: id(90), migration_mode: 'historical_record_only' } }], created_at: date }] },
    expectedTarget: { places: [], captures: [{ id: id(4), user_id: 'owner', raw_text: '', source_url: null, status: 'review', created_at: date, updated_at: date }], place_candidates: [] },
    captureFills: [{ id: id(4), field: 'raw_text', source: 'Original clue', target: '' }],
  };
}
test('rejects consent fields, foreign owners and live workflow references', () => {
  for (const mutate of [b => b.inserts.places[0].allow_friend_signal = true,
    b => b.inserts.captures[0].user_id = 'foreign', b => b.inserts.place_candidates[0].workflow_run_id = id(90),
    b => b.captureFills[0].field = 'status']) {
    const b = bundle(); mutate(b); assert.throws(() => validate(b));
  }
});

test('real transaction rollback, apply, idempotency, drift and ownership boundaries',
  { skip: !process.env.ACCOUNT_REPAIR_TEST_DATABASE_URL }, async () => {
    const client = new Client({ connectionString: process.env.ACCOUNT_REPAIR_TEST_DATABASE_URL });
    await client.connect();
    const schema = `repair_test_${process.pid}`;
    try {
      await client.query(`create schema ${schema}`);
      await client.query(`set search_path=${schema},public`);
      await client.query('create table profiles(id text primary key)');
      for (const table of ['places', 'captures', 'place_candidates']) await client.query(`create table ${table} (like public.${table} including all)`);
      await client.query('create trigger update_captures_updated_at before update on captures for each row execute procedure public.update_updated_at()');
      await client.query('alter table place_candidates add foreign key(capture_id) references captures(id)');
      await client.query('alter table place_candidates add foreign key(place_id) references places(id)');
      await client.query("insert into profiles values('owner'),('foreign')");
      await client.query("insert into captures(id,user_id,raw_text,created_at,updated_at) values($1,'owner','','2026-01-01T00:00:00.789Z','2026-01-01T00:00:00.789Z')", [id(4)]);
      const b = bundle();
      await client.query("insert into places(id,user_id,name,latitude,longitude,note) values($1,'owner','Existing',9,10,'Newer private edit')", [id(6)]);
      b.expectedTarget.places.push({ id: id(6), user_id: 'owner', name: 'Existing', latitude: 3, longitude: 4, note: 'Old edit' });
      const expected = { places: 1, captures: 1, place_candidates: 1, captureFields: 1, mergedPlaces: 0 };
      assert.deepEqual((await repair(client, b)).counts, expected);
      assert.equal((await client.query('select count(*)::int n from places')).rows[0].n, 1);
      assert.equal((await client.query('select raw_text from captures where id=$1', [id(4)])).rows[0].raw_text, '');
      assert.deepEqual((await repair(client, b, true)).counts, expected);
      assert.deepEqual((await repair(client, b, true)).counts, { places: 0, captures: 0, place_candidates: 0, captureFields: 0, mergedPlaces: 0 });
      assert.deepEqual((await client.query('select latitude,longitude,note from places where id=$1', [id(6)])).rows[0],
        { latitude: 9, longitude: 10, note: 'Newer private edit' });
      assert.equal((await client.query('select source_resolution from captures where id=$1', [id(4)])).rows[0].source_resolution, null);
      const candidate = (await client.query('select * from place_candidates')).rows[0];
      assert.equal(candidate.status, 'source_only'); assert.equal(candidate.workflow_run_id, null);
      assert.equal(candidate.evidence[0].legacy_workflow_provenance.workflow_run_id, id(90));
      await client.query("insert into places(id,user_id,name,latitude,longitude,google_place_id,note,business_photo_urls,created_at) values($1,'owner','Duplicate',1,2,'provider-id','Current note',array['new-photo'],'2026-02-01T00:00:00.789Z')", [id(7)]);
      await client.query('create unique index place_provider_unique on places(user_id,google_place_id) where google_place_id is not null');
      const merged = structuredClone(b);
      merged.placeMerges = [{ sourceID: id(8), expected: { id: id(7), user_id: 'owner', google_place_id: 'provider-id',
        note: 'Current note', business_photo_urls: ['new-photo'], created_at: '2026-02-01T00:00:00Z' },
        patch: { note: 'Current note\n\nOld note', business_photo_urls: ['new-photo', 'old-photo'], created_at: date } }];
      assert.equal((await repair(client, merged)).counts.mergedPlaces, 1);
      assert.equal((await client.query('select note from places where id=$1', [id(7)])).rows[0].note, 'Current note');
      assert.equal((await repair(client, merged, true)).counts.mergedPlaces, 1);
      assert.equal((await repair(client, merged, true)).counts.mergedPlaces, 0);
      const consolidated = (await client.query('select * from places where id=$1', [id(7)])).rows[0];
      assert.equal(consolidated.note, 'Current note\n\nOld note');
      assert.deepEqual(consolidated.business_photo_urls, ['new-photo', 'old-photo']);
      assert.equal(consolidated.created_at.toISOString(), date);
      assert.equal((await client.query('select id from places where id=$1', [id(8)])).rowCount, 0);
      await client.query("update captures set raw_text='Newer edit' where id=$1", [id(4)]);
      await assert.rejects(repair(client, b, true));
      assert.equal((await client.query('select raw_text from captures where id=$1', [id(4)])).rows[0].raw_text, 'Newer edit');
      const foreign = bundle(); foreign.expectedTarget.captures = []; foreign.captureFills = [];
      foreign.inserts.place_candidates[0].capture_id = id(5);
      await client.query("insert into captures(id,user_id) values($1,'foreign')", [id(5)]);
      await assert.rejects(repair(client, foreign, true));
      const conflict = bundle(); conflict.expectedTarget.captures = []; conflict.captureFills = [];
      conflict.inserts.places[0].latitude = 99;
      await assert.rejects(repair(client, conflict, true));
      assert.equal((await client.query('select latitude from places where id=$1', [id(1)])).rows[0].latitude, 1);
    } finally { await client.query(`drop schema if exists ${schema} cascade`); await client.end(); }
  });
