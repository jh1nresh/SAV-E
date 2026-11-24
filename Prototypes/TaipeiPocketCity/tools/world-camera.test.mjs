import test from 'node:test';
import assert from 'node:assert/strict';
import {constrainWorldCamera} from '../world-camera.js';

test('a portrait overview shows Taipei and Los Angeles in a single viewport',()=>{
  const width=390,height=800;
  const {center,zoom}=constrainWorldCamera({lng:0,lat:25},-2,width,height);
  const halfDegrees=180*width/(512*2**zoom);
  assert.ok(center.lng-halfDegrees<=-118.3 && center.lng+halfDegrees>=121.6);
  assert.equal(center.lat,0);
});

test('street-scale movement keeps the requested location and zoom',()=>{
  const {center,zoom}=constrainWorldCamera({lng:121.56481,lat:25.03367},17.25,390,800);
  assert.ok(Math.abs(center.lat-25.03367)<1e-8);
  assert.equal(center.lng,121.56481);
  assert.equal(zoom,17.25);
});
