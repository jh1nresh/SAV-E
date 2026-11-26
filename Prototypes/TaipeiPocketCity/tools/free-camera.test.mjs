import test from 'node:test';
import assert from 'node:assert/strict';
import {installFreeCamera} from '../free-camera.js';
function fixture(){
  class Element extends EventTarget{
    value='';dataset={};children=new Map();
    querySelector(s){return this.children.get(s)}
    querySelectorAll(){return this.pan??[]}
  }
  const stage=new Element(),panel=new Element();stage.children.set('#free-camera',panel);
  for(const id of ['camera-bearing','camera-pitch','bearing-value','pitch-value','globe-destination'])panel.children.set('#'+id,new Element());
  panel.pan=['left','up','down','right'].map(id=>{const el=new Element();el.dataset.pan=id;return el});
  const events=new Map(),removed=new Map(),calls=[];let bearing=0,pitch=45;
  const gesture=()=>({enable(){calls.push('enable')},enableRotation(){calls.push('rotate')}});
  const map={dragPan:gesture(),dragRotate:gesture(),touchZoomRotate:gesture(),touchPitch:gesture(),
    getBearing:()=>bearing,getPitch:()=>pitch,getCenter:()=>({toArray:()=>[121.5,25]}),getZoom:()=>18,
    setBearing(v){bearing=v;events.get('move')()},setPitch(v){pitch=v;events.get('move')()},stop(){calls.push('stop')},
    panBy(v,opts){calls.push({v,opts})},on:(k,f)=>events.set(k,f),once:(k,f)=>removed.set(k,f),off:(k,f)=>{if(events.get(k)===f)events.delete(k)}};
  globalThis.matchMedia=()=>({matches:true});
  const destinations=[];const camera=installFreeCamera(map,stage,{locate:x=>destinations.push(x)});
  return {stage,panel,map,camera,calls,removed,destinations};
}
test('rotation, pitch and pan work without assigning a preset camera',()=>{
  const f=fixture();
  const bearing=f.panel.querySelector('#camera-bearing');bearing.value='-120';bearing.dispatchEvent(new Event('input'));
  const pitch=f.panel.querySelector('#camera-pitch');pitch.value='72';pitch.dispatchEvent(new Event('input'));
  assert.equal(f.map.getBearing(),-120);assert.equal(f.map.getPitch(),72);
  assert.deepEqual(JSON.parse(f.stage.dataset.camera),{center:[121.5,25],zoom:18,bearing:-120,pitch:72});
  f.panel.pan[0].dispatchEvent(new Event('click'));assert.deepEqual(f.calls.at(-1),{v:[-140,0],opts:{duration:0}});
  assert.equal(f.destinations.length,0);
});
test('pointer, wheel, key and panel changes claim camera before a late catalog can apply',()=>{
  for(const [target,type,key] of [['stage','pointerdown'],['stage','wheel'],['stage','keydown','='],['panel','input'],['panel','change']]){
    const f=fixture();assert.equal(f.camera.userInteracted,false);
    const e=new Event(type);if(key)Object.defineProperty(e,'key',{value:key});f[target].dispatchEvent(e);
    assert.equal(f.camera.userInteracted,true,`${target}:${type}`);
  }
});
test('disposal unregisters input and map listeners',()=>{
  const f=fixture();f.removed.get('remove')();
  f.stage.dispatchEvent(new Event('pointerdown'));assert.equal(f.camera.userInteracted,false);
  f.panel.pan[0].dispatchEvent(new Event('click'));assert.ok(!f.calls.includes('stop'));
});
