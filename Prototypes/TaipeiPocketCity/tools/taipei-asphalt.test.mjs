import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {applyBaseAsphalt,asphaltColors,asphalt} from '../taipei-asphalt.js';
import {taipeiBoundary} from '../taipei-road-boundary.js';
import {update101Weather} from '../taipei101-single-ground.js';

test('Taipei motor approaches and bridge inks match the landmark, with paths and rail untouched',()=>{
  const scene=gunzipSync(readFileSync(new URL('./fixtures/taipei101-pocket-city.html.gz',import.meta.url))).toString();
  assert.ok(scene.includes('"road":"'+asphaltColors.day+'"'));
  const layers=JSON.parse(readFileSync(new URL('../assets/base-style.json',import.meta.url))).layers;
  for(const id of ['road_minor','road_link','bridge_motorway_link','bridge_secondary_tertiary','bridge_street_casing']){
    const l=layers.find(l=>l.id===id),original=l.paint['line-color'];
    applyBaseAsphalt(l,taipeiBoundary);
    const value=l.paint['line-color'];
    assert.equal(value[4],original); // overview, other regions and tracks retain base colors
    assert.equal(value[6][3],original);
    assert.deepEqual(value[6][1],['all',['!=',['get','class'],'track'],['within',taipeiBoundary]]);
    assert.deepEqual(value[6][2],id.endsWith('_casing')?'#c7b7a1':asphalt);
  }
  for(const id of ['bridge_path_pedestrian','road_major_rail','tunnel_motorway','road_one_way_arrow']){
    const l=layers.find(l=>l.id===id),before=structuredClone(l);
    applyBaseAsphalt(l,taipeiBoundary);assert.deepEqual(l,before);
  }
});

test('switching weather swaps just the 101 ground image once and restores the original daylight art',()=>{
  const urls=[],source={updateImage:({url})=>urls.push(new URL(url))},map={getSource:()=>source};
  for(const mode of ['day','cloudy','drizzle','rain','rain','day'])update101Weather(map,mode);
  assert.deepEqual(urls.map(u=>u.pathname.split('/').pop()),[
    'taipei101-ground-cloudy.png','taipei101-ground-drizzle.png','taipei101-ground-rain.png','taipei101-single-ground.png']);
  for(const url of urls){
    const image=readFileSync(url);assert.equal(image.readUInt32BE(16),2048);assert.equal(image.readUInt32BE(20),2048);
  }
});
