import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {addXinyiRidgeWoods,RidgeCrowns} from '../xinyi-ridge-woods.js';

const bytes=readFileSync(new URL('../assets/xinyi-ridge-woods.json.gz',import.meta.url));
const art=JSON.parse(gunzipSync(bytes));
function mockMap(){
  const layers=new Map(['city170-water','city170-inventory-trees','city170-prepared-lane','labels'].map(id=>[id,{}]));
  const sources=new Map(),events=new Map(),view={zoom:13,box:[121.57,25.024,121.58,25.031]};
  const map={getZoom:()=>view.zoom,getBounds:()=>({
    getWest:()=>view.box[0],getSouth:()=>view.box[1],getEast:()=>view.box[2],getNorth:()=>view.box[3]}),
    on:(type,fn)=>events.set(type,fn),off:(type)=>events.delete(type),
    addLayer:(layer,before)=>{assert.ok(!layers.has(layer.id));layers.set(layer.id,{layer,before});},
    addSource:(id,source)=>{assert.ok(!sources.has(id));sources.set(id,source);},
    getLayer:id=>layers.get(id),getSource:id=>sources.get(id),removeSource:id=>sources.delete(id),
    removeLayer:id=>layers.delete(id)};
  return {view,map,events,layers,sources};
}

test('ridge relief, real trails and crowns load only for the visible district and release on departure',async t=>{
  const {map,view,layers,sources,events}=mockMap();
  const fetch=t.mock.method(globalThis,'fetch',async()=>new Response(bytes));
  addXinyiRidgeWoods(map,'labels');assert.equal(fetch.mock.callCount(),0);
  view.zoom=16.3;await events.get('moveend')();await events.get('moveend')();
  assert.equal(fetch.mock.callCount(),1);
  assert.deepEqual(sources.get('xinyi-ridge-relief').coordinates,art.corners);
  assert.equal(layers.get('xinyi-ridge-relief').before,'city170-water');
  assert.equal(layers.get('xinyi-ridge-crowns').before,'city170-inventory-trees');
  assert.ok(sources.get('xinyi-ridge-paths').data.features.some(f=>f.properties.name.includes('象山')));
  view.box=[121.50,25.06,121.51,25.07];await events.get('moveend')();
  assert.equal(sources.size,0);assert.equal(layers.size,4);
});

test('a stale request cannot install woodland over the next view',async t=>{
  const {map,view,events,sources}=mockMap();
  let resolve,signal;
  t.mock.method(globalThis,'fetch',(_url,options)=>{signal=options.signal;return new Promise(r=>{resolve=r;});});
  addXinyiRidgeWoods(map,'labels');view.zoom=17;
  const loading=events.get('moveend')();
  view.box=[121.50,25.06,121.51,25.07];await events.get('moveend')();
  assert.ok(signal.aborted);resolve(new Response(bytes));await loading;assert.equal(sources.size,0);
  events.get('remove')();assert.equal(events.has('moveend'),false);
});

test('the instanced broadleaf mesh uses the visible DEM altitude, depth and a bounded draw budget',()=>{
  const {map,view,events}=mockMap();view.zoom=16.4;view.box=[121.55,25.0,121.599,25.045];
  let elevation=173.125;
  map.terrain={getDrawnElevationForLngLat:()=>elevation};
  const uploads=[],draws=[],removed=[];
  const constants=['VERTEX_ARRAY_BINDING','ARRAY_BUFFER_BINDING','CURRENT_PROGRAM','DEPTH_FUNC','DEPTH_WRITEMASK',
    'ARRAY_BUFFER','STATIC_DRAW','DYNAMIC_DRAW','DEPTH_TEST','CULL_FACE','BLEND','LEQUAL'];
  const gl=new Proxy({getShaderParameter:()=>true,getProgramParameter:()=>true,
    ...Object.fromEntries(constants.map((k,i)=>[k,i+1])),isEnabled:()=>false,
    bufferData:(_target,data,mode)=>uploads.push([data,mode]),drawArraysInstanced:(...args)=>draws.push(args),
    deleteVertexArray:()=>removed.push('vao'),deleteBuffer:()=>removed.push('buffer'),deleteProgram:()=>removed.push('program')},
    {get:(o,k)=>o[k]??(()=>{})});
  const woods=new RidgeCrowns(art);woods.onAdd(map,gl);
  const opts={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  woods.render(gl,opts);const group=uploads.at(-1)[0];
  assert.equal(woods.count,450);assert.equal(draws.length,1);assert.ok(woods.vertices/3<200);
  for(let i=2;i<group.length;i+=5)assert.equal(group[i],173.125);
  woods.render(gl,opts);assert.equal(uploads.length,2);
  elevation=0;events.get('sourcedata')({sourceId:'dem',sourceDataType:'content'});woods.render(gl,opts);
  assert.equal(woods.count,0);assert.equal(draws.length,2);
  woods.onRemove(map,gl);assert.deepEqual(removed,['vao','buffer','buffer','program']);
});

test('a stationary camera recovers missing and mixed DEM tiles after first entry',async()=>{
  const {map,view,events}=mockMap();view.zoom=17.55;view.box=[121.574,25.025,121.577,25.028];
  const gl=new Proxy({getShaderParameter:()=>true,getProgramParameter:()=>true,isEnabled:()=>false},
    {get:(o,k)=>o[k]??(()=>{})});
  let available=0,source=0,drawQueries=0,repaints=0;
  map.terrain={getDrawnElevationForLngLat:loc=>{
    drawQueries++;
    if(available===2||available===1&&loc.lng<121.5755)return 165;
    return 0;
  }};
  map.queryTerrainElevation=()=>source;
  const layer=new RidgeCrowns(art),opts={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  layer.onAdd(map,gl);
  map.triggerRepaint=()=>{repaints++;layer.render(gl,opts);};
  layer.render(gl,opts);assert.equal(layer.count,0);const firstQueries=drawQueries;
  layer.render(gl,opts);assert.equal(drawQueries,firstQueries);
  available=1;events.get('idle')();assert.ok(layer.count>0&&layer.waitingForTerrain);const partly=layer.count;
  events.get('idle')();assert.equal(repaints,1);
  available=2;
  await new Promise(resolve=>setTimeout(resolve,190));
  assert.ok(layer.count>partly);assert.equal(layer.waitingForTerrain,false);assert.equal(layer.timer,null);
  assert.equal(repaints,2);
  // While a drawn DEM transitions, the active map's available elevation can
  // ground the whole group immediately without waiting for a new camera event.
  source=160;available=0;events.get('sourcedata')({sourceId:'dem',sourceDataType:'content'});
  layer.render(gl,opts);assert.ok(layer.count>partly&&layer.waitingForTerrain);
  layer.onRemove(map,gl);assert.equal(layer.timer,null);
});

test('zooming into a smaller viewport resamples even within the same instance budget',()=>{
  const {map,view}=mockMap();
  view.zoom=16.8;view.box=[121.5568,25.009,121.5921,25.036];
  map.terrain={getDrawnElevationForLngLat:()=>175};
  const gl=new Proxy({getShaderParameter:()=>true,getProgramParameter:()=>true,isEnabled:()=>false},
    {get:(o,k)=>o[k]??(()=>{})});
  const layer=new RidgeCrowns(art),opts={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  layer.onAdd(map,gl);layer.render(gl,opts);assert.equal(layer.count,680);
  view.zoom=19.4;view.box=[121.5748,25.0260,121.5760,25.0272];
  layer.render(gl,opts);
  const [w,s,e,n]=layer.region;
  const visible=layer.rows.filter(({loc})=>loc.lng>=w&&loc.lng<=e&&loc.lat>=s&&loc.lat<=n);
  assert.ok(visible.length>0&&visible.length<80);assert.equal(layer.count,visible.length);
  layer.onRemove(map,gl);
});
