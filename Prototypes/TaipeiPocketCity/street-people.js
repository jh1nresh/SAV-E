import {inside101Ground,touches101Ground} from './taipei101-single-ground.js';
import {program,transform} from './survey-layer.js';

const vertex=`#version 300 es
layout(location=0) in vec3 point;
layout(location=1) in vec3 color;
uniform mat4 matrix;
out vec3 tint;
void main(){ gl_Position=matrix*vec4(point,1.0); tint=color; }
`;
const fragment=`#version 300 es
precision mediump float;
in vec3 tint;
out vec4 outColor;
void main(){ outColor=vec4(tint,1.0); }
`;
const paintWardrobe=outfits=>outfits.map(outfit=>outfit.map(hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255)));
const wardrobe=paintWardrobe([
  ['#ce5846','#37495d','#e4ad80','#e8ba59'],
  ['#4066a1','#5d4a42','#ad7654','#dfb478'],
  ['#e4ae3b','#3e5556','#d79970','#7d4b63'],
  ['#568778','#485768','#e5b998','#c6674f'],
  ['#be6585','#4d4058','#88543b','#478575'],
  ['#49a5ab','#484456','#f0c29b','#a9513f'],
  ['#e79356','#344b62','#bc805a','#edd591'],
]);
const hybridWardrobe=paintWardrobe([
  ['#e67254','#354b68','#e4ad80','#edc060'],
  ['#4f80ba','#61535b','#ad7654','#e7b06d'],
  ['#edb842','#365768','#d79970','#905475'],
  ['#399184','#485768','#e5b998','#ec7759'],
  ['#cd7094','#524759','#88543b','#61a28c'],
  ['#42a9b0','#474965','#f0c29b','#be604e'],
  ['#ee9c58','#344b62','#bc805a','#efda9a'],
]);
const charcoal=[.19,.17,.16];
const componentsPerFigure=6800;
const maxVisibleFigures=224;
const matrix=new Float32Array(16);
const tau=2*Math.PI;
const cosine=latitude=>Math.cos(latitude*Math.PI/180);
const mercator=(lng,lat)=>[(lng+180)/360,(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2];

function routeSeed(key){
  let hash=2166136261;
  for(const char of key)hash=Math.imul(hash^char.charCodeAt(0),16777619);
  return (hash>>>0)%1024;
}

function toRoute(path,projection){
  const points=path.points.map(point=>{
    const [mx,my]=mercator(...point);
    return {point,x:(mx-projection.mx)/projection.m,y:(projection.my-my)/projection.m};
  });
  let length=0;
  const segments=points.slice(1).map((end,i)=>{
    const start=points[i],dx=end.x-start.x,dy=end.y-start.y;
    const size=Math.hypot(dx,dy);
    length+=size;
    return {start,end,dx,dy,size,offset:length-size,angle:Math.atan2(dy,dx)};
  }).filter(segment=>segment.size>.01);
  const longitude=path.points.map(point=>point[0]),latitude=path.points.map(point=>point[1]);
  const bounds=[Math.min(...longitude),Math.min(...latitude),Math.max(...longitude),Math.max(...latitude)];
  return {segments,length,seed:path.key==null?null:routeSeed(path.key),count:path.people,bounds,near101:touches101Ground(bounds),single101:!!path.single101};
}

function routeTouchesBounds(route,[[west,south],[east,north]]){
  const [w,s,e,n]=route.bounds;
  return w<=east&&e>=west&&s<=north&&n>=south;
}

function position(route,fraction,time,speed){
  const travel=(fraction*route.length*2+time*speed)%(route.length*2);
  const distance=travel<=route.length?travel:2*route.length-travel;
  const segment=route.segments.find(s=>distance<s.offset+s.size)??route.segments.at(-1);
  const {start,end,dx,dy,offset,size,angle}=segment;
  const progress=(distance-offset)/size;
  const facing=travel<=route.length?angle:angle+Math.PI;
  return {
    x:start.x+dx*progress,y:start.y+dy*progress,angle:facing,
    point:start.point.map((n,i)=>n+(end.point[i]-n)*progress),
  };
}

class FigureMesh {
  constructor(data){this.data=data;this.length=0;}
  at(x,y,z,angle){
    this.x=x;this.y=y;this.z=z;
    this.forward=[Math.cos(angle),Math.sin(angle)];
  }
  vertex([x,y,z],color,shade){
    const [a,b]=this.forward;
    this.data[this.length++]=this.x+a*x-b*y;
    this.data[this.length++]=this.y+b*x+a*y;
    this.data[this.length++]=this.z+z;
    for(const channel of color)this.data[this.length++]=channel*shade;
  }
  ring(center,radii,heading,sides){
    const [x,y,z]=center,[depth,width]=radii;
    const a=Math.cos(heading),b=Math.sin(heading);
    return Array.from({length:sides},(_,i)=>{
      const phase=(i+.5)*tau/sides;
      const d=Math.cos(phase)*depth,w=Math.sin(phase)*width;
      return [x+a*d,y+w,z-b*d];
    });
  }
  shape(base,top,wide,narrow,color,sides=6){
    const heading=Math.atan2(top[0]-base[0],top[2]-base[2]);
    const low=this.ring(base,wide,heading,sides),high=this.ring(top,narrow,heading,sides);
    for(let i=0;i<sides;i++){
      const j=(i+1)%sides,shade=.87+.13*Math.cos(i*tau/sides-.4);
      for(const p of [low[i],low[j],high[i],high[i],low[j],high[j]])this.vertex(p,color,shade);
      for(const p of [top,high[i],high[j]])this.vertex(p,color,1.07);
      for(const p of [base,low[j],low[i]])this.vertex(p,color,.79);
    }
  }
  person(outfit,index,phase){
    const [coat,denim,skin,accent]=outfit;
    const swing=Math.sin(phase);
    for(const side of [-1,1]){
      const stride=swing*side;
      const foot=stride*.31,lift=Math.max(0,Math.cos(phase)*side)*.13;
      this.shape([foot+.07,side*.13,.025+lift],[foot+.068,side*.13,.15+lift],[.17,.102],[.154,.094],charcoal,4);
      this.shape([foot,side*.13,.12+lift],[0,side*.13,.91],[.095,.094],[.113,.118],denim);
      const hand=[-stride*.32,side*.315,1.02+Math.abs(stride)*.06];
      this.shape(hand,[-stride*.06,side*.24,1.52],[.09,.086],[.109,.106],coat);
      this.shape([hand[0],hand[1],hand[2]-.098],hand,[.064,.063],[.079,.078],skin);
    }
    this.shape([0,0,.88],[0,0,1.56],[.195,.27],[.163,.256],coat);
    this.shape([.025,0,1.51],[.025,0,1.65],[.13,.149],[.12,.138],accent);
    this.shape([.039,0,1.61],[.039,0,1.99],[.147,.16],[.157,.163],skin,8);
    this.shape([.016,0,1.89],[.011,0,2.05],[.166,.173],[.11,.12],index%5===0?accent:charcoal,8);
    if(index%3===0){
      this.shape([-.169,0,1.06],[-.169,0,1.48],[.124,.188],[.105,.155],accent);
    }
  }
  umbrella(color){
    const peak=[.052,0,2.81], center=[.052,0,2.61];
    const edge=this.ring(center,[.64,.64],0,8);
    this.shape([.052,0,1.17],center,[.024,.024],[.024,.024],charcoal,4);
    for(let i=0;i<edge.length;i++){
      this.vertex(peak,color,i%2?.94:1);
      this.vertex(edge[i],color,.83);
      this.vertex(edge[(i+1)%edge.length],color,.83);
    }
  }
}

export class StreetPeople {
  type='custom';
  renderingMode='3d';
  count=0;
  playing=false;
  elapsed=0;
  timer=0;
  paused=false;
  umbrellaShare=0;
  umbrellas=0;
  firstPosition=null;

  constructor(id,origin,paths,minZoom=16.65,hybrid=false){
    this.minZoom=minZoom;
    this.wardrobe=hybrid?hybridWardrobe:wardrobe;
    this.id=`${id}-people`;
    this.origin=origin;
    const [mx,my]=mercator(...origin);
    this.projection={mx,my,m:1/(40030228.9*cosine(origin[1]))};
    this.routes=paths.map(path=>toRoute(path,this.projection)).filter(route=>route.length>.01);
    const bounds=[Infinity,Infinity,-Infinity,-Infinity];
    for(const {bounds:[w,s,e,n]} of this.routes){
      bounds[0]=Math.min(bounds[0],w);
      bounds[1]=Math.min(bounds[1],s);
      bounds[2]=Math.max(bounds[2],e);
      bounds[3]=Math.max(bounds[3],n);
    }
    this.coverage={bounds};
    this.figureLimit=Math.min(maxVisibleFigures,this.routes.reduce((sum,route)=>sum+route.count,0));
    this.vertexData=new Float32Array(this.figureLimit*componentsPerFigure);
    this.motion=matchMedia('(prefers-reduced-motion: reduce)');
    this.refresh=()=>this.map.triggerRepaint();
  }
  static forStreetPacks(origin,records,hybrid,previous){
    const entries=Object.entries(Object.assign({},...records.map(record=>record.paths)));
    const paths=entries.map(([key,path])=>({...path,key}));
    const model=new StreetPeople('city170',previous?.origin??origin,paths,16.65,hybrid);
    model.elapsed=previous?.elapsed??0;
    return model;
  }
  onAdd(map,gl){
    this.map=map;
    this.program=program(gl,vertex,fragment);
    this.matrixLocation=gl.getUniformLocation(this.program,'matrix');
    this.buffer=gl.createBuffer();
    this.vao=gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER,this.vertexData.byteLength,gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(0,3,gl.FLOAT,false,24,0);
    gl.vertexAttribPointer(1,3,gl.FLOAT,false,24,12);
    gl.bindVertexArray(null);
    this.motion.addEventListener('change',this.refresh);
    document.addEventListener('visibilitychange',this.refresh);
  }
  onRemove(map,gl){
    clearTimeout(this.timer);
    this.motion.removeEventListener('change',this.refresh);
    document.removeEventListener('visibilitychange',this.refresh);
    gl.deleteVertexArray(this.vao);
    gl.deleteBuffer(this.buffer);
    gl.deleteProgram(this.program);
  }
  isActive(bounds){
    if(this.map.getZoom()<this.minZoom)return false;
    const extent=bounds.toArray();
    return routeTouchesBounds(this.coverage,extent)&&this.routes.some(route=>routeTouchesBounds(route,extent));
  }
  render(gl,options){
    const map=this.map;
    const bounds=map.getBounds();
    const active=this.isActive(bounds);
    const playing=active&&!document.hidden&&!this.paused&&!this.motion.matches;
    const now=performance.now();
    if(playing&&this.playing)this.elapsed+=Math.min((now-this.lastRender)/1000,.1);
    this.lastRender=now;
    this.playing=playing;
    this.count=0;
    this.firstPosition=null;
    if(!playing&&this.timer){
      clearTimeout(this.timer);
      this.timer=0;
    }
    this.umbrellas=0;
    if(!active)return;
    const vertexData=this.vertexData;
    const mesh=new FigureMesh(vertexData);
    const extent=bounds.toArray();
    const visibilityScale=1+.78*Math.max(0,Math.min(1,(18.25-map.getZoom())/1.6));
    let index=0;
    for(const route of this.routes){
      if(this.count===this.figureLimit)break;
      if(!routeTouchesBounds(route,extent)){index+=route.count;continue;}
      for(let i=0;i<route.count&&this.count<this.figureLimit;i++,index++){
        const fraction=(i+.32)/route.count*.5+(i%2)*.5;
        const personIndex=route.seed==null?index:route.seed+i;
        const speed=.83+(personIndex%4)*.18;
        const current=position(route,fraction,this.elapsed,speed);
        if(!bounds.contains(current.point))continue;
        if(route.near101 && inside101Ground(...current.point)!==route.single101)continue;
        const terrain=map.queryTerrainElevation(current.point);
        if(terrain==null)continue;
        const size=(.9+(personIndex%4)*.08)*visibilityScale;
        mesh.at(current.x,current.y,terrain/size,current.angle);
        // Scale each completed figure around its contact point on the sidewalk.
        const first=mesh.length;
        const outfit=this.wardrobe[personIndex%this.wardrobe.length];
        mesh.person(outfit,personIndex,this.elapsed*speed*6.7+personIndex*.81);
        if(personIndex%4<this.umbrellaShare){mesh.umbrella(outfit[3]);this.umbrellas++;}
        for(let j=first;j<mesh.length;j+=6){
          vertexData[j]=current.x+(vertexData[j]-current.x)*size;
          vertexData[j+1]=current.y+(vertexData[j+1]-current.y)*size;
          vertexData[j+2]*=size;
        }
        this.count++;
        this.firstPosition??=current.point;
      }
    }
    if(this.count){
      gl.useProgram(this.program);
      gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);
      gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
      transform(options.defaultProjectionData.mainMatrix,this.projection,matrix);
      gl.uniformMatrix4fv(this.matrixLocation,false,matrix);
      gl.bindVertexArray(this.vao);
      gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.bufferSubData(gl.ARRAY_BUFFER,0,vertexData,0,mesh.length);
      gl.drawArrays(gl.TRIANGLES,0,mesh.length/6);
      gl.bindVertexArray(null);
    }
    if(playing&&!this.timer)this.timer=setTimeout(()=>{
      this.timer=0;
      if(!document.hidden&&!this.paused&&!this.motion.matches)this.refresh();
    },42);
  }
}
