import test from 'node:test';
import assert from 'node:assert/strict';
import cells from '../city170-hydrant-points.js';
import {addCityHydrants,hydrantParts} from '../city170-hydrants.js';

test('measured ground pillar by Taipei 101 appears once, with a closed foot and a model in metres',()=>{
  const ids = new Set();
  for (const [key,rows] of Object.entries(cells)) {
    assert.match(key,/^\d+_\d+$/);
    for (const [id,x,y] of rows) {
      assert.ok(!ids.has(id));
      ids.add(id);
      assert.ok(Number.isInteger(x) && x>121.45e7 && x<121.68e7);
      assert.ok(Number.isInteger(y) && y>24.95e7 && y<25.22e7);
    }
  }
  assert.ok(ids.size>2000);
  const row=cells['1805_16291'].find(r=>r[0]===6336472365);
  assert.deepEqual(row,[6336472365,1215636237,250337352]);
  const solids = hydrantParts(row);
  assert.equal(solids.length,8);
  assert.equal(solids[0].properties.base,0);
  assert.equal(Math.max(...solids.map(f=>f.properties.height)),.81);
  const x=row[1]/1e7, y=row[2]/1e7;
  for (const f of solids) {
    assert.ok(f.properties.base < f.properties.height);
    const ring=f.geometry.coordinates[0];
    assert.deepEqual(ring[0],ring.at(-1));
    assert.ok(ring.every(([lon,lat])=>Math.hypot((lon-x)*100800,(lat-y)*110574) < .30));
  }
  assert.ok(!ids.has(656401283), 'known underground hydrant is absent');
});

test('fetches only in Taipei close-up, rechecks a moving camera, and clears on zoom-out', async()=>{
  const events=new Map(), result=[];
  let lon=120, zoom=20, resolve, requests=0, layer;
  const map={
    addSource(){}, addLayer(l){layer=l;}, getSource:()=>({setData:d=>result.push(d.features)}),
    getBounds:()=>({getWest:()=>lon-.00001,getEast:()=>lon+.00001,getSouth:()=>25,getNorth:()=>25.001}),
    getZoom:()=>zoom,on:(e,cb)=>events.set(e,cb),off:e=>events.delete(e),
  };
  addCityHydrants(map,'labels',()=>{requests++;return new Promise(r=>{resolve=r;});});
  assert.equal(layer.minzoom,19);
  assert.equal(requests,0);
  lon=121.51;zoom=18;await events.get('moveend')();assert.equal(requests,0);
  zoom=20;const first=events.get('moveend')();await events.get('resize')();assert.equal(requests,1);
  lon=121.56;resolve({one:[[1,1215100000,250005000]],two:[[2,1215600000,250005000]]});
  await first;assert.deepEqual(result.at(-1).map(f=>f.id),[20,21,22,23,24,25,26,27]);
  const writes=result.length;
  await events.get('moveend')();assert.equal(result.length,writes);
  zoom=18;await events.get('moveend')();assert.deepEqual(result.at(-1),[]);
  events.get('remove')();assert.ok(!events.has('moveend'));
});
