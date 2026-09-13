import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AnalysisUsageStore, AnalysisControlError, analysisLimits, analysisID, analysisPrices, estimatedMicros, geminiTokens, withAnalysisUsage, trackAnalysisOperation, type AnalysisLimits } from "./analysisUsage.js";
import { defaultPlacesCorroborator } from "./sourceSearchWorker.js";
import { runAnalysisRecovery } from "./analysisRecovery.js";

test("analysis controls are dormant until explicitly configured; malformed enabled policy fails closed",()=>{
  assert.equal(analysisLimits({}).enabled,false);
  for(const value of [undefined,"garbage","-1","1.2","Infinity","9007199254740992"]) assert.throws(()=>analysisLimits({SAVE_ANALYSIS_LIMITS_ENABLED:"true",SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT:value}),AnalysisControlError);
  const configured=analysisLimits({SAVE_ANALYSIS_LIMITS_ENABLED:"true",SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT:"0",SAVE_ANALYSIS_REQUEST_LIMIT:"0",SAVE_ANALYSIS_ACCOUNT_DAILY_BUDGET_MICROS:"0",SAVE_ANALYSIS_GLOBAL_DAILY_BUDGET_MICROS:"0",SAVE_ANALYSIS_BUDGET_MICROS:"0"});
  assert.equal(configured.accountDailyAnalyses,0);
});
test("opaque analysis IDs reject arbitrary and sensitive strings",()=>{
  const id=randomUUID();assert.equal(analysisID(id.toUpperCase()),id);
  for(const bad of ["https://example.com/private",123,"user@example.com",{},""]) assert.throws(()=>analysisID(bad));
});
test("Gemini estimated output includes thinking, cache discount, and explicit unknowns",()=>{
  const usage=geminiTokens({usageMetadata:{promptTokenCount:1000,candidatesTokenCount:100,thoughtsTokenCount:200,totalTokenCount:1300,cachedContentTokenCount:500}});
  assert.equal(estimatedMicros(analysisPrices["gemini:gemini-3.5-flash"],usage),3525);
  assert.equal(estimatedMicros(analysisPrices["gemini:gemini-3.5-flash"],geminiTokens({})),null);
  assert.equal(estimatedMicros(undefined,usage),null);
  assert.equal(estimatedMicros(analysisPrices["gemini:gemini-3.5-flash"],{...usage,total:100}),null);
  assert.equal(estimatedMicros(analysisPrices["gemini:gemini-3.5-flash"],{...usage,cached:2000}),null);
  assert.equal(estimatedMicros(analysisPrices.google_places),32000);
  assert.equal(estimatedMicros(analysisPrices["gemini:gemini-3.5-flash"],geminiTokens({usageMetadata:{promptTokenCount:1000,candidatesTokenCount:100,totalTokenCount:1300}})),4200);
});
test("no analysis context retains ordinary operation behavior without metering",async()=>{
  assert.equal(await trackAnalysisOperation({operation:"google_places"},async()=>17),17);
});

const databaseURL=process.env.SAVE_ANALYSIS_TEST_DATABASE_URL;
test("real PostgreSQL admission, reservations, retries, ownership and ledger completeness",{skip:!databaseURL,timeout:60000},async()=>{
  const url=new URL(databaseURL!);
  assert.equal(url.pathname,"/save_analysis_fixture","Use the disposable analysis fixture database only");
  assert.ok(url.searchParams.get("host")?.startsWith("/tmp/save-analysis-completion/"));
  const pool=new Pool({connectionString:databaseURL,max:12});
  const otherPool=new Pool({connectionString:databaseURL,max:4});
  let limits:AnalysisLimits={enabled:false};
  const store=new AnalysisUsageStore(pool,()=>limits);
  const otherStore=new AnalysisUsageStore(otherPool,()=>limits);
  const owner=`analysis-fixture-${randomUUID()}`;const other=`analysis-fixture-${randomUUID()}`;
  try {
    await pool.query("insert into profiles(id) values($1),($2)",[owner,other]);
    const id=randomUUID();await store.start(owner,id);await store.start(owner,id);
    await assert.rejects(store.start(other,id),error=>error instanceof AnalysisControlError && error.status===404);
    await assert.rejects(store.owner(other,id));
    const first=await store.reserve(owner,id,{operation:"google_places"});
    await store.settle(owner,id,first,{operation:"google_places"},"success",50);
    const failed=await store.reserve(owner,id,{operation:"google_places"});
    await store.settle(owner,id,failed,{operation:"google_places"},"failure",60);
    let summary=await store.summary(owner,id);assert.equal(summary.cost_complete,false);
    const rows=summary.operations as Array<any>;
    assert.equal(rows[0].attempts,2);assert.equal(rows[0].failures,1);assert.equal(rows[0].known_estimated_micros,"32000");
    const event={event_id:randomUUID(),operation:"metadata",outcome:"success",duration_ms:10,query:"PRIVATE",caption:"PRIVATE",estimated_micros:-999999};
    await store.clientEvents(owner,id,[event]);await store.clientEvents(owner,id,[event]);
    const client=await pool.query("select * from analysis_usage_events where id=$1",[event.event_id]);
    assert.equal(client.rowCount,1);assert.ok(!JSON.stringify(client.rows).includes("PRIVATE"));assert.equal(client.rows[0].estimated_micros,"0");
    const capture=randomUUID();await pool.query("insert into captures(id,user_id,source_type,status) values($1,$2,'note','review')",[capture,owner]);
    await pool.query("insert into place_candidates(capture_id,name,status) values($1,'Confirmed fixture','confirmed'),($1,'Saved fixture','saved'),($1,'Review fixture','review')",[capture]);
    await store.finish(owner,id,"review_candidate",[capture]);
    assert.equal((await store.summary(owner,id)).confirmed_candidates,2);await store.finish(owner,id,"failed",[capture]);
    assert.equal((await pool.query("select outcome from analysis_sessions where id=$1",[id])).rows[0].outcome,"review_candidate");
    await assert.rejects(store.reserve(owner,id,{operation:"google_places"}),error=>error instanceof AnalysisControlError && error.code==="analysis_closed");
    await store.clientEvents(owner,id,[],true);assert.equal((await store.summary(owner,id)).events_truncated,true);
    // Cost reservation is shared across distinct pools, not process-local counters.
    await pool.query("delete from analysis_sessions where user_id in ($1,$2)",[owner,other]);
    limits={enabled:true,accountDailyAnalyses:3,analysisRequests:10,analysisMicros:64000,accountDailyMicros:64000,globalDailyMicros:64000};
    const a=randomUUID(),b=randomUUID();await store.start(owner,a);await otherStore.start(other,b);
    const requests=await Promise.allSettled(Array.from({length:10},(_,i)=>(i%2?store:otherStore).reserve(i%2?owner:other,i%2?a:b,{operation:"google_places"})));
    assert.equal(requests.filter(r=>r.status==="fulfilled").length,2);
    assert.equal(requests.filter(r=>r.status==="rejected" && r.reason.code==="analysis_limit_exceeded").length,8);
    assert.equal((await pool.query("select count(*)::int n from analysis_usage_events where analysis_id in($1,$2)",[a,b])).rows[0].n,2);
    await assert.rejects(store.reserve(owner,a,{operation:"rubric"}),error=>error instanceof AnalysisControlError && error.code==="analysis_controls_unavailable");
    await store.clientEvents(owner,a,[{event_id:randomUUID(),operation:"metadata",outcome:"success",duration_ms:0,estimated_micros:-999999999}]);
    await assert.rejects(store.reserve(owner,a,{operation:"google_places"}),error=>error instanceof AnalysisControlError && error.code==="analysis_limit_exceeded");
    // Zero allowance is an explicit stop; rejected starts do not create sessions.
    limits={...limits,accountDailyAnalyses:0};const blocked=randomUUID();await assert.rejects(store.start(owner,blocked));
    assert.equal((await pool.query("select id from analysis_sessions where id=$1",[blocked])).rowCount,0);
    // Missing client receipts cannot be mistaken for complete accounting.
    limits={enabled:false};const incomplete=randomUUID();await store.start(owner,incomplete);
    await store.finish(owner,incomplete,"source_only",[]);
    assert.equal((await store.summary(owner,incomplete)).cost_complete,false);
    await store.clientEvents(owner,incomplete,[]);
    assert.equal((await store.summary(owner,incomplete)).cost_complete,true);
    // Async scopes correlate failures and concurrent success without crossing owners.
    limits={enabled:false};const c=randomUUID(),d=randomUUID();await store.start(owner,c);await store.start(other,d);
    await Promise.all([withAnalysisUsage(store,owner,c,()=>trackAnalysisOperation({operation:"google_places"},async()=>1)),withAnalysisUsage(store,other,d,()=>trackAnalysisOperation({operation:"google_places"},async()=>2))]);
    assert.equal((await store.summary(owner,c)).operations instanceof Array,true);await assert.rejects(store.summary(other,c));
    // Real SQL lease conflict, result reuse, failure retry and changed-input work.
    let release!:()=>void;const wait=new Promise<void>(resolve=>{release=resolve;});let calls=0;
    const work=async()=>{calls++;await wait;return {errors:[],created_candidates:[]};};
    const running=runAnalysisRecovery(pool,owner,capture,{query:"same"},work);
    await new Promise(resolve=>setTimeout(resolve,30));
    await assert.rejects(runAnalysisRecovery(otherPool,owner,capture,{query:"same"},work),error=>error instanceof AnalysisControlError && error.code==="analysis_recovery_running");
    release();await running;
    assert.equal((await runAnalysisRecovery(otherPool,owner,capture,{query:"same"},work)).reused,true);assert.equal(calls,1);
    let retry=0;const fail=async()=>{retry++;throw new Error("transient");};
    await assert.rejects(runAnalysisRecovery(pool,owner,capture,{query:"failed"},fail));await assert.rejects(runAnalysisRecovery(otherPool,owner,capture,{query:"failed"},fail));assert.equal(retry,2);
    await runAnalysisRecovery(pool,owner,capture,{query:"changed"},async()=>{calls++;return {errors:[]};});assert.equal(calls,2);
  } finally {
    await pool.query("delete from profiles where id in($1,$2)",[owner,other]);
    await pool.end();await otherPool.end();
  }
});


test("Google recovery records semantic and parse failures after reservation", async () => {
  const originalFetch=globalThis.fetch,originalKey=process.env.GOOGLE_PLACES_API_KEY;
  process.env.GOOGLE_PLACES_API_KEY="synthetic";
  const events:string[]=[];
  const store={reserve:async()=>{events.push("reserve");return randomUUID();},settle:async(_u:unknown,_a:unknown,_e:unknown,_i:unknown,outcome:string)=>{events.push(outcome);}} as unknown as AnalysisUsageStore;
  const candidate={name:"Fixture Cafe",address:"123 Main Street",evidence:[],confidence:0.5,missingInfo:[]};
  try {
    for(const body of [JSON.stringify({status:"REQUEST_DENIED",results:[]}),JSON.stringify({status:"OVER_QUERY_LIMIT",results:[]}),"malformed"]) {
      events.length=0;
      globalThis.fetch=async()=>{events.push("fetch");return new Response(body);};
      await assert.rejects(withAnalysisUsage(store,"owner",randomUUID(),()=>defaultPlacesCorroborator(candidate)));
      assert.deepEqual(events,["reserve","fetch","failure"]);
    }
    events.length=0;
    globalThis.fetch=async()=>{events.push("fetch");return Response.json({status:"ZERO_RESULTS",results:[]});};
    await withAnalysisUsage(store,"owner",randomUUID(),()=>defaultPlacesCorroborator(candidate));
    assert.deepEqual(events,["reserve","fetch","success"]);
  } finally {
    globalThis.fetch=originalFetch;
    if(originalKey===undefined) delete process.env.GOOGLE_PLACES_API_KEY;else process.env.GOOGLE_PLACES_API_KEY=originalKey;
  }
});
