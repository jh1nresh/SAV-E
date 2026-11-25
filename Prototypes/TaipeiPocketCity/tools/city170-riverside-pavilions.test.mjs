import assert from 'node:assert/strict';
import test from 'node:test';
import groups,{riversidePavilionSnapshot as snapshot} from '../city170-riverside-pavilion-points.js';
import {drawRiversidePavilion} from '../taipei-riverside-pavilion-mesh.js';

const envelopes={
  'river-pavilion':[2.05,1.55,1.55,1.05],
  'river-canopy':[1.55,1.15,1.22,.78],
};

test('riverside roofs fit their tested clearance and four posts reach the terrain',()=>{
  for(const [kind,[width,depth,postX,postY]] of Object.entries(envelopes)){
    const points=[],feet=[];
    drawRiversidePavilion(kind,{
      box(x,y,z,w,d,h){
        if(z<0&&z+h>2)feet.push([x,y,z]);
        for(const dx of [-w/2,w/2])for(const dy of [-d/2,d/2])points.push([x+dx,y+dy,z],[x+dx,y+dy,z+h]);
      },
      face(vertices){points.push(...vertices);},
    });
    assert.deepEqual(feet,[-postX,postX].flatMap(x=>[-postY,postY].map(y=>[x,y,-.35])));
    assert(points.some(([, ,z])=>z>2.7));
    assert(points.every(([x,y,z])=>Math.abs(x)<=width&&Math.abs(y)<=depth&&z>=-.35&&z<3.4));
    assert(.35*.79>.26); // The compact model still reaches the lowest checked support.
  }
});

test('all riverside shelter IDs, placements and exclusions reconcile to the checked inventory',()=>{
  const seen=new Set();
  for(const [pack,rows] of Object.entries(groups)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [id,[lon,lat,kind,size,angle]] of Object.entries(rows)){
      assert.match(id,/^riverside-pavilion\/\d+$/);
      assert(!seen.has(id));
      assert(lon>121.45&&lon<121.68&&lat>24.95&&lat<25.22);
      assert(Object.hasOwn(envelopes,kind));
      assert(size===1||size===.79);
      assert(Number.isInteger(angle)&&angle>=0&&angle<180);
      seen.add(id);
    }
  }
  assert.equal(seen.size,snapshot.pavilions);
  for(const totals of [snapshot.districts,snapshot.rivers,snapshot.parks]){
    assert.equal(Object.values(totals).reduce((sum,n)=>sum+n,0),seen.size);
  }
  const skipped=Object.values(snapshot.exclusions).reduce((sum,n)=>sum+n,0);
  assert.equal(seen.size+skipped,snapshot.candidatePavilions);
});
