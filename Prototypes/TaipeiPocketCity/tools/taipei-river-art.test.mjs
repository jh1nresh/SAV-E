import {test} from 'node:test';
import assert from 'node:assert/strict';
import {gunzipSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import {addCity170Style} from '../city170-style.js';
import {addTaipeiRiverArt} from '../taipei-river-art.js';

function mockCanvas(t) {
  const ctx = new Proxy({}, {get: (_target, key) => key === 'getImageData' ? () => ({width:256,height:256}) : () => {}});
  const original=globalThis.document;
  globalThis.document={createElement:()=>({getContext:()=>ctx})};
  t.after(()=>{if(original===undefined)delete globalThis.document;else globalThis.document=original;});
}

const bytes = readFileSync(new URL('../assets/taipei-river-art.json.gz',import.meta.url));
const rivers = JSON.parse(gunzipSync(bytes));

test('river artwork loads on entering Taipei, stays below roads and survives a transient error',async t=>{
  mockCanvas(t);
  let zoom = 9, requests = 0;
  const listeners = new Map(), layers = [], sources = new Map();
  const map = {
    on:(event,listener)=>listeners.set(event,listener),off:event=>listeners.delete(event),
    getZoom:()=>zoom, getBounds:()=>({getEast:()=>121.52,getWest:()=>121.49,getNorth:()=>25.07,getSouth:()=>25.05}),
    getSource:id=>sources.get(id),addSource:(id,source)=>sources.set(id,source),getLayer:id=>id==='landcover_sand',
    addImage:(_,image)=>assert.equal(image.width,256),
    addLayer:(layer,before)=>{assert.equal(before,'landcover_sand'); layers.push(layer);}
  };
  t.mock.method(globalThis,'fetch',async()=>++requests===1 ? new Response(null,{status:503}) : new Response(bytes));
  t.mock.method(console,'warn',()=>{});
  addTaipeiRiverArt(map,'label');
  assert.equal(requests,0);
  zoom=17;
  await listeners.get('moveend')();
  assert.equal(sources.size,0);
  await listeners.get('moveend')();
  assert.equal(requests,2);
  assert.deepEqual(sources.get('taipei-river-art').data,rivers);
  const kinds = new Set(rivers.features.map(f=>f.properties.k));
  assert.deepEqual(new Set(layers.map(l=>l.filter[2])),kinds);
  assert.ok(!listeners.has('moveend'));
  assert.ok(rivers.features.every(f=>f.properties.alpha>=0 && f.properties.alpha<=1));
  for (const k of kinds) {
    if (k.startsWith('pier-') || k==='deck-joint') continue;
    assert.ok(rivers.features.some(f=>f.properties.k===k && f.properties.alpha<.1),k+' must fade at the edge');
  }
});


test('late city tile installation keeps fallback water below the illustrated river', t=>{
  mockCanvas(t);
  const layers=new Map();
  const map={getStyle:()=>({layers:[]}),getSource:()=>null,hasImage:()=>true,
    getLayer:id=>['taipei-river-art-shore','landcover_sand'].includes(id),addImage:()=>{},
    addLayer:(layer,before)=>layers.set(layer.id,before)};
  addCity170Style(map,'atlas','labels');
  for(const id of ['city170-water','city170-water-texture','city170-water-shallows','city170-water-shoreline']){
    assert.equal(layers.get(id),'taipei-river-art-shore');
  }
});
