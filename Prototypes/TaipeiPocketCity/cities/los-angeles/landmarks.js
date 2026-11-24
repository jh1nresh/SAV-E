// w422130705 supplies the walls and rounded wing footprints.
// Official exterior elevation and plan: https://griffithobservatory.lacity.gov/wp-content/uploads/2025/12/Griffith-Observatory-Maps_digital.pdf
// Copper domes and the restoration photographs: https://griffithobservatory.lacity.gov/about/observatory-history/renovation-and-expansion/renovation/
const IVORY = '#f1eadc';
const PLASTER = '#f8efe1';
const COPPER = '#685d4d';
const BRONZE = '#836952';
const GLASS = '#62695c';

function drum(x,y,r,z0,z1,colour){
  const ring=polygon(x,y,r,48), a=atZ(ring,z0), b=atZ(ring,z1), material=soft(colour);
  return loft(a,b,n=>tone(n,material))+shape(b,tone([0,0,1],material),.34);
}

function observatoryDome(x,y,r,z,rise,telescope){
  const n=48,ring=polygon(x,y,r,n),base=atZ(ring,z);
  const levels=[0,.12,.25,.39,.53,.68,.82,.93,.98].map(v=>{
    const width=r*Math.sqrt(1-v*v);
    return atZ(polygon(x,y,width,n),z+rise*v);
  });
  const top=[x,y,z+rise];
  let svg='';
  for(let i=0;i<levels.length-1;i++)svg+=loft(levels[i],levels[i+1],normal=>tone(normal,soft(COPPER)));
  svg+=peak(levels.at(-1).map(([x,y])=>[x,y]),levels.at(-1)[0][2],top,COPPER);
  svg+=hullInk(base,.8);
  const ribCount=telescope?16:24;
  for(let i=0;i<ribCount;i++){
    const a=i*Math.PI*2/ribCount,co=Math.cos(a),si=Math.sin(a);
    if(!vis([co,si,.5]))continue;
    const path=levels.map(level=>[x+(level[0][0]-x)*co,y+(level[0][0]-x)*si,level[0][2]+.016]);
    svg+=`<path d="${pd(path,false)}" fill="none" stroke="#402e23" stroke-width=".56" stroke-opacity=".58"/>`;
  }
  if(telescope){
    for(const offset of [-.66,.66]){
      const path=levels.map(level=>[x+offset,y+level[0][0]-x,level[0][2]+.04]);
      if(vis([0,1,.5]))svg+=`<path d="${pd(path,false)}" fill="none" stroke="#443525" stroke-width="1.08"/>`;
    }
  }
  return {fp:ring,z0:z,z1:top[2],svg};
}

function facadePanel(x,y,w,h,z,colour,side=1){
  if(!vis([0,side,0]))return '';
  const x0=x-w/2,x1=x+w/2;
  return shape([[x1,y,z],[x0,y,z],[x0,y,z+h],[x1,y,z+h]],colour,.44);
}

function northFront(x,y){
  if(!vis([0,1,0]))return '';
  let svg='';
  for(const side of [-1,1]){
    for(const d of [13.8,18.1,22.4,26.5]){
      const px=x+side*d;
      svg+=facadePanel(px,y,1.62,5.6,1.2,BRONZE);
      svg+=facadePanel(px,y+.019,1.15,5.1,1.47,GLASS);
      svg+=edge([px-.54,y+.031,5.28],[px+.54,y+.031,5.28],'#c1b08d',.10);
    }
  }
  return svg;
}

function frontEntrance(x){
  const terrace=rect(x,7.12,13.5,5.92);
  return {fp:terrace,z1:2.0,svg:[0,1,2,3,4].map(i=>{
    const tread=rect(x,9.77-i*.77,13-i*.58,1.23),z=.20+i*.31;
    const step=block(tread,z-.20,z,{facade:'plain',wall:i%2?'#c9bfad':'#d8cdb9'});
    return step.draw();
  }).join('')};
}

function griffith(){
  const b=findBuilding('w422130705'),fp=ccw(b.ring),x=b.obb.c[0];
  const podium=block(fp,0,1.10,{facade:'plain',wall:'#caad8f',top:'#dfd5c4'});
  const body=block(fp,1.10,9.80,{facade:'plain',wall:IVORY,top:'#e9ded0'});
  const cornice=block(fp,9.80,10.26,{facade:'plain',wall:'#a2876c',top:'#eee2cf'});
  // The shallow north portal faces the Astronomers Monument. Dome centres follow
  // the circular OSM outline arcs (west/east) and the published roof plan (centre).
  const portal=rect(x,1.23,15.4,5.93);
  const portico=block(portal,1.12,11.95,{facade:'plain',wall:PLASTER});
  const lintel=block(portal,11.95,12.32,{facade:'plain',wall:'#b89e7a'});
  const domes=[[-30.33,-3.41,5.92,7.1,true],[28.20,-3.28,5.92,7.1,true],[-1.12,-29.7,14.1,13.0,false]];
  return obj(fp,25.25,()=>{
    let base=podium.draw()+body.draw()+cornice.draw();
    base+=northFront(x,3.16);
    // Two shallow Art Deco window bands visible from the rear terrace.
    for(const d of [-13,-8.5,8.5,13]) base+=facadePanel(x+d,-23.92,1.5,4.2,2.2,GLASS,-1);
    const py=4.22;
    let entrance=portico.draw()+lintel.draw();
    const capBottom=atZ(polygon(x,.24,5.1,12),12.32);
    const capTop=atZ(polygon(x,.24,3.55,12),13.27);
    entrance+=loft(capBottom,capTop,normal=>tone(normal,soft('#759384')));
    entrance+=shape(capTop,'#8eaa98',.4);
    if(vis([0,1,0])){
      entrance+=facadePanel(x,py,7.2,7.6,1.36,'#cdbb9c');
      entrance+=facadePanel(x,py+.024,5.72,6.42,1.39,'#a79274');
      entrance+=facadePanel(x,py+.042,4.5,5.32,1.42,'#4d514a');
      for(const d of [-1.48,0,1.48]) entrance+=edge([x+d,py+.07,1.51],[x+d,py+.07,6.60],'#bfa884',.14);
      if(SEASON.night)entrance+=facadePanel(x,py+.075,3.65,.72,5.27,'#edbb75');
      // Architectural engraved sign, visible as a fine band at the normal view.
      for(let j=0;j<19;j++){
        const pos=x-4.75+j*.53;
        entrance+=edge([pos,py+.052,10.18],[pos+.24,py+.052,10.18],'#5e4e3d',.10);
      }
    }
    const parts=[{fp:portal,z0:1.12,z1:12.32,svg:entrance},frontEntrance(x)];
    for(const [cx,cy,r,rise,telescope] of domes){
      const z=telescope?11.8:12.25;
      const well=drum(cx,cy,r+.28,10.24,z,IVORY);
      const dome=observatoryDome(cx,cy,r,z,rise,telescope);
      parts.push({...dome,z0:10.24,svg:well+dome.svg});
    }
    return base+planOrder(parts);
  });
}

function monument(){
  // Monument location, OSM n576589857; City of LA official star-party photographs.
  const x=-1.40,y=55.96,fp=polygon(x,y,3.1,16);
  return obj(fp,10.7,()=>{
    let svg=drum(x,y,3.15,0,.26,'#c3b298')+drum(x,y,2.83,.26,.56,IVORY);
    const shaft=rect(x,y,2.1,2.1);
    svg+=block(shaft,.55,8.8,{facade:'plain',wall:IVORY}).draw();
    for(const [dx,dy] of [[0,-1.24],[0,1.24],[-1.24,0],[1.24,0]]){
      if(!vis([dx,dy,0]))continue;
      svg+=edge([x+dx,y+dy,.72],[x+dx,y+dy,3.85],'#d4bea0',.48);
      svg+=ball([x+dx,y+dy,4.25],.37,soft('#dfc7a5'));
    }
    svg+=peak(shaft,8.8,[x,y,9.5],'#cab295');
    svg+=ball([x,y,9.76],.63,soft(BRONZE));
    return svg;
  });
}

const LANDMARKS = [
  {name:'Griffith Observatory',ids:['w422130705'],build:griffith},
  {name:"Astronomers’ Monument",ids:[],build:monument},
];

function CITY_EXTRA(){
  if(SEASON.id!=='star-party')return [];
  return [[-12,31],[10,34],[-13,49],[11,49]].filter(([x,y])=>standable(x,y)).map(([x,y])=>
    obj(rect(x,y,1.5,1.5),2.2,()=>{
      let svg='';
      for(const a of [0,2*Math.PI/3,4*Math.PI/3])svg+=edge([x+Math.cos(a)*.60,y+Math.sin(a)*.60,0],[x,y,1.34],'#505546',.090);
      svg+=stick([x-.51,y-.27,1.2],[x+.72,y+.43,2.17],.15,'#cfbf9c');
      return svg;
    })
  );
}
