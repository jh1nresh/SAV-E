import test from 'node:test';
import assert from 'node:assert/strict';
import {facadePixels,createFacadeTexture,uploadFacadeTexture} from '../pocket-facade-texture.js';

function atlas(){
  const image={width:1024,height:1536,data:new Uint8ClampedArray(1024*1536*4)};
  for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++){
    const i=(y*image.width+x)*4;
    image.data.set([Math.floor(y/512)*4+Math.floor(x/256),x%256,y%256,y<512?0:255],i);
  }
  return image;
}

test('all twelve painted elevations retain row orientation, edge pixels and alpha',()=>{
  const image=atlas(),pixels=facadePixels(image);
  for(let layer=0;layer<12;layer++)for(const [x,y] of [[0,0],[255,0],[0,511],[255,511],[73,214]]){
    const src=(((Math.floor(layer/4)*512+y)*1024)+(layer%4)*256+x)*4;
    const dest=((layer*512+y)*256+x)*4;
    assert.deepEqual([...pixels.slice(dest,dest+4)],[...image.data.slice(src,src+4)]);
  }
  assert.equal(pixels.length,image.data.length);
});

function mockGL(){
  const keys=['TEXTURE_BINDING_2D_ARRAY','PIXEL_UNPACK_BUFFER_BINDING','UNPACK_ALIGNMENT','UNPACK_FLIP_Y_WEBGL','UNPACK_PREMULTIPLY_ALPHA_WEBGL','UNPACK_ROW_LENGTH','UNPACK_IMAGE_HEIGHT','UNPACK_SKIP_PIXELS','UNPACK_SKIP_ROWS','UNPACK_SKIP_IMAGES','TEXTURE_2D_ARRAY','PIXEL_UNPACK_BUFFER','TEXTURE_MIN_FILTER','TEXTURE_MAG_FILTER','LINEAR','LINEAR_MIPMAP_LINEAR','TEXTURE_WRAP_S','TEXTURE_WRAP_T','REPEAT','RGBA8','RGBA','UNSIGNED_BYTE'];
  const gl=Object.fromEntries(keys.map(k=>[k,k]));
  const state=new Map(keys.slice(0,10).map((k,i)=>[k,i+10]));
  const initial=new Map(state),textures=new Map();
  Object.assign(gl,{
    getParameter:k=>state.get(k),createTexture:()=>({}),deleteTexture:t=>textures.delete(t),
    bindTexture:(_,t)=>state.set(gl.TEXTURE_BINDING_2D_ARRAY,t),
    bindBuffer:(_,b)=>state.set(gl.PIXEL_UNPACK_BUFFER_BINDING,b),pixelStorei:(k,v)=>state.set(k,v),
    texParameteri:(_,k,v)=>{
      const t=state.get(gl.TEXTURE_BINDING_2D_ARRAY);
      if(!textures.has(t))textures.set(t,{});
      textures.get(t)[k]=v;
    },
    texImage3D:(...args)=>{
      assert.equal(state.get(gl.PIXEL_UNPACK_BUFFER_BINDING),null);
      for(const k of keys.slice(5,10))assert.equal(state.get(k),0);
      assert.equal(state.get(gl.UNPACK_FLIP_Y_WEBGL),false);
      assert.equal(state.get(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL),false);
      if(gl.fail)throw new Error('upload failed');
      gl.upload=args;
    },generateMipmap:target=>{gl.mipTarget=target;},
  });
  return {gl,state,initial,textures};
}

test('upload builds isolated mipmapped elevations and restores borrowed map GL state',()=>{
  const {gl,state,initial,textures}=mockGL(),texture=createFacadeTexture(gl);
  assert.deepEqual(state,initial);
  assert.deepEqual(gl.upload.slice(3,6),[1,1,1]);
  uploadFacadeTexture(gl,texture,atlas());
  assert.deepEqual(gl.upload.slice(3,6),[256,512,12]);
  assert.equal(gl.mipTarget,gl.TEXTURE_2D_ARRAY);
  assert.equal(textures.get(texture)[gl.TEXTURE_MIN_FILTER],gl.LINEAR_MIPMAP_LINEAR);
  assert.equal(textures.get(texture)[gl.TEXTURE_WRAP_S],gl.REPEAT);
  assert.equal(textures.get(texture)[gl.TEXTURE_WRAP_T],gl.REPEAT);
  assert.deepEqual(state,initial);
});

test('invalid atlas and failed upload do not leak map upload state',()=>{
  const {gl,state,initial}=mockGL(),texture=createFacadeTexture(gl);
  assert.throws(()=>uploadFacadeTexture(gl,texture,{width:1,height:1,data:new Uint8Array(4)}),/dimensions/);
  assert.deepEqual(state,initial);
  gl.fail=true;
  assert.throws(()=>uploadFacadeTexture(gl,texture,atlas()),/upload failed/);
  assert.deepEqual(state,initial);
});
