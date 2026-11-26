import {additionalShopFloor,shopFloorLabel} from './shop-floor-labels.js';
import {frontageCamera} from './fuxing-block.js?v=frontage-views-1';
import {streetShopProperties} from './shop-trades.js?v=neighborhood-services-1';
import {loadCityPlaces} from './city-place-index.js?v=friendly-frontages-1';
import {isDuplicateShop,withOpenShopAddress} from './taipei-open-shop-catalog.js';
import {readPocketCityAsset} from './pocket-city-atlas.js';
import {loadVerifiedSavvyMapPins} from './savvy-place-sources.js';
import {frontageSearchRow} from './taipei-frontage-pack.js?v=friendly-frontages-1';

const fold=s=>s.normalize('NFKC').toLocaleLowerCase().replaceAll('臺','台').replaceAll('竪','豎')
  .replace(/([一二三四五六七八九])段/g,(_,n)=>('一二三四五六七八九'.indexOf(n)+1)+'段')
  .replace(/(\d+)號之(\d+)/g,'$1-$2號').replace(/(\d+)之(\d+)號/g,'$1-$2號').replace(/\s+/g,'');
export function surveyedShopCamera(row,views,viewport){
  const [, , ,x,y,angle,id]=row;
  if(!Number.isFinite(angle) || !views || !Object.hasOwn(views.frontageViews,id))return;
  const area={center:[x,y],bearing:0,pitch:12,mobilePitch:12,zoom:18.8,mobileZoom:18.8};
  if(!viewport?.clientHeight)return area;
  const compact=viewport.clientWidth<600;
  const {mobile,desktop}=views.frontageViewHeights;
  const heights=compact?mobile:desktop;
  const common=views.frontageViews[id];
  const partial=common<0 ? views.frontagePartialViews?.[id] : null;
  // MapLibre's eye distance scales as canvas height / 2^zoom. Match a ray actually checked
  // by the solver instead of interpolating between unobstructed rays through another building.
  let zoom, selected, best=Infinity;
  for(const [index,reference] of heights.entries()){
    const preset=views.frontageViewPresets[partial?partial[(compact?0:mobile.length)+index]:common];
    if(!preset)continue;
    const offset=Math.log2(viewport.clientHeight/reference), adjusted=preset[compact?3:2]+offset;
    if(adjusted>views.frontageViewMaxZoom || adjusted<17.55 || Math.abs(offset)>=best)continue;
    best=Math.abs(offset);
    zoom=adjusted;
    selected=preset;
  }
  if(!selected)return area;
  return {...frontageCamera(x,y,angle,selected),zoom,mobileZoom:zoom,verifiedFrontage:true};
}

export function addShopSearch(map,locate,heritage,openPlace,focusFront,searchNation){
  let pending,frontages,verifiedPending,verifiedEntries,cameras,cameraRequest,cameraAttempts=0;
  const forms=document.querySelectorAll('.shop-search');
  function entry(row){
    return {row,key:fold(row[0]),area:fold([row[1],row[2],row[7]?.address,row[7]?.categoryLabel,shopFloorLabel(row[6],row[7]?.source)].filter(Boolean).join(' '))};
  }
  function indexedRow(feature){
    const place=streetShopProperties(feature.properties);
    return [place.name,place.district??'',(place.detail??'').replace(place.district??'','').replace(/^\s*·\s*/,'').trim(),
      ...feature.geometry.coordinates,null,place.placeId,place];
  }
  function loadVerifiedEntries(){
    return verifiedPending??=loadVerifiedSavvyMapPins().then(({featureCollection})=>{
      verifiedEntries=featureCollection.features.map(feature=>entry(indexedRow(feature)));
      return verifiedEntries;
    }).catch(()=>{
      verifiedEntries=[];
      return verifiedEntries;
    });
  }
  function loadCameras(){
    if(cameraRequest)return cameraRequest;
    const url=new URL('./taipei-frontage-cameras.js?v=friendly-frontages-1',import.meta.url);
    if(cameraAttempts)url.searchParams.set('retry',String(cameraAttempts));
    cameraAttempts++;
    cameraRequest=import(url.href).then(views=>{cameras=views;}).catch(()=>{cameraRequest=null;});
    return cameraRequest;
  }
  function load(){
    frontages??=readPocketCityAsset('city170-frontages/search').catch(error=>{frontages=null;throw error;});
    return pending??=Promise.allSettled([frontages,loadCityPlaces()]).then(([shops,city])=>{
      if(shops.status==='rejected'||city.status==='rejected')pending=null;
      const rows=shops.value??[];
      const indexed=new Map((city.value?.features??[]).filter(f=>f.properties.name).map(f=>[f.properties.placeId,f]));
      const records=new Map(heritage.map(row=>[row[6],row]));
      for(const row of rows){
        const id=row[6];
        if(!records.has(id)&&!isDuplicateShop(id))records.set(id,[...frontageSearchRow(row),indexed.has(id)?streetShopProperties(indexed.get(id).properties):undefined]);
      }
      for(const [id,feature] of indexed){
        if(records.has(id))continue;
        records.set(id,indexedRow(feature));
      }
      return [...records.values()].map(entry);
    }).catch(error=>{pending=null;throw error;});
  }
  for(const form of forms){
    const input=form.querySelector('input'),list=form.querySelector('.shop-options');
    let serial=0;
    const hide=()=>{serial++;list.replaceChildren();list.hidden=true;};
    function render(entries,query,terms){
      const {lng,lat}=map.getCenter();
      const now=Date.now();
      const hits=entries.filter(e=>(e.row[7]?.sourcesExpireAt??Infinity)>now&&terms.every(t=>e.key.includes(t)||e.area.includes(t)))
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
        detail.textContent=heritagePlace?.address||[district,street,additionalShopFloor(id,heritagePlace?.source,street),angle!==null?'店面':district||street?'':'地點']
          .filter(Boolean).join(' · ');
        button.append(title,detail);
        button.addEventListener('click',()=>{
          if((heritagePlace?.sourcesExpireAt??Infinity)<=Date.now()){void update();return;}
          for(const f of forms){f.querySelector('input').value=name;f.querySelector('.shop-options').hidden=true;}
          hide();document.querySelector('.mobile').open=false;
          if(heritagePlace?.camera){locate(heritagePlace.camera);return;}
          const surveyed=surveyedShopCamera(row,cameras,map.getCanvas());
          if(angle!==null && focusFront?.(row))return;
          const a=(angle??0)*Math.PI/180,offset=angle===null?0:2.5;
          locate(heritagePlace?.mapView??surveyed??{center:[x+Math.cos(a)*offset/100780,y+Math.sin(a)*offset/110800],
            bearing:angle===null?0:270-angle,zoom:heritagePlace?.mapZoom??(angle===null?18.4:20.75),
            mobileZoom:heritagePlace?.mapZoom??(angle===null?18.4:20.45),pitch:42,mobilePitch:42});
          const osm=id.match(/^poi\/(node|way|relation)\/(\d+)$/);
          const inspected=id.startsWith('inspection/');
          const commerce=id.startsWith('commerce/');
          openPlace(withOpenShopAddress({id,point:[x,y],name,categoryLabel:'店家地點',
            source:osm?'OpenStreetMap':inspected?'臺北市衛生局':commerce?'臺北市商業處':undefined,
            url:osm?'https://www.openstreetmap.org/'+osm[1]+'/'+osm[2]:
              inspected||commerce?'https://data.taipei/dataset/detail?id='+(inspected?'59579c19-a561-4564-8c0f-545bfb32c0f6':'0d09e03e-bb11-4213-a9c8-6bfd392fbb16'):undefined,
            ...heritagePlace,retainMapCamera:!heritagePlace?.mapView&&surveyed?.verifiedFrontage===true,
            detail:heritagePlace?.source==='Savvy'?heritagePlace.detail
              :heritagePlace?.detail||[district,street].filter(Boolean).join(' · ')||''}));
        });
        list.append(button);
      }
    }
    async function update(){
      const turn=++serial,query=input.value.trim();
      if(!query){hide();return;}
      const terms=query.split(/\s+/).map(fold);
      let nearby=[],saved=[],national=[];
      function display(){
        if(turn!==serial||list.contains(document.activeElement))return;
        const byId=new Map();
        for(const e of [...saved,...nearby,...national])if(!byId.has(e.row[6])&&!isDuplicateShop(e.row[6]))byId.set(e.row[6],e);
        render([...byId.values()],query,terms);
      }
      const results=await Promise.allSettled([
        Promise.all([load(),loadCameras()]).then(([rows])=>{nearby=rows;display();}),
        loadVerifiedEntries().then(rows=>{saved=rows;if(rows.length)display();}),
        searchNation?.(query,map.getCenter()).then(rows=>{national=rows.map(entry);if(rows.length)display();}),
      ]);
      if(turn===serial&&results.every(r=>r.status==='rejected')){
        list.hidden=false;list.textContent='地點資料暫時無法載入，請再搜尋一次';
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
