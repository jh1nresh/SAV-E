import assert from 'node:assert/strict';
import test from 'node:test';
import {buildShop,storefrontCategory} from '../city-shopfronts.js';
import {dihuaNorthFronts} from '../dihua-north-frontages.js';
import {bookstoreId} from '../fuxing-block.js';

function shop(category, extra={}, fuxing=false){
  const vs=[], signNames=[];
  const row={id:'poi/node/100',name:'來源店名',center:[121.55,25.03],width:4,angle:0,category,...extra};
  const built=buildShop(vs,row,[0,0,0],1,{write(name){signNames.push(name);return [0,0,1,1];}},fuxing);
  assert.equal(built.row,row);
  assert.equal(built.count,vs.length/13);
  assert.deepEqual(signNames,[row.name]);
  return {vs,built};
}
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
function painted(vs,hex){
  const color=rgb(hex),points=[];
  for(let i=0;i<vs.length;i+=13)if(color.every((c,k)=>c===vs[i+3+k]))points.push(vs.slice(i,i+3));
  return points;
}

test('actual subtype chooses recognisable furniture independently of name and fallback label',()=>{
  const typeColors={hairdresser:'#ac6856',florist:'#d47774',bicycle:'#47877e',cafe:'#47877e',
    restaurant:'#f2dfb5',fast_food:'#f2dfb5',coffee:'#a87554',optician:'#494845'};
  for(const [category,tint] of Object.entries(typeColors)){
    const {vs}=shop(category);
    assert.ok(painted(vs,tint).length>=6,category);
    assert.deepEqual(shop(category,{name:'別的店名',categoryLabel:'商店'}).vs,vs);
  }
  assert.equal(painted(shop('clothes').vs,typeColors.hairdresser).length,0);
  assert.equal(painted(shop('grocery').vs,typeColors.florist).length,0);
  assert.equal(painted(shop('books').vs,typeColors.bicycle).length,0);
  assert.notDeepEqual(shop('restaurant').vs,shop('cafe').vs);
  assert.notDeepEqual(shop('cafe').vs,shop('coffee').vs);
  assert.deepEqual(storefrontCategory({category:'unexpected'}),['店家','retail']);
  assert.deepEqual(shop('unexpected',{name:'自行車髮廊咖啡館'}).vs,shop('unexpected').vs);
});

test('different width and bearing keep all fixtures in the matched bay and bound their geometry cost',()=>{
  for(const category of ['hairdresser','florist','bicycle','cafe','coffee','restaurant','fast_food','optician']){
    for(const width of [1.5,2.2,4,6,9]){
      const a=shop(category,{width,angle:0}).vs,b=shop(category,{width,angle:90}).vs;
      assert.equal(a.length,b.length);
      assert.ok(a.length/(13*3)<180);
      for(let i=0;i<a.length;i+=13){
        assert.ok(Number.isFinite(a[i]) && a[i]>=0 && a[i]<.82);
        assert.ok(Math.abs(a[i+1])<=width/2+.000001);
        assert.ok(a[i+2]>=0 && a[i+2]<=3.25);
        assert.ok(Math.abs(a[i+1]+b[i])<1e-9 && Math.abs(a[i]-b[i+1])<1e-9);
      }
    }
  }
});

test('authored arcade and Fuxing bookshop geometry retain precedence over generic trade fixtures',()=>{
  for (const row of dihuaNorthFronts){
    const actual=shop(row.category,row).vs;
    assert.deepEqual(shop('bicycle',{...row,category:'bicycle'}).vs,actual);
    assert.ok(actual.length>0);
  }
  const row={id:bookstoreId,center:[121.543674,25.027489],width:6};
  assert.deepEqual(shop('books',row,true).vs,shop('florist',row,true).vs);
  assert.notDeepEqual(shop('florist',row,false).vs,shop('florist',row,true).vs);
});
