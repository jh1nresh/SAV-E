import {readTaiwanJSON} from './taiwan-coverage.js';
import {placePinStyle} from './place-pins.js';

const collection=features=>({type:'FeatureCollection',features});
const layer='tw-public-places';
const labels={platform:'乘車月台',stop_position:'停靠站',bus_stop:'公車站',bus_station:'公車站',
  subway_entrance:'捷運出入口',tram_stop:'電車站',ferry_terminal:'渡輪碼頭',bicycle_rental:'自行車租借站',
  parking:'停車場',clothes:'服飾店',hairdresser:'髮廊',beverages:'飲品店',bar:'酒吧',tea:'茶店',pastry:'糕餅店',
  attraction:'景點',marketplace:'市場',post_office:'郵局',clinic:'診所',dentist:'牙醫',hostel:'旅宿',
  restaurant:'餐廳',cafe:'咖啡店',school:'學校',convenience:'便利商店',bakery:'麵包店',
  fast_food:'速食',place_of_worship:'宗教場所',station:'車站',hotel:'旅宿',museum:'博物館',hospital:'醫院',
  pharmacy:'藥局',park:'公園',library:'圖書館',supermarket:'超市',viewpoint:'觀景點',college:'學校',university:'大學'};
const shardCache=new Map();
function readShard(key){
  if(!shardCache.has(key)){
    if(shardCache.size>=16)shardCache.delete(shardCache.keys().next().value);
    const pending=readTaiwanJSON('places/'+key+'.json.gz');
    shardCache.set(key,pending);
    pending.catch(()=>{if(shardCache.get(key)===pending)shardCache.delete(key);});
  }
  return shardCache.get(key);
}
export function placeRecord(row){
  const [name,category,id,lng,lat,code]=row;
  const type={n:'node',w:'way',r:'relation'}[id[0]];
  return {name,category,code,categoryLabel:labels[category]??'地圖地點',placeId:'poi/'+type+'/'+id.slice(1),
    url:'https://www.openstreetmap.org/'+type+'/'+id.slice(1),source:'OpenStreetMap',point:[lng,lat]};
}
function tileAt(lon,lat){
  return [Math.floor((lon+180)/360*1024),Math.floor((1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)*512)];
}
export function addTaiwanPlaces(map,exclude,open){
  map.addSource(layer,{type:'geojson',data:collection([]),maxzoom:18});
  const style=placePinStyle(map);
  map.addLayer({id:layer,type:'symbol',source:layer,minzoom:16.6,...style},
    map.getLayer('city-atlas-places')?'city-atlas-places':undefined);
  map.on('click',layer,event=>{
    const f=event.features?.[0];
    if(!f||event.defaultPrevented)return;
    const upper=['city-atlas-pins','city-atlas-places','city-atlas-locators'].filter(id=>map.getLayer(id));
    if(upper.length&&map.queryRenderedFeatures(event.point,{layers:upper}).length)return;
    event.preventDefault();
    open({...f.properties,id:f.properties.placeId,point:f.geometry.coordinates});
  });
  let revision=0,manifest,removed=false;
  async function refresh(){
    const turn=++revision;
    if(map.getZoom()<16.6){map.getSource(layer)?.setData(collection([]));return;}
    const bounds=map.getBounds(),[w,n]=tileAt(bounds.getWest(),bounds.getNorth()),[e,s]=tileAt(bounds.getEast(),bounds.getSouth());
    manifest??=readTaiwanJSON('places/index.json').then(m=>new Set(m.tiles)).catch(error=>{manifest=null;throw error;});
    const keys=await manifest,requests=[];
    if(turn!==revision||removed)return;
    for(let x=w;x<=e;x++)for(let y=n;y<=s;y++)if(keys.has(x+'-'+y))requests.push(readShard(x+'-'+y));
    const packs=await Promise.allSettled(requests);
    if(turn!==revision||removed)return;
    const features=[];
    for(const pack of packs)if(pack.status==='fulfilled'){
      for(const row of pack.value){
        const [,category,,x,y]=row;
        if(!bounds.contains([x,y]))continue;
        const p=placeRecord(row);
        if(exclude(p,map.getZoom()))continue;
        const {point,...properties}=p;
        properties.rank=['station','hospital','museum','school'].includes(category)?1:4;
        features.push({type:'Feature',properties,geometry:{type:'Point',coordinates:point}});
      }
    }
    map.getSource(layer).setData(collection(features));
  }
  const update=()=>refresh().catch(error=>console.warn('Taiwan places',error));
  map.on('moveend',update);map.on('city-atlas-pins-changed',update);map.on('remove',()=>{removed=true;revision++;});update();
}

let searchWorker,next=0;
const waiting=new Map();
export async function searchTaiwanEntries(query,center){
  if(!searchWorker){
    searchWorker=new Worker(new URL('./taiwan-search-worker.js?v=alpine-1',import.meta.url),{type:'module'});
    searchWorker.onmessage=({data})=>{waiting.get(data.id)?.(data);waiting.delete(data.id);};
    searchWorker.onerror=()=>{
      for(const resolve of waiting.values())resolve({entries:[],refs:[]});
      waiting.clear();searchWorker.terminate();searchWorker=null;
    };
  }
  const id=++next;
  const result=await new Promise(resolve=>{waiting.set(id,resolve);searchWorker.postMessage({id,query,center});});
  const hydrated=await Promise.allSettled(result.refs.map(async({key,pos,area})=>{
    const p=placeRecord((await readShard(key))[pos]);
    return [p.name,area,p.categoryLabel,...p.point,null,p.placeId,p];
  }));
  return [...result.entries,...hydrated.filter(row=>row.status==='fulfilled').map(row=>row.value)];
}
