import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {addTaiwanStreets,assignRoadLabels,streetLabelCandidates,indexStreetShard,localStreetFeatures,missingStreetBuildings} from '../taiwan-streets.js';
import {buildTaiwanCells} from '../taiwan-cell-geometry.js';

const dir=new URL('../taiwan/',import.meta.url);
const file=name=>readFileSync(new URL(name,dir));
const json=name=>JSON.parse(file(name));
const gz=name=>JSON.parse(gunzipSync(file(name)));
const all={contains:()=>true,exclude:()=>false};
const keyFor=(x,y)=>Math.floor(x*32)+'-'+Math.floor(y*32);
const samples=[
  ['勝利路65巷','Q凍屋','w1163794705',120.2178,22.99022],
  ['民族路','天恩素食早點','n2835983798',118.32057,24.43072],
  ['海埔路','富國海鮮餐廳','w833470351',119.57325,23.56863],
  ['仁愛路','FamilyMart','n13763170746',119.92774,26.14520],
  ['國興六街','可利亞','n4122842501',121.59965,23.98658],
];
test('all 21 non-Taipei counties have offline ordinary streets, footprints and sourced storefront matches',()=>{
  const m=json('streets/index.json');
  assert.equal(m.sha256,json('places/index.json').sha256);
  assert.equal(Object.keys(m.counties).length,21);assert.ok(!m.counties['臺北市']);
  for(const c of Object.values(m.counties)){
    assert.ok(c.roads>=c.namedRoads&&c.namedRoads>0&&c.lanesAndWalks>0);
    assert.ok(c.footprints>0&&c.frontagePOIs>0&&c.commercialPOIs>=c.frontagePOIs);
  }
  assert.ok(m.compressedBytes<45_000_000&&m.largestShardBytes<350_000);
});
for(const [road,name,id,x,y] of samples){
  test(road+' / '+name+' renders with the basemap vector source empty',()=>{
    const key=keyFor(x,y),shard=indexStreetShard(key,gz('streets/'+key+'.json.gz'));
    const view=[x-.0009,y-.00075,x+.0009,y+.00075],data=localStreetFeatures([shard],view,19,all);
    assert.ok(data.roads.some(r=>r.properties.name===road));
    assert.ok(data.pois.some(p=>p.properties.mappedShop===id));
    const publicTile=Math.floor((x+180)/360*1024)+'-'+Math.floor((1-Math.asinh(Math.tan(y*Math.PI/180))/Math.PI)*512);
    assert.ok(gz('places/'+publicTile+'.json.gz').some(r=>r[0]===name&&r[2]===id));
    const {details}=buildTaiwanCells({view,center:[x,y],zoom:19,...all,tiles:{
      ways:data.roads,buildings:data.buildings,pois:data.pois,woods:[],water:[],fields:[],
    }});
    for(const kind of ['building','awning','window','shop-frame','shop-sign','valance','door-glass'])assert.ok(details.some(f=>f.properties.kind===kind),kind);
    assert.deepEqual(localStreetFeatures([shard],view,19,{...all,overlapsAuthored:()=>true}),
      {roads:[],buildings:[],pois:[],tiles:1});
  });
}
test('matched labels need a common name and a nearby parallel road',()=>{
  const line=(name,a,b)=>({geometry:{type:'LineString',coordinates:[a,b]},properties:{name,label:name}});
  const x=120,y=24,online=line('和平街',[x,y],[x+.001,y]);
  const same=line('和平街',[x,y+.000005],[x+.001,y+.000005]),other=line('和平街',[x,y+.0003],[x+.001,y+.0003]),
    cross=line('和平街',[x+.0005,y-.0005],[x+.0005,y+.0005]),alley=line('和平街一巷',[x,y],[x+.001,y]);
  assignRoadLabels([same,other,cross,alley],[online]);
  assert.deepEqual([same,other,cross,alley].map(l=>l.properties.label),['','和平街','和平街','和平街一巷']);
});
test('online building priority retains courtyards and a neighboring offline building',()=>{
  const box=(x,y,r)=>[[x,y],[x+r,y],[x+r,y+r],[x,y+r],[x,y]];
  const polygon=(...rings)=>({properties:{},geometry:{type:'Polygon',coordinates:rings}});
  const original=polygon(box(120,23,.001),box(120.0003,23.0003,.0003));
  const same=polygon(box(120.00001,23.00001,.00098)),inner=polygon(box(120.00036,23.00036,.0001)),
    adjacent=polygon(box(120.001,23,.001));
  assert.deepEqual(missingStreetBuildings([original],[same,inner,adjacent],[119.999,22.999,120.003,23.003]),[inner,adjacent]);
});
test('adjoining 7.5% overlap does not remove a real building; clipped halves of a matching footprint do',()=>{
  const poly=(w,s,e,n)=>({properties:{},geometry:{type:'Polygon',coordinates:[[[w,s],[e,s],[e,n],[w,n],[w,s]]]}});
  const view=[119.999,22.999,120.002,23.002],local=poly(120.00008,23.00001,120.00020,23.00011);
  const adjacent=poly(120,23,120.00009,23.00010);
  assert.deepEqual(missingStreetBuildings([adjacent],[local],view),[local]);
  const left=poly(120.00008,23.00001,120.000135,23.00011);
  const right=poly(120.000135,23.00001,120.00020,23.00011);
  assert.deepEqual(missingStreetBuildings([left,left],[local],view),[local]);
  assert.deepEqual(missingStreetBuildings([left,right],[local],view),[]);
});
test('Q凍屋 display and category fascia face 勝利路 on the west exterior, away from the neighboring party walls',()=>{
  const x=120.2178,y=22.99022,view=[x-.0009,y-.00075,x+.0009,y+.00075],key=keyFor(x,y);
  const data=localStreetFeatures([indexStreetShard(key,gz('streets/'+key+'.json.gz'))],view,19,all);
  const result=buildTaiwanCells({view,center:[x,y],zoom:19,...all,tiles:{
    ways:data.roads,buildings:data.buildings,pois:data.pois,woods:[],water:[],fields:[],
  }});
  const shop=result.details.filter(f=>f.properties.frontagePOI==='w1163794705');
  assert.ok(shop.length>=10);
  const canopy=shop.find(f=>f.properties.kind==='awning').geometry.coordinates[0];
  assert.ok(canopy[2][0]<canopy[0][0]-.000008);
  assert.ok(shop.some(f=>f.properties.kind==='door-glass'));
  assert.ok(shop.some(f=>f.properties.kind==='shop-sign'&&f.properties.color==='#ab4232'));
});
test('a close 65 m Q凍屋 view has at most one 勝利路 label, including adjacent split ways',()=>{
  const x=120.217746,y=22.990214,key=keyFor(x,y),view=[x-.00032,y-.00028,x+.00032,y+.00028];
  const roads=localStreetFeatures([indexStreetShard(key,gz('streets/'+key+'.json.gz'))],view,20.6,all).roads;
  const actual=streetLabelCandidates(roads,view,20.6).filter(r=>r.properties.name==='勝利路');
  assert.equal(actual.length,1);
  const split=[];
  for(let i=0;i<5;i++)split.push({id:i,geometry:{type:'LineString',coordinates:
    [[x,y-.00025+i*.00010],[x,y-.00015+i*.00010]]},properties:{name:'勝利路',label:'勝利路'}});
  assert.equal(streetLabelCandidates(split,view,20.6).length,1);
  split[0].properties.label='';
  assert.equal(streetLabelCandidates(split,view,20.6).length,0);
});
test('pan away cancels any unmatched shard and removes local data at low zoom',async t=>{
  const [x,y]=[120.2178,22.99022],key=keyFor(x,y),view=[x-.0005,y-.0005,x+.0005,y+.0005];
  const listeners=new Map(),source={setData(){}},map={on:(k,v)=>listeners.set(k,v),addSource(){},addLayer(){},
    getLayer:()=>undefined,getSource:id=>id.startsWith('tw-ordinary-streets')?source:undefined};
  let activeSignal,done,ready;
  const indexReady=new Promise(resolve=>{ready=resolve;});
  t.mock.method(globalThis,'fetch',async (url,opts)=>{
    if(String(url).includes('/index.json'))return Response.json({version:1,scale:100000,tileSpan:3125,tiles:[key]});
    activeSignal=opts.signal;
    return await new Promise(resolve=>{done=()=>resolve(new Response('[]'));});
  });
  const loader=addTaiwanStreets(map,undefined,all,ready);
  loader.refresh(view,[x,y],16.5);await indexReady;
  loader.refresh(view,[x,y],16.5);assert.equal(activeSignal.aborted,false);
  loader.refresh(view,[x,y],8);assert.equal(activeSignal.aborted,true);
  done();await new Promise(r=>setTimeout(r,0));
  assert.equal(loader.state().streets,0);
  listeners.get('remove')();
});
