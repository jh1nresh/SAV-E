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
const opening=spring(.22,.9);
const closing=spring(.20,.95);
const limit=value=>Math.max(0,Math.min(1,value));

export function bouncePhotoPin(element,from){
  if(!element||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  element.getAnimations().forEach(animation=>animation.cancel());
  element.animate(badge.samples.map(p=>({transform:'scale('+(from+(1-from)*p)+')'})),{duration:badge.duration});
}

export function morphPlaceCard(card,photo,origin,reverse=false){
  const curve=reverse?closing:opening;
  const fractions=curve.samples.map(p=>reverse?1-p:p);
  const options={duration:curve.duration,fill:'both'};
  const cover=card.querySelector('.place-morph');
  cover.style.backgroundImage=photo?'url("'+photo.src+'")':'none';
  const width=card.offsetWidth,height=card.offsetHeight;
  const diameter=origin.diameter;
  const frames=fractions.map(p=>{
    const remaining=1-p;
    const x=(origin.x-diameter/2)*remaining,y=(origin.y-diameter/2)*remaining;
    const scaleX=p+remaining*diameter/width,scaleY=p+remaining*diameter/height;
    return {transformOrigin:'0 0',transform:`translate(${x}px,${y}px) scale(${scaleX},${scaleY})`,
      borderRadius:(13+278*(1-limit(p))**1.6)+'px'};
  });
  const shape=card.animate(frames,options);
  const animations=[shape,cover.animate(fractions.map(p=>({opacity:limit(1-(p-.05)*2.4)})),options)];
  const contentFrames=fractions.map(p=>({opacity:limit((p-.18)*2.2)}));
  for(const element of card.querySelectorAll(':scope > :not(.place-morph)')){
    animations.push(element.animate(contentFrames,options));
  }
  card.classList.add('morphing');
  const cancel=()=>{
    animations.forEach(a=>a.cancel());
    card.classList.remove('morphing');
  };
  return {shape,cancel};
}
