import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID, createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { applyIdentityFeedback, canonicalSourceURL, LinkPlaceIntelligence, placePopularity } from "./linkPlaceIntelligence.js";
import { analyzeSocialCaption, type SemanticAnalysisResult } from "./socialSemanticExtraction.js";

const digest = (value: string) => createHash("sha256").update(value).digest("hex");
const result = (): SemanticAnalysisResult => ({ status:"ready",venues:[{
  name:{value:"Cafe",quote:"Cafe",source:"caption"},branch:null,address:{value:"1 Road",quote:"1 Road",source:"caption"},transport:null,
  mapStatus:"matched",matches:[{id:"wrong",name:"Cafe",address:"1 Road",latitude:25,longitude:121}],
}] });

test("source identity ignores tracking but preserves meaningful queries, fragments and branches", () => {
  assert.equal(canonicalSourceURL("https://www.instagram.com/reel/abc/?igsh=private&utm_source=share"),"https://instagram.com/reel/abc");
  assert.equal(canonicalSourceURL("https://twitter.com/author/status/123?utm_medium=social"),"https://x.com/author/status/123");
  assert.notEqual(canonicalSourceURL("https://youtube.com/watch?v=one"),canonicalSourceURL("https://youtube.com/watch?v=two"));
  assert.notEqual(canonicalSourceURL("https://instagram.com/p/abc?view=one"),canonicalSourceURL("https://instagram.com/p/abc?view=two"));
  assert.notEqual(canonicalSourceURL("https://instagram.com/p/abc#one"),canonicalSourceURL("https://instagram.com/p/abc#two"));
  for (const url of ["http://instagram.com/p/a","https://owner:secret@instagram.com/p/a","https://127.0.0.1/","https://instagram.com.evil.test/p/a","garbage"]) assert.equal(canonicalSourceURL(url),undefined);
});

test("confirmed owner correction removes wrong provider identity without inventing a replacement", () => {
  const original = result();
  const applied = applyIdentityFeedback(original,[{rejected_id:"wrong",selected_id:"right"}]);
  assert.equal(applied.applied,1); assert.deepEqual(applied.result.venues[0].matches,[]);
  assert.equal(applied.result.venues[0].mapStatus,"unverified");
  assert.equal(original.venues[0].matches[0].id,"wrong");
  const alternatives = result(); alternatives.venues[0].mapStatus="ambiguous";
  alternatives.venues[0].matches.push({...alternatives.venues[0].matches[0],id:"right"});
  assert.equal(applyIdentityFeedback(alternatives,[{rejected_id:"wrong",selected_id:"right"}]).result.venues[0].matches[0].id,"right");
});

test("conflicting decisions, another venue, absent address and conflicting provider matches abstain", () => {
  assert.equal(applyIdentityFeedback(result(),[{rejected_id:"wrong",selected_id:"a"},{rejected_id:"wrong",selected_id:"b"}]).applied,0);
  assert.equal(applyIdentityFeedback(result(),[{rejected_id:"other",selected_id:"a"}]).applied,0);
  const noAddress=result(); noAddress.venues[0].address=null;
  assert.equal(applyIdentityFeedback(noAddress,[{rejected_id:"wrong",selected_id:"a"}]).applied,0);
  const conflict=result(); conflict.venues[0].mapStatus="conflict";
  assert.equal(applyIdentityFeedback(conflict,[{rejected_id:"wrong",selected_id:"a"}]).applied,0);
});

const databaseURL = process.env.SAVE_LINK_INTELLIGENCE_TEST_DATABASE_URL;
test("real database: cache ownership, frozen corrections, source graph, deduplication and revocation", {skip:!databaseURL,timeout:60_000}, async t => {
  const url = new URL(databaseURL!);
  assert.equal(url.pathname,"/save_link_fixture");
  assert.ok(["127.0.0.1","localhost"].includes(url.hostname));
  assert.equal(url.port,"55449");
  const pool = new Pool({connectionString:databaseURL,max:6});
  const service = new LinkPlaceIntelligence(pool);
  const prefix = `link-fixture-${randomUUID()}`;
  const owners = Array.from({length:8},(_,i)=>`${prefix}-${i}`);
  const source = "https://instagram.com/reel/fixture";
  const ids:string[]=[];
  try {
    const migration=await readFile(new URL("../sql/link-place-intelligence.sql",import.meta.url),"utf8");
    await pool.query(migration); await pool.query(migration);
    for (const owner of owners) await pool.query("insert into profiles(id) values($1)",[owner]);
    async function place(owner:string,venue="same-cafe",status="visited",published=true) {
      const id=randomUUID();ids.push(id);
      await pool.query(`insert into places(id,user_id,name,address,latitude,longitude,google_place_id,status,source_url,note)
        values($1,$2,'Fixture Cafe','1 Road',25,121,$3,$4,$5,'NEVER EXPOSE')`,[id,owner,venue,status,`${source}-${ids.length}?igsh=private`]);
      await pool.query("insert into place_visibility(place_id,user_id,visibility,allow_trending_signal) values($1,$2,$3,$4)",[id,owner,published?"public_guide":"private",published]);
      return id;
    }
    async function capture(owner:string,sourceURL=source) {
      const id=randomUUID();
      await pool.query("insert into captures(id,user_id,source_url,raw_text) values($1,$2,$3,'Cafe 1 Road')",[id,owner,sourceURL]);return id;
    }
    async function scope(owner:string,id:string,sourceURL=source) {
      const row=(await pool.query("select md5(jsonb_build_array(source_url,raw_text,source_resolution->'captured_text_v1')::text) as stamp from captures where id=$1",[id])).rows[0];
      return service.extractionCache(owner,id,sourceURL,row?.stamp ?? "missing");
    }
    const first=await capture(owners[0]), second=await capture(owners[0],`${source}?igsh=tracking`), foreign=await capture(owners[1]);
    const key=digest("caption-v1");
    const firstCache=await scope(owners[0],first);
    await firstCache.cache.load(key);
    await firstCache.cache.save(key,{venues:[]});
    assert.deepEqual(await (await scope(owners[0],second)).cache.load(key),{venues:[]});
    assert.equal(await (await scope(owners[1],foreign)).cache.load(key),undefined);
    assert.equal(await (await scope(owners[0],foreign)).cache.load(key),undefined);
    assert.equal(await firstCache.cache.load(digest("changed")),undefined);
    await pool.query("update semantic_extraction_cache set expires_at=clock_timestamp()-interval '1 second' where user_id=$1",[owners[0]]);
    assert.equal(await firstCache.cache.load(key),undefined);
    await firstCache.cache.save(key,{venues:[]});

    await t.test("direct analyzer cache skips extraction but freshly verifies Maps; deletion clears raw cache",async()=>{
      const input={caption:"Cafe 1 Road"};let extracts=0,searches=0;
      const raw={venues:[{name:{value:"Cafe",quote:"Cafe",source:"caption"},branch:null,address:{value:"1 Road",quote:"1 Road",source:"caption"},transport:null}]};
      const deps={cache:service.ownerCache(owners[0]),extract:async()=>{extracts++;return raw;},search:async()=>{searches++;return [{id:"cafe",name:"Cafe",address:"1 Road",latitude:25,longitude:121}];}};
      assert.equal((await analyzeSocialCaption(input,deps)).venues[0].mapStatus,"matched");
      await analyzeSocialCaption(input,deps);assert.equal(extracts,1);assert.equal(searches,2);
      await pool.query("delete from captures where id=$1",[second]);
      await analyzeSocialCaption(input,deps);assert.equal(extracts,2);
      await analyzeSocialCaption(input,{...deps,cache:service.ownerCache(owners[1])});assert.equal(extracts,3);
    });

    await t.test("explicit decision freezes source fingerprint, correction works and withdrawal invalidates it",async()=>{
      const target=await place(owners[0],"right","wantToGo",false);
      const candidate=randomUUID(),run=randomUUID(),decision=randomUUID();
      await pool.query("insert into workflow_runs(id,user_id,workflow_id,listing_id) values($1,$2,'place-recovery','fixture')",[run,owners[0]]);
      await pool.query(`insert into place_candidates(id,capture_id,name,evidence,status,place_id)
        values($1,$2,'Cafe','[{"google_place_id":"wrong"}]','saved',$3)`,[candidate,first,target]);
      await firstCache.bindCandidate(pool,candidate,key);
      await pool.query(`insert into user_decisions(id,run_id,user_id,candidate_id,final_place_id,action,idempotency_key)
        values($1,$2,$3,$4,$5,'wrong_branch','fixture')`,[decision,run,owners[0],candidate,target]);
      const next=await capture(owners[0]);const nextScope=await scope(owners[0],next);
      await nextScope.cache.load(key);
      assert.equal((await nextScope.feedback(result())).applied,1);
      const different=await scope(owners[0],next);await different.cache.load(digest("changed content"));
      assert.equal((await different.feedback(result())).applied,0);
      await firstCache.cache.save(digest("changed content"),{venues:[]});
      assert.equal((await different.feedback(result())).applied,0,"later analysis must not rewrite old decision fingerprint");
      const graph=await service.sources(owners[0],target);
      assert.equal(graph?.sources.length,2);assert.ok(graph?.sources.some(row=>row.corrected));
      assert.equal(await service.sources(owners[1],target),undefined);
      await pool.query("update place_candidates set status='rejected' where id=$1",[candidate]);
      assert.equal((await nextScope.feedback(result())).applied,0);
      await pool.query("update place_candidates set status='saved' where id=$1",[candidate]);
      await pool.query("delete from user_decisions where id=$1",[decision]);
      assert.equal((await nextScope.feedback(result())).applied,0);
      assert.equal((await pool.query("select count(*)::int n from place_identity_feedback where decision_id=$1",[decision])).rows[0].n,0);
    });

    await t.test("five people across different links form one venue; duplicates and private records never inflate people",async()=>{
      const publicIds=[];
      for (const owner of owners.slice(0,5)) publicIds.push(await place(owner));
      const duplicate=await place(owners[0]);
      await place(owners[5],"same-cafe","visited",false);
      await place(owners[6],"other-branch");
      let data=await placePopularity(pool);let venue=data.places.find(row=>row.google_place_id==="same-cafe");
      assert.equal(venue?.save_count,5);assert.equal(venue?.self_reported_visit_count,5);assert.equal(venue?.linked_source_count,6);
      assert.ok(!data.places.some(row=>row.google_place_id==="other-branch"));
      assert.doesNotMatch(JSON.stringify(data),/NEVER EXPOSE|instagram|capture_id|user_id|igsh/);
      const before=(await pool.query("select first_visited_at from place_signal_state where place_id=$1",[duplicate])).rows[0].first_visited_at;
      await pool.query("update places set status='wantToGo' where id=$1",[duplicate]);await pool.query("update places set status='visited' where id=$1",[duplicate]);
      assert.equal((await pool.query("select first_visited_at from place_signal_state where place_id=$1",[duplicate])).rows[0].first_visited_at.toISOString(),before.toISOString());
      await pool.query("update place_visibility set allow_trending_signal=false where place_id=$1",[publicIds[4]]);
      assert.ok(!(await placePopularity(pool)).places.some(row=>row.google_place_id==="same-cafe"));
      await pool.query("update place_visibility set allow_trending_signal=true where place_id=$1",[publicIds[4]]);
      await pool.query("update places set status='wantToGo' where id=$1",[publicIds[4]]);
      venue=(await placePopularity(pool)).places.find(row=>row.google_place_id==="same-cafe");assert.equal(venue?.self_reported_visit_count,null);
      await pool.query("delete from places where id=$1",[publicIds[3]]);
      assert.ok(!(await placePopularity(pool)).places.some(row=>row.google_place_id==="same-cafe"));
    });

    await t.test("valid save plus a null-saved_at duplicate for the same account still counts toward the floor",async()=>{
      const venue="null-dup-cafe";
      for (const owner of owners.slice(0,5)) await place(owner,venue);
      const duplicate=await place(owners[0],"stray-before-correction");
      await pool.query("update places set google_place_id=$1 where id=$2",[venue,duplicate]);
      const cleared=(await pool.query("select saved_at from place_signal_state where place_id=$1",[duplicate])).rows[0];
      assert.equal(cleared.saved_at,null);
      const venueRow=(await placePopularity(pool)).places.find(row=>row.google_place_id===venue);
      assert.equal(venueRow?.save_count,5);
    });

    await t.test("legacy state and identity edits do not invent recent save/visit timestamps",async()=>{
      const id=await place(owners[7],"legacy");
      await pool.query("delete from place_signal_state where place_id=$1",[id]);
      await pool.query("update places set status='visited',name='Renamed' where id=$1",[id]);
      assert.equal((await pool.query("select * from place_signal_state where place_id=$1",[id])).rowCount,0);
      await pool.query("update places set google_place_id='corrected-venue' where id=$1",[id]);
      const row=(await pool.query("select * from place_signal_state where place_id=$1",[id])).rows[0];
      assert.equal(row.saved_at,null);assert.equal(row.first_visited_at,null);
    });

    await t.test("in-flight cache writes and candidate bindings cannot undo deletion or source edits",async()=>{
      const id=await capture(owners[0]);
      const current=await scope(owners[0],id);const oldKey=digest("inflight");
      await current.cache.load(oldKey);
      const candidate=randomUUID();
      await pool.query("insert into place_candidates(id,capture_id,name) values($1,$2,'Before edit')",[candidate,id]);
      await pool.query("update captures set raw_text='Changed while provider worked' where id=$1",[id]);
      await current.bindCandidate(pool,candidate,oldKey);
      assert.equal((await pool.query("select * from candidate_extraction_inputs where candidate_id=$1",[candidate])).rowCount,0);
      const cache=service.ownerCache(owners[0]);await cache.load(oldKey);
      await pool.query("delete from captures where id=$1",[id]);
      await cache.save(oldKey,{venues:[]});
      assert.equal((await pool.query("select * from semantic_extraction_cache where user_id=$1 and input_key=$2",[owners[0],oldKey])).rowCount,0);
    });

    await t.test("bounded cache, capture changes, account deletion and RLS",async()=>{
      const cache=service.ownerCache(owners[0]);
      await Promise.all(Array.from({length:105},(_,i)=>cache.save(digest(String(i)),{venues:[]})));
      assert.equal((await pool.query("select count(*)::int n from semantic_extraction_cache where user_id=$1",[owners[0]])).rows[0].n,100);
      await pool.query("update captures set raw_text='new caption' where id=$1",[first]);
      assert.equal((await pool.query("select * from candidate_extraction_inputs where capture_id=$1",[first])).rowCount,0);
      const tables=await pool.query("select relname,relrowsecurity from pg_class where relname=any($1::text[])",[["candidate_extraction_inputs","place_identity_feedback","place_signal_state","semantic_extraction_cache","extraction_cache_epochs"]]);
      assert.equal(tables.rows.length,5);assert.ok(tables.rows.every(row=>row.relrowsecurity));
      await pool.query("delete from profiles where id=$1",[owners[0]]);
      assert.equal((await pool.query("select count(*)::int n from semantic_extraction_cache where user_id=$1",[owners[0]])).rows[0].n,0);
    });
  } finally { await pool.query("delete from profiles where id=any($1::text[])",[owners]);await pool.end(); }
});
