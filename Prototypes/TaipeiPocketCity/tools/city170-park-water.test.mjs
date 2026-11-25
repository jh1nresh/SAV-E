import test from 'node:test';
import assert from 'node:assert/strict';
import cells, {snapshot} from '../city170-park-water-points.js';
import {addParkWater, parkWaterParts} from '../city170-park-water.js';

test('the Taipei park snapshot has unique official anchors and all parts stay inside their clearance',()=>{
  const rows=Object.values(cells).flat();
  assert.equal(rows.length,snapshot.candidates-Object.values(snapshot.exclusions).reduce((a,b)=>a+b,0));
  assert.equal(rows.length,new Set(rows.map(([id])=>id)).size);
  assert.equal(Object.keys(snapshot.districts).length,12);
  assert.equal(snapshot.asOf,'2026-10-31');
  for(const row of rows){
    const [id,x,y]=row;
    assert.match(id,/^[0-9]{4}[a-z]?$/);
    assert.ok(Number.isInteger(x)&&Number.isInteger(y));
    const solids=parkWaterParts(row);
    assert.equal(solids.length,8);
    assert.equal(solids[0].properties.base,0);
    assert.equal(Math.max(...solids.map(f=>f.properties.height)),1.09);
    assert.equal(solids.find(f=>f.id.endsWith('/rim')).geometry.coordinates.length,2);
    for(const part of solids)for(const ring of part.geometry.coordinates){
      assert.ok(part.properties.base<part.properties.height);
      assert.deepEqual(ring[0],ring.at(-1));
      for(const [lon,lat] of ring)assert.ok(Math.hypot((lon-x/1e7)*100800,(lat-y/1e7)*110574)<.46);
    }
  }
  assert.deepEqual(rows.find(([id])=>id==='0279'),['0279',1215046610,250197140]);
  assert.ok(!rows.some(([id])=>id==='1262'), 'the legacy tree in 朝陽茶業公園 overlaps the station');
});

test('street furniture is lazy and clears on zoom-out',async()=>{
  const callbacks=new Map(),states=[];
  let zoom=18.7, loaded=0;
  const map={
    addSource(){},addLayer(l){assert.equal(l.minzoom,19);assert.equal(l.id,'city170-park-water');},
    getSource:()=>({setData:d=>states.push(d.features)}),
    getBounds:()=>({getWest:()=>121.50465,getEast:()=>121.50467,getSouth:()=>25.01971,getNorth:()=>25.01972}),
    getZoom:()=>zoom,on:(e,f)=>callbacks.set(e,f),off:e=>callbacks.delete(e),
  };
  addParkWater(map,'labels',async()=>{loaded++;return cells;});
  assert.equal(loaded,0);
  zoom=20;await callbacks.get('moveend')();
  assert.ok(states.at(-1).some(f=>f.id==='0279/foot'));
  assert.equal(loaded,1);
  zoom=18;await callbacks.get('moveend')();
  assert.deepEqual(states.at(-1),[]);
  callbacks.get('remove')();
  assert.ok(!callbacks.has('moveend'));
});
