import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {asphalt as asphaltPaint} from '../taipei-asphalt.js';
import {streetDistricts} from '../taipei-street-districts.js';
import {plotOverlaps} from '../authored-footprint.js';
import {unpackDistrictGround,addDistrictStreetGround,districtStreetMarkings} from '../xinyi-street-ground.js';

const bytes=await readFile(new URL('../assets/xinyi-street-ground.json.gz',import.meta.url));
const ground=unpackDistrictGround(JSON.parse(gunzipSync(bytes)));
const byKind=kind=>ground.features.filter(f=>f.properties.kind===kind);
function inRing([x,y],ring){
  let inside=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const a=ring[i],b=ring[j];
    if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;
  }
  return inside;
}
function contains(feature,point){
  const [outer,...holes]=feature.geometry.coordinates;
  return inRing(point,outer)&&!holes.some(ring=>inRing(point,ring));
}

test('the four Yanchang Road OSM ways share continuous asphalt through three 170 m cell boundaries',()=>{
  const roads=byKind('road');
  const points=[
    // Representative portions of ways 453793968, 555525974, 1125954424 and 1290438178.
    [121.5610884,25.0450255],[121.5577547,25.0449922],[121.5591933,25.0450772],[121.5593373,25.0451296],
  ];
  assert.ok(points.every(point=>roads.some(road=>contains(road,point))));
  const seams=[
    [[121.5583414,25.0450234],[121.5583513,25.0450240],[121.5583612,25.0450246]],
    [[121.5600264,25.0450691],[121.5600363,25.0450688],[121.5600461,25.0450684]],
    [[121.5617108,25.0449858],[121.5617206,25.0449844],[121.5617304,25.0449830]],
  ];
  for(const seam of seams)assert.ok(roads.some(road=>seam.every(point=>contains(road,point))));
});

test('the compact art contains valid polygons, district paths, and the Songyan pond stays clear',()=>{
  const counts=Object.fromEntries(['road','walk','path','kerb'].map(k=>[k,byKind(k).length]));
  assert.ok(counts.road>30&&counts.walk>2000&&counts.path>190&&counts.kerb>900);
  for(const {geometry} of ground.features){
    for(const ring of geometry.type==='Polygon'?geometry.coordinates:[geometry.coordinates]){
      assert.ok(ring.length>=(geometry.type==='Polygon'?4:2));
      assert.ok(ring.every(([lng,lat])=>lng>121.552&&lng<121.593&&lat>25.008&&lat<25.050));
      if(geometry.type==='Polygon')assert.deepEqual(ring[0],ring.at(-1));
    }
  }
  for(const kind of ['road','walk','path'])assert.ok(!byKind(kind).some(f=>contains(f,[121.56231,25.04366])));
  assert.ok(byKind('walk').some(f=>contains(f,[121.5618274,25.043428])));
  assert.ok(byKind('path').some(f=>contains(f,[121.5813145,25.017794])));
});

const songshanBytes=await readFile(new URL('../assets/songshan-street-ground.json.gz',import.meta.url));
const songshan=unpackDistrictGround(JSON.parse(gunzipSync(songshanBytes)));
const songshanRoads=songshan.features.filter(f=>f.properties.kind==='road');

test('surveyed Shimin Boulevard meets on both sides of four district border crossings',()=>{
  // One metre to either side of each official border intersection on these at-grade OSM ways.
  const pairs=[
    // 市民大道四段, 51420787 and 1125954418. 市民大道六段, 386557631 and 802123174.
    [[121.5577299,25.0452194],[121.5577491,25.0452249]],
    [[121.5577199,25.0450037],[121.5577386,25.0450106]],
    [[121.5793506,25.0494941],[121.5793706,25.0494941]],
    [[121.5713969,25.0494597],[121.5713770,25.0494577]],
  ];
  const allRoads=[...songshanRoads,...byKind('road')];
  for(const [ss,xy] of pairs){
    assert.ok(songshanRoads.some(road=>contains(road,ss)));
    assert.ok(byKind('road').some(road=>contains(road,xy)));
    // Sample the two-metre crossing at centimetre intervals. Individual
    // district masks are quantized to ~0.1 m; their physical surfaces must meet.
    for(let i=0;i<=220;i++){
      const point=ss.map((v,j)=>v+(xy[j]-v)*i/220);
      assert.ok(allRoads.some(road=>contains(road,point)),'Shimin Boulevard gap at '+point);
    }
  }
});

test('Songshan public surfaces leave the isolated elevated carriageway, apron, taxiway and runway clear',()=>{
  const surfaces=songshan.features.filter(f=>f.geometry.type==='Polygon');
  for(const point of [[121.5504519,25.0654125],[121.5547623,25.0656975],
    [121.5546655,25.0656785],[121.5525072,25.0696005]]){
    assert.ok(!surfaces.some(f=>contains(f,point)));
  }
  // Elevated 市民大道 OSM 48776359, away from a surface road.
  assert.ok(!songshanRoads.some(f=>contains(f,[121.5545488,25.0444231])));
  assert.ok(songshanRoads.length>=9);
  assert.deepEqual(Object.fromEntries(['walk','path','kerb'].map(kind=>
    [kind,songshan.features.filter(f=>f.properties.kind===kind).length])),{walk:1421,path:26,kerb:943});
});

test('the full 60 m flat-ended runway excludes every decoded ground polygon and kerb segment',async()=>{
  const source=JSON.parse(await readFile(new URL('../scripts/songshan-runway.geojson',import.meta.url)));
  assert.equal(source.id,'way/678331011');
  assert.equal(source.properties.tags.width,'60');
  const bounds=ring=>ring.reduce(([w,s,e,n],[x,y])=>
    [Math.min(w,x),Math.min(s,y),Math.max(e,x),Math.max(n,y)],[Infinity,Infinity,-Infinity,-Infinity]);
  const runway={footprint:source.geometry,bounds:bounds(source.geometry.coordinates[0])};
  for(const {geometry,properties} of songshan.features){
    const coords=geometry.coordinates;
    if(geometry.type==='Polygon'){
      assert.ok(!plotOverlaps(runway,bounds(coords[0]),coords),properties.kind+' intersects the runway');
      continue;
    }
    for(let i=1;i<coords.length;i++){
      // Closing a two-point segment gives it zero area and checks both vertices
      // and the entire line against the full runway polygon.
      const segment=[coords[i-1],coords[i],coords[i-1]];
      assert.ok(!plotOverlaps(runway,bounds(segment),[segment]),'kerb intersects the runway');
    }
  }
});

function verifyMarkingColors(paint,ready){
  assert.equal(paint[0],'case');assert.deepEqual(paint.slice(2),['#f0dfc0','#fff0d4']);
  const [allOperator,has,...conditions]=paint[1];
  assert.equal(allOperator,'all');assert.deepEqual(has,['has','districtStreetMask']);
  const missing=streetDistricts.filter(d=>!ready.includes(d.mask));
  assert.deepEqual(conditions,missing.map(d=>
    ['==',['%',['floor',['/',['number',['get','districtStreetMask'],0],d.mask]],2],0]));
}

const baseOrder=['street-songshan-road','taipei101-single-ground','atlas-shadows',
  'city170-prepared-lane','city170-prepared-crossing','survey','street-songshan-road-labels'];
const grounds=['xinyi-street-ground','songshan-street-ground'];
function groundMap(outlines=[]){
  // Isolate these two districts for the connection tests. Dedicated citywide tests supply all polygons.
  const outside={type:'Polygon',coordinates:[[[0,0],[1,0],[1,1],[0,1],[0,0]]]};
  outlines=[...outlines,...streetDistricts.slice(2).filter(d=>!outlines.some(f=>f.properties.name===d.name))
    .map(d=>({properties:{name:d.name},geometry:outside}))];
  const events=new Map(),sources=new Map(),layers=new Map(),images=new Map(),paints=new Map();
  const order=baseOrder.slice(),view={zoom:15,box:[[121.52,25.01],[121.53,25.02]]};
  const map={on:(id,cb)=>events.set(id,cb),off:id=>events.delete(id),getZoom:()=>view.zoom,
    getBounds:()=>({toArray:()=>view.box}),getStyle:()=>({layers:order.map(id=>({id})),
      sources:{districts:{data:{features:outlines}}}}),getLayer:id=>order.includes(id),
    getPaintProperty:(id)=>paints.get(id)??'#fff0d4',setPaintProperty:(id,prop,value)=>paints.set(id,value),
    addSource:(id,src)=>{assert.ok(!sources.has(id));sources.set(id,src);},
    removeLayer:id=>{assert.ok(layers.delete(id));order.splice(order.indexOf(id),1);},
    removeSource:id=>assert.ok(sources.delete(id)),
    addImage:(id,image)=>{assert.ok(!images.has(id));images.set(id,image);},
    addLayer:(layer,before)=>{assert.ok(!layers.has(layer.id));layers.set(layer.id,layer);
      assert.ok(order.includes(before));order.splice(order.indexOf(before),0,layer.id);}};
  return {map,events,sources,layers,images,paints,order,view};
}

test('Songshan and Xinyi load on demand with one paving pattern, deterministic layer order and shared markings',async t=>{
  // Each point is within both districts' bounding boxes. Actual polygon tests
  // distinguish a close Songyan (Xinyi) view from a northern street in Songshan.
  const polygon=(name,ring)=>({properties:{name},geometry:{type:'Polygon',coordinates:[ring]}});
  const outlines=[
    polygon('信義區',[[121.55,25.02],[121.59,25.02],[121.59,25.048],[121.55,25.045],[121.55,25.02]]),
    polygon('松山區',[[121.55,25.045],[121.59,25.048],[121.59,25.071],[121.55,25.071],[121.55,25.045]]),
  ];
  const {map,events,sources,layers,images,paints,order,view}=groundMap(outlines);
  const requests=[];
  t.mock.method(globalThis,'fetch',async url=>{
    const ss=url.pathname.endsWith('/songshan-street-ground.json.gz');
    requests.push(ss?'松山區':'信義區');return new Response(ss?songshanBytes:bytes);
  });
  addDistrictStreetGround(map);view.zoom=18;await events.get('moveend')();assert.deepEqual(requests,[]);
  view.box=[[121.56,25.0484],[121.562,25.0486]];await events.get('moveend')();
  assert.deepEqual(requests,['松山區']);
  assert.equal(sources.get(grounds[1]).data.features.length,songshan.features.length);
  verifyMarkingColors(paints.get('city170-prepared-lane'),[2]);
  view.box=[[121.560,25.0450],[121.562,25.0452]];view.zoom=15.95;await events.get('moveend')();
  assert.deepEqual(requests,['松山區','信義區']);assert.equal(events.has('moveend'),true);
  assert.equal(sources.get(grounds[0]).data.features.length,ground.features.length);
  const suffixes=['paving','asphalt','concrete-joints','kerb'];
  assert.deepEqual(order,[baseOrder[0],...grounds.flatMap(g=>suffixes.map(s=>g+'-'+s)),...baseOrder.slice(1)]);
  for(const id of grounds){
    const asphalt=layers.get(id+'-asphalt');
    assert.deepEqual(asphalt.paint['fill-color'],asphaltPaint);
    assert.ok(asphalt.minzoom<15.95&&asphalt.paint['fill-opacity'].at(-2)<=16.3);
    assert.equal(layers.get(id+'-kerb').paint['line-color'],'#e3c477');
    // Patterned asphalt produced rectangular draping artefacts at street zoom.
    const patterned=[...layers.values()].filter(l=>l.source===id&&'fill-pattern' in l.paint);
    assert.equal(patterned.length,1);assert.deepEqual(patterned[0].filter,['in',['get','kind'],['literal',['walk']]]);
    assert.equal(patterned[0].paint['fill-opacity'].at(-1),.55);
  }
  assert.deepEqual([...paints.keys()],['city170-prepared-lane','city170-prepared-crossing']);
  for(const paint of paints.values())verifyMarkingColors(paint,[1,2]);
  assert.equal(images.size,5);
  for(const [id,image] of images){
    assert.match(id,/^district-street-pavers-/);assert.equal(image.width*image.height*4,image.data.length);
  }
});

test('a failed neighboring district keeps its base paint and can retry independently',async t=>{
  const {map,events,sources,images,paints,view}=groundMap();
  const ids=[],warn=t.mock.method(console,'warn',()=>{});
  let fail=true;
  t.mock.method(globalThis,'fetch',async url=>{
    const ss=url.pathname.endsWith('/songshan-street-ground.json.gz');ids.push(ss?'songshan':'xinyi');
    return ss&&fail?new Response('',{status:503}):new Response(ss?songshanBytes:bytes);
  });
  addDistrictStreetGround(map);view.zoom=18;view.box=[[121.55,25.03],[121.58,25.066]];
  const initial=events.get('moveend')();await events.get('moveend')();await initial;
  assert.equal(warn.mock.callCount(),1);assert.deepEqual([...sources.keys()],[grounds[0]]);
  verifyMarkingColors(paints.get('city170-prepared-crossing'),[1]);
  fail=false;await events.get('moveend')();
  assert.deepEqual(ids,['xinyi','songshan','songshan']);assert.equal(images.size,5);assert.equal(events.has('moveend'),true);
});

test('removing the map cancels both pending districts',async t=>{
  const {map,events,sources,view}=groundMap(),signals=[];
  t.mock.method(globalThis,'fetch',(_url,{signal})=>new Promise((_,reject)=>{
    signals.push(signal);signal.addEventListener('abort',()=>reject(signal.reason),{once:true});
  }));
  addDistrictStreetGround(map);view.zoom=18;view.box=[[121.55,25.03],[121.58,25.066]];
  const pending=events.get('moveend')();events.get('remove')();await pending;
  assert.equal(signals.length,2);assert.ok(signals.every(s=>s.aborted));
  assert.equal(sources.size,0);assert.equal(events.has('moveend'),false);
});

test('existing stripes use only the districts serving their cell and never duplicate a feature',()=>{
  const items=['lane','crossing','grove-tree'].map(kind=>({properties:{kind}}));
  for(const [names,mask] of [[['信義區'],1],[['松山區'],2],[['信義區','松山區'],3],[['大安區','信義區','松山區'],7]]){
    const output=districtStreetMarkings(items,{districts:names});
    assert.deepEqual(output.map(f=>f.properties.districtStreetMask),[mask,mask,undefined]);
    assert.equal(output[2],items[2]);
  }
  for(const names of [[],['跨出台北市'],['信義區','跨出台北市']])assert.equal(districtStreetMarkings(items,{districts:names}),items);
  assert.deepEqual(items.map(f=>f.properties.districtStreetMask),[undefined,undefined,undefined]);
});


test('panning away releases district sources and layers; returning restores the pavement',async t=>{
  const {map,events,sources,layers,images,view}=groundMap();
  t.mock.method(globalThis,'fetch',async()=>new Response(bytes));
  addDistrictStreetGround(map);
  view.zoom=18;view.box=[[121.57,25.032],[121.571,25.033]];
  await events.get('moveend')();assert.ok(sources.has(grounds[0]));
  view.box=[[121.48,25.135],[121.481,25.136]];
  await events.get('moveend')();assert.equal(sources.size,0);assert.equal(layers.size,0);
  view.box=[[121.57,25.032],[121.571,25.033]];
  await events.get('moveend')();assert.ok(sources.has(grounds[0]));assert.equal(images.size,5);
});

test('all twelve districts can be entered, released, and revisited on one map', {skip:!process.env.POCKET_TAIPEI_DATA},async t=>{
  const {join}=await import('node:path');
  const official=JSON.parse(await readFile(join(process.env.POCKET_TAIPEI_DATA,'districts.geojson'))).features;
  assert.equal(official.length,12);
  const {map,events,sources,view}=groundMap(official);
  const fetched=new Set();
  t.mock.method(globalThis,'fetch',async url=>{
    fetched.add(url.pathname.split('/').at(-1));
    return new Response(await readFile(url));
  });
  addDistrictStreetGround(map);view.zoom=18;
  // Centres of inhabited 170 m cells entirely inside their named district.
  const locations=[[121.56591,25.04070],[121.55754,25.05148],[121.55431,25.03205],
    [121.53396,25.05310],[121.51038,25.05471],[121.50696,25.04398],
    [121.51539,25.04549],[121.52401,25.08997],[121.50227,25.13302],
    [121.59137,25.08050],[121.60642,25.05589],[121.54211,24.99014]];
  for(const [i,[x,y]] of [...locations,locations[0]].entries()){
    const district=streetDistricts[i%12];
    view.box=[[x-.0001,y-.0001],[x+.0001,y+.0001]];
    await events.get('moveend')();
    assert.ok(sources.get(district.id+'-street-ground')?.data.features.length,district.name);
    assert.ok(sources.size<12);
  }
  assert.equal(fetched.size,12);
});

test('a late response after panning away cannot replace a newer request for the same district',async t=>{
  const {map,events,sources,view}=groundMap();
  const requests=[];
  t.mock.method(globalThis,'fetch',(_,options)=>new Promise(resolve=>requests.push({resolve,signal:options.signal})));
  addDistrictStreetGround(map);view.zoom=18;
  const local=[[121.57,25.032],[121.571,25.033]];
  view.box=local;const first=events.get('moveend')();
  view.box=[[121.48,25.135],[121.481,25.136]];await events.get('moveend')();
  assert.ok(requests[0].signal.aborted);
  view.box=local;const second=events.get('moveend')();
  requests[0].resolve(new Response(bytes));await first;
  assert.equal(sources.size,0);await events.get('moveend')();assert.equal(requests.length,2);
  requests[1].resolve(new Response(bytes));await second;assert.ok(sources.has(grounds[0]));
});

test('zooming out releases mounted streets and cancels other district loads before their response',async t=>{
  const {map,events,sources,layers,paints,view}=groundMap();
  let pending;
  t.mock.method(globalThis,'fetch',async (url,{signal})=>{
    if(url.pathname.endsWith('/songshan-street-ground.json.gz'))
      return new Promise(resolve=>{pending={signal,resolve};});
    return new Response(bytes);
  });
  addDistrictStreetGround(map);view.zoom=18;
  view.box=[[121.57,25.032],[121.571,25.033]];await events.get('moveend')();
  assert.ok(sources.has(grounds[0]));
  view.box=[[121.55,25.03],[121.58,25.066]];const loading=events.get('moveend')();
  view.zoom=12;await events.get('moveend')();
  assert.ok(pending.signal.aborted);assert.equal(sources.size,0);assert.equal(layers.size,0);
  verifyMarkingColors(paints.get('city170-prepared-lane'),[]);
  pending.resolve(new Response(songshanBytes));await loading;
  assert.equal(sources.size,0);assert.equal(layers.size,0);
  view.zoom=18;view.box=[[121.57,25.032],[121.571,25.033]];await events.get('moveend')();
  assert.ok(sources.has(grounds[0]));
});
