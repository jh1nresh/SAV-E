import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connectIOSMap, visibleRegion} from '../ios-map.js';
import {placePinType} from '../place-pins.js';
import {nativeExploreVenues} from '../savvy-place-sources.js';

test('native pin selections track the current visible IDs without moving the camera on refresh', t => {
  const buttons = [], messages = [], commands = [];
  const dom = globalThis.document;
  globalThis.document = {createElement: () => ({
    dataset:{}, classList:{toggle() {}},
    addEventListener(type, handler) { this[type] = handler; },
    setAttribute(name, value) { this[name] = value; },
  })};
  t.after(() => { if (dom === undefined) delete globalThis.document; else globalThis.document = dom; });
  class Marker {
    constructor({element}) { this.button = element; buttons.push(element); }
    getElement() { return this.button; }
    setLngLat() { return this; }
    addTo() { return this; }
    remove() { this.button.removed = true; }
  }
  let east = 122;
  const bounds = {getEast: () => east, getWest: () => 120, getNorth: () => 26, getSouth: () => 24};
  const map = {on(event, fn) { this[event] = fn; }, getBounds: () => bounds,
    fitBounds(...args) { commands.push(args); }};
  const bridge = connectIOSMap(map, Marker, {postMessage: value => messages.push(value)});
  const a = {id:'first',name:'Tea',kind:'saved',label:'Tea, saved',point:[121,25]};
  const b = {...a,id:'second',name:'Bookshop',kind:'visited',label:'Bookshop, visited'};
  bridge.update({pins:[a,b],bounds:[120,24,122,26]});
  assert.equal(buttons.length,1);
  assert.equal(buttons[0]['aria-label'],'Tea, saved, Bookshop, visited');
  buttons[0].click({stopPropagation() {}});
  assert.deepEqual(messages.pop(), {event:'select', ids:['first','second']});
  bridge.update({pins:[b]});
  assert.equal(buttons[0].textContent,'Bookshop');
  buttons[0].click({stopPropagation() {}});
  assert.deepEqual(messages.pop(), {event:'select', ids:['second']});
  assert.equal(buttons[0].dataset.kind, 'visited');
  east = 120.5;
  map.moveend();
  assert.deepEqual(messages.pop(), {event:'move',region:[120.25,25,0.5,2]});
  assert.equal(buttons[0].removed,true);
  assert.equal(commands.length,1);
});

test('all native fallback categories have a map icon', () => {
  assert.deepEqual(['food','cafe','bar','attraction','stay','shopping'].map(placePinType),
    ['food','cafe','cafe','culture','stay','shop']);
});

test('wraps both representations of a viewport crossing the date line', () => {
  for (const east of [183,-177]) {
    const box = visibleRegion({getWest:()=>177,getEast:()=>east,getSouth:()=>4,getNorth:()=>8});
    assert.deepEqual(box.region,[-180,6,6,4]);
    for (const lon of [-179,179]) assert.ok(box.contains([lon,6]));
    assert.equal(box.contains([0,6]), false);
  }
});

test('Guide routes update and clear on the same map without moving its camera', () => {
  const sources = new Map(), layers = [];
  const map = {
    on() {},
    getBounds: () => ({getEast: () => 122, getWest: () => 120, getNorth: () => 26, getSouth: () => 24}),
    getSource: id => sources.get(id),
    addSource(id, {data}) { sources.set(id, {data, setData(next) { this.data = next; }}); },
    addLayer(layer) { layers.push(layer); },
  };
  const host = connectIOSMap(map, class {}, {postMessage() {}});
  const route = [[121.53,25.04],[121.54,25.05]];
  host.update({routes: [route]});
  const source = sources.get('savvy-guide-route');
  assert.deepEqual(source.data.features[0].geometry, {type: 'LineString', coordinates: route});
  assert.equal(layers.length, 1);
  host.update({pins: []});
  assert.equal(source.data.features.length, 1);
  host.update({routes: []});
  assert.deepEqual(source.data.features, []);
  host.update({routes: [route]});
  assert.equal(layers.length, 1);
  assert.equal(source.data.features.length, 1);
});

test('iOS map tool changes are forwarded without replacing the map or its viewport', () => {
  const changes = [];
  const map = {
    on() {},
    getBounds: () => ({getEast: () => 122, getWest: () => 120, getNorth: () => 26, getSouth: () => 24}),
  };
  const host = connectIOSMap(map, class {}, {postMessage() {}}, settings => changes.push(settings));
  const presentation = {weather: 'cloudy', metro: true, showsPublicPins: false};
  host.update({presentation});
  host.update({pins: []});
  assert.deepEqual(changes, [presentation]);
  host.update({presentation: {...presentation, weather: 'day', metro: false}});
  assert.equal(changes.length, 2);
});

test('nearby public pins open a single chooser and separate when zoomed in', t => {
  const messages = [], markers = new Set();
  const previousDocument = globalThis.document;
  globalThis.document = {createElement: () => ({
    dataset: {}, classList: {toggle() {}},
    addEventListener(event, handler) { this[event] = handler; }, setAttribute() {},
  })};
  t.after(() => { if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument; });
  class Marker {
    constructor({element}) { this.button = element; }
    getElement() { return this.button; }
    setLngLat() { return this; }
    addTo() { markers.add(this); return this; }
    remove() { markers.delete(this); }
  }
  let pixelsPerDegree = 1_000;
  const map = {
    getBounds: () => ({getEast: () => 122, getWest: () => 120, getNorth: () => 26, getSouth: () => 24}),
    project: ([x,y]) => ({x: (x - 121) * pixelsPerDegree, y: (y - 25) * pixelsPerDegree}),
    on(event, handler) { this[event] = handler; },
  };
  const host = connectIOSMap(map, Marker, {postMessage: message => messages.push(message)});
  const a = {id: 'a', name: 'Tea', label: 'Tea, public posts', kind: 'post', point: [121,25]};
  const b = {id: 'b', name: 'Books', label: 'Books, public posts', kind: 'post', point: [121.012,25.009]};
  host.update({pins: [a,b]});
  assert.equal(markers.size, 1);
  [...markers][0].button.click({stopPropagation() {}});
  assert.deepEqual(messages.pop(), {event: 'select', ids: ['a','b']});
  pixelsPerDegree = 5_000;
  map.moveend();
  assert.equal(markers.size, 2);
});

test('the atlas owns reviewed branch pins, with a separate action for the live native detail', t => {
  const now = Date.parse('2026-11-24T16:40:00Z');
  const clock = t.mock.method(Date, 'now', () => now);
  const rows = [
    {provider: 'apple_maps', providerPlaceID: 'H2710I3F9267923395B', placeId: 'poi/node/2572568042',
      posts: [{platform: 'threads', url: 'https://www.threads.com/@savvysave_/post/DfHb3hGlcDq', expiresAt: '2026-11-25T02:36:47.988Z'}]},
    {provider: 'apple_maps', providerPlaceID: 'H2710I3F98C2A281E4E', placeId: 'savvy/apple_maps/H2710I3F98C2A281E4E',
      posts: [{platform: 'instagram', url: 'https://www.instagram.com/p/CxSV8d9PJum/', expiresAt: '2026-11-25T15:22:04.874Z'}]},
  ];
  const venues = nativeExploreVenues(rows, now, Infinity);
  const markers = new Set(), messages = [];
  const previousDocument = globalThis.document;
  const button = () => ({dataset: {}, classList: {toggle() {}}, setAttribute() {},
    addEventListener(type, handler) { this[type] = handler; }});
  globalThis.document = {createElement: button};
  t.after(() => { if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument; });
  class Marker {
    constructor({element}) { this.button = element; }
    getElement() { return this.button; }
    setLngLat() { return this; }
    addTo() { markers.add(this.button); return this; }
    remove() { markers.delete(this.button); }
  }
  const map = {
    getBounds: () => ({getEast: () => 122, getWest: () => 120, getNorth: () => 26, getSouth: () => 24}),
    project: ([x,y]) => ({x:x*10_000, y:y*10_000}), fire() {}, on(event, handler) { this[event] = handler; },
  };
  const detail = button();
  const bridge = connectIOSMap(map, Marker, {postMessage: value => messages.push(value)}, undefined, {venues, button:detail});
  t.after(() => map.remove());
  const ximen = {id: 'public:apple_maps:H2710I3F9267923395B', name: '阿宗麵線', label: '阿宗麵線', kind:'post', point: [121.5077,25.0433]};
  const coffee = {...ximen, id: 'public:apple_maps:H2710I3F98C2A281E4E', name: 'Yokoso Coffee Stand 民生店', point: [121.55633127539062,25.058198259765632]};
  const remote = {...ximen, id:'public:apple_maps:RemoteOnly'}; // Identical label and coordinates do not make an identity.
  bridge.update({pins:[ximen, coffee, remote]});
  assert.deepEqual([...markers].map(marker => marker.placeIDs), [[remote.id]]);
  map.pocketplacechange({placeId:'poi/node/4194681689'}); // 阿宗麵線 忠孝店
  assert.equal(detail.hidden, true);
  map.pocketplacechange({placeId:rows[0].placeId});
  assert.equal(detail.hidden, false);
  assert.deepEqual(messages, []);
  detail.click();
  assert.deepEqual(messages.pop(), {event:'select', ids:[ximen.id]});
  map.pocketplacechange({placeId:rows[1].placeId});
  detail.click();
  assert.deepEqual(messages.pop(), {event:'select', ids:[coffee.id]});
  bridge.update({presentation:{showsPublicPins:false}, pins:[{...ximen, kind:'saved'}, {...coffee, kind:'shared'}]});
  assert.equal(detail.hidden, true);
  assert.deepEqual([...markers].map(marker => marker.dataset.kind).sort(), ['saved','shared']);
  clock.mock.mockImplementation(() => Date.parse('2026-11-25T04:00:00Z'));
  bridge.update({presentation:{showsPublicPins:true}, pins:[ximen,coffee]});
  assert.deepEqual([...markers].map(marker => marker.placeIDs), [[ximen.id]]);
  map.pocketplacechange({placeId:rows[0].placeId});
  assert.equal(detail.hidden, true);
});

test('camera replay follows presentation, supersedes bounds, and reports the acknowledged pose', () => {
  const calls = [], messages = [];
  const map = {
    on(type, fn) { this[type] = fn; }, fitBounds() { calls.push('bounds'); },
    fire(event) { calls.push(event); }, jumpTo(camera) { calls.push(camera); },
    getBounds: () => ({getEast: () => 122, getWest: () => 120, getNorth: () => 26, getSouth: () => 24}),
    getCenter: () => ({lng: 481.5,lat:25.03}), getZoom: () => 17.5, getBearing: () => -12, getPitch: () => 47,
  };
  const camera = [121.5,25.03,17.5,-12,47];
  const bridge = connectIOSMap(map, class {}, {postMessage: message => messages.push(message)}, () => calls.push('presentation'));
  bridge.update({presentation:{metro:true}, viewportSerial:3, bounds:null, restoreCamera:camera});
  assert.deepEqual(calls, ['presentation','pocketcamerarestore',{center:[121.5,25.03],zoom:17.5,bearing:-12,pitch:47}]);
  map.moveend();
  assert.deepEqual(messages, [{event:'move', camera, viewportSerial:3, region:[121,25,2,2]}]);
  bridge.update({bounds:[120,24,122,26], restoreCamera:[121,NaN,0,0,0]});
  assert.equal(calls.at(-1), 'bounds');
});

test('an exact saved branch shares its source card, bookmark and thumbnail, and clears both layers on account change', t => {
  const venueKey='public:apple_maps:branch36';
  const otherKey='public:apple_maps:branch47';
  const placeId='poi/node/3007181095', otherId='poi/node/3007181096';
  const element=()=>({dataset:{},children:[],classList:{flags:new Set(),add(name){this.flags.add(name);},toggle(name,on){if(on)this.flags.add(name);else this.flags.delete(name);}},
    setAttribute(key,value){this[key]=value;},addEventListener(type,fn){this[type]=fn;},
    append(...nodes){this.children.push(...nodes);},replaceChildren(...nodes){this.children=nodes;},
    getContext(){return new Proxy({},{get:()=>()=>{}});},remove(){this.removed=true;}});
  const prevDocument=globalThis.document,prevPath=globalThis.Path2D;
  globalThis.document={createElement:element};globalThis.Path2D=class{};
  t.after(()=>{if(prevDocument===undefined)delete globalThis.document;else globalThis.document=prevDocument;
    if(prevPath===undefined)delete globalThis.Path2D;else globalThis.Path2D=prevPath;});
  const markers=new Set(), filterChanges=[], selections=[], opened=[];
  class Marker {
    constructor({element}){this.button=element;}
    setLngLat(point){this.point=point;return this;}
    addTo(){markers.add(this);return this;} remove(){markers.delete(this);} getElement(){return this.button;}
  }
  const map={on(type,fn){this[type]=fn;},fire(type,detail){filterChanges.push([type,detail]);},
    getBounds:()=>({getEast:()=>122,getWest:()=>120,getSouth:()=>24,getNorth:()=>26}),
    project:([x,y])=>({x:x*1e6,y:y*1e6})};
  const button=element(),friendButton=element(),venues=new Map([[venueKey,{placeId,expiresAt:Date.now()+300_000}],
    [otherKey,{placeId:otherId,expiresAt:Date.now()+300_000}]]);
  const bridge=connectIOSMap(map,Marker,{postMessage:m=>selections.push(m)},undefined,{venues,button,friendButton,open:p=>opened.push(p)});
  t.after(()=>map.remove());
  const a={id:'saved/36',publicVenueID:venueKey,name:'美觀園',label:'美觀園 36 號，已收藏',point:[121.5065,25.0434],kind:'saved',category:'restaurant',isSaved:true};
  const post={...a,kind:'post',id:venueKey,point:[121.50655,25.04345],isSaved:false,label:'美觀園 36 號，公開貼文'};
  const other={...post,id:otherKey,publicVenueID:otherKey,point:[121.5068,25.0436]};
  const unknown={...a,id:'unconfirmed',publicVenueID:null,point:[121.507,25.044],photoURL:'https://unrelated.example/thumbnail.jpg'};
  const friend={...a,id:'friend/share36',kind:'shared',label:'朋友分享美觀園 36 號'};
  bridge.update({pins:[a,post,friend,other,unknown]});
  assert.equal(markers.size,2);
  const marker=[...markers].find(m=>m.button.placeIDs.includes(a.id)).button;
  const bare=[...markers].find(m=>m.button.placeIDs.includes(unknown.id)).button;
  assert.match(marker.children[0].children[1].src,/mei-36\.jpg$/);
  assert.equal(marker.children[0].children[2].className,'ios-pin-bookmark');
  assert.equal(bare.children[0].children.some(c=>c.src),false);
  assert.deepEqual(filterChanges.at(-1),['pocketaccountpins',{placeIds:[placeId]}]);
  marker.click({stopPropagation(){}});
  assert.equal(opened.at(-1).placeId,placeId);
  map.pocketplacechange({placeId});
  assert.ok(marker.classList.flags.has('ios-pin-open'));
  assert.equal(button.textContent,'查看我的收藏');
  assert.equal(friendButton.hidden,false);friendButton.click();
  assert.deepEqual(selections.pop(),{event:'select',ids:[friend.id]});
  assert.equal(marker.children[0].children[3].className,'ios-pin-friend');
  button.click();
  assert.deepEqual(selections.pop(),{event:'select',ids:[a.id]});
  bridge.update({pins:[a],presentation:{showsPublicPins:false}});
  assert.deepEqual(filterChanges.at(-1)[1].placeIds,[placeId,otherId]);
  assert.equal(friendButton.hidden,true);
  map.pocketplacechange({placeId:null});
  assert.ok(!marker.classList.flags.has('ios-pin-open'));
  marker.click({stopPropagation(){}});
  assert.equal(opened.at(-1).placeId,placeId);
  map.pocketplacechange({placeId});
  assert.equal(button.textContent,'查看我的收藏');
  button.click();
  assert.deepEqual(selections.pop(),{event:'select',ids:[a.id]});
  bridge.update({pins:[],presentation:{showsPublicPins:true}});
  assert.equal(markers.size,0);
  assert.deepEqual(filterChanges.at(-1)[1].placeIds,[]);
  bridge.update({pins:[{...a,selected:true}]});
  const art=[...markers][0].button.children[0];
  assert.match(art.children[1].src,/mei-36\.jpg$/);
  art.children[1].onerror();
  assert.equal(art.children[1].removed,true);
  assert.ok(art.children[0].getContext);
  const samePointOtherBranch={...other,point:a.point,id:'search-47',kind:'search',selected:true};
  bridge.update({pins:[a,samePointOtherBranch]});
  const group=[...markers][0].button;
  assert.equal(markers.size,1);
  assert.equal(group.dataset.kind,'group');
  assert.equal(group.classList.flags.has('is-saved'),false);
  assert.equal(group.children[1].textContent,'2 個地點');
  assert.equal(group.children[0].children.length,1);
  group.click({stopPropagation(){}});
  assert.deepEqual(selections.pop(),{event:'select',ids:[a.id,samePointOtherBranch.id]});
});
