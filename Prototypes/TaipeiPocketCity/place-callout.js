import {additionalShopFloor} from './shop-floor-labels.js';
import {setPlacePinEmphasis} from './photo-pin-motion.js';
import {placeButtonIcon} from './place-pins.js?v=category-badges-1';
import {originalPlacePhoto} from './place-photos.js';
import {cityPlaceID,reviewedSavvyPosts} from './savvy-place-sources.js';

export function appleDirections(point){
  if(!Array.isArray(point)||point.length!==2)return null;
  const [lng,lat]=point;
  if(!Number.isFinite(lng)||!Number.isFinite(lat)||Math.abs(lng)>180||Math.abs(lat)>90)return null;
  return 'https://maps.apple.com/?daddr='+lat+','+lng;
}

export function createPlaceCallout(map){
  const card=document.querySelector('#place-card');
  const closeButton=card.querySelector('#place-close');
  const photoButton=card.querySelector('.place-photo');
  const photoImage=photoButton.querySelector('img');
  const original=document.querySelector('#place-original');
  const fullImage=original.querySelector('img');
  const fullCredit=original.querySelector('a');
  const photoIsCurrent=()=>currentPhoto&&(!currentPhoto.remote||Date.now()<currentPhoto.expiresAt);
  photoButton.addEventListener('click',()=>{
    if(!photoIsCurrent())return;
    fullImage.referrerPolicy='no-referrer';
    if(currentPhoto.remote)fullImage.crossOrigin='anonymous';
    else fullImage.removeAttribute('crossorigin');
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
  const directions=card.querySelector('.place-directions');
  const official=card.querySelector('.place-official');
  const postsList=card.querySelector('.savvy-posts');
  const credit=card.querySelector('.photo-credit');
  for(const link of [credit,fullCredit])link.addEventListener('click',event=>{if(!photoIsCurrent())event.preventDefault();});
  const name=card.querySelector('h3');
  const handle=card.querySelector('.sheet-handle');
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const host=window.webkit?.messageHandlers?.pocketMap;
  const nativeSheet=Boolean(host&&window.savvyNativePlaceSheet===true);
  const savedButton=card.querySelector('#place-in-explore');
  const friendButton=card.querySelector('#place-in-friends');
  const choices=card.querySelector('.place-choices');
  let branchPhoto=null,reviewed=[],lastPayload;
  if(nativeSheet)card.classList.add('uses-native-drawer');
  function publish(force=false){
    if(!nativeSheet||card.hidden)return;
    const payload={serial:openSerial,name:name.textContent,kind:kind.textContent,
      address:detail.hidden?'':detail.textContent,directions:directions.hidden?null:directions.href,
      website:official.hidden?null:official.href,websiteLabel:official.hidden?'':official.textContent.replace(/ ↗$/,''),
      photo:branchPhoto&&{file:branchPhoto.file,alt:branchPhoto.alt,credit:branchPhoto.credit,url:branchPhoto.url},
      posts:reviewed.filter(post=>post.expiresAt>Date.now()).map(post=>({platform:post.platform,
        title:post.title||'',author:post.authorHandle||'',url:post.url,expiresAt:post.expiresAt,
        cover:post.cover&&{url:post.cover,expiresAt:Math.min(post.expiresAt,post.coverExpiry),permission:post.coverPermission}})),
      choices:Array.from(choices.children,option=>option.textContent),
      savedActionLabel:savedButton.hidden?null:savedButton.textContent,friendAction:!friendButton.hidden};
    const encoded=JSON.stringify(payload);
    if(force||encoded!==lastPayload){lastPayload=encoded;host.postMessage({event:'placeDetail',detail:payload});}
  }
  const actionsObserver=nativeSheet?new MutationObserver(()=>publish()):null;
  for(const button of [savedButton,friendButton])actionsObserver?.observe(button,
    {attributes:true,attributeFilter:['hidden'],childList:true,characterData:true,subtree:true});
  if(nativeSheet){
    window.savvySyncPlaceSheet=()=>publish(true);
    window.savvyPlaceSheetAction=(serial,action,index)=>{
      if(card.hidden||serial!==openSerial)return;
      if(action==='close')dismiss();
      else if(action==='saved'&&!savedButton.hidden)savedButton.click();
      else if(action==='friend'&&!friendButton.hidden)friendButton.click();
      else if(action==='choice'&&Number.isInteger(index)&&index>=0&&index<choices.children.length)
        choices.children[index].click();
    };
  }
  let anchor=null,trigger=null,currentPhoto=null,activeArt=null,focusMarker=null;
  let slide,expiryTimer,openSerial=0,dragStart;
  function moveFocusMarker(){
    if(!focusMarker||!anchor)return;
    const {x,y}=map.project(anchor);
    focusMarker.style.left=x+'px';focusMarker.style.top=y+'px';
  }
  function reset(){
    openSerial++;branchPhoto=null;reviewed=[];lastPayload=undefined;
    clearTimeout(expiryTimer);
    slide?.cancel();
    slide=null;
    dragStart=undefined;
    if(original.open)original.close();
    trigger?.setAttribute('aria-expanded','false');
    setPlacePinEmphasis(activeArt,false);
    map.off('move',moveFocusMarker);
    focusMarker?.remove();
    focusMarker=null;activeArt=null;anchor=null;currentPhoto=null;trigger=null;
  }
  function close(restoreFocus=false){
    if(card.hidden)return;
    const previous=trigger;
    reset();
    card.hidden=true;
    map.fire('pocketplacechange',{placeId:null});
    host?.postMessage({event:'placeSheet',open:false});
    if(restoreFocus)(previous?.isConnected?previous:map.getCanvas()).focus({preventScroll:true});
  }
  function dismiss(){
    if(card.hidden)return;
    if(nativeSheet){
      // Keep the temporary canvas marker attached while its artwork settles.
      if(focusMarker&&activeArt&&!reduced.matches){
        const marker=focusMarker,point=anchor;
        setPlacePinEmphasis(activeArt,false);
        activeArt=null;focusMarker=null;
        const follow=()=>{const {x,y}=map.project(point);marker.style.left=x+'px';marker.style.top=y+'px';};
        map.on('move',follow);
        const remove=()=>{map.off('move',follow);marker.remove();};
        Promise.allSettled(marker.firstChild.getAnimations().map(animation=>animation.finished)).then(remove);
      }
      close(true);return;
    }
    if(reduced.matches){close(true);return;}
    const from=getComputedStyle(card).transform;
    slide?.cancel();
    setPlacePinEmphasis(activeArt,false);
    activeArt=null;
    slide=card.animate([{transform:from},{transform:'translateY(105%)'}],
      {duration:200,easing:'cubic-bezier(.4,0,.8,.3)',fill:'forwards'});
    slide.onfinish=()=>close(true);
  }
  function emphasize(place){
    // Native marker artwork owns its selection spring. For tile symbols, place
    // a temporary highlight at the selected coordinate without moving the camera.
    if(trigger?.classList.contains('ios-place-pin'))return;
    activeArt=trigger?.querySelector('.photo-badge,canvas');
    if(!activeArt&&anchor){
      focusMarker=document.createElement('span');
      focusMarker.className='place-focus-marker';
      activeArt=placeButtonIcon(place.category??place.kind).canvas;
      focusMarker.append(activeArt);
      map.getCanvasContainer().append(focusMarker);
      moveFocusMarker();
      map.on('move',moveFocusMarker);
    }
    setPlacePinEmphasis(activeArt,true,{repeat:true});
  }
  handle.addEventListener('pointerdown',event=>{
    dragStart=event.clientY;handle.setPointerCapture(event.pointerId);
  });
  handle.addEventListener('pointerup',event=>{
    if(dragStart!==undefined&&event.clientY-dragStart>32)dismiss();
    dragStart=undefined;
  });
  handle.addEventListener('pointercancel',()=>{dragStart=undefined;});
  if(host)window.savvyDismissPlaceSheet=()=>close();
  function showPhoto(photo,fallback=null){
    currentPhoto=photo;
    photoImage.onerror=null;
    photoButton.hidden=credit.hidden=!photo;
    card.classList.toggle('has-photo',Boolean(photo));
    if(!photo){photoImage.removeAttribute('src');return;}
    photoButton.setAttribute('aria-label','查看'+name.textContent+'的完整照片');
    photoImage.alt=photo.alt;
    photoImage.referrerPolicy='no-referrer';
    if(photo.remote)photoImage.crossOrigin='anonymous';
    else photoImage.removeAttribute('crossorigin');
    photoImage.onerror=()=>{showPhoto(fallback);};
    photoImage.src=photo.src;
    credit.textContent=(photo.remote?photo.credit:'攝影 '+photo.credit.split(' · ')[0])+' ↗';
    credit.title=photo.credit;
    credit.href=photo.url;
  }
  async function showPosts(place,serial,localPhoto){
    const posts=await reviewedSavvyPosts(place);
    if(serial!==openSerial)return;
    reviewed=posts;publish();
    const hadFocus=postsList.contains(document.activeElement);
    postsList.replaceChildren();
    const platformName={instagram:'Instagram',threads:'Threads'};
    for(const post of posts){
      const item=document.createElement('li');
      const link=document.createElement('a');
      link.href=post.url;
      link.target='_blank';
      link.rel='noopener noreferrer';
      link.textContent=post.title||'查看'+platformName[post.platform]+'原文';
      link.addEventListener('click',event=>{if(Date.now()>=post.expiresAt)event.preventDefault();});
      const byline=document.createElement('small');
      byline.textContent=platformName[post.platform]+(post.authorHandle?' · @'+post.authorHandle:'');
      item.append(link,byline);
      postsList.append(item);
    }
    postsList.hidden=posts.length===0;
    if(hadFocus)closeButton.focus({preventScroll:true});
    const featured=posts.find(post=>post.cover);
    const coverExpiresAt=featured?Math.min(featured.expiresAt,featured.coverExpiry):undefined;
    const sameOriginal=currentPhoto?.remote&&currentPhoto.src===featured?.cover
      &&currentPhoto.url===featured?.url&&currentPhoto.expiresAt===coverExpiresAt;
    if(currentPhoto?.remote&&!sameOriginal){
      if(original.open)original.close();
      fullImage.removeAttribute('src');
      if(!featured)showPhoto(localPhoto);
    }
    if(!nativeSheet&&featured&&!sameOriginal){
      showPhoto({src:featured.cover,alt:featured.title||name.textContent,remote:true,url:featured.url,
        expiresAt:coverExpiresAt,
        credit:platformName[featured.platform]+(featured.authorHandle?' · @'+featured.authorHandle:'')},localPhoto);
    }
    if(posts.length){
      const expiry=Math.min(...posts.map(post=>post.expiresAt),featured?.coverExpiry??Infinity);
      expiryTimer=setTimeout(()=>showPosts(place,serial,localPhoto),Math.min(2**31-1,Math.max(0,expiry-Date.now())));
    }
  }
  function open(place,button=null){
    const wasOpen=!card.hidden;
    if(map.savvySavedOnly&&!button?.classList.contains('is-saved'))return;
    reset();
    anchor=place.point??null;
    trigger=button;
    button?.setAttribute('aria-expanded','true');
    name.textContent=place.name||place.categoryLabel||'地點';
    kind.textContent=place.kind==='school-label'?'學校':place.categoryLabel??place.kind??'地點';
    const street=place.detail===kind.textContent?'':place.detail;
    const floor=place.indoorFloor?undefined:additionalShopFloor(cityPlaceID(place),place.source,street,kind.textContent);
    detail.textContent=[street,floor].filter(Boolean).join(' · ');
    detail.hidden=!detail.textContent;
    choices.replaceChildren();
    choices.hidden=!place.choices?.length;
    for(const candidate of place.choices??[]){
      const option=document.createElement('button');
      option.type='button';option.textContent=candidate.name||candidate.categoryLabel||'地點';
      const candidateFloor=additionalShopFloor(cityPlaceID(candidate),candidate.source,option.textContent);
      if(candidateFloor)option.textContent+=' · '+candidateFloor;
      option.addEventListener('click',()=>open(candidate));
      choices.append(option);
    }
    const photo=originalPlacePhoto(place);
    branchPhoto=photo;
    if(!nativeSheet)showPhoto(photo);
    postsList.hidden=true;
    postsList.replaceChildren();
    void showPosts(place,openSerial,photo);
    const destination=appleDirections(anchor);
    directions.hidden=!destination;
    if(destination)directions.href=destination;
    else directions.removeAttribute('href');
    const site=URL.canParse(place.url)?new URL(place.url):null;
    const hasSite=site?.protocol==='https:'&&!/(^|\.)openstreetmap\.org$/i.test(site.hostname)&&place.source!=='Savvy';
    official.hidden=!hasSite;
    if(hasSite){
      official.href=site.href;
      official.textContent=(place.source||'官方資訊')+' ↗';
    }else official.removeAttribute('href');
    map.fire('pocketplacechange',{placeId:cityPlaceID(place)});
    card.hidden=false;
    card.scrollTop=0;
    emphasize(place);
    // Reserve the sheet’s possible expanded height on entry so late-arriving
    // posts or a photo never cover the selected pin or trigger another pan.
    if(anchor&&map.panBy&&!place.retainMapCamera){
      const viewport=map.getContainer();
      const point=map.project(anchor);
      const top=viewport.clientHeight-Math.min(viewport.clientHeight*.58,560);
      if((nativeSheet||(point.x>=card.offsetLeft&&point.x<=card.offsetLeft+card.offsetWidth))&&point.y>top-20){
        map.panBy([0,point.y-(top-20)],{duration:reduced.matches?0:260},{pocketPlaceReveal:true});
      }
    }
    if(!wasOpen){
      host?.postMessage({event:'placeSheet',open:true});
      if(!nativeSheet&&!reduced.matches)slide=card.animate([{transform:'translateY(105%)'},{transform:'translateY(0)'}],
        {duration:300,easing:'cubic-bezier(.2,.85,.22,1)'});
    }
    if(nativeSheet)publish();
    else closeButton.focus({preventScroll:true});
  }
  closeButton.addEventListener('click',dismiss);
  card.addEventListener('keydown',event=>{
    if(event.key==='Escape'){event.stopPropagation();dismiss();}
  });
  map.on('remove',()=>{
    close();
    actionsObserver?.disconnect();
    if(nativeSheet){delete window.savvySyncPlaceSheet;delete window.savvyPlaceSheetAction;}
    if(host)delete window.savvyDismissPlaceSheet;
  });
  return {open,close,dismiss,get trigger(){return trigger;}};
}
