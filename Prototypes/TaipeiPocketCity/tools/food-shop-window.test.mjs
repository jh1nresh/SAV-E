import assert from 'node:assert/strict';
import test from 'node:test';
import {buildShop} from '../city-shopfronts.js';
import {categoryFoodWindow,cuisineWindow} from '../shop-food-windows.js';
import {mappedFoodWindow} from '../taipei-food-window-evidence.js';

const teaShop={id:'poi/node/3785981604',category:'cafe'};
const hotPot={id:'poi/node/4433646392',category:'restaurant'};
function draw(row,width=4,angle=0){
  const vs=[];
  buildShop(vs,{id:'sample',name:'商店',center:[121.5166,25.0302],width,angle,...row},
    [0,0,0],1,{write:()=>[0,0,1,1]},true);
  return vs;
}
test('寧波西街相鄰兩家店使用同一份 170m 地圖的料理證據',()=>{
  assert.equal(mappedFoodWindow(teaShop),'bubble-tea');
  assert.equal(mappedFoodWindow(hotPot),'hot-pot');
  assert.equal(mappedFoodWindow({...teaShop,category:'restaurant'}),undefined);
  assert.equal(mappedFoodWindow({...teaShop,id:teaShop.id.replace('/node/','/way/')}),undefined);
  assert.deepEqual(draw(teaShop),draw({...teaShop,cuisine:'bubble_tea'}));
  assert.deepEqual(draw(hotPot),draw({...hotPot,cuisine:'hotpot'}));
  assert.notDeepEqual(draw(teaShop),draw({...teaShop,cuisine:'coffee_shop'}));
  assert.notDeepEqual(draw(hotPot),draw({...hotPot,cuisine:'regional'}));
});
test('broad cuisines, names, and unrelated retailers cannot infer a signature dish',()=>{
  for(const cuisine of ['japanese','chinese;regional','台灣',undefined]){
    assert.equal(cuisineWindow('restaurant',cuisine),null);
  }
  assert.equal(cuisineWindow('cafe',' cake ; Bubble_Tea '),'bubble-tea');
  assert.equal(cuisineWindow('clothes','pizza'),null);
  assert.equal(cuisineWindow('restaurant','breakfast;burger;sandwich'),'burger-tray');
  assert.equal(cuisineWindow('restaurant','breakfast'),'morning-griddle');
  assert.equal(cuisineWindow('restaurant','breadfast'),null);
  assert.equal(cuisineWindow('clothes','breakfast'),null);
  assert.equal(categoryFoodWindow('inspection_store',0),'pickup-counter');
  assert.equal(categoryFoodWindow('commerce_store',0,'餐飲店家'),'pickup-counter');
  assert.equal(categoryFoodWindow('commerce_store',0,'特色店家'),null);
  assert.equal(cuisineWindow('tea','tea'),null);
  assert.deepEqual(draw({category:'restaurant'}),draw({category:'restaurant',name:'火鍋拉麵珍珠奶茶'}));
  assert.deepEqual(new Set([0,1,2].map(seed=>categoryFoodWindow('restaurant',seed))),
    new Set(['dining','menu-stand','sideboard']));
  assert.deepEqual(draw({category:'restaurant',cuisine:'chinese'}),draw({category:'restaurant'}));
});
test('typed dish displays retain distinct geometry, fit the wall, and rotate with it',()=>{
  const rows=['hotpot','dumplings','beef_noodle','sushi','burger','pizza',
    'breakfast','sandwich','teppanyaki','barbecue','seafood','beef_bowl','curry','dessert','bento'].map(cuisine=>({category:'restaurant',cuisine}));
  rows.push({category:'cafe',cuisine:'bubble_tea'},{category:'cafe',cuisine:'tea'},{category:'cafe',cuisine:'coffee_shop'},
    ...['tea','ice_cream','pub','deli','fast_food'].map(category=>({category})));
  const shapes=new Set(rows.map(row=>JSON.stringify(draw(row).filter((_,i)=>i%13<3))));
  assert.equal(shapes.size,rows.length);
  for(const row of rows)for(const width of [1.5,3,5.6,5.7,9]){
    const a=draw(row,width),b=draw(row,width,90);
    assert.equal(a.length,b.length);
    assert.ok(a.length/39<=180,row.category);
    for(let i=0;i<a.length;i+=13){
      assert.ok(a[i]>=0 && a[i]<=.82 && Math.abs(a[i+1])<=width/2+1e-8);
      assert.ok(a[i+2]>=0 && a[i+2]<=3.25);
      assert.ok(Math.abs(a[i]-b[i+1])<1e-8 && Math.abs(a[i+1]+b[i])<1e-8);
    }
  }
});
