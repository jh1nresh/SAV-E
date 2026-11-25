import assert from 'node:assert/strict';
import test from 'node:test';

import groups,{bikeRackSnapshot as snapshot} from '../city170-bike-rack-points.js';
import {drawBicycleRack} from '../taipei-bike-rack-mesh.js';

const sizes={'bike-wheel-rack':[.81,.29,.33],'bike-frame-stand':[.46,.12,.83]};

test('rack art sits on the ground and stays inside the checked placement envelopes',()=>{
  for(const [kind,[width,depth,top]] of Object.entries(sizes)){
    const positions=[];
    drawBicycleRack(kind,{
      box(x,y,z,w,d,h){
        for(const dx of [-w/2,w/2])for(const dy of [-d/2,d/2]){
          positions.push([x+dx,y+dy,z],[x+dx,y+dy,z+h]);
        }
      },
      face(vertices){positions.push(...vertices);},
    });
    assert(positions.some(([, ,z])=>z<=-.13));
    assert(positions.some(([, ,z])=>z>=top-.014));
    assert(positions.every(([x,y,z])=>Math.abs(x)<=width&&Math.abs(y)<=depth&&z>=-.17&&z<=top));
  }
});

test('all rack placements use unique OSM IDs and reconcile with checked sites',()=>{
  const ids=new Set(), kinds={};
  for(const [pack,rows] of Object.entries(groups)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [id,[lon,lat,kind,scale,heading]] of Object.entries(rows)){
      assert.match(id,/^bike-parking\/(node|way)\/\d+$/);
      assert(!ids.has(id));
      assert(lon>121.45&&lon<121.68&&lat>24.95&&lat<25.22);
      assert(scale===1&&Number.isInteger(heading)&&heading>=0&&heading<180);
      assert(Object.hasOwn(sizes,kind));
      kinds[kind]=(kinds[kind]??0)+1;
      ids.add(id);
    }
  }
  assert.deepEqual(kinds,snapshot.kinds);
  assert.equal(ids.size,snapshot.illustratedSites);
  assert.equal(Object.values(snapshot.districts).reduce((a,b)=>a+b,0),ids.size);
  assert.equal(Object.values(snapshot.exclusions).reduce((a,b)=>a+b,ids.size),snapshot.documentedOutdoorSites);
});
