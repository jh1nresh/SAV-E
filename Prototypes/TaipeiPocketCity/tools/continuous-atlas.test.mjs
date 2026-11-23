import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {geographicPoint,geographicScene} from '../cities/geography.js';
import {intersectsBuilding} from '../city-context.js';
const read=async file=>JSON.parse(await readFile(new URL('../'+file,import.meta.url),'utf8'));
const rows=await read('cities/catalog.json');
const tiles=await read('cities/map-tiles/index.json');

test('local metre grids rotate about the actual longitude and latitude',()=>{
  const meta={lon:121,lat:25,rotation:90};
  assert.deepEqual(geographicPoint(meta,[0,0]),[121,25]);
  const eastOnDrawing=geographicPoint(meta,[5,0]);
  assert.equal(eastOnDrawing[0],121);
  assert.ok(Math.abs((eastOnDrawing[1]-25)*110574-5)<1e-8);
});

test('context polygons that cross a plot edge yield to the authored scene',()=>{
  assert.ok(intersectsBuilding([[0,.5],[0,1],[2,1],[2,.5]],[.4,.4,1.6,.8]));
  assert.ok(!intersectsBuilding([[0,0],[0,1],[.1,1]],[.4,.4,1.6,.8]));
});

test('every registered landmark opens inside a cached street tile and labels actual map coordinates',async()=>{
  const keys=new Set(tiles.tiles.map(p=>p.join('/')));
  for(const row of rows){
    const [lon,lat]=row.center;
    const x=Math.floor((lon+180)/360*16384),y=Math.floor((1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)*8192);
    assert.ok(keys.has(x+'/'+y),row.id+' local context');
    const scene=await read('cities/'+row.id+'/scene.json');
    const features=geographicScene(scene,row.landmarkIds,row.landmarkSites);
    assert.ok(features.some(f=>f.properties.kind==='pin'&&f.properties.name),row.id+' readable pin');
    for(const f of features.filter(f=>f.geometry.type==='Polygon')){
      assert.ok(f.geometry.coordinates.every(r=>r.length>=4&&r[0][0]===r.at(-1)[0]&&r[0][1]===r.at(-1)[1]));
    }
    for(const pin of features.filter(f=>f.properties.placeId)){
      assert.match(pin.properties.placeId,/^poi\/(node|way|relation)\/\d+$/);
    }
  }
});

test('surrounding streets expose named places while authored plots keep their own pins',async()=>{
  const {addCityContext}=await import('../city-context.js');
  const {placePinStyle}=await import('../place-pins.js');
  assert.equal(typeof placePinStyle,'function');
  const source={setData(data){this.features=data.features;}},handlers=new Map(),layers=[];
  const map={addSource(){},addLayer(l){layers.push(l);},hasImage:()=>true,getZoom:()=>19,
    getSource:()=>source,getCenter:()=>({lng:121.43,lat:25.17}),getBounds:()=>({
      getWest:()=>121.4,getSouth:()=>25.14,getEast:()=>121.46,getNorth:()=>25.2}),
    querySourceFeatures(_,{sourceLayer}){return sourceLayer==='building'?[]:
      [[121.43,25.17],[121.44,25.18],[121.44,25.18]].map(coordinates=>({
        geometry:{type:'Point',coordinates},properties:{name:'街邊測試店',subclass:'cafe',rank:9}}));},
    on(event,layer,callback){handlers.set(event,callback||layer);}};
  let tapped;
  addCityContext(map,[{center:[121.43,25.17],bounds:[121.429,25.169,121.431,25.171]}],
    undefined,()=>false,p=>{tapped=p;});
  await new Promise(resolve=>setTimeout(resolve,135));
  assert.equal(source.features.length,1);
  assert.deepEqual(source.features[0].geometry.coordinates,[121.44,25.18]);
  handlers.get('click')({features:source.features});
  assert.equal(tapped.category,'cafe');assert.equal(tapped.placeId,undefined);
  assert.equal(layers.find(l=>l.type==='symbol').minzoom,16.6);
  handlers.get('remove')();
});
