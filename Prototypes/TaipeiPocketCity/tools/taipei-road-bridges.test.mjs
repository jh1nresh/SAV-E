import test from 'node:test';
import assert from 'node:assert/strict';
import {gzipSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import {TaipeiRoadBridges,addTaipeiRoadBridges} from '../taipei-road-bridges.js';
import {asphaltColors} from '../taipei-asphalt.js';

const near={id:'road/way/138265874',name:'信義路入口匝道',width:7,paintIds:[1382658742],
  line:[[121.5715,25.03215],[121.5724,25.0328]],box:[121.5715,25.03215,121.5724,25.0328]};
const east={...near,id:'road/way/300',paintIds:[3000,97002],line:[[121.574,25.03215],[121.5743,25.0328]],box:[121.574,25.03215,121.5743,25.0328]};
const opts={defaultProjectionData:{mainMatrix:new Float32Array(16)}};
function fixture(){
  const style=JSON.parse(readFileSync(new URL('../assets/base-style.json',import.meta.url)));
  const layers=new Map(style.layers.map(l=>[l.id,{...l,sourceLayer:l['source-layer']}]));layers.set('survey',{id:'survey'});
  const opacities=new Map(style.layers.map(l=>[l.id,l.paint?.['line-opacity']])),states=new Map(),events=new Map(),updates=[],draws=[],deletions=[],colors=[],uploads=[];
  const camera={zoom:15.5,box:[121.570,25.031,121.575,25.034]};
  const gl=new Proxy({
    getShaderParameter:()=>true,getProgramParameter:()=>true,isEnabled:()=>false,
    getUniformLocation:(_p,key)=>key,drawArrays:(_t,_s,count)=>draws.push(count),bufferData:(_t,data)=>uploads.push(data.length),
    uniform3fv:(_u,color)=>colors.push(color),deleteBuffer:()=>deletions.push('buffer'),
    deleteVertexArray:()=>deletions.push('vao'),deleteProgram:()=>deletions.push('program'),
  },{get:(o,k)=>o[k]??(()=>{})});
  const map={terrain:{getDrawnElevationForLngLat:()=>4},triggerRepaint:()=>{},getZoom:()=>camera.zoom,
    getBounds:()=>({getWest:()=>camera.box[0],getEast:()=>camera.box[2],getNorth:()=>camera.box[3],getSouth:()=>camera.box[1]}),
    getLayer:id=>layers.get(id),getLayersOrder:()=>[...layers.keys()],
    getPaintProperty:(id,k)=>{assert.equal(k,'line-opacity');return opacities.get(id);},
    setPaintProperty:(id,k,v)=>{assert.equal(k,'line-opacity');updates.push(id);opacities.set(id,v);},
    setFeatureState:(target,s)=>{
      assert.deepEqual(target,{source:'openmaptiles',sourceLayer:'transportation',id:target.id});
      states.set(target.id,{...states.get(target.id),...s});
    },
    removeFeatureState:(target,k)=>{delete states.get(target.id)[k];},
    on:(type,fn)=>{if(!events.has(type))events.set(type,new Set());events.get(type).add(fn);},
    off:(type,fn)=>events.get(type)?.delete(fn),
    addLayer:(layer,before)=>{assert.equal(before,'survey');layers.set(layer.id,layer);layer.onAdd(map,gl);},
    removeLayer:id=>{layers.get(id).onRemove(map,gl);layers.delete(id);},
  };
  const fire=(event,payload)=>Promise.all([...(events.get(event)??[])].map(fn=>fn(payload)));
  return {map,camera,gl,style,opacities,states,events,updates,draws,colors,uploads,deletions,fire};
}
const id='taipei-road-bridges';
const color=s=>[1,3,5].map(i=>parseInt(s.slice(i,i+2),16)/255);

test('only drawn bridge ways suppress the corresponding transportation strokes; cold, flat and pedestrian routes survive',async t=>{
  const f=fixture(),{map,camera,gl,draws,updates,opacities,states,uploads}=f;
  const layer=new TaipeiRoadBridges([near,east]);layer.onAdd(map,gl);t.after(()=>layer.onRemove(map,gl));
  camera.zoom=18;
  map.terrain={getDrawnElevationForLngLat:loc=>loc.lng<121.573?0:undefined,
    getElevationAndDEMStateForLngLat:()=>({demState:'loading',elevation:0})};
  map.isSourceLoaded=()=>false;
  layer.render(gl,opts);assert.deepEqual(layer.drawnIds,[]);assert.equal(draws.length,0);
  map.isSourceLoaded=()=>true;
  layer.render(gl,opts);
  assert.deepEqual(layer.drawnIds,[near.id]);assert.ok(draws[0]>0);assert.ok(layer.missing);
  assert.deepEqual([...states.keys()],[1382658742]);
  const flag=['boolean',['feature-state','pocketRaisedRoad'],false];
  assert.deepEqual(opacities.get('bridge_trunk_primary'),['case',flag,0,1]);
  assert.deepEqual(opacities.get('bridge_street_casing'),['interpolate',['linear'],['zoom'],
    12,['case',flag,0,0],12.5,['case',flag,0,1]]);
  states.get(1382658742).unrelated=true;
  assert.ok(updates.includes('bridge_trunk_primary_casing'));
  assert.ok(updates.every(k=>k.startsWith('bridge_')&&!/rail|pedestrian/.test(k)));
  const firstUploads=uploads.length;
  layer.render(gl,opts);assert.equal(uploads.length,firstUploads);
  map.terrain.getElevationAndDEMStateForLngLat=()=>({demState:'loaded',elevation:0});
  await f.fire('idle');layer.render(gl,opts);
  assert.deepEqual(layer.drawnIds,[near.id,east.id]);assert.equal(layer.missing,false);assert.equal(layer.timer,null);
  camera.box=[121.59,25.042,121.60,25.045];layer.render(gl,opts);
  assert.deepEqual(layer.drawnIds,[]);assert.deepEqual(states.get(1382658742),{unrelated:true});assert.deepEqual(states.get(3000),{});assert.deepEqual(states.get(97002),{});assert.equal(states.has(3002),false);
  assert.equal(uploads.at(-1),0);
});

test('deck pigments follow weather without rebuilding geography; a lost terrain tile restores the original way paint',async t=>{
  const f=fixture(),{map,camera,gl,colors,states,uploads}=f;
  camera.zoom=18;const layer=new TaipeiRoadBridges([near]);layer.onAdd(map,gl);t.after(()=>layer.onRemove(map,gl));
  layer.render(gl,opts);assert.deepEqual(colors.at(-1),color(asphaltColors.day));
  await f.fire('pocketasphalt',{color:asphaltColors.rain});layer.render(gl,opts);
  assert.deepEqual(colors.at(-1),color(asphaltColors.rain));assert.equal(uploads.length,1);
  map.getGlobalState=()=>({taipeiAsphalt:asphaltColors.cloudy});layer.render(gl,opts);
  assert.deepEqual(colors.at(-1),color(asphaltColors.cloudy));assert.equal(uploads.length,1);
  const draws=f.draws.length;
  map.terrain.getDrawnElevationForLngLat=()=>undefined;
  await f.fire('sourcedata',{sourceId:'dem',sourceDataType:'content'});layer.render(gl,opts);
  assert.deepEqual(layer.drawnIds,[]);assert.equal(f.draws.length,draws);
  assert.deepEqual(states.get(1382658742),{});
});

test('zoom and district exit abort a pending index, release graphics and restore paint; re-entry and failed fetch retry cleanly',async t=>{
  const f=fixture(),{map,camera,fire,gl}=f,gets=[];
  t.mock.method(globalThis,'fetch',(_url,{signal})=>new Promise(resolve=>gets.push({signal,resolve})));
  t.mock.method(console,'warn',()=>{});
  const payload=gzipSync(JSON.stringify([near]));
  addTaipeiRoadBridges(map,'label');assert.equal(gets.length,0);
  camera.zoom=18;const old=fire('moveend');camera.zoom=14;await fire('moveend');assert.ok(gets[0].signal.aborted);
  camera.zoom=18;const second=fire('moveend');
  gets[0].resolve(new Response(payload));await old;assert.equal(map.getLayer(id),undefined);
  gets[1].resolve(new Response(null,{status:503}));await second;assert.equal(map.getLayer(id),undefined);
  const retry=fire('moveend');gets[2].resolve(new Response(payload));await retry;
  const layer=map.getLayer(id);layer.render(gl,opts);assert.deepEqual(layer.drawnIds,[near.id]);
  camera.box=[122,25,122.01,25.01];await fire('moveend');
  assert.equal(map.getLayer(id),undefined);assert.deepEqual(layer.drawnIds,[]);
  assert.deepEqual(f.deletions,['vao','buffer','program']);
  assert.equal(f.opacities.get('bridge_motorway'),null);
  assert.deepEqual(f.opacities.get('bridge_street_casing'),f.style.layers.find(l=>l.id==='bridge_street_casing').paint['line-opacity']);
  assert.equal(f.events.get('sourcedata').size,0);assert.equal(f.events.get('pocketasphalt').size,0);
  camera.box=[121.570,25.031,121.575,25.034];const again=fire('moveend');
  gets[3].resolve(new Response(payload));await again;assert.ok(map.getLayer(id));
  map.terrain=null;await fire('terrain');assert.equal(map.getLayer(id),undefined);
  await fire('remove');assert.equal(f.events.get('moveend').size,0);assert.equal(f.events.get('terrain').size,0);
});
