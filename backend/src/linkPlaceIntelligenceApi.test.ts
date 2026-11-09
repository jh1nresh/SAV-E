import assert from "node:assert/strict";
import test from "node:test";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { randomUUID } from "node:crypto";
import { mkdtemp, writeFile, readFile } from "node:fs/promises";
import { tmpdir, userInfo } from "node:os";
import { join } from "node:path";
import { createServer } from "node:net";
import { Pool } from "pg";
import { generateKeyPair, exportSPKI, SignJWT } from "jose";

const databaseURL=process.env.SAVE_LINK_INTELLIGENCE_TEST_DATABASE_URL;
test("HTTP routes preserve auth, reuse direct extraction, avoid inferring session provenance, and keep sources private",{skip:!databaseURL,timeout:30_000},async()=>{
  const url=new URL(databaseURL!);assert.equal(url.pathname,"/save_link_fixture");assert.equal(url.hostname,"127.0.0.1");assert.equal(url.port,"55449");
  url.username ||= userInfo().username;
  const pool=new Pool({connectionString:url.href});
  const dir=await mkdtemp(join(tmpdir(),"save-link-http-"));
  const calls=join(dir,"calls.jsonl"),hook=join(dir,"providers.mjs");
  await writeFile(calls,"");
  await writeFile(hook,`import {appendFileSync} from 'node:fs';
    globalThis.fetch=async (input,init)=>{
      const url=new URL(String(input));
      const gemini=url.hostname==='generativelanguage.googleapis.com';
      const google=url.hostname==='maps.googleapis.com';
      if(!gemini&&!google) throw new Error('External provider blocked');
      appendFileSync(process.env.LINK_FIXTURE_CALLS,JSON.stringify({provider:gemini?'gemini':'google'})+'\\n');
      const field=value=>({value,quote:value,source:'caption'});
      return Response.json(gemini?{candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify({venues:[{name:field('Fixture Cafe'),branch:null,address:field('1 Road'),transport:null}]})}]}}],usageMetadata:{promptTokenCount:100,candidatesTokenCount:30}}
       :{status:'OK',results:[{place_id:'fixture-venue',name:'Fixture Cafe',formatted_address:'1 Road',geometry:{location:{lat:25,lng:121}}}]});
    };`);
  const {publicKey,privateKey}=await generateKeyPair("ES256");
  const owners=[`did:privy:link-${randomUUID()}`,`did:privy:link-${randomUUID()}`];
  const tokens=await Promise.all(owners.map(owner=>new SignJWT({}).setProtectedHeader({alg:"ES256"}).setIssuer("privy.io").setAudience("link-fixture").setSubject(owner).setExpirationTime("5m").sign(privateKey)));
  const listener=createServer();listener.listen(0,"127.0.0.1");await once(listener,"listening");const port=(listener.address() as {port:number}).port;await new Promise<void>(resolve=>listener.close(()=>resolve()));
  const child=spawn(process.execPath,["--import",hook,new URL("./server.js",import.meta.url).pathname],{env:{PATH:process.env.PATH,HOME:process.env.HOME,NODE_ENV:"test",PORT:String(port),DATABASE_URL:url.href,PGSSLMODE:"disable",PRIVY_APP_ID:"link-fixture",PRIVY_VERIFICATION_KEY:await exportSPKI(publicKey),SAVE_GUEST_SESSION_SECRET:"link-fixture-only",SLLR_NOTIFY_INTERVAL_MS:"0",GEMINI_API_KEY:"synthetic",GOOGLE_PLACES_API_KEY:"synthetic",LINK_FIXTURE_CALLS:calls},stdio:["ignore","pipe","pipe"]});
  const exited=once(child,"exit");let log="";child.stdout.on("data",chunk=>{log+=chunk;});child.stderr.on("data",chunk=>{log+=chunk;});
  const api=async(path:string,who:number|null=0,body?:unknown,method=body===undefined?"GET":"POST")=>{
    const response=await fetch(`http://127.0.0.1:${port}${path}`,{method,signal:AbortSignal.timeout(5000),headers:{"content-type":"application/json",...(who===null?{}:{authorization:`Bearer ${tokens[who]}`})},body:body===undefined?undefined:JSON.stringify(body)});
    return {status:response.status,body:await response.json() as any,cache:response.headers.get("cache-control")};
  };
  try {
    let ready=false;const deadline=Date.now()+10_000;
    while(Date.now()<deadline&&!ready){if(child.exitCode!==null)throw new Error(log);try{ready=(await api("/",null)).status===200;}catch{}if(!ready)await new Promise(resolve=>setTimeout(resolve,50));}
    assert.ok(ready,log);
    assert.equal((await api("/v0/place-intelligence/trending",null)).status,401);
    const pop=await api("/v0/place-intelligence/trending");assert.equal(pop.status,200,JSON.stringify(pop.body));assert.equal(pop.cache,"private, no-store");assert.equal(pop.body.visit_evidence,"self_reported");
    const ids=[randomUUID(),randomUUID()];
    for(const id of ids)assert.equal((await api("/v0/analysis",0,{id})).status,201);
    for(const id of ids){const extracted=await api(`/v0/analysis/${id}/extract-place-clues`,0,{caption:"Fixture Cafe 1 Road"});assert.equal(extracted.status,200);assert.equal(extracted.body.venues[0].mapStatus,"matched");}
    const counts=(await readFile(calls,"utf8")).trim().split("\n").map(row=>JSON.parse(row));
    assert.equal(counts.filter(row=>row.provider==="gemini").length,1);assert.equal(counts.filter(row=>row.provider==="google").length,2);
    const cap=await api("/v0/memory/captures",0,{source_type:"url",source_url:"https://instagram.com/reel/fixture",raw_text:"Fixture Cafe 1 Road",analysis_id:ids[1]});
    assert.equal(cap.status,201,JSON.stringify(cap.body));
    assert.equal((await pool.query("select * from candidate_extraction_inputs where capture_id=$1",[cap.body.id])).rowCount,0,"a session ID alone is not candidate provenance");
    assert.equal((await api(`/v0/analysis/${ids[1]}/extract-place-clues`,1,{caption:"Fixture Cafe 1 Road"})).status,404);
    const place=await api("/v0/places",0,{name:"Fixture Cafe",address:"1 Road",latitude:25,longitude:121,google_place_id:"fixture-venue",source_url:"https://instagram.com/reel/fixture?igsh=private"});
    assert.equal(place.status,201,JSON.stringify(place.body));
    const sources=await api(`/v0/places/${place.body.id}/source-associations`);assert.equal(sources.status,200,JSON.stringify(sources.body));assert.equal(sources.cache,"private, no-store");assert.equal(sources.body.sources[0].url,"https://instagram.com/reel/fixture");
    assert.equal((await api(`/v0/places/${place.body.id}/source-associations`,1)).status,404);
    assert.equal((await api(`/v0/places/${place.body.id}/source-associations`,null)).status,401);
    assert.equal((await api("/v0/places/not-a-uuid/source-associations")).status,400);
  } finally {
    child.kill("SIGTERM");await exited;
    await writeFile(join(dir,"server.log"),log);
    await pool.query("delete from profiles where id=any($1::text[])",[owners]);await pool.end();
  }
});
