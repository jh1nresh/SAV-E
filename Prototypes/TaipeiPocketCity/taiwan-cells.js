import {addTaiwanStreets,mergeVisibleBuildings} from './taiwan-streets.js?v=city-colour-3';
import {PitchedRoofs} from './taiwan-pitched-roofs.js?v=city-colour-3';
import {CityNature} from './city-nature.js?v=alpine-1';
import {buildTaiwanCells} from './taiwan-cell-geometry.js?v=city-colour-3';

const sourceId='taiwan-cell-details';
const collection=features=>({type:'FeatureCollection',features});
export function addTaiwanCells(map,before,{contains,exclude,overlapsAuthored},context){
  let crowns,roofs;
  map.addSource(sourceId,{type:'geojson',data:collection([]),maxzoom:18});
  map.addLayer({id:sourceId,source:sourceId,type:'fill-extrusion',minzoom:15,
    paint:{'fill-extrusion-base':['get','base'],'fill-extrusion-height':['get','height'],
      'fill-extrusion-color':['get','color'],'fill-extrusion-vertical-gradient':false}},before);

  const streets=addTaiwanStreets(map,before,{contains,exclude,overlapsAuthored},schedule);
  let timer,revision=0,counts={cells:0,details:0,trees:0};
  async function refresh(){
    const current=++revision;
    timer=undefined;
    const b=map.getBounds(),view=[b.getWest(),b.getSouth(),b.getEast(),b.getNorth()];
    const zoom=map.getZoom(),{lng,lat}=map.getCenter();
    const local=streets.refresh(view,[lng,lat],zoom);
    if(zoom<15||view[2]<110||view[0]>126||view[3]<9||view[1]>27){
      if(counts.cells){
        context?.setDetailedFootprints([]);roofs?.setRows([]);
        map.getSource(sourceId).setData(collection([]));crowns?.setRows([]);
        counts={cells:0,details:0,trees:0};
      }
      return;
    }
    const read=(sourceLayer,filter)=>map.querySourceFeatures('openmaptiles',{sourceLayer,filter});
    const classes=(...names)=>['match',['get','class'],names,true,false];
    const buildings=await mergeVisibleBuildings(read('building'),local.buildings,view,()=>current===revision);
    if(current!==revision||!buildings)return;
    const tiles={buildings,water:[],woods:[],fields:[],ways:[],pois:[]};
    if(zoom>=17){
      tiles.water=read('water');
      tiles.woods=read('landcover',['any',classes('wood','forest'),['match',['get','subclass'],['orchard','park','garden'],true,false]]);
      tiles.fields=read('landuse',classes('pitch','track','cemetery','railway','playground','stadium','garages','quarry'));
      tiles.ways=[...read('transportation'),...read('waterway'),...local.roads];
      if(zoom>=18)tiles.pois=[...read('poi'),...local.pois];
    }
    const built=buildTaiwanCells({view,center:[lng,lat],zoom,tiles,contains,exclude,overlapsAuthored});
    if(built.roofs.length&&!roofs){roofs=new PitchedRoofs();map.addLayer(roofs,before);}
    roofs?.setRows(built.roofs);
    if(built.trees.length&&!crowns){
      crowns=new CityNature();
      crowns.id='taiwan-cell-forest';
      map.addLayer(crowns,before);
    }
    context?.setDetailedFootprints(built.mappedBodies);
    map.getSource(sourceId).setData(collection(built.details));crowns?.setRows(built.trees);
    counts={cells:built.cells,details:built.details.length,trees:built.trees.length};
  }
  function schedule(){if(timer===undefined)timer=setTimeout(refresh,120);}
  map.on('movestart',()=>{revision++;clearTimeout(timer);timer=undefined;});
  map.on('moveend',schedule);
  map.on('sourcedata',e=>{if(e.sourceId==='openmaptiles'&&e.sourceDataType==='content')schedule();});
  map.on('remove',()=>{revision++;clearTimeout(timer);});
  schedule();
  return {state:()=>({...counts,treesDrawn:crowns?.drawn??0,ordinary:streets.state()})};
}
