import {test} from 'node:test';
import assert from 'node:assert/strict';
import {addCityAirfield} from '../city170-airfield.js';

test('civilian pavement and cartographic paths stay below roads, load on demand and have no labels',async t=>{
  let zoom=15,x=120,loads=0,drawn;
  const listeners=new Map(),layers=[];
  const data={type:'FeatureCollection',features:[]};
  const map={
    getStyle:()=>({layers:[{id:'park'},{id:'street','source-layer':'transportation'},{id:'building','source-layer':'building'},{id:'label'}]}),
    addSource(){},getSource:()=>({setData:value=>{drawn=value;}}),
    addLayer:(layer,before)=>layers.push([layer,before]),on:(name,fn)=>listeners.set(name,fn),off:(name)=>listeners.delete(name),
    getZoom:()=>zoom,getBounds:()=>({getWest:()=>x,getEast:()=>x+.002,getSouth:()=>25.065,getNorth:()=>25.066}),
  };
  t.mock.method(globalThis,'fetch',async()=>{loads++;return Response.json(data);});
  addCityAirfield(map,'label');
  assert.equal(loads,0);
  assert.deepEqual(layers.map(([l,b])=>[l.type,l.minzoom,b]),[['fill',15,'street'],['line',15,'street']]);
  x=121.552;zoom=14;await listeners.get('moveend')();assert.equal(loads,0);
  zoom=18;await listeners.get('moveend')();assert.equal(loads,1);assert.deepEqual(drawn,data);
  assert.equal(listeners.has('moveend'),false);
});
