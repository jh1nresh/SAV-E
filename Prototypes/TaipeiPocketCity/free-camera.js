// MapLibre owns gestures; the controls offer equivalent single-pointer and keyboard actions.
export const destinations={
  taipei:{center:[121.56481,25.03367],zoom:16.3,pitch:54,bearing:-54},
  songyan:{center:[121.56149,25.04350],zoom:17.2,pitch:46,bearing:-65},
  tamsui:{center:[121.4328251,25.1752279],zoom:18.32,pitch:52,bearing:18},
  jiufen:{center:[121.8436223,25.1084473],zoom:19.55,pitch:49,bearing:143},
  shanghai:{center:[121.4859379,31.2380855],zoom:17.95,pitch:52,bearing:-17},
  beijing:{center:[116.4060983,39.8822385],zoom:17.95,pitch:52,bearing:-17},
  la:{center:[-118.30036,34.1184],zoom:17.95,pitch:52,bearing:-17},
};
export function installFreeCamera(map,stage,{locate}){
  const panel=stage.querySelector('#free-camera');
  const bearing=panel.querySelector('#camera-bearing'),pitch=panel.querySelector('#camera-pitch');
  const direction=panel.querySelector('#bearing-value'),angle=panel.querySelector('#pitch-value');
  const select=panel.querySelector('#globe-destination');
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const controller=new AbortController(),{signal}=controller;
  const listen=(element,event,fn)=>element.addEventListener(event,fn,{signal});
  let userInteracted=false;
  const claim=()=>{userInteracted=true;};
  listen(stage,'pointerdown',claim);
  stage.addEventListener('wheel',claim,{signal,capture:true,passive:true});
  listen(stage,'keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End','PageUp','PageDown','+','=','-','Enter',' '].includes(e.key))claim();});
  listen(panel,'input',claim);listen(panel,'change',claim);
  const sync=()=>{
    bearing.value=String(Math.round(((map.getBearing()+180)%360+360)%360-180));
    pitch.value=String(Math.round(map.getPitch()));
    direction.value=bearing.value+'°';angle.value=pitch.value+'°';
    stage.dataset.camera=JSON.stringify({center:map.getCenter().toArray(),zoom:map.getZoom(),bearing:map.getBearing(),pitch:map.getPitch()});
  };
  listen(bearing,'input',()=>{map.stop();map.setBearing(Number(bearing.value));});
  listen(pitch,'input',()=>{map.stop();map.setPitch(Number(pitch.value));});
  listen(select,'change',()=>{const place=destinations[select.value];if(place)locate(place);});
  for(const button of panel.querySelectorAll('[data-pan]'))listen(button,'click',()=>{
    map.stop();
    const offsets={left:[-140,0],right:[140,0],up:[0,-140],down:[0,140]};
    map.panBy(offsets[button.dataset.pan],{duration:reduced.matches?0:180});
  });
  map.dragPan.enable();map.dragRotate.enable();map.touchZoomRotate.enable();map.touchZoomRotate.enableRotation();map.touchPitch.enable();
  map.on('move',sync);sync();
  map.once('remove',()=>{controller.abort();map.off('move',sync);});
  return {get userInteracted(){return userInteracted;}};
}
