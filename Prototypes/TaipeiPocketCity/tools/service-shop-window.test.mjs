import assert from 'node:assert/strict';
import test from 'node:test';
import {buildShop} from '../city-shopfronts.js';
import {neighborhoodServiceLabels,serviceWindowLabels} from '../shop-service-labels.js';
import {streetShopProperties} from '../shop-trades.js';

const atlas={write:()=>[0,0,1,1]};
function draw(category,width=4,angle=0,name='街口商店'){
  const vertices=[];
  buildShop(vertices,{id:'sample/1',category,name,angle,width,center:[121.541,24.997]},
    [0,0,0],1,atlas,true);
  return vertices;
}
const silhouette=vertices=>vertices.filter((_,i)=>i%13<3);

test('an explicitly tagged service shop gets trade-specific equipment without using the shop name',()=>{
  const shapes=new Set();
  for(const category of serviceWindowLabels.keys()){
    const mesh=draw(category);
    assert.deepEqual(draw(category,4,0,'換名字'),mesh);
    assert.notDeepEqual(silhouette(mesh),silhouette(draw('clothes')));
    assert.notDeepEqual(silhouette(mesh),silhouette(draw('unknown')));
    shapes.add(JSON.stringify(silhouette(mesh)));
  }
  // Hardware and DIY use the same tool display. Other equipment is physically distinct.
  assert.equal(shapes.size,serviceWindowLabels.size-1);
  assert.deepEqual(draw('unknown',4,0,'鞋店美容五金汽車修護'),draw('unknown'));
});

test('service displays scale and rotate inside the surveyed storefront at the city mesh budget',()=>{
  for(const category of serviceWindowLabels.keys())for(const width of [1.5,2.8,5.6,5.7,9]){
    const a=draw(category,width),b=draw(category,width,90);
    assert.equal(a.length,b.length);
    assert.ok(a.length/(13*3)<=150,category);
    for(let i=0;i<a.length;i+=13){
      assert.ok(a[i]>=0 && a[i]<.82 && Math.abs(a[i+1])<=width/2+1e-8);
      assert.ok(a[i+2]>=0 && a[i+2]<=3.25);
      assert.ok(Math.abs(a[i]-b[i+1])<1e-8 && Math.abs(a[i+1]+b[i])<1e-8);
    }
  }
});

test('point and search cards localize documented motorcycle shops while preserving source descriptions',()=>{
  for(const [id,category,label] of [['poi/node/11406970586','motorcycle_repair','機車維修'],['poi/node/11390928032','motorcycle','機車行']]){
    const place={id,category,categoryLabel:category,detail:category};
    assert.deepEqual(streetShopProperties(place),{...place,categoryLabel:label,detail:label});
    const exact={...place,categoryLabel:'重型機車專賣店'};
    assert.equal(streetShopProperties(exact),exact);
  }
});

test('neighborhood-service cards only localize explicit categories and keep specific source labels',()=>{
  for(const [category,label] of [['baby_goods','嬰童用品'],['pet_grooming','寵物美容'],['outpost','包裹取貨點']]){
    assert.deepEqual(streetShopProperties({id:'shop/verified',category,categoryLabel:category,detail:category}),
      {id:'shop/verified',category,categoryLabel:label,detail:label});
  }
  const woodware={id:'shop/woodware',category:'houseware',categoryLabel:'竹木器店',detail:'竹木器店'};
  assert.equal(streetShopProperties(woodware),woodware);
  assert.deepEqual(draw('yes',4,0,'嬰童用品維修'),draw('yes'));
});

test('decorating a neighborhood shop keeps the coordinates of the original door and windows',()=>{
  // Select the renderer's door and window frame, panes and highlights by their facade depth.
  const openings=[.025,.041,.049,.053,.020,.038,.042];
  function frames(vertices){
    const points=[];
    for(let i=0;i<vertices.length;i+=13){
      if(openings.some(depth=>Math.abs(vertices[i]-(.14+depth))<1e-8)){
        points.push(vertices.slice(i,i+3));
      }
    }
    return points;
  }
  // Shelves and stock in the generic fixture use other depths than the openings.
  for(const category of neighborhoodServiceLabels.keys()){
    for(const width of [2.45,4.10,5.6,5.7,8]){
      const mapped=frames(draw(category,width));
      const original=frames(draw('unknown',width));
      // Some legacy paint details decorate both windows at the door-handle depth.
      const structural=points=>points.filter(([, ,z],i)=>
        Math.abs(points[i][0]-.193)>1e-8||z===1.07||z===1.40);
      assert.deepEqual(structural(mapped),structural(original),category);
    }
  }
});
