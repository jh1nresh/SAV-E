import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {gzipSync,gunzipSync} from 'node:zlib';
import {frontageSearchRow} from '../taipei-frontage-pack.js';
import {readShopfrontPack,storefrontCategory} from '../city-shopfronts.js';
import {recoveredFronts} from '../taipei-shopfront-recoveries.js';

test('the searched store and wall share the same ID, view and source footprint',()=>{
  for(const record of recoveredFronts){
    assert.match(record.id,/^poi\/way\/[0-9]+$/);
    assert.equal(record.buildingId,record.id.replace('poi/','building/'));
    assert.ok(record.surveyTile&&record.wall.length===2&&record.surveyTop>record.groundZ+2.3);
    const old=[record.name,record.district,record.street,...record.poiCenter,null,record.id];
    assert.deepEqual(frontageSearchRow(old),[record.name,record.district,record.street,...record.center,record.angle,record.id]);
    const moved=[record.name,record.district,'新版實測街名',121,25,33,record.id];
    assert.deepEqual(frontageSearchRow(moved),moved);
    const other=[...old.slice(0,6),'poi/node/123'];
    assert.deepEqual(frontageSearchRow(other),other);
  }
  const entrance=recoveredFronts.find(r=>r.id==='poi/way/663589871');
  assert.equal(entrance.entranceId,'node/3676289823');
});
test('draw a supplement once, with both raw gzip and an already-decoded HTTP body',async t=>{
  const row=recoveredFronts[0],primary={id:'poi/node/555'};
  let payload=[primary],raw=true;
  t.mock.method(globalThis,'fetch',async()=>new Response(raw?gzipSync(JSON.stringify(payload)):JSON.stringify(payload)));
  assert.deepEqual((await readShopfrontPack(row.pack)).filter(p=>p.id===row.id),[row]);
  raw=false;payload=[primary,{...row,name:'現有資料的店名'}];
  const both=await readShopfrontPack(row.pack);
  const claimed=both.filter(p=>p.id===row.id);
  assert.equal(claimed.length,1);assert.equal(claimed[0].name,'現有資料的店名');
  assert.deepEqual(await readShopfrontPack('p999_999'),payload);
});
test('public source categories select existing storefront families and preserve unspecified retail',()=>{
  assert.deepEqual(storefrontCategory({category:'beverages'}),['飲料店','grocery']);
  assert.deepEqual(storefrontCategory({category:'pastry'}),['西點店','cafe']);
  assert.equal(storefrontCategory({category:'commerce_store',categoryLabel:'餐飲店家'})[1],'meal');
  assert.equal(storefrontCategory({category:'commerce_store',categoryLabel:'特色店家'})[1],'retail');
});
const data=process.env.POCKET_TAIPEI_DATA;
test('every recovered store was an existing unmatched city POI and has a real surveyed wall tile',
  {skip:!data&&'set POCKET_TAIPEI_DATA to the restored published dataset'},()=>{
    const read=(file)=>JSON.parse(gunzipSync(readFileSync(join(data,file))));
    const search=new Map(read('city170-frontages/search.json.gz').map(r=>[r[6],r]));
    for(const row of recoveredFronts){
      const original=search.get(row.id);
      assert.equal(original[5],null);assert.deepEqual(original.slice(3,5),row.poiCenter);
      assert.ok(!read('city170-frontages/'+row.pack+'.json.gz').some(r=>r.id===row.id));
      assert.ok(readFileSync(join(data,'200',row.surveyTile+'.bin.gz')).length>0);
    }
  });

test('the two shop pins retain their identity throughout the Dihua arcade',async()=>{
  const {dihuaNorthFronts}=await import('../dihua-north-frontages.js');
  const {withShopFacts,completeFrontagePack}=await import('../taipei-frontage-pack.js');
  const {drawDihuaShop}=await import('../dihua-shop-art.js');
  const shops=completeFrontagePack('p221_2038',[]);
  for(const row of dihuaNorthFronts){
    assert.equal(shops.filter(s=>s.id===row.id).length,1);
    assert.equal(completeFrontagePack('p000_000',[]).length,0);
    const pin={id:row.id,properties:{placeId:row.id,category:'convenience',name:row.name}};
    assert.equal(withShopFacts(pin).properties.categoryLabel,row.categoryLabel);
    const search=frontageSearchRow([row.name,'大同區','',...row.poiCenter,null,row.id]);
    assert.deepEqual(search.slice(3),[...row.center,row.angle,row.id]);
    const vertices=[],plaques=[];
    const geometry={half:row.width/2,point:(...p)=>p,quad:pts=>vertices.push(...pts),
      panel:(a,b,lo,hi,d)=>vertices.push([a,lo,d],[b,hi,d]),rgb:x=>x,plaque:(...args)=>plaques.push(args)};
    assert.equal(drawDihuaShop(row,geometry),true);
    assert.equal(plaques.length,1);
    assert.ok(vertices.every(([x,z,depth])=>Number.isFinite(x+z+depth)&&
      Math.abs(x)<=row.width/2+.025 && z>=0 && z<=3.25 && depth<=row.arcadeDepth+.14));
  }
  const other={properties:{placeId:'poi/node/123',name:'其他店'}};
  assert.equal(withShopFacts(other),other);
  assert.equal(drawDihuaShop(other,{}),false);
});
