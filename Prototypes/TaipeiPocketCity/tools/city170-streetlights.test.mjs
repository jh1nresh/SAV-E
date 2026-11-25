import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';

import {loadStreetlightPacks,streetlightObjects} from '../taipei-streetlight-data.js';
import {drawStreetlight} from '../taipei-streetlight-mesh.js';

const encoded=readFileSync(new URL('../assets/taipei-streetlights.json.gz',import.meta.url));
const inventory=JSON.parse(gunzipSync(encoded));

test('the public batch has one above-ground pole per source position across all districts',()=>{
  const {packs,receipt}=inventory;
  const seen=new Set();
  const counts={road:0,path:0};
  for(const [key,rows] of Object.entries(packs)){
    assert.match(key,/^p\d+_\d+$/);
    for(const [x,y,height,bearing,style] of rows){
      assert.ok([x,y,height,bearing,style].every(Number.isInteger));
      assert.ok(x>=1214000000&&x<=1217000000&&y>=249000000&&y<=252500000);
      assert.ok(height>=240&&height<=1400&&bearing>=0&&bearing<360);
      assert.ok(style>=0&&style<=3);
      assert.ok(style>=2?height<=600&&bearing===0:height>=450);
      counts[style<2?'road':'path']++;
      assert.ok(!seen.has(x+'/'+y));
      seen.add(x+'/'+y);
    }
  }
  assert.equal(seen.size,45705);
  assert.equal(receipt.total,seen.size);
  assert.equal(Object.keys(receipt.districts).length,12);
  assert.equal(Object.values(receipt.districts).reduce((total,count)=>total+count,0),seen.size);
  const {inventory:inventoryCount,...excluded}=receipt.sourceCounts;
  assert.equal(Object.values(excluded).reduce((total,count)=>total+count,seen.size),inventoryCount);
  assert.deepEqual(counts,receipt.types);
  assert.equal(receipt.snapshot,'2025-10-25 06:59:32');
  assert.ok(encoded.byteLength<480000);
});

test('load the packaged compressed asset at background priority and retain row coordinates and height',async t=>{
  const fetch=globalThis.fetch;
  const requests=[];
  globalThis.fetch=async (url,options)=>{
    requests.push([url.pathname,options.priority]);
    return new Response(encoded);
  };
  t.after(()=>{globalThis.fetch=fetch;});
  const packs=await loadStreetlightPacks();
  assert.equal(requests.length,1);
  assert.match(requests[0][0],/assets\/taipei-streetlights\.json\.gz$/);
  assert.equal(requests[0][1],'low');
  for(const [key,rows] of Object.entries(packs)){
    const [first]=rows;
    const objects=streetlightObjects(rows);
    const [east,north,height,angle,style]=first;
    assert.equal(Object.keys(objects).length,rows.length,key);
    assert.deepEqual(objects['streetlight/'+east+'/'+north],
      [east/1e7,north/1e7,'street-light',height/100,angle,style]);
  }
});

test('all four pole variants remain within their checked ground envelope',()=>{
  for(const style of [0,1,2,3]){
    const pieces=[],arms=[],tops=[];
    const box=(x,y,z,width,depth,height,color)=>{
      const far=Math.hypot(Math.abs(x)+width/2,Math.abs(y)+depth/2);
      assert.ok(far<=(style<2 ? .18 : .1));
      assert.ok(z>=-.006&&z+height<=1);
      if(z===.960||(z===.944&&color==='#464f4b'))arms.push(x);
      tops.push(z+height);
      pieces.push(color);
    };
    const prism=(center,radius,levels,sides)=>{
      assert.deepEqual(center,[0,0,0]);
      assert.ok(radius.every(r=>r<.04)&&sides===5);
      assert.ok(levels[0][0]<0&&levels.at(-1)[0]>.95);
    };
    drawStreetlight(style,{box,prism});
    assert.equal(arms.length,style%2+1);
    assert.equal(Math.max(...tops),1);
    assert.ok(pieces.includes('#f4ddab'));
  }
});
