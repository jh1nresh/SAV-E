import {readPocketCityAsset} from './pocket-city-atlas.js';
import {withShopFacts} from './taipei-frontage-pack.js?v=ground-shops-2';
import {metroExitFeatures,metroExitLayer} from './taipei-metro-exits.js';
import {photoPlaces} from './place-photos.js';
import {loadVerifiedSavvyMapPins} from './savvy-place-sources.js';

const source='taipei-place-index';
const names='taipei-place-names';
const outdoorNames='taipei-outdoor-names';
const nearby='taipei-place-neighbors';
const savvySource='taipei-savvy-places';
const savvyNames='taipei-savvy-place-names';
const savvyNearby='taipei-savvy-place-neighbors';
const savvyZoom=16;
export const cityPlaceLayers=[savvyNames,names,outdoorNames,metroExitLayer,nearby];

// Stable IDs distinguish the landmark itself from rentals and shops bearing the same name.
const cityLandmarks=[
  'poi/way/1159328965', // 台北 101
  'poi/way/827791918', // 國立故宮博物院
  'poi/way/1052759757', // 中正紀念堂
  'park/way/1227733215', // 大安森林公園
  'poi/way/135913533', // 臺北市立動物園
];
const districtLandmarks=[
  'park/relation/7009035','park/way/189784276', // 北投公園、大湖公園
  'poi/relation/11736180','poi/way/189788192','poi/way/229061328', // 北美館、國父紀念館、松菸
];
const outdoor=['park','garden','pitch','recreation_ground','nature_reserve','sports_centre','playground','stadium'];
const category=['get','category'];
const matches=(field,values)=>['in',field,['literal',values]];
const revealZoom=['case',
  matches(['get','placeId'],cityLandmarks),11,
  matches(['get','placeId'],districtLandmarks),13,
  matches(category,['museum','zoo','station','nature_reserve','market-area']),14,
  matches(category,['park','arts_centre','university','hospital','marketplace','mall','theatre']),15,
  matches(category,['library','attraction','school','sports_centre','stadium','garden','department_store']),16,
  17,
];

let pending;
export function loadCityPlaces(){
  return pending??=readPocketCityAsset('city-place-index').then(data=>({
    ...data,features:data.features.map(withShopFacts).concat(metroExitFeatures),
  })).catch(error=>{pending=null;throw error;});
}

export function addCityPlaceIndex(map,pin){
  map.addSource(source,{type:'geojson',data:{type:'FeatureCollection',features:metroExitFeatures},maxzoom:19});
  const before='city170-school-names';
  const named=['has','name'];
  const notExit=['!',['has','exitLabel']];
  const photoIds=matches(['get','placeId'],photoPlaces.map(p=>p.placeId));
  // Symbols and text compete for the same screen space as the base map labels.
  // Increasing the padding at city scales leaves room to read roads and geography.
  const layout={...pin.layout,'symbol-sort-key':revealZoom,
    'icon-size':['interpolate',['linear'],['zoom'],11,0.93,17,1.08,19,1.16],
    'text-size':['interpolate',['linear'],['zoom'],11,12.5,17,14,20,16],
    'text-padding':['interpolate',['linear'],['zoom'],11,25,14,24,16,17,17,10,19,5],
  };
  map.addSource(savvySource,{type:'geojson',data:{type:'FeatureCollection',features:[]},maxzoom:19});
  map.addLayer({id:names,source,type:'symbol',minzoom:11,maxzoom:17.8,
    filter:['all',named,notExit,['>=',['zoom'],revealZoom],['any',['<',['zoom'],16],['!',photoIds]]],
    layout,paint:pin.paint},before);
  // Detailed street layers take over individual POIs. The index continues to name
  // outdoor areas represented by polygons in the detailed street packs.
  map.addLayer({id:outdoorNames,source,type:'symbol',minzoom:17.8,
    filter:['all',named,matches(category,outdoor)],layout,paint:pin.paint},before);
  map.addLayer({id:metroExitLayer,source,type:'symbol',minzoom:17.55,
    filter:['has','exitLabel'],
    layout:{...pin.layout,'icon-image':'place-pin-transit','icon-size':.92,
      'text-field':['get','exitLabel'],'text-size':13,'text-offset':[.98,0],
      'text-padding':4,'text-optional':true,'symbol-sort-key':0},
    paint:{...pin.paint,'text-color':'#24599b'}},before);
  map.addLayer({id:savvyNames,source:savvySource,type:'symbol',minzoom:savvyZoom,
    layout:{...layout,'text-optional':true},paint:pin.paint},before);
  // Query only after a visible street pin was selected, to disambiguate adjoining shops.
  map.addLayer({id:nearby,source,type:'circle',minzoom:16,filter:['all',notExit,['!',photoIds]],
    paint:{'circle-radius':6,'circle-opacity':0}},before);
  map.addLayer({id:savvyNearby,source:savvySource,type:'circle',minzoom:savvyZoom,
    paint:{'circle-radius':6,'circle-opacity':0}},before);

  // Native account markers replace only atlas features with a reviewed identity.
  const accountLayers = [names,outdoorNames,metroExitLayer,nearby,savvyNames,savvyNearby,
    'city170-shop-names','city170-poi-labels','city170-poi-dots','city170-vendor-awnings'];
  const previousFilters = new Map(accountLayers.filter(id=>map.getLayer(id)).map(id=>[id,map.getFilter(id)??null]));
  function refreshFilters(placeIds){
    const wing=map.savvyMallFootprint;
    const hiddenIds=[...new Set([...placeIds,...(map.savvyMallAdjacentPlaceIds??[])])];
    const identity=['coalesce',['get','placeId'],['id'],''];
    for (const id of accountLayers) {
      if (!map.getLayer(id)) continue;
      if (!previousFilters.has(id)) previousFilters.set(id,map.getFilter(id) ?? null);
      const previous = previousFilters.get(id);
      const filters=[];
      if(previous)filters.push(previous);
      if(wing)filters.push(['!',['within',wing]]);
      if(hiddenIds.length)filters.push(['!',matches(identity,hiddenIds)]);
      map.setFilter(id,filters.length>1?['all',...filters]:filters[0]??null);
    }
  }
  map.on('pocketaccountpins',({placeIds})=>refreshFilters(placeIds));
  map.on('pocketmallplaces',()=>refreshFilters(map.savvyAccountPlaceIds??[]));

  let loading=false;
  function load(){
    if(loading||map.getZoom()<11)return;
    loading=true;
    loadCityPlaces().then(data=>{
      map.getSource(source).setData(data);map.off('moveend',load);
    }).catch(error=>{loading=false;console.warn('Taipei place index',error.message);});
  }
  map.on('moveend',load);
  load();

  let loadingSavvy=false,removed=false,expiryTimer;
  async function updateSavvy(){
    const {featureCollection,nextExpiry}=await loadVerifiedSavvyMapPins();
    if(removed)return;
    const pinSource=map.getSource(savvySource);
    if(!pinSource)return;
    pinSource.setData(featureCollection);
    if(Number.isFinite(nextExpiry))expiryTimer=setTimeout(updateSavvy,Math.min(2**31-1,Math.max(0,nextExpiry-Date.now())));
  }
  function loadSavvy(){
    if(loadingSavvy||map.getZoom()<savvyZoom)return;
    loadingSavvy=true;
    map.off('moveend',loadSavvy);
    void updateSavvy();
  }
  map.on('moveend',loadSavvy);
  map.on('remove',()=>{removed=true;clearTimeout(expiryTimer);});
  loadSavvy();
}

export function nearbyPlaces(map,coordinates){
  if(map.getZoom()<16||!map.getLayer(nearby))return [];
  const center=map.project(coordinates);
  const layers=[nearby,savvyNearby].filter(id=>map.getLayer(id));
  const hits=map.queryRenderedFeatures(center,{layers});
  const unique=new Map();
  for(const hit of hits){
    const p=hit.properties;
    const point=hit.geometry.coordinates;
    if(map.project(point).dist(center)<=6)unique.set(p.placeId,{...p,point});
  }
  return [...unique.values()];
}
