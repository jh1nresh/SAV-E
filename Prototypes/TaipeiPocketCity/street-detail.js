import {bouncePhotoPin} from './photo-pin-motion.js';
import {createPlaceCallout} from './place-callout.js?v=shop-floor-1';
import {originalPlacePhoto,photoPlaces} from './place-photos.js';
import {cityPlaceID} from './savvy-place-sources.js';
import {placeButtonIcon} from './place-pins.js?v=category-badges-1';
import {StreetPeople} from './street-people.js';
import {StreetScenery} from './street-scenery.js?v=trail-guideposts-1';

const isDistrict=key=>key.endsWith('-district');
const limitsStreetLabels=key=>isDistrict(key)||key==='xinyi-link';

function addGroundColors(map,prefix,data,anatomy,blendRoadOutline,hybrid,projectedShadows){
  map.addSource(`${prefix}-ground`,{type:'geojson',data,buffer:256});
  const beneathShadow=map.getLayer('atlas-shadows')?'atlas-shadows':'survey';
  const colors=anatomy?[
    ['plaza','#ddc3a2',.85],['grass','#aec084',.93],['water','#70a3a5',1],
    ['road-edge','#c5b8a4',1],['road','#9c9da0',1],
    ['walk-edge','#bdab8b',1],['walk','#ead8b9',1],
    ['shadow','#545b70',.18],['crossing','#f2e5ce',.97],
  ]:hybrid?[
    ['wood','#78a86d',.76],['plaza','#dfb79a',.88],['grass','#acd473',.95],['water','#69afbd',1],
    ['road-edge','#c8bba7',1],['road','#828b9d',1],
    ['walk-edge','#c79570',.92],['walk','#f2d5a7',1],
    ['shadow','#3b528e',.28],['crossing','#fff1d5',.98],
  ]:[
    ['wood','#9eae79',.61],['plaza','#dcb595',.85],['grass','#a6bd76',.93],['water','#5b9fa6',1],
    ['road-edge','#c6b7a5',1],['road','#929299',1],
    ['walk-edge','#cd9d73',1],['walk','#efd0a5',1],
    ['shadow','#465c90',.22],['crossing','#fff1d5',.97],
  ];
  if(data.features.some(f=>f.properties.kind==='lane'))colors.splice(-1,0,['lane','#f6edd4',.83]);
  for(const [kind,color,opacity] of colors){
    if(kind==='shadow'&&projectedShadows)continue;
    map.addLayer({
      id:`${prefix}-${kind}`,type:'fill',source:`${prefix}-ground`,minzoom:16.65,
      filter:['==',['get','kind'],kind],
      paint:{
        'fill-color':color,'fill-outline-color':color,
        'fill-antialias':blendRoadOutline||!['road-edge','road'].includes(kind),
        'fill-opacity':['interpolate',['linear'],['zoom'],16.65,0,kind==='crossing'?17.02:17.35,['*',opacity,['coalesce',['get','coverage'],1]]],
      },
    },['wood','plaza','grass','water'].includes(kind)?'building':beneathShadow);
  }
}

const roadLabelZoom=17;
// The city street register uses 復. The source map also has a way spelled 複.
const roadNameAliases=new Map([['光複南路473巷11弄','光復南路473巷11弄']]);
const baseRoadName=['coalesce',['get','name:zh-Hant'],['get','name:zh'],['get','name:nonlatin'],['get','name'],''];

function roadLabelsFor(streets){
  const positionsByName=new Map();
  const labelsByScene=new Map();
  // Keep the authored focal views when a district-wide label is nearby.
  const ordered=[...streets].sort((a,b)=>Number(isDistrict(a.key))-Number(isDistrict(b.key)));
  for(const {key,data} of ordered){
    const labels=data.roads.features.flatMap(feature=>{
      const point=feature.geometry.coordinates;
      const {name:sourceName,rank=0}=feature.properties;
      const name=roadNameAliases.get(sourceName)??sourceName;
      const positions=positionsByName.get(name)??[];
      const spacing=rank<=3?260:165;
      if(positions.some(([lng,lat])=>Math.hypot((point[0]-lng)*100770,(point[1]-lat)*111195)<spacing))return [];
      positions.push(point);
      positionsByName.set(name,positions);
      return [name===sourceName?feature:{...feature,properties:{...feature.properties,name}}];
    });
    labelsByScene.set(key,{type:'FeatureCollection',features:labels});
  }
  // A vector-tile road can cross the district boundary. Suppress its base label
  // only when it passes a nearby authored label of the same name.
  const canonicalBaseName=['match',baseRoadName,...[...roadNameAliases].flat(),baseRoadName];
  const coveredRoad=['match',canonicalBaseName];
  for(const [name,coordinates] of positionsByName){
    coveredRoad.push(name,['<',['distance',{type:'MultiPoint',coordinates}],86]);
  }
  coveredRoad.push(false);
  return {labelsByScene,coveredRoad};
}

export function addStreetDetail(map,{Marker,MercatorCoordinate},districts,firstLabel,anatomy,hybrid,shadows,continuousRoads=false){
  const scenes=[],pins=[];
  let localLife=null;
  const allScenes=()=>localLife?[...scenes,localLife]:scenes;
  const baseRoadLayers=map.getStyle().layers.filter(l=>l['source-layer']==='transportation_name');
  let umbrellaShare=0;

  function createScene({key,data},labels){
    const prefix=`street-${key}`;
    const linked=limitsStreetLabels(key);
    const useAnatomy=key==='101'&&anatomy;
    const model=new StreetPeople(prefix,data.origin,data.paths,key==='xinyi-link'?17.05:16.65,hybrid);
    model.paused=paused;
    model.umbrellaShare=umbrellaShare;
    addGroundColors(map,prefix,data.ground,useAnatomy,!linked&&key!=='yongchun',hybrid,!!shadows);
    const scenery=new StreetScenery(prefix,data.origin,data.objects,MercatorCoordinate,useAnatomy,hybrid);
    map.addLayer(scenery,firstLabel);
    map.addLayer(model,firstLabel);
    map.addSource(`${prefix}-roads`,{type:'geojson',data:labels});
    map.addLayer({
      id:`${prefix}-road-labels`,type:'symbol',source:`${prefix}-roads`,minzoom:roadLabelZoom,
      layout:{
        'symbol-placement':'point','text-field':['get','name'],
        'text-font':['Noto Sans Bold'],'text-size':['interpolate',['linear'],['zoom'],roadLabelZoom,12,19,16],
        'text-rotation-alignment':'viewport','text-pitch-alignment':'viewport','text-padding':5,'text-allow-overlap':!linked,'symbol-sort-key':['coalesce',['get','rank'],0],
      },
      paint:{'text-color':'#2d4c55','text-halo-color':'#fff8e9','text-halo-width':1.7},
    });
    return {key,data,model,scenery};
  }

  if(shadows){
    map.addSource('atlas-shadows',{
      type:'raster',tileSize:512,minzoom:shadows.zoom,maxzoom:shadows.zoom,bounds:shadows.bounds,
      tiles:[new URL('./data/shadows/',import.meta.url).href+'{x}/{y}.png'],
    });
    map.addLayer({
      id:'atlas-shadows',type:'raster',source:'atlas-shadows',minzoom:16.4,
      paint:{
        'raster-opacity':['interpolate',['linear'],['zoom'],16.4,0,17.75,1],
        'raster-fade-duration':0,
      },
    },'survey');
  }

  let accountPlaceIds=new Set();
  map.on('pocketaccountpins',event=>{
    accountPlaceIds=new Set(event.placeIds);
    update();
  });
  const callout=createPlaceCallout(map);
  const pause=document.querySelector('#street-motion');
  let mappedStores=new Set(),visiblePlaceFilter,isContextPin;
  let paused=false;
  const motion=matchMedia('(prefers-reduced-motion: reduce)');
  const photoIds=new Set(photoPlaces.map(place=>place.placeId));
  const pinsFor=({key,data})=>data.places
    .filter(place=>key==='photos'||!photoIds.has(cityPlaceID(place)))
    .map(place=>({key,place,point:place.point,minZoom:place.minZoom??16.65,priority:place.priority??0,active:false}));
  function createMarker(pin){
    const {place}=pin;
    const button=document.createElement('button');
    button.type='button';
    button.className='street-pin';
    button.dataset.kind=place.kind;
    button.dataset.place=place.placeId??place.id??place.name;
    button.dataset.name=place.name;
    const {canvas,color}=placeButtonIcon(place.kind);
    button.style.setProperty('--pin',color);
    button.append(canvas,document.createTextNode(place.name));
    button.setAttribute('aria-controls','place-card');
    button.setAttribute('aria-expanded','false');
    const photo=originalPlacePhoto(place);
    if(photo){
      button.classList.add('photo-pin');
      button.setAttribute('aria-label',place.name+'，查看照片');
      const thumb=document.createElement('img');
      thumb.alt='';
      thumb.decoding='async';
      thumb.src=photo.src;
      const badge=document.createElement('span');
      badge.className='photo-badge';
      badge.append(thumb);
      thumb.onerror=()=>badge.replaceChildren(canvas);
      const label=document.createElement('span');
      label.className='photo-title';
      label.textContent=place.name;
      button.replaceChildren(badge,label);
    }
    button.addEventListener('click',event=>{
      event.stopPropagation();
      if(callout.trigger===button){callout.dismiss();return;}
      callout.open(place,button);
    });
    pin.button=button;
    pin.marker=new Marker({element:button,anchor:photo?'bottom':'left',offset:photo?[0,0]:[-15.5,0]}).setLngLat(place.point);
  }

  function update(){
    const zoom=map.getZoom();
    const viewport=map.getContainer();
    const width=viewport.clientWidth;
    const height=viewport.clientHeight;
    const available=[];
    const photoRects=[];
    const bounds=map.getBounds();
    const near=allScenes().some(({model})=>model.isActive(bounds));
    pause.hidden=!near||motion.matches;
    for(const pin of pins){
      const photo=pin.key==='photos';
      let visible=!accountPlaceIds.has(cityPlaceID(pin.place))&&zoom>=pin.minZoom&&bounds.contains(pin.point)&&
        (!visiblePlaceFilter||visiblePlaceFilter(pin.point,cityPlaceID(pin.place)))&&(photo||!mappedStores.has(pin.place.id??pin.place.name));
      if(visible){
        const {x,y}=map.project(pin.point);
        const length=pin.place.name.length;
        const rectangle=photo?[x-22,y-44,x+28+length*13,y]:[x-16,y-14,x+Math.max(length*7+24,length*12+20),y+14];
        if(photo){
          visible=!(x<0||x>width||y<0||y>height)&&!photoRects.some(([x1,y1,x2,y2])=>
            rectangle[0]<x2&&rectangle[2]>x1&&rectangle[1]<y2&&rectangle[3]>y1);
          if(visible)photoRects.push(rectangle);
        }else if(limitsStreetLabels(pin.key)&&callout.trigger!==pin.button){
          visible=rectangle[0]>=9&&rectangle[2]<=width-9&&rectangle[1]>=0&&rectangle[3]<=height
            &&!available.some(([x1,y1,x2,y2])=>rectangle[0]<x2&&rectangle[2]>x1&&rectangle[1]<y2&&rectangle[3]>y1);
        }
        if(visible)available.push(rectangle);
      }
      if(visible){
        if(!pin.marker)createMarker(pin);
        pin.button.classList.toggle('mall101-context-pin',!!isContextPin?.(pin.point));
      }
      if(visible===pin.active)continue;
      pin.active=visible;
      if(visible){
        pin.marker.addTo(map);
        if(photo)bouncePhotoPin(pin.button.querySelector('.photo-badge'),0);
      }
      else{
        pin.marker.remove();
        if(photo){
          pin.marker=null;
          pin.button=null;
        }
      }
    }
  }
  function addStreets(rows){
    const existing=new Set(scenes.map(scene=>scene.key));
    const incoming=rows.filter(row=>!existing.has(row.key));
    if(!incoming.length)return;
    // The continuous atlas supplies canonical road lines at street zoom. Avoid rebuilding
    // a city-wide distance expression and invalidating all basemap tiles on every district pan.
    const {labelsByScene,coveredRoad}=continuousRoads
      ? {labelsByScene:new Map(incoming.map(({key,data})=>[key,limitsStreetLabels(key)?{type:'FeatureCollection',features:[]}:data.roads])),coveredRoad:[]}
      : roadLabelsFor([...scenes,...incoming]);
    for(const {key} of continuousRoads?[]:scenes){
      map.getSource(`street-${key}-roads`).setData(labelsByScene.get(key));
    }
    for(const row of incoming){
      scenes.push(createScene(row,labelsByScene.get(row.key)));
      pins.push(...pinsFor(row));
    }
    pins.sort((a,b)=>Number(isDistrict(a.key))-Number(isDistrict(b.key))||a.priority-b.priority);
    if(coveredRoad.length>3){
      for(const layer of baseRoadLayers){
        map.setFilter(layer.id,['all',layer.filter??true,['!', ['all',['>=',['zoom'],roadLabelZoom],coveredRoad]]]);
      }
    }
    update();
  }
  map.on('move',update);
  motion.addEventListener('change',update);
  pause.addEventListener('click',()=>{
    paused=!paused;
    pause.setAttribute('aria-pressed',String(paused));
    pause.textContent=paused?'播放行人':'暫停行人';
    for(const {model} of allScenes())model.paused=paused;
    map.triggerRepaint();
  });
  pins.push(...pinsFor({key:'photos',data:{places:photoPlaces.map(place=>({...place,kind:place.categoryLabel,minZoom:15.8}))}}));
  addStreets(districts);
  update();
  function state(){
    const details=Object.fromEntries(allScenes().map(({key,model,scenery})=>[key,{
      people:model.count,umbrellas:model.umbrellas,playing:model.playing,firstPosition:model.firstPosition,scenery:scenery.drawnTriangles,
      pins:pins.filter(pin=>pin.key===key&&pin.active).length,
    }]));
    const states=Object.values(details);
    return {
      people:states.reduce((n,state)=>n+state.people,0),playing:states.some(state=>state.playing),
      firstPosition:states.find(state=>state.firstPosition)?.firstPosition??null,
      pins:states.reduce((n,state)=>n+state.pins,0),scenery:states.reduce((n,state)=>n+state.scenery,0),
      scenes:details,
    };
  }
  function setLocalLife(records){
    if(localLife){
      map.removeLayer(localLife.model.id);
      map.removeLayer(localLife.scenery.id);
      localLife=null;
    }
    if(records.length){
      const objects=Object.values(Object.assign({},...records.map(r=>r.objects)));
      const paths=Object.values(Object.assign({},...records.map(r=>r.paths)));
      const origin=map.getCenter().toArray();
      const model=new StreetPeople('city170',origin,paths,16.65,hybrid);
      model.paused=paused;
      model.umbrellaShare=umbrellaShare;
      const scenery=new StreetScenery('city170',origin,objects,MercatorCoordinate,false,hybrid);
      map.addLayer(scenery,firstLabel);
      map.addLayer(model,firstLabel);
      localLife={key:'city170',model,scenery};
    }
    update();
  }
  const focalRoads=roadLabelsFor(scenes.filter(scene=>!limitsStreetLabels(scene.key))).coveredRoad;
  function hasFocalPin(feature){
    if(feature.properties.kind!=='poi')return false;
    const [lng,lat]=feature.geometry.coordinates;
    const normalize=name=>(name??'').normalize('NFKC').replace(/\s/g,'').toLowerCase();
    const label=normalize(feature.properties.name);
    if(!label)return false;
    return pins.some(pin=>{
      if(!pin.active || Math.hypot((pin.point[0]-lng)*100850,(pin.point[1]-lat)*110800)>=12)return false;
      if(pin.key==='photos'&&feature.id===pin.place.placeId)return true;
      const title=normalize(pin.button.dataset.name);
      const [short,long]=title.length<label.length?[title,label]:[label,title];
      return title===label || (short.length>=3 && long.startsWith(short) && long.slice(short.length).endsWith('店'));
    });
  }
  return {state,addStreets,setVisiblePlaceFilter(filter,contextPin){visiblePlaceFilter=filter;isContextPin=contextPin;update();},closeMappedPlace:callout.close,openMappedPlace:callout.open,setLocalLife,hasFocalPin,authoredRoads:focalRoads.length>3?focalRoads:false,setMappedStores(ids){
    mappedStores=new Set(ids.map(id=>id.replace(/^poi\/(node|way|relation)\//,'osm-$1-')));
    update();
  },setRain(share){
    umbrellaShare=share;
    for(const {model} of allScenes())model.umbrellaShare=umbrellaShare;
    map.triggerRepaint();
  }};
}
