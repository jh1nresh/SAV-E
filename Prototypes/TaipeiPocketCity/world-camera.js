// Use the same hemisphere and framing for first open and the return-to-globe control.
export function globeCamera(width,height){
  const center=[124,24];
  const diameter=Math.min(Math.max(1,width),Math.max(1,height))*.80;
  // MapLibre scales the globe at the latitude under the camera.
  const circumference=diameter*Math.PI*Math.cos(center[1]*Math.PI/180);
  return {center,zoom:Math.max(-2,Math.min(4,Math.log2(circumference/512))),bearing:0,pitch:0};
}

export function returnToGlobe(map,camera,reducedMotion){
  map.stop();
  const finish=()=>map.easeTo({...camera,duration:reducedMotion?0:650});
  if(map.getZoom()<10){finish();return;}
  // A street-projection flight constrains its destination to a flat viewport.
  // Let the globe render before calculating the final sweep to East Asia.
  const globeZoom=8;
  map.once('moveend',()=>map.once('render',()=>{
    if(!map.isMoving()&&Math.abs(map.getZoom()-globeZoom)<.01)finish();
  }));
  map.easeTo({zoom:globeZoom,pitch:0,bearing:0,duration:reducedMotion?0:550});
}
