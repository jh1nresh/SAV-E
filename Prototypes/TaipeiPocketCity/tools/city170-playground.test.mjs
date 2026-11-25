import assert from 'node:assert/strict';
import test from 'node:test';
import groups,{playgroundSnapshot as snapshot} from '../city170-playground-points.js';
import {drawPlaygroundObject} from '../taipei-playground-mesh.js';

test('mapped playground fittings stay inside their generator clearance',()=>{
  const radii={'play-tower':2.02,'play-slide':1.96,'play-swing':1.94,
    'play-sand':1.53,'play-climb':1.34,'play-rider':.54};
  for(const [kind,radius] of Object.entries(radii)){
    const points=[];
    drawPlaygroundObject(kind,0,{
      box(x,y,z,w,d,h){for(const dx of [-w/2,w/2])for(const dy of [-d/2,d/2])points.push([x+dx,y+dy,z],[x+dx,y+dy,z+h]);},
      prism([x,y,z],[rx,ry],levels){for(const [height,scale] of levels)for(const dx of [-rx,rx])for(const dy of [-ry,ry])
        points.push([x+dx*scale,y+dy*scale,z+height]);},
      face(vertices){points.push(...vertices);},
    });
    assert.ok(points.length>0,kind);
    assert.ok(points.some(([, ,z])=>z<=.03),kind);
    for(const [x,y,z] of points)assert.ok(Math.hypot(x,y)<radius&&z>=0&&z<=2.5,kind);
  }
});

test('the verified park inventory uses unique equipment IDs and only documented shapes',()=>{
  const ids=new Set(), counts={}, boundaries=new Set();
  for(const [pack,rows] of Object.entries(groups)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [id,[lon,lat,kind,size,angle,index]] of Object.entries(rows)){
      const prefix=id.split('/').slice(0,-1).join('/');
      assert.match(prefix,/^playground\/park\/(way|relation)\/\d+$/);
      assert.ok(!ids.has(id));
      ids.add(id);
      boundaries.add(prefix);
      counts[kind]=(counts[kind]??0)+1;
      assert.ok(lon>121.45&&lon<121.68&&lat>24.95&&lat<25.22);
      assert.equal(size,1);
      assert.ok(angle>=0&&angle<180&&Number.isInteger(index)&&index>=0&&index<4);
    }
  }
  assert.deepEqual(counts,snapshot.equipment);
  assert.equal(boundaries.size,snapshot.mappedPlaygrounds);
  assert.equal(ids.size,Object.values(snapshot.districts).reduce((a,b)=>a+b,0));
});
