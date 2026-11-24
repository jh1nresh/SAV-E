import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {makeTaiwanCoverage} from '../taiwan-coverage.js';

function load(path){
  const bytes=readFileSync(new URL('../taiwan/'+path,import.meta.url));
  return JSON.parse(path.endsWith('.gz')?gunzipSync(bytes):bytes);
}
test('all official township anchors land in their own geometry and a 170 metre cell',()=>{
  const grid=load('cells.json'),towns=load('town-index.json');
  const coverage=makeTaiwanCoverage(load('townships.geojson.gz'),grid);
  let count=0,lastY=-Infinity;
  for(const [y,...runs] of grid.rows){
    assert.ok(y>lastY);lastY=y;
    let previous=-Infinity;
    assert.equal(runs.length%2,0);
    for(let i=0;i<runs.length;i+=2){
      const [left,right]=runs.slice(i,i+2);
      assert.ok(left>previous+1&&left<=right);count+=right-left+1;previous=right;
    }
  }
  assert.equal(count,1283052);assert.equal(grid.count,count);
  assert.equal(towns.length,368);assert.equal(new Set(towns.map(t=>t.county)).size,22);
  for(const {code,anchor:[x,y]} of towns){
    assert.equal(coverage.at(x,y)?.code,code);
    assert.equal(coverage.cellsIn({getWest:()=>x,getSouth:()=>y,getEast:()=>x,getNorth:()=>y}).length,1);
  }
  assert.equal(coverage.at(122.12,23.65),undefined);
});
test('every national search reference resolves to the matching public place and township',()=>{
  const manifest=load('places/index.json'),names=load('places/names.json.gz');
  const tiles=new Map(manifest.tiles.map(k=>[k,load('places/'+k+'.json.gz')]));
  assert.equal(names.length,manifest.count);
  const counts={},seen=new Set();
  for(const [name,town,key,pos] of names){
    const r=tiles.get(key)?.[pos];
    assert.equal(r?.[0],name);assert.equal(r[5],town);
    assert.match(r[2],/^[nwr]\d+$/);assert.ok(!seen.has(r[2]));seen.add(r[2]);
    counts[town]=(counts[town]??0)+1;
  }
  assert.equal(Object.keys(counts).length,368);assert.deepEqual(counts,manifest.townships);
  assert.equal([...tiles.values()].reduce((total,rows)=>total+rows.length,0),names.length);
});
