import {update101Weather} from './taipei101-single-ground.js';
import {asphaltColors} from './taipei-asphalt.js';
const tileSize=166;
const weatherProfiles={
  day:{shadow:1,umbrellaShare:0},
  cloudy:{shadow:.38,umbrellaShare:0,ground:{
    'walk':'#e3cfad','plaza':'#d5bdab',
  },paving:'#e4d5b8'},
  drizzle:{shadow:.27,umbrellaShare:2,ground:{
    'road-edge':'#b8aa99','walk':'#dfc5a1','walk-edge':'#b9876e','plaza':'#cfb09a',
  },paving:'#dfc9a7',drops:24,dropLength:5},
  rain:{shadow:.16,umbrellaShare:3,ground:{
    'road-edge':'#a49a8b','walk':'#cdb093','walk-edge':'#a57760','plaza':'#beaa99',
  },paving:'#c9b496',drops:60,dropLength:11},
};

function rainTexture(count,baseLength){
  const canvas=document.createElement('canvas');
  canvas.width=canvas.height=tileSize;
  const context=canvas.getContext('2d');
  for(let i=0;i<count;i++){
    const x=(i*1697+i*i*139)%158+5;
    const y=(i*1589+i*i*61)%146+2;
    const length=baseLength+i%7;
    context.strokeStyle=i%3===0?'rgba(73,100,133,.40)':'rgba(231,244,249,.66)';
    context.lineWidth=i%4===0?1.05:.65;
    context.beginPath();
    context.moveTo(x,y);
    context.lineTo(x-length*.23,y+length);
    context.stroke();
  }
  return canvas.toDataURL();
}

export function addPocketCityWeather(map,stage,setStreetRain,initialWeather){
  const rain=stage.querySelector('#rain');
  const selector=stage.querySelector('#weather-select');
  const clearPaint=new Map(),textures=new Map();
  let mode=Object.hasOwn(weatherProfiles,initialWeather)?initialWeather:'day';

  function paint(id,property,adjustedValue){
    if(!map.getLayer(id))return;
    if(!clearPaint.has(id))clearPaint.set(id,map.getPaintProperty(id,property));
    map.setPaintProperty(id,property,adjustedValue??clearPaint.get(id));
  }

  function refresh(){
    const profile=weatherProfiles[mode];
    const color=asphaltColors[mode];
    if(map.getGlobalState().taipeiAsphalt!==color){
      map.setGlobalStateProperty('taipeiAsphalt',color);
      map.fire('pocketasphalt',{color});
    }
    update101Weather(map,mode);
    for(const {id} of map.getStyle().layers){
      const kind=id.match(/^street-.+?-(road-edge|walk-edge|road|walk|plaza)$/)?.[1];
      if(kind&&kind!=='road')paint(id,'fill-color',profile.ground?.[kind]);
    }
    for(const kind of ['road-edge','walk']){
      paint('city170-'+kind,'line-color',profile.ground?.[kind]);
    }
    paint('city170-prepared-skill-paving','fill-color',profile.paving);
    paint('pocket-city-skill-paving','fill-color',profile.paving);
    paint('atlas-shadows','raster-opacity',['interpolate',['linear'],['zoom'],16.4,0,17.75,profile.shadow]);
    if(profile.drops){
      if(!textures.has(mode))textures.set(mode,rainTexture(profile.drops,profile.dropLength));
      rain.style.backgroundImage=`url("${textures.get(mode)}")`;
    }
    rain.hidden=!profile.drops;
    stage.dataset.weather=mode;
    selector.value=mode;
    setStreetRain(profile.umbrellaShare);
  }

  selector.hidden=false;
  function setMode(next){
    if(!Object.hasOwn(weatherProfiles,next)||mode===next)return;
    mode=next;
    refresh();
  }
  selector.addEventListener('change',()=>{
    setMode(selector.value);
    const url=new URL(location.href);
    if(mode==='day')url.searchParams.delete('weather');
    else url.searchParams.set('weather',mode);
    history.replaceState(null,'',url);
  });
  refresh();
  return {refresh,setMode,state:()=>mode};
}
