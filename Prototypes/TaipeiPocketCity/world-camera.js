// Keep the full longitude range visible on portrait displays. The default Mercator
// constraints instead increase zoom until a single map fills both dimensions.
export const worldBounds=[[-179,-55],[179,74]];
export function constrainWorldCamera(center,zoom,width,height){
  const clamp=(value,min,max)=>Math.max(min,Math.min(value,max));
  const overviewScale=Math.max(1,Math.min(width,height));
  const level=clamp(zoom,Math.max(-2,Math.log2(overviewScale/512)),21.6);
  const size=512*2**level;
  const xMargin=Math.min(.5,width/(2*size));
  const yMargin=Math.min(.5,height/(2*size));
  const lat=clamp(center.lat,-85.051129,85.051129)*Math.PI/180;
  const y=clamp((1-Math.asinh(Math.tan(lat))/Math.PI)/2,yMargin,1-yMargin);
  return {center:{lng:clamp(center.lng,-180+360*xMargin,180-360*xMargin),
    lat:Math.atan(Math.sinh(Math.PI*(1-2*y)))*180/Math.PI},zoom:level};
}
