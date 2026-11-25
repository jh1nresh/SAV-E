import assert from 'node:assert/strict';
import test from 'node:test';
import {buildShop} from '../city-shopfronts.js';

const retail=['convenience','supermarket','clothes','bakery','pastry','beverages','chemist'];
function draw(category,width=4,angle=0,extra={}){
  const vs=[], names=[];
  const row={id:'shop/200',category,name:'街口店家',width,angle,center:[121.52,25.04],...extra};
  buildShop(vs,row,[0,0,0],1,{write:n=>{names.push(n);return [0,0,1,1];}},true);
  assert.deepEqual(names,[row.name]);
  return vs;
}
test('retail merchandise has distinct silhouettes even without color, name or texture',()=>{
  const silhouettes=new Set();
  for(const category of retail){
    const vertices=draw(category);
    const positions=vertices.filter((_,i)=>i%13<3);
    silhouettes.add(JSON.stringify(positions));
    assert.deepEqual(draw(category,4,0,{name:'另一個名字',categoryLabel:'店家'}),vertices);
  }
  assert.equal(silhouettes.size,retail.length);
  assert.deepEqual(draw('unknown',4,0,{name:'藥妝麵包烘焙精品服飾'}),draw('unknown'));
});

test('retail fittings stay within the measured bay at any representative width and bearing',()=>{
  for(const category of retail)for(const width of [1.5,2.45,4,6,9]){
    const a=draw(category,width), b=draw(category,width,90);
    assert.equal(a.length,b.length);
    assert.ok(a.length/(13*3)<=180,category);
    for(let i=0;i<a.length;i+=13){
      assert.ok(a[i]>=0 && a[i]<.82);
      assert.ok(Math.abs(a[i+1])<=width/2+1e-6);
      assert.ok(a[i+2]>=0 && a[i+2]<=3.25);
      assert.ok(Math.abs(a[i] - b[i+1])<1e-8 && Math.abs(a[i+1]+b[i])<1e-8);
    }
  }
});
