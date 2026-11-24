import test from 'node:test';
import assert from 'node:assert/strict';
import {globeCamera,returnToGlobe} from '../world-camera.js';

test('the globe opens facing East Asia with the short edge controlling its diameter',()=>{
  const portrait=globeCamera(390,844);
  assert.deepEqual(portrait,globeCamera(844,390));
  assert.deepEqual(portrait.center,[124,24]);
  assert.equal(portrait.pitch,0);
  const desktop=globeCamera(1280,900);
  assert.ok(Math.abs(2**(desktop.zoom-portrait.zoom)-900/390)<1e-6);
  assert.ok(Number.isFinite(globeCamera(0,0).zoom));
});

test('a street reset waits for globe rendering and respects interrupted motion',()=>{
  for(const interrupted of [true,false]){
    const events=new Map(),moves=[];
    let zoom=18;
    const map={stop(){},isMoving:()=>interrupted,getZoom:()=>zoom,
      once:(event,handler)=>events.set(event,handler),easeTo:move=>moves.push(move)};
    const home=globeCamera(390,844);
    returnToGlobe(map,home,true);
    assert.equal(moves.length,1);
    assert.equal(moves[0].duration,0);
    zoom=moves[0].zoom;
    events.get('moveend')();
    assert.equal(moves.length,1);
    events.get('render')();
    assert.deepEqual(moves.slice(1),interrupted?[]:[{...home,duration:0}]);
  }
});
