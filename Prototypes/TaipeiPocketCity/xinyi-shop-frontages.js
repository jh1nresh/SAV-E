import {streetDistricts} from './taipei-street-districts.js';

export const shopDetailZoom=17.55, neighborhoodFrontageZoom=16.8;
const districtNames=new Set(streetDistricts.map(({name})=>name));
export function frontagePackIds(visible,zoom){
  if(zoom>=shopDetailZoom)return visible.map(pack=>pack.id);
  if(zoom<neighborhoodFrontageZoom)return [];
  return visible.filter(({bounds:[w,s,e,n]})=>{
    for(const {bounds:[west,south,east,north]} of streetDistricts){
      if(w<=east&&e>=west&&s<=north&&n>=south)return true;
    }
    return false;
  }).map(pack=>pack.id);
}

export function isNeighborhoodShopWall(row,districtAt){
  // city170-frontages intersects each matched OSM bay with a measured vertical
  // survey wall. A POI, an address or a survey-only estimate has no such identity.
  return /^building\/(way|relation)\/\d+$/.test(row.buildingId)&&/^(road|walk)\/(way|relation)\/\d+$/.test(row.streetId)&&
    row.wall?.length===2&&row.wall.every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite))&&
    Number.isFinite(row.surveyBase)&&Number.isFinite(row.surveyTop)&&Number.isFinite(row.groundZ)&&
    // Match the exposure check in build-city170-frontages.py after heights round to millimetres.
    row.groundZ>=row.surveyBase-1.501&&row.surveyTop-row.groundZ>=2.299&&
    ['near-wall','street-address','shop-footprint','mapped-entrance'].includes(row.evidence)&&
    !row.vendor&&row.kind!=='market-area'&&districtNames.has(districtAt?.(...row.center));
}
