import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {unpackDistrictGround} from '../xinyi-street-ground.js';
import {addSongshanRiverMeadow} from '../songshan-river-meadow.js';

const bytes=readFileSync(new URL('../assets/songshan-river-meadow.json.gz',import.meta.url));
const meadow=JSON.parse(gunzipSync(bytes));
const plots=meadow.features.filter(f=>f.properties.kind==='grassland');
const clumps=meadow.features.filter(f=>f.properties.kind==='clump');
function covers(p,geometry){
  if(geometry.type==='MultiPolygon')return geometry.coordinates.some(coordinates=>covers(p,{type:'Polygon',coordinates}));
  let inside=false;
  for(const ring of geometry.coordinates)for(let i=1;i<ring.length;i++){
    const [x,y]=ring[i-1],[u,v]=ring[i];
    if((y>p[1])!==(v>p[1])&&p[0]<x+(u-x)*(p[1]-y)/(v-y))inside=!inside;
  }
  return inside;
}
function edgeDistance([x,y],line){
  let closest=Infinity;
  for(let i=1;i<line.length;i++){
    const u=(line[i-1][0]-x)*100907.4,v=(line[i-1][1]-y)*110773.3;
    const dx=(line[i][0]-line[i-1][0])*100907.4,dy=(line[i][1]-line[i-1][1])*110773.3;
    const t=Math.max(0,Math.min(1,-(u*dx+v*dy)/(dx*dx+dy*dy||1)));
    closest=Math.min(closest,Math.hypot(u+t*dx,v+t*dy));
  }
  return closest;
}

test('75 varied grass clumps stay within two mapped land footprints with room for the whole sprite',()=>{
  assert.equal(plots.length,2);
  assert.equal(clumps.length,75);
  assert.equal(new Set(clumps.map(f=>f.properties.form)).size,3);
  for(const tuft of clumps){
    const plot=plots.find(f=>f.properties.sourceId===tuft.properties.sourceId);
    assert.ok(covers(tuft.geometry.coordinates,plot.geometry));
    assert.ok(edgeDistance(tuft.geometry.coordinates,plot.geometry.coordinates[0])>=1.599);
    assert.ok(tuft.properties.scale>=.66&&tuft.properties.scale<=1);
  }
});

test('the rendered Songshan pavers leave room for the grass and its grounded sprite edges',()=>{
  const packed=readFileSync(new URL('../assets/songshan-street-ground.json.gz',import.meta.url));
  const paving=unpackDistrictGround(JSON.parse(gunzipSync(packed))).features.filter(f=>
    f.geometry.type==='Polygon'&&f.geometry.coordinates[0].some(([x,y])=>
      x>121.5689&&x<121.56985&&y>25.0612&&y<25.0624));
  assert.ok(paving.length>0);
  for(const f of plots)for(const ring of f.geometry.coordinates)for(const p of ring){
    for(const path of paving)if(covers(p,path.geometry)){
      assert.ok(path.geometry.coordinates.some(edge=>edgeDistance(p,edge)<.001));
    }
  }
  for(const f of clumps)for(const path of paving){
    assert.ok(!covers(f.geometry.coordinates,path.geometry));
    for(const edge of path.geometry.coordinates)assert.ok(edgeDistance(f.geometry.coordinates,edge)>1.6);
  }
});

const data=process.env.POCKET_TAIPEI_DATA;
test('both covers and all grass roots belong to Guanshan on the Songshan side of the Keelung River',{skip:!data},()=>{
  const read=path=>JSON.parse(gunzipSync(readFileSync(join(data,path))));
  const fs=['p226_2038','p226_2039'].flatMap(pack=>read('city170/'+pack+'.json.gz').features.features);
  const park=fs.find(f=>f.id===meadow.park);
  const water=fs.find(f=>f.id===meadow.river);
  const districts=JSON.parse(readFileSync(join(data,'districts.geojson'))).features;
  const district=districts.find(f=>f.properties.name==='松山區');
  assert.equal(park.properties.name,'觀山河濱公園');assert.equal(water.properties.name,'基隆河');
  const paths=fs.filter(f=>['road','walk'].includes(f.properties.kind)&&f.geometry.type==='LineString'&&
    f.geometry.coordinates.some(([x,y])=>x>121.5687&&x<121.57&&y>25.061&&y<25.063));
  assert.ok(paths.some(f=>f.properties.name==='基隆河左岸自行車道'));
  for(const f of plots){
    const original=fs.find(s=>s.id===f.properties.sourceId);
    assert.equal(original.properties.natural,'grassland');
    for(const ring of f.geometry.coordinates)for(const p of ring){
      assert.ok(covers(p,park.geometry)&&covers(p,district.geometry));
      assert.ok(covers(p,original.geometry)||edgeDistance(p,original.geometry.coordinates[0])<.002);
      assert.ok(!covers(p,water.geometry));
      for(const path of paths)assert.ok(edgeDistance(p,path.geometry.coordinates)>=path.properties.width/2-.002);
    }
  }
  for(const f of clumps)for(const path of paths){
    assert.ok(edgeDistance(f.geometry.coordinates,path.geometry.coordinates)>=path.properties.width/2+1.59);
  }
});

function runtime(t){
  const layers=new Map(),sources=new Map(),images=new Set(),events=new Map();
  const camera={zoom:15.1,west:121.568};
  const map={getZoom:()=>camera.zoom,getSource:id=>sources.get(id),getLayer:id=>id==='city170-pitch'||layers.get(id),
    getBounds:()=>({getWest:()=>camera.west,getEast:()=>camera.west+.004,getNorth:()=>25.063,getSouth:()=>25.061}),
    on:(event,fn)=>events.set(event,fn),off:event=>events.delete(event),
    addSource:(id,value)=>sources.set(id,value),removeSource:id=>{assert.equal(layers.size,0);assert.ok(sources.delete(id));},
    hasImage:id=>images.has(id),addImage:id=>{assert.ok(!images.has(id));images.add(id);},
    removeImage:id=>{assert.equal(layers.size,0);assert.ok(images.delete(id));},
    addLayer:(layer,before)=>{assert.equal(before,'city170-pitch');layers.set(layer.id,layer);},
    removeLayer:id=>assert.ok(layers.delete(id))};
  const ctx=new Proxy({getImageData:()=>({width:80,height:42})},{get:(o,k)=>o[k]??(()=>{})});
  const old=globalThis.document;
  globalThis.document={createElement:()=>({getContext:()=>ctx})};
  t.after(()=>{if(old===undefined)delete globalThis.document;else globalThis.document=old;});
  addSongshanRiverMeadow(map,'label');
  return {map,camera,layers,events,update:()=>events.get('moveend')(),size:()=>[layers.size,sources.size,images.size]};
}

test('the meadow retries missing assets and releases its source, layers and images when leaving or zooming out',async t=>{
  let requests=0;
  t.mock.method(globalThis,'fetch',async()=>++requests===1?new Response(null,{status:404}):new Response(bytes));
  t.mock.method(console,'warn',()=>{});
  const {camera,layers,update,size}=runtime(t);
  assert.equal(requests,0);
  camera.west=121.48;camera.zoom=18;await update();assert.equal(requests,0);
  camera.west=121.568;await update();assert.deepEqual(size(),[0,0,0]);
  await update();assert.equal(requests,2);assert.deepEqual(size(),[2,1,3]);
  assert.deepEqual([...layers.values()].map(l=>l.type),['fill','symbol']);
  assert.equal(layers.get('songshan-river-meadow-clumps').layout['icon-anchor'],'bottom');
  camera.west=121.5704;await update();assert.deepEqual(size(),[2,1,3]); // within retention margin
  camera.west=121.58;await update();assert.deepEqual(size(),[0,0,0]);
  camera.west=121.5704;await update();assert.equal(requests,2); // only load on actual overlap
  camera.west=121.568;await update();assert.deepEqual(size(),[2,1,3]);
  camera.zoom=15.19;await update();assert.deepEqual(size(),[0,0,0]);
  camera.zoom=18;await update();assert.equal(requests,4);assert.deepEqual(size(),[2,1,3]);
});

test('late completion from an abandoned visit cannot install layers or clear the new request',async t=>{
  const requests=[];
  t.mock.method(globalThis,'fetch',(_url,{signal})=>new Promise(resolve=>requests.push({signal,resolve})));
  const {camera,events,update,size}=runtime(t);
  camera.zoom=18;
  const old=update();
  camera.west=121.58;await update();
  assert.ok(requests[0].signal.aborted);
  camera.west=121.568;
  const current=update();
  requests[0].resolve(new Response(bytes));await old;
  assert.deepEqual(size(),[0,0,0]);
  await update();assert.equal(requests.length,2);
  requests[1].resolve(new Response(bytes));await current;
  assert.deepEqual(size(),[2,1,3]);
  camera.zoom=14;await update();camera.zoom=18;
  const final=update();events.get('remove')();
  assert.ok(requests[2].signal.aborted);
  requests[2].resolve(new Response(bytes));await final;
  assert.deepEqual(size(),[0,0,0]);assert.ok(!events.has('moveend'));
});

test('a failure after partial style installation can retry without duplicate sprite IDs',async t=>{
  t.mock.method(globalThis,'fetch',async()=>new Response(bytes));
  t.mock.method(console,'warn',()=>{});
  const {map,camera,update,size}=runtime(t);
  const addLayer=map.addLayer;
  map.addLayer=(layer,before)=>{
    if(layer.type==='symbol')throw Error('style interrupted');
    addLayer(layer,before);
  };
  camera.zoom=18;await update();assert.deepEqual(size(),[0,0,0]);
  map.addLayer=addLayer;await update();assert.deepEqual(size(),[2,1,3]);
});
