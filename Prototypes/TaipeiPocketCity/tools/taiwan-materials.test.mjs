import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {decodeMaterialShard,applyStreetMaterials,mergeStreetBuildings,mergeVisibleBuildings,indexStreetShard,localStreetFeatures,
  addTaiwanStreets} from '../taiwan-streets.js';
import {buildTaiwanCells} from '../taiwan-cell-geometry.js';

const root=new URL('../taiwan/',import.meta.url);
const read=name=>readFileSync(new URL(name,root));
const json=name=>JSON.parse(read(name));
const gunzip=name=>JSON.parse(gunzipSync(read(name)));
const ring=(w,s,e,n)=>[[w,s],[e,s],[e,n],[w,n],[w,s]];
const poly=(r,properties,id)=>({type:'Feature',id,geometry:{type:'Polygon',coordinates:[r]},properties});
const view=[120,23,120.002,23.002],source=poly(ring(120,23,120.001,23.001),
  {osmBuildingId:-105,localFootprint:true,'roof:colour':'#aabbcc','building:material':'wood'},105);

test('material coverage and sizes are consistent with the frozen footprint index',()=>{
  const m=json('materials/index.json'),streets=json('streets/index.json');
  assert.equal(m.sha256,streets.sha256);assert.deepEqual(Object.keys(m.counties).sort(),Object.keys(streets.counties).sort());
  assert.equal(m.fields.includes('addr:housenumber'),false);
  const sizes=m.tiles.map(k=>read('materials/'+k+'.json.gz').length);
  assert.equal(sizes.reduce((a,b)=>a+b),m.compressedBytes);
  assert.equal(Math.max(...sizes),m.largestShardBytes);assert.ok(m.compressedBytes<900000&&m.largestShardBytes<90000);
  assert.equal(Object.values(m.counties).reduce((n,v)=>n+v.tagged,0),m.taggedFootprints);
  for(const [county,v] of Object.entries(m.counties)){
    assert.equal(v.footprints,streets.counties[county].footprints);
    assert.ok(v.tagged>0&&v.tagged<v.footprints);
    assert.ok((v['building:colour']??0)<=v.tagged&&(v['roof:colour']??0)<=v.tagged);
  }
});
test('sidecar signed IDs distinguish way and relation and preserve missing fields',()=>{
  const schema=json('materials/index.json').fields;
  const pack=decodeMaterialShard({profiles:[[schema.indexOf('roof:colour'),'#aabbcc'],
    [schema.indexOf('building'),'retail',schema.indexOf('shop'),'bakery']],rows:[-105,0,210,1]});
  const buildings=[-105,105,106].map(id=>({properties:{osmBuildingId:id}}));
  applyStreetMaterials(buildings,[pack]);
  assert.deepEqual(buildings.map(f=>f.properties),[
    {osmBuildingId:-105,'roof:colour':'#aabbcc'},
    {osmBuildingId:105,building:'retail',shop:'bakery'},{osmBuildingId:106},
  ]);
});
test('true clipped online copies inherit mapped tags; adjacent, conflicting or ambiguous sources do not',()=>{
  const p={render_height:14,render_min_height:2};
  const left=poly(ring(120,23,120.00051,23.001),p,900),right=poly(ring(120.0005,23,120.001,23.001),p,900);
  const far=poly(ring(120.00098,23,120.002,23.001),p,901);
  const result=mergeStreetBuildings([left,right,far],[source],view);
  assert.equal(result.length,3);
  for(const f of result.slice(0,2)){
    assert.equal(f.properties['roof:colour'],'#aabbcc');
    assert.equal(f.properties.osmBuildingId,-105);
    assert.equal(f.properties.render_height,14);
    assert.equal(f.properties.suppressPitchedRoof,true);
    assert.ok(!f.properties.localFootprint);
  }
  assert.equal(result[2],far);assert.deepEqual(p,{render_height:14,render_min_height:2});
  const full=poly(ring(120,23,120.001,23.001),{osm_type:'way',osm_id:105},809);
  assert.equal(mergeStreetBuildings([full],[source],view)[0].properties['roof:colour'],undefined);
  const competing=poly(source.geometry.coordinates[0],{osmBuildingId:304,'roof:colour':'red',localFootprint:true},304);
  assert.equal(mergeStreetBuildings([left,right],[source,competing],view)[0].properties['roof:colour'],undefined);
  const authoritative=poly(source.geometry.coordinates[0],{'roof:colour':'green'},809);
  assert.equal(mergeStreetBuildings([authoritative],[source],view)[0].properties['roof:colour'],'green');
  const duplicate=mergeStreetBuildings([authoritative,{...authoritative}],[source],view);
  assert.ok(duplicate.every(f=>!f.properties.suppressPitchedRoof));

});
test('a match without any material tags keeps its local identity and shop use across levels of detail',async()=>{
  const ground=ring(120,23,120.0008,23.0004);
  const online=poly(ground,{render_height:11},834);
  const offline=poly(ground,{osmBuildingId:572116,render_height:5.5,styleHeight:5.5,styleArea:230,
    mappedShopKind:'bakery',localFootprint:true},572116);
  const matched=await mergeVisibleBuildings([online],[offline],view,()=>true);
  assert.equal(matched.length,1);
  assert.deepEqual(matched[0].properties,{osmBuildingId:572116,render_height:11,styleHeight:5.5,styleArea:230,mappedShopKind:'bakery'});
  assert.equal(await mergeVisibleBuildings([online],[offline],view,()=>false),undefined);
});
test('real street geometry uses only tags of its matching OSM object',()=>{
  const key='472-97',pack=decodeMaterialShard(gunzip('materials/'+key+'.json.gz'));
  assert.equal(pack.get(1072725772)['building:colour'],'olive');
  const streetIndex=json('streets/index.json');
  let found;
  for(const k of streetIndex.tiles){
    const coarse=k.split('-').map(v=>Math.floor(Number(v)/8)).join('-');
    if(coarse!==key)continue;
    const index=indexStreetShard(k,gunzip('streets/'+k+'.json.gz'));
    const row=index.find(v=>v.row[0]===1&&v.row[1]===1072725772);
    if(!row)continue;
    const sample=localStreetFeatures([[row]],row.bounds,19,{contains:()=>true,exclude:()=>false});
    applyStreetMaterials(sample.buildings,[pack]);found=sample.buildings[0];
    const [w,s,e,n]=row.bounds,view=[w-.0001,s-.0001,e+.0001,n+.0001],center=[(w+e)/2,(s+n)/2];
    const online={...found,id:834,properties:{render_height:6}};
    for(const buildings of [[found],mergeStreetBuildings([online],[found],view)]){
      const colours=zoom=>buildTaiwanCells({view,center,zoom,contains:()=>true,exclude:()=>false,
        tiles:{buildings,ways:[],fields:[],water:[],woods:[],pois:[]}}).details
        .filter(f=>['building','roof'].includes(f.properties.kind)).map(f=>f.properties.color);
      assert.equal(colours(15).length,2);
      assert.deepEqual(colours(15),colours(19));
    }
    break;
  }
  assert.equal(found.properties.osmBuildingId,1072725772);assert.equal(found.properties['building:colour'],'olive');
});
test('one small on-demand pack supplies identical material and identity at z15 and z19',async t=>{
  const requested=[],listeners=new Map();
  const sources=new Map();
  const map={on:(e,f)=>listeners.set(e,f),addLayer(){},getLayer:()=>undefined,getSource:id=>sources.get(id),
    addSource:id=>sources.set(id,{setData(){}})};
  const lat=23.0003,lng=120.0004,key='3840-736',coarse='480-92',m=json('materials/index.json');
  const street=[1,105,0,8,[[2,2,40,0,0,40,-40,0]],[['w501','bakery',10,10]]];
  const road=[0,111,0,1,'測試巷',[2,25,40,0]];
  let release;
  t.mock.method(globalThis,'fetch',async url=>{
    const path=new URL(url).pathname.split('/taiwan/').at(-1);
    requested.push(path);
    if(path==='streets/index.json')return Response.json({version:1,tileSpan:3125,scale:100000,tiles:[key],sha256:m.sha256});
    if(path==='materials/index.json')return Response.json({...m,tiles:[coarse]});
    if(path==='streets/'+key+'.json.gz')return Response.json([street,road]);
    return await new Promise(resolve=>{release=()=>resolve(Response.json({profiles:[[m.fields.indexOf('roof:shape'),'gabled']],rows:[105,0]}));});
  });
  const loader=addTaiwanStreets(map,undefined,{contains:()=>true,exclude:()=>false},()=>{});
  const v=[120.00001,23.00001,120.0008,23.0008],center=[lng,lat];
  const tick=()=>new Promise(r=>setTimeout(r,8));
  for(let i=0;i<2;i++){loader.refresh(v,center,14.9);await tick();}
  assert.ok(requested.every(path=>!path.startsWith('materials/')));
  for(let i=0;i<3;i++){loader.refresh(v,center,15);await tick();}
  const base=loader.refresh(v,center,15);assert.equal(base.buildings[0].properties.osmBuildingId,105);
  await tick();loader.refresh(v,center,15);await tick();
  assert.equal(base.buildings[0].properties['roof:shape'],undefined);
  release();await tick();const middle=loader.refresh(v,center,15);
  assert.equal(middle.roads.length,0);assert.equal(middle.pois.length,0);
  assert.equal(middle.buildings[0].properties['roof:shape'],'gabled');
  assert.equal(middle.buildings[0].properties.mappedShopKind,'bakery');
  const streets=loader.refresh(v,center,16);
  assert.equal(streets.roads.length,1);assert.equal(streets.pois.length,0);
  const ready=loader.refresh(v,center,19);
  assert.deepEqual(ready.buildings[0].properties,middle.buildings[0].properties);
  assert.equal(ready.pois.length,1);
  assert.equal(ready.buildings[0].properties['roof:shape'],'gabled');
  assert.equal(requested.filter(p=>p==='materials/'+coarse+'.json.gz').length,1);
  listeners.get('remove')();
});
