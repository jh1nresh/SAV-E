import {cityPlaceLayers} from './city-place-index.js';
import {inFuxing,frontageCamera,bookshopView,shopRowView,bookshopEvidence,bookstoreId} from './fuxing-block.js';
import * as ml from './assets/maplibre-gl.mjs';
import {SurveyLayer,buildingZoom} from './survey-layer.js?v=taipei-frontages-2';
import {addStreetDetail} from './street-detail.js?v=category-badges-1';
import {addMetroPreview} from './metro-preview.js';
import {addPocketCityPaint,readPocketCityAsset} from './pocket-city-atlas.js';
import {addPocketCityWeather} from './pocket-city-weather.js';
import {addCityStreetLoading} from './city-streets.js';
import {loadSongyanNear} from './songyan-detail.js?v=5';

import {addShopSearch} from './city-shop-search.js?v=photo-pins-1';
import {addCity170,dihuaSearch} from './city170.js?v=category-badges-1';
import {addCityShopfronts} from './city-shopfronts.js?v=named-pins-1';
import {CityNature} from './city-nature.js?v=inventory-3';

const $=query=>document.querySelector(query);
const stage=$('#stage');
const preview=new URLSearchParams(location.search);
const terrainRevision=new URL(import.meta.url).search;
const look=preview.get('look')??'hybrid';
const hybrid=look==='hybrid';
const rerun=hybrid&&preview.get('detail')!=='prior';
const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
const taipei=[[121.454,24.954],[121.673,25.218]];
const taiwan=[[119.77,21.84],[122.12,25.36]];
const dihuaCamera={center:[121.509939,25.056432],pitch:43,mobilePitch:41,bearing:70,zoom:21.35,mobileZoom:20.28};
const landmarks={
  '101':{name:'台北 101',center:[121.56481,25.03367]},
  yongchun:{name:'永春',center:[121.57655,25.04069],bearing:12},
  songshan:{name:'松菸',center:[121.56149,25.04350],mobileCenter:[121.56168,25.04349],bearing:-65,mobileBearing:-63,pitch:42,zoom:17.62},
};
const dihuaWalk={points:[[121.5099332,25.056349],[121.509895,25.056689]],people:7};
const dihuaViews=new Map([
  ['dihua',dihuaCamera],
  ['dihua-north',{center:[121.509917,25.056599],pitch:42,mobilePitch:39,bearing:75,zoom:20.91,mobileZoom:19.91}],
  ['dihua-noodles',{center:[121.509848,25.056424],pitch:42,mobilePitch:40,bearing:-75,zoom:21.38,mobileZoom:20.93}],
]);
const illustratedDistricts={'信義區':'xinyi-district','大安區':'daan-district','松山區':'songshan-district','中山區':'zhongshan-district'};
const illustratedGridMinZoom=11.4;
const cityGridMinZoom=9.55;
const streetDataKeys=[...Object.values(illustratedDistricts),'xinyi-link',...Object.keys(landmarks)];
const districtOrder=['中正區','大同區','中山區','松山區','大安區','萬華區','信義區','士林區','北投區','內湖區','南港區','文山區'];
const nativeStatus=$('#progress');
let map, layer, streetDetail, metroState, weather;
let streetDistricts=new Map();
let cityDistricts=[], cityGrids, cityGridLoad;
let atlas170,shopfronts,cityNature;
let preparedGroundReady=false;
function setPreparedGround(ready=preparedGroundReady){
  preparedGroundReady=ready;
  for(const id of ['pocket-city-crossing','pocket-city-lane','pocket-city-skill-paving','pocket-city-paving-joints']){
    if(map.getLayer(id))map.setLayoutProperty(id,'visibility',ready?'none':'visible');
  }
}
let previousFronts=preview.get('fuxing')==='before', quietFronts=false, bookWallReady=false;
let labelOrder=[],applyLocalNames;
function updateFrontageView(){
  if(!map||!atlas170)return;
  const {lng,lat}=map.getCenter();
  const close=showModels&&map.getZoom()>=19&&inFuxing(lng,lat);
  $('#fuxing-controls').hidden=!close;
  applyLocalNames?.(close);
  $('#fuxing-frame').textContent=map.getZoom()>=21?'看整排':'看書店';
  const quiet=close&&!previousFronts&&bookWallReady;
  if(quiet!==quietFronts){
    quietFronts=quiet;
    if(quiet){
      // Ground labels draw before the solid facades and trees, so uncovered points remain visible.
      const layers=map.getStyle().layers;
      labelOrder=layers.flatMap((layer,i)=>{
        const place=['city170-poi-dots','poi_r1'].includes(layer.id);
        const road=layer['source-layer']==='transportation_name'||layer.id==='city170-road-names'||layer.id.endsWith('-road-labels');
        return place||road?[[layer.id,layers[i+1]?.id]]:[];
      });
      for(const [id] of labelOrder)map.moveLayer(id,'survey');
    }else{
      for(const [id,next] of labelOrder.reverse())if(map.getLayer(id))map.moveLayer(id,next&&map.getLayer(next)?next:undefined);
      labelOrder=[];
    }
  }
}
let manualPitch=false, showModels=true, showGrid=false;
let districtsByName=new Map();
let districtShapes=[];
const terrainSource='https://s3.amazonaws.com/elevation-tiles-prod/terrarium/';
const loadImage=async path=>{
  const image=new Image();
  image.src=new URL(path,import.meta.url);
  await image.decode();
  return image;
};
const get=async path=>{
  const response=await fetch(new URL(path,import.meta.url));
  if(!response.ok)throw Error(`${response.status} ${path}`);
  return response.json();
};
const layersForColor = {
  'background':'#efe7d6','park':'#bed0a7','landuse_residential':'#e6e0d2',
  'landcover_wood':'#a7be95','landcover_grass':'#c9d5a8','landcover_wetland':'#b5cbd1',
  'landuse_pitch':'#bdd3b1','landuse_track':'#d5ab98','landuse_cemetery':'#c5ceb3',
  'landuse_hospital':'#edd8d4','landuse_school':'#e9d6b8','water':'#9fc3d4',
  'waterway_river':'#83b2c8','waterway_other':'#97b9cf','building':'#d0c5b1',
  'road_minor':'#fcf6e5','road_secondary_tertiary':'#f4eddb','road_trunk_primary':'#f7efd7',
  'road_motorway':'#e8c991','road_major_rail':'#a49497','road_path_pedestrian':'#ac9e8e',
  'bridge_street':'#f5eedf','bridge_trunk_primary':'#f7efd7','bridge_major_rail':'#9b8d93',
};
const hybridBaseColors={
  background:'#f4ebd7',park:'#acd07c',landuse_residential:'#ede4d0',
  landcover_wood:'#92b379',landcover_grass:'#bfd68f',landcover_wetland:'#a7c29c',
  landuse_pitch:'#a7c67b',landuse_track:'#d9a984',landuse_cemetery:'#c3ce99',
  landuse_hospital:'#ebd5d0',landuse_school:'#ebd0a1',water:'#89c0cc',
  waterway_river:'#73b6c6',waterway_other:'#8ec4ce',building:'#d2c5ad',
  road_minor:'#faf0d8',road_secondary_tertiary:'#f1e4ca',road_trunk_primary:'#f5e8cb',
};
function mapStyle(base,districts) {
  base.name='Savvy Taipei';
  const omit=new Set(['building-3d','natural_earth','road_area_pattern','poi_r20','poi_r7',
    'highway-shield-non-us','highway-shield-us-interstate','road_shield_us']);
  base.layers=base.layers.filter(l=>!omit.has(l.id));
  for(const l of base.layers){
    const color=(hybrid?hybridBaseColors[l.id]:null)??layersForColor[l.id];
    if(color)l.paint={...l.paint,[l.type+'-color']:color};
    if(l.id.startsWith('road_')&&l.id.endsWith('_casing'))l.paint['line-color']='#c5bdb0';
    if(l.id.startsWith('tunnel_')&&l.type==='line')l.paint={...l.paint,'line-opacity':.25};
    if(l.id==='building')l.paint={...l.paint,'fill-opacity':.65};
    if(l.id==='poi_r1')delete l.layout['icon-image'];
    if(l.id==='poi_transit')l.filter=['match',['get','class'],['airport','rail'],true,false];
    if(l.id==='label_city'||l.id==='label_city_capital')l.maxzoom=14.3;
    if(l.type==='symbol'&&l.layout?.['text-field']&&l.source==='openmaptiles'){
      const original=l.layout['text-field'];
      if(!l.id.includes('shield')){
        l.layout['text-field']=['coalesce',['get','name:zh-Hant'],['get','name:zh'],['get','name:nonlatin'],['get','name'],original];
      }
      l.paint={...l.paint,'text-color':'#45564c','text-halo-color':'#f7f2e7'};
    }
  }
  base.sources.dem={
    type:'raster-dem', encoding:'terrarium', tileSize:256, maxzoom:14,
    tiles:[terrainSource+'{z}/{x}/{y}.png'],
    attribution:'<a href="https://registry.opendata.aws/terrain-tiles/" target="_blank" rel="noopener">Mapzen</a>',
  };
  base.sources.relief={...base.sources.dem};
  delete base.sources.relief.attribution;
  base.sources.districts={type:'geojson',data:districts};
  base.sources.plots={type:'geojson',data:empty};
  const waterIndex=base.layers.findIndex(l=>l.id==='water');
  base.layers.splice(waterIndex,0,{
    id:'topography',type:'hillshade',source:'relief',minzoom:6,maxzoom:16,
    paint:{'hillshade-shadow-color':'#52695d','hillshade-highlight-color':'#f5eed8','hillshade-accent-color':'#7f967a','hillshade-exaggeration':.29},
  });
  base.layers.push({
    id:'district-boundaries',type:'line',source:'districts',minzoom:9,maxzoom:14.9,
    paint:{'line-color':'#3e7864','line-opacity':['interpolate',['linear'],['zoom'],9,.61,13.5,.55,14.9,.08],
      'line-dasharray':[2,2],'line-width':['interpolate',['linear'],['zoom'],9,1.25,13,1.6]},
  },{
    id:'pocket-plots',type:'line',source:'plots',minzoom:cityDistricts.length?cityGridMinZoom:illustratedGridMinZoom,
    layout:{visibility:'none'},
    paint:{'line-color':'#3c7164','line-width':1.2,
      'line-opacity':['interpolate',['linear'],['zoom'],9.55,.19,12,.43],'line-dasharray':[2,2]},
  });
  base.terrain={source:'dem',exaggeration:1};
  return base;
}
const empty={type:'FeatureCollection',features:[]};
function message(value) {
  if(nativeStatus.textContent!==value)nativeStatus.textContent=value;
}
const distance=([a,b],[c,d])=>Math.hypot((a-c)*.905,b-d);
function jump(options){
  if(!map)return;
  if(reducedMotion.matches)map.jumpTo(options);
  else map.easeTo({...options,duration:540});
}
function fit(bounds,city){
  if(!map)return;
  manualPitch=false;
  const compact=stage.clientWidth<600;
  map.fitBounds(bounds,{bearing:0,pitch:city?18:0,padding:{left:compact?22:70,right:compact?26:70,top:compact?80:58,bottom:42},
    maxZoom:city?15.1:8.9,duration:reducedMotion.matches?0:720});
}
function locate(record,animate=true){
  const tower=record===landmarks['101'];
  manualPitch=true;
  const compact=stage.clientWidth<600;

  const zoom=record.zoom?(compact?(record.mobileZoom??record.zoom-.35):record.zoom):tower?(compact?15.25:15.81):(compact?17.69:18.22);
  const camera={
    center:compact?(record.mobileCenter??record.center):record.center,
    bearing:(compact?record.mobileBearing:undefined)??record.bearing??map.getBearing(),
    zoom,pitch:tower?39:compact?(record.mobilePitch??47):record.pitch??47,
  };
  if(animate)jump(camera);
  else map.jumpTo(camera);
}
function focus101Street(animate=true){
  if(!map)return;
  manualPitch=true;
  const compact=stage.clientWidth<600;
  const camera={center:compact?[121.56491,25.03355]:[121.56551,25.034],
    bearing:compact?-15:-22,zoom:compact?17.55:17.98,pitch:compact?46:48};
  if(animate)jump(camera);
  else map.jumpTo(camera);
}
function focusCorridor(){
  manualPitch=true;
  map.jumpTo({center:[121.56865,25.03960],bearing:0,pitch:38,zoom:stage.clientWidth<600?15.85:16.77});
}
function togglePitch(){
  manualPitch=true;
  const angle=map.getPitch();
  jump({pitch:angle<23?54:0});
}
function rotate(delta){
  jump({bearing:map.getBearing()+delta});
}
function inside(ring,x,y){
  let result=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const a=ring[i],b=ring[j];
    if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])result=!result;
  }
  return result;
}
function regionAt(){
  if(map.getZoom()<11)return null;
  const {lng,lat}=map.getCenter();
  return districtShapes.find(d=>{
    const [w,s,e,n]=d.bounds;
    return lng>=w&&lng<=e&&lat>=s&&lat<=n
      &&d.polygons.some(r=>inside(r[0],lng,lat)&&!r.slice(1).some(h=>inside(h,lng,lat)));
  })?.name??null;
}
function updateUI(){
  if(!map.getLayer('district-boundaries'))return;
  updateFrontageView();
  const z=map.getZoom(), district=regionAt(), {lng,lat}=map.getCenter();
  $('#apple-places-link').href='./apple.html?lat='+lat.toFixed(6)+'&lng='+lng.toFixed(6);
  $('#dihua-views').hidden=!rerun||preview.get('dihua')==='before'||z<18.7||
    Math.abs(lng-121.50991)>.0008||Math.abs(lat-25.05650)>.0008;
  const city=z>=10&&lng>=taipei[0][0]&&lng<=taipei[1][0]&&lat>=taipei[0][1]&&lat<=taipei[1][1];
  const active=!!district&&showModels&&z>=buildingZoom;
  const zoomed=active&&z>=16.4;
  const label=district??(city?'台北市':'台灣');
  $('#parent').textContent=district?'台北市':city?'台灣':'';
  $('#region').textContent=label;
  const nearby=z>=16&&Object.entries(landmarks).find(([key,item])=>{
    const bounds=streetDistricts.get(key)?.bounds;
    if(!bounds)return distance([lng,lat],item.center)<.0033;
    const [west,south,east,north]=bounds;
    return lng>=west&&lng<=east&&lat>=south&&lat<=north;
  });
  const link=streetDistricts.get('xinyi-link');
  const inLink=link&&inside(link.footprint.coordinates[0],lng,lat);
  const illustrated=hasStreetDistrict(district);
  $('#resolution').textContent=z<10?'全台總覽':zoomed
    ?atlas170?`${nearby?nearby[1].name+' · ':''}170 公尺街區`:(nearby?`${nearby[1].name} · ${nearby[0]!=='101'&&streetDistricts.has(nearby[0])?'220':'200'} 公尺街區`:illustrated||inLink?'街廓 · 220 公尺':'200 公尺 · 插畫立面')
    :active?'2025 LOD1 量體':'地圖總覽';
  $('#pitch').setAttribute('aria-pressed',String(map.getPitch()>=23));
  for(const button of document.querySelectorAll('[data-district]')){
    if(button.dataset.district===district)button.setAttribute('aria-current','location');
    else button.removeAttribute('aria-current');
  }
  $('#mobile-district').value=district??'';
}
let lastGrid='', plotGrid, loadingPlots;
function hasStreetDistrict(name){
  const key=illustratedDistricts[name];
  return streetDistricts.has(key)||cityDistricts.some(district=>district.key===key);
}
function updateGrid(){
  if(atlas170){atlas170.grid(showGrid);return;}
  const source=map.getSource('plots');
  if(!source)return;
  const link=streetDistricts.get('xinyi-link');
  const fullAtlas=cityDistricts.length>0;
  const hasDistrictGrid=fullAtlas||hasStreetDistrict(regionAt());
  const display=showGrid&&map.getZoom()>=(fullAtlas?cityGridMinZoom:hasDistrictGrid?illustratedGridMinZoom:15.5);
  const {lng,lat}=map.getCenter();
  const activeKeys=hasDistrictGrid?Object.values(illustratedDistricts)
    :link&&inside(link.footprint.coordinates[0],lng,lat)?['xinyi-link']:[];
  if(display&&hasDistrictGrid&&cityDistricts.length&&!cityGrids&&!cityGridLoad){
    cityGridLoad=readPocketCityAsset('city-streets/grids').then(data=>{
      cityGrids=data;
      updateGrid();
    }).catch(error=>console.warn(error.message)).finally(()=>{cityGridLoad=null;});
  }
  if(display&&!activeKeys.length&&!plotGrid){
    if(!loadingPlots){
      loadingPlots=get('./data/grid-200.json').then(payload=>{
        plotGrid=payload.plots;
        updateGrid();
      }).catch(error=>console.warn(error.message)).finally(()=>{loadingPlots=null;});
    }
    return;
  }
  const [sw,ne]=map.getBounds().toArray();
  const boundsOf=ring=>{
    const x=ring.map(point=>point[0]),y=ring.map(point=>point[1]);
    return [Math.min(...x),Math.min(...y),Math.max(...x),Math.max(...y)];
  };
  const tiles=display?(activeKeys.length?activeKeys.flatMap(key=>
    (streetDistricts.get(key)?.cells??cityGrids?.[key]??[]).map(({id,bounds,geometry})=>({
      id:`${key}-${id}`,bounds:bounds??boundsOf(geometry.coordinates[0]),geometry,
    }))
  ):plotGrid.map(([id,ring])=>({id,bounds:boundsOf(ring),geometry:{type:'Polygon',coordinates:[ring]}}))).filter(({bounds:b})=>
    b[0]<=ne[0]&&b[2]>=sw[0]&&b[1]<=ne[1]&&b[3]>=sw[1]):[];
  const fingerprint=tiles.map(({id})=>id).join('|');
  if(lastGrid===fingerprint)return;
  lastGrid=fingerprint;
  source.setData({type:'FeatureCollection',features:tiles.map(({id,geometry})=>({
    type:'Feature',properties:{id},geometry,
  }))});
}
function setModels(input){
  showModels=input.checked;
  $('#models').checked=$('#mobile-models').checked=showModels;
  layer?.setEnabled(showModels);
  shopfronts?.setEnabled(showModels);
  if(map?.getLayer('atlas-shadows'))map.setLayoutProperty('atlas-shadows','visibility',showModels?'visible':'none');
  updateUI();
}
function setGrid(input){
  showGrid=input.checked;
  $('#grid').checked=$('#mobile-grid').checked=showGrid;
  if(map?.getLayer('pocket-plots')){
    map.setLayoutProperty('pocket-plots','visibility',showGrid?'visible':'none');
    updateGrid();
  }
}
function formatDistricts(counts){
  districtsByName=new Map(counts.map(row=>[row.name,row]));
  for(const name of districtOrder){
    const district=districtsByName.get(name);
    if(!district)continue;
    const button=document.createElement('button');button.type='button';button.dataset.district=name;
    button.textContent=name;button.addEventListener('click',()=>focusDistrict(name));$('#districts').append(button);
    const item=document.createElement('option');item.value=name;item.textContent=name;$('#mobile-district').append(item);
  }
}
function focusDistrict(name){
  const d=districtsByName.get(name);
  if(!d){fit(taipei,true);return;}
  const [west,south,east,north]=d.bounds;
  // Zhongshan wraps around the airport, so its bounding-box midpoint is in Songshan.
  const left=name==='中山區'?Math.min(west,2*121.5355-east):west;
  fit([[left,south],[east,north]],true);
}
for(const selector of ['#models','#mobile-models']) $(selector).addEventListener('change',event=>setModels(event.target));
for(const selector of ['#grid','#mobile-grid']) $(selector).addEventListener('change',event=>setGrid(event.target));
$('#mobile-district').addEventListener('change',event=>{
  focusDistrict(event.target.value);
  $('.mobile').open=false;
});
for(const button of document.querySelectorAll('[data-landmark]'))
  button.addEventListener('click',()=>{if(map){locate(landmarks[button.dataset.landmark]);$('.mobile').open=false;}});
$('#rotate-left').addEventListener('click',()=>{if(map)rotate(-30)});
$('#rotate-right').addEventListener('click',()=>{if(map)rotate(30)});
$('#pitch').addEventListener('click',()=>{if(map)togglePitch()});
for(const button of document.querySelectorAll('[data-street-101]'))
  button.addEventListener('click',()=>{focus101Street();$('.mobile').open=false;});
$('#taiwan').addEventListener('click',()=>fit(taiwan,false));
$('#taipei').addEventListener('click',()=>fit(taipei,true));

message('載入地圖…');
try{
  const [base,districts,index,landmark,sharedMask,atlas,shadows,metro,walkingDetails,skillAtlas,cityIndex,...loadedStreets]=await Promise.all([
    get('./assets/base-style.json'),get('./data/districts.geojson'),get('./data/survey-index.json'),
    get('./data/landmark-101.json').catch(()=>null),
    loadImage(hybrid?'./data/street-hybrid-material-mask.png':'./data/street-atlas-material-mask.png').catch(()=>null),
    get('./data/street-atlas.json').catch(()=>null),
    hybrid?get('./data/street-shadows.json').catch(()=>null):null,
    get('./data/metro-preview.json').catch(()=>null),
    get('./data/pocket-city-walks.json').catch(()=>null),
    rerun?readPocketCityAsset('street-pocket-city')
      .then(data=>data?.summary&&data?.districts?data:null).catch(()=>null):null,
    rerun?get(`./data/city-streets/index.json${terrainRevision}`).catch(()=>null):null,
    ...streetDataKeys.filter(key=>!rerun||!key.endsWith('-district')).map(key=>get(`./data/street-${key}.json`)
      .then(data=>({key,data})).catch(error=>{console.warn(error.message);return null;})),
  ]);
  formatDistricts(index.counts);
  cityDistricts=cityIndex?.districts??[];
  for(const {name,key} of cityDistricts)illustratedDistricts[name]=key;
  const [cityMask,cityLandmarkModels]=cityIndex?.materialBounds?await Promise.all([
    loadImage('./data/city170-material.png').catch(()=>loadImage('./data/city-streets/material-mask.png').catch(()=>null)),
    get('./data/city-streets/landmarks.json').catch(()=>[]),
  ]):[null,[]];
  for(const {geometry,properties} of districts.features){
    const {name}=properties, district=districtsByName.get(name);
    const polygons=geometry.type==='MultiPolygon'?geometry.coordinates:[geometry.coordinates];
    districtShapes.push({name,bounds:district.bounds,polygons});
  }
  const localTerrain=new Map([[terrainSource+'14/13724/7014.png',
    new URL('./data/terrain/14-13724-7014.png',import.meta.url).href]]);
  for(const tile of atlas?.tiles??[]){
    localTerrain.set(`${terrainSource}14/${tile}.png`,
      new URL(`./data/terrain/street-atlas/14-${tile.replace('/','-')}.png`,import.meta.url).href);
  }
  for(const tile of cityIndex?.terrainTiles??[]){
    localTerrain.set(`${terrainSource}14/${tile}.png`,
      new URL(`./data/city-streets/terrain/14-${tile.replace('/','-')}.png${terrainRevision}`,import.meta.url).href);
  }
  map=new ml.Map({
    container:'map',style:mapStyle(base,districts),center:[121.547,25.083],zoom:11.4,bearing:0,pitch:18,
    minZoom:6,maxZoom:21.6,maxPitch:65,maxBounds:[[116.5,19.7],[124.5,27.5]],
    transformRequest:url=>({url:localTerrain.get(url)??url}),
    attributionControl:false,renderWorldCopies:false,localIdeographFontFamily:'sans-serif',
    canvasContextAttributes:{antialias:true},
  });
  map.addControl(new ml.NavigationControl({visualizePitch:true}),'top-right');
  map.addControl(new ml.ScaleControl({maxWidth:100,unit:'metric'}),'bottom-left');
  map.addControl(new ml.AttributionControl({compact:true,customAttribution:[
    '<a href="https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143" target="_blank" rel="noopener">臺北市區界</a>',
    '<a href="https://data.taipei/dataset/detail?id=c013d9ec-a550-46bd-ac60-45f085930706" target="_blank" rel="noopener">臺北市市場處</a>',
    '<a href="https://data.taipei/dataset/detail?id=59579c19-a561-4564-8c0f-545bfb32c0f6" target="_blank" rel="noopener">臺北市衛生局</a>',
    '<a href="https://data.gov.tw/dataset/128274" target="_blank" rel="noopener">臺北市公園處樹籍</a>',
    '<a href="https://april-zhu.com/pocketnature" target="_blank" rel="noopener">Pocket Nature</a>',
    '<a href="https://historygis.udd.gov.taipei/arcgis/rest/services/Hosted/LOD1_2025/SceneServer/layers/0?f=pjson" target="_blank" rel="noopener">臺北市都發局 2025</a>',
  ]}),'bottom-right');
  map.on('error',event=>{
    if(!map.isStyleLoaded())message('底圖暫時無法載入，請重新整理。');
    console.warn(event.error?.message??'Map data error');
  });
  await map.once('load');
  const streets=loadedStreets.filter(Boolean);
  const priorGround=new Map();
  for(const {key,data} of streets){
    const additions=skillAtlas?.districts[key];
    if(additions){
      data.paths.unshift(...additions.paths);
      data.objects.push(...additions.objects);
    }
    if(walkingDetails?.[key]){
      if(additions)priorGround.set(key,data.ground.features.length);
      else data.paths.push(...walkingDetails[key].paths);
      data.ground.features.push(...walkingDetails[key].ground);
    }
  }
  streetDistricts=new Map(streets.map(({key,data})=>[key,data]));
  const streetCenters=['yongchun','songshan'].map(key=>{
    const detail=streets.find(street=>street.key===key);
    return detail?ml.MercatorCoordinate.fromLngLat(detail.data.origin):null;
  });
  const linked=streetDistricts.get('xinyi-link');
  const linkScene=linked?{anchor:ml.MercatorCoordinate.fromLngLat(linked.origin),runs:linked.runs}:null;
  const districtMaterial=cityMask?{image:cityMask,bounds:cityIndex.materialBounds}
    :atlas&&sharedMask?{image:sharedMask,bounds:atlas.materialBounds}:null;
  const cityLandmarks=cityMask?cityLandmarkModels:[];
  layer=new SurveyLayer(index,message,landmark,look==='anatomy'||hybrid,streetCenters,linkScene,districtMaterial,hybrid,cityLandmarks);
  const firstLabel=map.getStyle().layers.find(l=>l.type==='symbol')?.id;
  map.addLayer(layer,firstLabel);
  map.getCanvas().setAttribute('aria-label','台北市地圖，可拖曳、縮放及旋轉');
  if(streets.length||cityDistricts.length)streetDetail=addStreetDetail(map,ml,streets,firstLabel,look==='anatomy',hybrid,shadows,rerun);
  if(rerun && streetDetail){
    cityNature=new CityNature();
    map.addLayer(cityNature,firstLabel);
    const localLife=(records,visiblePacks=[])=>{
      if(preview.get('dihua')!=='before'&&visiblePacks.includes('p221_2038'))
        records=[{objects:{},paths:{'dihua-arcade':dihuaWalk}},...records];
      streetDetail.setLocalLife(records);
    };
    const openMapLabel=place=>{
      if(!place.placeId || !shopfronts?.openNamedPlace(place.placeId))streetDetail.openMappedPlace(place);
    };
    atlas170=addCity170(map,firstLabel,openMapLabel,setPreparedGround,streetDetail.setMappedStores,localLife,streetDetail.authoredRoads,streetDetail.hasFocalPin,preview.get('dihua')!=='before'?layer:null,cityNature,ids=>shopfronts?.setPacks(ids));
    const focusFront=(card,x,y,angle)=>{
      if(previousFronts||!inFuxing(x,y))return false;
      locate(frontageCamera(x,y,angle));
      streetDetail.openMappedPlace({...card,...(card.id===bookstoreId?bookshopEvidence:{}),point:[x,y]});
      return true;
    };
    addShopSearch(map,locate,dihuaSearch,streetDetail.openMappedPlace,row=>{
      const [name,district,street,x,y,angle,id]=row;
      const osm=id.match(/^poi\/(node|way|relation)\/(\d+)$/);
      return focusFront({id,name,kind:'shopfront',categoryLabel:'臨街店面',detail:[district,street].filter(Boolean).join(' · '),
        source:osm?'OpenStreetMap':undefined,url:osm?'https://www.openstreetmap.org/'+osm[1]+'/'+osm[2]:undefined},x,y,angle);
    });
    shopfronts=addCityShopfronts(map,(card,row)=>{
      if(!focusFront(card,...row.center,row.angle))streetDetail.openMappedPlace({...card,point:row.center});
    },firstLabel,ids=>{
      const ready=ids.includes(bookstoreId);
      if(ready!==bookWallReady){bookWallReady=ready;requestAnimationFrame(updateFrontageView);}
    },()=>layer.visibleWallTiles,atlas170.openNearbyPlace);
    $('#fuxing-frame').addEventListener('click',()=>{
      if(!$('#place-card').hidden)$('#place-close').click();
      locate(map.getZoom()>=21?shopRowView:bookshopView);
    });
    const compare=$('#fuxing-compare');
    function applyComparison(){
      compare.setAttribute('aria-pressed',String(previousFronts));
      shopfronts.setFuxing(!previousFronts);
      updateFrontageView();
    }
    compare.addEventListener('click',()=>{previousFronts=!previousFronts;applyComparison();});
    applyComparison();
    for(const button of document.querySelectorAll('[data-fuxing]')){
      button.addEventListener('click',()=>{locate(bookshopView);$('.mobile').open=false;});
    }
  }
  const orderSongyanSurface=cityIndex&&preview.get('songyan')!=='before'
    ?loadSongyanNear(map,asset=>layer.setSongyan(asset)):null;
  if(cityIndex && preview.get('dihua')!=='before'){
    get('./data/city-streets/dihua-fronts.json?v=shop-names').then(asset=>{layer.dihua=asset;map.triggerRepaint();}).catch(e=>console.warn('迪化街街屋',e));
  }
  if(rerun&&streetDetail)weather=addPocketCityWeather(map,stage,streetDetail.setRain,preview.get('weather'));
  if(skillAtlas)addPocketCityPaint(map,()=>{
    // The legacy tiles may arrive after the cell-prepared street surface.
    setPreparedGround();
    for(const {key,data} of streets){
      if(!priorGround.has(key))continue;
      data.ground.features.length=priorGround.get(key);
      map.getSource(`street-${key}-ground`).setData(data.ground);
    }
    weather?.refresh();
    orderSongyanSurface?.();
  });
  setModels($('#models'));
  if(metro)metroState=addMetroPreview(map,ml.Marker,metro,preview.get('metro')==='1');
  if(streetDistricts.has('101')){
    for(const button of document.querySelectorAll('[data-street-101]'))button.hidden=false;
  }
  for(const record of cityLandmarks){
    const makeButton=()=>{
      const button=document.createElement('button');
      button.type='button';
      button.textContent=record.name;
      button.addEventListener('click',()=>{
        locate({...record,zoom:17.15});
        $('.mobile').open=false;
      });
      return button;
    };
    $('.landmarks').append(makeButton());
    $('.mobile-controls label[for="mobile-district"]').before(makeButton());
  }
  const nameInputs=[...document.querySelectorAll('[data-place-names]')];
  let globalNames=preview.get('names')!=='off',localNames=globalNames,appliedNames;
  applyLocalNames=inside=>{
    const visible=inside?localNames:globalNames;
    if(visible===appliedNames)return;
    appliedNames=visible;
    for(const id of [...cityPlaceLayers,'city170-shop-names','city170-poi-labels','city170-poi-dots','poi_r1']){
      if(map.getLayer(id))map.setLayoutProperty(id,'visibility',visible?'visible':'none');
    }
    shopfronts?.setNames(visible);
    $('#fuxing-names').setAttribute('aria-pressed',String(visible));
    document.body.classList.toggle('without-place-names',!visible);
    nameInputs.forEach(input=>input.checked=visible);
  };
  nameInputs.forEach(input=>input.addEventListener('change',()=>{
    globalNames=localNames=input.checked;applyLocalNames(!$('#fuxing-controls').hidden);
  }));
  $('#fuxing-names').addEventListener('click',()=>{localNames=!localNames;applyLocalNames(true);});
  applyLocalNames(false);
  for(const button of document.querySelectorAll('[data-dihua]')){
    button.addEventListener('click',()=>{locate(dihuaViews.get(button.dataset.dihua||'dihua'));$('.mobile').open=false;});
  }
  const street=preview.get('street');
  const cityLandmark=cityLandmarks.find(row=>row.id===preview.get('landmark'));
  const campusView=preview.get('campus');
  const coordinate=(preview.get('view')??'').split(',').map(Number);
  const facing=Number(preview.get('bearing')??-17);
  if(coordinate.length===3 && coordinate.every(Number.isFinite) &&
      coordinate[0]>=taipei[0][0] && coordinate[0]<=taipei[1][0] &&
      coordinate[1]>=taipei[0][1] && coordinate[1]<=taipei[1][1]){
    locate({center:coordinate.slice(0,2),zoom:Math.max(10,Math.min(21.6,coordinate[2])),mobileZoom:Math.max(10,Math.min(21.6,coordinate[2]-.35)),pitch:42,bearing:Number.isFinite(facing)?facing:-17},false);
  }else if(street==='fuxing')locate(bookshopView,false);
  else if(street==='fuxing-row')locate(shopRowView,false);
  else if(dihuaViews.has(street))locate(dihuaViews.get(street),false);
  else if(campusView==='ntu')locate({center:[121.53555,25.01657],zoom:16.75,pitch:38,bearing:-18},false);
  else if(cityLandmark)locate({...cityLandmark,zoom:17.15},false);
  else if(streetDistricts.has(street)||Object.values(illustratedDistricts).includes(street)||cityDistricts.some(district=>district.key===street)){
    const district=Object.keys(illustratedDistricts).find(name=>illustratedDistricts[name]===street);
    if(district)focusDistrict(district);
    else if(street==='xinyi-link')focusCorridor();
    else if(street==='101')focus101Street(false);
    else locate(landmarks[street],false);
  }else fit(taipei,true);
  if(cityDistricts.length&&!atlas170)addCityStreetLoading(map,cityDistricts,loaded=>{
    streetDetail.addStreets(loaded);
    for(const {key,data} of loaded)streetDistricts.set(key,data);
    weather?.refresh();
    updateUI();
  });
  message('');
  map.on('moveend',()=>{
    updateGrid();updateUI();
  });
  map.on('idle',updateUI);
  map.on('zoomend',()=>{
    if(!manualPitch){
      const z=map.getZoom();
      const goal=z>=16.35?50:z>=15.1?43:z<buildingZoom?18:34;
      if(Math.abs(goal-map.getPitch())>3)jump({pitch:goal});
    }
  });
  map.on('pitchstart',event=>{if(event.originalEvent)manualPitch=true});
  map.on('resize',()=>{updateGrid();updateUI()});
  updateUI();
  window.savvyTaipei={
    map,
    index,
    state:()=>({
      center:map.getCenter().toArray(),zoom:map.getZoom(),bearing:map.getBearing(),
      pitch:map.getPitch(),district:regionAt(),base:map.isSourceLoaded('openmaptiles'),
      rendered:map.queryRenderedFeatures().filter(f=>['transportation','water','building'].includes(f.sourceLayer)).length,
      detail:layer.diagnostics,street:streetDetail?.state(),metro:metroState?.(),weather:weather?.state(),
      pocketCity:skillAtlas?.summary??null,
      atlas170:atlas170?.state(),shopfronts:shopfronts?.state(),inventoryTreesDrawn:cityNature?.drawn,
      cityAtlas:atlas170?atlas170.state().coverage:cityIndex?.cityCoverage??null,
    }),
  };
}catch(error){
  message('預覽無法載入，請重新整理。');
  console.error(error);
}
