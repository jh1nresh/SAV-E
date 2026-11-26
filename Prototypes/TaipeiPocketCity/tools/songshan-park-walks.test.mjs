import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {parkWalksForPack} from '../songshan-park-walks.js';

const way=557896961;
const points=[[121.5589973,25.0589339],[121.5590172,25.058721]];
const pack={id:'p225_2038',features:{features:[{id:'walk/way/'+way,geometry:{type:'LineString',coordinates:points}}]}};

test('a park walker follows the mapped footway once and stays in its own pack',()=>{
  const original={paths:{},objects:{}};
  const augmented=parkWalksForPack(pack,original);
  assert.deepEqual(augmented.paths['walk/way/'+way],{way,points,people:1});
  assert.equal(parkWalksForPack(pack,augmented),augmented);
  assert.equal(parkWalksForPack({...pack,id:'p224_2038'},original),original);
  assert.deepEqual(original.paths,{});
});

test('the three park walkers use existing Songshan ground-level paths', {skip:!process.env.POCKET_TAIPEI_DATA},async()=>{
  const read=async key=>JSON.parse(gunzipSync(await readFile(join(process.env.POCKET_TAIPEI_DATA,key+'/p225_2038.json.gz'))));
  const [streets,life]=await Promise.all([read('city170'),read('city170-life')]);
  const augmented=parkWalksForPack(streets,life);
  for(const way of [557896961,1471704252,1471704270]){
    const id='walk/way/'+way;
    const feature=streets.features.features.find(f=>f.id===id);
    assert.equal(feature.properties.category,'footway');
    assert.equal(feature.properties.layer??'0','0');
    assert.ok(['bridge','indoor','tunnel','covered'].every(k=>!feature.properties[k]||feature.properties[k]==='no'));
    assert.deepEqual(augmented.paths[id]?.points,feature.geometry.coordinates);
    assert.equal(augmented.paths[id]?.people,1);
  }
});
