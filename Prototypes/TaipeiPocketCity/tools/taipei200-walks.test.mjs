import {test} from 'node:test';
import assert from 'node:assert/strict';
import packs from '../taipei200-walks-data.js';
import {StreetPeople} from '../street-people.js';
import {inside101Ground} from '../taipei101-single-ground.js';

test('200 m walks share their identity and exact geometry across streaming pack seams',()=>{
  const paths=new Map();
  let shared=0;
  for(const rows of Object.values(packs)){
    const ids=new Set();
    for(const [key,points,people] of rows){
      assert.ok(!ids.has(key));ids.add(key);
      assert.ok(points.length>=2 && people>=1 && people<=4);
      assert.ok(points.every(([lng,lat])=>!inside101Ground(lng,lat)));
      if(paths.has(key)){assert.deepEqual(paths.get(key),{points,people});shared++;}
      paths.set(key,{points,people});
    }
  }
  assert.ok(shared>0);
});

test('a moving figure keeps its position and mesh when neighbouring route packs change',t=>{
  globalThis.matchMedia=()=>({matches:false});
  globalThis.document={hidden:false};
  t.after(()=>{delete globalThis.matchMedia;delete globalThis.document;});
  const [key,points]=Object.values(packs)[0][0];
  const origin=points[0];
  const existing={paths:{[key]:{points,people:1}}};
  const remote={paths:{'offscreen':{points:[[0,0],[0,.001]],people:1}}};
  // Render the real triangle mesh at a known instant, including rain and gait.
  const bounds={toArray:()=>[[120,24],[122,26]],contains:()=>true};
  const map={getBounds:()=>bounds,getZoom:()=>19,queryTerrainElevation:()=>7};
  const noop=()=>{};
  function render(model){
    let vertices;
    const gl=new Proxy({bufferSubData:(_t,_o,array,start,size)=>{vertices=array.slice(start,start+size);}},
      {get:(target,key)=>target[key]??noop});
    model.map=map;
    model.paused=true;
    model.umbrellaShare=4;
    model.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
    assert.equal(model.count,1);
    assert.equal(model.umbrellas,1);
    return vertices;
  }
  const before=StreetPeople.forStreetPacks(origin,[existing],true);
  const start=render(before);
  before.elapsed=18;
  const after=render(before);
  assert.notDeepEqual(after,start);
  const next=StreetPeople.forStreetPacks(points.at(-1),[remote,existing,existing],true,before);
  assert.deepEqual(render(next),after);
  assert.deepEqual(next.firstPosition,before.firstPosition);
});

test('native flat recovery retains walkers and offscreen districts release crowd buffers',t=>{
  const prior={document:globalThis.document,matchMedia:globalThis.matchMedia};
  globalThis.document={hidden:false};globalThis.matchMedia=()=>({matches:false});
  t.after(()=>{for(const [key,value] of Object.entries(prior)){
    if(value===undefined)delete globalThis[key];else globalThis[key]=value;
  }});
  const origin=[121.576,25.041],path={points:[origin,[121.577,25.041]],people:2};
  const crowd=new StreetPeople('regression',origin,[path],16.65,true);
  assert.equal(crowd.vertexData.byteLength,0);
  let zoom=19,terrain=null,elevation=null,vertices;
  const allocations=[];
  crowd.map={getZoom:()=>zoom,getTerrain:()=>terrain,queryTerrainElevation:()=>elevation,
    getBounds:()=>({toArray:()=>[[121.57,25.04],[121.58,25.05]],contains:()=>true})};
  crowd.paused=true;
  const noop=()=>{},gl=new Proxy({
    bufferData:(_target,size)=>allocations.push(size),
    bufferSubData:(_target,_offset,data,start,length)=>{vertices=data.slice(start,start+length);},
  },{get:(obj,key)=>obj[key]??noop});
  const render=()=>crowd.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  render();assert.equal(crowd.count,2);assert(vertices.every(Number.isFinite));
  const flat=vertices;
  terrain={source:'dem'};render();assert.equal(crowd.count,0); // Never invent a hillside height.
  elevation=12;render();assert.equal(crowd.count,2);
  for(let i=2;i<vertices.length;i+=6)assert(Math.abs(vertices[i]-flat[i]-12)<.0001);
  const allocated=crowd.vertexData.byteLength;
  zoom=14;render();assert.equal(crowd.count,0);assert.equal(crowd.vertexData.byteLength,0);
  assert.deepEqual(allocations,[allocated,0]);
  zoom=19;render();assert.equal(crowd.count,2);assert.equal(allocations.at(-1),allocated);
});
