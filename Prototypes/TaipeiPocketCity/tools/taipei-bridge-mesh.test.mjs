import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {bridgeMesh} from '../taipei-bridge-mesh.js';

const identity=(x,y)=>[x,y];
const span=(line,width=8)=>({id:'test',line,width});
const flat=()=>0;
const approx=(actual,target,tolerance=.001)=>assert.ok(Math.abs(actual-target)<tolerance,`${actual} ≠ ${target}`);
function vertices(mesh){
  assert.ok(mesh.length>0&&mesh.length%18===0);
  const vertices=[];
  for(let i=0;i<mesh.length;i+=6){
    const v=Array.from(mesh.slice(i,i+6));
    assert.ok(v.every(Number.isFinite));
    assert.ok(v.slice(3).every(x=>x>=0&&x<=1));
    vertices.push(v);
  }
  for(let i=0;i<vertices.length;i+=3){
    const [a,b,c]=vertices.slice(i,i+3);
    const x=b[0]-a[0],y=b[1]-a[1],z=b[2]-a[2],u=c[0]-a[0],v=c[1]-a[1],w=c[2]-a[2];
    assert.ok(Math.hypot(y*w-z*v,z*u-x*w,x*v-y*u)>1e-7,'degenerate triangle');
  }
  return vertices;
}
const road=v=>Math.abs(v[3]-146/255)<1e-6;
const unique=values=>new Set(values.map(v=>v.map(c=>Math.round(c*1000)||0).join(',')));

test('retains measured width and brings the full cross-section down to both sloping landings',()=>{
  const ground=(x,y)=>9+.043*x+.13*y+.018*y*y;
  const mesh=vertices(bridgeMesh(span([[0,0],[120,0]],10),identity,ground));
  assert.ok(mesh.some(road));assert.equal(new Set(mesh.map(v=>v[3])).size,4);
  for(const x of [0,120])for(const y of [-5,0,5]){
    const landing=mesh.filter(v=>Math.abs(v[0]-x)<.0001&&Math.abs(v[1]-y)<.0001);
    assert.ok(landing.length);
    for(const v of landing)approx(v[2],ground(x,y));
  }
  approx(Math.max(...mesh.map(v=>v[1]))-Math.min(...mesh.map(v=>v[1])),10);
  const middle=mesh.filter(v=>Math.abs(v[0]-60)<.001&&Math.abs(v[1])<.001&&road(v));
  assert.ok(middle.length);approx(middle[0][2]-ground(60,0),3.9);
  assert.ok(Math.max(...mesh.filter(v=>Math.abs(v[0]-60)<.001).map(v=>v[2]))<ground(60,5)+4.6);
});

test('rise is gentle on short spans, smooth across a hill and bounded on long flat spans',()=>{
  const ground=x=>6+x*.04+1.7*Math.exp(-((x-65)**2)/170);
  for(const [length,dem] of [[14,flat],[130,ground],[420,flat]]){
    const mesh=vertices(bridgeMesh(span([[0,0],[length,0]]),identity,dem));
    const profile=[...new Map(mesh.filter(v=>road(v)&&Math.abs(v[1])<.001).map(v=>[v[0],v])).values()]
      .sort((a,b)=>a[0]-b[0]);
    for(let i=1;i<profile.length;i++){
      const [x,,z]=profile[i],prev=profile[i-1];
      assert.ok(z>=dem(x)-.001);
      assert.ok(Math.abs((z-prev[2])/(x-prev[0]))<.27);
    }
    const maxRise=Math.max(...profile.map(([x,,z])=>z-dem(x)));
    if(length===14)assert.ok(maxRise>.15&&maxRise<.5);
    if(length===420)approx(maxRise,5.2);
  }
});

test('a missing centre or shoulder DEM, an impossible landing or unusable line leaves the base map visible',()=>{
  const road=span([[0,0],[60,0]]);
  for(const [x,y] of [[0,0],[0,-4],[60,4],[30,4],[30,0]]){
    assert.deepEqual(bridgeMesh(road,identity,(a,b)=>Math.abs(a-x)<.001&&Math.abs(b-y)<.001?null:3),[]);
  }
  assert.deepEqual(bridgeMesh(road,identity,x=>x>3&&x<9?30:0),[]);
  assert.deepEqual(bridgeMesh(road,()=>[2,2],flat),[]);
  assert.deepEqual(bridgeMesh(span([[0,0],[NaN,1]]),identity,flat),[]);
  assert.deepEqual(bridgeMesh(span([[0,0],[30,0],[0,0]]),identity,flat),[]);
  assert.deepEqual(bridgeMesh(span([[0,0],[1,2]],0),identity,flat),[]);
});

test('the curved Xinyi entrance ramp has joined edges, independent of digitisation direction and rotation',()=>{
  const rows=JSON.parse(gunzipSync(readFileSync(new URL('../assets/taipei-road-bridges.json.gz',import.meta.url))));
  const ramp=rows.find(row=>row.id==='road/way/138265874');
  assert.equal(ramp.name,'信義路入口匝道');assert.equal(ramp.width,7);assert.equal(ramp.line.length,17);
  const project=(lon,lat)=>[(lon-121.572)*100910,(lat-25.0324)*110770];
  const ground=(lon,lat)=>{const [x,y]=project(lon,lat);return 12+.035*x-.05*y;};
  const mesh=vertices(bridgeMesh(ramp,project,ground));
  const reverse=vertices(bridgeMesh({...ramp,line:ramp.line.toReversed()},project,ground));
  assert.deepEqual(unique(mesh),unique(reverse));
  const rotated=(lon,lat)=>{const [x,y]=project(lon,lat);return [y,-x];};
  const quarterTurn=vertices(bridgeMesh(ramp,rotated,ground));
  assert.deepEqual(unique(mesh),unique(quarterTurn.map(([x,y,...v])=>[-y,x,...v])));
  // A joint lies exactly half the mapped road width from both adjoining segment axes.
  const xy=ramp.line.map(p=>project(...p));
  for(let i=1;i<xy.length-1;i++){
    const [x,y]=xy[i];
    const normals=[xy[i-1],xy[i+1]].map(([px,py])=>{
      const len=Math.hypot(px-x,py-y);return [(py-y)/len,(x-px)/len];
    });
    const candidates=mesh.filter(v=>Math.hypot(v[0]-x,v[1]-y)<ramp.width);
    assert.ok(candidates.some(([a,b])=>normals.every(([nx,ny])=>
      Math.abs(Math.abs((a-x)*nx+(b-y)*ny)-ramp.width/2)<.001)));
  }
});
