import test from 'node:test';
import assert from 'node:assert/strict';
import groups from '../city170-bus-shelter-points.js';
import {shelterParts} from '../city170-bus-shelters.js';

test('boarding canopy has a supported roof and signed seating at its mapped stop',()=>{
  const all=Object.values(groups).flat();
  assert.equal(new Set(all.map(r=>r[0])).size,all.length);
  const stop=all.find(row=>row[0]===2312619107);
  assert.ok(stop);
  assert.equal(stop[4],1);
  const full=shelterParts(stop),bare=shelterParts([...stop.slice(0,4),0,...stop.slice(5)]);
  assert.equal(full.length,bare.length+3);
  assert.equal(new Set(full.map(f=>f.id)).size,full.length);
  assert.ok(full.some(f=>f.properties.base===0));
  assert.equal(Math.max(...full.map(f=>f.properties.height)),2.6);
  const [,,lat]=stop;
  for(const f of full){
    assert.ok(f.properties.height>f.properties.base);
    const ring=f.geometry.coordinates[0];
    assert.deepEqual(ring.at(-1),ring[0]);
    for(const [x,y] of ring){
      assert.ok(Math.hypot((x-stop[1]/1e7)*111320*Math.cos(lat/1e7*Math.PI/180),(y-lat/1e7)*110574)<2.23);
    }
  }
});

test('compact shelters keep their boarding position and fit a tighter footprint',()=>{
  const compact=Object.values(groups).flat().find(row=>row[5]===2.8);
  assert.ok(compact);
  assert.equal(compact[6],1.5);
  const roof=(row)=>shelterParts(row).find(f=>f.properties.height===2.6).geometry.coordinates[0];
  const small=roof(compact), full=roof([...compact.slice(0,5),4,1.9]);
  const distance=(a,b)=>Math.hypot((a[0]-b[0])*111320*Math.cos(compact[2]/1e7*Math.PI/180),
    (a[1]-b[1])*110574);
  assert.ok(distance(small[0],small[1])<distance(full[0],full[1])*.71);
  assert.ok(distance(small[0],small[3])<distance(full[0],full[3])*.80);
});
