import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {taipei200Scenes,streetPaintUpdate,taipei200Grid} from '../taipei200.js';

const west=[121.50,25,121.502,25.002],east=[121.502,25,121.504,25.002];
const area=[west[0],west[1],east[2],east[3]],a=[121.501,25.001],b=[121.503,25.001];
const ring=[0,0,20,0,0,20,-20,0,0,-20];
const hole=[4,4,0,4,4,0,0,-4,-4,0];
const left={'15_16':[west,a,['大安區','信義區'],[[[ring,hole]],[],[]]]};
const right={'16_16':[east,b,['信義區'],[[],[[ring]],[]]]};
const index={size:200,crs:'EPSG:3826',cells:2,districtCells:{大安區:1,信義區:2},
  packs:[{id:'1_2',bounds:west,cells:1},{id:'2_2',bounds:east,cells:1}]};
function remember(){
  const pending=new Map();
  return (key,load)=>{
    if(!pending.has(key))pending.set(key,load().catch(e=>{pending.delete(key);throw e;}));
    return pending.get(key);
  };
}
function deferred(){
  let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});
  return {promise,resolve,reject};
}

test('viewport packs decode local 5 cm deltas, holes and district colours, once across concurrent views',async()=>{
  const fetched=[];
  const scenes=taipei200Scenes(remember(),async key=>{
    fetched.push(key);
    return {'index.json':index,'1_2.json.gz':left,'2_2.json.gz':right}[key];
  });
  assert.equal(scenes.coverage(),null);
  const [both,one]=await Promise.all([scenes.inView(area),scenes.inView([west[0],west[1],a[0],a[1]])]);
  assert.deepEqual(both.cells,['15_16','16_16']);assert.deepEqual(one.cells,['15_16']);
  assert.deepEqual(fetched.sort(),['1_2.json.gz','2_2.json.gz','index.json']);
  const [lane,crossing]=both.features;
  assert.equal(lane.properties.kind,'lane');assert.equal(crossing.properties.kind,'crossing');
  assert.notEqual(lane.properties.districtStreetMask,crossing.properties.districtStreetMask);
  const [outer,inner]=lane.geometry.coordinates[0];
  assert.deepEqual(outer[0],a);assert.deepEqual(outer[4],a);assert.deepEqual(inner[0],inner.at(-1));
  assert.ok(Math.abs((outer[1][0]-a[0])*111320*Math.cos(a[1]*Math.PI/180)-1)<1e-8);
  assert.ok(Math.abs((outer[2][1]-a[1])*110574-1)<1e-8);
  assert.equal(scenes.coverage().cells,2);
});

test('the Shilin snapshot survives terrain settling, and asks for a new snapshot on crossing a real cell edge',async()=>{
  const root=new URL('../assets/taipei200/',import.meta.url);
  const load=async name=>{
    const binary=await readFile(new URL(name,root));
    return JSON.parse(name.endsWith('.gz')?gunzipSync(binary):binary);
  };
  const key='1514_13885',row=(await load('189_1735.json.gz'))[key];
  const [x,y]=row[1], view=[x-.00050,y-.00036,x+.00050,y+.00036];
  const scenes=taipei200Scenes(remember(),load),snapshot=await scenes.inView(view);
  assert.deepEqual(snapshot.visibleCells(view),[key]);
  const settled=view.map((n,i)=>n+(i%2?.000003:-.000006));
  assert.notEqual(view.join(','),settled.join(','));
  assert.deepEqual(snapshot.visibleCells(settled),[key]);
  const expanded=[...settled];expanded[2]=row[0][2]+.00014;
  assert.equal(snapshot.visibleCells(expanded),null);
  const refreshed=await scenes.inView(expanded);
  assert.ok(refreshed.visibleCells(expanded).includes(key));
  assert.ok(refreshed.visibleCells(expanded).length>1);
});

test('a malformed adjacent pack cannot replace valid legacy markings; a subsequent request recovers',async()=>{
  const keys=[];let broken=true;
  const scenes=taipei200Scenes(remember(),async key=>{
    keys.push(key);
    if(key==='index.json')return index;
    if(key==='1_2.json.gz')return left;
    return broken?{'16_16':[east,b,['信義區'],[[],[[[0,0,20,0,0,20,-20,0]]],[]]]}:right;
  });
  await assert.rejects(scenes.inView(area),/Open 200m ring/);broken=false;
  assert.equal((await scenes.inView(area)).cells.length,2);
  assert.equal(keys.filter(k=>k==='2_2.json.gz').length,2);
  assert.equal(keys.filter(k=>k==='1_2.json.gz').length,1);
});

const old=['lane','crossing','skill-paving','grove-tree','fixture'].map(kind=>({properties:{kind}}));
const fresh={cells:['15_16'],features:[{properties:{kind:'lane',scene200:'15_16'}}]};
test('both sides switch together, keeping the original trees; source completion precedes readiness',async()=>{
  const pack=deferred(),worker=deferred(),entered=deferred(),legacy=deferred(),writes=[];
  const source={setData:async data=>{
    writes.push(data.features);if(writes.length===2){entered.resolve();await worker.promise;}
  }};
  let ready=false;
  const done=streetPaintUpdate(pack.promise)(source,old,()=>true,legacy.resolve).then(s=>{ready=true;return s;});
  await legacy.promise;assert.deepEqual(writes,[old]);
  pack.resolve(fresh);
  await entered.promise;
  assert.equal(ready,false);
  assert.deepEqual(writes[1],[old[3],old[4],fresh.features[0]]);
  worker.resolve();assert.equal(await done,fresh);assert.equal(ready,true);
});
test('late departure, a rejected scene, and a rejected source write all retain the complete fallback',async()=>{
  let active=true;const pending=deferred(),writes=[];
  const src={setData:data=>{writes.push(data.features);}};
  const first=streetPaintUpdate(pending.promise)(src,old,()=>active,()=>{});
  active=false;pending.resolve(fresh);await first;
  assert.deepEqual(writes,[old]);
  await assert.rejects(streetPaintUpdate(Promise.reject(Error('bad pack')))(src,old,()=>true,()=>{}),/bad pack/);
  assert.equal(writes.at(-1),old);
  let fallback=false;
  const update=streetPaintUpdate(Promise.resolve(fresh));await Promise.resolve();
  let onError;
  const reject={on:(_,cb)=>{onError=cb;},off:()=>{onError=null;},setData:async data=>{
    if(data.features!==old)onError({error:Error('worker')});else fallback=true;
  }};
  await assert.rejects(update(reject,old,()=>true,()=>{}),/worker/);assert.ok(fallback);
});
test('grid cancels on hide and re-entry, and publishes only clipped footprints in the latest viewport',async()=>{
  const requests=[],writes=[];
  let bounds=west;
  const map={getBounds:()=>({getWest:()=>bounds[0],getSouth:()=>bounds[1],getEast:()=>bounds[2],getNorth:()=>bounds[3]}),
    getZoom:()=>12,getSource:()=>({setData:data=>writes.push(data.features)})};
  const grid=taipei200Grid(map,(_,signal)=>{const r=deferred();requests.push({...r,signal});return r.promise;});
  function feature(id,[x,y]){
    return {type:'Feature',id,properties:{id},geometry:{type:'Polygon',coordinates:[[[x,y],[x+.0001,y],[x,y+.0001],[x,y]]]}};
  }
  const data={type:'FeatureCollection',features:[feature('left',a),feature('right',b)]};
  const stale=grid.show(true);await grid.show(false);assert.equal(requests[0].signal.aborted,true);
  const current=grid.show(true);bounds=east;await grid.show(true);
  requests[0].resolve(data);await stale;assert.equal(writes.length,0);
  requests[1].resolve(data);await current;assert.deepEqual(writes.at(-1),[data.features[1]]);
  await grid.show(true);assert.equal(writes.length,1);await grid.show(false);assert.deepEqual(writes.at(-1),[]);
});

test('the runtime decodes every shipped 200m pack and registers the same 7,047 footprints as the municipal grid',async()=>{
  const root=new URL('../assets/taipei200/',import.meta.url);
  const load=async name=>{
    const binary=await readFile(new URL(name,root));
    return JSON.parse(name.endsWith('.gz')?gunzipSync(binary):binary);
  };
  const meta=await load('index.json'),grid=await load('grid.json.gz');
  assert.equal(meta.cells,7047);assert.equal(Object.keys(meta.districtCells).length,12);
  const ids=new Set(grid.features.map(f=>f.id));
  assert.equal(ids.size,meta.cells);
  for(const p of meta.packs){
    const subset={...meta,cells:p.cells,packs:[p]};
    const scenes=taipei200Scenes(remember(),name=>name==='index.json'?subset:load(name));
    const result=await scenes.inView(p.bounds);
    assert.equal(result.cells.length,p.cells);
    for(const id of result.cells)assert.ok(ids.delete(id));
    for(const f of result.features)assert.ok(result.cells.includes(f.properties.scene200));
  }
  assert.equal(ids.size,0);
});
