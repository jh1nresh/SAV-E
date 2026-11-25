import assert from 'node:assert/strict';
import test from 'node:test';
import postBoxes,{postBoxSnapshot} from '../city170-post-box-points.js';
import {drawPostBox} from '../taipei-post-box-mesh.js';

test('Taipei postal scenery keeps one verified point and supported style per cabinet',()=>{
  const keys=new Set();
  const counts={};
  for(const [pack,boxes] of Object.entries(postBoxes)){
    assert.match(pack,/^p\d+_\d+$/);
    for(const [key,[lon,lat,type,size,angle,slots]] of Object.entries(boxes)){
      assert.equal(key,`post-box/${Math.round(lon*1e7)}/${Math.round(lat*1e7)}`);
      assert.ok(!keys.has(key));
      keys.add(key);
      assert.ok(['post-box-ordinary','post-box-express'].includes(type));
      counts[type]=(counts[type]??0)+1;
      assert.equal(size,1);
      assert.ok(Number.isInteger(angle)&&angle>=0&&angle<360);
      assert.ok([1,2,4].includes(slots));
    }
  }
  assert.equal(keys.size,postBoxSnapshot.total);
  assert.deepEqual(counts,postBoxSnapshot.types);
  assert.equal(Object.keys(postBoxSnapshot.districts).length,12);
  assert.equal(Object.values(postBoxSnapshot.exclusions).reduce((sum,n)=>sum+n,keys.size),postBoxSnapshot.inventory);
});

test('all postal meshes remain inside the tested clearance and show the source slot count',()=>{
  for(const [type,enamel] of [['post-box-ordinary','#43866b'],['post-box-express','#c65549']]){
    for(const slots of [1,2,4]){
      const colors=[];
      const box=(x,y,z,w,d,h,color)=>{
        assert.ok(Math.hypot(Math.abs(x)+w/2,Math.abs(y)+d/2)<.43);
        assert.ok(z>=-.018&&z+h<=1.15);
        colors.push(color);
      };
      const prism=([x,y,z],[w,d],levels,sides,color,phase=0)=>{
        for(const [height,scale] of levels){
          assert.ok(z+height>=-.018&&z+height<=1.15);
          for(let i=0;i<sides;i++){
            const angle=phase+i*2*Math.PI/sides;
            assert.ok(Math.hypot(x+w*scale*Math.cos(angle),y+d*scale*Math.sin(angle))<.43);
          }
        }
        colors.push(color);
      };
      drawPostBox(type,slots,{box,prism});
      assert.ok(colors.includes(enamel));
      assert.equal(colors.filter(color=>color==='#483c33').length,slots);
    }
  }
});
