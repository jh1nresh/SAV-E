import {CityNature} from './city-nature.js';
import {buildTaiwanCells} from './taiwan-cell-geometry.js?v=shuqi-1';

const sourceId='taiwan-cell-details';
const collection=features=>({type:'FeatureCollection',features});
export function addTaiwanCells(map,before,{contains,exclude,overlapsAuthored}){
  let crowns;
  map.addSource(sourceId,{type:'geojson',data:collection([]),maxzoom:18});
  map.addLayer({id:sourceId,source:sourceId,type:'fill-extrusion',minzoom:17,
    paint:{'fill-extrusion-base':['get','base'],'fill-extrusion-height':['get','height'],
      'fill-extrusion-color':['get','color'],'fill-extrusion-vertical-gradient':false}},before);

  let timer,counts={cells:0,details:0,trees:0};
  function refresh(){
    timer=undefined;
    const b=map.getBounds(),view=[b.getWest(),b.getSouth(),b.getEast(),b.getNorth()];
    const zoom=map.getZoom();
    if(zoom<17||view[2]<110||view[0]>126||view[3]<9||view[1]>27){
      if(counts.cells){
        map.getSource(sourceId).setData(collection([]));crowns?.setRows([]);
        counts={cells:0,details:0,trees:0};
      }
      return;
    }
    const read=(sourceLayer,filter)=>map.querySourceFeatures('openmaptiles',{sourceLayer,filter});
    const classes=(...names)=>['match',['get','class'],names,true,false];
    const tiles={
      buildings:read('building'),water:read('water'),
      woods:read('landcover',['any',classes('wood','forest'),['match',['get','subclass'],['orchard','park','garden'],true,false]]),
      fields:read('landuse',classes('pitch','track','cemetery','railway','playground','stadium','garages','quarry')),
      ways:[...read('transportation'),...read('waterway')],pois:zoom>=18?read('poi'):[],
    };
    const {lng,lat}=map.getCenter();
    const built=buildTaiwanCells({view,center:[lng,lat],zoom,tiles,contains,exclude,overlapsAuthored});
    if(built.trees.length&&!crowns){
      crowns=new CityNature();
      crowns.id='taiwan-cell-forest';
      map.addLayer(crowns,before);
    }
    map.getSource(sourceId).setData(collection(built.details));crowns?.setRows(built.trees);
    counts={cells:built.cells,details:built.details.length,trees:built.trees.length};
  }
  function schedule(){if(timer===undefined)timer=setTimeout(refresh,120);}
  map.on('moveend',schedule);
  map.on('sourcedata',e=>{if(e.sourceId==='openmaptiles'&&e.sourceDataType==='content')schedule();});
  map.on('remove',()=>clearTimeout(timer));
  schedule();
  return {state:()=>({...counts,treesDrawn:crowns?.drawn??0})};
}
