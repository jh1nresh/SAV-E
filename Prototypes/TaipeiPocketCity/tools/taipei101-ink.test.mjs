import assert from 'node:assert/strict';
import test from 'node:test';
import {Taipei101Ink,inkInView} from '../taipei101-ink.js';

const view=new Float32Array([.01,0,0,0,0,.01,0,0,0,0,.002,0,0,0,-.5,1]);
const outside=view.slice();outside[12]=5;
const asset={mesh:'ink',segments:4,mallFirst:1,mallCount:2};
const tick=()=>new Promise(done=>setImmediate(done));
const packed=()=>new Float32Array(Array.from({length:4},()=>[0,0,10,1,1,10,0x112233,.664]).flat()).buffer;

function mockGL(){
  const calls=[];
  const gl=new Proxy({calls,canvas:{clientWidth:160,clientHeight:120},drawingBufferWidth:320,
    createBuffer:()=>({type:'buffer'}),createVertexArray:()=>({type:'vao'}),
    getBufferParameter:()=>128,getParameter:key=>'saved-'+key,getUniformLocation:(_,name)=>name,
  },{get:(obj,name)=>name in obj?obj[name]:name===name.toUpperCase()?name:(...args)=>calls.push([name,...args])});
  return gl;
}

test('3D culling includes a tower crown whose footprint is outside the clip volume',()=>{
  assert.equal(inkInView(view),true);
  assert.equal(inkInView(outside),false);
  const spireOnly=view.slice();
  spireOnly[10]=.005;spireOnly[14]=-3;
  assert.equal(inkInView(spireOnly),true);
  assert.equal(inkInView(new Float32Array(16)),false);
});

test('one upload survives camera moves, mall cutaway skips the merchant group and GL state is restored',async()=>{
  const gl=mockGL(),program={},oldProgram={};
  let requests=0,repaints=0;
  const ink=new Taipei101Ink(gl,asset,()=>program,async()=>{requests++;return packed();},()=>repaints++);
  assert.equal(ink.prepare(outside),false);
  assert.equal(requests,0);
  assert.equal(ink.prepare(view),false);
  assert.equal(ink.prepare(view),false);
  await tick();
  assert.equal(ink.prepare(view),true);
  assert.equal(ink.prepare(outside),false);
  assert.equal(ink.prepare(view),true);
  assert.equal(requests,1);assert.equal(repaints,1);
  assert.deepEqual(gl.calls.filter(c=>c[0]==='vertexAttribDivisor'),[[0,1],[1,1],[2,1]].map(args=>['vertexAttribDivisor',...args]));
  ink.draw(view,false,oldProgram);ink.draw(view,true,oldProgram);
  assert.deepEqual(gl.calls.filter(c=>c[0]==='uniform2i').map(c=>c.slice(2)),[[1,1],[1,3]]);
  assert.deepEqual(gl.calls.filter(c=>c[0]==='drawArraysInstanced').map(c=>c.slice(1)),[0,1].map(()=>['TRIANGLE_STRIP',0,4,4]));
  assert.deepEqual(gl.calls.filter(c=>c[0]==='depthMask').map(c=>c[1]),[false,true,false,true]);
  assert.deepEqual(gl.calls.at(-1),['useProgram',oldProgram]);
  assert.deepEqual(gl.calls.filter(c=>c[0]==='blendFuncSeparate').at(-1).slice(1),
    ['BLEND_SRC_RGB','BLEND_DST_RGB','BLEND_SRC_ALPHA','BLEND_DST_ALPHA'].map(k=>'saved-'+k));
  ink.dispose();
  assert.equal(gl.calls.filter(c=>c[0].startsWith('delete')).length,3);
});

test('missing or damaged ink keeps the complete exterior until a later visit can load it',async t=>{
  t.mock.method(console,'warn',()=>{});
  for(const load of [async()=>{throw Error('missing');},async()=>new ArrayBuffer(32),async()=>new ArrayBuffer(128)]){
    let requests=0;
    const renderer=new Taipei101Ink(mockGL(),asset,()=>({}),async()=>{requests++;return load();},()=>{});
    assert.equal(renderer.prepare(view),false);
    await tick();
    for(let frame=0;frame<5;frame++)assert.equal(renderer.prepare(view),false);
    assert.equal(requests,1);
    renderer.prepare(outside);renderer.prepare(view);
    assert.equal(requests,2);
    renderer.dispose();await tick();
  }
});

test('removal aborts a pending fetch and ignores any subsequently resolved bytes',async()=>{
  const gl=mockGL();let resolve,signal,repaints=0;
  const r=new Taipei101Ink(gl,asset,()=>({}),(_,s)=>{signal=s;return new Promise(done=>{resolve=done;});},()=>repaints++);
  r.prepare(view);r.dispose();
  assert.equal(signal.aborted,true);
  resolve(new ArrayBuffer(128));await tick();
  assert.equal(repaints,0);assert.equal(r.prepare(view),false);
  assert.equal(r.data,null);
});
