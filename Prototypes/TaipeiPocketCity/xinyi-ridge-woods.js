// The understorey follows mapped wood and hill aspect. The sparse crowns are
// illustrations; the city's separate tree inventory retains its measured roots.
import {LngLat,MercatorCoordinate} from './assets/maplibre-gl.mjs';
import {decodeMapJSON} from './pocket-city-atlas.js';
import {program,transform} from './survey-layer.js';

const ridge=[121.5617,25.0080,121.5923,25.0375];
const elevationDelays=[120,350,900,2000,4000,8000];
const east=111320*Math.cos(25.03*Math.PI/180),north=110574;
const prefix='xinyi-ridge-',artURL=new URL('./assets/xinyi-ridge-woods.json.gz',import.meta.url);
const reliefURL=new URL('./assets/xinyi-ridge-relief.png',import.meta.url).href;
const smooth=(z,from,to,end=1)=>['interpolate',['linear'],['zoom'],z,from,to,end];
const marker=(map,id,fallback)=>map.getLayer(id)?id:fallback;
const vertex=`#version 300 es
layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in float foliage;
layout(location=3) in vec3 root;
layout(location=4) in vec2 scaleTurn;
uniform mat4 matrix;
out vec3 tint;
void main() {
  float height=scaleTurn.x, c=cos(scaleTurn.y), s=sin(scaleTurn.y);
  mat2 rotation=mat2(c,s,-s,c);
  vec3 xyz=vec3(rotation*position.xy,position.z)*height;
  gl_Position=matrix*vec4(root+xyz,1.);
  vec3 n=normalize(vec3(rotation*normal.xy,normal.z));
  float light=dot(n,normalize(vec3(-.62,.46,.64)));
  float localTone=sin(root.x*.013+root.y*.019)*.5+sin(root.x*.023-root.y*.007)*.5;
  if(foliage<.5){
    tint=mix(vec3(.20,.17,.12),vec3(.48,.36,.23),smoothstep(-.3,.72,light));
  }else{
    // Inked lower sprays and warm, selectively lit tips keep the tree readable
    // against the sunlit slope. A smooth geographical tint follows neighboring stands.
    vec3 dark=vec3(.13,.27,.22),middle=vec3(.26,.43,.28),sun=vec3(.55,.67,.36);
    tint=mix(dark,middle,smoothstep(-.48,.24,light));
    tint=mix(tint,sun,smoothstep(.37,.9,light)*(.55+.45*foliage/4.));
    tint*=mix(.72,1.06,clamp((foliage-1.)/3.,0.,1.));
    tint+=vec3(localTone*.029,localTone*.020,-localTone*.012);
  }
}`;
const fragment=`#version 300 es
precision mediump float;
in vec3 tint;
out vec4 pixel;
void main(){pixel=vec4(tint,1.);}
`;

function crownMesh(){
  const mesh=[];
  function face(a,b,c,leaf){
    const u=b.map((v,i)=>v-a[i]),v=c.map((q,i)=>q-a[i]);
    const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
    for(const p of [a,b,c])mesh.push(...p,...n,leaf);
  }
  function rings(cx,cy,levels,sides,leaf,turn){
    const polys=levels.map(([z,r,ry])=>Array.from({length:sides},(_,i)=>{
      const a=i*Math.PI*2/sides+turn,w=1+.09*Math.sin(3*a+turn);
      return [cx+r*w*Math.cos(a),cy+ry*w*Math.sin(a),z];
    }));
    for(let j=0;j<polys.length-1;j++)for(let i=0;i<sides;i++){
      const next=(i+1)%sides,a=polys[j][i],b=polys[j][next],c=polys[j+1][next],d=polys[j+1][i];
      const band=leaf?j+1:0;
      if(levels[j][1]>0)face(a,b,c,band);
      if(levels[j+1][1]>0)face(a,c,d,band);
    }
  }
  rings(0,0,[[-.03,.046,.039],[.54,.024,.020]],5,0,0);
  for(const [x,y,z] of [[-.17,.06,.52],[.15,.08,.57],[.03,-.16,.59]]){
    const r=.023;
    for(let j=0;j<4;j++){
      const a=j*Math.PI/2,b=(j+1)*Math.PI/2;
      face([r*Math.cos(a),r*Math.sin(a),.29],[r*Math.cos(b),r*Math.sin(b),.29],[x,y,z],0);
    }
  }
  // Four overlapping, irregular leaf masses hold their shape on an oblique hillside.
  for(const [x,y,z,r,t] of [[-.17,.06,.59,.255,.54],[.14,.10,.67,.235,1.7],[.04,-.145,.62,.235,2.3],[-.035,.005,.81,.265,0]]){
    rings(x,y,[[z-.20,0,0],[z-.085,r*.92,r*.79],[z+.02,r,r*.92],[z+.105,r*.66,r*.60],[z+.17,0,0]],7,1,t);
  }
  return new Float32Array(mesh);
}

export class RidgeCrowns {
  id=prefix+'crowns';
  type='custom';
  renderingMode='3d';
  constructor(art){
    const anchor=MercatorCoordinate.fromLngLat(art.origin),m=anchor.meterInMercatorCoordinateUnits();
    this.tile={mx:anchor.x,my:anchor.y,m};
    this.rows=art.crowns.map(([x,y,z,h,turn])=>{
      const loc=new LngLat(art.origin[0]+x/east,art.origin[1]+y/north),q=MercatorCoordinate.fromLngLat(loc);
      return {loc,x:(q.x-anchor.x)/m,y:(anchor.y-q.y)/m,z,h,turn:turn*Math.PI/180};
    });
    this.matrix=new Float32Array(16);
    this.count=0;
  }
  onAdd(map,gl){
    this.map=map;this.shader=program(gl,vertex,fragment);this.matrixLoc=gl.getUniformLocation(this.shader,'matrix');
    this.vao=gl.createVertexArray();this.mesh=gl.createBuffer();this.instances=gl.createBuffer();
    const oldVao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),oldBuffer=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    const shape=crownMesh();this.vertices=shape.length/7;
    gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.mesh);gl.bufferData(gl.ARRAY_BUFFER,shape,gl.STATIC_DRAW);
    for(const [i,size,offset] of [[0,3,0],[1,3,12],[2,1,24]]){
      gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,size,gl.FLOAT,false,28,offset);
    }
    gl.bindBuffer(gl.ARRAY_BUFFER,this.instances);
    for(const [i,size,offset] of [[3,3,0],[4,2,12]]){
      gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,size,gl.FLOAT,false,20,offset);gl.vertexAttribDivisor(i,1);
    }
    gl.bindVertexArray(oldVao);gl.bindBuffer(gl.ARRAY_BUFFER,oldBuffer);
    this.terrainChanged=e=>{
      if(e.sourceId==='dem'&&e.sourceDataType==='content'){
        this.restartSampling();
        this.elevationDirty=true;
      }
    };
    this.afterIdle=()=>{
      if(this.waitingForTerrain&&!this.idleChecked){
        this.idleChecked=true;this.elevationDirty=true;
        map.triggerRepaint();
      }
    };
    map.on('sourcedata',this.terrainChanged);map.on('idle',this.afterIdle);
  }
  restartSampling(){
    clearTimeout(this.timer);this.timer=null;this.retry=0;this.idleChecked=false;this.waitingForTerrain=false;
  }
  scheduleElevation(){
    if(!this.waitingForTerrain){
      clearTimeout(this.timer);this.timer=null;
    }else if(this.timer==null&&this.retry<elevationDelays.length){
      // Raster DEM content can precede MapLibre's drawn elevation tiles. A
      // stationary camera still gets a bounded resample after that render.
      this.timer=setTimeout(()=>{
        this.timer=null;this.elevationDirty=true;this.map.triggerRepaint();
      },elevationDelays[this.retry++]);
    }
  }
  update(gl,box,budget){
    const [w,s,e,n]=box,dx=(e-w)*.12,dy=(n-s)*.12;
    this.region=[w-dx,s-dy,e+dx,n+dy];this.viewSize=[e-w,n-s];this.budget=budget;
    const values=[];this.waitingForTerrain=false;this.elevationDirty=false;
    for(const {loc,x,y,h,turn} of this.rows){
      if(loc.lng<w-dx||loc.lng>e+dx||loc.lat<s-dy||loc.lat>n+dy)continue;
      let z=this.map.terrain?.getDrawnElevationForLngLat(loc);
      if(!Number.isFinite(z)||z<1){
        this.waitingForTerrain=true;
        z=this.map.queryTerrainElevation?.(loc);
        if(!Number.isFinite(z)||z<1)continue;
      }
      values.push(x,y,z,h,turn);
      if(values.length===budget*5)break;
    }
    const old=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    gl.bindBuffer(gl.ARRAY_BUFFER,this.instances);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(values),gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER,old);this.count=values.length/5;this.scheduleElevation();
  }
  render(gl,opts){
    const zoom=this.map.getZoom();
    if(zoom<15||!this.map.terrain){if(this.region)this.restartSampling();this.region=null;this.count=0;return;}
    const bounds=this.map.getBounds(),box=[bounds.getWest(),bounds.getSouth(),bounds.getEast(),bounds.getNorth()];
    const budget=zoom<15.7?280:zoom<16.7?450:680,r=this.region;
    const smaller=r&&(box[2]-box[0]<this.viewSize[0]*.65||box[3]-box[1]<this.viewSize[1]*.65);
    const moved=!r||smaller||budget!==this.budget||box[0]<r[0]||box[1]<r[1]||box[2]>r[2]||box[3]>r[3];
    if(moved)this.restartSampling();
    if(moved||this.elevationDirty)this.update(gl,box,budget);
    if(!this.count)return;
    const vao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),shader=gl.getParameter(gl.CURRENT_PROGRAM);
    const oldDepth=gl.isEnabled(gl.DEPTH_TEST),oldCull=gl.isEnabled(gl.CULL_FACE),oldBlend=gl.isEnabled(gl.BLEND);
    const oldFunc=gl.getParameter(gl.DEPTH_FUNC),oldMask=gl.getParameter(gl.DEPTH_WRITEMASK);
    gl.useProgram(this.shader);gl.bindVertexArray(this.vao);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);
    gl.depthMask(true);gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
    transform(opts.defaultProjectionData.mainMatrix,this.tile,this.matrix);gl.uniformMatrix4fv(this.matrixLoc,false,this.matrix);
    gl.drawArraysInstanced(gl.TRIANGLES,0,this.vertices,this.count);
    gl.bindVertexArray(vao);gl.useProgram(shader);gl.depthFunc(oldFunc);gl.depthMask(oldMask);
    if(!oldDepth)gl.disable(gl.DEPTH_TEST);if(oldCull)gl.enable(gl.CULL_FACE);if(oldBlend)gl.enable(gl.BLEND);
  }
  onRemove(map,gl){
    this.restartSampling();map.off('sourcedata',this.terrainChanged);map.off('idle',this.afterIdle);gl.deleteVertexArray(this.vao);gl.deleteBuffer(this.mesh);
    gl.deleteBuffer(this.instances);gl.deleteProgram(this.shader);this.region=null;this.count=0;
  }
}

export function addXinyiRidgeWoods(map,firstLabel){
  let abort,installed=false,removed=false;
  const trailId=prefix+'paths',relief=prefix+'relief';
  function clear(){
    for(const id of [prefix+'crowns',trailId+'-ink',trailId+'-edge',relief])if(map.getLayer(id))map.removeLayer(id);
    for(const id of [trailId,relief])if(map.getSource(id))map.removeSource(id);
    installed=false;
  }
  async function update(){
    const zoom=map.getZoom(),b=map.getBounds();
    const intersects=b.getEast()>=ridge[0]&&b.getWest()<=ridge[2]&&b.getNorth()>=ridge[1]&&b.getSouth()<=ridge[3];
    if(removed)return;
    if(zoom<13.4||!intersects){
      abort?.abort();abort=null;if(installed)clear();return;
    }
    if(zoom<14||abort||installed)return;
    const request=abort=new AbortController();
    try{
      const response=await fetch(artURL,{signal:request.signal});
      if(!response.ok)throw Error('Ridge woodland '+response.status);
      const art=await decodeMapJSON(response);
      if(removed||abort!==request)return;
      map.addSource(relief,{type:'image',url:reliefURL,coordinates:art.corners});
      map.addLayer({id:relief,type:'raster',source:relief,minzoom:14,
        paint:{'raster-opacity':smooth(14,0,15.15,.91),'raster-fade-duration':0}},marker(map,'city170-water',firstLabel));
      map.addSource(trailId,{type:'geojson',data:{type:'FeatureCollection',features:art.trails},maxzoom:19,tolerance:0});
      const before=marker(map,'city170-prepared-lane',firstLabel);
      for(const [suffix,color,width] of [['edge','#8a7959',1.9],['ink','#ecd1a0',1.05]]){
        map.addLayer({id:trailId+'-'+suffix,type:'line',source:trailId,minzoom:14.85,
          layout:{'line-join':'round','line-cap':'round'},paint:{'line-color':color,
            'line-width':['interpolate',['exponential',1.4],['zoom'],15,width*.65,17,width,19,width*1.8],
            'line-opacity':['interpolate',['linear'],['zoom'],14.85,0,15.65,.83,17.5,.82,18.7,0]}},before);
      }
      map.addLayer(new RidgeCrowns(art),marker(map,'city170-inventory-trees',firstLabel));
      installed=true;
    }catch(error){
      if(abort===request&&!removed){clear();console.warn('四獸山林地',error.message);}
    }finally{if(abort===request)abort=null;}
  }
  map.on('moveend',update);
  map.on('remove',()=>{removed=true;abort?.abort();map.off('moveend',update);});
  void update();
}
