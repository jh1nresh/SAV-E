import test from 'node:test';
import assert from 'node:assert/strict';
import {additionalShopFloor,shopFloorLabel} from '../shop-floor-labels.js';
import groups from '../taipei-shop-floors.js';

test('posted floors follow exact public shop identities without leaking into account data',()=>{
  assert.equal(shopFloorLabel('poi/node/2444841748'),'B1');
  assert.equal(shopFloorLabel('poi/way/2444841748'),undefined);
  assert.equal(shopFloorLabel('poi/node/2444841748','Savvy'),undefined);
  assert.equal(shopFloorLabel('poi/node/7749782404'),undefined);
  const ids=groups.flatMap(([,type,ids])=>ids.split(' ').map(id=>type+'/'+id));
  assert.equal(new Set(ids).size,ids.length);
});

test('already visible floor captions are left singular, with complete floor-number matching',()=>{
  const id='poi/node/2444841748';
  assert.equal(additionalShopFloor(id,'OpenStreetMap','書店','地下街'), 'B1');
  assert.equal(additionalShopFloor(id,'OpenStreetMap','地下街Ｂ１'),undefined);
  assert.equal(additionalShopFloor(id,'OpenStreetMap','地下1樓'),undefined);
  assert.equal(additionalShopFloor(id,'OpenStreetMap','台北101購物中心 · B1'),undefined);
  assert.equal(additionalShopFloor(id,'OpenStreetMap','B10'),'B1');
});

test('precise indoor and address floors supersede a relative OSM label',()=>{
  for(const id of ['poi/node/5492157852','poi/node/7004289008']){
    assert.equal(shopFloorLabel(id),'地下樓層');
    assert.equal(additionalShopFloor(id,'OpenStreetMap','台北101購物中心 · B1'),undefined);
    assert.equal(additionalShopFloor(id,'OpenStreetMap','B1F'),undefined);
  }
  assert.equal(shopFloorLabel('poi/node/8420325607'),'樓上');
  assert.equal(additionalShopFloor('poi/node/8420325607','OpenStreetMap','民權東路六段 312號2樓'),undefined);
  assert.equal(additionalShopFloor('poi/node/8420325607','OpenStreetMap','民權東路六段 312號1樓'),'樓上');
});
