import test from 'node:test';
import assert from 'node:assert/strict';
import {stationLabelX} from '../metro-preview.js';

test('edge stations keep an on-map anchor and a readable label on portrait 101 views',()=>{
  const halfLabel=65.5;
  for(const [width,x] of [[320,21],[390,17],[390,32],[430,19]]){
    for(const anchor of [x,width-x]){
      const label=stationLabelX(anchor,halfLabel,width);
      assert.ok(label-halfLabel>=5&&label+halfLabel<=width-5);
      assert.ok(Math.abs(label-anchor)<=halfLabel);
    }
  }
  assert.equal(stationLabelX(210,halfLabel,430),210);
  assert.equal(stationLabelX(-1,halfLabel,430),null);
});
