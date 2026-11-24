// OSM w43921139 for the hall centre and outer roof; UNESCO nomination (site plan,
// elevation and photos) https://whc.unesco.org/uploads/nominations/881.pdf
// Temple of Heaven Park https://www.tiantanpark.cn/en/Scenic/detail/1396.html
const STONE = '#eee8d9';
const RED = '#9c392b';
const BLUE = '#305fa8';
const JADE = '#387268';
const GOLD = '#c39343';

function tier(x,y,profile,colour,n=48){
  const rings=profile.map(([r,z])=>atZ(polygon(x,y,r,n),z));
  const shade=soft(colour);
  let svg='';
  for(let i=0;i<rings.length-1;i++) svg+=loft(rings[i],rings[i+1],normal=>tone(normal,shade));
  return svg+shape(rings.at(-1),tone([0,0,1],shade),0);
}

function marbleRail(x,y,r,z,axis){
  const n=72;
  let svg='';
  for(let i=0;i<n;i++){
    const a=i*Math.PI*2/n;
    if(axis.some(([angle,width])=>Math.abs(Math.atan2(Math.sin(a-angle),Math.cos(a-angle)))<width/r))continue;
    const b=(i+1)*Math.PI*2/n;
    const p=[x+r*Math.cos(a),y+r*Math.sin(a)],q=[x+r*Math.cos(b),y+r*Math.sin(b)];
    const normal=[Math.cos(a),Math.sin(a),0];
    if(!vis(normal))continue;
    svg+=shape([[...p,z+.06],[...q,z+.06],[...q,z+.68],[...p,z+.68]],tone(normal,soft(STONE)),.35);
    svg+=edge([...p,z+.82],[...q,z+.82],'#f8f2e6',.13);
    svg+=edge([...p,z],[...p,z+.92],'#f5ecdc',.20);
  }
  return svg;
}

function templeStair(x,y,angle,width){
  const u=[Math.cos(angle),Math.sin(angle)],v=[-u[1],u[0]];
  const at=(r,d)=>[x+r*u[0]+d*v[0],y+r*u[1]+d*v[1]];
  const outline=ccw([at(49,-width),at(49,width),at(27,width),at(27,-width)]);
  return {fp:outline,z1:6.1,draw(){
    let svg='';
    for(let i=0;i<18;i++){
      const a=49-i*1.22,b=a-1.22,z=(i+1)*.335;
      svg+=shape([at(a,-width),at(a,width),at(b,width),at(b,-width)].map(p=>[...p,z]),i%2?'#f1eadc':'#e8dfcd',.3);
      if(vis([u[0],u[1],0]))svg+=shape([[...at(a,-width),z-.335],[...at(a,width),z-.335],[...at(a,width),z],[...at(a,-width),z]],'#d1c4b3',.25);
    }
    svg+=edge([...at(49,-width),.6],[...at(27,-width),6.8],STONE,.22);
    svg+=edge([...at(49,width),.6],[...at(27,width),6.8],STONE,.22);
    return svg;
  }};
}

function roofTiles(x,y,profile){
  let svg=tier(x,y,profile,BLUE,64);
  const [outerR,eave]=profile[0];
  const strips=UPX<.32?80:48;
  for(let i=0;i<strips;i++){
    const angle=i*2*Math.PI/strips,u=[Math.cos(angle),Math.sin(angle)];
    if(!vis([u[0],u[1],.75]))continue;
    const pts=profile.map(([r,z])=>[x+r*u[0],y+r*u[1],z+.024]);
    svg+=`<path d="${pd(pts,false)}" fill="none" stroke="#203f79" stroke-opacity=".48" stroke-width=".58"/>`;
  }
  svg+=hullInk(atZ(polygon(x,y,outerR,64),eave),.95);
  return svg;
}

function hallOfPrayer(){
  const b=findBuilding('w43921139'),[x,y]=b.obb.c;
  const stairs=[[-Math.PI/2,2.5],[-1.05,1.65],[-2.1,1.65],[0,1.8],[Math.PI,1.8],[1.42,1.7],[1.87,1.7]];
  const levels=[[45,0,1.96],[38,1.96,3.94],[31.3,3.94,6.05]];
  const fp=polygon(x,y,49,48);
  return obj(fp,38.2,()=>{
    const parts=levels.map(([r,z0,z1])=>({fp:polygon(x,y,r,48),z0,z1,
      svg:tier(x,y,[[r,z0],[r,z1-.18],[r+.16,z1]],STONE,64)+marbleRail(x,y,r-.52,z1,stairs)}));
    parts.push(...stairs.map(([angle,width])=>{const item=templeStair(x,y,angle,width);return {...item,svg:item.draw()}}));
    let svg=planOrder(parts);
    svg+=tier(x,y,[[12.7,6.05],[12.7,6.48]],'#d4c7b0');
    svg+=tier(x,y,[[11.87,6.48],[11.87,14.6]],RED,48);
    for(let i=0;i<24;i++){
      const a=(i+.5)*Math.PI/12, u=[Math.cos(a),Math.sin(a)],p=[x+12.05*u[0],y+12.05*u[1]];
      if(!vis([u[0],u[1],0]))continue;
      const v=[-u[1],u[0]];
      const side=(d,z)=>[p[0]+v[0]*d,p[1]+v[1]*d,z];
      svg+=shape([side(-.78,7.0),side(.78,7.0),side(.78,12.25),side(-.78,12.25)],'#612d27',.35);
      for (const d of [-.48,0,.48]) svg+=edge(side(d,7.3),side(d,12.05),'#a95840',.07);
      svg+=edge([x+12.30*u[0],y+12.30*u[1],6.47],[x+12.30*u[0],y+12.30*u[1],14.8],'#a84132',.36);
    }
    const stages=[
      {band:[[12.1,13.6],[12.4,14.75]],roof:[[14.48,15.0],[13.1,15.14],[10.9,16.35],[8.65,18.2],[7.9,19.1]]},
      {band:[[7.85,19.1],[7.85,21.7]],roof:[[10.95,22.0],[9.8,22.1],[8.15,23.15],[6.6,24.55],[5.75,25.65]]},
      {band:[[5.77,25.6],[5.77,28.15]],roof:[[8.0,28.45],[7.1,28.6],[5.35,30.1],[3.8,32.0],[2.28,34.25],[.76,36.45]]},
    ];
    for(const [i,part] of stages.entries()){
      svg+=tier(x,y,part.band,i?RED:JADE,48);
      const [[r,z]]=part.roof;
      svg+=tier(x,y,[[r-.13,z-.28],[r,z-.08]],GOLD,56);
      svg+=roofTiles(x,y,part.roof);
      if(SEASON.id==='temple-light'){
        const rim=atZ(polygon(x,y,r-.18,48),z-.08);
        for(let j=0;j<48;j++){
          const p=rim[j],q=rim[(j+1)%48];
          if(vis([p[0]-x,p[1]-y,0]))svg+=edge(p,q,'#ffe7a8',.15);
        }
      }
    }
    svg+=tier(x,y,[[.78,36.45],[.83,36.65],[.63,37.04],[.48,37.38]],GOLD,24);
    svg+=ball([x,y,37.65],.55,soft('#d2a746'));
    return svg;
  });
}

function axialHall(id,height,roofColour){
  const b=findBuilding(id),fp=ccw(b.ring),{c,ax,L,W}=b.obb;
  const wing=(length,width,z)=>{
    const [ux,uy]=ax;
    return [[-1,-1],[1,-1],[1,1],[-1,1]].map(([u,v])=>[
      c[0]+u*ux*length/2-v*uy*width/2,c[1]+u*uy*length/2+v*ux*width/2,z,
    ]);
  };
  const base=block(fp,0,.70,{facade:'plain',wall:'#d5c4aa'});
  const body=block(fp,.70,height,{facade:'temple',wall:RED,trim:'#8e532f',dark:'#66372d',wood:'#a34331',bay:3.5,floor:5.8});
  const roofRise=Math.min(4.45,W*.32), roofTop=height+roofRise;
  return obj(fp,roofTop,()=>{
    let svg=base.draw()+body.draw();
    const sections=[wing(L+1.35,W+1.25,height+.35),wing(L+.42,W+.52,height+.48),
      wing(L-2.8,W*.64,height+roofRise*.40),wing(L-W*.48,W*.23,height+roofRise*.78),wing(L-W*.73,.34,roofTop)];
    for(let i=0;i<sections.length-1;i++){
      svg+=loft(sections[i],sections[i+1],n=>tone(n,soft(roofColour)));
    }
    svg+=shape(sections.at(-1),'#31425f',.56);
    svg+=hullInk(sections[0],.8);
    svg+=edge(sections.at(-1)[0],sections.at(-1)[1],'#32445e',.18);
    if(UPX<.35){
      const row=sections[0],cap=sections.at(-1);
      for(const j of [0,2])for(let k=1;k<21;k++){
        const f=k/21,a=row[j],b=row[(j+1)%4],c=cap[j],d=cap[(j+1)%4];
        const n=vNewell([a,b,d,c]);
        if(vis(n))svg+=edge(a.map((v,i)=>v+(b[i]-v)*f),c.map((v,i)=>v+(d[i]-v)*f),'#3b4b70',.025);
      }
    }
    return svg;
  });
}

const LANDMARKS = [
  {name:'祈年殿',ids:['w43921139'],build:hallOfPrayer},
  {name:'祈年門',ids:['w43921137'],build:()=>axialHall('w43921137',7,'#3b5d98')},
  {name:'皇乾殿',ids:['w43921140'],build:()=>axialHall('w43921140',7.5,'#3b6099')},
  {name:'皇乾門',ids:['w43921141'],build:()=>axialHall('w43921141',4,'#3e5d83')},
  {name:'東配殿',ids:['w43921111'],build:()=>axialHall('w43921111',5,'#416696')},
  {name:'西配殿',ids:['w43921133'],build:()=>axialHall('w43921133',5,'#416696')},
  {name:'西側門',ids:['w43921126'],build:()=>axialHall('w43921126',4.1,'#496b5d')},
];

// The western and northern courtyard wall segments follow OSM ways
// 43921127/43921128/43921131, preserving the breaks at the mapped gates.
const enclosureWalls = [
  [[-31.5,-119],[-32.0,-105.1],[-33.0,-77.6],[-34.3,-45.4]],
  [[-34.8,-27.3],[-38.0,54.8],[26.3,57.3],[36.6,57.7]],
  [[52.1,58.3],[62.4,58.6],[119.45,60.8]],
];
const courtyardWall = (a,b)=>{
  const dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy),nx=-dy/len*.36,ny=dx/len*.36;
  const fp=ccw([[a[0]+nx,a[1]+ny],[b[0]+nx,b[1]+ny],[b[0]-nx,b[1]-ny],[a[0]-nx,a[1]-ny]]);
  const base=block(fp,0,.38,{facade:'plain',wall:'#ba9a7c',top:'#b6987c'});
  const wall=block(fp,.38,3.3,{facade:'plain',wall:'#a74839',top:'#41685c'});
  return obj(fp,3.3,()=>base.draw()+wall.draw()+edge([...a,3.3],[...b,3.3],'#496956',.79));
};
LANDMARKS.push({name:'祈穀壇院牆',ids:[],build:()=>enclosureWalls.flatMap(points=>
  points.slice(1).map((point,index)=>courtyardWall(points[index],point)))});
