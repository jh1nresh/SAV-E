import rows from './taipei-metro-exit-data.js';

export const metroExitLayer='taipei-metro-exits';
export const metroExitDataset='https://data.taipei/dataset/detail?id=cfa4778c-62c1-497b-b704-756231de348b';
export const metroExitPlaceId=(station,number)=>'metro-exit/'+encodeURIComponent(station)+'/'+number;
const station101='台北101/世貿站';
export const mallStreetExit4=metroExitPlaceId(station101,'4');

function exitLabel(number){
  if(number==='0')return '出口';
  return /^\d/.test(number)?number+' 號出口':number+' 出口';
}

const cards=new Map();
export const metroExitFeatures=rows.map(([station,number,lon,lat,district,accessible])=>{
  const placeId=metroExitPlaceId(station,number);
  const label=exitLabel(number);
  const point=[lon,lat];
  const properties={
    placeId,name:'捷運 '+station.replace('/','／')+' '+label,category:'subway_entrance',
    categoryLabel:'捷運出入口',district,exitLabel:label,accessible,
    detail:[district,accessible?'無障礙出口':''].filter(Boolean).join(' · '),
    source:'臺北捷運',
    url:station===station101?'https://web.metro.taipei/pages2026/WebStation/100':metroExitDataset,
  };
  cards.set(placeId,{...properties,point});
  return {type:'Feature',id:placeId,properties,geometry:{type:'Point',coordinates:point}};
});
export const metroExitCard=id=>cards.get(id);

// Keep the authoritative exit once, while retaining unmatched entrances elsewhere.
const compact=name=>(name??'').replace(/^捷運\s*/,'').replace(/[\s／/]/g,'');
export function isDuplicateMetroExit(place){
  if(!place.point||!place.name?.includes('出口'))return false;
  const name=compact(place.name);
  return metroExitFeatures.some(f=>compact(f.properties.name)===name &&
    Math.hypot((f.geometry.coordinates[0]-place.point[0])*100780,
      (f.geometry.coordinates[1]-place.point[1])*110800)<35);
}
