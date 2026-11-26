// The normal map connects district street surfaces and the georegistered
// Songyan artwork. The existing 170 m paint owns crossing and lane
// geometry, including dashes that cross a cell boundary.
import {decodeMapJSON} from './pocket-city-atlas.js';
import {plotOverlaps} from './authored-footprint.js';

// The broad-phase boxes come from the 170 m index. The map supplies the official district polygons.
const districts=[
  {name:'信義區',id:'xinyi',mask:1,bounds:[121.55252,25.00810,121.59216,25.04951]},
  {name:'松山區',id:'songshan',mask:2,bounds:[121.53834422,25.04429119,121.58006742,25.07597382]},
];
const districtMasks=new Map(districts.map(row=>[row.name,row.mask]));
const street='#929394',walk='#e6c9a6',path='#dcc5a3',kerb='#e3c477',marking='#f0dfc0';
// The narrow full-tower camera reaches street scale below the detail-pack zoom.
const roadOverviewZoom=15.35;
const fade=(z,full)=>['interpolate',['linear'],['zoom'],z,0,full,1];

function unpackRing(values){
  if(values.length<4||values.length%2)throw Error('Invalid district ground coordinates');
  let lng=121550000,lat=25000000;
  const line=[];
  for(let i=0;i<values.length;i+=2){
    lng+=values[i];lat+=values[i+1];
    line.push([lng/1e6,lat/1e6]);
  }
  return line;
}

export function unpackDistrictGround(packed){
  const features=[];
  for(const kind of ['road','walk','path','kerb']){
    for(const row of packed[kind]){
      const geometry=kind==='kerb'?{type:'LineString',coordinates:unpackRing(row)}
        :{type:'Polygon',coordinates:row.map(unpackRing)};
      features.push({type:'Feature',properties:{kind},geometry});
    }
  }
  return {type:'FeatureCollection',features};
}

// A shared boundary cell can use the district finish once both halves are ready.
// Keep the base paint in cells also belonging to a district without ground art.
export function districtStreetMarkings(items,cell){
  if(!cell.districts?.length||cell.districts.some(name=>!districtMasks.has(name)))return items;
  const mask=cell.districts.reduce((bits,name)=>bits|districtMasks.get(name),0);
  return items.map(f=>f.properties.kind==='lane'||f.properties.kind==='crossing'?
    {...f,properties:{...f.properties,districtStreetMask:mask}}:f);
}

function sidewalkTiles(width){
  const data=new Uint8Array(width*width*4);
  // A globally anchored 4.3 m repeat holds three 1.4 m rows of 0.6 m stones.
  for(let y=0;y<width;y++)for(let x=0;x<width;x++){
    const row=Math.floor(3*y/width),offset=x*7/width+row*.37;
    const joint=offset%1<.08||(3*y/width)%1<.045;
    const shade=(Math.floor(offset)+row*3)%4===0;
    data.set(joint?[143,126,104,136]:shade?[112,90,79,18]:[255,249,230,11],(y*width+x)*4);
  }
  return {width,height:width,data};
}

function sidewalkPattern(map){
  const ids=[];
  for(let z=17;z<=21;z++){
    const id='district-street-pavers-'+z;
    map.addImage(id,sidewalkTiles(2**(z-13)),{pixelRatio:2});
    ids.push(id);
  }
  return ['step',['zoom'],ids[0],...ids.slice(1).flatMap((id,i)=>[18+i,id])];
}

function install(map,groundId,data,pattern,nextDistrict){
  // Insert above the legacy street fills while yielding to the exact 101 plot,
  // pond paint, shadows, foreground furniture, survey buildings and all labels.
  const order=map.getStyle().layers;
  const foreground=new Set(['taipei101-single-ground','songyan-woods','atlas-shadows','city170-prepared-lane','city170-prepared-crossing','survey']);
  if(nextDistrict)foreground.add(nextDistrict.groundId+'-paving');
  const before=order.find(layer=>foreground.has(layer.id))?.id;
  map.addSource(groundId,{type:'geojson',data,maxzoom:20,tolerance:0,buffer:96});
  const material=(id,kinds,paint,minzoom=roadOverviewZoom)=>{
    map.addLayer({id:groundId+'-'+id,type:'fill',source:groundId,minzoom,
      filter:['in',['get','kind'],['literal',kinds]],paint:{'fill-antialias':false,...paint}},before);
  };
  material('paving',['walk','path'],{'fill-color':['match',['get','kind'],'path',path,walk],'fill-opacity':fade(roadOverviewZoom,16.25)});
  material('asphalt',['road'],{'fill-color':street,'fill-opacity':fade(roadOverviewZoom,16.25)});
  material('concrete-joints',['walk'],{'fill-pattern':pattern,
    'fill-opacity':['interpolate',['linear'],['zoom'],17,0,17.9,.55]},17);
  map.addLayer({id:groundId+'-kerb',type:'line',source:groundId,minzoom:16.65,
    filter:['==',['get','kind'],'kerb'],layout:{'line-join':'round','line-cap':'round'},
    paint:{'line-color':kerb,'line-width':['interpolate',['exponential',2],['zoom'],16,.16,21,5.14],
      'line-opacity':fade(16.65,17.4)}},before);
}

export function addDistrictStreetGround(map){
  const outlines=map.getStyle().sources?.districts?.data?.features??[];
  const regions=districts.map(row=>({...row,
    footprint:outlines.find(f=>f.properties.name===row.name)?.geometry,
    groundId:row.id+'-street-ground',request:null,ready:false}));
  const markings=['city170-prepared-lane','city170-prepared-crossing']
    .filter(id=>map.getLayer(id)).map(id=>[id,map.getPaintProperty(id,'fill-color')]);
  let removed=false,pattern;
  async function load(region){
    region.request=new AbortController();
    try{
      const asset=new URL('./assets/'+region.groundId+'.json.gz',import.meta.url);
      const response=await fetch(asset,{signal:region.request.signal});
      if(!response.ok)throw Error(region.groundId+' '+response.status);
      const data=unpackDistrictGround(await decodeMapJSON(response));
      if(removed)return;
      pattern??=sidewalkPattern(map);
      const nextDistrict=regions.slice(regions.indexOf(region)+1).find(r=>r.ready);
      install(map,region.groundId,data,pattern,nextDistrict);
      region.ready=true;
      const ready=regions.reduce((mask,r)=>r.ready?mask|r.mask:mask,0);
      const available=regions.filter(r=>r.ready).map(r=>r.mask);
      if(available.length>1)available.push(ready);
      for(const [id,base] of markings){
        map.setPaintProperty(id,'fill-color',['case',
          ['in',['get','districtStreetMask'],['literal',available]],marking,base]);
      }
      if(regions.every(r=>r.ready))map.off('moveend',near);
    }catch(error){
      if(!removed)console.warn(region.name+'道路',error.message);
    }finally{region.request=null;}
  }
  function near(){
    if(removed||map.getZoom()<roadOverviewZoom)return;
    const [[w,s],[e,n]]=map.getBounds().toArray();
    return Promise.all(regions.filter(region=>!region.ready&&!region.request&&
      plotOverlaps(region,[w,s,e,n])).map(load));
  }
  map.on('remove',()=>{
    removed=true;
    for(const region of regions)region.request?.abort();
    map.off('moveend',near);
  });
  map.on('moveend',near);
  void near();
}
