import test from 'node:test';
import assert from 'node:assert/strict';
import {officialFloorDirectory as directory} from '../taipei101-directory.js';

test('mall directory keeps multi-floor brands on their official floors without creating coordinates',()=>{
  assert.deepEqual(Object.keys(directory),['B1','1F','2F','3F','4F','5F','6F']);
  for(const rows of Object.values(directory)){
    assert.ok(rows.length);
    assert.equal(new Set(rows.map(r=>r.name)).size,rows.length);
    for(const row of rows){
      assert.deepEqual(Object.keys(row).sort(),['name','url']);
      assert.equal(new URL(row.url).origin,'https://www.taipei-101.com.tw');
    }
  }
  const listedFloors=name=>Object.entries(directory).filter(([,rows])=>rows.some(r=>r.name===name)).map(([f])=>f);
  assert.deepEqual(listedFloors('ZARA'),['1F','2F']);
  assert.deepEqual(listedFloors('凱林鐵板燒'),['B1']);
});
