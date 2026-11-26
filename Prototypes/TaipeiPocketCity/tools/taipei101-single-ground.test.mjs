import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {geographicPoint} from '../cities/geography.js';
import {meta,coordinates} from '../taipei101-single-ground-data.js';
import {add101Ground,inside101Ground,touches101Ground,planting101,walks101} from '../taipei101-single-ground.js';
import {streetMeshes101,streetObjects101} from '../taipei101-single-furniture.js';
import {StreetScenery} from '../street-scenery.js';
import {StreetPeople} from '../street-people.js';
import {MercatorCoordinate} from '../assets/maplibre-gl.mjs';
import {buildingZoom} from '../survey-layer.js';

test('the complete 101 tower view retains plaza objects and walking routes at phone zoom',t=>{
  const previous=globalThis.matchMedia;
  globalThis.matchMedia=()=>({matches:false});
  t.after(()=>{if(previous)globalThis.matchMedia=previous;else delete globalThis.matchMedia;});
  const bounds={toArray:()=>[[121.562,25.031],[121.567,25.035]]};
  const map={on(){},getZoom:()=>16.22,isSourceLoaded:()=>true,queryTerrainElevation:()=>12,getBounds:()=>bounds};
  const gl=new Proxy({},{get:()=>()=>true});
  const scene=new StreetScenery('street-101',[121.5645,25.033],streetObjects101,MercatorCoordinate,false,true);
  scene.onAdd(map,gl);scene.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  assert.ok(scene.drawnTriangles>0);
  const other=new StreetScenery('street-other',[121.5645,25.033],streetObjects101,MercatorCoordinate,false,true);
  other.onAdd(map,gl);other.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  assert.equal(other.drawnTriangles,0);
  const people=new StreetPeople('street-101',[121.5645,25.033],walks101,buildingZoom,true);
  people.map=map;assert.ok(people.isActive(bounds));
});

test('the source plaza image follows its rotated 200 m plot and draws below map shadows',async()=>{
  const layers=[],sources=[];
  add101Ground({addSource:(id,data)=>sources.push([id,data]),addLayer:(layer,before)=>layers.push([layer,before]),getLayer:id=>id==='atlas-shadows'});
  assert.equal(layers[0][1],'atlas-shadows');
  assert.equal(sources[0][1].type,'image');
  const corners=[[-100,100],[100,100],[100,-100],[-100,-100]].map(p=>geographicPoint(meta,p));
  for(const [i,p] of corners.entries())for(const [axis,v] of p.entries())assert.ok(Math.abs(v-coordinates[i][axis])<1e-8);
  for(const p of [[0,0],[-99,99],[99,-99]])assert.ok(inside101Ground(...geographicPoint(meta,p)));
  for(const p of [[101,0],[0,-101]])assert.ok(!inside101Ground(...geographicPoint(meta,p)));
  assert.ok(!touches101Ground([121.43,25.17,121.44,25.18]));
  const png=await readFile(new URL('../assets/taipei101-single-ground.png',import.meta.url));
  assert.equal(png.readUInt32BE(16),2048);assert.equal(png.readUInt32BE(20),2048);
  assert.equal(createHash('sha256').update(png).digest('hex'),'18e323717a22d295c7bbea0b108a1f81830446b5022d4c543d363484f28e3753');
});

test('the plaza supplies source plantings, walking routes and ground-anchored street objects',()=>{
  assert.equal(planting101.length,38);
  assert.equal(new Set(planting101.map(p=>p.slice(0,2).join(','))).size,38);
  assert.ok(planting101.every(([x,y,h])=>inside101Ground(x,y)&&h===7.2));
  assert.equal(walks101.length,54);
  assert.ok(walks101.every(r=>r.single101&&r.points.length>=2&&r.people===1));
  const types=streetObjects101.map(o=>o[2]);
  assert.equal(types.filter(t=>t==='single101-lamp').length,52);
  assert.equal(types.filter(t=>t==='single101-shelter').length,2);
  assert.equal(types.filter(t=>t==='single101-cafe').length,9);
  assert.ok(streetObjects101.filter(o=>o[2]!=='single101-lamp').every(o=>streetMeshes101[o[5]].length%12===0));
});
