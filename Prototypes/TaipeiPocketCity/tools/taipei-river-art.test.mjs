import {test} from 'node:test';
import assert from 'node:assert/strict';
import {gunzipSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import {addTaipeiRiverArt} from '../taipei-river-art.js';

const bytes = readFileSync(new URL('../assets/taipei-river-art.json.gz',import.meta.url));
const rivers = JSON.parse(gunzipSync(bytes));

test('river artwork loads on entering Taipei, stays below roads and survives a transient error',async t=>{
  let zoom = 9, requests = 0;
  const listeners = new Map(), layers = [], sources = new Map();
  const map = {
    on:(event,listener)=>listeners.set(event,listener),off:event=>listeners.delete(event),
    getZoom:()=>zoom, getBounds:()=>({getEast:()=>121.52,getWest:()=>121.49,getNorth:()=>25.07,getSouth:()=>25.05}),
    getSource:id=>sources.get(id),addSource:(id,source)=>sources.set(id,source),getLayer:id=>id==='landcover_sand',
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
    if (k.startsWith('pier-')) continue;
    assert.ok(rivers.features.some(f=>f.properties.k===k && f.properties.alpha<.1),k+' must fade at the edge');
  }
});
