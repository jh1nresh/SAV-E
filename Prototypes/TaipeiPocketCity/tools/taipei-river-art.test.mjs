import {test} from 'node:test';
import assert from 'node:assert/strict';
import {gzipSync,gunzipSync} from 'node:zlib';
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
  let zoom = 9, west = 121.49, requests = 0;
  const listeners = new Map(), layers = [], sources = new Map();
  const map = {
    on:(event,listener)=>listeners.set(event,listener),off:event=>listeners.delete(event),
    getZoom:()=>zoom, getBounds:()=>({getEast:()=>west+.03,getWest:()=>west,getNorth:()=>25.07,getSouth:()=>25.05}),
    getSource:id=>sources.get(id),addSource:(id,source)=>sources.set(id,source),getLayer:id=>id==='landcover_sand',
    addImage:(_,image)=>assert.ok(image.width>0),hasImage:()=>false,
    addLayer:(layer,before)=>{assert.equal(before,'landcover_sand'); layers.push(layer);}
  };
  const empty=gzipSync(JSON.stringify({type:'FeatureCollection',features:[]}));
  t.mock.method(globalThis,'fetch',async()=>{
    requests++;
    if(requests===1)return new Response(null,{status:503});
    return new Response(requests===2?empty:bytes);
  });
  t.mock.method(console,'warn',()=>{});
  addTaipeiRiverArt(map,'label');
  assert.equal(requests,0);
  zoom=10.75;
  west=120;
  await listeners.get('moveend')();
  assert.equal(requests,0,'City-scale preloading only begins when the viewport overlaps Taipei');
  west=121.49;
  await listeners.get('moveend')();
  assert.equal(sources.size,0);
  assert.equal(layers.length,0,'Keep the basemap visible during a failed artwork request');
  await listeners.get('moveend')();
  assert.equal(sources.size,0,'An empty dataset also leaves the fallback available for a retry');
  await listeners.get('moveend')();
  assert.equal(requests,3);
  assert.deepEqual(sources.get('taipei-river-art').data,rivers);
  const kinds = new Set(rivers.features.map(f=>f.properties.k));
  const drawnKinds=new Set(layers.map(l=>l.filter[2]));
  for(const kind of kinds)assert.ok(drawnKinds.has(kind),kind+' has no drawing layer');
  assert.ok(!listeners.has('moveend'));
  assert.ok(rivers.features.every(f=>f.properties.alpha>=0 && f.properties.alpha<=1));
  for (const k of kinds) {
    if (k.startsWith('pier-') || k==='deck-joint' || k.startsWith('bank-') || k==='bridge-reflection')continue;
    assert.ok(rivers.features.some(f=>f.properties.k===k && f.properties.alpha<.1),k+' must fade at the edge');
  }
  const byId=name=>layers.find(layer=>layer.id==='taipei-river-art-'+name);
  const position=name=>layers.indexOf(byId(name));
  for(const name of ['bank-mud','bank-marsh','bank-reflection','bridge-reflection','bank-foliage','bank-silt']){
    const layer=byId(name);
    assert.ok(layer,name);
    assert.equal(layer.source,'taipei-river-art');
    assert.ok(position('shade')<position(name) && position(name)<position('deck'),name);
    assert.equal(layer.filter[2],({'bank-foliage':'bank-marsh','bank-silt':'bank-mud'})[name]??name);
  }
  // These are map-coordinate layers. At city scale the colored reaches and current
  // ribbons appear first; short brush marks and translucent crests build up next.
  const opacity=(name,zoom,alpha)=>{
    const layer=byId(name);
    const stops=layer.paint[layer.type==='line'?'line-opacity':'fill-opacity'];
    assert.deepEqual(stops.slice(0,3),['interpolate',['linear'],['zoom']]);
    assert.equal(stops[4],0);
    assert.deepEqual(stops[6].slice(2),[['get','alpha']]);
    return Math.max(0,Math.min(1,(zoom-stops[3])/(stops[5]-stops[3])))*stops[6][1]*alpha;
  };
  for(const wash of ['shore','shallows','reach','channel']){
    assert.ok(byId(wash).minzoom<=11 && opacity(wash,12,1)>.65);
    assert.ok(opacity(wash,13,.03)<.03);
  }
  assert.ok(opacity('currents',13,1)>.18);
  for(const brush of ['ripple','glint','shade'])assert.ok(opacity(brush,14,1)>.19);
  assert.ok(opacity('wavelets',14.5,1)>.15 && opacity('wavelets',16,1)>.40);
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

test('Guandu marsh and mud stay on the bank while reflections land in the mapped channel',()=>{
  function contains(polygon,[x,y]){
    if(polygon.type!=='Polygon')return false;
    let inside=false;
    for(const ring of polygon.coordinates){
      for(let i=1;i<ring.length;i++){
        const [a,b]=ring[i-1],[c,d]=ring[i];
        if((b>y)!==(d>y) && x<a+(c-a)*(y-b)/(d-b))inside=!inside;
      }
    }
    return inside;
  }
  const water=rivers.features.filter(f=>f.properties.k==='shore');
  const locations=[
    ['bank-marsh','way/363171376','mangrove',[121.4591034,25.1285895],false],
    ['bank-mud','way/363171375','tidalflat',[121.4609114,25.1240995],false],
    ['bank-reflection','way/363171376','mangrove',[121.4592439,25.1274945],true],
    ['bridge-reflection','way/550496017','bridge',[121.525106,25.0739375],true],
  ];
  for(const [kind,osm,habitat,point,inWater] of locations){
    assert.ok(rivers.features.some(f=>f.properties.k===kind && f.properties.osm===osm &&
      f.properties.habitat===habitat && contains(f.geometry,point)),kind+' must keep its source position');
    assert.equal(water.some(f=>contains(f.geometry,point)),inWater,kind);
  }
});
