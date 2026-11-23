import {morphPlaceCard} from './photo-pin-motion.js';
import {originalPlacePhoto} from './place-photos.js';

export function createPlaceCallout(map,setExpandedPhoto=()=>{}){
  const card=document.querySelector('#place-card');
  const closeButton=card.querySelector('#place-close');
  const photoButton=card.querySelector('.place-photo');
  const photoImage=photoButton.querySelector('img');
  const original=document.querySelector('#place-original');
  const fullImage=original.querySelector('img');
  const fullCredit=original.querySelector('a');
  photoButton.addEventListener('click',()=>{
    if(!currentPhoto)return;
    fullImage.src=currentPhoto.src;
    fullImage.alt=currentPhoto.alt;
    original.querySelector('strong').textContent=name.textContent;
    fullCredit.textContent=currentPhoto.credit;
    fullCredit.href=currentPhoto.url;
    original.showModal();
  });
  original.addEventListener('click',event=>{if(event.target===original)original.close();});
  const kind=card.querySelector('.place-kind');
  const detail=card.querySelector('.place-detail');
  const source=card.querySelector('.place-source');
  const name=card.querySelector('h3');
  const scene=map.getContainer();
  let anchor=null,trigger=null,currentPhoto=null,entering=false;
  let pop,origin;
  function animateCard(reverse=false){
    pop?.cancel();
    const motion=morphPlaceCard(card,currentPhoto,origin,reverse);
    pop=motion;
    motion.shape.onfinish=()=>{
      if(pop!==motion)return;
      if(reverse){close(true);return;}
      motion.cancel();
      pop=null;
    };
  }
  function reveal(){
    if(!entering)return;
    entering=false;
    if(!matchMedia('(prefers-reduced-motion: reduce)').matches)animateCard();
    closeButton.focus({preventScroll:true});
  }
  function dismiss(){
    if(!origin||matchMedia('(prefers-reduced-motion: reduce)').matches){close(true);return;}
    // Dismiss immediately if the user interrupts the opening or closing motion.
    if(pop){close(true);return;}
    animateCard(true);
  }
  function position(){
    if(!anchor)return;
    const {x,y}=map.project(anchor);
    const width=scene.clientWidth,height=scene.clientHeight;
    const visible=x>=0&&x<=width&&y>=0&&y<=height;
    card.style.visibility=visible?'':'hidden';
    if(!visible)return;
    const w=card.offsetWidth,h=card.offsetHeight;
    const gap=currentPhoto?8:17;
    const above=y-h-gap>=8;
    const top=above?y-h-gap:y+gap;
    const left=Math.max(8,Math.min(width-w-8,x-w/2));
    card.style.left=left+'px';
    const cardTop=Math.max(8,Math.min(height-h-8,top));
    card.style.top=cardTop+'px';
    const diameter=currentPhoto?38:20;
    origin={diameter,x:x-left,y:y-cardTop-(currentPhoto?diameter/2+3:0)};
    card.style.setProperty('--tip',Math.max(15,Math.min(w-15,x-left))+'px');
    card.classList.toggle('below',!above);
    reveal();
  }
  function close(restoreFocus=false){
    pop?.cancel();
    pop=null;
    const previous=trigger;
    if(original.open)original.close();
    entering=false;
    origin=null;
    anchor=null;
    currentPhoto=null;
    trigger=null;
    card.hidden=true;
    setExpandedPhoto(null,restoreFocus);
    previous?.setAttribute('aria-expanded','false');
    if(restoreFocus)(previous?.isConnected?previous:map.getCanvas()).focus({preventScroll:true});
  }
  function open(place,button=null){
    close();
    anchor=place.point??null;
    trigger=button;
    button?.setAttribute('aria-expanded','true');
    name.textContent=place.name||place.categoryLabel||'地點';
    kind.textContent=place.kind==='school-label'?'學校':place.categoryLabel??place.kind??'地點';
    const street=(place.detail??'').replace(/[０-９0-9]+(?:[之－-][０-９0-9]+)?\s*號.*$/u,'').trim();
    detail.textContent=street;
    detail.hidden=!street||street===kind.textContent;
    const choices=card.querySelector('.place-choices');
    choices.replaceChildren();
    choices.hidden=!place.choices?.length;
    for(const candidate of place.choices??[]){
      const option=document.createElement('button');
      option.type='button';option.textContent=candidate.name||candidate.categoryLabel||'地點';
      option.addEventListener('click',()=>open(candidate));
      choices.append(option);
    }
    const photo=originalPlacePhoto(place,anchor);
    currentPhoto=photo;
    setExpandedPhoto(photo?.src??null);
    photoImage.onerror=null;
    photoButton.hidden=!photo;
    card.classList.toggle('has-photo',Boolean(photo));
    if(photo){
      photoButton.setAttribute('aria-label','查看'+name.textContent+'的完整照片');
      photoImage.alt=photo.alt;
      photoImage.onerror=()=>{
        photoButton.hidden=true;
        card.classList.remove('has-photo');
        position();
      };
      photoImage.src=photo.src;

    }else{
      photoImage.removeAttribute('src');
    }
    const credit=card.querySelector('.photo-credit');
    credit.hidden=!photo;
    if(photo){
      credit.textContent='攝影 '+photo.credit.split(' · ')[0]+' ↗';
      credit.title=photo.credit;
      credit.href=photo.url;
    }
    const url=place.url;
    source.hidden=!url;
    if(url){
      source.href=url;
      source.textContent=(place.source??(url.startsWith('https://www.openstreetmap.org/')?'OpenStreetMap':'官方資訊'))+' ↗';
    }
    card.hidden=false;
    card.style.visibility='';
    card.classList.toggle('anchored',Boolean(anchor));
    entering=true;
    position();
    if(!anchor){origin={x:card.offsetWidth/2,y:card.offsetHeight,diameter:38};reveal();}
  }
  closeButton.addEventListener('click',dismiss);
  card.addEventListener('keydown',event=>{
    if(event.key==='Escape'){event.stopPropagation();dismiss();}
  });
  map.on('move',position);
  map.on('moveend',()=>{
    position();
    if(anchor&&card.style.visibility==='hidden')close(card.contains(document.activeElement));
  });
  new ResizeObserver(position).observe(card);
  return {open,close,dismiss,get trigger(){return trigger;}};
}
