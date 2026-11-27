import {loadCreatorCatalog,appendCreatorPlaces,withoutCreatorDuplicates} from './creator-place-sources.js';
import {cityLandmarks,districtLandmarks} from './taipei-priority-places.js';
import {readPocketCityAsset} from './pocket-city-atlas.js';
import {addressShopFeature,addedOpenShops,canonicalShopId,isDuplicateShop} from './taipei-open-shop-catalog.js';
import {withShopFacts} from './taipei-frontage-pack.js?v=friendly-frontages-1';
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
  return pending??=Promise.all([readPocketCityAsset('city-place-index'),loadCreatorCatalog()]).then(([data,creator])=>appendCreatorPlaces({
    ...data,features:data.features.filter(feature=>!isDuplicateShop(feature.id))
      .map(feature=>addressShopFeature(withShopFacts(feature))).concat(metroExitFeatures,addedOpenShops),
  },creator)).catch(error=>{pending=null;throw error;});
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
    'icon-size':['interpolate',['linear'],['zoom'],11,.82,17,.88,19,.94],
    'text-size':['interpolate',['linear'],['zoom'],11,12,17,12.5,20,14],
    'text-padding':['interpolate',['linear'],['zoom'],11,32,14,28,16,23,17,20,19,11],
  };
  map.addSource(savvySource,{type:'geojson',data:{type:'FeatureCollection',features:[]},maxzoom:19});
  map.addLayer({id:names,source,type:'symbol',minzoom:11,maxzoom:17.8,
    filter:['all',named,notExit,['>=',['zoom'],revealZoom],['any',['<',['zoom'],16],['!',photoIds]]],
    layout,paint:pin.paint},before);
  // Detailed street layers take over individual POIs. The index continues to name
  // outdoor areas represented by polygons in the detailed street packs.
  map.addLayer({id:outdoorNames,source,type:'symbol',minzoom:17.8,
    filter:['all',named,['any',matches(category,outdoor),['has','creatorSource']]],layout,paint:pin.paint},before);
  map.addLayer({id:metroExitLayer,source,type:'symbol',minzoom:18.2,
    filter:['has','exitLabel'],
    layout:{...pin.layout,'icon-image':'place-pin-transit','icon-size':.8,
      'text-field':['get','exitLabel'],'text-size':12,
      'text-padding':10,'symbol-sort-key':0},
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
    const hiddenIds=[...new Set([...Array.from(placeIds,canonicalShopId),...(map.savvyMallAdjacentPlaceIds??[])])];
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
    const [{featureCollection,nextExpiry},creator]=await Promise.all([loadVerifiedSavvyMapPins(),loadCreatorCatalog()]);
    if(removed)return;
    const pinSource=map.getSource(savvySource);
    if(!pinSource)return;
    pinSource.setData(withoutCreatorDuplicates(featureCollection,creator));
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
