import assert from 'node:assert/strict';
import test from 'node:test';
import points from '../city170-bench-points.js';
import {addCityBenches, benchParts} from '../city170-benches.js';

test('bench IDs are unique to a single geographic cell and only tagged backrests rise above the seat', () => {
  const ids = new Set();
  for (const [cell, rows] of Object.entries(points)) {
    assert.match(cell, /^\d+_\d+$/);
    for (const row of rows) {
      assert.ok(!ids.has(row[0])); ids.add(row[0]);
      const parts = benchParts(row);
      assert.equal(parts.length, row[5] ? 4 : 3);
      for (const f of parts) {
        assert.ok(f.properties.height > f.properties.base);
        const ring = f.geometry.coordinates[0];
        assert.deepEqual(ring[0], ring.at(-1));
        for (const [x,y] of ring) assert.ok(Math.hypot((x-row[1])*100700,(y-row[2])*110574) < 1);
      }
    }
  }
  assert.ok(ids.size > 0);
});

test('0 and 90 degree tagged facings put the backrest south and west of the mapped seat', () => {
  for (const [angle,axis] of [[0,1],[90,0]]) {
    const c = [121.51,25.04];
    const [ring] = benchParts([123,...c,angle,'wood',1]).at(-1).geometry.coordinates;
    assert.ok(ring.slice(0,4).every(p => p[axis] < c[axis]));
  }
});

test('lazy bench data follows the current camera, is cleared on zoom out and survives teardown', async () => {
  const events = new Map(), draws = [];
  let x = 120, y = 23, zoom = 19, resolve, loads = 0;
  const map = {addSource(){}, addLayer(){}, getSource:() => ({setData:d=>draws.push(d.features)}),
    getBounds:() => ({getEast:()=>x+.00015,getWest:()=>x-.00015,getSouth:()=>y-.00015,getNorth:()=>y+.00015}),
    getZoom:() => zoom, on:(e,f)=>events.set(e,f), off:e=>events.delete(e)};
  const a = [11,121.51,25.04,null,'other',0], b = [12,121.52,25.05,90,'wood',1];
  const load = () => { loads++; return new Promise(r => { resolve = r; }); };
  addCityBenches(map,'before',load);
  assert.equal(loads,0);
  [x,y] = a.slice(1,3); zoom = 17; await events.get('moveend')(); assert.equal(loads,0);
  zoom = 19; const pending = events.get('moveend')();
  [x,y] = b.slice(1,3); await events.get('moveend')();
  resolve({a:[a],b:[b]}); await pending;
  assert.equal(loads,1); assert.deepEqual(draws.at(-1).map(f=>f.id),[120,121,122,123]);
  [x,y] = a.slice(1,3); await events.get('resize')(); assert.equal(draws.at(-1).length,3);
  zoom = 17; await events.get('moveend')(); assert.deepEqual(draws.at(-1),[]);
  events.get('remove')(); assert.ok(!events.has('moveend') && !events.has('resize'));
});
