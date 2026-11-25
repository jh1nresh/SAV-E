import assert from 'node:assert/strict';
import test from 'node:test';
import {CityNature} from '../city-nature.js';

function scene(id) {
  const models=[], uploads=[], draws=[];
  let zoom=17, elevation=12;
  const gl=new Proxy({
    STATIC_DRAW:1, DYNAMIC_DRAW:2, getShaderParameter:()=>true, getProgramParameter:()=>true,
    bufferData(_target,data,usage){(usage===1?models:uploads).push(data);},
    drawArraysInstanced(_mode,first,count,instances){draws.push({first,count,instances});},
  },{get:(obj,key)=>obj[key]??(()=>{})});
  const bounds={getWest:()=>121.50,getSouth:()=>25.03,getEast:()=>121.52,getNorth:()=>25.05,
    toArray:()=>[[121.50,25.03],[121.52,25.05]]};
  const map={getZoom:()=>zoom,getBounds:()=>bounds,getPitch:()=>45,getBearing:()=>0,
    getCenter:()=>[121.51,25.04],terrain:{getDrawnElevationForLngLat:()=>elevation},
    triggerRepaint(){},on(){},off(){}};
  const art=new CityNature();
  if(id)art.id=id;
  art.onAdd(map,gl);
  return {art,models,uploads,draws,zoom:z=>{zoom=z;},terrain:z=>{elevation=z;},
    render:()=>art.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}})};
}

test('surveyed crown silhouettes retain their root, height scale and distinct widths',()=>{
  const {art,models}=scene();
  const spans=[];
  for(const [i,mesh] of art.meshes.entries()){
    for(const [first,count] of [[0,mesh.street],[mesh.street,mesh.overview]]){
      assert.ok(count>0 && count%3===0);
      const vertices=models[i].subarray(first*8,(first+count)*8);
      let ground=Infinity,top=0,width=0;
      for(let v=0;v<vertices.length;v+=8){
        assert.ok(Number.isFinite(vertices[v+2]));
        ground=Math.min(ground,vertices[v+2]);
        top=Math.max(top,vertices[v+2]+Math.abs(vertices[v+4]));
        width=Math.max(width,Math.abs(vertices[v])+Math.abs(vertices[v+3]));
      }
      assert.equal(ground,0);
      assert.ok(top>.85 && top<1.04);
      if(!first)spans.push(width);
    }
    // About 1,552 triangles per old broadleaf at every zoom.
    assert.ok(mesh.overview/3<=350 && mesh.street/3<850);
  }
  assert.ok(spans[0]>spans[1]*1.15 && spans[1]>spans[2]*1.4);
});

test('moving between neighbourhood and street zoom reuses the same rooted instances',()=>{
  const s=scene();
  const rows=['broad','round','column','palm'].map((form,i)=>[121.5101+i*.0001,25.04,5+i,form,1]);
  s.art.setRows(rows);s.render();
  assert.equal(s.draws.length,4);
  for(const [i,d] of s.draws.entries()){
    const mesh=s.art.meshes[i];
    assert.deepEqual(d,{first:mesh.street,count:mesh.overview,instances:1});
    assert.equal(s.uploads[i][2],12);assert.equal(s.uploads[i][3],5+i);
  }
  const version=s.art.revision;
  s.zoom(19);s.draws.length=0;s.render();
  for(const [i,d] of s.draws.entries())assert.deepEqual(d,{first:0,count:s.art.meshes[i].street,instances:1});
  assert.equal(s.uploads.length,4);
  assert.deepEqual(s.art.activeTrees.rows,rows);
  assert.equal(s.art.revision,version);
});

test('regional mountain trees retain their fir and original mesh levels',()=>{
  const s=scene('taiwan-cell-forest');
  s.terrain(3000);s.art.setRows([[121.51,25.04,6,'round']]);s.render();
  assert.equal(s.art.forms.at(-1),'fir');
  assert.equal(s.art.meshes[0].street/3,1552);
  assert.ok(s.art.meshes.every(m=>m.overview===0));
  assert.deepEqual(s.draws,[{first:0,count:s.art.meshes.at(-1).street,instances:1}]);
});
