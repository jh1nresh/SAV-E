// Pocket Nature's Watarase field atlas uses forked wood and sunlit scalloped leaf sprays.
// Here each spray stays on its tree in 3D while its outline faces the reader.
import {MercatorCoordinate,LngLat} from './assets/maplibre-gl.mjs';
import {program,transform} from './survey-layer.js';

const vertex=`#version 300 es
layout(location=0) in vec3 p;
layout(location=1) in vec2 leaf;
layout(location=2) in vec3 ink;
layout(location=3) in vec4 root;
layout(location=4) in float turn;
uniform mat4 matrix;
uniform vec3 rightAxis,upAxis;
out vec3 tint;
void main(){
  float c=cos(turn),s=sin(turn);
  vec3 q=vec3(c*p.x-s*p.y,s*p.x+c*p.y,p.z)+rightAxis*leaf.x+upAxis*leaf.y;
  gl_Position=matrix*vec4(root.xyz+q*root.w,1.);
  tint=ink*(.97+.05*sin(turn));
}`;
const fragment=`#version 300 es
precision mediump float;
in vec3 tint;
out vec4 pixel;
void main(){pixel=vec4(tint,1.);}
`;
const forms=['broad','round','column','palm'];
const tau=Math.PI*2;
const bark=[.45,.35,.26], barkLight=[.61,.47,.34];
const palette=[[.28,.43,.31],[.36,.53,.35],[.49,.64,.38],[.63,.73,.45]];
function plant(form){
  const vertices=[];
  const vertex=(p,offset,color)=>vertices.push(...p,...offset,...color);
  function branch(start,end,r1,r2){
    for(let j=0;j<5;j++){
      const ring=(base,r,k)=>[base[0]+r*Math.cos(k*tau/5),base[1]+r*Math.sin(k*tau/5),base[2]];
      const a=ring(start,r1,j),b=ring(end,r2,j),c=ring(end,r2,j+1),d=ring(start,r1,j+1);
      for(const p of [a,b,c,a,c,d])vertex(p,[0,0],j<2?barkLight:bark);
    }
  }
  if(form==='fir'){
    branch([0,0,0],[0,0,.99],.031,.009);
    // Offset each tier so daylight can show between the drooping boughs.
    for(let tier=0;tier<7;tier++){
      const base=.19+tier*.11,span=.24*(1-tier/8);
      for(let j=0;j<9;j++){
        const a=j*tau/9+tier*.8;
        const tip=[span*Math.cos(a),span*Math.sin(a),base-.025];
        for(const sign of [-1,1]){
          const side=[span*.72*Math.cos(a+sign*.37),span*.72*Math.sin(a+sign*.37),base+.032];
          const shade=palette[Math.cos(a+sign*.4)>.4?2:0];
          for(const v of [[0,0,base+.13],side,tip])vertex(v,[0,0],shade);
        }
      }
    }
  }else if(form==='palm'){
    branch([0,0,0],[.025,0,.79],.027,.016);
    for(let j=0;j<13;j++){
      const a=j*2.4,c=Math.cos(a),s=Math.sin(a),radius=.32+.04*Math.cos(j*2);
      const tip=(t,offset)=>[.025+c*radius*t-s*offset,s*radius*t+c*offset,.78+.66*t*(1-t)-.14*t*t];
      for(let k=0;k<8;k++){
        const t=k/8,u=(k+1)/8,w=.017*Math.sin(Math.PI*(t+.05))+.004;
        for(const p of [tip(t,-w),tip(t,w),tip(u,0)])vertex(p,[0,0],palette[j%4]);
        for(const sign of [-1,1]){
          const end=tip(u+.031,sign*(.064*Math.sin(Math.PI*u)+.009));
          end[2]-=.05;
          for(const p of [tip(t,0),tip(u,0),end])vertex(p,[0,0],palette[(j+k%2)%4]);
        }
      }
    }
  }else{
    const width=form==='broad'?.42:form==='column'?.18:.31;
    const depth=form==='column'?.30:.21;
    branch([0,0,0],[.012,0,.54],.036,.021);
    for(let j=0;j<5;j++){
      const a=j*2.4;
      branch([.008,0,.36+.026*j],[width*.51*Math.cos(a),width*.51*Math.sin(a),.64+.035*(j%3)],.020,.008);
    }
    for(let j=0;j<32;j++){
      const nz=2*(j+.5)/32-1,radial=Math.sqrt(1-nz*nz);
      const a=j*2.39996, nx=Math.cos(a)*radial,ny=Math.sin(a)*radial;
      const center=[nx*width*.81,ny*width*.81,.67+nz*depth];
      const light=-.49*nx+.28*ny+.73*nz;
      const color=palette[light>.44?3:light>.02?2:light>-.46?1:0];
      const rx=width*(.33+.035*Math.cos(j)),ry=.08+.015*Math.sin(j);
      function rim(k){
        const theta=tau*k/22;
        const r=(k%2===0?1:.88)+.035*Math.cos(k*3+j);
        return [rx*Math.cos(theta)*r,ry*Math.sin(theta)*r];
      }
      // Round each shoulder of the spray and leave a few fine paired leaf strokes
      // on the lit planes. The strokes share their spray's depth and camera angle.
      const edge=[];
      for(let k=0;k<22;k++){
        const a=rim(k),b=rim(k+1);
        edge.push([.76*a[0]+.24*b[0],.76*a[1]+.24*b[1]],
                  [.24*a[0]+.76*b[0],.24*a[1]+.76*b[1]]);
      }
      for(let k=0;k<edge.length;k++){
        vertex(center,[0,0],color);
        vertex(center,edge[k],color);
        vertex(center,edge[(k+1)%edge.length],color);
      }
      if(j%3!==0){
        const leafInk=color.map((c,i)=>c*.79+[.91,.89,.61][i]*.21);
        for(const sign of [-1,1]){
          for(const uv of [[-.09,.02],[sign*.23,.30],[sign*.36,.32],[sign*.36,.32],[sign*.18,.11],[-.09,.02]]){
            vertex(center,[uv[0]*rx,uv[1]*ry],leafInk);
          }
        }
      }
    }
  }
  return new Float32Array(vertices);
}

const bin=(x,y)=>x+','+y;
export function indexTrees(rows){
  const buckets=new Map();
  for(const row of rows){
    const x=Math.floor(row[0]*100780/10),y=Math.floor(row[1]*110800/10),key=bin(x,y);
    if(!buckets.has(key))buckets.set(key,[]);
    buckets.get(key).push(row);
  }
  return {
    rows,
    near(lon,lat,radius){
      const x=Math.floor(lon*100780/10),y=Math.floor(lat*110800/10);
      for(let i=x-1;i<=x+1;i++)for(let j=y-1;j<=y+1;j++){
        if(buckets.get(bin(i,j))?.some(([a,b])=>Math.hypot((a-lon)*100780,(b-lat)*110800)<radius))return true;
      }
      return false;
    },
  };
}

export class CityNature {
  id='city170-inventory-trees';
  type='custom';
  renderingMode='3d';
  rows=[];
  drawn=0;
  activeTrees=indexTrees([]);
  rootKey='';
  revision=0;
  publishRoots(rows,key){
    if(this.rootKey===key)return;
    this.rootKey=key;
    this.activeTrees=indexTrees(rows);
    this.revision++;
    this.onRootsChanged?.();
  }
  setRows(rows){
    this.rows=rows;
    this.dirty=true;
    this.map.triggerRepaint();
  }
  onAdd(map,gl){
    this.map=map;
    this.program=program(gl,vertex,fragment);
    this.matrix=new Float32Array(16);
    this.uniforms=Object.fromEntries(['matrix','rightAxis','upAxis'].map(k=>[k,gl.getUniformLocation(this.program,k)]));
    this.forms=this.id==='taiwan-cell-forest'?[...forms,'fir']:forms;
    this.meshes=this.forms.map(form=>{
      const model=plant(form),vao=gl.createVertexArray(),shape=gl.createBuffer(),instances=gl.createBuffer();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER,shape);
      gl.bufferData(gl.ARRAY_BUFFER,model,gl.STATIC_DRAW);
      for(const [slot,size,offset] of [[0,3,0],[1,2,12],[2,3,20]]){
        gl.enableVertexAttribArray(slot);
        gl.vertexAttribPointer(slot,size,gl.FLOAT,false,32,offset);
      }
      gl.bindBuffer(gl.ARRAY_BUFFER,instances);
      for(const [slot,size,offset] of [[3,4,0],[4,1,16]]){
        gl.enableVertexAttribArray(slot);
        gl.vertexAttribPointer(slot,size,gl.FLOAT,false,20,offset);
        gl.vertexAttribDivisor(slot,1);
      }
      gl.bindVertexArray(null);
      return {vao,shape,instances,vertices:model.length/8,count:0};
    });
    this.terrainChanged=e=>{if(e.sourceId==='dem' && e.sourceDataType==='content')this.dirty=true;};
    map.on('sourcedata',this.terrainChanged);
  }
  sample(gl,bounds){
    const [[w,s],[e,n]]=bounds.toArray(),dx=(e-w)*.18,dy=(n-s)*.18;
    this.region=[w-dx,s-dy,e+dx,n+dy];
    const base=MercatorCoordinate.fromLngLat(this.map.getCenter()),m=base.meterInMercatorCoordinateUnits();
    this.tile={mx:base.x,my:base.y,m};
    const groups=this.forms.map(()=>[]);
    const visible=[];
    for(const row of this.rows){
      const [lon,lat,h,form]=row;
      if(lon<w-dx||lat<s-dy||lon>e+dx||lat>n+dy)continue;
      const z=this.map.terrain?.getDrawnElevationForLngLat(new LngLat(lon,lat));
      if(!Number.isFinite(z))continue;
      const alpine=this.id==='taiwan-cell-forest'&&z>=2500;
      if(alpine&&z>=3600)continue;
      visible.push(row);
      const q=MercatorCoordinate.fromLngLat([lon,lat]),i=this.forms.indexOf(alpine?'fir':form);
      const height=h>0?h:form==='palm'?7:6;
      groups[i<0?1:i].push((q.x-base.x)/m,(base.y-q.y)/m,z,height,((lon*26553+lat*8179)%1)*tau);
    }
    for(const [i,mesh] of this.meshes.entries()){
      const instances=new Float32Array(groups[i]);
      mesh.count=instances.length/5;
      gl.bindBuffer(gl.ARRAY_BUFFER,mesh.instances);
      gl.bufferData(gl.ARRAY_BUFFER,instances,gl.DYNAMIC_DRAW);
    }
    this.publishRoots(visible,visible.map(row=>row[0]+','+row[1]).join(';'));
    this.dirty=false;
  }
  render(gl,opts){
    this.drawn=0;
    if(this.map.getZoom()<16.9 || !this.rows.length){
      if(this.rootKey){this.publishRoots([],'');this.dirty=true;}
      return;
    }
    const b=this.map.getBounds(),r=this.region;
    if(this.dirty||!r||b.getWest()<r[0]||b.getEast()>r[2]||b.getSouth()<r[1]||b.getNorth()>r[3])this.sample(gl,b);
    const pitch=this.map.getPitch()*Math.PI/180,bearing=this.map.getBearing()*Math.PI/180;
    gl.useProgram(this.program);
    gl.uniform3f(this.uniforms.rightAxis,Math.cos(bearing),-Math.sin(bearing),0);
    gl.uniform3f(this.uniforms.upAxis,Math.sin(bearing)*Math.cos(pitch),Math.cos(bearing)*Math.cos(pitch),Math.sin(pitch));
    transform(opts.defaultProjectionData.mainMatrix,this.tile,this.matrix);
    gl.uniformMatrix4fv(this.uniforms.matrix,false,this.matrix);
    gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
    for(const mesh of this.meshes){
      if(!mesh.count)continue;
      gl.bindVertexArray(mesh.vao);
      gl.drawArraysInstanced(gl.TRIANGLES,0,mesh.vertices,mesh.count);
      this.drawn+=mesh.count;
    }
    gl.bindVertexArray(null);
  }
  onRemove(map,gl){
    map.off('sourcedata',this.terrainChanged);
    for(const {vao,shape,instances} of this.meshes){
      gl.deleteVertexArray(vao);gl.deleteBuffer(shape);gl.deleteBuffer(instances);
    }
    gl.deleteProgram(this.program);
  }
}
