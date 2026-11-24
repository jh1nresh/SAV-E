export async function readPocketCityAsset(name){
  const url=new URL(`./data/${name}.json.gz`,import.meta.url);
  const response=await fetch(url);
  if(!response.ok||!response.body)throw Error(`Pocket City asset ${response.status} ${name}`);
  const decoded=response.body.pipeThrough(new DecompressionStream('gzip'));
  return new Response(decoded).json();
}

function pavingJoints(){
  const width=16,height=16;
  const pixels=new Uint8Array(width*height*4);
  // A restrained square-concrete joint, layered only over prepared pavement.
  for(let y=0;y<height;y++){
    for(let x=0;x<width;x++){
      if(x===0||y===0)pixels.set([129,101,77,54],(y*width+x)*4);
    }
  }
  return {width,height,data:pixels};
}

export function addPocketCityPaint(map,paintReady){
  let loading=false;
  async function loadAtStreetZoom(){
    if(loading||map.getZoom()<16.5)return;
    loading=true;
    try{
      const data=await readPocketCityAsset('street-pocket-city-paint');
      if(data?.type!=='FeatureCollection'||!Array.isArray(data.features))throw Error('Invalid Pocket City paint data');
      map.off('moveend',loadAtStreetZoom);
      map.addSource('pocket-city-street-paint',{type:'geojson',data,maxzoom:19});
      const before=map.getLayer('atlas-shadows')?'atlas-shadows':'survey';
      for(const [kind,minZoom,fullyVisible,color,opacity] of [
        ['skill-paving',16.5,17.6,'#efdbb7',.85],
        ['lane',17.25,18.05,'#f6edd4',.83],
        ['crossing',16.65,17.45,'#fff2d9',.96],
      ]){
        map.addLayer({
          id:`pocket-city-${kind}`,source:'pocket-city-street-paint',type:'fill',minzoom:minZoom,
          filter:['==',['get','kind'],kind],
          paint:{'fill-color':color,'fill-antialias':false,
            'fill-opacity':['interpolate',['linear'],['zoom'],minZoom,0,fullyVisible,opacity]},
        },before);
      }
      map.addImage('pocket-city-paving-joints',pavingJoints(),{pixelRatio:2});
      map.addLayer({
        id:'pocket-city-paving-joints',source:'pocket-city-street-paint',type:'fill',minzoom:18.35,
        filter:['==',['get','kind'],'skill-paving'],
        paint:{'fill-pattern':'pocket-city-paving-joints','fill-antialias':false,
          'fill-opacity':['interpolate',['linear'],['zoom'],18.35,0,19.25,.71]},
      },before);
      await map.once('idle');
      paintReady();
    }catch(error){
      console.warn(`Pocket City paint: ${error.message}`);
    }
    loading=false;
  }
  map.on('moveend',loadAtStreetZoom);
  loadAtStreetZoom();
}
