import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {buildShop,addCityShopfronts} from '../city-shopfronts.js';
import {completeFrontagePack} from '../taipei-frontage-pack.js';
import {frontagePackIds,isNeighborhoodShopWall} from '../xinyi-shop-frontages.js';

const bakery={id:'poi/node/12803393045',name:'初 CHU Bakery',category:'bakery',evidence:'near-wall',
  streetId:'road/way/51420588',buildingId:'building/way/1159644377',center:[121.56351214,25.04266575],
  angle:89.71,width:7.29,wall:[[121.56347601,25.04266592],[121.56354826,25.04266558]],groundZ:6.852,
  surveyBase:7.15,surveyTop:27.02,surveyTile:'1534_13853'};
const aposo={id:'poi/node/12517900426',name:'Aposo',category:'bakery',evidence:'near-wall',
  streetId:'road/way/1371667013',buildingId:'building/way/764255602',center:[121.55667083,25.0513905],
  angle:88.55,width:7.6,wall:[[121.55663318,25.05139138],[121.55670847,25.05138961]],groundZ:16.07,
  surveyBase:4.99,surveyTop:42.95,surveyTile:'1530_13857'};
const xinyi=()=>'信義區';

test('the neighborhood view requests local packs and requires an identified shop wall',()=>{
  const local={id:'local',bounds:[121.56,25.041,121.568,25.048]};
  const songshan={id:'songshan',bounds:[121.546,25.052,121.55,25.058]};
  const boundary={id:'boundary',bounds:[121.557,25.046,121.56,25.05]};
  const distant={id:'distant',bounds:[121.50,25.08,121.51,25.09]};
  assert.deepEqual(frontagePackIds([local,distant],16.7),[]);
  assert.deepEqual(frontagePackIds([local,songshan,boundary,distant],16.8),['local','songshan','boundary']);
  assert.deepEqual(frontagePackIds([local,distant],17.55),['local','distant']);
  assert.ok(isNeighborhoodShopWall(bakery,xinyi));
  assert.ok(isNeighborhoodShopWall(bakery,()=>'松山區'));
  assert.ok(!isNeighborhoodShopWall(bakery,()=>'大安區'));
  for(const patch of [{kind:'market-area'},{vendor:true},{buildingId:null},{streetId:null},{wall:null},{evidence:'survey-near-wall'},{surveyTop:null}]){
    assert.ok(!isNeighborhoodShopWall({...bakery,...patch},xinyi));
  }
});

function checkStorefrontExtent(row,overview){
  const z=Math.max(row.surveyBase,row.groundZ),out=[],names=[];
  const shop=buildShop(out,row,[0,0,z],Math.min(1,(row.surveyTop-z-.13)/3.25),
    {write:name=>{names.push(name);return null;}},false,overview);
  const angle=row.angle*Math.PI/180,along=[-Math.sin(angle),Math.cos(angle)];
  let high=-Infinity;
  for(let i=0;i<out.length;i+=13){
    const [x,y,h]=out.slice(i,i+3);
    assert.ok(Number.isFinite(x+y+h));
    assert.ok(Math.abs(x*along[0]+y*along[1])<=row.width/2+.00001,row.name);
    assert.ok(h>=z&&h<=z+3.25001,`${row.name} draws across the survey windows at ${h-z} m`);
    high=Math.max(high,h);
  }
  assert.ok(high>z+2.5);
  return {out,names,shop};
}

test('true storefronts keep their name, picking area and projecting cornice below the survey windows',()=>{
  const near=checkStorefrontExtent(bakery,false),mid=checkStorefrontExtent(bakery,true);
  assert.deepEqual(near.shop.hit,mid.shop.hit);
  assert.equal(near.shop.first,0);
  assert.deepEqual(near.names,[bakery.name]);
  assert.deepEqual(mid.names,[]);
  assert.ok(mid.out.length<near.out.length);
  const angle=bakery.angle*Math.PI/180;
  for(const {out} of [near,mid]){
    const lip=[];
    for(let i=0;i<out.length;i+=13){
      const [x,y,h]=out.slice(i,i+3);
      if(Math.abs(h-bakery.surveyBase-3.25)<1e-7)lip.push(x*Math.cos(angle)+y*Math.sin(angle));
    }
    assert.ok(Math.max(...lip)-Math.min(...lip)>.19);
  }
});

test('the normal shop layer draws a shared Songshan bay once across packs at either detail level',async t=>{
  const fallback={...aposo,id:'poi/node/2',buildingId:null,evidence:'survey-near-wall'};
  t.mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify([aposo,fallback])));
  const noop=()=>{}, tile=aposo.surveyTile, walls=new Set([tile]);
  let layer,zoom=17.05,repaint=null,built=[];
  const canvas={clientWidth:440,clientHeight:600,ownerDocument:{createElement:()=>({getContext:()=>null})}};
  const map={addLayer:l=>{layer=l;},getZoom:()=>zoom,getBounds:()=>({toArray:()=>[[121.554,25.050],[121.558,25.054]]}),
    getCenter:()=>({lng:121.556,lat:25.052}),getCanvas:()=>canvas,triggerRepaint:()=>repaint?.(),on:noop,off:noop};
  const gl=new Proxy({getShaderParameter:()=>true,getProgramParameter:()=>true,getParameter:()=>1024},
    {get:(obj,key)=>obj[key]??noop});
  const ui=addCityShopfronts(map,noop,undefined,ids=>{built=ids;},()=>walls,noop,()=>'松山區');
  layer.onAdd(map,gl);
  t.after(()=>layer.onRemove());
  // The synthetic pair repeats a source row as two neighboring packs can at an edge.
  ui.setPacks(['p0_0','p0_1']);
  if(ui.state().pending)await new Promise(resolve=>{
    repaint=()=>{if(!ui.state().pending)resolve();};
  });
  assert.equal(ui.state().loaded,2);
  const render=()=>layer.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  render();assert.deepEqual(built,[aposo.id]);
  zoom=17.7;render();assert.deepEqual(built,[aposo.id,fallback.id]);
  zoom=17.1;render();assert.deepEqual(built,[aposo.id]);
  zoom=16.6;render();assert.deepEqual(built,[]);
});

const data=process.env.POCKET_TAIPEI_DATA;
test('published Songshan and Xinyi shops use identified surveyed bays and keep Raohe market separate',{skip:!data},async()=>{
  const districts=JSON.parse(await readFile(join(data,'districts.geojson')));
  function inside(ring,x,y){
    let hit=false;
    for(let i=1;i<ring.length;i++){
      const [ax,ay]=ring[i-1],[bx,by]=ring[i];
      if((ay>y)!==(by>y)&&x<(bx-ax)*(y-ay)/(by-ay)+ax)hit=!hit;
    }
    return hit;
  }
  const shapes=districts.features.filter(f=>['松山區','信義區'].includes(f.properties.name));
  const districtAt=(x,y)=>shapes.find(f=>inside(f.geometry.coordinates[0],x,y))?.properties.name;
  const base=join(data,'city170-frontages'),rows=[];
  for(const file of await readdir(base)){
    if(!/^p\d+_\d+\.json\.gz$/.test(file))continue;
    rows.push(...completeFrontagePack(file.split('.')[0],JSON.parse(gunzipSync(await readFile(join(base,file))))));
  }
  const eligible=rows.filter(row=>isNeighborhoodShopWall(row,districtAt));
  const buildable=eligible.filter(row=>row.surveyTop-Math.max(row.groundZ,row.surveyBase)>=1.9);
  assert.equal(new Set(buildable.map(r=>r.id)).size,buildable.length);
  const songshan=buildable.filter(r=>districtAt(...r.center)==='松山區');
  assert.ok(songshan.length>=347);
  assert.ok(new Set(songshan.map(r=>r.buildingId)).size>=273);
  const nanjing=songshan.filter(r=>/^南京東路[一二三四五六]段$/.test(r.street));
  assert.ok(nanjing.length>=59);
  const matched=nanjing.find(row=>row.id===aposo.id);
  for(const key of Object.keys(aposo))assert.deepEqual(matched[key],aposo[key]);
  checkStorefrontExtent(matched,true);
  const raohe=songshan.filter(r=>r.street==='饒河街');
  for(const name of ['58海南河粉 越南法國麵包','娃娃瘋']){
    const shop=raohe.find(r=>r.name===name);
    assert.equal(shop?.evidence,'street-address',name);
    checkStorefrontExtent(shop,true);
  }
  const markets=JSON.parse(gunzipSync(await readFile(join(data,'city170-markets.json.gz'))));
  const nightMarket=markets.features.find(f=>f.properties.name.includes('饒河'));
  assert.equal(nightMarket.properties.kind,'market-area');
  assert.ok(!buildable.some(r=>r.id===nightMarket.id));
  const xinyiRows=buildable.filter(r=>districtAt(...r.center)==='信義區');
  const near=xinyiRows.filter(({center:[x,y]})=>x>=121.557&&x<=121.564&&y>=25.0415&&y<=25.0465);
  assert.ok(xinyiRows.length>=370&&near.length>=23);
  assert.ok(new Set(xinyiRows.map(r=>r.street)).size>=90);
  assert.ok(new Set(xinyiRows.map(r=>r.buildingId)).size>=230);
  // Regression from the 553 alley view: four independently anchored tenants
  // used to draw four shifted grids over the long building's survey glazing.
  const alley=buildable.filter(r=>['poi/node/4325693477','poi/node/4325693920',
    'poi/node/4384257962','poi/node/4384257988'].includes(r.id));
  assert.equal(alley.length,4);
  assert.equal(new Set(alley.map(r=>r.buildingId)).size,1);
  for(const row of alley){
    checkStorefrontExtent(row,false);
    checkStorefrontExtent(row,true);
  }
  const actual=near.find(row=>row.id===bakery.id);
  for(const key of ['buildingId','streetId','surveyTile','center','wall'])assert.deepEqual(actual[key],bakery[key]);
});
