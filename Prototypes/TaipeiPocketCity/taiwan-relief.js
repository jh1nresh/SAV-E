// The survey mask and shaded DEM sheets are in Web Mercator, like the vector map.
import coverage from './taiwan/relief/index.js';
import mountains from './taiwan/mountains/index.js';

const mountainBase=new URL('./taiwan/mountains/',import.meta.url);
const mountainDEM=new Set(mountains.dem);
const localBase=new URL('./taiwan/relief/',import.meta.url);
const terrainPrefix=coverage.terrainSource+'/';
const localDEM=new Set(coverage.dem);

export function taiwanLocalDEM(url){
  if(!url.startsWith(terrainPrefix)||!url.endsWith('.png'))return;
  const name=url.slice(terrainPrefix.length,-4).replaceAll('/','-');
  if(mountainDEM.has(name))return new URL('dem/'+name+'.png',mountainBase).href;
  if(localDEM.has(name))return new URL('dem/'+name+'.png',localBase).href;
}

export function installTaiwanRelief(map,beforeId){
  const attached=new Set();
  const surveyOpacity=['interpolate',['linear'],['zoom'],4.5,0,6,.9,9,.94,11,.75,13,.3,14,0];
  const sheets=[
    ...coverage.sheets.map(sheet=>({...sheet,base:localBase,minzoom:4.5,maxzoom:14,opacity:surveyOpacity})),
    ...mountains.sheets.map(sheet=>({...sheet,base:mountainBase,opacity:['interpolate',['linear'],['zoom'],
      sheet.minzoom,0,sheet.minzoom+.8,1,sheet.maxzoom-1,1,sheet.maxzoom,0]})),
  ];
  function refresh(){
    const zoom=map.getZoom(),bounds=map.getBounds();
    const west=bounds.getWest();
    let east=bounds.getEast();
    if(east<west)east+=360;
    for(const [index,sheet] of sheets.entries()){
      const [[left,north],,[right,south]]=sheet.coordinates;
      const shift=360*Math.round((east+west-right-left)/720);
      const visible=zoom>=sheet.minzoom&&zoom<sheet.maxzoom&&south<=bounds.getNorth()&&north>=bounds.getSouth()&&
        left+shift<=east&&right+shift>=west;
      const id='taiwan-relief-'+sheet.name;
      if(visible===attached.has(id))continue;
      if(visible){
        map.addSource(id,{type:'image',url:new URL(sheet.name+'.webp',sheet.base).href,
          coordinates:sheet.coordinates});
        const next=sheets.slice(index+1).find(s=>attached.has('taiwan-relief-'+s.name));
        map.addLayer({id,source:id,type:'raster',minzoom:sheet.minzoom,maxzoom:sheet.maxzoom,
          paint:{'raster-opacity':sheet.opacity,
            'raster-fade-duration':0}},next?'taiwan-relief-'+next.name:beforeId);
        attached.add(id);
      }else{
        map.removeLayer(id);
        map.removeSource(id);
        attached.delete(id);
      }
    }
  }
  map.on('moveend',refresh);
  refresh();
  return sheets.length;
}
