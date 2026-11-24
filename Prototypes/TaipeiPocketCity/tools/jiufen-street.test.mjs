import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {plotOverlaps} from '../authored-footprint.js';
import {geographicPoint,geographicScene} from '../cities/geography.js';
const json=path=>JSON.parse(readFileSync(new URL('../cities/'+path,import.meta.url)));

test('a narrow street reserves crossing buildings but keeps neighbours and courtyard holes',()=>{
  const row={bounds:[0,0,9,9],footprint:{type:'Polygon',coordinates:[
    [[0,0],[8,7],[9,9],[7,8],[0,1],[0,0]],
    [[4.8,4.8],[5.1,4.8],[5.1,5.1],[4.8,5.1],[4.8,4.8]],
  ]}};
  assert.equal(plotOverlaps(row,[.1,6,.3,7]),false);
  assert.equal(plotOverlaps(row,[4,3,4.2,5]),true);
  assert.equal(plotOverlaps(row,[5,5,5,5]),false);
  assert.equal(plotOverlaps(row,[2,2,2,2]),true);
});
test('the real stair route and two original venue pins share the street camera viewport',()=>{
  const row=json('catalog.json').find(r=>r.id==='jiufen-shuqi');
  const scene=json('jiufen-shuqi/scene.json');
  assert.ok(row.camera.zoom>=18);
  const features=geographicScene(scene,row.landmarkIds,row.landmarkSites,row.landmarkPlaceIds);
  for(const [name,id] of [['阿妹茶樓','poi/node/2071356259'],['昇平戲院','poi/way/272732655']]){
    assert.ok(features.some(f=>f.properties.name===name&&f.properties.placeId===id));
  }
  const steps=scene.centerlines.find(r=>r.name==='豎崎路');
  assert.ok(steps.p.length>=7);
  for(const p of steps.p){
    const [x,y]=geographicPoint(scene.meta,p);
    // Catalog geometry is rounded to seven decimal degrees at the end landings.
    assert.ok(plotOverlaps(row,[x-1e-7,y-1e-7,x+1e-7,y+1e-7]),'footprint contains stair centerline');
  }
});

test('the z14 building beside the upper shops keeps its walls and rooftop details',()=>{
  const row=json('catalog.json').find(r=>r.id==='jiufen-shuqi');
  // OpenMapTiles building 1968427370 in 14/13737/7010.
  const ring=[[121.84344828128815,25.108339054266736],[121.84355556964874,25.108353626820914],[121.84358775615692,25.108144753378596],[121.84348583221436,25.10813018079955],[121.84344828128815,25.108339054266736]];
  const xs=ring.map(p=>p[0]),ys=ring.map(p=>p[1]);
  const bounds=[Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)];
  assert.equal(plotOverlaps(row,bounds),true);
  assert.equal(plotOverlaps(row,bounds,[ring]),false);
});

test('teahouse lanterns have real mesh anchors and share the street terrain datum',()=>{
  const scene=json('jiufen-shuqi/scene.json'),index=json('jiufen-shuqi/map-mesh.json');
  assert.equal(scene.lanterns.length,28);
  assert.equal(new Set(scene.lanterns.map(p=>p.join(','))).size,28);
  for(const [east,north,height,radius] of scene.lanterns){
    assert.ok([east,north,height,radius].every(Number.isFinite)&&radius>0&&radius<1);
    const [x,y]=geographicPoint(scene.meta,[east,north]);
    assert.ok(Math.abs(x-121.8436)<.001&&Math.abs(y-25.10845)<.001);
  }
  assert.ok(index.parts.every(p=>p.at.join(',')===index.parts[0].at.join(',')));
});
