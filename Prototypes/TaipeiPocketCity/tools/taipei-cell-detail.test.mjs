import test from 'node:test';
import assert from 'node:assert/strict';
import {gzipSync} from 'node:zlib';
import {courtMarkings} from '../city170-courts.js';
import {decodeMapJSON} from '../pocket-city-atlas.js';

// Taipei OSM way 387838548, a single basketball court at Yu Da.
const ring=[[121.5539382,25.0502135],[121.5539387,25.0499584],[121.5540815,25.0499586],
  [121.554081,25.0502137],[121.5539382,25.0502135]];
const court=(coordinates,sport='basketball')=>({id:'pitch/way/387838548',
  properties:{kind:'pitch',category:'pitch',sport},geometry:{type:'Polygon',coordinates}});
test('painted sports lines fit a single mapped playing area in either winding',()=>{
  for(const path of [ring,ring.toReversed()]){
    const line=courtMarkings(court([path]));
    assert.equal(line.geometry.coordinates.length,4);
    for(const [x,y] of line.geometry.coordinates.flat()){
      assert.ok(x>=121.5539382-1e-10&&x<=121.5540815+1e-10&&y>=25.0499584-1e-10&&y<=25.0502137+1e-10);
    }
  }
  assert.equal(courtMarkings(court([ring,ring])),undefined);
  assert.equal(courtMarkings(court([ring],'multi')),undefined);
  assert.equal(courtMarkings(court([ring.map(([x,y])=>[x+(x-ring[0][0])*2,y])])),undefined);
});
test('map assets can be served as raw gzip or already decoded by the host',async()=>{
  const layer={features:[{name:'育達高職'}]};
  for(const bytes of [JSON.stringify(layer),gzipSync(JSON.stringify(layer))]){
    assert.deepEqual(await decodeMapJSON(new Response(bytes)),layer);
  }
  await assert.rejects(()=>decodeMapJSON(new Response('not JSON')));
});

test('recorded rooftop court and below-grade stairs stay off the ground plane',async()=>{
  const {surfaceFeature}=await import('../city170-ground.js');
  const rooftop=surfaceFeature({...court([ring]),id:'pitch/way/827534780'});
  assert.equal(rooftop.properties.offGround,true);
  assert.equal(courtMarkings(rooftop),undefined);
  for(const id of [810653304,810653313,1458439462]){
    assert.equal(surfaceFeature({id:'walk/way/'+id,properties:{kind:'walk',category:'steps'}}).properties.offGround,true);
  }
  const level=court([ring]);
  assert.equal(surfaceFeature(level),level);
});
