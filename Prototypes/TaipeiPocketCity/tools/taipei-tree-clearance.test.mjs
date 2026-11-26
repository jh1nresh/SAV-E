import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {StreetScenery} from '../street-scenery.js';
import {MercatorCoordinate} from '../assets/maplibre-gl.mjs';
import {insideRing} from '../authored-footprint.js';
import {misplacedIllustratedTree} from '../taipei-illustrated-trees.js';

test('the legacy scenery renderer removes only trees at a conflicting root',()=>{
  const root=[121.5714960,25.0320072];
  const neighbour=[root[0]+.00002,root[1]];
  const scene=new StreetScenery('road',root,[[...root,'tree',1,0,0],[...root,'street-light',1,0,0],
    [...neighbour,'tree',1,0,0]],MercatorCoordinate,false,true);
  assert.deepEqual(scene.objects.map(p=>[p.point,p.kind]),[[root,'street-light'],[neighbour,'tree']]);
});

const data=process.env.POCKET_TAIPEI_DATA;
test('both raw illustrated tree layers clear the Yingfeng soccer field without clearing the surrounding park',
  {skip:!data},()=>{
  const read=name=>JSON.parse(gunzipSync(readFileSync(join(data,name+'.json.gz'))));
  const pack='p224_2039';
  const field=read('city170/'+pack).features.features.find(f=>f.id==='pitch/way/596345093');
  const ring=field.geometry.coordinates[0];
  const grove=Object.values(read('city170-prepared/'+pack.slice(1))).flat()
    .filter(f=>f.properties.kind==='grove-tree').map(f=>f.geometry.coordinates);
  const scenery=Object.values(read('city170-life/'+pack).objects).filter(r=>r[2]==='tree');
  for(const [rows,expected] of [[grove,14],[scenery,8]]){
    const onField=rows.filter(([x,y])=>insideRing(ring,x,y));
    assert.equal(onField.length,expected);
    assert.ok(onField.every(([x,y])=>misplacedIllustratedTree(x,y)));
    assert.ok(rows.some(([x,y])=>!insideRing(ring,x,y)&&!misplacedIllustratedTree(x,y)));
  }
});
