import assert from 'node:assert/strict';
import test from 'node:test';
import catalog from '../taipei-open-shop-catalog-data.js';
import {addedOpenShops,canonicalShopId,doorplatePoint,isDuplicateShop,withOpenShopAddress}
  from '../taipei-open-shop-catalog.js';
import {appleDirections} from '../place-callout.js';

test('an exact inspection shop is plotted at its official doorplate',()=>{
  const bakery=addedOpenShops.find(f=>f.properties.name==='聖瑪莉北醫店');
  assert.ok(bakery);
  assert.equal(bakery.properties.address,'臺北市信義區吳興街252號1樓');
  assert.deepEqual(doorplatePoint(bakery.properties),bakery.geometry.coordinates);
  assert.equal(appleDirections(doorplatePoint(bakery.properties)),
    'https://maps.apple.com/?daddr=25.026638,121.5636377');
});

test('an old duplicate id resolves the canonical address without rewriting saved identity',()=>{
  const previous='poi/node/13784533059';
  const canonical='poi/node/13724520041';
  assert.ok(isDuplicateShop(previous));
  assert.equal(canonicalShopId(previous),canonical);
  const oldSavedPlace={placeId:previous,name:'Q Burger 信義永吉店'};
  const updated=withOpenShopAddress(oldSavedPlace);
  assert.equal(updated.placeId,previous);
  assert.equal(updated.address,catalog.entries[canonical].address);
  assert.equal(canonicalShopId(canonical),canonical);
});

test('unknown shops keep their given address and coordinates',()=>{
  const place={placeId:'savvy/example',address:'地址',point:[121.55,25.03]};
  assert.equal(withOpenShopAddress(place),place);
  assert.equal(doorplatePoint(place),null);
  assert.equal(appleDirections(doorplatePoint(place))??appleDirections(place.point),
    'https://maps.apple.com/?daddr=25.03,121.55');
});
