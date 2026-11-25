import assert from 'node:assert/strict';
import test from 'node:test';
import bins,{pedestrianBinSnapshot as snapshot} from '../city170-pedestrian-bin-points.js';
import {drawPedestrianBin} from '../taipei-pedestrian-bin-mesh.js';

test('packaged Taipei bins retain the checked municipal coordinates',()=>{
  const used=new Set();
  for(const [pack,objects] of Object.entries(bins)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [key,[lon,lat,kind,size,angle,variant]] of Object.entries(objects)){
      assert.ok(lon>=121.4&&lon<=121.7&&lat>=24.9&&lat<=25.25);
      assert.equal(key,`pedestrian-bin/${Math.round(lon*1e7)}/${Math.round(lat*1e7)}`);
      assert.equal(kind,'pedestrian-bin');
      assert.equal(size,1);
      assert.equal(variant,0);
      assert.ok(Number.isInteger(angle)&&angle>=0&&angle<360);
      assert.ok(!used.has(key));
      used.add(key);
    }
  }
  assert.equal(used.size,snapshot.total);
  for(const key of ['1215153570/250336710','1215900290/250690980']){
    assert.ok(!used.has('pedestrian-bin/'+key),'Keep existing pedestrian animation routes clear');
  }
  assert.equal(used.size,136);
  assert.equal(Object.values(snapshot.districts).reduce((total,n)=>total+n,0),used.size);
  assert.equal(Object.values(snapshot.exclusions).reduce((total,n)=>total+n,used.size),661);
});

test('the new bin fits below one metre and within the validated clearance',()=>{
  const rectangle=(x,y,z,w,d,h)=>{
    assert.ok(Math.hypot(Math.abs(x)+w/2,Math.abs(y)+d/2)<.43);
    assert.ok(z>=-.012&&z+h<=1);
  };
  const lid=([x,y,z],[w,d],levels)=>{
    assert.ok(Math.hypot(Math.abs(x)+w,Math.abs(y)+d)<.43);
    for(const [height,scale] of levels)assert.ok(z+height<=1&&scale<=1);
  };
  drawPedestrianBin({box:rectangle,prism:lid});
});
