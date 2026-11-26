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
