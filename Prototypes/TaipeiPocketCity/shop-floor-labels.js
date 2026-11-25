import groups from './taipei-shop-floors.js';

const labels=new Map();
for(const [label,kind,ids] of groups){
  for(const id of ids.split(' '))labels.set('poi/'+kind+'/'+id,label);
}

export function shopFloorLabel(id,source){
  return source==='Savvy' ? undefined : labels.get(id);
}

export function additionalShopFloor(id,source,...shown){
  const floor=shopFloorLabel(id,source);
  if(!floor)return;
  if(shown.some(text=>text?.split(' · ').includes(floor)))return;
  // An existing business address can already show a precise floor in Latin or Chinese.
  const precise=shown.flatMap(text=>Array.from(
    (text??'').normalize('NFKC').matchAll(/(?:^|[^A-Z0-9])(?:((?:B|地下)[1-9][0-9]?)(?:F|樓|層)?|([1-9][0-9]?)(?:F|樓|層))(?![A-Z0-9])/gi),
    ([,below,above])=>below?below.toUpperCase().replace('地下','B'):above+'F',
  ));
  const matches={
    '地面層':()=>precise.includes('1F'),
    '樓上':()=>precise.some(label=>label.endsWith('F')&&label!=='1F'),
    '地下樓層':()=>precise.some(label=>label.startsWith('B')),
  };
  const redundant=matches[floor]?.()??floor.split('、').every(label=>precise.includes(label));
  return redundant?undefined:floor;
}
