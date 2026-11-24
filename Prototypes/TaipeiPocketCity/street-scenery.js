import {program,transform} from './survey-layer.js';

const vertex=`#version 300 es
layout(location=0) in vec3 point;
layout(location=1) in vec3 color;
uniform mat4 matrix;
out vec3 tint;
void main(){gl_Position=matrix*vec4(point,1.0);tint=color;}
`;
const fragment=`#version 300 es
precision mediump float;
in vec3 tint;
out vec4 outputColor;
void main(){outputColor=vec4(tint,1.0);}
`;
const greens=['#74a26c','#508763','#c0c572','#85b987','#a5b858','#51977f'];
const hybridGreens=['#88bd5f','#479776','#c2cf65','#9bc785','#77a651','#53aa90'];
const hybridAccents=['#e57e62','#409b91','#e7b645'];
const accents=['#d66046','#398d83','#e3ad49'];
const paper='#ead8af', trunk='#8c6952', bronze='#755548';
const anatomyGreens=['#80a45f','#63845e','#a9b873','#91af73','#9bb56e','#639377'];

function buildObject(kind,size,angle,index,origin,vertices,anatomy,hybrid){
  const [x,y,z]=origin;
  const canopy=anatomy?anatomyGreens:hybrid?hybridGreens:greens;
  const a=Math.cos(angle*Math.PI/180), b=Math.sin(angle*Math.PI/180);
  function prism([cx,cy,cz],radii,levels,sides,hex,phase=0){
    const color=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
    const rings=levels.map(([height,scale])=>Array.from({length:sides},(_,i)=>{
      const direction=i*2*Math.PI/sides+phase;
      const u=(cx+radii[0]*Math.cos(direction)*scale)*size;
      const v=(cy+radii[1]*Math.sin(direction)*scale)*size;
      return [x+u*a-v*b,y+u*b+v*a,z+(cz+height)*size];
    }));
    const push=(points,shade)=>{
      for(const point of points)vertices.push(...point,...color.map(c=>Math.min(c*shade,1)));
    };
    for(let j=1;j<rings.length;j++){
      for(let i=0;i<sides;i++){
        const next=(i+1)%sides;
        const low=rings[j-1], high=rings[j];
        const light=Math.cos(i*2*Math.PI/sides+angle*Math.PI/180+.8);
        const shade=anatomy
          ? (light>.55?1.04:light>.06?.96:light>-.48?.88:.80)
          : (light>.30?1.02:light>-.32?.91:.77)+(j-1)*.025;
        push([low[i],low[next],high[i],high[i],low[next],high[next]],shade);
        if(j===rings.length-1&&i>0&&next>0)push([high[0],high[i],high[next]],1.08);
      }
    }
  }
  const box=(x,y,z,w,d,h,color)=>prism([x,y,z],[w/Math.SQRT2,d/Math.SQRT2],[[0,1],[h,1]],4,color,Math.PI/4);
  const accent=anatomy
    ? (kind==='entrance'?'#c67a3d':'#927a62')
    : (hybrid?hybridAccents:accents)[index%3];
  switch(kind){
    case 'tree':{
      prism([0,0,0],[.28,.25],[[0,1],[3.6,.58]],7,trunk);
      const round=[[-1.5,.28],[-.9,.77],[.13,1],[1.22,.66],[1.7,.18]];
      prism([0,0,4.08],[2.45,2.28],round,9,canopy[index]);
      prism([1.01,.54,3.9],[1.53,1.6],round,8,canopy[(index+3)%canopy.length],.18);
      prism([-.76,-.57,4.5],[1.46,1.47],round,8,canopy[(index+2)%canopy.length],.21);
      break;
    }
    case 'bench':
      for(const side of [-1,1])box(side*1.17,0,0,.23,.63,.55,bronze);
      box(0,0,.49,3,.73,.18,accent);
      box(0,.31,.65,3,.14,.63,accent);
      box(2.4,.04,0,1.32,1.27,.55,paper);
      prism([2.4,.04,.66],[.73,.63],[[-.15,.7],[.25,1],[.61,.32]],7,canopy[(index+1)%canopy.length]);
      break;
    case 'entrance':
      for(const side of [-1,1])box(side*2,0,0,.22,.26,3.25,bronze);
      box(0,0,3,4.76,2.7,.31,accent);
      box(0,-1.38,3.04,4.64,.12,.29,paper);
      break;
    case 'metro':
      box(0,0,0,.31,.34,2.9,bronze);
      box(0,0,2.37,.99,.39,.55,'#bd5750');
      box(0,-.23,2.5,.58,.09,.29,paper);
      break;
  }
}

export class StreetScenery {
  type='custom';
  renderingMode='3d';
  vertices=0;
  drawnTriangles=0;
  constructor(id,origin,objects,MercatorCoordinate,anatomy,hybrid){
    this.id=`${id}-scenery`;
    this.anatomy=anatomy;
    this.hybrid=hybrid;
    const base=MercatorCoordinate.fromLngLat(origin);
    const m=base.meterInMercatorCoordinateUnits();
    this.projection={mx:base.x,my:base.y,m};
    this.matrix=new Float32Array(16);
    this.objects=objects.map(([lng,lat,kind,size,angle,index])=>{
      const {x,y}=MercatorCoordinate.fromLngLat([lng,lat]);
      return {point:[lng,lat],x:(x-base.x)/m,y:(base.y-y)/m,kind,size,angle,index};
    });
    const xs=objects.map(row=>row[0]), ys=objects.map(row=>row[1]);
    this.bounds=[Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)];
  }
  onAdd(map,gl){
    this.map=map;
    this.groundNeedsSampling=true;
    this.sampleAfterLoading=event=>{
      if(event.sourceId==='dem')this.groundNeedsSampling=true;
    };
    map.on('sourcedata',this.sampleAfterLoading);
    this.program=program(gl,vertex,fragment);
    this.matrixLocation=gl.getUniformLocation(this.program,'matrix');
    this.buffer=gl.createBuffer();
    this.vao=gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(0,3,gl.FLOAT,false,24,0);
    gl.vertexAttribPointer(1,3,gl.FLOAT,false,24,12);
    gl.bindVertexArray(null);
  }
  onRemove(map,gl){
    map.off('sourcedata',this.sampleAfterLoading);
    gl.deleteVertexArray(this.vao);
    gl.deleteBuffer(this.buffer);
    gl.deleteProgram(this.program);
  }
  render(gl,options){
    const map=this.map;
    this.drawnTriangles=0;
    if(map.getZoom()<17)return;
    const [[west,south],[east,north]]=map.getBounds().toArray();
    const [w,s,e,n]=this.bounds;
    if(e<west||w>east||n<south||s>north)return;
    const sample=this.sampleBounds;
    const moved=!sample||west<sample[0]||south<sample[1]||east>sample[2]||north>sample[3];
    if((this.groundNeedsSampling||moved)&&map.isSourceLoaded('dem')){
      this.groundNeedsSampling=false;
      const padX=(east-west)*.28,padY=(north-south)*.28;
      const a=west-padX,b=south-padY,c=east+padX,d=north+padY;
      this.sampleBounds=[a,b,c,d];
      const vertices=[];
      for(const {point,x,y,kind,size,angle,index} of this.objects){
        if(point[0]<a||point[0]>c||point[1]<b||point[1]>d)continue;
        const z=map.queryTerrainElevation(point);
        if(z!=null)buildObject(kind,size,angle,index,[x,y,z],vertices,this.anatomy,this.hybrid);
      }
      gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(vertices),gl.STATIC_DRAW);
      this.vertices=vertices.length/6;
    }
    if(!this.vertices)return;
    gl.useProgram(this.program);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LEQUAL);
    gl.depthMask(true);
    gl.disable(gl.CULL_FACE);
    gl.disable(gl.BLEND);
    transform(options.defaultProjectionData.mainMatrix,this.projection,this.matrix);
    gl.uniformMatrix4fv(this.matrixLocation,false,this.matrix);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.TRIANGLES,0,this.vertices);
    this.drawnTriangles=this.vertices/3;
    gl.bindVertexArray(null);
  }
}
