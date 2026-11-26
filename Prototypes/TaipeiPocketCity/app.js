import {taipeiDome,addDomeApron} from './taipei-dome.js';
import {connectIOSMap} from './ios-map.js?v=mall-1';
import {addOfficialFloorGuide} from './taipei101-floor-guide.js';
import {addTaipei101Indoor} from './taipei101-indoor.js?v=original-ink-2';
import {loadNativeExploreVenues} from './savvy-place-sources.js';
import {installTaiwanRelief,taiwanLocalDEM} from './taiwan-relief.js?v=alpine-1';
import {makeTaiwanCoverage,readTaiwanJSON} from './taiwan-coverage.js?v=streets-2';
import {addTaiwanPlaces,searchTaiwanEntries} from './taiwan-places.js?v=alpine-1';
import {addTaipeiRiverArt} from './taipei-river-art.js?v=waterfront-4';
import {marketStallLife} from './taipei-market-stalls.js';
import {addTaiwanScenery,yushanView} from './taiwan-scenery.js?v=alpine-1';
import {addTaiwanCells} from './taiwan-cells.js?v=city-colour-3';
import {globeCamera,returnToGlobe} from './world-camera.js?v=globe-1';
import {addCityContext} from './city-context.js?v=city-colour-3';
import {plotOverlaps} from './authored-footprint.js';
import {addCityAtlas} from './city-atlas-layer.js?v=city-colour-3';
import {metroExitDataset} from './taipei-metro-exits.js';
import {cityPlaceLayers} from './city-place-index.js?v=friendly-frontages-1';
import {inFuxing,bookshopView,shopRowView,bookshopEvidence,bookstoreId} from './fuxing-block.js?v=frontage-views-1';
import * as ml from './assets/maplibre-gl.mjs';
import {SurveyLayer,buildingZoom} from './survey-layer.js?v=xinyi-connected-1';
import {sunYatSenHall} from './sun-yat-sen-hall.js';
import {songyanFactory} from './taipei-songyan-factory.js';
import {esliteSongyan} from './taipei-eslite-songyan.js';
import {addStreetDetail} from './street-detail.js?v=taipei-post-boxes-1';
import {addMetroPreview} from './metro-preview.js?v=metro-label-2';
import {streetObjects101} from './taipei101-single-furniture.js';
import {add101Ground,planting101,walks101} from './taipei101-single-ground.js';
import {addPocketCityPaint,readPocketCityAsset} from './pocket-city-atlas.js';
import {addPocketCityWeather} from './pocket-city-weather.js';
import {addCityStreetLoading} from './city-streets.js';
import {loadSongyanNear} from './songyan-detail.js?v=campus-1';

import {addShopSearch} from './city-shop-search.js?v=friendly-frontages-1';
import {addCity170,dihuaSearch} from './city170.js?v=songshan-streets-1';
import {addCityShopfronts} from './city-shopfronts.js?v=songshan-streets-1';
import {CityNature} from './city-nature.js?v=canopies-2';
import {loadTreeCanopies} from './taipei-tree-canopies.js';

const $=query=>document.querySelector(query);
const stage=$('#stage');
const iosChannel=window.webkit?.messageHandlers?.pocketMap;
if(iosChannel) document.documentElement.classList.add('ios-map');
const preview=new URLSearchParams(location.search);
const bundledTiles=preview.get('tiles')==='bundled';
const appChrome=Boolean(iosChannel&&bundledTiles);
const reducedLoad=appChrome&&preview.get('renderer')==='light';
if(appChrome)document.documentElement.classList.add('ios-app-map');
const lanternCamera={center:[121.84363,25.10852],zoom:20.25,mobileZoom:19.8,pitch:58,mobilePitch:56,bearing:138};
let lanternView=preview.get('street')==='amei-lanterns';
const terrainRevision=new URL(import.meta.url).search;
const look=preview.get('look')??'hybrid';
const hybrid=look==='hybrid';
const rerun=hybrid&&preview.get('detail')!=='prior';
const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
const taipei=[[121.454,24.954],[121.673,25.218]];
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
const nativeStatus=$('#progress');
let map, layer, streetDetail, metroState, weather, indoor101;
let streetDistricts=new Map();
let cityDistricts=[], cityGrids, cityGridLoad;
let atlas170,shopfronts,cityNature,worldAtlas,taiwanCoverage,taiwanCells,taiwanScenery;
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
        const place=['city170-poi-dots','city-atlas-pins','city-atlas-places','city-atlas-context-places','tw-public-places','city-atlas-locators','world-cities','world-city-dots','poi_r1'].includes(layer.id);
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
  base.name='Savvy Pocket City';
  base.projection={type:'globe'};
  base.sky={'sky-color':'#152532','horizon-color':'#b7d9d7','fog-color':'transparent',
    'atmosphere-blend':['interpolate',['linear'],['zoom'],0,.62,5,.4,10,0]};
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
    // At globe scale the surface near the horizon has little room for text.
    if(['water_name_point_label','water_name_line_label','label_country_3','label_city_capital','label_city'].includes(l.id)){
      l.minzoom=Math.max(4,l.minzoom??0);
    }
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
function worldOverview(){
  if(!map)return;
  lanternView=false;
  manualPitch=false;
  const url=new URL(location.href);
  for(const key of ['city','street','view','nature','campus','landmark','bearing','pitch'])url.searchParams.delete(key);
  history.replaceState(null,'',url);
  returnToGlobe(map,globeCamera(stage.clientWidth,stage.clientHeight),reducedMotion.matches);
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
  // Match the original oblique view: the camera looks northwest at the east and south facades.
  const scale=Math.min(stage.clientHeight/810,stage.clientWidth/430);
  const zoom=Math.max(buildingZoom,Math.min(16.65,16.36+Math.log2(Math.max(.1,scale))));
  const camera={center:[121.56263,25.03525],bearing:-54,zoom,pitch:54};
  const originalFov=map.getVerticalFieldOfView();
  map.setVerticalFieldOfView(18);
  const restoreLens=()=>{
    const p=map.getCenter();
    if(map.getZoom()>14.4&&Math.abs(p.lng-121.56481)<.009&&Math.abs(p.lat-25.03367)<.008)return;
    map.off('moveend',restoreLens);
    map.setVerticalFieldOfView(originalFov);
  };
  if(animate)jump(camera);
  else map.jumpTo(camera);
  map.on('moveend',restoreLens);
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
  return districtAt(lng,lat);
}
function districtAt(lng,lat){
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
  stage.classList.toggle('street-scale',z>=14);
  if(metroState)$('#metro-toggle').hidden=!city&&$('#metro-toggle').getAttribute('aria-pressed')!=='true';
  const active=!!district&&showModels&&z>=buildingZoom;
  const zoomed=active&&z>=16.4;
  const patch=z>=10&&worldAtlas?.at(lng,lat);
  const inShuqi=patch?.id==='jiufen-shuqi'&&z>=17;
  const lanternButton=$('#shuqi-view');
  lanternButton.hidden=!inShuqi;
  lanternButton.textContent=lanternView?'看整段石階':'看茶樓燈火';
  worldAtlas?.setDusk(Boolean(lanternView&&inShuqi));
  const inTaiwan=lng>=118&&lng<=122.2&&lat>=21.7&&lat<=26.5;
  const town=z>=8?taiwanCoverage?.at(lng,lat):null;
  const label=patch?.name??district??(town?(z>=10?town.name:town.county):city?'台北市':z>=5&&z<8&&inTaiwan?'台灣':'地球');
  $('.geography').hidden=z>4&&label==='地球';
  const retry=$('#retry-landmark');
  retry.hidden=!patch||!worldAtlas.failed(patch.id);
  if(patch)retry.dataset.city=patch.id;
  $('#parent').textContent=patch?(patch.area===label?'':patch.area??''):district?'台北市':town?(z>=10?town.county:'台灣'):city?'台灣':'';
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
  $('#resolution').textContent=patch&&z>=15?(worldAtlas.failed(patch.id)?'街區載入失敗':worldAtlas.ready(patch.id)?patch.landmark:'載入街區…'):z<10?'':zoomed
    ?atlas170?`${nearby?nearby[1].name+' · ':''}170 公尺街區`:(nearby?`${nearby[1].name} · ${nearby[0]!=='101'&&streetDistricts.has(nearby[0])?'220':'200'} 公尺街區`:illustrated||inLink?'街廓 · 220 公尺':'200 公尺 · 插畫立面')
    :active?'2025 LOD1 量體':town?'':'地圖總覽';
  $('#pitch').setAttribute('aria-pressed',String(map.getPitch()>=23));
}
let lastGrid='', plotGrid, loadingPlots;
function hasStreetDistrict(name){
  const key=illustratedDistricts[name];
  return streetDistricts.has(key)||cityDistricts.some(district=>district.key===key);
}
function updateGrid(){
  if(map.getSource('taiwan-grid')){
    const town=showGrid&&taiwanCoverage&&map.getZoom()>=15&&
      !regionAt()&&taiwanCoverage.at(map.getCenter().lng,map.getCenter().lat);
    map.getSource('taiwan-grid').setData(town?{type:'FeatureCollection',features:taiwanCoverage.cellsIn(map.getBounds())}:empty);
  }
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
  layer?.setEnabled(showModels);
  shopfronts?.setEnabled(showModels);
  if(map?.getLayer('atlas-shadows'))map.setLayoutProperty('atlas-shadows','visibility',showModels?'visible':'none');
  updateUI();
}
function setGrid(input){
  showGrid=input.checked;
  if(map?.getLayer('pocket-plots')){
    map.setLayoutProperty('pocket-plots','visibility',showGrid?'visible':'none');
    updateGrid();
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
$('#models').addEventListener('change',event=>setModels(event.target));
$('#grid').addEventListener('change',event=>setGrid(event.target));
$('#rotate-left').addEventListener('click',()=>{if(map)rotate(-30)});
$('#rotate-right').addEventListener('click',()=>{if(map)rotate(30)});
$('#pitch').addEventListener('click',()=>{if(map)togglePitch()});
$('#world').addEventListener('click',worldOverview);

message('載入地圖…');
try{
  const [base,districts,index,landmark,sharedMask,atlas,shadows,metro,walkingDetails,skillAtlas,cityIndex,tileIndex,bundledTaipeiTiles,previewTaipeiTiles,liveTiles,...loadedStreets]=await Promise.all([
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
    get('./cities/map-tiles/index.json?rev=shuqi-1').catch(()=>null),
    bundledTiles?get('./cities/map-tiles/taipei-bundled/index.json'):null,
    bundledTiles?get('./cities/map-tiles/taipei-preview/index.json').catch(()=>null):null,
    bundledTiles?null:fetch('https://tiles.openfreemap.org/planet',{signal:AbortSignal.timeout(1800)})
      .then(res=>res.ok?res.json():null).catch(()=>null),
    ...streetDataKeys.filter(key=>!rerun||!key.endsWith('-district')).map(key=>get(`./data/street-${key}.json`)
      .then(data=>({key,data})).catch(error=>{console.warn(error.message);return null;})),
  ]);
  districtsByName=new Map(index.counts.map(row=>[row.name,row]));
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
  if(tileIndex){
    const vectorTemplate=liveTiles?.tiles?.[0]??tileIndex.vectorTemplate;
    base.sources.openmaptiles={type:'vector',tiles:[vectorTemplate],minzoom:0,maxzoom:14,
      attribution:tileIndex.attribution};
    for(let z=0;z<=tileIndex.overviewMaxZoom;z++){
      const side=2**z;
      for(let x=0;x<side;x++)for(let y=0;y<side;y++){
        const url=vectorTemplate.replace('{z}',z).replace('{x}',x).replace('{y}',y);
        localTerrain.set(url,new URL(`./cities/map-tiles/overview/${z}-${x}-${y}.pbf`,import.meta.url).href);
      }
    }
    for(const [x,y] of tileIndex.tiles){
      for(const [key,ext] of [[terrainSource+'14/'+x+'/'+y+'.png','png'],
          [vectorTemplate.replace('{z}',14).replace('{x}',x).replace('{y}',y),'pbf']]){
        localTerrain.set(key,new URL('./cities/map-tiles/'+x+'-'+y+'.'+ext,import.meta.url).href);
      }
    }
    for(const [folder,region] of [['taipei-bundled',bundledTaipeiTiles],['taipei-preview',previewTaipeiTiles]]){
      for(const [z,x,y] of region?.tiles??[]){
        const url=vectorTemplate.replace('{z}',z).replace('{x}',x).replace('{y}',y);
        localTerrain.set(url,new URL(`./cities/map-tiles/${folder}/${z}-${x}-${y}.pbf`,import.meta.url).href);
      }
    }
  }
  if(cityIndex?.terrainTiles?.includes('13724/7014')){
    localTerrain.set(terrainSource+'14/13724/7014.png',
      new URL('./assets/taipei-songyan-factory-terrain.png',import.meta.url).href);
  }
  map=new ml.Map({
    container:'map',style:mapStyle(base,districts),...globeCamera(stage.clientWidth,stage.clientHeight),
    minZoom:-2,maxZoom:21.6,maxPitch:65,
    transformRequest:url=>({url:localTerrain.get(url)??taiwanLocalDEM(url)??url}),
    attributionControl:false,renderWorldCopies:false,localIdeographFontFamily:'sans-serif',
    canvasContextAttributes:{antialias:!appChrome},
    ...(appChrome?{pixelRatio:Math.min(window.devicePixelRatio,reducedLoad?1:1.5),maxTileCacheSize:reducedLoad?8:16}:{}),
  });
  if(!appChrome){
    map.addControl(new ml.NavigationControl({visualizePitch:true}),'top-right');
    map.addControl(new ml.ScaleControl({maxWidth:100,unit:'metric'}),'bottom-left');
  }
  const credits=new ml.AttributionControl({compact:false,customAttribution:[
    ...(appChrome?['天氣預報 <a href="https://www.met.no/en">MET Norway</a> · <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>']:[]),
    '<a href="https://data.gov.tw/dataset/7441">國土測繪中心鄉鎮界線</a>',
    '<a href="https://github.com/tilezen/joerd/blob/master/docs/attribution.md">地形 Mapzen · USGS / NOAA</a>',
    '<a href="https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143" target="_blank" rel="noopener">臺北市區界</a>',
    '<a href="https://data.taipei/dataset/detail?id=c013d9ec-a550-46bd-ac60-45f085930706" target="_blank" rel="noopener">臺北市市場處</a>',
    '<a href="https://data.taipei/dataset/detail?id=59579c19-a561-4564-8c0f-545bfb32c0f6" target="_blank" rel="noopener">臺北市衛生局</a>',
    `<a href="${metroExitDataset}" target="_blank" rel="noopener">臺北捷運出口座標</a>`,
    '<a href="https://data.gov.tw/dataset/128274" target="_blank" rel="noopener">臺北市公園處樹籍</a>',
    '<a href="https://data.gov.tw/dataset/128640" target="_blank" rel="noopener">臺北自來水事業處直飲臺</a>',
    '<a href="https://data.gov.tw/dataset/136476" target="_blank" rel="noopener">臺北市公園處遊具及體健設施</a>',
    '<a href="https://data.gov.tw/dataset/121649" target="_blank" rel="noopener">臺北市水利處河濱公園涼亭</a> · <a href="https://data.gov.tw/dataset/143897" target="_blank" rel="noopener">河濱休憩點</a>',
    '<a href="https://april-zhu.com/pocketnature" target="_blank" rel="noopener">Pocket Nature</a>',
    '<a href="https://historygis.udd.gov.taipei/arcgis/rest/services/Hosted/LOD1_2025/SceneServer/layers/0?f=pjson" target="_blank" rel="noopener">臺北市都發局 2025</a>',
  ]});
  const creditsDialog=$('#map-credits');
  creditsDialog.querySelector('.credit-list').append(credits.onAdd(map));
  const showCredits=()=>{if(!creditsDialog.open)creditsDialog.showModal();};
  $('#show-map-credits').addEventListener('click',showCredits);
  if(appChrome)window.savvyShowMapCredits=showCredits;
  map.once('remove',()=>{
    credits.onRemove();
    $('#show-map-credits').removeEventListener('click',showCredits);
    if(window.savvyShowMapCredits===showCredits)delete window.savvyShowMapCredits;
  });
  map.on('error',event=>{
    if(!map.isStyleLoaded())message('底圖暫時無法載入，請重新整理。');
    console.warn(event.error?.message??'Map data error');
  });
  if(appChrome){
    const canvas=map.getCanvas();
    let lostTimer;
    const restored=()=>clearTimeout(lostTimer);
    const lost=()=>{
      restored();
      lostTimer=setTimeout(()=>iosChannel.postMessage({event:'rendererLost'}),2000);
    };
    canvas.addEventListener('webglcontextlost',lost);
    canvas.addEventListener('webglcontextrestored',restored);
    map.once('remove',()=>{
      restored();
      canvas.removeEventListener('webglcontextlost',lost);
      canvas.removeEventListener('webglcontextrestored',restored);
    });
  }
  await map.once('load');
  function syncTerrain(){
    const terrain=!reducedLoad&&map.getZoom()>=12;
    if(terrain!==Boolean(map.getTerrain()))map.setTerrain(terrain?{source:'dem',exaggeration:1}:null);
  }
  if(appChrome){
    let terrainTimer;
    const cancelTerrain=()=>clearTimeout(terrainTimer);
    map.on('movestart',cancelTerrain);
    map.on('moveend',()=>{
      cancelTerrain();
      terrainTimer=setTimeout(syncTerrain,150);
    });
    map.on('remove',cancelTerrain);
  }else map.on('zoomend',syncTerrain);
  syncTerrain();
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
  const street101=streets.find(street=>street.key==='101');
  if(street101){
    street101.data.paths.unshift(...walks101);
    street101.data.objects.push(...streetObjects101);
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
  const cityLandmarks=[...(cityMask?cityLandmarkModels:[]),sunYatSenHall,taipeiDome,esliteSongyan,songyanFactory];
  layer=new SurveyLayer(index,message,landmark,look==='anatomy'||hybrid,streetCenters,linkScene,districtMaterial,hybrid,cityLandmarks,appChrome);
  const firstLabel=map.getStyle().layers.find(l=>l.type==='symbol')?.id;
  map.addSource('taiwan-grid',{type:'geojson',data:empty});
  map.addLayer({id:'taiwan-grid',source:'taiwan-grid',type:'line',minzoom:15,
    paint:{'line-color':'#3c7164','line-opacity':.35,'line-width':1,'line-dasharray':[2,2]}},firstLabel);
  // Keep elevation bands visible when the regional illustrations fade at street zoom.
  // Reuse the hillshade DEM, with low elevations transparent for cities and coastlines.
  function updateAlpineColors(){
    const {lng,lat}=map.getCenter();
    const visible=map.getZoom()>=11&&lng>=119.99&&lng<=122.12&&lat>=21.75&&lat<=25.64;
    const id='taiwan-alpine-colors';
    if(visible===Boolean(map.getLayer(id)))return;
    if(visible){
      map.addLayer({id,type:'color-relief',source:'relief',minzoom:11,paint:{
        'color-relief-opacity':['interpolate',['linear'],['zoom'],11,0,13,.74],
        'color-relief-color':['interpolate',['linear'],['elevation'],
          0,'rgba(112,146,107,0)',600,'rgba(112,146,107,0)',1350,'#8ca97d',
          2400,'#678e76',2950,'#60816b',3350,'#9da478',3600,'#bcaf89',3950,'#bcafa0'],
      }},'topography');
    }else map.removeLayer(id);
  }
  map.on('moveend',updateAlpineColors);
  updateAlpineColors();
  installTaiwanRelief(map,'water');
  if (preview.get('river') !== 'before') addTaipeiRiverArt(map,firstLabel);
  addDomeApron(map,firstLabel);
  map.addLayer(layer,firstLabel);
  map.getCanvas().setAttribute('aria-label','Pocket City 地圖，可拖曳、縮放及旋轉');
  if(streets.length||cityDistricts.length)streetDetail=addStreetDetail(map,ml,streets,firstLabel,look==='anatomy',hybrid,shadows,rerun);
  if(rerun && streetDetail){
    cityNature=new CityNature(loadTreeCanopies);
    map.addLayer(cityNature,firstLabel);
    const localLife=(records,visiblePacks=[])=>{
      if(preview.get('dihua')!=='before'&&visiblePacks.includes('p221_2038'))
        records=[{objects:{},paths:{'dihua-arcade':dihuaWalk}},...records];
      if(preview.get('markets')!=='before')records=marketStallLife(records,visiblePacks);
      streetDetail.setLocalLife(records);
    };
    const openMapLabel=place=>{
      if(!place.placeId || !shopfronts?.openNamedPlace(place.placeId))streetDetail.openMappedPlace(place);
    };
    atlas170=addCity170(map,firstLabel,openMapLabel,setPreparedGround,streetDetail.setMappedStores,localLife,streetDetail.authoredRoads,streetDetail.hasFocalPin,preview.get('dihua')!=='before'?layer:null,cityNature,ids=>shopfronts?.setPacks(ids));
    const focusBookshop=(card,x,y)=>{
      if(previousFronts||card.id!==bookstoreId)return false;
      locate(bookshopView);
      streetDetail.openMappedPlace({...card,...bookshopEvidence,point:[x,y]});
      return true;
    };
    addShopSearch(map,locate,dihuaSearch,place=>{
      if(indoor101)indoor101.openSearchPlace(place);else streetDetail.openMappedPlace(place);
    },row=>{
      const [name,,,x,y,,id,place]=row;
      return focusBookshop({...place,id,name},x,y);
    },async (query,center)=>{
      const entries=await searchTaiwanEntries(query,center);
      const street=worldAtlas?.rows.find(row=>row.id==='jiufen-shuqi');
      if(street?.camera)entries.unshift(['九份豎崎路','新北市瑞芳區','石階街景',...street.camera.center,
        null,'poi/way/217815406',{camera:street.camera}]);
      return entries;
    });
    shopfronts=addCityShopfronts(map,(card,row)=>{
      if(!focusBookshop(card,...row.center))streetDetail.openMappedPlace({...card,point:row.center});
    },firstLabel,ids=>{
      const ready=ids.includes(bookstoreId);
      if(ready!==bookWallReady){bookWallReady=ready;requestAnimationFrame(updateFrontageView);}
    },()=>layer.visibleWallTiles,atlas170.openNearbyPlace,districtAt);
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
  }
  add101Ground(map);
  if(!cityNature){
    cityNature=new CityNature();
    map.addLayer(cityNature,firstLabel);
    cityNature.setRows(planting101);
  }
  const orderSongyanSurface=cityIndex&&preview.get('songyan')!=='before'
    ?loadSongyanNear(map,asset=>layer.setSongyan(asset)):null;
  if(cityIndex && preview.get('dihua')!=='before'){
    get('./data/city-streets/dihua-fronts.json?v=shop-names').then(asset=>{layer.dihua=asset;map.triggerRepaint();}).catch(e=>console.warn('迪化街街屋',e));
  }
  if(rerun&&streetDetail)weather=addPocketCityWeather(map,stage,share=>{streetDetail.setRain(share);worldAtlas?.setRain(share);},preview.get('weather'));
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
  const nameInputs=[...document.querySelectorAll('[data-place-names]')];
  let globalNames=preview.get('names')!=='off',localNames=globalNames,appliedNames,showsPublicPins=true;
  applyLocalNames=inside=>{
    const visible=showsPublicPins&&(inside?localNames:globalNames);
    if(visible===appliedNames)return;
    appliedNames=visible;
    for(const id of [...cityPlaceLayers,'tw-ordinary-streets-names','city170-shop-names','city170-poi-labels','city170-poi-dots','city-atlas-pins','city-atlas-places','city-atlas-context-places','tw-public-places','city-atlas-locators','world-cities','world-city-dots','poi_r1']){
      if(map.getLayer(id))map.setLayoutProperty(id,'visibility',visible&&(id!=='taipei-savvy-place-names'||showsPublicPins)?'visible':'none');
    }
    taiwanScenery?.setLabels(visible);
    shopfronts?.setNames(visible);
    indoor101?.setNames(visible);
    metroState?.setNames(visible);
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
  try{
    worldAtlas=await addCityAtlas(map,firstLabel,place=>streetDetail?.openMappedPlace(place),updateUI,{settleCamera:appChrome});
    const open=place=>streetDetail?.openMappedPlace(place);
    const inTown=(x,y)=>!!taiwanCoverage?.at(x,y);
    const overlapsAuthored=(box,rings)=>worldAtlas.rows.some(row=>plotOverlaps(row,box,rings));
    const exclude=(x,y)=>!!districtAt(x,y)||overlapsAuthored([x,y,x,y]);
    const context=addCityContext(map,worldAtlas.rows,firstLabel,districtAt,open,inTown);
    taiwanScenery=addTaiwanScenery(map,firstLabel,open);
    addTaiwanPlaces(map,(place,zoom)=>!!districtAt(...place.point)||worldAtlas.claimsPlace(place,zoom),open);
    let coverageRequest;
    function loadCoverage(){
      if(taiwanCoverage||coverageRequest||map.getZoom()<5)return;
      const b=map.getBounds();
      if(b.getEast()<114||b.getWest()>125||b.getNorth()<10||b.getSouth()>27)return;
      coverageRequest=Promise.all([readTaiwanJSON('townships.geojson.gz'),readTaiwanJSON('cells.json')])
        .then(([towns,grid])=>{
          taiwanCoverage=makeTaiwanCoverage(towns,grid);
          context.refresh();
          taiwanCells=addTaiwanCells(map,firstLabel,{contains:inTown,exclude,overlapsAuthored},context);
          appliedNames=undefined;applyLocalNames(!$('#fuxing-controls').hidden);
          updateGrid();updateUI();
        }).catch(error=>console.warn('Taiwan coverage',error)).finally(()=>{coverageRequest=null;});
    }
    map.on('moveend',loadCoverage);loadCoverage();
    weather?.refresh();
    appliedNames=undefined;applyLocalNames(false);
    $('#shuqi-view').addEventListener('click',()=>{
      const row=worldAtlas.rows.find(r=>r.id==='jiufen-shuqi');
      if(!row)return;
      lanternView=!lanternView;
      locate(lanternView?lanternCamera:row.camera);updateUI();
    });
    $('#retry-landmark').addEventListener('click',e=>worldAtlas.retry(e.currentTarget.dataset.city));
  }catch(error){console.warn('City catalog unavailable',error);}
  function atlasCamera(row){
    if(row.camera)return row.camera;
    return {center:row.center,zoom:row.id==='tamsui'?18.32:17.95,mobileZoom:17.45,pitch:52,mobilePitch:49,bearing:row.id==='tamsui'?18:row.bearing??-17};
  }
  const startCity=worldAtlas?.rows.find(row=>row.id===preview.get('city'));
  const street=preview.get('street');
  const cityLandmark=cityLandmarks.find(row=>row.id===preview.get('landmark'));
  const campusView=preview.get('campus');
  const coordinate=(preview.get('view')??'').split(',').map(Number);
  const facing=Number(preview.get('bearing')??-17);
  if(coordinate.length===3 && coordinate.every(Number.isFinite) &&
      Math.abs(coordinate[0])<=180 &&
      Math.abs(coordinate[1])<=85){
    const zoom=Math.max(4,Math.min(21.6,coordinate[2]));
    const defaultPitch=zoom<11?0:42;
    const requestedPitch=Number(preview.get('pitch')??defaultPitch);
    const pitch=Number.isFinite(requestedPitch)?Math.max(0,Math.min(65,requestedPitch)):defaultPitch;
    locate({center:coordinate.slice(0,2),zoom,mobileZoom:Math.max(4,zoom-.35),
      pitch,mobilePitch:pitch,bearing:Number.isFinite(facing)?facing:-17},false);
  }else if(preview.get('nature')==='yushan')locate(yushanView,false);
  else if(lanternView)locate(lanternCamera,false);
  else if(startCity)locate(atlasCamera(startCity),false);
  else if(street==='101-mall')locate({center:[121.56446,25.034],zoom:18.7,mobileZoom:17.65,pitch:0,mobilePitch:0,bearing:0},false);
  else if(street==='fuxing')locate(bookshopView,false);
  else if(street==='fuxing-row')locate(shopRowView,false);
  else if(dihuaViews.has(street))locate(dihuaViews.get(street),false);
  else if(campusView==='ntu')locate({center:[121.53555,25.01657],zoom:16.75,pitch:38,bearing:-18},false);
  else if(cityLandmark)locate({...cityLandmark,zoom:cityLandmark.zoom??17.15},false);
  else if(streetDistricts.has(street)||Object.values(illustratedDistricts).includes(street)||cityDistricts.some(district=>district.key===street)){
    const district=Object.keys(illustratedDistricts).find(name=>illustratedDistricts[name]===street);
    if(district)focusDistrict(district);
    else if(street==='xinyi-link')focusCorridor();
    else if(street==='101')focus101Street(false);
    else locate(landmarks[street],false);
  }else if(preview.get('city')==='taipei')fit(taipei,true);
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
  if(streetDetail){
    addOfficialFloorGuide(stage,{allowRemoteImages:!bundledTiles});
    indoor101=addTaipei101Indoor(map,{stage,Marker:ml.Marker,startFloor:preview.get('floor'),namesVisible:appliedNames,
      load:async()=>{
        const [{taipei101Indoor},{officialFloorDirectory}]=await Promise.all([
          import(new URL('./taipei101-indoor-data.js',import.meta.url).href),
          import(new URL('./taipei101-directory.js',import.meta.url).href),
        ]);
        return {...taipei101Indoor,directory:officialFloorDirectory};
      },
      setCutaway:(active,ring)=>layer.setMallCutaway(active?ring.map(p=>ml.MercatorCoordinate.fromLngLat(p)):null),
      openPlace:streetDetail.openMappedPlace,
      closePlace:streetDetail.closeMappedPlace,
    });
    const updateMallPins=()=>streetDetail.setVisiblePlaceFilter(indoor101.isStreetPinVisible,indoor101.isContextPin);
    updateMallPins();
    stage.addEventListener('mall101-floor',updateMallPins);
  }
  function adjustPitch(){
    if(!manualPitch&&!indoor101?.state().active&&!map.isMoving()){
      const z=map.getZoom();
      const center=map.getCenter();
      const highland=z>=12&&center.lng>=120&&center.lng<=122&&center.lat>=21.8&&center.lat<=25.4
        &&map.queryTerrainElevation(center)>=1200;
      const goal=highland?55:z>=16.35?50:z>=15.1?43:z<10?0:z<buildingZoom?18:34;
      if(Math.abs(goal-map.getPitch())>3)jump({pitch:goal});
    }
  }
  map.on('moveend',adjustPitch);
  map.on('idle',adjustPitch);
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
      indoor101:indoor101?.state(),detail:layer.diagnostics,street:streetDetail?.state(),metro:metroState?.(),weather:weather?.state(),
      pocketCity:skillAtlas?.summary??null,
      atlas170:atlas170?.state(),shopfronts:shopfronts?.state(),inventoryTreesDrawn:cityNature?.drawn,
      landmarkAtlas:worldAtlas?.state(),taiwan:{townships:taiwanCoverage?.towns,landCells:taiwanCoverage?.count,visible:taiwanCells?.state()},
      cityAtlas:atlas170?atlas170.state().coverage:cityIndex?.cityCoverage??null,
    }),
  };
  if(iosChannel){
    map.on('pocketcamerarestore',()=>{manualPitch=true;});
    const explore=appChrome&&atlas170?{
      button:$('#place-in-explore'),
      friendButton:$('#place-in-friends'),
      venues:await loadNativeExploreVenues(),
      open:(place,trigger)=>streetDetail.openMappedPlace(place,trigger),
    }:undefined;
    window.savvyPocketHost=connectIOSMap(map,ml.Marker,iosChannel,appChrome?settings=>{
      weather?.setMode(settings.weather);
      if(metroState&&metroState().visible!==settings.metro)metroState.setVisible(settings.metro);
      if(showsPublicPins===settings.showsPublicPins)return;
      showsPublicPins=settings.showsPublicPins;
      map.savvySavedOnly=!showsPublicPins;
      indoor101?.refreshVisibility();
      if(!showsPublicPins)window.savvyDismissPlaceSheet?.();
      applyLocalNames(!$('#fuxing-controls').hidden);
      if(map.getLayer('taipei-savvy-place-neighbors'))
        map.setLayoutProperty('taipei-savvy-place-neighbors','visibility',showsPublicPins?'visible':'none');

    }:undefined,explore,{floorEvents:stage,visiblePin:indoor101?.isPinVisible});
    iosChannel.postMessage({event:'ready'});
    if(!$('#place-card').hidden){
      iosChannel.postMessage({event:'placeSheet',open:true});
      window.savvySyncPlaceSheet?.();
    }
  }
}catch(error){
  iosChannel?.postMessage({event:'failure'});
  message('預覽無法載入，請重新整理。');
  console.error(error);
}
