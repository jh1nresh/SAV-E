import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {addressFronts} from '../taipei-address-frontages.js';
import {surveyFronts} from '../taipei-survey-frontages.js';
import {compactFronts} from '../taipei-compact-frontages.js';
import {groundFronts} from '../taipei-ground-frontages.js';
import {completeFrontagePack,frontageSearchRow} from '../taipei-frontage-pack.js';
import {surveyedShopCamera} from '../city-shop-search.js';
import * as views from '../taipei-frontage-cameras.js';

const supplements=[...groundFronts,...addressFronts,...surveyFronts,...compactFronts];

test('citywide ground-floor additions use the same wall for browsing and search',()=>{
  assert.equal(new Set(groundFronts.map(r=>r.district)).size,12);
  assert.equal(new Set(groundFronts.map(r=>r.id)).size,groundFronts.length);
  for(const row of supplements){
    const original=[row.name,row.district,row.street,...row.poiCenter,null,row.id];
    assert.deepEqual(frontageSearchRow(original).slice(3),[...row.center,row.angle,row.id]);
    assert.equal(completeFrontagePack(row.pack,[]).filter(r=>r.id===row.id).length,1);
    const primary={...row,source:'newer pack'};
    assert.deepEqual(completeFrontagePack(row.pack,[primary]).filter(r=>r.id===row.id),[primary]);
    assert.ok(['tagged-ground','single-storey-footprint'].includes(row.groundEvidence));
    assert.ok(row.wall.length===2 && row.width>=2.4 && row.width<=4.2 && row.surveyTop>=row.groundZ+2.3);
  }
});

const data=process.env.POCKET_TAIPEI_DATA;
test('each new wall corrects an actual pin-only record in its source pack',
  {skip:!data&&'set POCKET_TAIPEI_DATA to restored Taipei assets'},()=>{
    const read=file=>JSON.parse(gunzipSync(readFileSync(join(data,file))));
    const search=new Map(read('city170-frontages/search.json.gz').map(row=>[row[6],row]));
    for(const row of supplements){
      const original=search.get(row.id);
      assert.equal(original[5],null);
      assert.deepEqual(original.slice(3,5),row.poiCenter);
      assert.ok(!read('city170-frontages/'+row.pack+'.json.gz').some(f=>f.id===row.id));
    }
  });

test('compact bays use surveyed wall strips and only offer preflighted close-up cameras',()=>{
  assert.equal(new Set(compactFronts.map(row=>row.id)).size,compactFronts.length);
  assert.ok(compactFronts.length>0);
  for(const row of compactFronts){
    assert.equal(row.evidence,'compact-measured-street-wall');
    assert.ok(row.width>=2.45&&row.width<=3.8);
    assert.ok(row.buildingId&&row.streetId&&row.surveyTile);
    assert.ok(Object.hasOwn(views.frontageViews,row.id));
    const entry=frontageSearchRow([row.name,row.district,row.street,...row.poiCenter,null,row.id]);
    const phone=surveyedShopCamera(entry,views,{clientWidth:390,clientHeight:845});
    const hasView=views.frontageViews[row.id]>=0||views.frontagePartialViews[row.id]?.[2]>=0;
    assert.equal(!!phone?.verifiedFrontage,hasView,row.id);
  }
});

test('nearby cross-source identities with a parent doorplate keep their independent pins',
  {skip:!data&&'set POCKET_TAIPEI_DATA to restored Taipei assets'},()=>{
    const search=new Map(JSON.parse(gunzipSync(readFileSync(join(data,'city170-frontages/search.json.gz'))))
      .map(r=>[r[6],r]));
    for(const id of ['inspection/A-112411160-00940-7','poi/node/4083325656',
      'inspection/A-122717540-00001-7','poi/node/9504555261']){
      const pin=search.get(id);
      assert.equal(pin[5],null);
      assert.equal(pin[6],id);
      assert.deepEqual(frontageSearchRow(pin),pin);
      assert.ok(!groundFronts.some(row=>row.id===id));
    }
  });
