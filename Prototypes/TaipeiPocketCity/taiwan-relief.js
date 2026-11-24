// The survey mask and shaded DEM sheets are in Web Mercator, like the vector map.
import coverage from './taiwan/relief/index.js';

const localBase=new URL('./taiwan/relief/',import.meta.url);
const terrainPrefix=coverage.terrainSource+'/';
const localDEM=new Set(coverage.dem);

export function taiwanLocalDEM(url){
  if(!url.startsWith(terrainPrefix)||!url.endsWith('.png'))return;
  const name=url.slice(terrainPrefix.length,-4).replaceAll('/','-');
  if(localDEM.has(name))return new URL('dem/'+name+'.png',localBase).href;
}

export function installTaiwanRelief(map,beforeId){
  const attached=new Set();
  function refresh(){
    const zoom=map.getZoom(),bounds=map.getBounds();
    const west=bounds.getWest();
    let east=bounds.getEast();
    if(east<west)east+=360;
    for(const sheet of coverage.sheets){
      const [[left,north],,[right,south]]=sheet.coordinates;
      const shift=360*Math.round((east+west-right-left)/720);
      const visible=zoom>=4.5&&zoom<14&&south<=bounds.getNorth()&&north>=bounds.getSouth()&&
        left+shift<=east&&right+shift>=west;
      const id='taiwan-relief-'+sheet.name;
      if(visible===attached.has(id))continue;
      if(visible){
        map.addSource(id,{type:'image',url:new URL(sheet.name+'.webp',localBase).href,
          coordinates:sheet.coordinates});
        map.addLayer({id,source:id,type:'raster',minzoom:4.5,maxzoom:14,
          paint:{'raster-opacity':['interpolate',['linear'],['zoom'],4.5,0,6,.9,9,.94,11,.75,13,.3,14,0],
            'raster-fade-duration':0}},beforeId);
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
  return coverage.sheets.length;
}
