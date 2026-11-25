import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {gzipSync,gunzipSync} from 'node:zlib';
import {SurveyLayer} from '../survey-layer.js';
import {buildTaipeiDome,isDomeSurveyTile,taipeiDome as site,addDomeApron} from '../taipei-dome.js';
import {domeApron} from '../taipei-dome-geography.js';

const mesh=buildTaipeiDome();
const near=(a,b,t=.0001)=>Math.abs(a-b)<t;
test('the rooftop and foot form a closed shell with the survey height and a grounded skirt',()=>{
  assert.ok(mesh.every(Number.isFinite));
  assert.equal(mesh.length%18,0);
  assert.ok(mesh.length/18<=3000);
  const edges=new Map();
  let minZ=Infinity,maxZ=-Infinity;
  for(let i=0;i<mesh.length;i+=18){
    const points=[0,6,12].map(j=>Array.from(mesh.subarray(i+j,i+j+3)));
    const [a,b,c]=points,u=b.map((x,j)=>x-a[j]),v=c.map((x,j)=>x-a[j]);
    assert.ok(Math.hypot(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])>1e-5);
    for(const j of [0,6,12]){
      assert.ok(near(mesh[i+3+j],site.ground));
      assert.ok(near(mesh[i+4+j],60.41006));
      assert.equal(mesh[i+5+j],mesh[i+5]);
    }
    minZ=Math.min(minZ,...points.map(p=>p[2]));
    maxZ=Math.max(maxZ,...points.map(p=>p[2]));
    if(mesh[i+5]===0x98a7a7+2)continue;
    for(let k=0;k<3;k++){
      const a=points[k].join('/'),b=points[(k+1)%3].join('/');
      const key=[a,b].sort().join(':');
      const entry=edges.get(key)??[0,0];
      entry[0]++;
      entry[1]+=a<b?1:-1;
      edges.set(key,entry);
    }
  }
  assert.ok(minZ<6.81);
  assert.ok(near(maxZ,site.ground+60.41006));
  for(const edge of edges.values())assert.deepEqual(edge,[2,0]);
  assert.deepEqual(domeApron.geometry.coordinates[0][0],domeApron.geometry.coordinates[0].at(-1));
});

test('the apron draws as terrain and only the registered dome survey tile is suppressed once the model loads',async t=>{
  const layers=[],source=[];
  addDomeApron({addLayer:(layer,before)=>layers.push([layer,before]),addSource:(name,item)=>source.push([name,item])},'labels');
  assert.equal(layers.length,1);
  assert.equal(layers[0][0].type,'fill');
  assert.equal(layers[0][1],'labels');
  assert.equal(source[0][1].data,domeApron);

  const anchor={...site,lngLat:site.center,verts:3};
  const coarse={...anchor,id:'306_2770'};
  const fine={...anchor,id:'1532_13852'};
  const neighbour={...anchor,id:'other'};
  let zoom=15.5,masked;
  const calls=[],noop=()=>{};
  const gl=new Proxy({
    getUniformLocation:(_,name)=>name,getShaderParameter:()=>true,getProgramParameter:()=>true,
    uniform1i:(name,v)=>{if(name==='u_replaceDomeShell')masked=v;},
    drawArrays:(_,offset,count)=>calls.push([count,masked]),
  },{get:(target,name)=>target[name]??noop});
  const w=site.box;
  const map={triggerRepaint:noop,getZoom:()=>zoom,getCenter:()=>({lng:site.center[0],lat:site.center[1]}),
    getBounds:()=>({toArray:()=>[w.slice(0,2),w.slice(2)]})};
  const bytes=gzipSync(new Uint8Array(72));
  t.mock.method(globalThis,'fetch',async()=>new Response(bytes));
  const layer=new SurveyLayer({levels:{1000:[coarse,neighbour],200:[fine,neighbour]}},noop,null,true,[],null,null,true,[site]);
  const options={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  const render=()=>{calls.length=0;layer.render(gl,options);};
  async function settle(){
    for(let i=0;i<100;i++){
      render();
      if(layer.diagnostics.live===0)return;
      await new Promise(resolve=>setImmediate(resolve));
    }
    assert.fail('survey uploads did not settle');
  }
  layer.onAdd(map,gl);
  try{
    render();
    assert.equal(layer.domeDrawn,false);
    await settle();
    assert.equal(layer.diagnostics.mode,1000);
    assert.deepEqual(calls,[[3,1],[3,0],[mesh.length/6,0]]);
    zoom=17.8;
    await settle();
    assert.equal(layer.diagnostics.mode,200);
    assert.deepEqual(calls,[[3,1],[3,0],[mesh.length/6,0]]);
  }finally{layer.onRemove();}
});

const data=process.env.POCKET_TAIPEI_DATA;
test('both restored survey levels identify 536 shell and 1052 apron triangles at the stadium', {skip:!data},async()=>{
  const index=JSON.parse(await readFile(path.join(data,'survey-index.json'),'utf8'));
  for(const [level,id] of [[200,'1532_13852'],[1000,'306_2770']]){
    assert.ok(isDomeSurveyTile(level+'/'+id));
    const record=index.levels[level].find(t=>t.id===id);
    const raw=gunzipSync(await readFile(path.join(data,String(level),id+'.bin.gz')));
    const values=new Float32Array(raw.buffer,raw.byteOffset,raw.length/4);
    const counts=[0,0];
    for(let i=0;i<values.length;i+=18){
      if(!near(values[i+3],7.52979,.002))continue;
      const kind=near(values[i+4],60.41006,.002)&&near(values[i+5],.315)?0:
        near(values[i+4],55.75004,.002)&&near(values[i+5],.345)?1:-1;
      if(kind<0)continue;
      for(const offset of [0,6,12]){
        const east=(record.mx-site.mx+values[i+offset]*record.m)/site.m;
        const north=(site.my-record.my+values[i+offset+1]*record.m)/site.m;
        assert.ok(Math.abs(east)<130&&Math.abs(north)<105);
      }
      counts[kind]++;
    }
    assert.deepEqual(counts,[536,1052]);
  }
});
