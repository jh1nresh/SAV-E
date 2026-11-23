import {addCity170Style, city170PlaceLayers} from './city170-style.js?v=shop-names-2';
import {readPocketCityAsset} from './pocket-city-atlas.js';

const collection = features => ({type: 'FeatureCollection', features});
const overlaps = ([w,s,e,n], [left,bottom,right,top]) => w <= right && e >= left && s <= top && n >= bottom;

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
  ...dihuaPlaces.map(([id,x,y,name])=>[name,'大同區','迪化街一段',x,y,185,'dihua/'+id]),
  ['爵林堅果','大同區','迪化街一段',121.509911,25.056479,185,'commerce/153'],
  ['度小月擔仔麵','大同區','迪化街一段',121.509866,25.056424,5,'poi/node/6681493385'],
];

export function addCity170(map, firstLabel, openPlace, setPrepared, updateStores, setLocalLife, authoredRoads, hasFocalPin, dihuaLayer, nature, setShopPacks) {
  const data = 'city170-detail';
  const paint = 'city170-prepared';
  const schools = 'city170-schools';
  for (const id of [data, paint, schools]) {
    map.addSource(id, {type:'geojson', data:collection([]), maxzoom:19});
  }
  addCity170Style(map, data, firstLabel);
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
  // Existing landmark and road labels get first choice of screen space.
  map.addLayer({
    id:'city170-road-names',type:'symbol',source:data,minzoom:16.9,
    filter:['all',['in',['get','kind'],['literal',['road','walk']]],['has','name'],['!',authoredRoads]],
    layout:{'symbol-placement':'line','symbol-spacing':360,'text-field':['get','name'],
      'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],16.9,11,19.0,14],'text-padding':5,'text-max-angle':30,
      'text-pitch-alignment':'viewport','text-keep-upright':true},
    paint:{'text-color':'#4b5a51','text-halo-color':'#fff5dd','text-halo-width':1.4},
  },firstLabel);
  map.addSource('city170-markets',{type:'geojson',data:collection([])});
  map.addLayer({id:'city170-market-names',source:'city170-markets',type:'symbol',minzoom:15.6,
    layout:{'text-field':['get','name'],'text-font':['Noto Sans Bold'],'text-size':12,
      'text-offset':[0,.65],'text-anchor':'top','text-max-width':9,'text-padding':6},
    paint:{'text-color':'#883e2a','text-halo-color':'#fff0d8','text-halo-width':1.6}});
  map.addLayer({id:'city170-market-points',source:'city170-markets',type:'circle',minzoom:15.6,
    paint:{'circle-color':'#bd6749','circle-radius':4.6,'circle-stroke-color':'#fff3d9','circle-stroke-width':1.5}});
  let marketData;
  async function loadMarkets(){
    if(marketData || map.getZoom()<15.6)return;
    marketData=readPocketCityAsset('city170-markets').then(value=>map.getSource('city170-markets').setData(value))
      .catch(error=>{marketData=null;console.warn('Taipei markets',error.message);});
  }
  map.on('moveend',loadMarkets);
  loadMarkets();
  const entranceCards=new Map();
  // At close scale a built shop has a sign on its wall and can be tapped directly.
  const placeLayers=['city170-poi-labels','city170-poi-dots'].map(id=>[id,map.getFilter(id)]);
  let builtIds=[],previousIds='',useShopSigns=false,useDihuaSigns=false;
  function applySignFilter(){
    for(const [id,filter] of placeLayers){
      const tests=[filter];
      if(useDihuaSigns)tests.push(['!', ['has','entranceId']]);
      if(useShopSigns && builtIds.length)tests.push(['!', ['in',['get','placeId'],['literal',builtIds]]]);
      map.setFilter(id,tests.length===1?filter:['all',...tests]);
    }
  }
  map.on('render',()=>{
    const close=map.getZoom()>=19;
    const dihua=Boolean(dihuaLayer?.dihuaDrawn && dihuaLayer.dihua?.entrances && map.getZoom()>=19.25);
    if(close===useShopSigns && dihua===useDihuaSigns)return;
    useShopSigns=close;useDihuaSigns=dihua;applySignFilter();
  });
  map.on('click', event => {
    const card=entranceCards.get(dihuaLayer?.pickDihuaEntrance(event.point));
    if(card){event.preventDefault();openPlace(card);return;}
    const layers = [...city170PlaceLayers, 'city170-school-names','city170-market-points','city170-market-names'].filter(id => map.getLayer(id));
    const feature = map.queryRenderedFeatures(event.point, {layers})[0];
    if (feature?.properties) {
      const properties = {...feature.properties};
      const match = String(properties.placeId ?? feature.id ?? '').match(/(?:^|\/)(node|way|relation)\/(\d+)$/);
      if (!properties.url && match) properties.url='https://www.openstreetmap.org/'+match[1]+'/'+match[2];
      event.preventDefault();openPlace(properties);
    }
  });

  let index, schoolData, grid, pendingGrid, current = 0, timer, failures = 0;
  let lifeKey='';
  let lifeRecords=[],lifeRevision=-1,sceneKey='';
  function resetLife(){
    setShopPacks([]);
    if(lifeKey){setLocalLife([]);nature.setRows([]);lifeKey='';lifeRecords=[];lifeRevision=-1;sceneKey='';}
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
    clearTimeout(timer);
    try {
      if (map.getZoom() < 13) {
        map.getSource(data).setData(collection([]));
        map.getSource(paint).setData(collection([]));
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
        const features = landscape.features.filter(feature => overlaps(feature.bbox, view));
        map.getSource(data).setData(collection(features));
        map.getSource(paint).setData(collection([]));
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
        wanted.has(f.id) && !['school','school-label'].includes(f.properties.kind)));
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
        if(f.properties.entranceId)entranceCards.set(f.properties.entranceId,f.properties);
      }
      updateStores(map.getZoom() >= 18.15 ? features.filter(f => f.properties.kind === 'poi').map(f => f.id) : []);
      const mapped=features.filter(f=>!hasFocalPin(f) &&
        (f.properties.kind!=='tree'||!nature.activeTrees.near(...f.geometry.coordinates,5)));
      map.getSource(data).setData(collection(mapped.map(f=>f.properties.kind==='poi'
        ?{...f,properties:{...f.properties,placeId:f.id}}:f)));
      cityRoadLabels(cells.length>0);
      status = {cells:cells.length, features:features.length, prepared:0};
      const paintPacks = await Promise.all(visible.map(item => markings(item.id)));
      if (epoch !== current) return;
      const pieces = [];
      for (let i = 0; i < packs.length; i++) {
        for (const cell of packs[i].cells) {
          if (overlaps(cell.bounds, view)) pieces.push(...(paintPacks[i][cell.id] ?? []));
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
    setBuiltShops(ids){
      const key=ids.join('|');
      if(key===previousIds)return;
      previousIds=key;builtIds=ids;
      if(useShopSigns)applySignFilter();
    },
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
