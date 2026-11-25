import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
import {runningTrack} from '../city170-running-tracks.js';
import {surfaceFeature} from '../city170-ground.js';
import {onSongshanAthleticsField} from '../songshan-athletics.js';
import {campusBounds,showSchool} from '../school-camera.js';

const ring = (lo,hi) => [[lo,lo],[hi,lo],[hi,hi],[lo,hi],[lo,lo]];
const track = {type:'Feature',id:'pitch/relation/example',
  properties:{kind:'pitch',category:'track',sport:'running',lanes:'6'},
  geometry:{type:'Polygon',coordinates:[ring(0,.001),ring(.0001,.0009)]}};
const data=process.env.POCKET_TAIPEI_DATA;
const read=name=>JSON.parse(gunzipSync(readFileSync(join(data,'city170',name+'.json.gz'))));

test('indoor, elevated and unmeasured running surfaces do not invent lane counts',()=>{
  const [surface,paint]=runningTrack(track);
  assert.equal(surface.geometry, track.geometry);
  assert.equal(paint.geometry.coordinates.length,5);
  assert.deepEqual(paint.geometry.coordinates.map(r=>r.length),[5,5,5,5,5]);
  for (const lanes of [null,'',1,3.4,'6;4',11]) {
    assert.equal(runningTrack({...track,properties:{...track.properties,lanes}}).length,1);
  }
  for (const tags of [{sport:'cycling'},{kind:'road'},{covered:'yes'},{indoor:'yes'},{layer:1},{offGround:true}]) {
    assert.equal(runningTrack({...track,properties:{...track.properties,...tags}}),undefined);
  }
  assert.equal(runningTrack({...track,geometry:{type:'Polygon',coordinates:[ring(0,.001)]}}),undefined);
});

test('school search fits the whole named campus and retains point-only school lookup',()=>{
  const polygons=[{id:'school/way/1',properties:{kind:'school',name:'同名學校'},geometry:{type:'MultiPolygon',
    coordinates:[[ring(0,1)],[ring(2,3)]]}}];
  const bounds=campusBounds(polygons);
  assert.deepEqual([...bounds],[['label/school/way/1',[[0,0],[3,3]]]]);
  let jumped;
  const map={getBearing:()=>47,getCanvas:()=>({clientWidth:390,clientHeight:670}),
    cameraForBounds:(b,o)=>{assert.deepEqual(b,[[0,0],[3,3]]);assert.equal(o.bearing,47);
      assert.ok(o.padding.top>90);return {center:[1.5,1.5],zoom:15.5};},jumpTo:c=>{jumped=c;}};
  showSchool(map,{center:[.5,.5],bounds:bounds.get('label/school/way/1')});
  assert.deepEqual(jumped,{center:[1.5,1.5],zoom:15.5,pitch:38,bearing:47});
  showSchool(map,{center:[4,4]});
  assert.deepEqual(jumped,{center:[4,4],zoom:17.35,pitch:38});
});

test('real Xinyi and Songshan tracks preserve the infield and evidenced lane count',{skip:!data},()=>{
  const rows=[...read('p225_2037').features.features,...read('p224_2037').features.features];
  const find=id=>rows.find(f=>f.id===id);
  assert.equal(runningTrack(find('pitch/relation/5962939'))[1].geometry.coordinates.length,5);
  assert.equal(runningTrack(find('pitch/relation/5012216')).length,1);
  const lap=surfaceFeature(find('pitch/way/1469168936'));
  assert.equal(lap.geometry.type,'LineString');
  assert.equal(lap.properties.lanes,'6');
  assert.equal(lap.properties.kind,'track-axis');
  assert.equal(runningTrack(find('pitch/relation/7932249'))[0].geometry.coordinates.length,2);
  assert.equal(find('park/way/281751128').properties.category,'recreation_ground');
  const schools=read('schools').features, bounds=campusBounds(schools);
  const named=schools.filter(f=>f.properties.kind==='school-label');
  assert.ok(named.filter(f=>bounds.has(f.id)).length>=380);
});

test('the Taipei Sports Park infield is clear of illustrated trees while surrounding park trees remain',{skip:!data},()=>{
  const readPack=path=>JSON.parse(gunzipSync(readFileSync(join(data,path+'.json.gz'))));
  const life=Object.values(readPack('city170-life/p224_2037').objects).filter(o=>o[2]==='tree');
  const groves=Object.values(readPack('city170-prepared/224_2037')).flat()
    .filter(f=>f.properties.kind==='grove-tree').map(f=>f.geometry.coordinates);
  for (const [trees,collisions] of [[life,8],[groves,6]]) {
    assert.equal(trees.filter(([x,y])=>onSongshanAthleticsField(x,y)).length,collisions);
    assert.ok(trees.length>collisions);
  }
  const official=readPack('city170-nature/p224_2037');
  assert.equal(official.filter(([x,y])=>onSongshanAthleticsField(x,y)).length,0);
});
