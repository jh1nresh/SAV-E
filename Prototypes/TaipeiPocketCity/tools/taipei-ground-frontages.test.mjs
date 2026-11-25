import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {addressFronts} from '../taipei-address-frontages.js';
import {surveyFronts} from '../taipei-survey-frontages.js';
import {edgeFronts} from '../taipei-edge-frontages.js';
import {registeredFronts} from '../taipei-registered-frontages.js';
import {compactFronts} from '../taipei-compact-frontages.js';
import {groundFronts} from '../taipei-ground-frontages.js';
import {completeFrontagePack,frontageSearchRow} from '../taipei-frontage-pack.js';
import {surveyedShopCamera} from '../city-shop-search.js';
import {buildShop} from '../city-shopfronts.js';
import * as views from '../taipei-frontage-cameras.js';

const supplements=[...groundFronts,...addressFronts,...surveyFronts,...compactFronts,...edgeFronts];

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

test('edge frontages share measured walls and safe views with the actual shop renderer',()=>{
  assert.equal(new Set(supplements.map(row=>row.id)).size,supplements.length);
  assert.equal(edgeFronts.length,5);
  assert.equal(new Set(edgeFronts.map(row=>row.district)).size,4);
  for(const row of edgeFronts){
    assert.equal(row.evidence,'ground-pin-measured-edge');
    assert.equal(row.frontageLocator,'ground-shop-pin');
    assert.ok(['survey-roof','local-osm-wall'].includes(row.footprintEvidence));
    assert.ok(row.footprintEvidence!=='local-osm-wall'||row.buildingId);
    assert.ok(row.width>=2.45&&row.width<=4.2);
    assert.ok(row.surveyTile&&row.streetId);
    const delta=[(row.center[0]-row.poiCenter[0])*100780,(row.center[1]-row.poiCenter[1])*110800];
    assert.ok(Math.hypot(...delta)<=3.06,row.id);
    const entry=frontageSearchRow([row.name,row.district,row.street,...row.poiCenter,null,row.id]);
    assert.ok(Object.hasOwn(views.frontageViews,row.id));
    for(const [clientWidth,clientHeight] of [[390,845],[1050,845]]){
      // Interpolated viewport anchors may decline a partial preset.
      const pose=surveyedShopCamera(entry,views,{clientWidth,clientHeight});
      if(views.frontageViews[row.id]>=0)assert.ok(pose?.verifiedFrontage,row.id);
      if(views.frontageViews[row.id]<0&&!views.frontagePartialViews[row.id])assert.ok(!pose?.verifiedFrontage,row.id);
    }
    const vertices=[];
    const base=Math.max(row.surveyBase,row.groundZ)-row.groundZ;
    const scale=Math.min(1,(row.surveyTop-row.groundZ-base-.13)/3.25);
    const shop=buildShop(vertices,row,[0,0,base],scale,{write:()=>null});
    assert.ok(shop.count>=6&&shop.count<=450&&vertices.every(Number.isFinite),row.id);
  }
});

test('nearby cross-source identities with a parent doorplate keep their independent pins',
  {skip:!data&&'set POCKET_TAIPEI_DATA to restored Taipei assets'},()=>{
    const search=new Map(JSON.parse(gunzipSync(readFileSync(join(data,'city170-frontages/search.json.gz'))))
      .map(r=>[r[6],r]));
    for(const id of ['inspection/A-112411160-00940-7','poi/node/4083325656',
      'inspection/A-122717540-00001-7','poi/node/9504555261',
      'inspection/A-153928416-00001-7','poi/node/5110245039','poi/node/5551931024','poi/node/14085069784']){
      const pin=search.get(id);
      assert.equal(pin[5],null);
      assert.equal(pin[6],id);
      assert.deepEqual(frontageSearchRow(pin),pin);
      assert.ok(!groundFronts.some(row=>row.id===id));
    }
  });

test('verified registry floors add exposed shop fronts without adding merchant records',()=>{
  assert.deepEqual(registeredFronts.map(row=>row.id),[
    'poi/node/11390928051','poi/node/2300640533','poi/node/5095512233',
  ]);
  for(const row of registeredFronts){
    assert.equal(row.groundEvidence,'business-and-tax-addresses');
    assert.equal(row.frontageLocator,'municipal-address');
    assert.ok(row.addressNode.startsWith('node/'));
    assert.ok(!Object.hasOwn(row,'detail'));
    assert.ok(row.width>=2.45&&row.width<=4.2);
    assert.ok(row.surveyTop-row.groundZ>=2.3);
    const entry=[row.name,row.district,row.street,...row.poiCenter,null,row.id];
    assert.deepEqual(frontageSearchRow(entry).slice(3),[...row.center,row.angle,row.id]);
    assert.equal(completeFrontagePack(row.pack,[]).filter(r=>r.id===row.id).length,1);
    assert.ok(Object.hasOwn(views.frontageViews,row.id));
    const vertices=[];
    const base=Math.max(row.surveyBase,row.groundZ)-row.groundZ;
    const scale=Math.min(1,(row.surveyTop-row.groundZ-base-.13)/3.25);
    const shop=buildShop(vertices,row,[0,0,base],scale,{write:()=>null});
    assert.ok(shop.count>=6&&shop.count<=540&&vertices.every(Number.isFinite),row.id);
  }
});
