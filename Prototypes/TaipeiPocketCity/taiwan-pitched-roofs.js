import {LngLat,MercatorCoordinate} from './assets/maplibre-gl.mjs';
import {program,transform} from './survey-layer.js';

const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
const vertex=`#version 300 es
layout(location=0) in vec3 p;
layout(location=1) in vec3 ink;
uniform mat4 matrix;
out vec3 color;
void main(){ gl_Position=matrix*vec4(p,1.); color=ink; }`;
const fragment=`#version 300 es
precision mediump float;
in vec3 color;
out vec4 pixel;
void main(){ pixel=vec4(color,1.); }`;

export class PitchedRoofs{
  id='taiwan-pitched-roofs';type='custom';renderingMode='3d';rows=[];
  onAdd(map,gl){
    this.map=map;this.shader=program(gl,vertex,fragment);this.matrix=new Float32Array(16);
    this.uniform=gl.getUniformLocation(this.shader,'matrix');this.buffer=gl.createBuffer();this.vao=gl.createVertexArray();
    gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    for(let i=0;i<2;i++){gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,3,gl.FLOAT,false,24,i*12);}
    gl.bindVertexArray(null);
    this.terrainChanged=e=>{if(e.sourceId==='dem'&&e.sourceDataType==='content')this.dirty=true;};
    map.on('sourcedata',this.terrainChanged);
  }
  setRows(rows){this.rows=rows;this.dirty=true;}
  upload(gl){
    const data=[],origin=MercatorCoordinate.fromLngLat(this.map.getCenter()),m=origin.meterInMercatorCoordinateUnits();
    this.anchor={mx:origin.x,my:origin.y,m};
    for(const {center,faces} of this.rows){
      const ground=this.map.terrain?.getDrawnElevationForLngLat(new LngLat(...center))??0;
      for(const {p,color} of faces){
        const points=p.map(([lon,lat,z])=>{
          const q=MercatorCoordinate.fromLngLat([lon,lat]);return [(q.x-origin.x)/m,(origin.y-q.y)/m,ground+z+.025];
        });
        const a=points[0],b=points[1],c=points[2];
        const dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],ex=c[0]-a[0],ey=c[1]-a[1],ez=c[2]-a[2];
        const nx=dy*ez-dz*ey,ny=dz*ex-dx*ez,nz=dx*ey-dy*ex;
        const sun=(-.5*nx+.48*ny+.7*nz)*(nz<0?-1:1)/(Math.hypot(nx,ny,nz)||1);
        const ink=rgb(color).map((v,i)=>sun>.55?v*.88+[1,.95,.84][i]*.12:v*.78+[.28,.35,.48][i]*.22);
        for(let i=1;i<points.length-1;i++)for(const v of [a,points[i],points[i+1]])data.push(...v,...ink);
      }
    }
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(data),gl.DYNAMIC_DRAW);
    this.count=data.length/6;this.dirty=false;
  }
  render(gl,options){
    if(!this.rows.length||this.map.getZoom()<17)return;
    if(this.dirty)this.upload(gl);
    transform(options.defaultProjectionData.mainMatrix,this.anchor,this.matrix);
    gl.useProgram(this.shader);gl.uniformMatrix4fv(this.uniform,false,this.matrix);gl.bindVertexArray(this.vao);
    gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);gl.disable(gl.BLEND);gl.disable(gl.CULL_FACE);
    gl.drawArrays(gl.TRIANGLES,0,this.count);gl.bindVertexArray(null);
  }
  onRemove(map,gl){map.off('sourcedata',this.terrainChanged);gl.deleteBuffer(this.buffer);gl.deleteVertexArray(this.vao);gl.deleteProgram(this.shader);}
}
