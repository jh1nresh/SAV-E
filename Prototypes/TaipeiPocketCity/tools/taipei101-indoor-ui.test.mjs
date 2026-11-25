import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {addTaipei101Indoor,floorData,indoorCamera,insideMall} from '../taipei101-indoor.js';
import {addOfficialFloorGuide} from '../taipei101-floor-guide.js';
import {taipei101Indoor as venue} from '../taipei101-indoor-data.js';
import {mallAdjacentTenants} from '../taipei101-mall-tenants.js';
import {officialFloorDirectory as directory} from '../taipei101-directory.js';
import {Style,MercatorCoordinate} from '../assets/maplibre-gl.mjs';
import {SurveyLayer} from '../survey-layer.js';
import {connectIOSMap} from '../ios-map.js';

class Element {
  children=[]; attrs={};dataset={};style={};hidden=false; handlers=new Map();
  classList={add(){},remove(){},toggle(){}};
  append(...items){this.children.push(...items);}
  prepend(item){this.children.unshift(item);}
  replaceChildren(){this.children=[];}
  setAttribute(k,v){this.attrs[k]=v;}
  getAttribute(k){return this.attrs[k];}
  addEventListener(k,f){
    const first=this.handlers.get(k);
    this.handlers.set(k,first?event=>{first(event);f(event);}:f);
  }
  dispatchEvent(event){this.handlers.get(event.type)?.(event);}
  removeEventListener(k){this.handlers.delete(k);}
  click(){this.handlers.get('click')?.({stopPropagation(){}});}
  focus(){this.focused=true;} remove(){}
  querySelectorAll(){return this.children;}
  querySelector(k){return this.children.find(b=>b.getAttribute('aria-pressed')==='true');}
}
const mall=[121.56446,25.034];
test('mall camera keeps bearing, and the official directory supplies floor names without invented points',()=>{
  assert(insideMall(mall,venue.footprint.coordinates[0]));
  assert(!insideMall([121.56865,25.0396],venue.footprint.coordinates[0]));
  assert.deepEqual(indoorCamera(mall,46,18.95),{center:mall,bearing:46,zoom:18.95,pitch:0});
  assert.deepEqual(floorData(venue,'2F').features,[]);
  assert(directory['2F'].length>0);
  for(const {label,features} of venue.levels)assert(features.features.every(f=>f.properties.level===label));
});
test('zoom in, expand, select, inspect, leave and re-enter the same map',async t=>{
  const doc=globalThis.document;
  globalThis.document={createElement:tag=>Object.assign(new Element(),{tag}),createElementNS:()=>new Element()};
  t.after(()=>{if(doc===undefined)delete globalThis.document;else globalThis.document=doc;});
  const stage=new Element(),nav=new Element(),els={};
  for(const key of ['[data-floor-toggle]','[data-floor-list]','[data-floor-exit]','details','[data-directory-summary]','[data-directory]','[data-floor-note]'])els[key]=new Element();
  els['[data-floor-list]'].hidden=true;nav.hidden=true;
  nav.querySelector=k=>els[k];stage.querySelector=()=>nav;
  const container=new Element(),canvas=new Element(),events={},sources=new Map(),layers=[],filters=new Map(),cards=[],cut=[];
  const zoomFade=['interpolate',['linear'],['zoom'],17.8,0,18.35,.98];
  const outdoorLayerTypes={'city170-poi-labels':'symbol','city170-poi-dots':'circle','taipei-place-neighbors':'circle','city170-road-names':'symbol'};
  const paint=new Map([
    ['city170-poi-labels:text-color','#954c35'],
    ['city170-poi-dots:circle-opacity',zoomFade],
    ['city170-poi-dots:circle-stroke-opacity',zoomFade],
    ['taipei-place-neighbors:circle-opacity',0],
    ['city170-road-names:text-color','#4c4b43'],
  ]);
  const outdoorPaint=new Map(paint);
  const loc={lng:mall[0],lat:mall[1],toArray(){return [this.lng,this.lat];}};
  let z=16.7,pitch=47,hit,lastJump;
  canvas.getBoundingClientRect=()=>({left:0,top:0});
  const map={isMoving:()=>false,getCanvasContainer:()=>container,getCanvas:()=>canvas,getCenter:()=>loc,getZoom:()=>z,getPitch:()=>pitch,getBearing:()=>76,
    getBounds:()=>({getWest:()=>121.562,getEast:()=>121.569,getSouth:()=>25.032,getNorth:()=>25.037}),
    project:([lng,lat])=>({x:lng*2,y:lat*2}),unproject:()=>loc,
    getLayer:id=>outdoorLayerTypes[id]?{type:outdoorLayerTypes[id]}:undefined,getFilter:()=>['has','name'],setFilter:(id,f)=>filters.set(id,f),
    getPaintProperty:(id,prop)=>paint.get(id+':'+prop),
    setPaintProperty:(id,prop,value)=>value==null?paint.delete(id+':'+prop):paint.set(id+':'+prop,value),
    addSource:(id,spec)=>sources.set(id,{...spec,setData(data){this.data=data;}}),getSource:id=>sources.get(id),
    addLayer:l=>layers.push(l),
    setLayoutProperty:(id,prop,value)=>{layers.find(layer=>layer.id===id).layout[prop]=value;},
    on:(e,f)=>{const prev=events[e];events[e]=prev?(event)=>{prev(event);f(event);}:f;},
    fire:(e,data)=>events[e]?.(data),off:()=>{},jumpTo:(c,eventData)=>{pitch=c.pitch;z=c.zoom??z;lastJump={c,eventData};},
    queryRenderedFeatures:()=>hit?[hit]:[]};
  const markers=new Set();
  class Marker{
    constructor({element}){this.el=element;}
    setLngLat(){return this;} addTo(){markers.add(this);return this;} remove(){markers.delete(this);} getElement(){return this.el;}
  }
  const tenant=floorData(venue,'B1').features.find(f=>f.id==='node/5492157852');
  const [dinTaiFung,apple]=mallAdjacentTenants;
  const canonical='poi/'+tenant.id,venueKey='public:apple_maps:tenant-fixture';
  const shared={id:'friend/shared-tenant',name:tenant.properties.name,label:'好友分享',kind:'shared',point:tenant.geometry.coordinates,publicVenueID:venueKey};
  let panel;
  const bridge=connectIOSMap(map,Marker,{postMessage(){}},undefined,{
    button:new Element(),venues:new Map([[venueKey,{placeId:canonical,expiresAt:Date.now()+30000}]])
  },{floorEvents:stage,visiblePin:(...args)=>panel?.isPinVisible(...args)??true});
  const sharedIsVisible=()=>[...markers].some(m=>m.getElement().placeIDs?.includes(shared.id));
  t.after(()=>events.remove());
  bridge.update({pins:[shared]}); // Coverage already exists before the indoor controller or its sources.
  assert(sharedIsVisible());assert.deepEqual(map.savvyAccountPlaceIds,[canonical]);
  const selected=[];stage.addEventListener('mall101-floor',e=>selected.push(e.detail.floor));
  panel=addTaipei101Indoor(map,{stage,Marker,startFloor:'B1',setCutaway:v=>cut.push(v),closePlace(){},openPlace:p=>cards.push(p),
    load:async()=>({...venue,directory})});
  panel.setNames(false); // Preference changed while lazy assets were still loading.
  await Promise.resolve();await Promise.resolve();
  const names=layers.find(layer=>layer.id==='taipei101-indoor-names');
  assert.equal(names.layout.visibility,'none');
  panel.setNames(true);assert.equal(names.layout.visibility,'visible');
  panel.setNames(false);assert.equal(names.layout.visibility,'none');
  assert.notEqual(layers.find(layer=>layer.id==='taipei101-indoor-dots').layout?.visibility,'none');
  assert.deepEqual(panel.state(),{ready:true,active:false,floor:null});
  assert.equal(filters.get('city170-poi-labels')[2][1][0],'within');
  assert.deepEqual(paint,outdoorPaint);
  const outside=[121.57,25.04];
  assert(!panel.isContextPin(outside));
  const source=sources.get('taipei101-indoor-places');
  const plan=sources.get('taipei101-wayfinding');
  const planLabels=()=>plan.data.features.map(feature=>feature.properties.name);
  const validator={version:8,glyphs:'https://localhost/{fontstack}/{range}.pbf',sources:Object.fromEntries(sources),layers:[]};
  for(const layer of layers){
    const errors=[];
    Style.prototype.addLayer.call({_checkLoaded(){},getLayer(){},fire(e){errors.push(e.error.message);},serialize:()=>validator,
      _validate(...args){Style.prototype._validate.call(this,...args);return true;}},layer);
    assert.deepEqual(errors,[],layer.id);
  }
  z=19;events.moveend();assert.equal(panel.state().floor,'B1');
  assert(panel.isContextPin(outside));assert(!panel.isContextPin(mall));
  assert.equal(paint.get('city170-poi-labels:text-color'),'#645d50');
  assert.deepEqual(paint.get('city170-poi-labels:icon-opacity'),['*',1,.36]);
  assert.deepEqual(paint.get('city170-poi-dots:circle-opacity'),
    ['interpolate',['linear'],['zoom'],17.8,['*',0,.36],18.35,['*',.98,.36]]);
  assert.equal(paint.get('taipei-place-neighbors:circle-opacity'),0);
  assert.equal(paint.get('city170-road-names:text-color'),'#4c4b43');
  assert(planLabels().includes('美食廣場'));assert.match(els['[data-floor-note]'].textContent,/捷運 4 號出口/);
  assert.equal(els['[data-floor-note]'].hidden,false);
  assert(sharedIsVisible());assert(!source.data.features.some(f=>f.id===tenant.id));assert.equal(pitch,0);assert.equal(nav.hidden,false);
  assert.equal(els['[data-floor-list]'].hidden,true);
  els['[data-floor-toggle]'].click();assert.equal(els['[data-floor-list]'].hidden,false);
  const choose=label=>els['[data-floor-list]'].children.find(el=>el.dataset.floor===label).click();
  choose('B1');assert.equal(els['[data-floor-list]'].hidden,true);
  assert.equal(els['[data-directory-summary]'].textContent,'本層店家（'+directory.B1.length+'）');
  assert(sharedIsVisible());
  const pointIds=()=>source.data.features.map(f=>f.id);
  assert(!pointIds().includes(tenant.id));
  assert(pointIds().includes('node/7004289008')); // Sawadee shares the floor, not this pin.
  assert(pointIds().includes(dinTaiFung.id));
  assert.deepEqual(map.savvyMallAdjacentPlaceIds,mallAdjacentTenants.map(f=>'poi/'+f.id));
  choose('1F');assert(!sharedIsVisible());
  assert(pointIds().includes(apple.id));assert(!pointIds().includes(dinTaiFung.id));
  assert(panel.isPinVisible(apple.geometry.coordinates,'poi/'+apple.id));
  assert(!panel.isStreetPinVisible(apple.geometry.coordinates,'poi/'+apple.id));
  assert(!panel.isStreetPinVisible(dinTaiFung.geometry.coordinates,'din-tai-fung'));
  assert(panel.isStreetPinVisible(outside,undefined));
  assert(!panel.isPinVisible(dinTaiFung.geometry.coordinates,'poi/'+dinTaiFung.id));
  assert.equal(paint.get('city170-poi-labels:text-color'),'#645d50');
  assert(planLabels().includes('松智路入口'));assert(planLabels().includes('信義南'));
  assert(!planLabels().includes('美食廣場'));
  choose('B1');assert(sharedIsVisible());assert(!pointIds().includes(tenant.id));
  bridge.update({pins:[]});assert(!sharedIsVisible());assert(pointIds().includes(tenant.id));
  assert.equal(source.data.features.length,floorData(venue,'B1').features.length+1);
  hit=source.data.features.find(f=>f.properties.kind==='shop');
  container.handlers.get('click')({target:canvas,clientX:8,clientY:9,stopImmediatePropagation(){}});
  assert.equal(cards[0].placeId,'poi/'+hit.id);assert.equal(cards[0].name,hit.properties.name);assert.match(cards[0].categoryLabel,/B1/);
  const shopList=els['[data-directory]'];
  const locatedRow=shopList.children.find(row=>row.children[0].textContent===tenant.properties.name);
  const [mapButton,officialLink]=locatedRow.children;
  assert.equal(mapButton.tag,'button');assert.equal(mapButton.textContent,tenant.properties.name);
  assert.equal(officialLink.href,tenant.properties.floorSourceUrl);
  assert.equal(shopList.children.filter(row=>row.children.some(el=>el.tag==='button')).length,2);
  const dinTaiFungRow=shopList.children.find(row=>row.children[0].textContent==='鼎泰豐');
  assert.deepEqual(dinTaiFungRow.children.map(el=>el.tag),['button','a']);
  dinTaiFungRow.children[0].click();
  assert(insideMall(lastJump.c.center,venue.footprint.coordinates[0]));
  assert.deepEqual(cards.at(-1).point,dinTaiFung.geometry.coordinates);
  assert.equal(cards.at(-1).placeId,'poi/'+dinTaiFung.id);
  [loc.lng,loc.lat]=dinTaiFung.geometry.coordinates;
  let stopped=false;
  const original=dinTaiFung.geometry.coordinates;
  hit={...dinTaiFung,geometry:{type:'Point',coordinates:[original[0]+.0000005,original[1]]}};
  const tap=()=>container.handlers.get('click')({target:canvas,clientX:8,clientY:9,stopImmediatePropagation(){stopped=true;}});
  tap();assert(stopped);assert.equal(cards.at(-1).placeId,'poi/'+dinTaiFung.id);
  assert.deepEqual(cards.at(-1).point,original);
  assert.equal(cards.at(-1).category,'restaurant');
  hit=tenant;stopped=false;tap();assert(!stopped);
  hit=tenant;
  [loc.lng,loc.lat]=mall;
  const startingZoom=z;
  els.details.open=true;mapButton.click();
  assert.equal(els.details.open,false);assert.equal(els['[data-directory-summary]'].focused,true);
  assert.deepEqual(lastJump,{c:indoorCamera(tenant.geometry.coordinates,76,startingZoom),eventData:{pocketPlaceReveal:true}});
  assert.deepEqual(cards.at(-1).point,tenant.geometry.coordinates);
  assert.equal(cards.at(-1).placeId,canonical);assert.equal(cards.at(-1).category,'restaurant');
  assert.equal(cards.at(-1).indoorFloor,'B1');assert.equal(panel.state().floor,'B1');
  assert(!panel.isPinVisible(hit.geometry.coordinates,'account-id'));
  assert(panel.isPinVisible(hit.geometry.coordinates,'poi/'+hit.id));
  assert(panel.isPinVisible([121.57,25.04],'account-id'));
  choose('2F');assert.equal(source.data.features.length,0);assert(els['[data-directory]'].children.length>1);
  assert(els['[data-directory]'].children.every(row=>row.children.every(el=>el.tag==='a')));
  assert.equal(plan.data.features.length,0);assert.equal(els['[data-floor-note]'].hidden,true);
  els['[data-floor-exit]'].click();assert.equal(panel.state().active,false);assert.equal(pitch,47);
  assert.deepEqual(map.savvyMallAdjacentPlaceIds,[]);
  assert(panel.isPinVisible(dinTaiFung.geometry.coordinates,'poi/'+dinTaiFung.id));
  assert(panel.isStreetPinVisible(dinTaiFung.geometry.coordinates,'din-tai-fung'));
  assert.deepEqual(paint,outdoorPaint);assert(!panel.isContextPin(outside));
  assert.equal(plan.data.features.length,0);
  assert.equal(nav.hidden,true);assert.deepEqual(cut,[true,false]);assert.deepEqual(selected,['B1','B1','1F','B1','2F',null]);
  z=19;events.moveend();assert.equal(panel.state().active,false);
  z=16;events.moveend();z=19;events.moveend();assert.equal(panel.state().floor,'1F');
  map.savvySavedOnly=true;panel.refreshVisibility();assert.equal(panel.state().active,false);
  assert.deepEqual(paint,outdoorPaint);
  assert(panel.isPinVisible(hit.geometry.coordinates,'account-id'));
  map.savvySavedOnly=false;panel.refreshVisibility();assert(panel.state().active);
  loc.lng=121.57;events.moveend({pocketPlaceReveal:true});assert(panel.state().active);loc.lng=mall[0];
  const searched={name:hit.properties.name,id:'poi/'+hit.id,point:hit.geometry.coordinates};
  panel.openSearchPlace(searched);assert.equal(panel.state().floor,'B1');
  assert.equal(cards.at(-1).name,searched.name);assert.match(cards.at(-1).categoryLabel,/B1/);
  panel.openSearchPlace({...searched,id:'unknown'});
  assert.equal(panel.state().active,false);assert.equal(cards.at(-1).id,'unknown');
  assert(panel.isPinVisible(searched.point,'account-id'));
  loc.lng=121.57;events.moveend();loc.lng=mall[0];events.moveend();assert(panel.state().active);
  loc.lng=121.57;events.moveend();assert.equal(panel.state().active,false);assert.equal(pitch,47);
  [loc.lng,loc.lat]=apple.geometry.coordinates;
  panel.openSearchPlace({name:apple.properties.name,id:'poi/'+apple.id,point:apple.geometry.coordinates});
  assert.equal(panel.state().floor,'1F');assert.equal(cards.at(-1).placeId,'poi/'+apple.id);
  assert(insideMall(lastJump.c.center,venue.footprint.coordinates[0]));
});

test('adjacent tenant identities retain the public map coordinates and match a unique floor directory row',()=>{
  const root=process.env.POCKET_TAIPEI_DATA;
  const publicPlaces=root?JSON.parse(gunzipSync(readFileSync(root+'/city-place-index.json.gz'))).features:null;
  const ring=venue.footprint.coordinates[0];
  for(const tenant of mallAdjacentTenants){
    const {level,floorSourceUrl,branchUrl}=tenant.properties;
    assert(!insideMall(tenant.geometry.coordinates,ring));
    assert.equal(directory[level].filter(row=>row.url===floorSourceUrl).length,1);
    assert(branchUrl.startsWith('https://'));
    if(publicPlaces){
      const original=publicPlaces.find(f=>f.id==='poi/'+tenant.id);
      assert.deepEqual(tenant.geometry,original.geometry);
      assert.equal(tenant.properties.name,original.properties.name);
      assert.equal(tenant.properties.category,original.properties.category);
      assert.equal(tenant.properties.url,original.properties.url);
    }
  }
});

test('cutaway uses the real shopping wing in world metres without requiring the ornament asset',()=>{
  const mesh=new SurveyLayer({},()=>{},null,false,[],null,null);
  const ring=venue.footprint.coordinates[0].map(p=>MercatorCoordinate.fromLngLat(p));
  mesh.setMallCutaway(ring);
  const {mx,my,m,ring:positions}=mesh.mallMask;
  const pairs=[];for(let i=0;i<positions.length;i+=2)pairs.push([positions[i],positions[i+1]]);
  const hits=lnglat=>{const p=MercatorCoordinate.fromLngLat(lnglat);return insideMall([(p.x-mx)/m,(my-p.y)/m],pairs);};
  assert(hits(mall));
  assert(!hits([121.5648093,25.0336696])); // tower outside the shopping wing
  mesh.setEnabled(false);mesh.setMallCutaway(null);assert.equal(mesh.mallMask,null);
});

test('bundled iOS mode never constructs or requests an external floor-guide image',()=>{
  const stage={append(){assert.fail('remote guide mounted in bundled mode');}};
  addOfficialFloorGuide(stage,{allowRemoteImages:false});
});
