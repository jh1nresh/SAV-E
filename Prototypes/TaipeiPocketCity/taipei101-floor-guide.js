// The mall publishes schematic floor guides without geographic control points.
// Show the original in a labelled inset so its symbols cannot be mistaken for surveyed coordinates.
const floorFiles = {B1:'b1','1F':'f1','2F':'f2','3F':'f3','4F':'f4','5F':'f5','6F':'f6'};
const official = 'https://www.taipei-101.com.tw';

export function addOfficialFloorGuide(stage,{allowRemoteImages}) {
  if(!allowRemoteImages)return;
  const panel=document.createElement('details');
  panel.id='mall101-official-guide';
  panel.hidden=true;
  panel.open=true;
  const title=document.createElement('summary');
  const zoom=document.createElement('button');
  zoom.type='button';
  const source=document.createElement('a');
  source.textContent='台北 101 官網 ↗';
  source.target='_blank';
  source.rel='noopener noreferrer';
  panel.append(title,zoom,source);
  stage.append(panel);
  let activeFloor,expanded=false;
  function resize(next) {
    expanded=next;
    panel.classList.toggle('enlarged',expanded);
    zoom.setAttribute('aria-expanded',String(expanded));
    zoom.setAttribute('aria-label', (expanded?'縮小':'放大')+'館方樓層示意圖');
  }
  zoom.addEventListener('click',()=>resize(!expanded));
  panel.addEventListener('toggle',()=>{if(!panel.open)resize(false);});
  stage.addEventListener('mall101-floor',event=>{
    const floor=event.detail?.floor;
    if(!Object.hasOwn(floorFiles,floor)) {
      panel.hidden=true;
      activeFloor=null;
      return;
    }
    if(activeFloor===floor)return;
    if(!activeFloor){panel.open=true;resize(false);}
    activeFloor=floor;
    panel.hidden=false;
    title.textContent=floor+' 館方樓層示意';
    source.href=official+'/tw/shopping/floorcon/'+floor;
    const image=new Image();
    image.alt='台北 101 購物中心 '+floor+' 樓層示意圖';
    image.referrerPolicy='no-referrer';
    zoom.hidden=true;
    image.onload=()=>{if(zoom.firstChild===image)zoom.hidden=false;};
    image.onerror=()=>{if(zoom.firstChild===image){zoom.hidden=true;resize(false);}};
    zoom.replaceChildren(image);
    image.src=official+'/asset/img/map/'+floorFiles[floor]+'.svg';
  });
}
