import {geographicPoint} from './cities/geography.js';
import {meta,coordinates,routes,trees} from './taipei101-single-ground-data.js';

const angle=meta.rotation*Math.PI/180;
const c=Math.cos(angle),s=Math.sin(angle);
const lngMetres=111320*Math.cos(meta.lat*Math.PI/180);
const xs=coordinates.map(p=>p[0]),ys=coordinates.map(p=>p[1]);
const extent=[Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)];

export function touches101Ground([w,s,e,n]){
  return w<=extent[2]&&e>=extent[0]&&s<=extent[3]&&n>=extent[1];
}

export function inside101Ground(lng,lat){
  if(lng<extent[0]||lng>extent[2]||lat<extent[1]||lat>extent[3])return false;
  const east=(lng-meta.lon)*lngMetres,north=(lat-meta.lat)*110574;
  return Math.abs(east*c+north*s)<=meta.half&&Math.abs(north*c-east*s)<=meta.half;
}

// The square ends at the exact coordinates used by the original drawing.
export function add101Ground(map){
  const id='taipei101-single-ground';
  map.addSource(id,{type:'image',url:new URL('./assets/taipei101-single-ground.png',import.meta.url).href,coordinates});
  map.addLayer({id,source:id,type:'raster',minzoom:14,
    paint:{'raster-opacity':['interpolate',['linear'],['zoom'],14,0,16,1],'raster-fade-duration':0}},
    map.getLayer('atlas-shadows')?'atlas-shadows':'survey');
}

export const planting101=trees;
export const walks101=routes.map(p=>({
  points:p.map(pt=>geographicPoint(meta,pt)),single101:true,
  // One moving figure per mapped route works with the map's shared figure budget.
  people:1,
}));
