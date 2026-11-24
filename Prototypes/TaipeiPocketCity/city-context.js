import {plotOverlaps,footprintKey} from './authored-footprint.js?v=street-walls-1';
import {placePinStyle} from './place-pins.js';
// Continue the built streets between authored landmarks with the visible OpenMapTiles
// building tiles. Style the original tile fragments, retaining courtyards and min heights.
export const atlasRegions=[
  [119.24,21.7,122.15,25.5], [118.12,24.29,118.51,24.60], [119.88,25.90,120.54,26.42],
  [120.85,30.66,122.25,31.92],[115.41,39.42,117.53,41.10],[-118.96,33.65,-117.60,34.83],
];
function covers([w,s,e,n],x,y){return x>=w&&x<=e&&y>=s&&y<=n;}
function buildingBounds(outer){
  let west=Infinity,south=Infinity,east=-Infinity,north=-Infinity;
  for(const [x,y] of outer){west=Math.min(west,x);east=Math.max(east,x);south=Math.min(south,y);north=Math.max(north,y);}
  return [west,south,east,north];
}
export function intersectsBuilding(outer,bounds){
  return plotOverlaps({bounds},buildingBounds(outer));
}
export function addCityContext(map,rows,before,inTaipei,open,inTaiwan=()=>false){
  const id='city-atlas-context',data=features=>({type:'FeatureCollection',features});
  map.addSource(id,{type:'geojson',data:data([]),maxzoom:16});
  map.addLayer({id,source:id,type:'fill-extrusion',minzoom:15,filter:['==',['geometry-type'],'Polygon'],paint:{
    'fill-extrusion-height':['get','height'],'fill-extrusion-base':['get','base'],
    'fill-extrusion-color':['match',['get','material'],0,'#e1c7aa',1,'#ddc0ab',2,'#cec5ae',3,'#e1cdb2','#cdbaa6'],
    'fill-extrusion-opacity':1,'fill-extrusion-vertical-gradient':true,
  }},before);
  const placeLayer='city-atlas-context-places';
  map.addLayer({id:placeLayer,source:id,type:'symbol',minzoom:16.6,
    filter:['all',['==',['geometry-type'],'Point'],['step',['zoom'],['<=',['get','rank'],7],17.8,['<=',['get','rank'],19],18.8,true]],
    ...placePinStyle(map)});
  map.on('click',placeLayer,event=>{
    const hit=event.features?.[0];
    if(hit)open({...hit.properties,kind:'地點',point:hit.geometry.coordinates});
  });
  let timer,previous='',active=false;
  function refresh(){
    const {lng,lat}=map.getCenter(),z=map.getZoom(),bounds=map.getBounds();
    if(z<15||!(inTaiwan(lng,lat)||atlasRegions.some(box=>covers(box,lng,lat)))){
      if(active){map.getSource(id).setData(data([]));previous='';active=false;}return;
    }
    const view=[bounds.getWest(),bounds.getSouth(),bounds.getEast(),bounds.getNorth()];
    const nearby=rows.filter(r=>covers([view[0]-.02,view[1]-.02,view[2]+.02,view[3]+.02],...r.center));
    const features=[],seen=new Set();
    for(const feature of map.querySourceFeatures('openmaptiles',{sourceLayer:'building'})){
      const g=feature.geometry,p=feature.properties;
      if(p.hide_3d===true||!['Polygon','MultiPolygon'].includes(g.type))continue;
      for(const polygon of g.type==='Polygon'?[g.coordinates]:g.coordinates){
        const ring=polygon[0];
        if(!ring?.length||inTaipei(...ring[0]))continue;
        const bounds=buildingBounds(ring);
        if(!plotOverlaps({bounds:view},bounds)||nearby.some(row=>plotOverlaps(row,bounds,polygon)))continue;
        const key=footprintKey(ring);
        if(seen.has(key))continue;
        seen.add(key);
        const height=Math.max(1,Number(p.render_height)||5.5),base=Math.min(height,Math.max(0,Number(p.render_min_height)||0));
        features.push({type:'Feature',geometry:{type:'Polygon',coordinates:polygon},properties:{
          footprint:key,height,base,material:Math.abs(Math.round(ring[0][0]*3000+ring[0][1]*17000))%5}});
      }
    }
    if(z>=16.6)for(const feature of map.querySourceFeatures('openmaptiles',{sourceLayer:'poi'})){
      if(feature.geometry.type!=='Point')continue;
      const p=feature.properties,[x,y]=feature.geometry.coordinates;
      const name=p['name:zh-Hant']||p['name:zh']||p.name;
      if(!name||!covers(view,x,y)||inTaiwan(x,y)||inTaipei(x,y)||nearby.some(row=>covers(row.bounds,x,y)))continue;
      const key='poi/'+name+'/'+x.toFixed(6)+'/'+y.toFixed(6);
      if(seen.has(key))continue;
      seen.add(key);
      features.push({type:'Feature',geometry:feature.geometry,properties:{
        name,rank:Number(p.rank)||30,category:p.subclass||p.class||'other',categoryLabel:'地圖地點'}});
    }
    const signature=[...seen].sort().join('|');
    if(signature!==previous){map.getSource(id).setData(data(features));previous=signature;}
    active=true;
  }
  function schedule(){clearTimeout(timer);timer=setTimeout(refresh,100);}
  map.on('moveend',schedule);
  map.on('sourcedata',e=>{if(e.sourceId==='openmaptiles'&&e.sourceDataType==='content')schedule();});
  map.on('remove',()=>clearTimeout(timer));schedule();
  let prior=[];
  return {setDetailedFootprints(keys){
    keys.sort();
    if(keys.length===prior.length&&keys.every((v,i)=>v===prior[i]))return;
    prior=keys;
    const polygon=['==',['geometry-type'],'Polygon'];
    map.setFilter(id,keys.length?['all',polygon,['!', ['in',['get','footprint'],['literal',keys]]]]:polygon);
  }};
}
