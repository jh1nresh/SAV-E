import test from 'node:test';
import assert from 'node:assert/strict';
import {access} from 'node:fs/promises';
import {originalPlacePhoto, photoPlaces} from '../place-photos.js';

import {appleDirections} from '../place-callout.js';

test('directions use the selected door and reverse GeoJSON axes for Apple Maps',()=>{
  assert.equal(appleDirections([121.5065422,25.0434442]),'https://maps.apple.com/?daddr=25.0434442,121.5065422');
  assert.notEqual(appleDirections([121.5068365,25.0436012]),appleDirections([121.5065422,25.0434442]));
  for(const invalid of [undefined,null,[],[121],[NaN,25],[121,Infinity],[25,121],[181,25]]){
    assert.equal(appleDirections(invalid),null);
  }
});

test('each credited example resolves to its own bundled photo',async()=>{
  for(const place of photoPlaces){
    const photo=originalPlacePhoto(place);
    await access(new URL(photo.src));
    assert.ok(photo.credit);
    assert.ok(photo.url.startsWith('https://commons.wikimedia.org/'));
  }
});

test('a nearby same-name place needs the verified branch ID to show its photo',()=>{
  const {name, point}=photoPlaces[0];
  assert.equal(originalPlacePhoto({name,point,placeId:'poi/node/different'}),null);
  assert.equal(originalPlacePhoto({name,point,id:'poi/node/different'}),null);
  assert.equal(originalPlacePhoto({name,point}),null);
  assert.equal(originalPlacePhoto({name:'無照片的地點',point}),null);
});

test('both Meiguanyuan storefronts have their own photo and door number',()=>{
  const west=photoPlaces.find(place=>place.placeId==='poi/node/3007181095');
  const east=photoPlaces.find(place=>place.placeId==='poi/node/3007181096');
  assert.match(west.detail,/峨眉街 36 號/);
  assert.match(east.detail,/峨眉街 47 號/);
  assert.notEqual(originalPlacePhoto(west).src,originalPlacePhoto(east).src);
  assert.match(originalPlacePhoto(west).url,/Meiguanyuan-no.36/);
  assert.match(originalPlacePhoto(east).url,/Meiguanyuan-no.47/);
  assert.equal(originalPlacePhoto({name:'美觀園',point:west.point}),null);
});

test('Din Tai Fung Xinyi has a licensed storefront and A13 keeps its own source-only card',()=>{
  const main=photoPlaces.find(place=>place.placeId==='poi/node/2426176904');
  assert.match(originalPlacePhoto(main).url,/Din_Tai_Fung_Xinyi_Branch/);
  assert.equal(originalPlacePhoto({placeId:'savvy/apple_maps/H2710I3F98C599035A5',name:'鼎泰豐 A13店'}),null);
});
