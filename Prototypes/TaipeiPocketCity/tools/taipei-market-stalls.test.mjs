import assert from 'node:assert/strict';
import test from 'node:test';
import {MercatorCoordinate} from '../assets/maplibre-gl.mjs';
import {StreetScenery} from '../street-scenery.js';
import marketPacks from '../taipei-market-stalls-data.js';
import {marketStallLife,withMarketScenery} from '../taipei-market-stalls.js';

test('market scenes stay in the selected 170 m atlas packs and create no merchant pins',()=>{
  const keys=Object.keys(marketPacks);
  const scenes=marketStallLife([],keys);
  assert.deepEqual(marketStallLife([],['world','p0_0']),[]);
  const ids=new Set(),counts=new Map(),routes=new Map();
  for(const scene of scenes){
    for(const [key,row] of Object.entries(scene.objects)){
      assert(!ids.has(key));ids.add(key);
      const [market]=key.split('/');
      counts.set(market,(counts.get(market)??0)+1);
      assert.equal(row.length,6);
      assert(row[2].startsWith('market-'));
      assert.equal(row[3],1);
    }
    for(const [key,route] of Object.entries(scene.paths)){
      assert(route.points.length>=2 && route.people>=2);
      if(routes.has(key))assert.deepEqual(routes.get(key),route);
      routes.set(key,route);
    }
  }
  assert.equal(counts.size,2);
  assert([...counts.values()].every(count=>count>=45));
  for(const market of counts.keys()){
    assert([...routes.keys()].some(key=>key.startsWith(market+'/walk/')));
  }
  const replaced=scenes.flatMap(scene=>scene.replacePaths??[]);
  assert(replaced.length>0);
  const paths={[replaced[0]]:{points:[]},keep:{points:[]}};
  assert.deepEqual(marketStallLife([{objects:{},paths}],keys)[0].paths,{keep:paths.keep});
  const mark={type:'Feature',id:'tcma-market-11',geometry:{type:'Point',coordinates:[121.575,25.05]},
    properties:{detail:'松山區 · 饒河街',source:'臺北市市場處'}};
  const copy=withMarketScenery(mark);
  assert.equal(copy.geometry,mark.geometry);
  assert.equal(copy.id,mark.id);
  assert.equal(copy.properties.source,mark.properties.source);
  assert.match(copy.properties.detail,/街景示意/);
  assert.equal(withMarketScenery({...mark,id:'tcma-market-9'}).properties,mark.properties);
});

function projectedVertices(kind,angle){
  const point=[121.575,25.05];
  const scene=new StreetScenery('test',point,[[...point,kind,1,angle,2]],MercatorCoordinate,false,true);
  let vertices;
  const gl=new Proxy({bufferData(_target,data){vertices=data;}},{get:(obj,key)=>obj[key]??(()=>true)});
  const map={on(){},getZoom:()=>19,isSourceLoaded:()=>true,queryTerrainElevation:()=>13,
    getBounds:()=>({toArray:()=>[[121.57,25.04],[121.58,25.06]]})};
  scene.onAdd(map,gl);
  scene.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  assert.ok(scene.drawnTriangles>0 && scene.drawnTriangles<480);
  return vertices;
}

test('the rendered fixtures ground their supports and keep the reserved footprint at both bearings',()=>{
  const silhouettes=new Set();
  for(const kind of ['market-canopy','market-grill','market-counter']){
    const forward=projectedVertices(kind,0);
    const rotated=projectedVertices(kind,90);
    assert.equal(forward.length,rotated.length);
    assert.equal(Math.min(...forward.filter((_,i)=>i%6===2)),13);
    for(let i=0;i<forward.length;i+=6){
      assert(Math.abs(forward[i])<=1.12);
      assert(Math.abs(forward[i+1])<=.81);
      assert(forward[i+2]>=13 && forward[i+2]<15.3);
      assert.ok(Math.abs(forward[i]-rotated[i+1])<1e-6);
      assert.ok(Math.abs(forward[i+1]+rotated[i])<1e-6);
    }
    silhouettes.add(JSON.stringify(forward.filter((_,i)=>i%6<3)));
  }
  assert.equal(silhouettes.size,3);
});
