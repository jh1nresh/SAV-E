import {readPocketCityAsset} from './pocket-city-atlas.js';

const materials=[
  ['woods','#8fa363',.88],['shore','#ada380',1],
  ['water','#637e70',1],['edge','#a2b095',.85],['deep','#4b7c79',1],
  ['court','#caba9b',.94],['garden','#7e9a62',.95],
  ['walk-edge','#ac9275',.92],['walk','#d8b792',1],['joint','#b49a81',.67],
  ['ripple','#a5c0ac',.44],
];
const assetVersion='songyan-v5';

function addSongyanSurface(map,ground){
  const source='songyan-waterfront';
  const beneath=map.getLayer('atlas-shadows')?'atlas-shadows':'survey';
  map.addSource(source,{type:'geojson',data:ground,maxzoom:19});
  const layers=materials.map(([kind,color,opacity])=>{
    const id='songyan-'+kind;
    map.addLayer({
      id,type:'fill',source,minzoom:17,
      filter:['==',['get','kind'],kind],
      paint:{'fill-color':color,'fill-outline-color':color,
        'fill-opacity':['interpolate',['linear'],['zoom'],17,0,17.45,opacity]},
    },beneath);
    return id;
  });
  return ()=>{for(const id of layers)map.moveLayer(id,beneath);};
}

function validSongyan(asset){
  return asset?.id==='songyan'&&asset.file===assetVersion&&Number.isFinite(asset.mx)&&Number.isFinite(asset.my)&&asset.m>0&&
    Number.isInteger(asset.verts)&&asset.verts>0&&asset.box?.length===4&&asset.box.every(Number.isFinite)&&
    asset.limit?.length===4&&asset.limit.every(Number.isFinite)&&asset.matches?.length===4&&
    asset.matches.every(row=>Array.isArray(row)&&row.length===3&&row.every(Number.isFinite))&&
    asset.ground?.type==='FeatureCollection'&&Array.isArray(asset.ground.features);
}

export function loadSongyanNear(map,onReady){
  let pending=false,retryAfter=0,order;
  const extent=[121.5591,25.0425,121.5629,25.0444];
  async function near(){
    if(pending||Date.now()<retryAfter||map.getZoom()<16.55)return;
    const [[w,s],[e,n]]=map.getBounds().toArray();
    if(e<extent[0]||n<extent[1]||w>extent[2]||s>extent[3])return;
    pending=true;
    try{
      const asset=await readPocketCityAsset(`city-streets/${assetVersion}`);
      if(!validSongyan(asset))throw Error('Invalid Songyan scene');
      order=addSongyanSurface(map,asset.ground);
      onReady(asset);
      map.off('moveend',near);
    }catch(error){
      retryAfter=Date.now()+3000;
      console.warn('Songyan close-up:',error.message);
    }finally{pending=false;}
  }
  map.on('moveend',near);
  near();
  return ()=>order?.();
}
