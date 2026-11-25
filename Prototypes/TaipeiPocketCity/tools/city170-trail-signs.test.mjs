import assert from 'node:assert/strict';
import test from 'node:test';

import packs,{trailSignSnapshot as snapshot} from '../city170-trail-sign-points.js';
import {drawTrailGuidepost} from '../taipei-trail-sign-mesh.js';

test('guidepost details fit the clearance envelope and the foot penetrates the terrain',()=>{
  const vertices=[];
  const boards=[];
  drawTrailGuidepost({
    box(x,y,z,w,d,h){
      for(const dx of [-w/2,w/2])for(const dy of [-d/2,d/2]){
        vertices.push([x+dx,y+dy,z],[x+dx,y+dy,z+h]);
      }
      if(w>.8&&h>.175)boards.push(z);
    },
  });
  assert.equal(boards.length,2);
  assert(vertices.some(([, ,z])=>z<-.25));
  assert(vertices.some(([, ,z])=>z>2));
  assert(vertices.every(([x,y,z])=>Math.hypot(x,y)<=.64&&z>=-.26&&z<=2.01));
});

test('unique guideposts, offsets and coverage reconcile to the frozen OSM scan',()=>{
  const seen=new Set();
  for(const [pack,rows] of Object.entries(packs)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [id,[lon,lat,kind,scale,heading]] of Object.entries(rows)){
      assert.match(id,/^trail-sign\/node\/\d+$/);
      assert(!seen.has(id));
      assert(lon>121.45&&lon<121.68&&lat>24.95&&lat<25.22);
      assert(kind==='trail-guidepost'&&scale===1);
      assert(Number.isInteger(heading)&&heading>=0&&heading<180);
      seen.add(id);
    }
  }
  const total=(a,b)=>a+b;
  assert.equal(seen.size,snapshot.illustrated);
  assert.equal(Object.values(snapshot.districts).reduce(total,0),seen.size);
  assert.equal(Object.values(snapshot.exclusions).reduce(total,seen.size),snapshot.sourceGuideposts);
  assert(snapshot.shiftedWithinVerge<=seen.size&&snapshot.maxOffsetMetres<=2.25);
});
