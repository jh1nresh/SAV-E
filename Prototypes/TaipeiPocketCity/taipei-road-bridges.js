// Road paint in the base vector tiles remains available until a grounded deck is drawn.
import {LngLat,MercatorCoordinate} from './assets/maplibre-gl.mjs';
import {decodeMapJSON} from './pocket-city-atlas.js';
import {program,transform} from './survey-layer.js';
import {bridgeMesh,bridgeDeckMaterial} from './taipei-bridge-mesh.js';
import {asphaltColors} from './taipei-asphalt.js';

const layerId='taipei-road-bridges',minZoom=16.65;
const extent=[121.45,24.95,121.67,25.22];
const delays=[150,450,1100,2500,5000],raised='pocketRaisedRoad';
const shader=`#version 300 es
layout(location=0) in vec3 xyz;
layout(location=1) in vec3 pigment;
uniform mat4 matrix;
uniform vec3 asphalt;
out vec3 color;
void main(){
  gl_Position=matrix*vec4(xyz,1.);
  color=distance(pigment,vec3(${bridgeDeckMaterial.join(',')}))<.001 ? asphalt : pigment;
}`;
const fragment=`#version 300 es
precision mediump float;
in vec3 color;
out vec4 pixel;
void main(){pixel=vec4(color,1.);}`;
function bounds(map){
  const b=map.getBounds();return [b.getWest(),b.getSouth(),b.getEast(),b.getNorth()];
}
function intersects(a,b){
  return a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
}
function rgb(value){
  const color=/^#[0-9a-f]{6}$/i.test(value)?value:asphaltColors.day;
  return [1,3,5].map(i=>parseInt(color.slice(i,i+2),16)/255);
}

export class TaipeiRoadBridges {
  id=layerId;
  type='custom';
  renderingMode='3d';
  drawnIds=[];
  constructor(spans){
    this.spans=spans;this.paintIds=new Map(spans.map(s=>[s.id,s.paintIds]));this.opacities=new Map();this.matrix=new Float32Array(16);
    const origin=MercatorCoordinate.fromLngLat([121.55,25.05]),m=origin.meterInMercatorCoordinateUnits();
    this.tile={mx:origin.x,my:origin.y,m};
    this.project=(lon,lat)=>{
      const p=MercatorCoordinate.fromLngLat([lon,lat]);return [(p.x-origin.x)/m,(origin.y-p.y)/m];
    };
  }
  onAdd(map,gl){
    this.map=map;this.shader=program(gl,shader,fragment);this.matrixLoc=gl.getUniformLocation(this.shader,'matrix');
    this.asphaltLoc=gl.getUniformLocation(this.shader,'asphalt');
    this.vao=gl.createVertexArray();this.buffer=gl.createBuffer();
    const oldVao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),oldBuffer=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    for(const [i,offset] of [[0,0],[1,12]]){gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,3,gl.FLOAT,false,24,offset);}
    gl.bindVertexArray(oldVao);gl.bindBuffer(gl.ARRAY_BUFFER,oldBuffer);
    this.demChanged=e=>{
      if(e.sourceId==='dem'&&e.sourceDataType==='content'){
        this.resetRetry();this.dirty=true;map.triggerRepaint();
      }
    };
    this.afterIdle=()=>{
      if(this.missing&&!this.idleChecked){this.idleChecked=true;this.dirty=true;map.triggerRepaint();}
    };
    this.weather=e=>{this.weatherColor=e.color;map.triggerRepaint();};
    map.on('sourcedata',this.demChanged);map.on('idle',this.afterIdle);map.on('pocketasphalt',this.weather);
    this.resetRetry();this.dirty=true;
  }
  resetRetry(){
    clearTimeout(this.timer);this.timer=null;this.attempt=0;this.idleChecked=false;this.missing=false;
  }
  ground(lon,lat){
    const p=new LngLat(lon,lat),terrain=this.map.terrain;
    const drawn=terrain.getDrawnElevationForLngLat?.(p);
    if(Number.isFinite(drawn))return drawn; // Sea-level zero is a real sampled height.
    const sample=terrain.getElevationAndDEMStateForLngLat?.(p,Math.floor(this.map.getZoom()));
    if(sample?.demState==='loaded'&&Number.isFinite(sample.elevation))return sample.elevation;
    this.missing=true;return null;
  }
  replacePaint(ids){
    const key=ids.join(',');
    if(key===(this.paintKey??''))return;
    this.paintKey=key;
    if(ids.length&&!this.opacities.size){
      const visible=value=>['case',['boolean',['feature-state',raised],false],0,value];
      for(const id of this.map.getLayersOrder()){
        if(!id.startsWith('bridge_')||/rail|pedestrian/.test(id))continue;
        const layer=this.map.getLayer(id);
        if(layer.type!=='line'||layer.source!=='openmaptiles'||layer.sourceLayer!=='transportation')continue;
        const original=this.map.getPaintProperty(id,'line-opacity');
        this.opacities.set(id,original);
        // The base street casing interpolates opacity with zoom. Keep its zoom
        // expression at the top level, as required by the MapLibre style spec.
        const paint=original?.[0]==='interpolate'&&original[2]?.[0]==='zoom'?
          original.map((value,i)=>i>=4&&i%2===0?visible(value):value):visible(original??1);
        this.map.setPaintProperty(id,'line-opacity',paint);
      }
    }
    // IDs and every tile fragment they cover were checked against the pinned
    // z14 source. Merged OMT IDs cannot be inferred from an OSM way number.
    const target=id=>({source:'openmaptiles',sourceLayer:'transportation',id});
    const active=ways=>new Set(ways.flatMap(way=>this.paintIds.get(way)));
    const next=active(ids),old=active(this.drawnIds);
    for(const id of old)if(!next.has(id))this.map.removeFeatureState(target(id),raised);
    for(const id of next)if(!old.has(id))this.map.setFeatureState(target(id),{[raised]:true});
    this.drawnIds=ids;
  }
  rebuild(gl,spans){
    const meshes=[],ids=[];let length=0;this.missing=false;this.dirty=false;
    for(const span of spans){
      const mesh=bridgeMesh(span,this.project,(x,y)=>this.ground(x,y));
      if(mesh.length){meshes.push(mesh);length+=mesh.length;ids.push(span.id);}
    }
    const data=new Float32Array(length);let offset=0;
    for(const mesh of meshes){data.set(mesh,offset);offset+=mesh.length;}
    const buffer=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,data,gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER,buffer);this.vertices=length/6;this.meshIds=ids;
    if(!this.missing){clearTimeout(this.timer);this.timer=null;}
    else if(this.timer===null&&this.attempt<delays.length){
      this.timer=setTimeout(()=>{this.timer=null;this.dirty=true;this.map.triggerRepaint();},delays[this.attempt++]);
    }
  }
  render(gl,opts){
    const area=bounds(this.map),visible=this.map.terrain&&this.map.getZoom()>=minZoom?
      this.spans.filter(s=>intersects(s.box,area)):[];
    const key=visible.map(s=>s.id).join(',');
    if(this.visibleKey!==key){this.visibleKey=key;this.resetRetry();this.dirty=true;}
    if(this.dirty)this.rebuild(gl,visible);
    // MapLibre can briefly draw a lower-zoom parent while street tiles load.
    // The packaged feature IDs are certified only for the z14 geometry.
    if(!this.vertices||this.map.isSourceLoaded?.('openmaptiles')===false){this.replacePaint([]);return;}
    const vao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),oldProgram=gl.getParameter(gl.CURRENT_PROGRAM);
    const depth=gl.isEnabled(gl.DEPTH_TEST),cull=gl.isEnabled(gl.CULL_FACE),blend=gl.isEnabled(gl.BLEND);
    const func=gl.getParameter(gl.DEPTH_FUNC),mask=gl.getParameter(gl.DEPTH_WRITEMASK);
    gl.useProgram(this.shader);gl.bindVertexArray(this.vao);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);
    gl.depthMask(true);gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
    transform(opts.defaultProjectionData.mainMatrix,this.tile,this.matrix);gl.uniformMatrix4fv(this.matrixLoc,false,this.matrix);
    gl.uniform3fv(this.asphaltLoc,rgb(this.map.getGlobalState?.()?.taipeiAsphalt??this.weatherColor));
    gl.drawArrays(gl.TRIANGLES,0,this.vertices);
    gl.bindVertexArray(vao);gl.useProgram(oldProgram);gl.depthFunc(func);gl.depthMask(mask);
    if(!depth)gl.disable(gl.DEPTH_TEST);if(cull)gl.enable(gl.CULL_FACE);if(blend)gl.enable(gl.BLEND);
    this.replacePaint(this.meshIds);
  }
  onRemove(map,gl){
    this.resetRetry();this.replacePaint([]);
    for(const [id,original] of this.opacities){
      if(map.getLayer(id))map.setPaintProperty(id,'line-opacity',original??null);
    }
    this.opacities.clear();
    map.off('sourcedata',this.demChanged);map.off('idle',this.afterIdle);map.off('pocketasphalt',this.weather);
    gl.deleteVertexArray(this.vao);gl.deleteBuffer(this.buffer);gl.deleteProgram(this.shader);
  }
}

export function addTaipeiRoadBridges(map,firstLabel){
  let request=null,removed=false;
  async function update(){
    if(removed)return;
    if(map.getZoom()<minZoom||!intersects(bounds(map),extent)||!map.terrain){
      request?.abort();request=null;
      if(map.getLayer(layerId))map.removeLayer(layerId);
      return;
    }
    if(request||map.getLayer(layerId))return;
    const current=request=new AbortController();
    try{
      const response=await fetch(new URL('./assets/taipei-road-bridges.json.gz',import.meta.url),{signal:current.signal});
      if(!response.ok)throw Error(String(response.status));
      const spans=await decodeMapJSON(response);
      if(removed||current.signal.aborted)return;
      if(!Array.isArray(spans)||!spans.length||spans.some(s=>!/^road\/way\/\d+$/.test(s?.id)||
        !Array.isArray(s.paintIds)||!s.paintIds.length||!s.paintIds.every(id=>Number.isSafeInteger(id)&&id>0)||
        !Array.isArray(s.box)||s.box.length!==4||!s.box.every(Number.isFinite)))throw Error('Invalid Taipei bridge index');
      map.addLayer(new TaipeiRoadBridges(spans),map.getLayer('survey')?'survey':firstLabel);
    }catch(error){if(!removed&&!current.signal.aborted)console.warn('Taipei road bridges',error.message);}
    finally{if(request===current)request=null;}
  }
  map.on('moveend',update);map.on('terrain',update);
  map.on('remove',()=>{removed=true;request?.abort();map.off('moveend',update);map.off('terrain',update);});
  void update();
}
