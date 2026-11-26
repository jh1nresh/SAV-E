import test from 'node:test';
import assert from 'node:assert/strict';
import {Style} from '../assets/maplibre-gl.mjs';
import {addCityPlaceIndex,cityPlaceLayers,loadCityPlaces} from '../city-place-index.js';
import {mallStreetExit4,metroExitCard,metroExitFeatures,metroExitLayer,metroExitPlaceId,isDuplicateMetroExit} from '../taipei-metro-exits.js';
import {mallMetroExit4} from '../taipei101-wayfinding.js';

test('use all 280 Taipei City exit records with stable distinct identities and original coordinates',()=>{
  assert.equal(metroExitFeatures.length,280);
  assert.equal(new Set(metroExitFeatures.map(f=>f.id)).size,280);
  assert.equal(new Set(metroExitFeatures.map(f=>f.properties.district)).size,12);
  for(const feature of metroExitFeatures){
    const {coordinates}=feature.geometry;
    const card=metroExitCard(feature.id);
    assert.equal(feature.properties.placeId,feature.id);
    assert.deepEqual(card.point,coordinates);
    assert.equal(card.category,'subway_entrance');
    assert.notEqual(card.exitLabel,'0 號出口');
    assert(card.detail.includes(card.district));
    assert.equal(card.detail.includes('無障礙出口'),card.accessible);
  }
  const street=metroExitCard(mallStreetExit4);
  assert.deepEqual(street.point,[121.564112,25.033034]);
  assert.equal(street.url,mallMetroExit4.properties.url);
  assert.notDeepEqual(street.point,mallMetroExit4.geometry.coordinates);
  assert.equal(metroExitCard(metroExitPlaceId('台北車站','M2')).exitLabel,'M2 出口');
  assert.equal(metroExitCard(metroExitPlaceId('中山國中站','0')).exitLabel,'出口');
});

test('the shared map and search index retains existing shops alongside exits',async t=>{
  const shop={type:'Feature',id:'poi/node/987',properties:{placeId:'poi/node/987',name:'小店'},
    geometry:{type:'Point',coordinates:[121.522,25.04]}};
  const request=t.mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify({
    type:'FeatureCollection',features:[shop],
  })));
  const index=await loadCityPlaces();
  assert.equal(request.mock.callCount(),1);
  assert.equal(index.features.length,281);
  assert.deepEqual(index.features[0],shop);
  assert(index.features.some(f=>f.properties.placeId===mallStreetExit4));
});

test('street exits are only a close-up layer and mall suppression composes with account pins',()=>{
  const layers=new Map(),sources=new Map(),events=new Map();
  const map={
    addSource:(id,spec)=>sources.set(id,spec),
    addLayer:layer=>layers.set(layer.id,layer),
    getLayer:id=>layers.get(id),
    getFilter:id=>layers.get(id).filter,
    setFilter:(id,filter)=>{layers.get(id).filter=filter;},
    getZoom:()=>4,
    on:(name,handler)=>events.set(name,handler),
  };
  addCityPlaceIndex(map,{layout:{},paint:{}});
  assert(cityPlaceLayers.includes(metroExitLayer));
  const exits=layers.get(metroExitLayer);
  assert.equal(exits.minzoom,18.2);
  assert.equal(exits.layout['icon-image'],'place-pin-transit');
  assert.deepEqual(exits.layout['text-field'],['get','exitLabel']);
  assert.deepEqual(sources.get(exits.source).data.features,metroExitFeatures);
  for(const id of ['taipei-place-names','taipei-place-neighbors']){
    assert.deepEqual(layers.get(id).filter.find(f=>f[0]==='!'),['!',['has','exitLabel']]);
  }
  const original=structuredClone(exits.filter);
  const ownID=metroExitPlaceId('台北車站','M2');
  map.savvyAccountPlaceIds=[ownID];
  map.savvyMallAdjacentPlaceIds=[mallStreetExit4];
  events.get('pocketmallplaces')();
  assert(JSON.stringify(exits.filter).includes(JSON.stringify([ownID,mallStreetExit4])));
  const errors=[];
  Style.prototype.addLayer.call({
    _checkLoaded(){},getLayer(){},fire(e){errors.push(e.error.message);},
    serialize:()=>({version:8,glyphs:'https://localhost/{fontstack}/{range}.pbf',sources:Object.fromEntries(sources),layers:[]}),
    _validate(...args){Style.prototype._validate.call(this,...args);return true;},
  },exits);
  assert.deepEqual(errors,[]);
  map.savvyMallAdjacentPlaceIds=[];
  events.get('pocketmallplaces')();
  assert(JSON.stringify(exits.filter).includes(ownID));
  assert(!JSON.stringify(exits.filter).includes(mallStreetExit4));
  events.get('pocketaccountpins')({placeIds:[]});
  assert.deepEqual(exits.filter,original);
});

test('duplicate authored exits yield to surveyed exit pins without hiding distinct places',()=>{
  const point=metroExitCard(metroExitPlaceId('永春站','4')).point;
  assert.equal(isDuplicateMetroExit({name:'永春站 4 號出口',point}),true);
  assert.equal(isDuplicateMetroExit({name:'永春站 5 號出口',point:[121,25]}),false);
  assert.equal(isDuplicateMetroExit({name:'永春站附近咖啡',point}),false);
  assert.equal(isDuplicateMetroExit({name:'永春站 99 號出口',point}),false);
  assert.equal(isDuplicateMetroExit({name:'商場 4 號出口',point}),false);
  assert.equal(isDuplicateMetroExit({name:'永春站 4 號出口',point:[121,25]}),false);
});
