// Two natural-grassland footprints between Guanshan Riverside Park's paths and the Keelung River.
import {decodeMapJSON} from './pocket-city-atlas.js';

const source='songshan-river-meadow';
const bounds=[121.56915,25.06143,121.56967,25.06222];
const fade=(start,end,value)=>['interpolate',['linear'],['zoom'],start,0,end,value];

// Each transparent sprite is a low fan of grass. The map keeps the toe on the
// ground as it pitches, while the blades stand upright above the small shadow.
function grassSprite(variant){
  const canvas=document.createElement('canvas');
  canvas.width=80;canvas.height=42;
  const ctx=canvas.getContext('2d');
  ctx.scale(2,2);
  ctx.fillStyle='rgba(66,91,65,.30)';
  ctx.beginPath();ctx.ellipse(19,18.5,15.5,2.3,0,0,Math.PI*2);ctx.fill();
  const blades=[
    [9,2,6],[13,7,2],[16,13,4],[21,19,1],[23,28,3],[27,34,7],[30,38,11],
    [9,4,10],[14,10,7],[17,16,5],[19,24,6],[25,29,8],[29,35,12],
  ];
  const colors=['#648562','#80a16c','#9fb57b','#bfd08e'];
  for(const [i,[base,tip,top]] of blades.entries()){
    const drift=variant===1?2:variant===2?-1:0;
    const x=tip+drift, y=top+((i+variant)%3);
    ctx.fillStyle=colors[(i<7?i%2:1+i%3)];
    ctx.beginPath();ctx.moveTo(base-1.6,18.8);
    ctx.quadraticCurveTo(base-1,13,x,y);
    ctx.quadraticCurveTo((x+base)/2+1.4,13.4,base+1.5,18.8);
    ctx.closePath();ctx.fill();
  }
  return ctx.getImageData(0,0,canvas.width,canvas.height);
}

export function addSongshanRiverMeadow(map,firstLabel){
  let activeRequest=null,installed=false,removed=false;
  function overlaps(view,pad){
    return view.getWest()<=bounds[2]+pad&&view.getEast()>=bounds[0]-pad&&
      view.getSouth()<=bounds[3]+pad&&view.getNorth()>=bounds[1]-pad;
  }
  function unload(){
    for(const suffix of ['-clumps','-cover']){
      if(map.getLayer(source+suffix))map.removeLayer(source+suffix);
    }
    if(map.getSource(source))map.removeSource(source);
    for(let i=0;i<3;i++)if(map.hasImage(source+'-'+i))map.removeImage(source+'-'+i);
    installed=false;
  }
  async function load(){
    const request=new AbortController();
    activeRequest=request;
    try{
      const response=await fetch(new URL('./assets/songshan-river-meadow.json.gz',import.meta.url),{signal:request.signal});
      if(request.signal.aborted)return;
      if(!response.ok)throw Error(String(response.status));
      const data=await decodeMapJSON(response);
      if(removed||request.signal.aborted)return;
      if(data.type!=='FeatureCollection'||!data.features?.length)throw Error('Missing Guanshan grassland');
      const anchor=map.getLayer('city170-pitch')?'city170-pitch':firstLabel;
      for(let i=0;i<3;i++)map.addImage(source+'-'+i,grassSprite(i),{pixelRatio:2});
      map.addSource(source,{type:'geojson',data,maxzoom:20,tolerance:0,
        attribution:'<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a>'});
      map.addLayer({id:source+'-cover',type:'fill',source,minzoom:15.2,filter:['==',['get','kind'],'grassland'],
        paint:{'fill-color':'#b2c387','fill-opacity':fade(15.2,16.8,.91)}},anchor);
      map.addLayer({id:source+'-clumps',type:'symbol',source,minzoom:16.25,filter:['==',['get','kind'],'clump'],
        layout:{'icon-image':['concat',source+'-',['to-string',['get','form']]],
          'icon-size':['interpolate',['exponential',2],['zoom'],16,['*',.078,['get','scale']],21,['*',2.496,['get','scale']]],
          'icon-anchor':'bottom','icon-allow-overlap':true,'icon-ignore-placement':true,
          'icon-rotation-alignment':'viewport','icon-pitch-alignment':'viewport'},
        paint:{'icon-opacity':fade(16.25,17.25,1)}},anchor);
      installed=true;
    }catch(error){
      if(!removed&&!request.signal.aborted){
        unload();
        console.warn('Guanshan river meadow',error);
      }
    }finally{if(activeRequest===request)activeRequest=null;}
  }
  function update(){
    if(removed)return;
    const view=map.getBounds(),visible=map.getZoom()>=15.2;
    // Retain a roughly 200 m margin after entry so a short pan can return immediately.
    if(!visible||!overlaps(view,.002)){
      activeRequest?.abort();activeRequest=null;
      if(installed)unload();
    }else if(!activeRequest&&!installed&&overlaps(view,0))return load();
  }
  map.on('remove',()=>{
    removed=true;activeRequest?.abort();map.off('moveend',update);
  });
  map.on('moveend',update);
  update();
}
