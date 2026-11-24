// Additive, depth-tested glows at the original lantern fixtures. The opaque mesh
// supplies the ribbed paper body; other shop walls and roofs can hide the glow.
import {program} from './survey-layer.js';
const vert=`#version 300 es
layout(location=0) in vec4 lamp;
uniform mat4 matrix;
uniform vec2 viewport;
uniform float ground;
void main(){
  vec4 p=matrix*vec4(lamp.xy,lamp.z+ground,1.);
  vec4 dx=p+matrix[0]*lamp.w,dy=p+matrix[1]*lamp.w;
  float radius=max(length((dx.xy/dx.w-p.xy/p.w)*viewport*.5),
                   length((dy.xy/dy.w-p.xy/p.w)*viewport*.5));
  gl_Position=p;
  gl_PointSize=clamp(radius*6.,1.,116.);
}`;
const frag=`#version 300 es
precision mediump float;
out vec4 colour;
void main(){
  vec2 xy=2.*gl_PointCoord-1.;
  float r=dot(xy,xy);
  if(r>=1.)discard;
  colour=vec4(1.,.28,.045,.42*exp(-4.5*r)*(1.-r));
}`;
export class LanternLight{
  constructor(gl,rows){
    this.gl=gl;this.count=rows.length;
    this.shader=program(gl,vert,frag);
    this.matrix=gl.getUniformLocation(this.shader,'matrix');
    this.ground=gl.getUniformLocation(this.shader,'ground');
    this.viewport=gl.getUniformLocation(this.shader,'viewport');
    this.vao=gl.createVertexArray();this.buffer=gl.createBuffer();
    gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(rows.flat()),gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,4,gl.FLOAT,false,0,0);gl.bindVertexArray(null);
  }
  draw(matrix,ground){
    const gl=this.gl;
    gl.useProgram(this.shader);gl.bindVertexArray(this.vao);
    gl.uniformMatrix4fv(this.matrix,false,matrix);gl.uniform1f(this.ground,ground);
    gl.uniform2f(this.viewport,gl.drawingBufferWidth,gl.drawingBufferHeight);
    gl.depthMask(false);gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE);
    gl.drawArrays(gl.POINTS,0,this.count);
    gl.depthMask(true);gl.disable(gl.BLEND);gl.bindVertexArray(null);
  }
  dispose(){
    this.gl.deleteBuffer(this.buffer);this.gl.deleteVertexArray(this.vao);this.gl.deleteProgram(this.shader);
  }
}
