import {withShopFacts} from './taipei-frontage-pack.js?v=survey-store-1';
import {addArcadeFloors} from './taipei-arcade-floors.js?v=sections-2';
import {addCityHydrants} from './city170-hydrants.js?v=street-furniture-1';
import {addBusShelters} from './city170-bus-shelters.js';
import {addCityBenches} from './city170-benches.js';
import {addCityAirfield} from './city170-airfield.js';
import {surfaceFeature} from './city170-ground.js';
import {bikeDockParts} from './city170-bike-docks.js';
import {courtDetails} from './city170-courts.js?v=court-nets-1';
import {pinLabelColor} from './place-pins.js?v=category-badges-1';
import {addCityPlaceIndex,cityPlaceLayers,nearbyPlaces} from './city-place-index.js?v=shop-address-1';
import {addCity170Style, city170PlaceLayers} from './city170-style.js?v=point-icons-5';
import {streetShopProperties} from './shop-trades.js?v=point-icons-5';
import {readPocketCityAsset} from './pocket-city-atlas.js?v=taipei-audit-1';
import {withMarketScenery} from './taipei-market-stalls.js';

const collection = features => ({type: 'FeatureCollection', features});
const overlaps = ([w,s,e,n], [left,bottom,right,top]) => w <= right && e >= left && s <= top && n >= bottom;

function clipStreetSegment(a,b,view){
  let start=0,end=1;
  for(let axis=0;axis<2;axis++){
    const span=b[axis]-a[axis],min=view[axis],max=view[axis+2];
    if(!span){
      if(a[axis]<min||a[axis]>max)return null;
      continue;
    }
    const low=(min-a[axis])/span, high=(max-a[axis])/span;
    start=Math.max(start,Math.min(low,high));
    end=Math.min(end,Math.max(low,high));
    if(start>=end)return null;
  }
  return [start,end];
}

function along(a,b,t){
  return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
}

// Use the longest on-screen run per name. MapLibre follows its direction
// and keeps the resulting caption upright as the user rotates the map.
export function cityStreetLabels(features,map,geographicBounds){
  const {clientWidth:width,clientHeight:height}=map.getContainer();
  if(width<=8||height<=8)return [];
  const screen=[4,4,width-4,height-4];
  const chosen=new Map();
  for(const feature of features){
    const {name,kind,category}=feature.properties;
    if(!name||(kind!=='road'&&kind!=='walk'))continue;
    const key=name.normalize('NFKC').replaceAll('台','臺').replace(/([一二三四五六七八九])段/g,(_,n)=>`${'一二三四五六七八九'.indexOf(n)+1}段`);
    const {type,coordinates}=feature.geometry;
    const lines=type==='LineString'?[coordinates]:type==='MultiLineString'?coordinates:[];
    const rank=['motorway','trunk','primary','secondary'].includes(category)?0:kind==='road'?1:2;
    for(const line of lines){
      let points=[];
      let length=0;
      const flush=()=>{
        if(length>(chosen.get(key)?.length??0))chosen.set(key,{name,rank,length,points});
        points=[];
        length=0;
      };
      for(let i=1;i<line.length;i++){
        const a=line[i-1],b=line[i];
        const bounds=clipStreetSegment(a,b,geographicBounds);
        if(!bounds){flush();continue;}
        const left=map.project(along(a,b,bounds[0])),right=map.project(along(a,b,bounds[1]));
        const start=[left.x,left.y],end=[right.x,right.y];
        const visible=clipStreetSegment(start,end,screen);
        if(!visible){flush();continue;}
        const from=along(start,end,visible[0]),to=along(start,end,visible[1]);
        const pixels=Math.hypot(to[0]-from[0],to[1]-from[1]);
        if(!pixels)continue;
        const last=points.at(-1);
        if(last&&Math.hypot(last[0]-from[0],last[1]-from[1])>.05)flush();
        if(!points.length)points.push(from);
        points.push(to);
        length+=pixels;
      }
      flush();
    }
  }
  return [...chosen.values()].map(({name,rank,points})=>({type:'Feature',properties:{name,rank},
    geometry:{type:'LineString',coordinates:points.map(point=>map.unproject(point).toArray())}}));
}

const heritagePage=id=>'https://tcmb.culture.tw/zh-tw/detail?id='+id+'&indexCode=BOCH_CountryCulture_12';
const cityRoster='https://www.travel.taipei/file/34265/';
const dihuaPlaces=[
  [85,121.509924,25.056381,'迪化街歷史街屋','歷史店屋','國家文化記憶庫',heritagePage('20060217000002')],
  [87,121.509918,25.056431,'德成藥行舊址','歷史店屋','國家文化記憶庫',heritagePage('20220711000001')],
  [91,121.509906,25.056526,'利生堂蔘藥行','蔘藥行','台北通','https://id.taipei/tpcd/offers/coupons/52cedf24-4205-45fa-a968-82e1910cbcb0'],
  [93,121.509900,25.056575,'黃裕生藥行','蔘藥行','臺北旅遊網',cityRoster],
  [95,121.509894,25.056625,'老成記街屋','歷史立面示意','百耘堂經銷名錄','https://bwt100.com/index_down.php?hstyle=9&sele=hstyle'],
  [97,121.509889,25.056671,'正元參藥行','蔘藥行','臺北旅遊網',cityRoster],
];

export const dihuaSearch=[
  ...dihuaPlaces.map(([id,x,y,name,categoryLabel,source,url])=>[name,'大同區','迪化街一段',x,y,185,'dihua/'+id,{categoryLabel,source,url}]),
  ['爵林堅果','大同區','迪化街一段',121.509911,25.056479,185,'commerce/153'],
  ['度小月擔仔麵','大同區','迪化街一段',121.509866,25.056424,5,'poi/node/6681493385'],
];

export function addCity170(map, firstLabel, openPlace, setPrepared, updateStores, setLocalLife, authoredRoads, hasFocalPin, dihuaLayer, nature, setShopPacks) {
  const data = 'city170-detail';
  const paint = 'city170-prepared';
  const schools = 'city170-schools';
  const roadAnchors = 'city170-road-anchors';
  for (const id of [data, paint, schools, 'city170-equipment']) {
    map.addSource(id, {type:'geojson', data:collection([]), maxzoom:19});
  }
  // One shared vector tile holds neighboring school courts at close zoom.
  map.addSource('city170-playing-areas',{type:'geojson',data:collection([]),maxzoom:16,buffer:256,tolerance:0});
  // Keep short visible label lines intact across a native vector tile edge.
  map.addSource(roadAnchors,{type:'geojson',data:collection([]),maxzoom:16,buffer:512});
  for(const id of ['city170-waterways','city170-farmland']){
    map.addSource(id,{type:'geojson',data:collection([]),maxzoom:17});
  }
  addCityAirfield(map,firstLabel);
  addCityBenches(map,firstLabel);
  const pin=addCity170Style(map, data, firstLabel);
  addArcadeFloors(map,'survey');
  addCityHydrants(map,firstLabel);
  addBusShelters(map,firstLabel);
  addCityPlaceIndex(map,pin);
  const baseRoads=map.getStyle().layers.filter(l=>l['source-layer']==='transportation_name');
  let boundary,roadLabelsActive=false;
  function cityRoadLabels(active){
    if(active===roadLabelsActive||!boundary)return;
    roadLabelsActive=active;
    for(const layer of baseRoads){
      const rule=['!', ['all',['>=',['zoom'],16.9],['within',boundary]]];
      map.setFilter(layer.id,active?['all',layer.filter??true,rule]:layer.filter??null);
    }
  }
  // Road captions follow the ground's draw order and can be occluded by buildings.
  map.addLayer({
    id:'city170-road-names',type:'symbol',source:roadAnchors,minzoom:16.9,
    filter:['!',authoredRoads],
    layout:{'symbol-placement':'line-center','text-field':['get','name'],
      'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],16.9,11,19.0,14],
      'text-padding':6,'text-pitch-alignment':'viewport','text-rotation-alignment':'map','text-keep-upright':true,
      'text-max-angle':30,'symbol-sort-key':['get','rank']},
    paint:{'text-color':'#4b5a51','text-halo-color':'#fff5dd','text-halo-width':1.4},
  },'survey');
  map.addSource('city170-markets',{type:'geojson',data:collection([])});
  map.addLayer({id:'city170-market-names',source:'city170-markets',type:'symbol',minzoom:15.6,
    layout:{...pin.layout,'icon-image':'place-pin-market','text-size':13},
    paint:{'text-color':pinLabelColor('market'),'text-halo-color':'#fff0d8','text-halo-width':1.6}});
  map.addLayer({id:'city170-market-points',source:'city170-markets',type:'circle',minzoom:15.6,filter:['!', ['has','name']],
    paint:{'circle-color':'#bd6749','circle-radius':4.6,'circle-stroke-color':'#fff3d9','circle-stroke-width':1.5}});
  let marketData;
  async function loadMarkets(){
    if(marketData || map.getZoom()<15.6)return;
    marketData=readPocketCityAsset('city170-markets')
      .then(value=>map.getSource('city170-markets').setData(collection(value.features.map(withMarketScenery))))
      .catch(error=>{marketData=null;console.warn('Taipei markets',error.message);});
  }
  map.on('moveend',loadMarkets);
  loadMarkets();
  const entranceCards=new Map();
  const basePlaces=['poi_r1','poi_transit','airport'];
  const hitLayers=[...city170PlaceLayers,'city170-school-names','city170-market-points','city170-market-names',...basePlaces,...cityPlaceLayers.filter(id=>id!=='taipei-place-neighbors')]
    .filter(id=>map.getLayer(id));
  function basePlaceName(props){
    return props['name:zh-Hant']||props['name:zh']||props['name:nonlatin']||props.name||props.name_en||props['name:latin'];
  }
  function hitPlace(point,padding=0){
    const area=padding?[[point.x-padding,point.y-padding],[point.x+padding,point.y+padding]]:point;
    const hits=map.queryRenderedFeatures(area,{layers:hitLayers});
    return hits.find(f=>!basePlaces.includes(f.layer.id)||basePlaceName(f.properties));
  }
  function openFeature(feature,point){
    const props={...streetShopProperties(feature.properties)};
    if(props.placeId && feature.geometry.type==='Point'){
      const choices=nearbyPlaces(map,feature.geometry.coordinates);
      if(choices.length>1 && choices.some(p=>p.placeId===props.placeId)){
        openPlace({name:'選擇地點',choices:choices.map(streetShopProperties),point:feature.geometry.coordinates});return;
      }
    }
    if(props.entranceId && entranceCards.has(props.entranceId)){
      openPlace(entranceCards.get(props.entranceId));return;
    }
    if(basePlaces.includes(feature.layer.id)){
      const geometry=feature.geometry;
      const points=geometry.type==='MultiPoint'?geometry.coordinates:geometry.type==='Point'?[geometry.coordinates]:[map.unproject(point).toArray()];
      const [lng,lat]=points.reduce((best,next)=>map.project(next).dist(point)<map.project(best).dist(point)?next:best);
      openPlace({point:[lng,lat],name:basePlaceName(props),categoryLabel:feature.layer.id==='airport'?'機場':feature.layer.id==='poi_transit'?'交通設施':'地點',
        source:'OpenStreetMap',url:'https://www.openstreetmap.org/?mlat='+lat+'&mlon='+lng+'#map=19/'+lat+'/'+lng});
      return;
    }
    const match=String(props.placeId??feature.id??'').match(/(?:^|\/)(node|way|relation)\/(\d+)$/);
    if(!props.url && match)props.url='https://www.openstreetmap.org/'+match[1]+'/'+match[2];
    props.point=feature.geometry.type==='Point'?feature.geometry.coordinates:map.unproject(point).toArray();
    openPlace(props);
  }
  map.on('click',event=>{
    const feature=hitPlace(event.point);
    if(!['city170-shop-names','city170-poi-labels'].includes(feature?.layer.id)){
      const entrance=entranceCards.get(dihuaLayer?.pickDihuaEntrance(event.point));
      if(entrance){event.preventDefault();openPlace(entrance);return;}
    }
    if(feature){event.preventDefault();openFeature(feature,event.point);}
  });
  // Called after an exact label, illustrated entrance and visible shopfront all miss.
  function openNearbyPlace(point){
    let feature=hitPlace(point,13);
    if(!feature)return;
    let low=0,high=13;
    while(high-low>1){
      const mid=Math.floor((low+high)/2);
      const closer=hitPlace(point,mid);
      if(closer){feature=closer;high=mid;}else low=mid;
    }
    openFeature(feature,point);
  }
  const canvas=map.getCanvas();
  map.on('mousemove',event=>{
    if(!map.isMoving() && !event.originalEvent?.buttons)canvas.classList.toggle('over-place',Boolean(hitPlace(event.point)));
  });
  canvas.addEventListener('mouseleave',()=>canvas.classList.remove('over-place'));
  map.on('movestart',()=>canvas.classList.remove('over-place'));

  let index, schoolData, grid, pendingGrid, current = 0, timer, failures = 0;
  let lifeKey='';
  let lifeRecords=[],lifeRevision=-1,sceneKey='';
  function resetLife(){
    setShopPacks([]);
    if(lifeKey){setLocalLife([]);nature.setRows([]);lifeKey='';lifeRecords=[];lifeRevision=-1;sceneKey='';}
  }
  const landLayers=new Map();
  function loadLandDetails(){
    // The network is static and clipped to the city. Send it to the map worker once.
    if(map.getZoom()<14)return;
    const b=map.getBounds();
    if(!overlaps([b.getWest(),b.getSouth(),b.getEast(),b.getNorth()],[121.4588,24.9603,121.6659,25.2102]))return;
    for(const id of ['city170-farmland','city170-waterways']){
      if(landLayers.has(id))continue;
      const load=readPocketCityAsset(id).then(value=>map.getSource(id).setData(value))
        .catch(error=>{landLayers.delete(id);console.warn(id,error.message);});
      landLayers.set(id,load);
    }
  }
  let status = {cells:0, features:0, prepared:0};
  const cache = new Map();
  const inflight = new Map();
  function remember(key, load) {
    if (cache.has(key)) {
      const value = cache.get(key);
      cache.delete(key);
      cache.set(key, value);
      return Promise.resolve(value);
    }
    if (!inflight.has(key)) {
      inflight.set(key, load().then(value => {
        cache.set(key, value);
        while (cache.size > 56) cache.delete(cache.keys().next().value);
        return value;
      }).finally(() => inflight.delete(key)));
    }
    return inflight.get(key);
  }
  const pack = id => remember(id, () => readPocketCityAsset('city170/' + id));
  const markings = id => remember('paint/' + id, () => readPocketCityAsset('city170-prepared/' + id.slice(1)));

  const schoolInputs = [...document.querySelectorAll('.school-find')];
  const schoolList = document.querySelector('#school-list');
  const schoolPositions = new Map();
  async function loadSchools() {
    if (schoolData) return;
    const value = await remember('schools', () => readPocketCityAsset('city170/schools'));
    if (schoolData) return;
    for (const f of value.features) {
      const match=String(f.id).match(/\/(node|way|relation)\/(\d+)$/);
      if (match) f.properties.url='https://www.openstreetmap.org/'+match[1]+'/'+match[2];
    }
    schoolData = value;
    map.getSource(schools).setData(value);
    const options = document.createDocumentFragment();
    for (const f of value.features) {
      if (f.properties.kind !== 'school-label' || !f.properties.name) continue;
      let key = f.properties.name;
      if (schoolPositions.has(key)) key += '（' + f.geometry.coordinates.map(n => n.toFixed(4)).join(', ') + '）';
      schoolPositions.set(key, f.geometry.coordinates);
      const option = document.createElement('option');
      option.value = key;
      options.append(option);
    }
    schoolList.replaceChildren(options);
  }
  for (const input of schoolInputs) {
    input.addEventListener('focus', () => loadSchools().catch(error => console.warn(error.message)));
    input.addEventListener('change', () => {
      const center = schoolPositions.get(input.value.trim());
      if (!center) return;
      for (const other of schoolInputs) other.value = input.value;
      document.querySelector('.mobile').open = false;
      map.jumpTo({center,zoom:17.35,pitch:38});
    });
  }
  async function refresh() {
    const epoch = ++current;
    loadLandDetails();
    clearTimeout(timer);
    try {
      if (map.getZoom() < 13) {
        map.getSource(data).setData(collection([]));
        map.getSource(paint).setData(collection([]));
        map.getSource('city170-equipment').setData(collection([]));
        map.getSource('city170-playing-areas').setData(collection([]));
        map.getSource(roadAnchors).setData(collection([]));
        cityRoadLabels(false);
        resetLife();
        setPrepared(false);
        updateStores([]);
        status = {cells:0, features:0, prepared:0};
        return;
      }
      await loadSchools();
      if (epoch !== current) return;
      if (map.getZoom() < 16.35) {
        const landscape = await remember('landscape', () => readPocketCityAsset('city170-landscape'));
        if (epoch !== current) return;
        const b = map.getBounds();
        const view = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()];
        const features = landscape.features.filter(feature => overlaps(feature.bbox, view)).map(surfaceFeature);
        map.getSource(data).setData(collection(features));
        map.getSource(paint).setData(collection([]));
        map.getSource('city170-equipment').setData(collection([]));
        map.getSource('city170-playing-areas').setData(collection([]));
        map.getSource(roadAnchors).setData(collection([]));
        updateStores([]);
        cityRoadLabels(false);
        resetLife();
        setPrepared(false);
        status = {cells:0, features:0, prepared:0};
        return;
      }
      if (!index) index = await remember('index', async () => {
        const response = await fetch(new URL('./data/city170/index.json', import.meta.url));
        if (!response.ok) throw Error('City atlas index ' + response.status);
        return response.json();
      });
      if (epoch !== current) return;
      const b = map.getBounds();
      const view = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()];
      const visible = index.packs.filter(item => overlaps(item.bounds, view));
      const packIds=visible.map(item=>item.id);
      setShopPacks(map.getZoom()>=17.55?packIds:[]);
      if(!boundary)boundary=await remember('boundary',async()=>{
        const response=await fetch(new URL('./data/city170-boundary.json',import.meta.url));
        if(!response.ok)throw Error('City boundary '+response.status);
        return response.json();
      });
      const packs = await Promise.all(visible.map(item => pack(item.id)));
      if (epoch !== current) return;
      const key=packIds.join(',');
      if(key!==lifeKey){
        const [records,inventories]=await Promise.all([
          Promise.all(packIds.map(id=>remember('life/'+id,()=>readPocketCityAsset('city170-life/'+id)))),
          Promise.all(packIds.map(id=>remember('trees/'+id,()=>readPocketCityAsset('city170-nature/'+id))
            .catch(error=>{console.warn('臺北樹籍',id,error.message);return null;}))),
        ]);
        if(epoch!==current)return;
        nature.setRows(inventories.flatMap(pack=>pack??[]));
        lifeRecords=records;lifeRevision=-1;
        lifeKey=inventories.every(Boolean)?key:'retry-trees';
      }
      if(lifeRevision!==nature.revision){
        const scenery=lifeRecords.map(r=>({...r,objects:Object.fromEntries(Object.entries(r.objects).filter(([,obj])=>
          obj[2]!=='tree'||!nature.activeTrees.near(obj[0],obj[1],5)))}));
        const fingerprint=key+'|'+scenery.map(r=>Object.keys(r.objects).join(',')).join('|');
        if(sceneKey!==fingerprint){setLocalLife(scenery,packIds);sceneKey=fingerprint;}
        lifeRevision=nature.revision;
      }
      if (epoch !== current) return;
      const cells = packs.flatMap(p => p.cells.filter(c => overlaps(c.bounds, view)));
      const wanted = new Set(cells.flatMap(cell => cell.refs));
      const owners = new Set(cells.flatMap(cell => cell.deps));
      for (const p of packs) owners.delete(p.id);
      const dependencies = await Promise.all([...owners].map(pack));
      if (epoch !== current) return;
      const features = [...packs,...dependencies].flatMap(p => p.features.features.filter(f =>
        wanted.has(f.id) && !['school','school-label'].includes(f.properties.kind))).map(surfaceFeature);
      // The city roster supplements the canonical street features without blocking the base map.
      let supplemental;
      try {
        supplemental = await remember('shops', () => readPocketCityAsset('city170-shops'));
      } catch (error) {
        console.warn('Taipei storefronts', error.message);
      }
      if (epoch !== current) return;
      if (supplemental) {
        for (let i=0;i<features.length;i++) {
          const f=features[i], matched=supplemental.matches[f.id];
          if (matched) features[i]={...f,properties:{...f.properties,commerceListed:true}};
        }
        features.push(...supplemental.features.filter(f=>{
          const [x,y]=f.geometry.coordinates;
          return x>=view[0]&&x<=view[2]&&y>=view[1]&&y<=view[3];
        }));
      }
      for(const [i,f] of features.entries()){
        if(f.id==='commerce/153' || f.id==='poi/node/6681493385'){
          features[i]={...f,properties:{...f.properties,detail:'大同區 · 迪化街一段'}};
        }
      }
      const inspected=await remember('inspected-shops',()=>readPocketCityAsset('city170-inspected-shops'))
        .catch(error=>{console.warn('餐飲評核資料',error.message);return null;});
      if(epoch!==current)return;
      if(inspected)features.push(...inspected.features.filter(f=>{
        const [x,y]=f.geometry.coordinates;
        return x>=view[0]&&x<=view[2]&&y>=view[1]&&y<=view[3];
      }));
      if(dihuaLayer && map.getZoom()>=19.25 && overlaps(view,[121.50982,25.05634,121.50995,25.05672])){
        // At façade scale the user can tap the entrance itself.
        const onStreet=(x,y)=>x>=view[0]&&x<=view[2]&&y>=view[1]&&y<=view[3];
        const facingAcross=Math.sin(map.getBearing()*Math.PI/180)*Math.sin(map.getPitch()*Math.PI/180);
        const eastVisible=facingAcross>-.30, westVisible=facingAcross<.30;
        const front=[121.509911,25.056479];
        const existing=features.findIndex(f=>f.id==='commerce/153');
        const juelin=supplemental?.features.find(f=>f.id==='commerce/153');
        if(existing>=0)features.splice(existing,1);
        if(eastVisible && juelin && onStreet(...front))features.push({...juelin,geometry:{type:'Point',coordinates:front},
          properties:{...juelin.properties,detail:'大同區 · 迪化街一段',name:'爵林堅果',entranceId:89,rank:-10}});
        const noodle=features.findIndex(f=>f.id==='poi/node/6681493385');
        if(noodle>=0 && !westVisible)features.splice(noodle,1);
        else if(noodle>=0){
          const f=features[noodle];
          features[noodle]={...f,geometry:{type:'Point',coordinates:[121.509866,25.056424]},
            properties:{...f.properties,name:'度小月擔仔麵',entranceId:112,rank:-10,
              source:'度小月官網',url:'https://noodle1895.com/branch/taipei-dihua-store/'}};
        }
        for(const [number,x,y,name,categoryLabel,source,url] of dihuaPlaces){
          if(eastVisible && onStreet(x,y))features.push({type:'Feature',id:'dihua/'+number,geometry:{type:'Point',coordinates:[x,y]},
            properties:{kind:'poi',name,entranceId:number,category:'street_place',categoryLabel,rank:-10,
              detail:'大同區 · 迪化街一段',source,url}});
        }
      }
      entranceCards.clear();
      for(const f of features){
        if(f.properties.entranceId)entranceCards.set(f.properties.entranceId,{...f.properties,point:f.geometry.coordinates});
      }
      updateStores(map.getZoom() >= 18.15 ? features.filter(f => f.properties.kind === 'poi').map(f => f.id) : []);
      const equipment=[], playingAreas=[], detailedPitchIds=new Set();
      if(map.getZoom()>=17)for(const feature of features){
        if(feature.properties.kind!=='pitch'){
          if(map.getZoom()>=18.5 && feature.properties.category==='bicycle_rental')equipment.push(...bikeDockParts(feature));
          continue;
        }
        const [painted,...parts]=courtDetails(feature,map.getZoom()>=18.5);
        if(painted){
          detailedPitchIds.add(feature.id);
          playingAreas.push(feature,painted);
        }
        equipment.push(...parts);
      }
      map.getSource('city170-equipment').setData(collection(equipment));
      map.getSource('city170-playing-areas').setData(collection(playingAreas));
      const mapped=features.filter(f=>!detailedPitchIds.has(f.id)&&!hasFocalPin(f) &&
        (f.properties.kind!=='tree'||!nature.activeTrees.near(...f.geometry.coordinates,5)));
      map.getSource(data).setData(collection(mapped.map(f=>f.properties.kind==='poi'
        ?withShopFacts({...f,properties:{...f.properties,placeId:f.id}}):f)));
      map.getSource(roadAnchors).setData(collection(cityStreetLabels(mapped,map,view)));
      cityRoadLabels(cells.length>0);
      status = {cells:cells.length, features:features.length, prepared:0};
      const [paintPacks, openGround] = await Promise.all([
        Promise.all(visible.map(item => markings(item.id))),
        visible.length ? remember('open-ground',()=>readPocketCityAsset('city170-open-ground'))
          .catch(error=>{console.warn('臺北開放地貌',error.message);return {};}) : {},
      ]);
      if (epoch !== current) return;
      const pieces = [];
      for (let i = 0; i < packs.length; i++) {
        for (const cell of packs[i].cells) {
          if(!overlaps(cell.bounds,view))continue;
          const items=paintPacks[i][cell.id]??[];
          const blocked=openGround[cell.id];
          if(!blocked){pieces.push(...items);continue;}
          const roots=new Set(blocked.map(pt=>pt.join(',')));
          for(const f of items){
            if(f.properties.kind!=='grove-tree'||!roots.has(f.geometry.coordinates.join(',')))pieces.push(f);
          }
        }
      }
      map.getSource(paint).setData(collection(pieces.filter(f=>f.properties.kind!=='grove-tree'||!nature.activeTrees.near(...f.geometry.coordinates,9))));
      setPrepared(packs.length > 0);
      status.prepared = pieces.length;
      failures = 0;
    } catch (error) {
      if (epoch !== current) return;
      console.warn('Taipei 170m', error.message);
      timer = setTimeout(refresh, Math.min(30000, 1800 * 2 ** Math.min(failures++, 4)));
    }
  }
  nature.onRootsChanged=()=>{
    clearTimeout(timer);
    timer=setTimeout(refresh,125);
  };
  map.on('moveend', refresh);
  map.on('resize', refresh);
  refresh();
  return {
    openNearbyPlace,
    state:() => ({...status,cellSize:170,coverage:index?.stats??null}),
    grid(show) {
      if (show && !grid && !pendingGrid) {
        pendingGrid = readPocketCityAsset('city170/grid').then(value => {
          map.getSource('plots').setData(value);
          grid = value;
        }).catch(error => console.warn('170m grid', error.message)).finally(() => {pendingGrid = null;});
      }
    },
  };
}
