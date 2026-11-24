import {readPocketCityAsset} from './pocket-city-atlas.js';

export function addCityStreetLoading(map,districts,addStreets){
  const active=new Set(), loading=new Set(), retryAfter=new Map();

  async function load(key){
    loading.add(key);
    try{
      const data=await readPocketCityAsset(`city-streets/${key}`);
      if(!data?.ground?.features||!data?.roads?.features||!Array.isArray(data.paths)||
         !Array.isArray(data.objects)||!Array.isArray(data.places))throw Error('Invalid Pocket City district');
      addStreets([{key,data}]);
      active.add(key);
    }catch(error){
      retryAfter.set(key,Date.now()+2500);
      console.warn(`Pocket City ${key}: ${error.message}`);
    }finally{
      loading.delete(key);
    }
  }

  function refresh(){
    if(map.getZoom()<15.65)return;
    const [[west,south],[east,north]]=map.getBounds().toArray();
    for(const {key,bounds:[w,s,e,n]} of districts){
      if(active.has(key)||loading.has(key)||(retryAfter.get(key)||0)>Date.now())continue;
      if(w<=east&&e>=west&&s<=north&&n>=south)load(key);
    }
  }

  map.on('moveend',refresh);
  refresh();
}
