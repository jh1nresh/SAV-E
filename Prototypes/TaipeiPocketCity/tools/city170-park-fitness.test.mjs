import assert from 'node:assert/strict';
import test from 'node:test';
import groups,{fitnessSnapshot as snapshot} from '../city170-park-fitness-points.js';
import {drawParkFitness} from '../taipei-park-fitness-mesh.js';

const clearance={
  'fitness-ladder':1.27,'fitness-parallel':1.04,'fitness-pullup':.98,'fitness-twister':.98,
  'fitness-bench':.95,'fitness-wheel':.89,'fitness-ski':.88,'fitness-walker':.87,
  'fitness-rower':.87,'fitness-pull':.83,'fitness-back':.69,'fitness-shoulder':.65,
};

test('all park exercise models touch ground and fit inside their placement clearances',()=>{
  for(const [kind,radius] of Object.entries(clearance)){
    const points=[];
    drawParkFitness(kind,0,{
      box(x,y,z,w,d,h){
        for(const dx of [-w/2,w/2])for(const dy of [-d/2,d/2])points.push([x+dx,y+dy,z],[x+dx,y+dy,z+h]);
      },
      prism([x,y,z],[rx,ry],levels,sides,_,phase=0){
        for(const [height,scale] of levels){
          for(let i=0;i<sides;i++){
            const angle=2*Math.PI*i/sides+phase;
            points.push([x+rx*Math.cos(angle)*scale,y+ry*Math.sin(angle)*scale,z+height]);
          }
        }
      },
      face(vertices){points.push(...vertices);},
    });
    assert.ok(points.some(([, ,z])=>z<.01),kind);
    for(const [x,y,z] of points)assert.ok(Math.hypot(x,y)<radius&&z>=0&&z<=2.3,`${kind}: ${[x,y,z]}`);
  }
});

test('mapped fitness equipment IDs, cells and district counts reconcile to the city snapshot',()=>{
  const objects=new Set(), parks=new Set(), kinds={};
  for(const [pack,rows] of Object.entries(groups)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [id,[lon,lat,kind,size,angle,index]] of Object.entries(rows)){
      assert.match(id,/^fitness\/park\/(way|relation)\/\d+\/\d+$/);
      assert.ok(!objects.has(id));
      objects.add(id);
      parks.add(id.slice(0,id.lastIndexOf('/')));
      kinds[kind]=(kinds[kind]??0)+1;
      assert.ok(lon>121.45&&lon<121.68&&lat>24.95&&lat<25.22);
      assert.equal(size,1);
      assert.ok(Number.isInteger(angle)&&angle>=0&&angle<180);
      assert.ok(Number.isInteger(index)&&index>=0&&index<4);
    }
  }
  assert.deepEqual(Object.keys(kinds).sort(),Object.keys(clearance).sort());
  assert.deepEqual(kinds,snapshot.equipment);
  assert.equal(parks.size,snapshot.mappedParks);
  assert.equal(Object.keys(snapshot.districts).length,12);
  assert.equal(objects.size,Object.values(snapshot.districts).reduce((sum,n)=>sum+n,0));
  assert.ok(snapshot.renderedSites<=snapshot.uniqueSites);
});

test('the Wenshan fitness cluster avoids the animated route through its park',()=>{
  // city170-life/p224_2033, route 0aa959f7891e8733d25a. Figures carry umbrellas in rain.
  const route=[[121.54776495,24.99977407],[121.54773904,24.99980350],
    [121.54729102,25.00037370],[121.54724959,25.00037008]];
  const local=([lon,lat])=>[(lon-route[0][0])*100950,(lat-route[0][1])*110780];
  const points=route.map(local);
  for(const [id,row] of Object.entries(groups.p224_2033??{})){
    if(!id.startsWith('fitness/park/way/222081021/'))continue;
    const [x,y]=local(row);
    for(let i=1;i<points.length;i++){
      const [a,b]=points[i-1], dx=points[i][0]-a, dy=points[i][1]-b;
      const t=Math.min(1,Math.max(0,((x-a)*dx+(y-b)*dy)/(dx*dx+dy*dy)));
      assert.ok(Math.hypot(x-a-t*dx,y-b-t*dy)>=clearance[row[2]]+1.29,id);
    }
  }
});
