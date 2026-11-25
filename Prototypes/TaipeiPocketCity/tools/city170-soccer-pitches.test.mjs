import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {join} from 'node:path';
import {courtDetails} from '../city170-courts.js';
import {surfaceFeature} from '../city170-ground.js';

const make=(ring,props={})=>({id:'pitch/way/example',properties:{kind:'pitch',category:'pitch',sport:'soccer',...props},
  geometry:{type:'Polygon',coordinates:[ring]}});
const ll=[121.5525,25.0742],east=111320*Math.cos(ll[1]*Math.PI/180),north=110574;
function rotatedField(length,width,angle){
  const cos=Math.cos(angle),sin=Math.sin(angle);
  const point=([x,y])=>[ll[0]+(cos*x-sin*y)/east,ll[1]+(sin*x+cos*y)/north];
  const local=([lon,lat])=>{
    const x=(lon-ll[0])*east,y=(lat-ll[1])*north;
    return [cos*x+sin*y,-sin*x+cos*y];
  };
  return {ring:[[0,0],[length,0],[length,width],[0,width],[0,0]].map(point),local};
}
const approx=(actual,target,tolerance=.015)=>assert.ok(Math.abs(actual-target)<tolerance,`${actual} ≠ ${target}`);
function extent(points){
  return [Math.min(...points.map(p=>p[0])),Math.min(...points.map(p=>p[1])),
    Math.max(...points.map(p=>p[0])),Math.max(...points.map(p=>p[1]))];
}

test('IFAB markings and ground-supported goals follow either long axis, ring origin and winding',()=>{
  for(const angle of [.21,1.73]){
    const {ring,local}=rotatedField(108.3,70.5,angle);
    for(const reverse of [false,true])for(let start=0;start<4;start++){
      const corners=ring.slice(0,4);
      if(reverse)corners.reverse();
      const reordered=[...corners.slice(start),...corners.slice(0,start)];
      const pitch=make([...reordered,reordered[0]]);
      const [paint,...parts]=courtDetails(pitch,true);
      assert.deepEqual(courtDetails(pitch),[paint]);
      const lines=paint.geometry.coordinates.map(line=>line.map(local));
      const [x0,y0,x1,y1]=extent(lines[0]);
      approx(x1-x0,105);approx(y1-y0,68);
      const centre=[54.15,35.25];
      for(const p of lines[1])approx(p[0],centre[0]);
      for(const [x,y] of lines[2])approx(Math.hypot(x-centre[0],y-centre[1]),9.15);
      for(const index of [4,10]){
        const small=extent(lines[index]),big=extent(lines[index+1]);
        approx(small[2]-small[0],5.5);approx(small[3]-small[1],18.32);
        approx(big[2]-big[0],16.5);approx(big[3]-big[1],40.32);
        const penalty=lines[index+2],spot=penalty.reduce(([a,b],[x,y])=>[a+x/2,b+y/2],[0,0]);
        approx(Math.min(spot[0]-x0,x1-spot[0]),11);
        for(const [x,y] of lines[index+3])approx(Math.hypot(x-spot[0],y-spot[1]),9.15);
      }
      for(const [x,y] of lines.flat()){
        assert.ok(x>=x0-.001&&x<=x1+.001&&y>=y0-.001&&y<=y1+.001);
      }
      assert.equal(parts.length,6);
      for(const end of ['0','1']){
        const pair=parts.filter(f=>f.id.includes('/'+end+'-post'));
        const bar=parts.find(f=>f.id.endsWith('/'+end+'-crossbar'));
        const posts=pair.map(f=>extent(f.geometry.coordinates[0].map(local))).sort((a,b)=>a[1]-b[1]);
        approx(posts[1][1]-posts[0][3],7.32);
        assert.ok(pair.every(f=>f.properties.base===0&&f.properties.top===2.56));
        assert.equal(bar.properties.base,2.44);
        for(const p of bar.geometry.coordinates[0].map(local)){
          assert.ok(p[0]>0&&p[0]<108.3&&p[1]>0&&p[1]<70.5);
        }
      }
    }
  }
});

test('small-sided fields, multi-sport venues and off-ground or uncertain pitch shapes get no adult layout',()=>{
  const {ring}=rotatedField(105,68,0);
  for(const props of [{sport:'futsal'},{sport:'soccer;basketball'},{category:'sports_centre'},{offGround:true},
    {bridge:'yes'},{tunnel:'yes'},{indoor:'yes'},{covered:'yes'},{level:'1'},{layer:'2'},
    {location:'roof'},{surface:'asphalt'}])assert.deepEqual(courtDetails(make(ring,props),true),[]);
  for(const [l,w] of [[55,35],[90,52],[205,69],[105,140],[105,86]]){
    assert.deepEqual(courtDetails(make(rotatedField(l,w,0).ring),true),[]);
  }
  const skew=ring.map(p=>p.slice());skew[2][0]+=.00008;
  assert.deepEqual(courtDetails(make(skew),true),[]);
  assert.deepEqual(courtDetails(make(ring.slice(0,4)),true),[]);
  const hole=make(ring);hole.geometry.coordinates.push(ring);assert.deepEqual(courtDetails(hole,true),[]);
});

const data=process.env.POCKET_TAIPEI_DATA;
test('the restored Yingfeng pitch keeps its original turf footprint and gets a centred 105 by 68 m layout',{skip:!data},()=>{
  const pack=JSON.parse(gunzipSync(readFileSync(join(data,'city170/p224_2039.json.gz'))));
  const pitch=surfaceFeature(pack.features.features.find(f=>f.id==='pitch/way/596345093'));
  assert.equal(pitch.properties.name,'迎風足球場');
  const original=structuredClone(pitch);
  const [paint,...parts]=courtDetails(pitch,true);
  assert.deepEqual(pitch,original);assert.equal(parts.length,6);
  const perimeter=paint.geometry.coordinates[0];
  const edge=(a,b)=>Math.hypot((a[0]-b[0])*east,(a[1]-b[1])*north);
  approx(edge(perimeter[0],perimeter[1]),105,.08);
  approx(edge(perimeter[1],perimeter[2]),68,.08);
});

test('the atlas equipment source sends unsimplified post footprints to the tile worker',async()=>{
  const {addCity170}=await import('../city170.js');
  const {GeoJSONSource}=await import('../assets/maplibre-gl.mjs');
  const stop=new Error('captured source');
  let options;
  const map={addSource(id,spec){
    if(id==='city170-equipment'){
      options=new GeoJSONSource(id,spec,{getActor:()=>({})},{}).workerOptions.geojsonVtOptions;
      throw stop;
    }
  }};
  assert.throws(()=>addCity170(map),err=>err===stop);
  assert.equal(options.tolerance,0);
  assert.ok(options.maxZoom>=19);
});
