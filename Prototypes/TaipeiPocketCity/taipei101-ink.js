// Source outlines are CSS pixels. A negative width is a line measured in the
// original oblique projection; divide by sqrt(1.5) to recover world metres.
const vertex=`#version 300 es
layout(location=0) in vec3 a_start;
layout(location=1) in vec3 a_end;
layout(location=2) in vec2 a_style;
uniform mat4 u_transform;
uniform vec2 u_screen;
uniform float u_pixel;
uniform ivec2 u_skip;
out vec2 v_coverage;
flat out vec3 v_rgb;
void main(){
  gl_Position=vec4(2.,2.,2.,1.);
  v_coverage=vec2(0.); v_rgb=vec3(0.);
  if(gl_InstanceID>=u_skip.x&&gl_InstanceID<u_skip.y)return;
  vec4 a=u_transform*vec4(a_start,1.), b=u_transform*vec4(a_end,1.);
  // Clip the original centreline before dividing by w, including segments
  // crossing the camera near plane. Fully clipped segments make an empty strip.
  float da=a.w+a.z, db=b.w+b.z;
  if(da<0.&&db<0.)return;
  if(da<0.)a=mix(a,b,da/(da-db));
  else if(db<0.)b=mix(b,a,db/(db-da));
  if(a.w<=0.||b.w<=0.)return;
  vec2 delta=(b.xy/b.w-a.xy/a.w)*u_screen*.5;
  float len=length(delta);
  if(len<.001)return;
  vec2 normal=vec2(-delta.y,delta.x)/len;
  vec4 p=gl_VertexID<2?a:b;
  vec3 wAxis=vec3(u_transform[0].w,u_transform[1].w,u_transform[2].w);
  vec3 xAxis=vec3(u_transform[0].x,u_transform[1].x,u_transform[2].x);
  float pixelsPerMetre=length(xAxis-wAxis*(p.x/p.w))*u_screen.x*.5/p.w;
  float width=a_style.y>0.?a_style.y:-a_style.y*.816496580927726*pixelsPerMetre;
  float halfWidth=.5*width;
  float side=(gl_VertexID%2==0?-1.:1.)*(halfWidth+.5*u_pixel);
  p.xy+=normal*side*2./u_screen*p.w;
  // Bias coplanar trim by at most 3 cm in eye depth, capped in clip space.
  vec3 zAxis=vec3(u_transform[0].z,u_transform[1].z,u_transform[2].z);
  p.z-=min(2.e-6*p.w,.03*length(zAxis-wAxis*(p.z/p.w)));
  gl_Position=p;
  // Reconstruct affine screen interpolation in the fragment shader.
  v_coverage=vec2(side,halfWidth)*p.w;
  uint rgb=uint(a_style.x);
  v_rgb=vec3((rgb>>16u)&255u,(rgb>>8u)&255u,rgb&255u)/255.;
}`;
const fragment=`#version 300 es
precision highp float;
uniform float u_pixel;
in vec2 v_coverage;
flat in vec3 v_rgb;
out vec4 outColor;
void main(){
  vec2 d=v_coverage*gl_FragCoord.w;
  float alpha=min(clamp(2.*d.y/u_pixel,0.,1.),clamp((d.y-abs(d.x))/u_pixel+.5,0.,1.));
  if(alpha<=0.)discard;
  outColor=vec4(v_rgb*alpha,alpha);
}`;

// Clip the complete 101 plot, including its 508 m spire. Ground-only map bounds
// would incorrectly hide the tower when it rises into a pitched view.
export function inkInView(matrix){
  for(let axis=0;axis<3;axis++){
    for(const sign of [-1,1]){
      const x=matrix[3]+sign*matrix[axis],y=matrix[7]+sign*matrix[4+axis],z=matrix[11]+sign*matrix[8+axis];
      const distance=matrix[15]+sign*matrix[12+axis]+5*x+32*y+259*z;
      if(distance+103*Math.abs(x)+78*Math.abs(y)+256*Math.abs(z)<=0)return false;
    }
  }
  return true;
}

export class Taipei101Ink {
  constructor(gl,asset,compile,unpack,repaint){
    Object.assign(this,{gl,asset,compile,unpack,repaint});
  }
  prepare(matrix){
    if(!inkInView(matrix)){
      this.failed=false;
      return false;
    }
    if(this.vao)return true;
    if(this.failed||this.disposed)return false;
    if(this.data){
      try{this.upload();}catch(error){this.fail(error);}
      return !!this.vao;
    }
    if(!this.request){
      const controller=new AbortController();
      this.request=controller;
      this.unpack(this.asset.mesh,controller.signal).then(data=>{
        if(controller.signal.aborted)return;
        if(data.byteLength!==this.asset.segments*32)throw Error('Invalid 101 ink segment count');
        const rows=new Float32Array(data);
        for(let i=0;i<rows.length;i+=8){
          const rgb=rows[i+6],width=rows[i+7];
          if(!Number.isFinite(rows[i]+rows[i+1]+rows[i+2]+rows[i+3]+rows[i+4]+rows[i+5])||
             !Number.isInteger(rgb)||rgb<0||rgb>0xffffff||!Number.isFinite(width)||width===0)
            throw Error('Invalid 101 ink segment');
        }
        this.data=data;
      }).catch(error=>{if(!controller.signal.aborted)this.fail(error);}).finally(()=>{
        this.request=null;
        if(!this.disposed)this.repaint();
      });
    }
    return false;
  }
  fail(error){
    this.failed=true;
    this.data=null;
    this.releaseGPU();
    console.warn('Taipei 101 ink:',error.message);
  }
  upload(){
    const gl=this.gl;
    this.program=this.compile(gl,vertex,fragment);
    this.locations=Object.fromEntries(['transform','screen','pixel','skip'].map(name=>[name,gl.getUniformLocation(this.program,'u_'+name)]));
    this.buffer=gl.createBuffer();
    this.vao=gl.createVertexArray();
    if(!this.buffer||!this.vao)throw Error('WebGL resource allocation failed');
    const oldVao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),oldBuffer=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    try{
      gl.bindVertexArray(this.vao);
      gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER,this.data,gl.STATIC_DRAW);
      if(gl.getBufferParameter(gl.ARRAY_BUFFER,gl.BUFFER_SIZE)!==this.data.byteLength)
        throw Error('WebGL could not upload all 101 ink segments');
      for(const [slot,count,offset] of [[0,3,0],[1,3,12],[2,2,24]]){
        gl.enableVertexAttribArray(slot);
        gl.vertexAttribPointer(slot,count,gl.FLOAT,false,32,offset);
        gl.vertexAttribDivisor(slot,1);
      }
      this.data=null;
    }finally{
      gl.bindVertexArray(oldVao);
      gl.bindBuffer(gl.ARRAY_BUFFER,oldBuffer);
    }
  }
  // Called after all opaque survey geometry. SurveyLayer owns the active depth
  // test (LEQUAL), disabled culling/blending and enabled depth writes at entry.
  draw(matrix,cutaway,surveyProgram){
    const gl=this.gl,u=this.locations;
    const w=gl.canvas.clientWidth||gl.drawingBufferWidth,h=gl.canvas.clientHeight||gl.drawingBufferHeight;
    if(!w||!h)return;
    const srcRGB=gl.getParameter(gl.BLEND_SRC_RGB),dstRGB=gl.getParameter(gl.BLEND_DST_RGB);
    const srcAlpha=gl.getParameter(gl.BLEND_SRC_ALPHA),dstAlpha=gl.getParameter(gl.BLEND_DST_ALPHA);
    const eqRGB=gl.getParameter(gl.BLEND_EQUATION_RGB),eqAlpha=gl.getParameter(gl.BLEND_EQUATION_ALPHA);
    try{
      gl.useProgram(this.program);gl.bindVertexArray(this.vao);
      gl.uniformMatrix4fv(u.transform,false,matrix);
      gl.uniform2f(u.screen,w,h);gl.uniform1f(u.pixel,w/gl.drawingBufferWidth);
      gl.uniform2i(u.skip,this.asset.mallFirst,cutaway?this.asset.mallFirst+this.asset.mallCount:this.asset.mallFirst);
      gl.depthMask(false);gl.enable(gl.BLEND);
      gl.blendEquation(gl.FUNC_ADD);gl.blendFunc(gl.ONE,gl.ONE_MINUS_SRC_ALPHA);
      gl.drawArraysInstanced(gl.TRIANGLE_STRIP,0,4,this.asset.segments);
    }finally{
      gl.blendEquationSeparate(eqRGB,eqAlpha);gl.blendFuncSeparate(srcRGB,dstRGB,srcAlpha,dstAlpha);
      gl.disable(gl.BLEND);gl.depthMask(true);gl.bindVertexArray(null);gl.useProgram(surveyProgram);
    }
  }
  releaseGPU(){
    const gl=this.gl;
    if(this.vao)gl.deleteVertexArray(this.vao);
    if(this.buffer)gl.deleteBuffer(this.buffer);
    if(this.program)gl.deleteProgram(this.program);
    this.vao=this.buffer=this.program=null;
  }
  dispose(){
    this.disposed=true;
    this.request?.abort();
    this.data=null;
    this.releaseGPU();
  }
}
