import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gzipSync,gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {SurveyLayer} from '../survey-layer.js';
import {taipei101Exterior,taipei101Ink} from '../taipei101-exterior.js';
import {registerScene} from './register-taipei101-mesh.mjs';

const ground=4.939998465560478;
const packed=readFileSync(taipei101Exterior.mesh);
const original=gunzipSync(readFileSync(new URL('./fixtures/taipei101-pocket-city.html.gz',import.meta.url)));

test('the full registered mesh reproduces every original building group and every RGB',()=>{
  assert.equal(createHash('sha256').update(original).digest('hex'),'7255df7e18ddd8a0863463b0ae0ad94a624f23ffef24c8aab79a32ae8083f8e2');
  const {data,parts,inkData,solidVerts}=registerScene(original.toString());
  assert.deepEqual(gunzipSync(packed),data);
  assert.equal(data.length,taipei101Exterior.verts*24);
  assert.deepEqual(parts.map(p=>p.count),[3360,138,90,126,1752,8160,222,222,288,174,174]);
  assert.equal(solidVerts,taipei101Ink.solidVerts);
  assert.equal(solidVerts,14706);
  assert.deepEqual(inkData,gunzipSync(readFileSync(taipei101Ink.mesh)));
  assert.equal(inkData.length,taipei101Ink.segments*32);
  // Every original (#456) triangle is available for offline/failure fallback.
  const allTriangles=[];
  for(let i=0;i<data.length;i+=72)allTriangles.push(data.subarray(i,i+72));
  assert.equal(createHash('sha256').update(Buffer.concat(allTriangles.sort(Buffer.compare))).digest('hex'),
    'a4c8dcecdacba0e6ce5467236833fdb242e218279b4506a4dcb234d743bd706f');
  const [tower,mall,...entrances]=parts.slice(4);
  assert.equal(tower.name,'台北 101 塔樓');
  assert.equal(mall.name,'台北 101 購物中心');
  assert.ok(entrances.every(p=>p.name==='入口雨棚'));
  const levels=new Set(),colors=new Set();
  let tip;
  for(let i=0;i<data.length;i+=24){
    const x=data.readFloatLE(i),y=data.readFloatLE(i+4),absolute=data.readFloatLE(i+8),base=data.readFloatLE(i+12);
    assert.ok(Number.isFinite(x+y+absolute+base)&&Math.abs(x)<108&&Math.abs(y)<110);
    if(i/24<tower.first||i/24>=tower.first+tower.count)continue;
    const z=absolute-base;
    if(z>507.99)tip=[x,y,z];
    levels.add(Math.round(z*10));
    colors.add(data.readFloatLE(i+20)-2);
  }
  assert.ok(Math.hypot(tip[0]-.05428,tip[1]+.14817)<.001);
  assert.ok(Math.abs(tip[2]-508)<.001);
  for(let tier=0;tier<8;tier++)assert.ok(levels.has(Math.round((149.4+tier*33.4)*10)));
  for(const rgb of [0xd4c0a0,0x6aa89a,0x578f84,0xcfad64])assert.ok(colors.has(rgb));
  assert.equal(mall.firstInk,taipei101Ink.mallFirst);
  assert.equal(mall.inkCount,taipei101Ink.mallCount);
  assert.deepEqual([tower.firstInk,tower.inkCount],[69,1920]);
  const outlineWidth=Math.fround(.8*.83);
  const counts=new Map(),seen=new Set(),outlines=new Set();
  for(let i=tower.firstInk;i<tower.firstInk+tower.inkCount;i++){
    const [ax,ay,az,bx,by,bz,rgb,width]=Array.from({length:8},(_,k)=>inkData.readFloatLE(i*32+k*4));
    const a=[ax,ay,az],b=[bx,by,bz];
    assert.ok([...a,...b].every(Number.isFinite));
    const key=[a.join(','),b.join(',')].sort().join('/');
    assert.notEqual(a.join(','),b.join(','));
    assert.ok(!seen.has(key),'shared ink edge was exported more than once');
    seen.add(key);
    if(width===outlineWidth)outlines.add(rgb);
    const style=width===outlineWidth?'outline':rgb.toString(16)+'/'+(-width).toFixed(2);
    counts.set(style,(counts.get(style)??0)+1);
  }
  // Original compileInk uses lineOf(fill) for all visible shape boundaries.
  // Its explicit style= strokes carry the mullions' projection-unit widths.
  assert.ok(outlines.has(0x838380)&&outlines.has(0x58616d));
  assert.deepEqual(Object.fromEntries(counts),{
    outline:640,'84b6a9/0.14':448,'b4d3bd/0.31':88,'719c8f/0.13':616,'466e66/0.27':128,
  });
});

test('the normal map draws the same authored tower at both survey detail levels',async t=>{
  const center=[121.56480926832859,25.03366957841625];
  const anchor={mx:.8376800257453572,my:.42813775317984215,m:2.754036392361926e-8,
    box:[121.5644,25.0332,121.5652,25.034],lngLat:center};
  const tower={...anchor,id:'101',source:{min:ground},verts:10560};
  const coarse={...anchor,id:'306_2769',verts:3},fine={...anchor,id:'1534_13848',verts:3};
  const requests=[],draws=[],modes=[],noop=()=>{};
  let zoom=15.5;
  const gl=new Proxy({
    getUniformLocation:(_,name)=>name,getShaderParameter:()=>true,getProgramParameter:()=>true,
    drawArrays:(_,offset,count)=>draws.push(count),
    uniform1i:(name,value)=>{if(name==='u_taipei101Mode')modes.push(value);},
  },{get:(target,name)=>target[name]??noop});
  const map={triggerRepaint:noop,getZoom:()=>zoom,getCenter:()=>({lng:center[0],lat:center[1]}),
    getBounds:()=>({toArray:()=>[[121.5644,25.0332],[121.5652,25.034]]})};
  const bytes=gzipSync(new Uint8Array(72));
  t.mock.method(globalThis,'fetch',async url=>{
    requests.push(new URL(url).pathname);
    return new Response(url.pathname.endsWith('/taipei101-pocket-city.bin.gz')?packed:bytes);
  });
  const layer=new SurveyLayer({levels:{1000:[coarse],200:[fine]}},noop,tower,true,[],null,null,true);
  const options={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  async function settle(){
    for(let i=0;i<100;i++){
      draws.length=0;modes.length=0;
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
    assert.deepEqual(draws,[3,taipei101Exterior.verts]);
    assert.deepEqual(modes,[1,2]);
    zoom=18.05;
    await settle();
    assert.equal(layer.diagnostics.mode,200);
    assert.deepEqual(draws,[3,taipei101Exterior.verts]);
    assert.deepEqual(modes,[1,2]);
    assert.equal(layer.diagnostics.triangles,1+taipei101Exterior.verts/3);
    assert.equal(requests.filter(p=>p.endsWith('/taipei101-pocket-city.bin.gz')).length,1);
    assert.equal(layer.diagnostics.failed,0);
  }finally{
    layer.onRemove();
  }
});


test('an incomplete survey anchor leaves the original survey tower visible',()=>{
  const layer=new SurveyLayer({levels:{200:[],1000:[]}},()=>{},
    {id:'101',source:{min:NaN}},true,[],null,null,true);
  assert.equal(layer.landmark,null);
});
