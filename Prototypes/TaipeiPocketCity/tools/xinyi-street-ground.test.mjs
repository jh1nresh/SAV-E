import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {unpackXinyiGround,addXinyiStreetGround,xinyiStreetMarkings} from '../xinyi-street-ground.js';

const bytes=await readFile(new URL('../assets/xinyi-street-ground.json.gz',import.meta.url));
const ground=unpackXinyiGround(JSON.parse(gunzipSync(bytes)));
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

test('normal street zoom installs one draped road surface below landmarks, labels and shadows',async t=>{
  let near=false,zoom=15;const events=new Map(),sources=[],layers=[],images=[],repaints=[];
  const order=['street-songshan-road','taipei101-single-ground','atlas-shadows','city170-prepared-lane','city170-prepared-crossing','survey','street-songshan-road-labels'];
  const map={on:(id,cb)=>events.set(id,cb),off:id=>events.delete(id),getZoom:()=>zoom,
    getBounds:()=>({toArray:()=>near?[[121.56,25.044],[121.563,25.046]]:[[121.52,25.01],[121.53,25.02]]}),
    getStyle:()=>({layers:order.map(id=>({id}))}),getLayer:id=>order.includes(id),
    getPaintProperty:()=> '#fff0d4',setPaintProperty:(...props)=>repaints.push(props),
    addSource:(id,src)=>sources.push([id,src]),addImage:(...args)=>images.push(args),addLayer:(layer,before)=>layers.push([layer,before])};
  let requests=0;
  t.mock.method(globalThis,'fetch',async()=>{requests++;return new Response(bytes);});
  addXinyiStreetGround(map);zoom=17.6;await events.get('moveend')();assert.equal(requests,0);
  near=true;await events.get('moveend')();assert.equal(requests,1);assert.equal(events.has('moveend'),false);
  assert.equal(sources.length,1);assert.equal(sources[0][1].data.features.length,ground.features.length);
  assert.ok(layers.every(([l,before])=>before==='taipei101-single-ground'&&['fill','line'].includes(l.type)));
  assert.deepEqual(layers.map(([l])=>l.id.substring('xinyi-street-ground-'.length)),['paving','asphalt','concrete-joints','kerb']);
  assert.equal(layers[1][0].paint['fill-color'],'#929394');assert.equal(layers.at(-1)[0].paint['line-color'],'#e3c477');
  // Street-scale A/B showed rectangular artefacts on patterned asphalt. Only
  // mapped paved walks get a texture; dirt trails and the carriageway remain clear.
  const patterned=layers.map(([layer])=>layer).filter(layer=>'fill-pattern' in layer.paint);
  assert.equal(patterned.length,1);
  assert.deepEqual(patterned[0].filter,['in',['get','kind'],['literal',['walk']]]);
  assert.equal(patterned[0].paint['fill-opacity'].at(-1),.55);
  assert.equal(images.length,5);
  for(const [id,image] of images){
    assert.match(id,/^xinyi-pavers-/);
    assert.equal(image.width*image.height*4,image.data.length);
  }
  assert.deepEqual(repaints.map(p=>p[0]),['city170-prepared-lane','city170-prepared-crossing']);
});

test('existing stripes are tagged only in complete Xinyi cells and do not require another paint layer',()=>{
  const items=['lane','crossing','grove-tree'].map(kind=>({properties:{kind}}));
  const input=xinyiStreetMarkings(items,{districts:['信義區']});
  assert.deepEqual(input.map(f=>f.properties.xinyiMarking),[true,true,undefined]);
  assert.deepEqual(items.map(f=>f.properties.xinyiMarking),[undefined,undefined,undefined]);
  assert.equal(xinyiStreetMarkings(items,{districts:['信義區','松山區']}),items);
  assert.equal(xinyiStreetMarkings(items,{districts:['松山區']}),items);
});
