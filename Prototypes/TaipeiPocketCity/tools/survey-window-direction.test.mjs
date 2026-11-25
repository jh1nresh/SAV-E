import assert from 'node:assert/strict';
import test from 'node:test';
import {surveyWallDirections} from '../survey-layer.js';

function surveyedTriangles(points) {
  return Float32Array.from(points.flatMap(point=>[...point,4.59,14.18,.51]));
}

test('康定路太和傳統餅的兩個測繪三角面共用同一個窗框方向',()=>{
  // Survey tile 1502_13849, the 5.55 m street face of the building at this POI.
  const a=[89.3876,-9.8576,4.5901], b=[90.1675,-4.3631,4.5901];
  const c=[b[0],b[1],18.7704], d=[a[0],a[1],18.7704];
  const dx=b[0]-a[0], dy=b[1]-a[1], width=Math.hypot(dx,dy);
  const expected=[Math.round(32767*dx/width),Math.round(32767*dy/width)];
  for(const split of [[a,b,c,a,c,d],[a,b,d,b,c,d],[c,b,a,d,c,a]]){
    const vertices=surveyedTriangles(split);
    const directions=surveyWallDirections(vertices);
    assert.ok(directions instanceof Int16Array);
    assert.equal(directions.byteLength,4*split.length);
    for(let i=0;i<split.length;i++){
      assert.deepEqual(Array.from(directions.subarray(i*2,i*2+2)),expected);
    }
    const projectedWidth=(dx*directions[0]+dy*directions[1])/32767;
    assert.ok(Math.abs(projectedWidth-width)<.0002);
  }
});

test('axis-aligned walls retain a stable tangent and a roof or degenerate face has none',()=>{
  const origin=[0,0,0], corner=[0,0,4];
  const triangles=surveyedTriangles([
    origin,corner,[-4,0,0], origin,corner,[0,-4,0],
    origin,[0,3,0],[4,0,0], origin,origin,origin,
  ]);
  const directions=surveyWallDirections(triangles);
  for(const [index,pair] of [[0,[32767,0]],[1,[0,32767]],[2,[0,0]],[3,[0,0]]]){
    for(let i=0;i<3;i++){
      const start=index*6+i*2;
      assert.deepEqual(Array.from(directions.subarray(start,start+2)),pair);
    }
  }
});
