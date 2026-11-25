import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {gzipSync,gunzipSync} from 'node:zlib';
import {SurveyLayer} from '../survey-layer.js';
import {esliteSongyan as site,esliteSurveyTiles,esliteSurveyParts} from '../taipei-eslite-songyan.js';

const art=await readFile(site.mesh);
const triangles=gunzipSync(art);
const close=(a,b)=>Math.abs(a-b)<.0015;
test('the calibrated Eslite asset contains the stepped roof and full-height shop entry',()=>{
  assert.equal(triangles.length,site.verts*24);
  const heights=new Set(),colors=new Set();
  let min=Infinity,max=-Infinity;
  for(let offset=0;offset<triangles.length;offset+=72){
    const v=[0,24,48].map(n=>[0,4,8,12,16,20].map(i=>triangles.readFloatLE(offset+n+i)));
    assert.ok(v.flat().every(Number.isFinite));
    assert.ok(v.every(p=>close(p[3],site.ground)&&close(p[4],69.50983)&&p[5]===v[0][5]));
    assert.ok(v.every(p=>Math.abs(p[0])<100&&Math.abs(p[1])<55));
    min=Math.min(min,...v.map(p=>p[2]));max=Math.max(max,...v.map(p=>p[2]));
    if(v.every(p=>close(p[2],v[0][2])))heights.add(Math.round((v[0][2]-site.ground)*100)/100);
    colors.add(v[0][5]);
  }
  assert.ok(min<=site.ground+.001);
  assert.ok(close(max,site.ground+69.50983));
  for(const h of [6.43,12.27,17.13,21.30,25.31,29.39,33.56,41.90,46.07,49.97,54.28,58.78,69.51]){
    assert.ok(heights.has(h),`Missing cap at ${h} m`);
  }
  for(const color of [0x364947,0x83a29c,0xf0dfb7])assert.ok(colors.has(color+2));
});

test('the artwork replaces only its loaded survey tiles through a zoom transition',async t=>{
  const anchor={...site,mesh:undefined,lngLat:site.center,verts:3};
  const coarse={...anchor,id:'306_2770'};
  const fine=[{...anchor,id:'1532_13854'},{...anchor,id:'1533_13854'}];
  const neighbor={...anchor,id:'adjacent'};
  let zoom=15.5,masked=0,completeArt,artRequested=false;
  const artLoad=new Promise(resolve=>{completeArt=resolve;});
  const calls=[],noop=()=>{};
  const gl=new Proxy({
    getUniformLocation:(_,name)=>name,getShaderParameter:()=>true,getProgramParameter:()=>true,
    uniform1i:(name,value)=>{if(name==='u_replaceEsliteShell')masked=value;},
    drawArrays:(_,offset,count)=>calls.push([count,masked]),
  },{get:(target,name)=>target[name]??noop});
  const map={triggerRepaint:noop,getZoom:()=>zoom,getCenter:()=>({lng:site.center[0],lat:site.center[1]}),
    getBounds:()=>({toArray:()=>[site.box.slice(0,2),site.box.slice(2)]})};
  const survey=gzipSync(new Uint8Array(72));
  t.mock.method(globalThis,'fetch',async url=>{
    if(String(url)===String(site.mesh)){
      artRequested=true;
      await artLoad;
      return new Response(art);
    }
    return new Response(survey);
  });
  const layer=new SurveyLayer({levels:{1000:[coarse,neighbor],200:[...fine,neighbor]}},noop,null,true,[],null,null,true,[site]);
  const options={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  async function until(condition){
    for(let i=0;i<100;i++){
      calls.length=0;
      layer.render(gl,options);
      if(condition())return;
      await new Promise(resolve=>setImmediate(resolve));
    }
    assert.fail('survey uploads did not settle');
  }
  layer.onAdd(map,gl);
  try{
    await until(()=>layer.diagnostics.live===1&&calls.length===2);
    assert.ok(artRequested);
    assert.equal(layer.esliteDrawn,false);
    assert.deepEqual(calls,[[3,0],[3,0]]);
    completeArt();
    await until(()=>layer.diagnostics.live===0&&layer.esliteDrawn);
    assert.equal(layer.diagnostics.mode,1000);
    assert.deepEqual(calls,[[3,1],[3,0],[site.verts,0]]);
    zoom=17.8;
    await until(()=>layer.diagnostics.live===0&&layer.diagnostics.mode===200);
    assert.deepEqual(calls,[[3,1],[3,1],[3,0],[site.verts,0]]);
  }finally{
    completeArt();
    layer.onRemove();
  }
});

const data=process.env.POCKET_TAIPEI_DATA;
test('both real LODs isolate the same 16 survey components', {skip:!data},async()=>{
  const index=JSON.parse(await readFile(path.join(data,'survey-index.json'),'utf8'));
  const lods=new Map();
  for(const key of esliteSurveyTiles){
    const [level,id]=key.split('/');
    const record=index.levels[level].find(tile=>tile.id===id);
    const raw=gunzipSync(await readFile(path.join(data,level,id+'.bin.gz')));
    const counts=lods.get(level)??new Array(esliteSurveyParts.length).fill(0);
    lods.set(level,counts);
    for(let i=0;i<raw.length;i+=72){
      const signature=[12,16,20].map(offset=>raw.readFloatLE(i+offset));
      const part=esliteSurveyParts.findIndex(fields=>fields.every((value,k)=>close(value,signature[k])));
      if(part<0)continue;
      for(const offset of [0,24,48]){
        const x=(record.mx-site.mx+raw.readFloatLE(i+offset)*record.m)/site.m;
        const y=(site.my-record.my+raw.readFloatLE(i+offset+4)*record.m)/site.m;
        assert.ok(Math.abs(x)<100&&Math.abs(y)<55,`Found an unrelated survey component in ${key}`);
      }
      counts[part]++;
    }
  }
  assert.ok(lods.get('200').every(n=>n>0));
  assert.deepEqual(lods.get('200'),lods.get('1000'));
});
