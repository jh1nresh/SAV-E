// Keep each original painted elevation in its own mipmapped layer. Neighbouring
// atlas slots must never blend into one another when a street recedes or rotates.
export const facadeSize={width:256,height:512,columns:4,rows:3};

export function facadePixels(image){
  const {width:w,height:h,columns,rows}=facadeSize;
  if(image.width!==w*columns||image.height!==h*rows||image.data.length!==w*h*columns*rows*4)
    throw new Error('Unexpected Pocket City facade atlas dimensions');
  const pixels=new Uint8Array(image.data.length);
  for(let layer=0;layer<columns*rows;layer++){
    const x=layer%columns*w,y=Math.floor(layer/columns)*h;
    for(let row=0;row<h;row++){
      const start=((y+row)*image.width+x)*4;
      pixels.set(image.data.subarray(start,start+w*4),(layer*h+row)*w*4);
    }
  }
  return pixels;
}

function withUploadState(gl,texture,upload){
  const binding=gl.getParameter(gl.TEXTURE_BINDING_2D_ARRAY);
  const buffer=gl.getParameter(gl.PIXEL_UNPACK_BUFFER_BINDING);
  const settings=[
    [gl.UNPACK_ALIGNMENT,4],[gl.UNPACK_FLIP_Y_WEBGL,false],
    [gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,false],[gl.UNPACK_ROW_LENGTH,0],
    [gl.UNPACK_IMAGE_HEIGHT,0],[gl.UNPACK_SKIP_PIXELS,0],
    [gl.UNPACK_SKIP_ROWS,0],[gl.UNPACK_SKIP_IMAGES,0],
  ];
  const previous=settings.map(([name])=>gl.getParameter(name));
  try{
    gl.bindTexture(gl.TEXTURE_2D_ARRAY,texture);
    gl.bindBuffer(gl.PIXEL_UNPACK_BUFFER,null);
    for(const [name,value] of settings)gl.pixelStorei(name,value);
    upload();
  }finally{
    settings.forEach(([name],i)=>gl.pixelStorei(name,previous[i]));
    gl.bindBuffer(gl.PIXEL_UNPACK_BUFFER,buffer);
    gl.bindTexture(gl.TEXTURE_2D_ARRAY,binding);
  }
}

export function createFacadeTexture(gl){
  const texture=gl.createTexture();
  try{
    withUploadState(gl,texture,()=>{
      const target=gl.TEXTURE_2D_ARRAY;
      gl.texParameteri(target,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
      gl.texParameteri(target,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(target,gl.TEXTURE_WRAP_S,gl.REPEAT);
      gl.texParameteri(target,gl.TEXTURE_WRAP_T,gl.REPEAT);
      gl.texImage3D(target,0,gl.RGBA8,1,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array(4));
    });
    return texture;
  }catch(error){gl.deleteTexture(texture);throw error;}
}

export function uploadFacadeTexture(gl,texture,image){
  const pixels=facadePixels(image);
  const {width,height,columns,rows}=facadeSize;
  withUploadState(gl,texture,()=>{
    const target=gl.TEXTURE_2D_ARRAY;
    gl.texImage3D(target,0,gl.RGBA8,width,height,columns*rows,0,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
    gl.generateMipmap(target);
    gl.texParameteri(target,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);
  });
}
