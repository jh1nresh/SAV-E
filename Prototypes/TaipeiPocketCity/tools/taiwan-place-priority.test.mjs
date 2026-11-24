import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {indexAuthoredPlaces} from '../city-atlas-layer.js';
import {geographicScene} from '../cities/geography.js';
import {addTaiwanPlaces,placeRecord} from '../taiwan-places.js';

const point=[120,23];
const pin=(name,rank,placeId)=>({type:'Feature',geometry:{type:'Point',coordinates:point},
  properties:{name,rank,placeId,kind:'pin'}});
test('authored pins claim by ID or by nearby anonymous name only at their visible scale',()=>{
  const anonymous=pin('街角麵店',2),named=pin('別館',0,'poi/way/12');
  const pins=indexAuthoredPlaces([anonymous,named]);
  const shop=placeRecord(['街角麵店','restaurant','n45',...point,'A']);
  assert.equal(pins.claims({...shop,point:[120.01,23]},19),false);
  assert.equal(pins.claims(shop,17),false);
  assert.equal(pins.claims(shop,19),true);
  assert.equal(pins.enrich(anonymous).placeId,shop.placeId);
  assert.equal(pins.claims({...shop,placeId:'poi/node/99'},19),false);
  assert.equal(pins.claims({...shop,name:'別館'},19),false);
  assert.equal(pins.claims({...shop,name:'舊館名',placeId:named.properties.placeId,point:[120.001,23]},17),true);
  assert.equal(pins.claims({...shop,placeId:named.properties.placeId},16.65),false);
});

test('live Tainan patch retains unmatched shops while authoring load, zoom and unload change deduplication',async t=>{
  t.mock.method(globalThis,'fetch',async file=>new Response(await readFile(file)));
  const load=async path=>JSON.parse(await readFile(new URL('../'+path,import.meta.url),'utf8'));
  const row=(await load('cities/catalog.json')).find(r=>r.id==='tainan'),scene=await load('cities/tainan/scene.json');
  const authored=geographicScene(scene,row.landmarkIds,row.landmarkSites,row.landmarkPlaceIds);
  const [w,s,e,n]=row.bounds,handlers=new Map(),opened=[];
  let z=19,lookup=indexAuthoredPlaces([]),seen,ready,above=[],inserted;
  const source={setData:({features})=>{seen=features;ready();}};
  const bounds={getWest:()=>w,getEast:()=>e,getNorth:()=>n,getSouth:()=>s,
    contains:([x,y])=>x>=w&&x<=e&&y>=s&&y<=n};
  const map={getZoom:()=>z,getBounds:()=>bounds,hasImage:()=>true,
    addSource(){},getSource:()=>source,getLayer:id=>id==='city-atlas-places',
    addLayer:(_,before)=>inserted=before,queryRenderedFeatures:()=>above,
    on:(event,...args)=>handlers.set(event,args.at(-1))};
  const update=fn=>new Promise(resolve=>{ready=resolve;fn();});
  await update(()=>addTaiwanPlaces(map,(p,zoom)=>lookup.claims(p,zoom),p=>opened.push(p)));
  const has=id=>seen.some(f=>f.properties.placeId===id);
  const shop='poi/node/7544762172',temple='poi/way/561994812',noodles='poi/node/1710193292';
  assert.equal(inserted,'city-atlas-places');assert.ok(has(shop)&&has(temple)&&has(noodles));
  lookup=indexAuthoredPlaces(authored);
  await update(handlers.get('city-atlas-pins-changed'));
  assert.ok(has(shop));assert.equal(has(temple),false);assert.equal(has(noodles),false);
  const click={features:seen.filter(f=>f.properties.placeId===shop),point:[1,1],preventDefault(){}};
  above=[{}];handlers.get('click')(click);assert.equal(opened.length,0);
  above=[];handlers.get('click')(click);assert.equal(opened[0].placeId,shop);
  z=17.5;await update(handlers.get('moveend'));assert.ok(has(shop)&&has(noodles));assert.equal(has(temple),false);
  lookup=indexAuthoredPlaces([]);await update(handlers.get('city-atlas-pins-changed'));assert.ok(has(temple));
});
