import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {addTaiwanScenery,sceneryCard,sceneryLabels} from '../taiwan-scenery.js';

const load=async name=>{
  const bytes=await readFile(new URL('../taiwan/scenery/'+name,import.meta.url));
  return JSON.parse(name.endsWith('.gz')?gunzipSync(bytes):bytes);
};
const [manifest,points,rivers,waters]=await Promise.all(['sources.json','places.geojson.gz','rivers.geojson.gz','waters.geojson.gz'].map(load));

test('offline Taiwan scenery carries resolvable identities, actual waterways and inland shoreline rings',()=>{
  assert.equal(manifest.coverage.townshipsWithScenery,368);
  assert.equal(manifest.coverage.countiesWithScenery,22);
  assert.equal(manifest.invalidGeometriesSkipped,0);
  for(const [set,data] of Object.entries({places:points,rivers,waters})){
    assert.equal(data.features.length,manifest.counts[set]);
    assert.equal(new Set(data.features.map(f=>f.properties.id)).size,data.features.length);
    for(const feature of data.features){
      assert.ok(sceneryCard(feature.properties,[0,0])?.placeId);
    }
  }
  const lake=waters.features.find(f=>f.properties.id==='r3858334');
  assert.equal(lake.properties.n,'日月潭');
  assert.equal(lake.geometry.type,'Polygon');
  assert.ok(lake.geometry.coordinates[0].length>100);
  assert.deepEqual(lake.geometry.coordinates[0][0],lake.geometry.coordinates[0].at(-1));
  assert.ok(rivers.features.some(f=>f.properties.n==='濁水溪' && f.geometry.coordinates.length>10));
  const ids=new Set(points.features.map(f=>f.properties.id));
  for(const id of ['n3428095932','n1233402716','r6262405','r9331637','r19309093','r10730513','r12109259','r20426797'])assert.ok(ids.has(id),id);
});

test('named rivers resolve to a source way and its on-line midpoint',async()=>{
  const rows=await load('river-search.json.gz');
  const waterways=rivers.features.filter(f=>['river','stream'].includes(f.properties.k));
  const ways=new Map(waterways.map(f=>[f.properties.id,f]));
  assert.equal(rows.length,new Set(waterways.map(f=>f.properties.n)).size);
  assert.equal(rows.length,new Set(rows.map(row=>row[0])).size);
  for(const [name,kind,id,lng,lat] of rows){
    const source=ways.get(id);
    assert.equal(source.properties.n,name);
    assert.equal(source.properties.k,kind);
    // Local equirectangular metres, robust to the index's sub-centimetre rounding.
    const mx=111320*Math.cos(lat*Math.PI/180),my=111320;
    const coordinates=source.geometry.coordinates;
    const onSegment=coordinates.slice(1).some(([bx,by],index)=>{
      const [ax,ay]=coordinates[index];
      const dx=(bx-ax)*mx,dy=(by-ay)*my;
      const x=(lng-ax)*mx,y=(lat-ay)*my;
      const t=Math.max(0,Math.min(1,(x*dx+y*dy)/(dx*dx+dy*dy||1)));
      return Math.hypot(x-t*dx,y-t*dy)<.02;
    });
    assert.ok(onSegment,name);
  }
  for(const name of ['濁水溪','高屏溪','淡水河','曾文溪','秀姑巒溪']){
    const row=rows.find(r=>r[0]===name);
    assert.equal(row?.[1],'river',name);
  }
});

test('a low mountain named 玉山 keeps its own source and elevation',()=>{
  const low=sceneryCard({n:'玉山',id:'n2482643141',k:'peak',ele:370},[121.2,24.7]);
  const summit=sceneryCard({n:'玉山',id:'n3428095932',k:'peak',ele:3952},[120.95,23.46]);
  assert.equal(low.url,'https://www.openstreetmap.org/node/2482643141');
  assert.match(low.detail,/370/);
  assert.equal(new URL(summit.url).hostname,'www.ysnp.gov.tw');
  assert.notEqual(low.placeId,summit.placeId);
  assert.equal(sceneryCard({id:'n234',n:'無類別',k:'?'}),null);
});

test('the globe fetches scenery on first Taiwan view and yields underlying water taps to authored pins',()=>{
  let zoom=2,box=[117,20,122,27],hits=[],opened;
  const handlers={},layers=new Map([['landcover_sand',{}],['city-atlas-pins',{}]]),sources=[];
  const map={getZoom:()=>zoom,getBounds:()=>({getWest:()=>box[0],getSouth:()=>box[1],getEast:()=>box[2],getNorth:()=>box[3]}),
    on:(ev,fn)=>handlers[ev]=fn,getLayer:id=>layers.get(id),hasImage:()=>true,
    addLayer(l){layers.set(l.id,l);},addSource(id){sources.push(id);},getSource:()=>({setData(){}}),
    queryRenderedFeatures:()=>hits,setLayoutProperty:(id,k,v)=>{layers.get(id).layout[k]=v;}};
  const api=addTaiwanScenery(map,undefined,card=>opened=card,async()=>points);
  api.setLabels(false);
  zoom=12;box=[-119,34,-118,35];handlers.moveend();
  assert.deepEqual(sources,[]);
  box=[114.34,10.35,114.40,10.4];handlers.moveend();handlers.moveend();
  assert.equal(sources.length,3);
  assert.equal(layers.get(sceneryLabels).layout.visibility,'none');
  api.setLabels(true);
  const event={point:[1,1],lngLat:{lng:120.93,lat:23.85}};
  hits=[{layer:{id:'taiwan-scenery-waters'},geometry:{type:'Polygon'},properties:{id:'r3858334',n:'日月潭',k:'reservoir'}}];
  handlers.click(event);
  assert.equal(opened.name,'日月潭');
  assert.deepEqual(opened.point,[120.93,23.85]);
  opened=null;hits.unshift({layer:{id:'city-atlas-pins'}});handlers.click(event);
  assert.equal(opened,null);
});
