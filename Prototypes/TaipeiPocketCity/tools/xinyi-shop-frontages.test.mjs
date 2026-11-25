import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {buildShop,addCityShopfronts} from '../city-shopfronts.js';
import {completeFrontagePack} from '../taipei-frontage-pack.js';
import {frontagePackIds,isXinyiShopWall} from '../xinyi-shop-frontages.js';

const bakery={id:'poi/node/12803393045',name:'初 CHU Bakery',category:'bakery',evidence:'near-wall',
  streetId:'road/way/51420588',buildingId:'building/way/1159644377',center:[121.56351214,25.04266575],
  angle:89.71,width:7.29,wall:[[121.56347601,25.04266592],[121.56354826,25.04266558]],groundZ:6.852,
  surveyBase:7.15,surveyTop:27.02,surveyTile:'1534_13853'};
const xinyi=()=>'信義區';

test('the neighborhood view requests local packs and requires an identified shop wall',()=>{
  const local={id:'local',bounds:[121.56,25.041,121.568,25.048]};
  const distant={id:'distant',bounds:[121.50,25.08,121.51,25.09]};
  assert.deepEqual(frontagePackIds([local,distant],16.7),[]);
  assert.deepEqual(frontagePackIds([local,distant],16.8),['local']);
  assert.deepEqual(frontagePackIds([local,distant],17.55),['local','distant']);
  assert.ok(isXinyiShopWall(bakery,xinyi));
  assert.ok(!isXinyiShopWall(bakery,()=>'松山區'));
  for(const patch of [{buildingId:null},{streetId:null},{wall:null},{evidence:'survey-near-wall'},{surveyTop:null}]){
    assert.ok(!isXinyiShopWall({...bakery,...patch},xinyi));
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

test('the normal shop layer switches between neighborhood and detailed bays on the same map',async t=>{
  const fallback={...bakery,id:'poi/node/2',buildingId:null,evidence:'survey-near-wall'};
  t.mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify([bakery,fallback])));
  const noop=()=>{}, tile=bakery.surveyTile, walls=new Set([tile]);
  let layer,zoom=17.05,repaint=null,built=[];
  const canvas={clientWidth:440,clientHeight:600,ownerDocument:{createElement:()=>({getContext:()=>null})}};
  const map={addLayer:l=>{layer=l;},getZoom:()=>zoom,getBounds:()=>({toArray:()=>[[121.561,25.041],[121.565,25.045]]}),
    getCenter:()=>({lng:121.563,lat:25.043}),getCanvas:()=>canvas,triggerRepaint:()=>repaint?.(),on:noop,off:noop};
  const gl=new Proxy({getShaderParameter:()=>true,getProgramParameter:()=>true,getParameter:()=>1024},
    {get:(obj,key)=>obj[key]??noop});
  const ui=addCityShopfronts(map,noop,undefined,ids=>{built=ids;},()=>walls,noop,xinyi);
  layer.onAdd(map,gl);
  t.after(()=>layer.onRemove());
  ui.setPacks(['p0_0']);
  if(ui.state().pending)await new Promise(resolve=>{repaint=resolve;});
  const render=()=>layer.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
  render();assert.deepEqual(built,[bakery.id]);
  zoom=17.7;render();assert.deepEqual(built,[bakery.id,fallback.id]);
  zoom=17.1;render();assert.deepEqual(built,[bakery.id]);
  zoom=16.6;render();assert.deepEqual(built,[]);
});

const data=process.env.POCKET_TAIPEI_DATA;
test('published Xinyi and Songyan shop rows match the real district, buildings and streets',{skip:!data},async()=>{
  const districts=JSON.parse(await readFile(join(data,'districts.geojson')));
  const [ring]=districts.features.find(f=>f.properties.name==='信義區').geometry.coordinates;
  function districtAt(x,y){
    let hit=false;
    for(let i=1;i<ring.length;i++){
      const [ax,ay]=ring[i-1],[bx,by]=ring[i];
      if((ay>y)!==(by>y)&&x<(bx-ax)*(y-ay)/(by-ay)+ax)hit=!hit;
    }
    return hit?'信義區':null;
  }
  const base=join(data,'city170-frontages'),rows=[];
  for(const file of await readdir(base)){
    if(!/^p\d+_\d+\.json\.gz$/.test(file))continue;
    rows.push(...completeFrontagePack(file.split('.')[0],JSON.parse(gunzipSync(await readFile(join(base,file))))));
  }
  const eligible=rows.filter(row=>isXinyiShopWall(row,districtAt));
  const buildable=eligible.filter(row=>row.surveyTop-Math.max(row.groundZ,row.surveyBase)>=1.9);
  const near=buildable.filter(({center:[x,y]})=>x>=121.557&&x<=121.564&&y>=25.0415&&y<=25.0465);
  assert.ok(buildable.length>=370&&near.length>=23);
  assert.ok(new Set(buildable.map(r=>r.street)).size>=90);
  assert.ok(new Set(buildable.map(r=>r.buildingId)).size>=230);
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
