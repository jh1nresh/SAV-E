// Savvy's metro map integrates each spring in steps no longer than 4 ms.
// Sample the same response once; the browser can play it without a JS frame loop.
function spring(response,damping){
  const frequency=2*Math.PI/response;
  let progress=0,velocity=0;
  const samples=[0];
  do{
    for(let i=0;i<4;i++){
      velocity+=(frequency*frequency*(1-progress)-2*damping*frequency*velocity)*.004;
      progress+=velocity*.004;
    }
    samples.push(progress);
  }while(Math.abs(1-progress)>=.002||Math.abs(velocity)>=.008);
  samples[samples.length-1]=1;
  return {samples,duration:(samples.length-1)*16};
}

const badge=spring(.46,.61);
const closing=spring(.20,.95);

export function bouncePhotoPin(element,from){
  if(!element||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  element.getAnimations().forEach(animation=>animation.cancel());
  element.animate(badge.samples.map(p=>({transform:'scale('+(from+(1-from)*p)+')'})),{duration:badge.duration});
}

export function setPlacePinEmphasis(art,selected,{animate=true,repeat=false}={}){
  if(!art)return;
  const computed=getComputedStyle(art);
  const start=Number.parseFloat(computed.scale)||1;
  const angle=Number.parseFloat(computed.rotate)||0;
  const end=selected?1.28:1;
  art.getAnimations().forEach(animation=>animation.cancel());
  art.style.scale=String(end);
  if(!animate||matchMedia('(prefers-reduced-motion: reduce)').matches||(!repeat&&start===end&&!angle))return;
  const curve=selected?badge:closing;
  const swing=[0,-7,5,-2.5,0.8,0];
  const frames=curve.samples.map((value,index)=>{
    const phase=index/(curve.samples.length-1);
    const position=Math.min(5,phase*6.5);
    const segment=Math.floor(position);
    const tilt=selected?(swing[segment]+((swing[segment+1]??0)-swing[segment])*(position-segment)):0;
    return {scale:String(start+(end-start)*value),rotate:angle*(1-phase)+tilt+'deg'};
  });
  art.animate(frames,{duration:curve.duration});
}
