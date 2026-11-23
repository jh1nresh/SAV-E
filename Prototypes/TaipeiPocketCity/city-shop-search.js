import {loadCityPlaces} from './city-place-index.js';
import {readPocketCityAsset} from './pocket-city-atlas.js';

const fold=s=>s.normalize('NFKC').toLocaleLowerCase().replaceAll('臺','台').replace(/\s+/g,'');
export function addShopSearch(map,locate,heritage,openPlace,focusFront){
  let pending,frontages;
  const forms=document.querySelectorAll('.shop-search');
  function load(){
    frontages??=readPocketCityAsset('city170-frontages/search').catch(error=>{frontages=null;throw error;});
    return pending??=Promise.allSettled([frontages,loadCityPlaces()]).then(([shops,city])=>{
      if(shops.status==='rejected'||city.status==='rejected')pending=null;
      const rows=shops.value??[];
      const indexed=new Map((city.value?.features??[]).filter(f=>f.properties.name).map(f=>[f.properties.placeId,f]));
      const records=new Map(heritage.map(row=>[row[6],row]));
      for(const row of rows){
        const id=row[6];
        if(!records.has(id))records.set(id,[...row.slice(0,7),indexed.get(id)?.properties]);
      }
      for(const [id,feature] of indexed){
        if(records.has(id))continue;
        const place=feature.properties;
        records.set(id,[place.name,place.district??'',(place.detail??'').replace(place.district??'','').replace(/^\s*·\s*/,'').trim(),...feature.geometry.coordinates,null,id,place]);
      }
      return [...records.values()].map(row=>({
        row,key:fold(row[0]),area:fold([row[1],row[2],row[7]?.categoryLabel].filter(Boolean).join(' ')),
      }));
    }).catch(error=>{pending=null;throw error;});
  }
  for(const form of forms){
    const input=form.querySelector('input'),list=form.querySelector('.shop-options');
    let serial=0;
    const hide=()=>{serial++;list.replaceChildren();list.hidden=true;};
    async function update(){
      const turn=++serial,query=input.value.trim();
      if(!query){hide();return;}
      const terms=query.split(/\s+/).map(fold);
      try{
        const entries=await load();
        if(turn!==serial)return;
        const {lng,lat}=map.getCenter();
        const hits=entries.filter(e=>terms.every(t=>e.key.includes(t)||e.area.includes(t)))
          .map(e=>{
            const [, , ,x,y]=e.row;
            return {row:e.row,priority:e.key===fold(query)?0:e.key.startsWith(terms[0])?1:2,
              distance:Math.hypot((x-lng)*.906,y-lat)};
          }).sort((a,b)=>a.priority-b.priority||a.distance-b.distance).slice(0,12);
        list.replaceChildren();list.hidden=false;
        if(!hits.length){list.textContent='找不到符合的地點';return;}
        for(const {row} of hits){
          const [name,district,street,x,y,angle,id,heritagePlace]=row;
          const button=document.createElement('button');
          button.type='button';
          const title=document.createElement('strong'),detail=document.createElement('small');
          title.textContent=name;
          detail.textContent=[district,street,angle===null?'地點':'店面'].filter(Boolean).join(' · ');
          button.append(title,detail);
          button.addEventListener('click',()=>{
            for(const f of forms){f.querySelector('input').value=name;f.querySelector('.shop-options').hidden=true;}
            hide();document.querySelector('.mobile').open=false;
            if(angle!==null && focusFront?.(row))return;
            const a=(angle??0)*Math.PI/180,offset=angle===null?0:2.5;
            locate({center:[x+Math.cos(a)*offset/100780,y+Math.sin(a)*offset/110800],
              bearing:angle===null?0:270-angle,zoom:angle===null?18.4:20.75,
              mobileZoom:angle===null?18.4:20.45,pitch:42,mobilePitch:42});
            const osm=id.match(/^poi\/(node|way|relation)\/(\d+)$/);
            const inspected=id.startsWith('inspection/');
            const commerce=id.startsWith('commerce/');
            openPlace({id,point:[x,y],name,categoryLabel:'店家地點',
              source:osm?'OpenStreetMap':inspected?'臺北市衛生局':commerce?'臺北市商業處':undefined,
              url:osm?'https://www.openstreetmap.org/'+osm[1]+'/'+osm[2]:
                inspected||commerce?'https://data.taipei/dataset/detail?id='+(inspected?'59579c19-a561-4564-8c0f-545bfb32c0f6':'0d09e03e-bb11-4213-a9c8-6bfd392fbb16'):undefined,
              ...heritagePlace,detail:[district,street].filter(Boolean).join(' · ')||heritagePlace?.detail||''});
          });
          list.append(button);
        }
      }catch{
        if(turn===serial){list.hidden=false;list.textContent='地點資料暫時無法載入，請再搜尋一次';}
      }
    }
    input.addEventListener('input',update);
    if(input.value && input===document.activeElement)update();
    input.addEventListener('focus',()=>{if(input.value)update();});
    form.addEventListener('keydown',e=>{
      if(e.key==='Escape'){input.focus();hide();return;}
      const buttons=[...list.querySelectorAll('button')];
      if(list.hidden||!buttons.length)return;
      const i=buttons.indexOf(document.activeElement);
      if(e.key==='ArrowDown'||e.key==='ArrowUp'){
        e.preventDefault();
        buttons[Math.max(0,Math.min(buttons.length-1,i+(e.key==='ArrowDown'?1:-1)))].focus();
      }else if(e.key==='Enter' && i===-1){e.preventDefault();buttons[0].click();}
    });
    form.addEventListener('focusout',e=>{if(!form.contains(e.relatedTarget))hide();});
  }
}
