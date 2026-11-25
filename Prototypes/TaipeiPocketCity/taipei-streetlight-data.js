import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-audit-1';

export const streetlightZoom=18.25;

export async function loadStreetlightPacks(){
  const url=new URL('./assets/taipei-streetlights.json.gz?v=1',import.meta.url);
  const response=await fetch(url,{priority:'low'});
  if(!response.ok||!response.body)throw Error('Taipei streetlight asset '+response.status);
  const data=await decodeMapJSON(response);
  if(!data?.packs||!data.receipt?.total)throw Error('Invalid Taipei streetlight inventory');
  return data.packs;
}

export function streetlightObjects(rows){
  return Object.fromEntries(rows.map(([east,north,height,bearing,style])=>[
    'streetlight/'+east+'/'+north,
    [east/1e7,north/1e7,'street-light',height/100,bearing,style],
  ]));
}
