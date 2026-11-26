// Normal-map ground uses the georegistered Songyan roads and the district's
// connected street surfaces. The existing 170 m paint owns crossing and lane
// geometry, including dashes that cross a cell boundary.
import {decodeMapJSON} from './pocket-city-atlas.js';

const extent=[121.55252,25.00810,121.59216,25.04951];
const groundId='xinyi-street-ground';
const street='#929394',walk='#e6c9a6',path='#dcc5a3',kerb='#e3c477',marking='#f0dfc0';
const asset=new URL('./assets/xinyi-street-ground.json.gz',import.meta.url);
// The narrow full-tower camera reaches street scale below the detail-pack zoom.
const roadOverviewZoom=15.35;
const fade=(z,full)=>['interpolate',['linear'],['zoom'],z,0,full,1];

function unpackRing(values){
  if(values.length<4||values.length%2)throw Error('Invalid Xinyi ground coordinates');
  let lng=121550000,lat=25000000;
  const line=[];
  for(let i=0;i<values.length;i+=2){
    lng+=values[i];lat+=values[i+1];
    line.push([lng/1e6,lat/1e6]);
  }
  return line;
}

export function unpackXinyiGround(packed){
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

// Preserve the single existing markings layer, including its intersections,
// ordering and zoom range. Boundary cells retain the base marking colour.
export function xinyiStreetMarkings(items,cell){
  if(cell.districts?.length!==1||cell.districts[0]!=='信義區')return items;
  return items.map(f=>f.properties.kind==='lane'||f.properties.kind==='crossing'?
    {...f,properties:{...f.properties,xinyiMarking:true}}:f);
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
    const id='xinyi-pavers-'+z;
    map.addImage(id,sidewalkTiles(2**(z-13)),{pixelRatio:2});
    ids.push(id);
  }
  return ['step',['zoom'],ids[0],...ids.slice(1).flatMap((id,i)=>[18+i,id])];
}

function install(map,data){
  // Insert above the legacy street fills while yielding to the exact 101 plot,
  // pond paint, shadows, foreground furniture, survey buildings and all labels.
  const order=map.getStyle().layers;
  const foreground=new Set(['taipei101-single-ground','songyan-woods','atlas-shadows','city170-prepared-lane','city170-prepared-crossing','survey']);
  const before=order.find(layer=>foreground.has(layer.id))?.id;
  map.addSource(groundId,{type:'geojson',data,maxzoom:20,tolerance:0,buffer:96});
  const material=(id,kinds,paint,minzoom=roadOverviewZoom)=>{
    map.addLayer({id:groundId+'-'+id,type:'fill',source:groundId,minzoom,
      filter:['in',['get','kind'],['literal',kinds]],paint:{'fill-antialias':false,...paint}},before);
  };
  material('paving',['walk','path'],{'fill-color':['match',['get','kind'],'path',path,walk],'fill-opacity':fade(roadOverviewZoom,16.25)});
  material('asphalt',['road'],{'fill-color':street,'fill-opacity':fade(roadOverviewZoom,16.25)});
  material('concrete-joints',['walk'],{'fill-pattern':sidewalkPattern(map),
    'fill-opacity':['interpolate',['linear'],['zoom'],17,0,17.9,.55]},17);
  map.addLayer({id:groundId+'-kerb',type:'line',source:groundId,minzoom:16.65,
    filter:['==',['get','kind'],'kerb'],layout:{'line-join':'round','line-cap':'round'},
    paint:{'line-color':kerb,'line-width':['interpolate',['exponential',2],['zoom'],16,.16,21,5.14],
      'line-opacity':fade(16.65,17.4)}},before);
  for(const kind of ['lane','crossing']){
    const id='city170-prepared-'+kind;
    if(!map.getLayer(id))continue;
    const previous=map.getPaintProperty(id,'fill-color');
    map.setPaintProperty(id,'fill-color',['case',['==',['get','xinyiMarking'],true],marking,previous]);
  }
}

export function addXinyiStreetGround(map){
  let request,removed=false,ready=false;
  async function near(){
    if(request||ready||removed||map.getZoom()<roadOverviewZoom)return;
    const [[w,s],[e,n]]=map.getBounds().toArray();
    if(e<extent[0]||n<extent[1]||w>extent[2]||s>extent[3])return;
    request=new AbortController();
    try{
      const response=await fetch(asset,{signal:request.signal});
      if(!response.ok)throw Error('Xinyi street ground '+response.status);
      const data=unpackXinyiGround(await decodeMapJSON(response));
      if(removed)return;
      install(map,data);ready=true;
      map.off('moveend',near);
    }catch(error){
      if(!removed)console.warn('信義區道路',error.message);
    }finally{request=null;}
  }
  map.on('remove',()=>{removed=true;request?.abort();map.off('moveend',near);});
  map.on('moveend',near);
  near();
}
