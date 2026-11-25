import test from 'node:test';
import assert from 'node:assert/strict';
import {gzipSync} from 'node:zlib';
import {buildTaipei101Tower} from '../taipei101-tower.js';
import {SurveyLayer} from '../survey-layer.js';

const ground=4.939998465560478;
const mesh=buildTaipei101Tower(ground);
const triangleCount=mesh.length/18;
const near=(a,b)=>Math.abs(a-b)<.001;

test('the eight-tier exterior is closed and aligned to the survey ground',()=>{
  assert.equal(mesh.length%18,0);
  assert.ok(triangleCount<=3520,'the authored model should fit the old triangle budget');
  assert.ok(mesh.every(Number.isFinite));
  const detail=new Set([0x78aa9c,0x8db8a8,0x537f74,0x729f91,0xcfad64]);
  const edges=new Map(),cornices=new Set(),medals=new Set(),horizontal=new Map();
  let minZ=Infinity,maxZ=-Infinity;
  for(let i=0;i<mesh.length;i+=18){
    const points=[0,6,12].map(j=>Array.from(mesh.subarray(i+j,i+j+3)));
    const [a,b,c]=points;
    const u=b.map((v,j)=>v-a[j]),v=c.map((x,j)=>x-a[j]);
    assert.ok(Math.hypot(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])>1e-5);
    const color=mesh[i+5]-2;
    const z=a[2]-ground;
    for(const j of [0,6,12]){
      assert.ok(near(mesh[i+j+3],ground));
      assert.equal(mesh[i+j+4],508);
      assert.equal(mesh[i+j+5],color+2);
    }
    minZ=Math.min(minZ,...points.map(p=>p[2]));
    maxZ=Math.max(maxZ,...points.map(p=>p[2]));
    if(color===0xcfad64){
      assert.ok(points.every(p=>p[2]-ground>111&&p[2]-ground<119));
      medals.add(a.slice(0,2).join('/'));
    }
    if(detail.has(color))continue;
    if(points.every(p=>near(p[2],a[2]))){
      const signs=horizontal.get(a[2])??new Set();
      signs.add(Math.sign(u[0]*v[1]-u[1]*v[0]));
      horizontal.set(a[2],signs);
    }
    if(color===0xbcc7aa){
      for(let tier=0;tier<8;tier++){
        if(near(z,149.4+tier*33.4))cornices.add(tier);
      }
    }
    for(let j=0;j<3;j++){
      const x=points[j].join(','),y=points[(j+1)%3].join(',');
      const key=[x,y].sort().join('/');
      const entry=edges.get(key)??[0,0];
      entry[0]++;
      entry[1]+=x<y?1:-1;
      edges.set(key,entry);
    }
  }
  assert.ok(near(minZ,ground-.3)&&near(maxZ,ground+508));
  assert.equal(cornices.size,8);
  assert.equal(medals.size,4);
  for(const [z,signs] of horizontal)assert.equal(signs.size,1,`overlapping setback at elevation ${z}`);
  for(const [count,winding] of edges.values())assert.deepEqual([count,winding],[2,0]);
});

test('the normal map draws the same authored tower at both survey detail levels',async t=>{
  const center=[121.56480926832859,25.03366957841625];
  const anchor={mx:.8376800257453572,my:.42813775317984215,m:2.754036392361926e-8,
    box:[121.5644,25.0332,121.5652,25.034],lngLat:center};
  const tower={...anchor,id:'101',source:{min:ground},verts:10560};
  const coarse={...anchor,id:'coarse',verts:3},fine={...anchor,id:'fine',verts:3};
  const requests=[],draws=[],noop=()=>{};
  let zoom=15.5;
  const gl=new Proxy({
    getUniformLocation:(_,name)=>name,getShaderParameter:()=>true,getProgramParameter:()=>true,
    drawArrays:(_,offset,count)=>draws.push(count),
  },{get:(target,name)=>target[name]??noop});
  const map={triggerRepaint:noop,getZoom:()=>zoom,getCenter:()=>({lng:center[0],lat:center[1]}),
    getBounds:()=>({toArray:()=>[[121.5644,25.0332],[121.5652,25.034]]})};
  const bytes=gzipSync(new Uint8Array(72));
  t.mock.method(globalThis,'fetch',async url=>{
    requests.push(new URL(url).pathname);
    return new Response(bytes);
  });
  const layer=new SurveyLayer({levels:{1000:[coarse],200:[fine]}},noop,tower,true,[],null,null,true);
  const options={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  async function settle(){
    for(let i=0;i<100;i++){
      draws.length=0;
      layer.render(gl,options);
      if(layer.diagnostics.live===0)return;
      await new Promise(resolve=>setImmediate(resolve));
    }
    assert.fail('survey tiles did not settle');
  }
  layer.onAdd(map,gl);
  try{
    await settle();
    assert.equal(layer.diagnostics.mode,1000);
    assert.deepEqual(draws,[3,mesh.length/6]);
    zoom=18.05;
    await settle();
    assert.equal(layer.diagnostics.mode,200);
    assert.deepEqual(draws,[3,mesh.length/6]);
    assert.equal(layer.diagnostics.triangles,1+triangleCount);
    assert.equal(requests.some(p=>p.endsWith('/landmark/101.bin.gz')),false);
    assert.equal(layer.diagnostics.failed,0);
  }finally{
    layer.onRemove();
  }
});
