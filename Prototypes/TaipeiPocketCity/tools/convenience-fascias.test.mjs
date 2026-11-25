import assert from 'node:assert/strict';
import test from 'node:test';

import {buildShop} from '../city-shopfronts.js';
import {convenienceFascia} from '../shop-convenience-fascias.js';
import {storeBrandGroups} from '../taipei-convenience-art.js';

const groups=new Map();
const samples=new Map();
const identities=new Set();
for(const [brand,kind,ids] of storeBrandGroups){
  for(const id of ids.split(' ')){
    const placeId='poi/'+kind+'/'+id;
    samples.set(brand,samples.get(brand)??placeId);
    groups.set(brand,(groups.get(brand)??0)+1);
    identities.add(placeId);
  }
}
const store=(id,width=4,name='街口商店',category='convenience')=>({
  id,width,name,category,angle:0,center:[121.51,25.05],
});
function draw(row){
  const vertices=[];
  const mesh=buildShop(vertices,row,[0,0,0],1,{write:()=>[0,0,1,1]});
  return {vertices,hit:mesh.hit,triangles:mesh.count/3};
}

test('frozen street frontages use unique recorded brand identities only for convenience rows',()=>{
  assert.deepEqual(Object.fromEntries(groups),{family:185,hilife:62,ok:20,seven:279,shopee:70});
  assert.equal(identities.size,616);
  const panels=new Set();
  for(const [brand,id] of samples){
    const fascia=convenienceFascia(store(id));
    assert.equal(fascia.brand,brand);
    assert.equal(convenienceFascia(store(id,4,'完全不同的店名')),fascia);
    assert.equal(convenienceFascia(store(id,4,'街口商店','bakery')),undefined);
    panels.add(JSON.stringify(fascia.bands));
    const luminance=rgb=>rgb.reduce((value,channel,i)=>{
      const linear=channel<=.04045?channel/12.92:((channel+.055)/1.055)**2.4;
      return value+linear*[.2126,.7152,.0722][i];
    },0);
    const light=luminance(fascia.background),ink=luminance(fascia.ink);
    assert.ok((Math.max(light,ink)+.05)/(Math.min(light,ink)+.05)>=4.5,brand);
  }
  assert.equal(panels.size,5);
  assert.equal(convenienceFascia(store('poi/node/0',4,'全家便利商店')),undefined);
  assert.equal(convenienceFascia(store('poi/node/0',4,'蝦皮店到店')),undefined);
});

test('the illustrated fascias and parcel shelves keep the measured bounds and selection plane',()=>{
  for(const [brand,id] of samples){
    for(const width of [1.5,2.45,4,7.6,9]){
      const result=draw(store(id,width));
      const ordinary=draw(store('poi/node/0',width));
      assert.notDeepEqual(result.vertices,ordinary.vertices,brand);
      assert.deepEqual(result.hit,ordinary.hit,brand);
      assert.ok(result.triangles<=180,brand);
      assert.ok(result.vertices.every(Number.isFinite),brand);
      for(let i=0;i<result.vertices.length;i+=13){
        const [depth,side,height]=result.vertices.slice(i,i+3);
        assert.ok(depth>=0&&depth<.82,brand);
        assert.ok(Math.abs(side)<=width/2+1e-6,brand);
        assert.ok(height>=0&&height<=3.25,brand);
      }
    }
  }
  // The other brands retain the cooler. A parcel shop has lower shelves and
  // taped boxes, which changes geometry even if the colour and name are hidden.
  function windowVertices(row){
    const positions=[];
    const {vertices}=draw(row);
    for(let i=0;i<vertices.length;i+=13){
      if(vertices[i+2]<2.23)positions.push(...vertices.slice(i,i+3));
    }
    return positions;
  }
  assert.notDeepEqual(windowVertices(store(samples.get('shopee'))),windowVertices(store(samples.get('ok'))));
});
