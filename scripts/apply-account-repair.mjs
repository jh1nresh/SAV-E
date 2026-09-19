// A reviewed, one-account maintenance transaction. Defaults to ROLLBACK.
// DATABASE_URL/PGSSLMODE use the deployment's existing connection policy.
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const fields = {
  places: 'id user_id name address latitude longitude google_place_id category status rating note source_url source_platform source_image_url business_photo_urls extracted_dishes price_range recommender google_rating google_price_level opening_hours origin_shared_place_link_id created_at updated_at coordinate_system location_provider provider_place_id provider_map_url'.split(' '),
  captures: 'id user_id source_type source_url raw_text title source_resolution status created_at updated_at'.split(' '),
  place_candidates: 'id capture_id place_id name address city latitude longitude evidence confidence missing_info status created_at updated_at workflow_run_id'.split(' '),
};
const projections = {
  places: new Set(['visibility', 'social_signal']),
  captures: new Set(),
  place_candidates: new Set(['superseded_by_candidate_id', 'superseded_by_candidate_ids']),
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail = () => { throw new Error('Repair precondition failed'); };
export function storedRow(table, row) {
  if (!row || !uuid.test(row.id)) fail();
  for (const key of Object.keys(row)) if (!fields[table].includes(key) && !projections[table].has(key)) fail();
  return Object.fromEntries(fields[table].filter(key => Object.hasOwn(row, key)).map(key => [key, row[key]]));
}

export function validate(bundle) {
  if (bundle.version !== 1 || bundle.mode !== 'historical_account_repair' || typeof bundle.owner !== 'string' || !bundle.owner) fail();
  for (const table of Object.keys(fields)) {
    for (const rows of [bundle.inserts?.[table], bundle.expectedTarget?.[table]]) {
      if (!Array.isArray(rows) || new Set(rows.map(row => row.id)).size !== rows.length) fail();
      for (const raw of rows) {
        const row = storedRow(table, raw);
        if (table !== 'place_candidates' && row.user_id !== bundle.owner) fail();
      }
    }
  }
  for (const row of bundle.inserts.place_candidates) {
    if (row.workflow_run_id != null || !Array.isArray(row.evidence)) fail();
  }
  for (const fill of bundle.captureFills) {
    if (!uuid.test(fill.id) || !['raw_text', 'source_url'].includes(fill.field)
      || typeof fill.source !== 'string' || !fill.source.trim() || ![null, ''].includes(fill.target)) fail();
  }
  for (const merge of bundle.placeMerges ?? []) {
    if (!Array.isArray(merge.sourceIDs) || !merge.sourceIDs.length || merge.sourceIDs.some(id => !uuid.test(id))
      || merge.expected.user_id !== bundle.owner || !merge.expected.google_place_id) fail();
    storedRow('places', merge.expected);
    if (Object.keys(merge.patch).some(key => !['note', 'business_photo_urls', 'created_at'].includes(key))) fail();
    if (typeof merge.patch.note === 'string' && merge.expected.note && !merge.patch.note.includes(merge.expected.note)) fail();
    if (merge.patch.business_photo_urls && (merge.expected.business_photo_urls ?? []).some(url => !merge.patch.business_photo_urls.includes(url))) fail();
    if (merge.patch.created_at && Date.parse(merge.patch.created_at) > Date.parse(merge.expected.created_at)) fail();
  }
  if (new Set((bundle.placeMerges ?? []).map(merge => merge.expected.id)).size !== (bundle.placeMerges ?? []).length) fail();
}

async function matches(client, table, row) {
  const keys = Object.keys(row).filter(key => key !== 'id');
  // Compare typed values so equivalent timestamp encodings compare correctly.
  const result = await client.query(`select exists(select 1 from ${table} t,
    json_populate_record(null::${table}, $1::json) e where t.id=e.id
    and ${keys.map(key => sameColumn(key, 'e')).join(' and ') || 'true'}) as matches`, [JSON.stringify(row)]);
  return result.rows[0].matches;
}

// The account API's toIsoSeconds deliberately removes fractional seconds.
// Compare at that exported precision; all other fields remain exact.
function sameColumn(key, typed) {
  return ['created_at', 'updated_at'].includes(key)
    ? `date_trunc('second', t.${key}) is not distinct from date_trunc('second', ${typed}.${key})`
    : `t.${key} is not distinct from ${typed}.${key}`;
}

async function checkExisting(client, table, pairs) {
  if (!pairs.length) return;
  const predicate = (raw, typed) => fields[table].map(key =>
    `(not (${raw} ? '${key}') or ${sameColumn(key, typed)})`).join(' and ');
  const result = await client.query(`select count(*)::int as invalid
    from jsonb_array_elements($1::jsonb) pair
    cross join lateral jsonb_populate_record(null::${table}, pair->'before') b
    cross join lateral jsonb_populate_record(null::${table}, pair->'after') a
    left join ${table} t on t.id=b.id
    where t.id is null or not ((${predicate("pair->'before'", 'b')}) or (${predicate("pair->'after'", 'a')}))`, [JSON.stringify(pairs)]);
  if (result.rows[0].invalid) fail();
}

export async function repair(client, bundle, commit = false) {
  validate(bundle);
  const counts = { places: 0, captures: 0, place_candidates: 0, captureFields: 0, mergedPlaces: 0 };
  await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
  try {
    await client.query("SET LOCAL lock_timeout='5s'");
    await client.query("SET LOCAL statement_timeout='15s'");
    // Blocks concurrent writes only while this bounded transaction is running.
    await client.query('LOCK TABLE places, captures, place_candidates IN SHARE ROW EXCLUSIVE MODE');
    const profile = await client.query('select id from profiles where id=$1', [bundle.owner]);
    if (profile.rowCount !== 1) fail();
    const fills = new Map();
    for (const fill of bundle.captureFills) {
      const list = fills.get(fill.id) ?? []; list.push(fill); fills.set(fill.id, list);
    }
    // Only captures receiving a fill need an update precondition. Existing
    // places/candidates are never updated: retain any newer edits exactly.
    // Insert-ID collisions are checked separately below, without overwriting.
    for (const table of ['captures']) {
      const pairs = [];
      for (const raw of bundle.expectedTarget[table].filter(row => fills.has(row.id))) {
        const row = storedRow(table, raw);
        const expected = { ...row };
        if (table === 'captures') for (const fill of fills.get(row.id) ?? []) expected[fill.field] = fill.source;
        // The DB update trigger changes updated_at on an applied capture fill.
        if (table === 'captures' && fills.has(row.id)) delete expected.updated_at;
        pairs.push({ before: row, after: expected });
      }
      await checkExisting(client, table, pairs);
    }
    for (const merge of bundle.placeMerges ?? []) {
      const after = { ...merge.expected, ...merge.patch };
      if (await matches(client, 'places', after)) continue;
      if (!(await matches(client, 'places', merge.expected))) fail();
      const keys = Object.keys(merge.patch);
      if (!keys.length) continue;
      await client.query(`update places t set ${keys.map(key => `${key}=p.${key}`).join(',')}
        from json_populate_record(null::places,$1::json) p where t.id=p.id and t.user_id=$2`, [JSON.stringify(after), bundle.owner]);
      if (!(await matches(client, 'places', after))) fail();
      counts.mergedPlaces++;
    }
    for (const table of ['places', 'captures', 'place_candidates']) {
      for (const raw of bundle.inserts[table]) {
        const row = storedRow(table, raw);
        if (table === 'places' && row.origin_shared_place_link_id) fail();
        if (table === 'place_candidates') {
          const capture = await client.query('select id from captures where id=$1 and user_id=$2', [row.capture_id, bundle.owner]);
          if (capture.rowCount !== 1) fail();
          if (row.place_id) {
            const place = await client.query('select id from places where id=$1 and user_id=$2', [row.place_id, bundle.owner]);
            if (place.rowCount !== 1) fail();
          }
        }
        const current = await client.query(`select id from ${table} where id=$1`, [row.id]);
        if (current.rowCount) { if (!(await matches(client, table, row))) fail(); continue; }
        const keys = Object.keys(row);
        await client.query(`insert into ${table} (${keys.join(',')}) select ${keys.join(',')} from json_populate_record(null::${table}, $1::json)`, [JSON.stringify(row)]);
        if (!(await matches(client, table, row))) fail();
        counts[table]++;
      }
    }
    for (const [id, changes] of fills) {
      const expected = bundle.expectedTarget.captures.find(row => row.id === id);
      if (!expected || changes.some(fill => expected[fill.field] !== fill.target)) fail();
      const current = await client.query('select raw_text,source_url from captures where id=$1 and user_id=$2', [id, bundle.owner]);
      if (current.rowCount !== 1) fail();
      const pending = changes.filter(fill => current.rows[0][fill.field] !== fill.source);
      if (!pending.length) continue;
      if (pending.some(fill => current.rows[0][fill.field] !== fill.target)) fail();
      await client.query(`update captures set ${pending.map((fill, index) => `${fill.field}=$${index + 3}`).join(',')} where id=$1 and user_id=$2`, [id, bundle.owner, ...pending.map(fill => fill.source)]);
      counts.captureFields += pending.length;
    }
    await client.query(commit ? 'COMMIT' : 'ROLLBACK');
    return { committed: commit, counts };
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}

async function main() {
  const [file, receipt, commitHash] = process.argv.slice(2);
  if (!file || !receipt || process.argv.length > 5) throw new Error('Usage: apply-account-repair.mjs bundle.json receipt.json [approved-bundle-sha256]');
  const bytes = fs.readFileSync(file);
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (commitHash && commitHash !== hash) fail();
  // Reserve a private receipt before doing any work. Refuse overwrite/symlinks.
  const fd = fs.openSync(receipt, 'wx', 0o600);
  const require = createRequire(new URL('../backend/package.json', import.meta.url));
  const { Client } = require('pg');
  const ca = process.env.DATABASE_CA_CERT?.replace(/\\n/g, '\n');
  const client = new Client({ connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSLMODE === 'disable' ? false : process.env.PGSSLMODE === 'no-verify'
      ? { rejectUnauthorized: false } : { rejectUnauthorized: true, ...(ca ? { ca } : {}) }, connectionTimeoutMillis: 10000 });
  try {
    await client.connect();
    const result = await repair(client, JSON.parse(bytes), Boolean(commitHash));
    fs.writeFileSync(fd, JSON.stringify({ ...result, bundleSHA256: hash, finishedAt: new Date().toISOString() }, null, 2));
    console.log(JSON.stringify(result));
  } finally { fs.closeSync(fd); await client.end(); }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch(() => { console.error('Account repair failed; inspect local preconditions. No private data logged.'); process.exitCode = 1; });
