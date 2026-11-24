// Offline regional hydrography and named features from the Taiwan OSM extract.
import {readTaiwanJSON} from './taiwan-coverage.js';
const points='taiwan-scenery-places',rivers='taiwan-scenery-rivers',waters='taiwan-scenery-waters';
export const sceneryLabels='taiwan-scenery-labels';

const kindLabels={
  park:'公園',nature_reserve:'自然保護區',wood:'林地',canal:'人工水道',ditch:'溝渠',drain:'排水道',
  peak:'山峰',waterfall:'瀑布',cliff:'峭壁',cape:'海岬',beach:'沙灘',bay:'海灣',
  island:'島嶼',reef:'礁岩',lake:'湖泊',lagoon:'潟湖',reservoir:'水庫',water:'水域',
  pond:'池塘',wetland:'濕地',spring:'泉水',hot_spring:'溫泉',cave:'洞穴',river:'河流',stream:'溪流',
};
const classes={
  summit:['peak'],rock:['cliff','cave','reef'],coast:['beach','cape','island','bay'],
  falls:['waterfall'],wetland:['wetland','wood','park','nature_reserve'],water:['lake','lagoon','reservoir','pond','spring','hot_spring','water'],
};
const inks={summit:'#427052',rock:'#815e49',coast:'#2b7c81',falls:'#39779a',wetland:'#53805b',water:'#367d8c'};
const classStyle=value=>['match',['get','k'],...Object.entries(classes).flatMap(([key,kinds])=>[kinds,value(key)]),value('water')];
export const yushanView={center:[120.957274,23.469987],zoom:13.1,mobileZoom:12.8,
  bearing:-32,pitch:62,mobilePitch:56};
const yushanURL='https://www.ysnp.gov.tw/Trail/7fa5c242-df1a-4a8e-bcab-32dc55b1f7b6?ID=980ec5de-bc0d-41a5-b479-add518f66181&Tab=2';
const cliff={source:'太魯閣國家公園管理處',url:'https://www.taroko.gov.tw/ch/trailsAttractions/attractions/8',
  detail:'清水山東側的岩壁緊鄰太平洋。片岩、片麻岩與大理石構成這段蘇花海岸。'};
const fieldNotes={
  n3428095932:{name:'玉山主峰',source:'玉山國家公園管理處',url:yushanURL,detail:'海拔約 3,952 公尺。峰頂可見層疊的裸岩，周圍是草坡與深谷。'},
  r3858334:{source:'日月潭國家風景區管理處',url:'https://www.sunmoonlake.gov.tw/zh-tw/Attractions/Attractions?a=20&id=54',
    detail:'湖中的拉魯島是邵族祖靈的居所。'},
  n2705166889:cliff,n4851114805:cliff,
};
const highlights=['n3428095932','r3858334','n2705166889','w222540774','n2357167485',
  'r9331637','r6262405','w904763418','w904469677','n4845183318','n4705115484','w188412448','n9966788717','n1233402716'];

// Match identity to the original node, way or relation; equal names occur on different mountains.
export function sceneryCard(properties,point){
  const ref=/^([nwr])(\d+)$/.exec(properties.id??'');
  if(!ref||!properties.n||!Object.hasOwn(kindLabels,properties.k))return null;
  const type={n:'node',w:'way',r:'relation'}[ref[1]];
  const elevation=properties.ele;
  return {name:properties.n,categoryLabel:kindLabels[properties.k],point,
    placeId:'poi/'+type+'/'+ref[2],source:'OpenStreetMap',
    url:'https://www.openstreetmap.org/'+type+'/'+ref[2],
    detail:elevation==null?'':'圖載海拔 '+Number(elevation).toLocaleString('zh-TW')+' 公尺',
    ...fieldNotes[properties.id],
    ...(properties.k==='peak'?{mapView:properties.id==='n3428095932'?yushanView:
      {center:point,zoom:13.8,mobileZoom:13.45,bearing:-25,pitch:55,mobilePitch:51}}:{})};
}
function addSymbols(map){
  for(const [key,color] of Object.entries(inks)){
    const id='tw-nature-'+key;
    if(map.hasImage(id))continue;
    const canvas=document.createElement('canvas');
    canvas.width=canvas.height=48;
    const c=canvas.getContext('2d');
    c.scale(2,2);c.fillStyle=color;c.strokeStyle='#fff8e9';c.lineWidth=1.8;
    c.beginPath();c.arc(12,12,10,0,2*Math.PI);c.fill();c.stroke();
    c.lineWidth=1.45;c.lineJoin='round';c.lineCap='round';c.beginPath();
    const pen=(...coords)=>{c.moveTo(coords[0],coords[1]);for(let i=2;i<coords.length;i+=2)c.lineTo(coords[i],coords[i+1]);};
    if(key==='summit'){pen(4.8,15.8,10,7.5,13.2,12,15,9.5,19,15.8);pen(8.6,10,10,11,11.5,10);}
    if(key==='rock'){pen(5,16,9,10,15,7,18,16,5,16);pen(10,15,13,11,15,10);}
    if(key==='coast'){pen(5,13,9,12,12,9,15,8,17.5,8);pen(5,16,8,15,11,16,14,15,17.5,16);}
    if(key==='falls'){pen(5,7,12,7,12,14);pen(15,7,15,13);pen(7,16,10,15,13,16,17,15);}
    if(key==='wetland'){pen(6,16,10,15.5,14,16,18,15.5);pen(9,14,8,9);pen(12,14,12,7.5);pen(15,14,16,10);}
    if(key==='water'){pen(5.5,11,8.5,9.5,12,11,15.5,9.5,18.5,11);pen(5.5,15,8.5,13.5,12,15,15.5,13.5,18.5,15);}
    c.stroke();map.addImage(id,c.getImageData(0,0,48,48),{pixelRatio:2});
  }
}

export function addTaiwanScenery(map,beforeId,open,read=readTaiwanJSON){
  const attribution='<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a>';
  const domains=[[119.18,21.7,122.2,25.65],[118.1,24.26,118.52,24.60],
    [119.88,25.88,120.57,26.46],[119.39,24.94,119.49,25.04],[116.68,20.65,116.77,20.73],[114.32,10.36,114.39,10.40]];
  let installed=false,removed=false,labelsVisible=true;
  const assets=[[points,'places'],[rivers,'rivers'],[waters,'waters']];
  const pending=new Set(),ready=new Set();
  function refresh(){
    for(const [id,file] of assets){
      if(pending.has(id)||ready.has(id))continue;
      pending.add(id);
      read('scenery/'+file+'.geojson.gz').then(data=>{
        if(removed)return;
        map.getSource(id).setData(data);
        ready.add(id);
      }).catch(error=>{if(!removed)console.warn('Taiwan scenery '+file,error);})
        .finally(()=>pending.delete(id));
    }
  }
  function load(){
    if(removed||map.getZoom()<6)return;
    const view=map.getBounds();
    if(!domains.some(([w,s,e,n])=>view.getWest()<e&&view.getEast()>w&&view.getSouth()<n&&view.getNorth()>s))return;
    if(installed){refresh();return;}
    installed=true;
    addSymbols(map);
    for(const [id] of assets){
      map.addSource(id,{type:'geojson',data:{type:'FeatureCollection',features:[]},attribution,maxzoom:15});
    }
    const belowRoads=map.getLayer('landcover_sand')?'landcover_sand':beforeId;
    map.addLayer({id:waters,type:'fill',source:waters,minzoom:6,maxzoom:13.5,paint:{
      'fill-color':['match',['get','k'],'wetland','#8ebc96','lagoon','#78b9ad','#68abbb'],
      'fill-opacity':['interpolate',['linear'],['zoom'],6,.55,11,.55,13.5,0]}},belowRoads);
    map.addLayer({id:rivers,type:'line',source:rivers,minzoom:7,maxzoom:13.5,
      filter:['step',['zoom'],['==',['get','large'],true],10.5,true],
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':'#70aeb9','line-width':['interpolate',['linear'],['zoom'],7,.65,13,1.7],
        'line-opacity':['interpolate',['linear'],['zoom'],7,.76,11,.76,13.5,0]}},belowRoads);
    const first=['in',['get','id'],['literal',highlights]];
    map.addLayer({id:sceneryLabels,source:points,type:'symbol',minzoom:6.25,
      filter:['step',['zoom'],first,8.5,['any',first,['>=',['to-number',['get','ele'],0],3500]],
        10.5,['any',first,['>=',['to-number',['get','ele'],0],2500],['in',['get','k'],['literal',['cape','lagoon','waterfall','reservoir','island']]]],12.5,true],
      layout:{visibility:labelsVisible?'visible':'none','icon-image':classStyle(k=>'tw-nature-'+k),
        'icon-size':['interpolate',['linear'],['zoom'],6,.67,14,.91],'icon-padding':2,
        'text-field':['get','n'],'text-font':['Noto Sans Bold'],'text-anchor':'left','text-offset':[1.05,0],
        'text-size':['interpolate',['linear'],['zoom'],6,12,15,14],'text-padding':4,
        'symbol-sort-key':['case',first,0,['-',5200,['to-number',['get','ele'],0]]]},
      paint:{'text-color':classStyle(k=>inks[k]),'text-halo-color':'#fff8e9','text-halo-width':1.7}},beforeId);
    // A lake below an authored POI must not open a second card on the same tap.
    const protectedPins=['city-atlas-pins','city-atlas-places','city-atlas-context-places','city-atlas-locators',
      'tw-public-places','taipei-savvy-place-names','taipei-place-names','taipei-outdoor-names','city170-shop-names',
      'city170-poi-labels','city170-market-names','city170-market-points','city170-school-names','city170-vendor-awnings',
      'city170-poi-dots','world-cities','world-city-dots','airport','poi_r1','poi_transit'];
    map.on('click',event=>{
      if(event.defaultPrevented)return;
      const layers=[sceneryLabels,waters,rivers,...protectedPins.filter(id=>map.getLayer(id))];
      const hits=map.queryRenderedFeatures(event.point,{layers});
      if(hits.some(f=>protectedPins.includes(f.layer.id)))return;
      const picked=hits.find(f=>f.layer.id===sceneryLabels)??hits[0];
      if(!picked)return;
      const location=picked.geometry.type==='Point'?picked.geometry.coordinates:[event.lngLat.lng,event.lngLat.lat];
      const card=sceneryCard(picked.properties,location);
      if(card)open(card);
    });
    refresh();
  }
  map.on('remove',()=>{removed=true;});
  map.on('moveend',load);load();
  return {setLabels(visible){labelsVisible=visible;if(installed)map.setLayoutProperty(sceneryLabels,'visibility',visible?'visible':'none');}};
}
