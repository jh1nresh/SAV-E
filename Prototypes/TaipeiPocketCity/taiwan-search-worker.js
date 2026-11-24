import {readTaiwanJSON} from './taiwan-coverage.js';
import {sceneryCard} from './taiwan-scenery.js?v=2';

const fold=text=>text.normalize('NFKC').toLowerCase().replaceAll('臺','台').replace(/\s/g,'');
let loading;
async function buildIndex(){
  const [towns,names,nature,rivers]=await Promise.all([readTaiwanJSON('town-index.json'),
    readTaiwanJSON('places/names.json.gz'),readTaiwanJSON('scenery/places.geojson.gz'),
    readTaiwanJSON('scenery/river-search.json.gz')]);
  const areas=new Map(towns.map(t=>[t.code,{name:t.county+' '+t.name,key:fold(t.county+t.name),center:t.anchor}]));
  const entries=towns.map(t=>({name:t.name,area:t.county,point:t.anchor,card:{name:t.name,categoryLabel:'鄉鎮市區',
    source:'內政部國土測繪中心',url:'https://data.gov.tw/dataset/7441',mapZoom:12.5},id:'town/'+t.code}));
  for(const f of nature.features){
    const card=sceneryCard(f.properties,f.geometry.coordinates);
    if(!card)continue;
    const zoom={peak:13.8,lake:13,reservoir:13,wetland:14,river:14,island:13.5}[f.properties.k]??15.5;
    entries.push({name:card.name,area:card.categoryLabel,point:card.point,id:card.placeId,card:{...card,mapZoom:zoom}});
  }
  for(const [name,k,id,x,y] of rivers){
    const card=sceneryCard({n:name,k,id},[x,y]);
    entries.push({name,area:card.categoryLabel,point:card.point,id:card.placeId,card:{...card,mapZoom:12}});
  }
  return {names:names.map(([name,code,key,pos])=>({name:fold(name),area:areas.get(code),key,pos})),
    entries:entries.map(e=>({...e,key:fold(e.name),region:fold(e.area)}))};
}
let latest=0;
self.onmessage=async({data:{id,query,center}})=>{
  latest=id;
  try{
    loading??=buildIndex().catch(error=>{loading=null;throw error;});
    const {names,entries}=await loading;
    if(id!==latest){self.postMessage({id,entries:[],refs:[]});return;}
    const terms=query.trim().split(/\s+/).map(fold),exact=fold(query);
    const match=(key,area)=>terms.every(t=>key.includes(t)||area.includes(t));
    const score=(key,x,y)=>(key===exact?0:key.startsWith(terms[0])?1:2)*1e7+
      Math.hypot((x-center.lng)*.91,y-center.lat);
    const local=entries.filter(e=>match(e.key,e.region)).map(e=>[score(e.key,...e.point),e])
      .sort((a,b)=>a[0]-b[0]).slice(0,12).map(([,e])=>[e.name,e.area,'',...e.point,null,e.id,e.card]);
    const best=[];
    for(const r of names){
      if(!r.area||!match(r.name,r.area.key))continue;
      const rank=score(r.name,...r.area.center);
      if(best.length===12&&rank>=best[11].rank)continue;
      best.push({rank,key:r.key,pos:r.pos,area:r.area.name});
      best.sort((a,b)=>a.rank-b.rank);best.length=Math.min(12,best.length);
    }
    self.postMessage({id,entries:local,refs:best});
  }catch{self.postMessage({id,entries:[],refs:[]});}
};
