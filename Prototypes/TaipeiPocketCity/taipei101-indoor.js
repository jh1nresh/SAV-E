import {mallStreetExit4,metroExitLayer} from './taipei-metro-exits.js';
import {mallAdjacentTenants} from './taipei101-mall-tenants.js';
import {addMallWayfinding,mallMetroExit4} from './taipei101-wayfinding.js?v=b1-arrival-1';

// All plans, marks and camera changes share the outdoor map's geographic coordinates.
const prefix='taipei101-indoor';

const empty=()=>({type:'FeatureCollection',features:[]});
const svgNS='http://www.w3.org/2000/svg';
const pointKinds=['shop','facility','entrance'];
const adjacentPoints=[...mallAdjacentTenants,mallMetroExit4];
const transitExit=['==',['get','category'],'subway_entrance'];
const outdoorPlaces=['taipei-outdoor-names','taipei-place-names','taipei-place-neighbors','taipei-savvy-place-names','taipei-savvy-place-neighbors',
  metroExitLayer,'city170-shop-names','city170-poi-labels','city170-poi-dots','city-atlas-pins','city-atlas-places','city-atlas-context-places',
  'tw-public-places','poi_r1','city170-vendor-awnings'];
const zone=[121.5636,25.0332,121.5653,25.0348]; // Early loading envelope only; selection uses the supplied outline.

function contextPins(map){
  const original=[];
  return function setMuted(muted){
    if(!muted){
      for(const [id,property,value] of original.splice(0)){
        if(map.getLayer(id))map.setPaintProperty(id,property,value);
      }
      return;
    }
    for(const id of outdoorPlaces){
      const type=map.getLayer(id)?.type;
      const opacity=type==='symbol'?['icon-opacity']:type==='circle'&&!id.endsWith('-neighbors')
        ?['circle-opacity','circle-stroke-opacity']:[];
      const paints=type==='symbol'?[['text-color','#645d50']]:[];
      for(const property of opacity){
        const value=map.getPaintProperty(id,property)??1;
        // Keep the atlas's zoom fades at the top of the expression.
        const scaled=Array.isArray(value)&&value[0]==='interpolate'
          ?value.map((part,i)=>i>=4&&i%2===0?['*',part,.36]:part)
          :['*',value,.36];
        paints.push([property,scaled]);
      }
      for(const [property,value] of paints){
        original.push([id,property,map.getPaintProperty(id,property)]);
        map.setPaintProperty(id,property,value);
      }
    }
  };
}

export function insideMall([x,y],ring){
  let inside=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const [a,b]=ring[i],[c,d]=ring[j];
    if((b>y)!==(d>y)&&x<(c-a)*(y-b)/(d-b)+a)inside=!inside;
  }
  return inside;
}

export function floorData(venue,label){
  return venue.levels.find(level=>level.label===label)?.features??empty();
}

export function indoorCamera(center,bearing,zoom){
  return {center,bearing,zoom,pitch:0};
}

function pointColor(){
  return ['case',transitExit,'#a33c36',['match',['get','kind'],'facility','#58847d','entrance','#8b7848','#ad7d27']];
}

const b1StorefrontImage='taipei101-din-tai-fung-facade';
const b1StorefrontId='node/2718780533';

function addB1StorefrontImage(map){
  if(map.hasImage(b1StorefrontImage))return;
  const canvas=document.createElement('canvas');
  canvas.width=76;
  canvas.height=50;
  const ctx=canvas.getContext('2d');
  ctx.scale(2,2);
  function paint(color,x,y,width,height){
    ctx.fillStyle=color;
    ctx.fillRect(x,y,width,height);
  }
  // Draw the photographed entrance as a screen-sized elevation. The mapped
  // branch position remains the anchor and the illustration shows no footprint.
  paint('#695648',1,4,36,18);
  paint('#e6d6bd',2,5,34,16);
  paint('#ccc0a7',2,5,34,2);
  paint('#557570',22,9,12,12);
  paint('#8cae9f',23,10,10,3);
  paint('#ddcba8',27,10,1,11);
  paint('#b34840',5,11,14,4);
  paint('#d76d5c',6,11,12,1);
  paint('#8d7462',2,21,34,1);
  map.addImage(b1StorefrontImage,ctx.getImageData(0,0,canvas.width,canvas.height),{pixelRatio:2});
}

function addPlanLayers(map,venue,namesVisible){
  map.addSource(prefix+'-plan',{type:'geojson',data:empty(),maxzoom:21,tolerance:0});
  map.addSource(prefix+'-places',{type:'geojson',data:empty(),maxzoom:21,tolerance:0});
  const add=(key,type,source,options)=>map.addLayer({id:prefix+'-'+key,type,source:prefix+source,...options});
  add('paper','fill','-plan',{paint:{'fill-color':'#faf3df','fill-opacity':1}});
  add('edge','line','-plan',{paint:{'line-color':'#af8b4b','line-width':2}});
  const wayfinding=addMallWayfinding(map,namesVisible);
  add('rooms','fill','-places',{filter:['==',['geometry-type'],'Polygon'],paint:{'fill-color':'#e8dbbc','fill-outline-color':'#a99472'}});
  add('corridor','line','-places',{filter:['==',['geometry-type'],'LineString'],paint:{'line-color':'#b2a586','line-width':3}});
  add('dots','circle','-places',{filter:['all',['==',['geometry-type'],'Point'],['in',['get','kind'],['literal',pointKinds]]],
    paint:{'circle-radius':['interpolate',['linear'],['zoom'],18,['case',transitExit,6,4],21,['case',transitExit,8,6]],'circle-color':pointColor(),
      'circle-stroke-color':'#fffaf0','circle-stroke-width':1.8}});
  addB1StorefrontImage(map);
  add('storefront','symbol','-places',{minzoom:17.6,
    // GeoJSON tile feature IDs may be numeric. The place ID property is stable.
    filter:['==',['get','id'],b1StorefrontId],
    layout:{'icon-image':b1StorefrontImage,'icon-anchor':'bottom','icon-offset':[0,-2],
      'icon-size':['interpolate',['linear'],['zoom'],17.6,.76,19,1],
      'icon-allow-overlap':true,'icon-ignore-placement':true}});
  add('names','symbol','-places',{minzoom:17.45,filter:['all',['==',['geometry-type'],'Point'],['has','name']],
    layout:{visibility:namesVisible?'visible':'none','text-field':['get','name'],'text-font':['Noto Sans Bold'],'text-size':['interpolate',['linear'],['zoom'],18,12,21,15],
      'text-anchor':'top','text-offset':[0,.7],'text-padding':9,'text-max-width':8,
      'symbol-sort-key':['case',transitExit,-1,['match',['get','kind'],'shop',0,'facility',2,3]]},
    paint:{'text-color':['case',transitExit,'#7f332c','#695536'],'text-halo-color':'#faf3df','text-halo-width':1.7}});
  // Replace independent indoor POIs with the venue overview. Neighbouring streets retain their own labels.
  map.savvyMallFootprint=venue.footprint;
  const outside=['!',['within',venue.footprint]];
  for(const id of outdoorPlaces){
    if(map.getLayer(id))map.setFilter(id,['all',map.getFilter(id)??true,outside]);
  }
  return wayfinding;
}

export function addTaipei101Indoor(map,{stage,Marker,setCutaway,openPlace,closePlace,startFloor,namesVisible=true,load}){
  const control=stage.querySelector('#mall101-control'),toggle=control.querySelector('[data-floor-toggle]');
  const menu=control.querySelector('[data-floor-list]'),leave=control.querySelector('[data-floor-exit]');
  const floorNote=control.querySelector('[data-floor-note]');
  const directory=control.querySelector('details'),summary=control.querySelector('[data-directory-summary]'),shops=control.querySelector('[data-directory]');
  let venue,ring,center,current,active=false,loading=false,removed=false,suppressed=false,lastPitch=0;
  let guide,outline,badge,marker,wayfinding,pendingSearch,entranceMarks=[],returnFloor=startFloor;
  const muteContextPins=contextPins(map);
  const entryZoom=()=>stage.clientWidth && stage.clientWidth<600 ? 17.6 : 18.35;
  const exitZoom=()=>entryZoom()-.5;
  const mappedFeatures=new Map();
  const adjacentPlaceIds=[...adjacentPoints.map(f=>'poi/'+f.id),mallStreetExit4];
  const mappedId=id=>String(id??'').replace(/^poi\//,'').replace(/^osm-(node|way|relation)-/,'$1/');
  let coveredIds=new Set((map.savvyAccountPlaceIds??[]).map(mappedId));
  function updateFloorPoints(){
    if(!active||!current)return;
    const data=floorData(venue,current);
    const visible=data.features.filter(f=>f.geometry.type!=='Point'||!coveredIds.has(mappedId(f.properties.id??f.id)));
    map.getSource(prefix+'-places').setData(visible.length===data.features.length?data:{...data,features:visible});
  }
  function onAccountPins({placeIds}){
    coveredIds=new Set(placeIds.map(mappedId));
    updateFloorPoints();
  }
  const mappedPlace=feature=>({
    id:feature.properties.id??feature.id,placeId:'poi/'+(feature.properties.id??feature.id),name:feature.properties.name,
    point:feature.geometry.coordinates,category:feature.properties.category,
    indoorFloor:current,categoryLabel:[venue.name,current].join(' · '),
    detail:feature.properties.detail||feature.properties.categoryLabel||'',source:feature.properties.source,url:feature.properties.url,
  });
  function setNames(visible){
    namesVisible=visible;
    if(venue)map.setLayoutProperty(prefix+'-names','visibility',visible?'visible':'none');
    wayfinding?.setNames(visible);
  }
  function isPinVisible(point,id){
    if(!active)return true;
    if(id===mallStreetExit4)return false;
    const known=mappedFeatures.get(mappedId(id));
    if(known?.properties.adjacent||insideMall(point,ring))return known?.properties.level===current;
    return true;
  }
  function isStreetPinVisible(point,id){
    // The legacy 101 street scene already carries the same Din Tai Fung branch.
    return !(active&&adjacentPoints.some(feature=>feature.id===mappedId(id)||(id&&feature.properties.streetPinId===id)))
      &&isPinVisible(point,id);
  }
  const isContextPin=point=>active&&!insideMall(point,ring);
  function openSearchPlace(place){
    const [x,y]=place.point;
    pendingSearch=x>=zone[0]&&x<=zone[2]&&y>=zone[1]&&y<=zone[3]?place:null;
    if(!pendingSearch||map.savvySavedOnly){pendingSearch=null;openPlace(place);return;}
    // Opening a #414 drawer can pan the camera. Let the search camera reach the venue first.
    if(!map.isMoving())onMove();
  }
  function focusMappedPlace(feature){
    const point=feature.geometry.coordinates;
    let zoom=Math.max(map.getZoom(),entryZoom()+.05);
    let focus=point;
    if(feature.properties.adjacent){
      // Keep the wing and adjoining tenant in view while remaining in floor mode.
      const towardTenant=center.map((value,i)=>value+(point[i]-value)*.3);
      focus=insideMall(towardTenant,ring)?towardTenant:center;
      zoom=Math.min(zoom,entryZoom()+.2);
    }
    map.jumpTo(indoorCamera(focus,map.getBearing(),zoom),{pocketPlaceReveal:true});
  }
  function showAdjacentPoints(visible){
    map.savvyMallAdjacentPlaceIds=visible?adjacentPlaceIds:[];
    map.fire('pocketmallplaces');
  }
  const closeMenu=()=>{
    menu.hidden=true;toggle.setAttribute('aria-expanded','false');
  };
  function selectFloor(label){
    if(!venue.levels.some(f=>f.label===label))return;
    current=label;
    floorNote.hidden=!wayfinding.show(label);
    floorNote.textContent=label==='B1'?'樓層示意 · 鼎泰豐在捷運 4 號出口旁':'樓層示意';
    directory.open=false;
    const entries=venue.directory?.[label]??[];
    summary.textContent=entries.length?'本層店家（'+entries.length+'）':'本層店家';
    shops.replaceChildren();
    const addLink=(li,name,url)=>{
      const link=document.createElement('a');
      link.textContent=name;link.href=url;link.target='_blank';link.rel='noopener noreferrer';
      li.append(link);
      return link;
    };
    function openFromDirectory(feature){
      directory.open=false;
      summary.focus({preventScroll:true});
      focusMappedPlace(feature);
      openPlace(mappedPlace(feature));
    }
    const located=floorData(venue,label).features.filter(f=>f.geometry.type==='Point'
      &&f.properties.kind==='shop'&&f.properties.level===label
      &&(f.properties.adjacent||insideMall(f.geometry.coordinates,ring)));
    for(const entry of entries){
      if(!entry.url?.startsWith('https://'))continue;
      const li=document.createElement('li');
      // Only the same official shop record on this floor can link to a mapped point.
      const matches=located.filter(f=>f.properties.floorSourceUrl===entry.url);
      if(matches.length===1){
        const button=document.createElement('button'),hint=document.createElement('small');
        button.type='button';button.textContent=entry.name;
        hint.textContent='在地圖查看';button.append(hint);
        button.addEventListener('click',()=>openFromDirectory(matches[0]));
        li.className='mall101-located-shop';
        li.append(button);
        addLink(li,'官網',entry.url).setAttribute('aria-label',entry.name+'的官網');
        shops.prepend(li);
      }else{
        addLink(li,entry.name,entry.url);
        shops.append(li);
      }
    }
    const floorLink=document.createElement('li');
    addLink(floorLink,'查看 101 官方樓層圖','https://www.taipei-101.com.tw/tw/shopping/floorcon/'+encodeURIComponent(label));
    shops.append(floorLink);
    if(label===mallMetroExit4.properties.level){
      const row=document.createElement('li');
      row.className='mall101-located-shop';
      const button=document.createElement('button');
      button.type='button';button.textContent=mallMetroExit4.properties.name;
      button.addEventListener('click',()=>openFromDirectory(mallMetroExit4));
      row.append(button);
      shops.prepend(row);
    }
    updateFloorPoints();
    toggle.textContent=label;toggle.setAttribute('aria-label',label+'，選擇樓層');
    for(const button of menu.querySelectorAll('[data-floor]'))button.setAttribute('aria-pressed',String(button.dataset.floor===label));
    closeMenu();closePlace();
    stage.dispatchEvent(new CustomEvent('mall101-floor',{detail:{floor:label}}));
  }
  function enter(label,centerOnMall=false){
    if(!venue||map.savvySavedOnly)return;
    suppressed=false;
    if(!active){
      active=true;lastPitch=map.getPitch();
      setCutaway(true,ring);stage.classList.add('mall101-inside');muteContextPins(true);showAdjacentPoints(true);
      control.hidden=false;
      map.getSource(prefix+'-plan').setData({type:'Feature',geometry:venue.footprint,properties:{}});
      const first=venue.levels.find(f=>f.label===label)??venue.levels.find(f=>f.label==='1F')??venue.levels[0];
      selectFloor(first.label);
      map.jumpTo(indoorCamera(centerOnMall?center:map.getCenter(),map.getBearing(),centerOnMall?entryZoom()+.05:map.getZoom()));
    }
    drawGuide();
  }
  function exit(explicit=false){
    if(!active)return;
    active=false;suppressed=explicit;returnFloor=null;closeMenu();directory.open=false;control.hidden=true;closePlace();
    map.getSource(prefix+'-places').setData(empty());map.getSource(prefix+'-plan').setData(empty());
    wayfinding.show(null);
    stage.classList.remove('mall101-inside');setCutaway(false);muteContextPins(false);showAdjacentPoints(false);
    stage.dispatchEvent(new CustomEvent('mall101-floor',{detail:{floor:null}}));
    if(explicit)map.jumpTo({pitch:lastPitch,zoom:Math.min(map.getZoom(),exitZoom()-.2)});
    else if(map.getPitch()===0&&lastPitch&&map.getZoom()>16.5)map.jumpTo({pitch:lastPitch});
    drawGuide();
  }
  function refreshVisibility(){
    if(map.savvySavedOnly){
      pendingSearch=null;
      if(active)exit();
      drawGuide();
    }else onMove();
  }
  function onMove(event){
    if(removed||map.savvySavedOnly||event?.pocketPlaceReveal)return;
    if(!venue){void prepare();return;}
    const coords=map.getCenter().toArray(),inVenue=insideMall(coords,ring);
    if(!inVenue||map.getZoom()<exitZoom())suppressed=false;
    if(pendingSearch&&!map.isMoving()){
      const selected=pendingSearch;
      pendingSearch=null;
      const known=mappedFeatures.get(mappedId(selected.placeId))??mappedFeatures.get(mappedId(selected.id));
      const adjacent=known?.properties.adjacent;
      if((adjacent||(inVenue&&insideMall(selected.point,ring)))&&map.getZoom()>=exitZoom()){
        if(known){
          if(active)selectFloor(known.properties.level);
          else enter(known.properties.level,adjacent);
          if(adjacent)focusMappedPlace(known);
          openPlace({...selected,...mappedPlace(known)});
        }else{
          // An unassigned saved/search result still owns its outdoor card.
          if(active)exit();
          suppressed=true;
          openPlace(selected);
        }
        drawGuide();return;
      }
      if(active)exit();
      openPlace(selected);return;
    }
    if(active && (!inVenue||map.getZoom()<exitZoom()))exit();
    else if(!active&&!suppressed&&inVenue&&map.getZoom()>=entryZoom())enter(returnFloor);
    drawGuide();
  }
  function drawGuide(){
    if(!guide||!badge)return;
    const b=map.getBounds(),visible=!map.savvySavedOnly&&!active&&map.getZoom()>=14.7&&
      !(b.getEast()<zone[0]||b.getNorth()<zone[1]||b.getWest()>zone[2]||b.getSouth()>zone[3]);
    guide.style.display=visible?'':'none';badge.hidden=!visible;
    if(!visible)return;
    const points=ring.map(c=>map.project(c));
    const verts=points.map(p=>p.x.toFixed(1)+','+p.y.toFixed(1)).join(' ');
    if(outline.getAttribute('points')!==verts)outline.setAttribute('points',verts);
    for(const {el,coords} of entranceMarks){
      const p=map.project(coords);
      el.setAttribute('cx',p.x);el.setAttribute('cy',p.y);
      el.style.display=map.getZoom()>=16.4?'':'none';
    }
  }
  function handleHit(event){
    if(!venue||map.savvySavedOnly||event.target!==map.getCanvas()||map.getZoom()<14.7)return;
    const box=map.getCanvas().getBoundingClientRect(),point=[event.clientX-box.left,event.clientY-box.top];
    const coords=map.unproject(point).toArray();
    const inVenue=insideMall(coords,ring);
    if(!active){
      if(!inVenue)return;
      event.stopImmediatePropagation();
      enter(null,true);return;
    }
    const features=map.queryRenderedFeatures([[point[0]-9,point[1]-9],[point[0]+9,point[1]+9]],
      {layers:['names','dots','storefront','rooms','corridor'].map(k=>prefix+'-'+k)});
    const hit=features.find(f=>f.properties.name&&(inVenue||f.properties.adjacent));
    if(!inVenue&&!hit)return;
    event.stopImmediatePropagation();
    if(!hit){closePlace();return;}
    const p=hit.properties;
    if(p.adjacent){
      const feature=mappedFeatures.get(mappedId(p.id??hit.id));
      if(feature?.properties.level===current)openPlace(mappedPlace(feature));
      return;
    }
    openPlace({id:p.id??hit.id,placeId:'poi/'+(p.id??hit.id),name:p.name,
      point:hit.geometry.type==='Point'?hit.geometry.coordinates:coords,
      indoorFloor:current,categoryLabel:[venue.name,current].join(' · '),detail:p.detail??p.categoryLabel??'',
      source:p.source,url:p.url});
  }
  async function prepare(){
    if(loading||venue||removed||map.savvySavedOnly||map.getZoom()<14.7)return;
    const b=map.getBounds();
    if(b.getEast()<zone[0]||b.getNorth()<zone[1]||b.getWest()>zone[2]||b.getSouth()>zone[3])return;
    loading=true;
    try{
      const loaded=await load();
      const labels=[...new Set([...loaded.levels.map(l=>l.label),...Object.keys(loaded.directory??{})])];
      const rank=label=>label.startsWith('B')?-parseInt(label.slice(1),10):parseInt(label,10);
      const data={...loaded,levels:labels.sort((a,b)=>rank(a)-rank(b)).map(label=>{
        const floor=floorData(loaded,label);
        const adjacent=adjacentPoints.filter(f=>f.properties.level===label);
        return {label,features:{...floor,features:floor.features.concat(adjacent)}};
      })};
      if(removed)return;
      ring=data.footprint.coordinates[0];
      const xs=ring.map(c=>c[0]),ys=ring.map(c=>c[1]);
      center=[(Math.min(...xs)+Math.max(...xs))/2,(Math.min(...ys)+Math.max(...ys))/2];
      wayfinding=addPlanLayers(map,data,namesVisible);
      venue=data;
      for(const level of data.levels)for(const f of level.features.features)if(f.geometry.type==='Point')mappedFeatures.set(mappedId(f.properties.id??f.id),f);
      for(const {label} of [...data.levels].reverse()){
        const button=document.createElement('button');button.type='button';button.textContent=label;button.dataset.floor=label;
        button.addEventListener('click',()=>{selectFloor(label);toggle.focus({preventScroll:true});});
        menu.append(button);
      }
      guide=document.createElementNS(svgNS,'svg');guide.style.display='none';guide.classList.add('mall101-guide');guide.setAttribute('aria-hidden','true');
      outline=document.createElementNS(svgNS,'polygon');guide.append(outline);
      for(const f of data.entrances?.features??[]){
        if(f.geometry.type!=='Point')continue;
        const el=document.createElementNS(svgNS,'circle');el.setAttribute('r','3.5');guide.append(el);
        entranceMarks.push({el,coords:f.geometry.coordinates});
      }
      map.getCanvasContainer().append(guide);
      badge=document.createElement('button');badge.type='button';badge.hidden=true;badge.className='mall101-badge';
      badge.setAttribute('aria-label',data.name+'，查看樓層');
      const glyph=document.createElement('span');glyph.className='mall101-bag';glyph.setAttribute('aria-hidden','true');
      const name=document.createElement('span');name.textContent=data.name;badge.append(glyph,name);
      badge.addEventListener('click',event=>{event.stopPropagation();enter(null,true);toggle.focus({preventScroll:true});});
      marker=new Marker({element:badge,anchor:'center'}).setLngLat(center).addTo(map);
      onMove();
    }catch(error){
      console.warn('台北101樓層資料',error);
      if(pendingSearch){const selected=pendingSearch;pendingSearch=null;openPlace(selected);}
    }
    finally{loading=false;}
  }
  toggle.addEventListener('click',()=>{
    directory.open=false;menu.hidden=!menu.hidden;toggle.setAttribute('aria-expanded',String(!menu.hidden));
    if(!menu.hidden)menu.querySelector('[aria-pressed="true"]')?.focus({preventScroll:true});
  });
  directory.addEventListener('toggle',()=>{if(directory.open)closeMenu();});
  leave.addEventListener('click',()=>{exit(true);badge?.focus({preventScroll:true});});
  control.addEventListener('keydown',e=>{if(e.key==='Escape'){closeMenu();toggle.focus({preventScroll:true});}});
  map.getCanvasContainer().addEventListener('click',handleHit,true);
  map.on('pocketaccountpins',onAccountPins);
  map.on('moveend',onMove);map.on('render',drawGuide);
  map.on('remove',()=>{removed=true;map.off('pocketaccountpins',onAccountPins);map.off('moveend',onMove);map.off('render',drawGuide);
    map.getCanvasContainer().removeEventListener('click',handleHit,true);marker?.remove();guide?.remove();});
  void prepare();
  return {setNames,isPinVisible,isStreetPinVisible,isContextPin,openSearchPlace,refreshVisibility,state:()=>({ready:!!venue,active,floor:active?current:null}),exit};
}
