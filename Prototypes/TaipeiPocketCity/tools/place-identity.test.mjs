import test from 'node:test';
import assert from 'node:assert/strict';
import {access} from 'node:fs/promises';
import {originalPlacePhoto, photoPlaces} from '../place-photos.js';

test('each credited example resolves to its own bundled photo',async()=>{
  for(const place of photoPlaces){
    const photo=originalPlacePhoto(place);
    await access(new URL(photo.src));
    assert.ok(photo.credit);
    assert.ok(photo.url.startsWith('https://commons.wikimedia.org/'));
  }
});

test('a different mapped branch at the same address stays text-only',()=>{
  const {name, point}=photoPlaces[0];
  assert.equal(originalPlacePhoto({name,point,placeId:'poi/node/different'}),null);
  assert.equal(originalPlacePhoto({name,point,id:'poi/node/different'}),null);
  assert.ok(originalPlacePhoto({name,point}));
  assert.equal(originalPlacePhoto({name:'無照片的地點',point}),null);
});
