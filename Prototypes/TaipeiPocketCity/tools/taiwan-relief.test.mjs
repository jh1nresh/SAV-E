import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import coverage from '../taiwan/relief/index.js';
import mountains from '../taiwan/mountains/index.js';
import {installTaiwanRelief,taiwanLocalDEM} from '../taiwan-relief.js';

const directory=new URL('../taiwan/relief/',import.meta.url);
test('land sheets and the DEM fallback match their source manifest',async()=>{
  for(const name of ['taiwan','penghu','matsu','kinmen','wuqiu','liuqiu','ludao','lanyu','dongsha','nansha'])
    assert.ok(coverage.sheets.some(s=>s.name===name&&s.landPixels>0),name);
  for(const sheet of coverage.sheets){
    const bytes=await readFile(new URL(sheet.name+'.webp',directory));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),sheet.sha256,sheet.name);
    assert.equal(bytes.toString('ascii',8,12),'WEBP');
    assert.ok(sheet.height<=4096&&sheet.width<=4096);
  }
  const digest=createHash('sha256');
  for(const name of coverage.dem){
    const url=coverage.terrainSource+'/'+name.replaceAll('-','/')+'.png';
    const local=taiwanLocalDEM(url);
    assert.equal(local,new URL('dem/'+name+'.png',directory).href);
    const data=await readFile(new URL(local));
    assert.equal(data.readUInt32BE(16),256);
    assert.equal(data.readUInt32BE(20),256);
    digest.update(data);
  }
  assert.equal(digest.digest('hex'),coverage.demSha256);
  assert.equal(taiwanLocalDEM(coverage.terrainSource+'/9/0/0.png'),undefined);
  assert.equal(taiwanLocalDEM('https://example.com/9/428/220.png'),undefined);
});

test('textures are attached when in view and leave water and streets above them',()=>{
  let zoom=2,extent=[-180,-60,180,74],moveend;
  const layers=new Set(),sources=new Set();
  const map={getZoom:()=>zoom,getBounds:()=>({getWest:()=>extent[0],getSouth:()=>extent[1],getEast:()=>extent[2],getNorth:()=>extent[3]}),
    addSource(id,source){assert.equal(source.coordinates.length,4);sources.add(id);},
    removeSource(id){assert.ok(!layers.has(id));sources.delete(id);},
    addLayer(layer,before){assert.ok(before==='water'||layers.has(before));assert.ok(sources.has(layer.source));layers.add(layer.id);},
    removeLayer:id=>layers.delete(id),on:(event,func)=>{assert.equal(event,'moveend');moveend=func;}};
  assert.equal(installTaiwanRelief(map,'water'),coverage.sheets.length+mountains.sheets.length);
  assert.equal(sources.size,0);
  zoom=9;extent=[120.8,23.4,121.1,23.8];moveend();
  assert.deepEqual([...layers],['taiwan-relief-taiwan','taiwan-relief-taiwan-highlands']);
  zoom=13;extent=[120.95,23.46,120.97,23.48];moveend();
  assert.ok(layers.has('taiwan-relief-yushan-ridges'));
  zoom=9;
  extent=[118.33,24.38,118.39,24.46];moveend();
  assert.deepEqual([...layers],['taiwan-relief-kinmen']);
  extent=[170,-30,-170,40];moveend();
  assert.equal(sources.size,0);
  zoom=17;extent=[121.56,25.0,121.58,25.1];moveend();
  assert.equal(layers.size,0);
});
