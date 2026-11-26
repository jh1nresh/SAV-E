const collection=features=>({type:'FeatureCollection',features});
const lineFeature=({line,coords},lines)=>({
  type:'Feature',properties:{color:line?lines[line].color:'#5d695c',transfer:!line},
  geometry:{type:'LineString',coordinates:coords},
});
const meters=([x1,y1],[x2,y2])=>Math.hypot((x2-x1)*100770,(y2-y1)*111195);

function itinerary(edges,start,end){
  const adjacent=new Map();
  function connect(edge){
    const available=adjacent.get(edge.a)??[];
    available.push(edge);
    adjacent.set(edge.a,available);
  }
  for(const edge of edges){
    connect(edge);
    connect({...edge,a:edge.b,b:edge.a,coords:[...edge.coords].reverse()});
  }
  const seen=new Set();
  const queue=[{station:start,line:null,cost:0,legs:[]}];
  while(queue.length){
    queue.sort((a,b)=>a.cost-b.cost);
    const step=queue.shift();
    const key=JSON.stringify([step.station,step.line]);
    if(seen.has(key))continue;
    if(step.station===end)return step.legs;
    seen.add(key);
    for(const edge of adjacent.get(step.station)??[]){
      const transfer=step.line!==null&&step.line!==edge.line;
      queue.push({station:edge.b,line:edge.line,cost:step.cost+1+(transfer?3:0),legs:[...step.legs,edge]});
    }
  }
  return [];
}

function addTransferLinks(legs){
  return legs.flatMap((edge,i)=>{
    const previous=legs[i-1];
    if(!previous||previous.line===edge.line)return [edge];
    const platform=previous.coords.at(-1);
    return meters(platform,edge.coords[0])>3
      ?[{line:null,coords:[platform,edge.coords[0]]},edge]:[edge];
  });
}

function sampleLegs(legs){
  let length=0;
  const samples=[];
  for(const {line,coords} of legs){
    for(let i=1;i<coords.length;i++){
      const start=coords[i-1],end=coords[i];
      const distance=meters(start,end);
      if(!distance)continue;
      samples.push({start,end,offset:length,distance,line});
      length+=distance;
    }
  }
  return {samples,length};
}

// Keep the geographic point visible while a long station name opens toward the map interior.
export function stationLabelX(x,r,width){
  if(x<0||x>width||2*r+10>width)return null;
  return Math.max(5+r,Math.min(width-5-r,x));
}

export function addMetroPreview(map,Marker,data,openByDefault){
  const {lines,stations,edges}=data;
  const control=document.querySelector('#metro-toggle');
  const panel=document.querySelector('#metro-panel');
  const status=document.querySelector('#metro-status');
  const actions=panel.querySelector('.metro-actions');
  const reset=document.querySelector('#metro-reset');
  const play=document.querySelector('#metro-play');
  const reduceMotion=matchMedia('(prefers-reduced-motion: reduce)');
  let publicNames=true;
  let visible=false,start=null,end=null,legs=[],animation=0;
  let train;
  map.addSource('metro-network',{type:'geojson',data:collection(edges.map(edge=>lineFeature(edge,lines))),
    attribution:'<a href="https://data.gov.tw/dataset/121208" target="_blank" rel="noopener">臺北市捷運工程局路網</a>'});
  map.addSource('metro-selected',{type:'geojson',data:collection([])});
  const displayLayers=[
    {id:'metro-network-line',source:'metro-network',color:['get','color'],width:3,opacity:.62},
    {id:'metro-selection-border',source:'metro-selected',color:'#fffae9',width:8,opacity:1},
    {id:'metro-selection-line',source:'metro-selected',color:['get','color'],width:5,opacity:1},
    {id:'metro-transfer',source:'metro-selected',color:['get','color'],width:3,opacity:.9},
  ];
  for(const {id,source,color,width,opacity} of displayLayers){
    map.addLayer({id,type:'line',source,
      layout:{visibility:'none','line-cap':'round','line-join':'round'},
      ...(source==='metro-selected'?{filter:['==',['get','transfer'],id==='metro-transfer']}:{}),
      paint:{'line-color':color,'line-width':width,'line-opacity':opacity,
        ...(id==='metro-transfer'?{'line-dasharray':[1,1.4]}:{})}});
  }

  const markers=Object.entries(stations).map(([id,station])=>{
    const button=document.createElement('button');
    button.type='button';
    button.className='metro-station';
    button.dataset.station=id;
    button.setAttribute('aria-label',`${station.name}${station.name.endsWith('站')?'':'站'} ${Object.values(station.codes).join('、')}`);
    button.setAttribute('aria-pressed','false');
    for(const [key,code] of Object.entries(station.codes)){
      const badge=document.createElement('span');
      badge.style.setProperty('--station-line',lines[key].color);
      badge.textContent=code;
      button.append(badge);
    }
    const label=document.createElement('b');
    label.textContent=station.name;
    button.append(label);
    const marker=new Marker({element:button,anchor:'center'}).setLngLat(station.point);
    button.addEventListener('click',event=>{
      event.stopPropagation();
      if(!visible)setVisible(true);
      if(end||!start){start=id;end=null;}
      else if(start===id)start=null;
      else end=id;
      updateSelection();
    });
    return {id,station,button,marker,active:false};
  }).sort((a,b)=>Object.keys(b.station.codes).length-Object.keys(a.station.codes).length);

  function updateMarkers(){
    if(visible&&!start)status.textContent=map.getZoom()<12.4?'放大後點兩站看路線與轉乘':'點兩站看路線與轉乘';
    const extent=map.getBounds();
    const occupied=[];
    const width=map.getContainer().clientWidth;
    const height=map.getContainer().clientHeight;
    const selected=({id})=>id===start||id===end;
    for(const entry of [...markers].sort((a,b)=>Number(selected(b))-Number(selected(a)))){
      const {id,station,marker,button}=entry;
      const showStations=visible?map.getZoom()>=12.4:publicNames&&map.getZoom()>=14.9;
      let active=showStations&&extent.contains(station.point);
      if(active){
        const {x,y}=map.project(station.point);
        const r=station.name.length*5.5+Object.keys(station.codes).length*12.5+9;
        const labelX=stationLabelX(x,r,width);
        active=labelX!==null&&y>14&&y<height-14&&
          (selected(entry)||!occupied.some(q=>Math.abs(q.x-labelX)<q.r+r&&Math.abs(q.y-y)<27));
        if(active){
          occupied.push({x:labelX,y,r});
          const shift=Math.round(labelX-x);
          if(shift!==entry.shift){
            marker.setOffset([shift,0]);
            button.style.setProperty('--metro-shift',shift+'px');
            button.classList.toggle('metro-at-edge',shift!==0);
            entry.shift=shift;
          }
        }
      }
      button.setAttribute('aria-pressed',String(selected(entry)));
      if(active!==entry.active){
        entry.active=active;
        if(active)marker.addTo(map);
        else marker.remove();
      }
    }
  }

  function stopTrain(){
    if(animation)cancelAnimationFrame(animation);
    animation=0;
    train?.remove();
    play.textContent='播放路線';
    play.setAttribute('aria-pressed','false');
  }

  function updateSelection(){
    stopTrain();
    actions.hidden=!start;
    reset.hidden=!start;
    legs=end?itinerary(edges,start,end):[];
    play.hidden=!legs.length||reduceMotion.matches;
    map.getSource('metro-selected').setData(collection(addTransferLinks(legs).map(edge=>lineFeature(edge,lines))));
    if(!start)status.textContent='點兩站看路線與轉乘';
    else if(!end)status.textContent=`從 ${stations[start].name} 出發。請再選一站。`;
    else if(!legs.length)status.textContent='目前的示範路網未連到這一站';
    else {
      const changes=legs.flatMap((leg,i)=>i&&leg.line!==legs[i-1].line?`在 ${stations[leg.a].name} 轉乘 ${lines[leg.line].name}`:[]);
      const via=[lines[legs[0].line].name,...changes].join(' · ');
      status.textContent=`${stations[start].name} → ${stations[end].name} · ${via} · ${legs.length} 站`;
    }
    updateMarkers();
  }

  function setVisible(on){
    visible=on;
    control.setAttribute('aria-pressed',String(on));
    panel.hidden=!on;
    for(const {id} of displayLayers)map.setLayoutProperty(id,'visibility',on?'visible':'none');
    if(!on){start=null;end=null;}
    updateSelection();
  }

  play.addEventListener('click',()=>{
    if(animation){stopTrain();return;}
    if(!legs.length||reduceMotion.matches)return;
    const {samples,length}=sampleLegs(addTransferLinks(legs));
    if(!samples.length)return;
    const element=document.createElement('span');
    element.className='metro-train';
    element.setAttribute('aria-hidden','true');
    train=new Marker({element,rotationAlignment:'map',pitchAlignment:'map'}).setLngLat(samples[0].start).addTo(map);
    const begin=performance.now();
    const duration=Math.min(15000,Math.max(4500,length*2.7));
    play.textContent='停止播放';
    play.setAttribute('aria-pressed','true');
    function tick(now){
      const distance=Math.min(length,(now-begin)/duration*length);
      const current=samples.find(sample=>distance<=sample.offset+sample.distance)??samples.at(-1);
      const t=(distance-current.offset)/current.distance;
      const [w,s]=current.start,[e,n]=current.end;
      element.classList.toggle('metro-train-transfer',current.line===null);
      element.style.setProperty('--train-color',current.line?lines[current.line].color:'#5d695c');
      train.setLngLat([w+(e-w)*t,s+(n-s)*t]);
      train.setRotation(Math.atan2((e-w)*.906,n-s)*180/Math.PI-90);
      if(distance<length)animation=requestAnimationFrame(tick);
      else stopTrain();
    }
    animation=requestAnimationFrame(tick);
  });

  reset.addEventListener('click',()=>{start=null;end=null;updateSelection();});
  control.addEventListener('click',()=>setVisible(!visible));
  reduceMotion.addEventListener('change',()=>{stopTrain();play.hidden=!legs.length||reduceMotion.matches;});
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stopTrain();});
  map.on('move',updateMarkers);
  control.hidden=false;
  setVisible(openByDefault);
  return Object.assign(()=>({visible,start,end,legs:legs.map(({a,b,line})=>[a,b,line]),playing:!!animation}),
    {setVisible,setNames(on){publicNames=on;updateMarkers();}});
}
