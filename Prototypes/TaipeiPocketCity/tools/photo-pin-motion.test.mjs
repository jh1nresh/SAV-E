import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setPlacePinEmphasis} from '../photo-pin-motion.js';

function fixture(t,reduced=false){
  const media=globalThis.matchMedia,computed=globalThis.getComputedStyle;
  globalThis.matchMedia=()=>({matches:reduced});
  globalThis.getComputedStyle=art=>({scale:art.style.scale||'1',rotate:art.angle||'0deg'});
  t.after(()=>{globalThis.matchMedia=media;globalThis.getComputedStyle=computed;});
  const animations=[];
  const art={style:{},getAnimations:()=>animations.filter(a=>!a.cancelled),animate(frames,options){
    const a={frames,options,cancel(){this.cancelled=true;}};animations.push(a);return a;
  }};
  return {art,animations};
}

test('selection rocks artwork and settles without changing the geographic transform',t=>{
  const {art,animations}=fixture(t);
  art.style.transform='translate(-50%, -100%)';
  setPlacePinEmphasis(art,true);
  const {frames,options}=animations[0];
  assert.equal(art.style.transform,'translate(-50%, -100%)');
  assert.equal(art.style.scale,'1.28');
  assert.ok(frames.some(f=>parseFloat(f.rotate)<0));
  assert.ok(frames.some(f=>parseFloat(f.rotate)>0));
  assert.equal(frames.at(-1).rotate,'0deg');
  assert.equal(frames.at(-1).scale,'1.28');
  assert.ok(options.duration<1000);
  setPlacePinEmphasis(art,true,{animate:false});
  assert.equal(animations.length,1,'refresh must not replay');
});

test('close interrupts selected motion and settles to normal size',t=>{
  const {art,animations}=fixture(t);
  setPlacePinEmphasis(art,true);
  art.angle='-4deg';
  setPlacePinEmphasis(art,false);
  assert.equal(animations[0].cancelled,true);
  assert.equal(animations.at(-1).frames[0].rotate,'-4deg');
  assert.equal(animations.at(-1).frames.at(-1).rotate,'0deg');
  assert.equal(art.style.scale,'1');
});

test('Reduce Motion applies selection immediately with no rocking',t=>{
  const {art,animations}=fixture(t,true);
  setPlacePinEmphasis(art,true,{repeat:true});
  assert.equal(art.style.scale,'1.28');
  setPlacePinEmphasis(art,false);
  assert.equal(art.style.scale,'1');
  assert.equal(animations.length,0);
});


test('category artwork squashes once and close interrupts without moving the anchor',t=>{
  const {art,animations}=fixture(t);
  art.classList={contains:name=>name==='ios-category-art'};
  art.style.transform='translate(-50%, -100%)';
  setPlacePinEmphasis(art,true,{repeat:true});
  assert.ok(animations[0].frames.some(f=>{const [x,y]=f.scale.split(' ').map(Number);return Math.abs(x-y)>.04;}));
  assert.equal(animations[0].frames.at(-1).scale,'1.28 1.28');
  art.style.scale='1.28 1.1';
  setPlacePinEmphasis(art,false);
  assert.equal(animations[0].cancelled,true);
  assert.equal(animations.at(-1).frames[0].scale,'1.28 1.1');
  assert.equal(animations.at(-1).frames.at(-1).scale,'1 1');
  assert.equal(art.style.transform,'translate(-50%, -100%)');
});

test('category artwork respects Reduce Motion without losing selection',t=>{
  const {art,animations}=fixture(t,true);
  art.classList={contains:name=>name==='category-pin-art'};
  setPlacePinEmphasis(art,true,{repeat:true});
  assert.equal(art.style.scale,'1.28');
  assert.equal(animations.length,0);
});
