import {MercatorCoordinate,LngLat} from './assets/maplibre-gl.mjs';
import {program} from './survey-layer.js';
import {CityNature} from './city-nature.js';
import {StreetPeople} from './street-people.js';
import {placePinStyle} from './place-pins.js';
import {geographicPoint,geographicScene} from './cities/geography.js?v=continuous-5';

const vertex=`#version 300 es
layout(location=0) in vec3 p;
layout(location=1) in vec4 colour;
uniform mat4 matrix;
uniform float ground;
out vec4 tint;
void main(){gl_Position=matrix*vec4(p.xy,p.z+ground,1.);tint=colour;}`;
const fragment=`#version 300 es
precision mediump float;
in vec4 tint;
out vec4 pixel;
void main(){pixel=tint;}`;
const collection=features=>({type:'FeatureCollection',features});
const spans=(a,b)=>a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
const localURL=path=>new URL('./cities/'+path,import.meta.url);
async function read(path,signal,binary=false){
  const res=await fetch(localURL(path),{signal});
  if(!res.ok)throw Error(path+' HTTP '+res.status);
  return binary?res.arrayBuffer():res.json();
}

// Apply both matrices in double precision before the final conversion to WebGL floats.
function transform(out,m,meta){
  const base=MercatorCoordinate.fromLngLat([meta.lon,meta.lat]);
  const rad=meta.rotation*Math.PI/180,c=Math.cos(rad),s=Math.sin(rad);
  const cosLat=Math.cos(meta.lat*Math.PI/180);
  const east=1/(360*111320*cosLat),north=1/(360*110574*cosLat),up=base.meterInMercatorCoordinateUnits();
  for(let i=0;i<4;i++){
    out[i]=m[i]*c*east-m[i+4]*s*north;
    out[4+i]=-m[i]*s*east-m[i+4]*c*north;
    out[8+i]=m[8+i]*up;
    out[12+i]=m[i]*base.x+m[4+i]*base.y+m[12+i];
  }
}
class LandmarkLayer{
  id='city-atlas-buildings';
  type='custom';
  renderingMode='3d';
  meshes=new Map();
  onAdd(map,gl){
    this.map=map;this.gl=gl;
    this.shader=program(gl,vertex,fragment);
    this.matrix=gl.getUniformLocation(this.shader,'matrix');
    this.ground=gl.getUniformLocation(this.shader,'ground');
    this.frame=new Float32Array(16);
  }
  put(id,meta,parts,bytes){
    const gl=this.gl,vao=gl.createVertexArray(),buffer=gl.createBuffer();
    gl.bindVertexArray(vao);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,bytes,gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,16,0);
    gl.enableVertexAttribArray(1);gl.vertexAttribPointer(1,4,gl.UNSIGNED_BYTE,true,16,12);
    gl.bindVertexArray(null);
    const groups=parts.map(p=>({...p,coordinate:LngLat.convert(geographicPoint(meta,p.at))}));
    this.meshes.set(id,{vao,buffer,groups,meta});
    this.map.triggerRepaint();
  }
  drop(id){
    const item=this.meshes.get(id);
    if(!item)return;
    this.gl.deleteVertexArray(item.vao);this.gl.deleteBuffer(item.buffer);this.meshes.delete(id);
  }
  render(gl,opts){
    if(!this.meshes.size||this.map.getZoom()<14)return;
    gl.useProgram(this.shader);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);
    gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
    for(const mesh of this.meshes.values()){
      transform(this.frame,opts.defaultProjectionData.mainMatrix,mesh.meta);
      gl.uniformMatrix4fv(this.matrix,false,this.frame);gl.bindVertexArray(mesh.vao);
      for(const group of mesh.groups){
        const z=this.map.terrain?.getDrawnElevationForLngLat(group.coordinate);
        gl.uniform1f(this.ground,Number.isFinite(z)?z:0);
        gl.drawArrays(gl.TRIANGLES,group.first,group.count);
      }
    }
    gl.bindVertexArray(null);
  }
  onRemove(){for(const id of this.meshes.keys())this.drop(id);this.gl.deleteProgram(this.shader);}
}
export async function addCityAtlas(map,before,open,onChange){
  const rows=await read('catalog.json'),mesh=new LandmarkLayer(),trees=new CityNature();
  trees.id='city-atlas-trees';
  map.addSource('city-atlas-locations',{type:'geojson',data:collection(rows.map(r=>({
    type:'Feature',properties:{id:r.id,category:'museum',name:r.landmark.split(/[、與]/)[0]},geometry:{type:'Point',coordinates:r.center}})))});
  map.addLayer({id:'city-atlas-locators',type:'symbol',source:'city-atlas-locations',minzoom:6.4,maxzoom:16.8,...placePinStyle(map)});
  map.on('click','city-atlas-locators',e=>{
    const point=e.features?.[0]?.geometry.coordinates;
    if(point)map.easeTo({center:point,zoom:17.95,pitch:49,duration:matchMedia('(prefers-reduced-motion: reduce)').matches?0:480});
  });
  const loaded=new Map(),pending=new Map(),errors=new Map();
  let rain=0;
  map.addSource('city-atlas-ground',{type:'geojson',data:collection([])});
  const base={source:'city-atlas-ground',minzoom:14};
  map.addLayer({...base,id:'city-atlas-pavement',type:'fill',filter:['==',['geometry-type'],'Polygon'],
    paint:{'fill-color':['match',['get','kind'],'lawn','#a8bb83','sand','#e9d69c','water','#89c0cc','roads','#f1e4ca','walk','#e7d9bd','#ddc6aa'],'fill-opacity':['match',['get','kind'],'water',0,'roads',.36,'lawn',.42,.74]}},before);
  map.addLayer(mesh,before);map.addLayer(trees,before);
  map.addLayer({...base,id:'city-atlas-road-names',type:'symbol',minzoom:17,filter:['==',['get','kind'],'street'],
    layout:{'symbol-placement':'line','text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':12},
    paint:{'text-color':'#685b4d','text-halo-color':'#fcf4e3','text-halo-width':1.5}});
  const pinStyle=placePinStyle(map);
  for(const [id,minzoom,rank] of [['city-atlas-places',18.65,2],['city-atlas-pins',16.8,0]]){
    map.addLayer({...base,id,minzoom,type:'symbol',filter:['all',['==',['get','kind'],'pin'],['==',['get','rank'],rank]],...pinStyle});
  }
  map.on('click',e=>{
    const hit=map.queryRenderedFeatures(e.point,{layers:['city-atlas-pins','city-atlas-places']})[0];
    if(hit)open({...hit.properties,point:hit.geometry.coordinates});
  });
  const authoredBounds={type:'MultiPolygon',coordinates:rows.map(({bounds:[w,s,e,n]})=>
    [[[w,s],[e,s],[e,n],[w,n],[w,s]]])};
  for(const id of ['poi_r1','poi_transit'])if(map.getLayer(id)){
    const outside=['!', ['all',['>=',['zoom'],16.8],['within',authoredBounds]]];
    map.setFilter(id,['all',map.getFilter(id)??true,outside]);
  }
  function refresh(){
    map.getSource(base.source).setData(collection([...loaded.values()].flatMap(s=>s.features)));
    trees.setRows([...loaded.values()].flatMap(s=>s.trees));
    onChange();
  }
  function update(){
    const b=map.getBounds(),bounds=[b.getWest(),b.getSouth(),b.getEast(),b.getNorth()];
    const wanted=new Set(rows.filter(row=>map.getZoom()>=14&&spans(row.bounds,bounds)).map(row=>row.id));
    let changed=false;
    for(const [id,a] of pending)if(!wanted.has(id)){a.abort();pending.delete(id);}
    for(const [id,s] of loaded)if(!wanted.has(id)){
      if(s.people)map.removeLayer(s.people.id);
      mesh.drop(id);loaded.delete(id);changed=true;
    }
    if(changed)refresh();
    for(const id of wanted){
      if(loaded.has(id)||pending.has(id)||(errors.get(id)??0)>Date.now()-5000)continue;
      const task=new AbortController();pending.set(id,task);
      Promise.all([read(id+'/scene.json',task.signal),read(id+'/map-mesh.json',task.signal),read(id+'/map-mesh.bin',task.signal,true)]).then(([scene,index,bytes])=>{
        if(pending.get(id)!==task)return;
        const row=rows.find(r=>r.id===id),xy=p=>geographicPoint(scene.meta,p);
        const paths=scene.routes.filter(p=>p.kind==='ped'&&p.p.length>=2).slice(0,18).map(p=>({points:p.p.map(xy),people:2}));
        const people=paths.length?new StreetPeople('atlas-'+id,row.center,paths,16.65,true):null;
        const plants=scene.trees.map(([x,y,i])=>[...xy([x,y]),5.5,/palm/i.test(scene.species[i])?'palm':'broad']);
        mesh.put(id,scene.meta,index.parts,bytes);
        if(people){people.umbrellaShare=rain;map.addLayer(people,before);}
        loaded.set(id,{features:geographicScene(scene,row.landmarkIds,row.landmarkSites,row.landmarkPlaceIds),trees:plants,people});
        errors.delete(id);refresh();
      }).catch(e=>{if(!task.signal.aborted){errors.set(id,Date.now());console.warn('Pocket City',id,e);onChange();}})
        .finally(()=>{if(pending.get(id)===task)pending.delete(id);});
    }
  }
  map.on('moveend',update);map.on('remove',()=>{for(const task of pending.values())task.abort();});update();
  return {rows,setRain(share){rain=share;for(const s of loaded.values())if(s.people)s.people.umbrellaShare=share;},
    at(lng,lat){return rows.find(({bounds:[w,s,e,n]})=>lng>=w-.001&&lng<=e+.001&&lat>=s-.001&&lat<=n+.001);},
    ready:id=>loaded.has(id),failed:id=>errors.has(id),retry(id){errors.delete(id);update();},state:()=>({loaded:[...loaded.keys()],pending:[...pending.keys()],failed:[...errors.keys()]})};
}
