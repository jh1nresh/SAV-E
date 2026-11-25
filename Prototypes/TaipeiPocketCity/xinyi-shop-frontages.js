export const shopDetailZoom=17.55, neighborhoodFrontageZoom=16.8;
// District bounds from districts.geojson are used only to prefetch packs. The
// surveyed midpoint of each rendered bay must be inside the municipal district.
const districtBounds=new Map([
  ['信義區',[121.55252218973669,25.008107552148005,121.5921574797743,25.04950650405726]],
  ['松山區',[121.53834421549676,25.04429118892056,121.58006741694864,25.07597381828672]],
]);
export function frontagePackIds(visible,zoom){
  if(zoom>=shopDetailZoom)return visible.map(pack=>pack.id);
  if(zoom<neighborhoodFrontageZoom)return [];
  return visible.filter(({bounds:[w,s,e,n]})=>{
    for(const [west,south,east,north] of districtBounds.values()){
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
    ['near-wall','street-address','shop-footprint','mapped-entrance'].includes(row.evidence)&&
    !row.vendor&&row.kind!=='market-area'&&districtBounds.has(districtAt?.(...row.center));
}
