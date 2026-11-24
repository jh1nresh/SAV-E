import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {gzipSync,gunzipSync} from 'node:zlib';
import path from 'node:path';
import {SurveyLayer} from '../survey-layer.js';
import {buildSunYatSenHall,sunYatSenHall as hall,isMemorialSurveyTile} from '../sun-yat-sen-hall.js';

const mesh=buildSunYatSenHall();
const yaw=-1.88*Math.PI/180, cs=Math.cos(yaw),sn=Math.sin(yaw);
const local=[];
for(let i=0;i<mesh.length;i+=6){
  const [east,north,z,,,packed]=mesh.subarray(i,i+6);
  local.push([east*cs+north*sn,north*cs-east*sn,z-hall.ground,packed-2]);
}
const near=(a,b,tol=.02)=>Math.abs(a-b)<tol;
const has=(x,y,z,color)=>local.some(([a,b,c,d])=>near(a,x)&&near(b,y)&&near(c,z)&&d===color);

test('hall matches the six-float survey buffer and published 30.4 m height',()=>{
  assert.equal(mesh.length%18,0);
  assert.ok(mesh.byteLength<900*1024);
  assert.ok(mesh.every(Number.isFinite));
  assert.ok(near(Math.max(...local.map(p=>p[2])),30.4,.06));
  for(let i=0;i<mesh.length;i+=18){
    const a=mesh[i+5],b=mesh[i+11],c=mesh[i+17];
    assert.equal(a,b);assert.equal(b,c);
    assert.ok(Number.isInteger(a)&&a>=2&&a<=0xffffff+2);
    assert.ok(near(mesh[i+3],8.21));assert.ok(near(mesh[i+4],30.4));
  }
});

test('four gilt eave tips curl above each 100 m span and surround a dark level rooftop',()=>{
  const roof=new Set([0xd7a347,0xe0ad51,0xdba84c,0xe5b457]);
  const tileAt=(x,y,z)=>local.some(([a,b,c,color])=>near(a,x)&&near(b,y)&&near(c,z)&&roof.has(color));
  for(const x of [-54.3,54.3])for(const y of [-54.3,54.3])assert.ok(tileAt(x,y,17.95));
  for(const [x,y] of [[50.1,0],[-50.1,0],[0,50.1],[0,-50.1]])assert.ok(tileAt(x,y,13.8));
  for(const x of [-27.4,27.4])for(const y of [-27.4,27.4])assert.ok(has(x,y,26.82,0x977b73));
});

test('south stairs reach the landing at the glass entry, with stone columns and red side galleries',()=>{
  for(let i=0;i<9;i++)assert.ok(has(-17.25,-59.4+i*.84,(i+1)*1.72/9,0xd8cfc0));
  assert.ok(has(17.25,-51.88,1.72,0xd8cfc0));
  for(const x of [-13.35,-4.48,4.48,13.35])assert.ok(has(x+.9,-52.1,24.65,0xc0b8a7));
  assert.ok(has(-4.89,-53.1,21.59,0x313738));
  assert.ok(local.some(([x,y,z,color])=>x>15&&y<-41&&near(z,10.95)&&color===0xb36355));
});

const coarse={...hall,id:'306_2770',lngLat:hall.center,verts:3};
const fine={...hall,id:'1532_13851',lngLat:hall.center,verts:3};
const neighbour={...coarse,id:'305_2770'};
test('normal survey rendering keeps the hall at both LODs and suppresses only its own surveyed shell',async t=>{
  let zoom=15.5, nowMasked=0;
  const draws=[], noop=()=>{};
  const gl=new Proxy({
    getUniformLocation:(_,name)=>name,getShaderParameter:()=>true,getProgramParameter:()=>true,
    uniform1i:(location,value)=>{if(location==='u_replaceMemorialShell')nowMasked=value;},
    drawArrays:(_,offset,count)=>draws.push({count,masked:nowMasked}),
  },{get:(target,name)=>target[name]??noop});
  const map={triggerRepaint:noop,getZoom:()=>zoom,getCenter:()=>({lng:hall.center[0],lat:hall.center[1]}),
    getBounds:()=>({toArray:()=>[[hall.box[0],hall.box[1]],[hall.box[2],hall.box[3]]]})};
  const bytes=gzipSync(new Uint8Array(72));
  t.mock.method(globalThis,'fetch',async()=>new Response(bytes));
  const layer=new SurveyLayer({levels:{1000:[coarse,neighbour],200:[fine]}},noop,null,true,[],null,null,true,[hall]);
  const options={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
  const render=()=>{draws.length=0;layer.render(gl,options);};
  const settle=async()=>{
    for(let i=0;i<100;i++){
      render();
      if(layer.diagnostics.live===0)return;
      await new Promise(resolve=>setImmediate(resolve));
    }
    assert.fail('tile upload did not settle');
  };
  layer.onAdd(map,gl);
  try{
    render();
    assert.equal(layer.memorialDrawn,false);
    await settle();
    assert.equal(layer.diagnostics.mode,1000);
    assert.deepEqual(draws.map(d=>d.masked),[1,0,0]);
    assert.equal(draws.at(-1).count,mesh.length/6);
    zoom=18.05;await settle();
    assert.equal(layer.diagnostics.mode,200);
    assert.deepEqual(draws.map(d=>d.masked),[1,0]);
    assert.equal(draws.at(-1).count,mesh.length/6);
    zoom=13;render();
    assert.equal(layer.memorialDrawn,false);assert.equal(draws.length,0);
  }finally{layer.onRemove();}
});

const data=process.env.POCKET_TAIPEI_DATA;
test('both restored survey LODs contain exactly 284 hall triangles inside its outline', {skip:!data},async()=>{
  const index=JSON.parse(await readFile(path.join(data,'survey-index.json'),'utf8'));
  for(const [level,id] of [[200,fine.id],[1000,coarse.id]]){
    assert.ok(isMemorialSurveyTile(level+'/'+id));
    const record=index.levels[level].find(t=>t.id===id);
    const bytes=gunzipSync(await readFile(path.join(data,String(level),id+'.bin.gz')));
    const values=new Float32Array(bytes.buffer,bytes.byteOffset,bytes.length/4);
    let matched=0;
    for(let i=0;i<values.length;i+=6){
      if(Math.abs(values[i+3]-8.23)>=.006||Math.abs(values[i+4]-9.77)>=.006||Math.abs(values[i+5]-.495)>=.0002)continue;
      const east=(record.mx-hall.mx+values[i]*record.m)/hall.m;
      const north=(hall.my-record.my+values[i+1]*record.m)/hall.m;
      assert.ok(Math.abs(east)<57 && Math.abs(north)<61);
      matched++;
    }
    assert.equal(matched,284*3);assert.ok(matched<record.verts);
  }
});
