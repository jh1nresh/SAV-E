export const shopDetailZoom=17.55, xinyiFrontageZoom=16.8;
// survey-index.json district bounds are used only to prefetch packs. The
// surveyed midpoint of each rendered bay must be inside the municipal district.
const xinyiBounds=[121.55252218973669,25.008107552148005,121.5921574797743,25.04950650405726];
export function frontagePackIds(visible,zoom){
  if(zoom>=shopDetailZoom)return visible.map(pack=>pack.id);
  if(zoom<xinyiFrontageZoom)return [];
  const [west,south,east,north]=xinyiBounds;
  return visible.filter(({bounds:[w,s,e,n]})=>w<=east&&e>=west&&s<=north&&n>=south).map(pack=>pack.id);
}

export function isXinyiShopWall(row,districtAt){
  // city170-frontages intersects each matched OSM bay with a measured vertical
  // survey wall. A POI, an address or a survey-only estimate has no such identity.
  return /^building\/(way|relation)\/\d+$/.test(row.buildingId)&&/^(road|walk)\/(way|relation)\/\d+$/.test(row.streetId)&&
    row.wall?.length===2&&row.wall.every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite))&&
    Number.isFinite(row.surveyBase)&&Number.isFinite(row.surveyTop)&&Number.isFinite(row.groundZ)&&
    ['near-wall','street-address','shop-footprint','mapped-entrance'].includes(row.evidence)&&
    districtAt?.(...row.center)==='信義區';
}
