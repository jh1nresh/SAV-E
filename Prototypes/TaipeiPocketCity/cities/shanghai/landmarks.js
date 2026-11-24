// The Bund's Customs House, former HSBC building, China Merchants Building
// and the earlier Russell & Co building. Footprints remain the mapped shapes.
// The architecture sources and photographic references are listed in city.json.
const SH_STONE = '#c2ad94';
const SH_LEDGE = '#d4c1a7';
const SH_ROOF = '#a69d92';
const SH_RECESS = '#647074';

// The renderer's generic mooring scatter cannot identify a landing berth on the
// Huangpu. Leave the river wash and its movement, but don't place moored craft.
SCENE.boats = [];

function shAxis(center, along) {
  const east = [along[1],-along[0]];
  const point = (u,v,z=0) => [center[0]+along[0]*u+east[0]*v,center[1]+along[1]*u+east[1]*v,z];
  const ring = (u,v,w,d) => rect(u,v,w,d).map(([x,y])=>point(x,y).slice(0,2));
  return {point,ring,east};
}

function shRectangle(at,a,b,lo,hi,color,ink=.29) {
  return shape([at(a,lo),at(b,lo),at(b,hi),at(a,hi)],color,ink);
}

function shWalls(ring,from,to,color,decorate,reverse=false) {
  const r=ccw(ring);
  return r.map((a,i)=>{
    const b=r[(i+1)%r.length],L=Math.hypot(b[0]-a[0],b[1]-a[1]);
    if(L<.1)return '';
    const u=[(b[0]-a[0])/L,(b[1]-a[1])/L];
    const n=reverse?[-u[1],u[0],0]:[u[1],-u[0],0];
    if(!vis(n))return '';
    const at=(x,z,d=.038)=>[a[0]+x*u[0]+d*n[0],a[1]+x*u[1]+d*n[1],z];
    return shRectangle(at,0,L,from,to,SEASON.night ? mix(color,'#655a71',.36) : tone(n,soft(color)),.65)
      +(decorate?decorate(at,L,n):'');
  }).join('');
}

function shVolume(ring,z0,z1,color,roof=SH_ROOF) {
  return {fp:ring,z1,draw:()=>shWalls(ring,z0,z1,color)+shape(atZ(ring,z1),roof,.62)};
}

function shWindow(at,m,lo,hi,w,lit=false) {
  let s=shRectangle(at,m-w/2-.15,m+w/2+.15,lo-.12,hi+.17,SH_LEDGE);
  s+=shRectangle(at,m-w/2,m+w/2,lo,hi,SEASON.night&&lit?'#f0c988':SH_RECESS);
  s+=edge(at(m,lo,.048),at(m,hi,.048),'#b7b3a1',.16);
  return s+edge(at(m-w/2,hi-.64,.048),at(m+w/2,hi-.64,.048),'#b7b3a1',.15);
}

function shDoric(frame, u, v, bottom, top, radius) {
  const [x,y]=frame.point(u,v);
  const bottomRing=polygon(x,y,radius,10);
  const topRing=polygon(x,y,radius*.87,10);
  return loft(atZ(bottomRing,bottom),atZ(topRing,top),n=>tone(n,soft(SH_LEDGE)))+
    shape(atZ(topRing,top),SH_LEDGE,.2);
}

function shClockFace(at,m,z,r) {
  const circular = (rad, color, depth=.052) => shape(Array.from({length:26},(_,i)=>{
    const a=i*Math.PI/13;
    return at(m+rad*Math.cos(a),z+rad*Math.sin(a),depth);
  }),color,.55);
  let svg=circular(r,'#837465')+circular(r*.9,SEASON.night?'#ffe3ac':'#ede2cd',.057);
  for (let i=0;i<12;i++) {
    const a=i*Math.PI/6,x=Math.sin(a),y=Math.cos(a);
    const k=i%3===0?.65:.73;
    svg+=edge(at(m+x*r*k,z+y*r*k,.065),at(m+x*r*.84,z+y*r*.84,.065),'#3d4651',i%3===0?.22:.13);
  }
  const pin=at(m,z,.075);
  const hand = (a,k,w) => edge(pin,at(m+r*k*Math.sin(a),z+r*k*Math.cos(a),.075),'#333a47',w);
  return svg+hand(-Math.PI*.27,.54,.19)+hand(Math.PI*.25,.75,.13);
}

const CUSTOMS = ['w178407318','w178407323','w178407326','w178407328','w178407330','w178407333'];

function shCustoms() {
  const b=findBuilding(CUSTOMS[0]), frame=shAxis(b.obb.c,b.obb.ax);
  const mass=b.ring, height=33.3;
  const cap=shVolume(frame.ring(0,0,36.5,23.6),32.2,height,SH_LEDGE,'#b9aea0');
  const blocks=CUSTOMS.slice(1).map((id,i)=>{
    const part=findBuilding(id);
    return shVolume(part.ring,33.3,i===1?42.5:39.8,'#b6a187','#b0a69a');
  });
  const towerCenter=[1.15,5.6];
  const tRing=(w,d=w)=>frame.ring(...towerCenter,w,d);
  const lower=tRing(10.3,9.5), dial=tRing(8.4), drum=tRing(6.1);
  const lanternTop=tRing(4.0), lanternBase=tRing(5.45);
  const upperTiers=[
    shVolume(tRing(10.65,9.8),41.1,42.6,SH_LEDGE,'#b9ab95'),
    shVolume(tRing(10.6,9.8),53.1,54.7,SH_LEDGE,'#ad9e89'),
    shVolume(tRing(8.95),64.4,65.9,SH_LEDGE,'#b4a393'),
    shVolume(drum,65.9,68.3,'#a99681'),
    shVolume(tRing(6.9),68.3,69.25,SH_LEDGE),
    shVolume(lanternBase,69.25,72.05,'#a99a85'),
    shVolume(tRing(6.04),71.94,72.39,SH_LEDGE),
    shVolume(lanternTop,74.8,75.4,'#ae9b86'),
  ];
  const mainFacade=()=>shWalls(mass,0,height,SH_STONE,(at,L,n)=>{
    const view=n[0]>.7, count=view?7:Math.max(3,Math.round(L/4.7)), bay=L/count;
    let s=shRectangle(at,0,L,0,2.0,'#a38f7d')+shRectangle(at,0,L,7.95,8.45,SH_LEDGE)
      +shRectangle(at,0,L,29.25,30.15,'#a38f7c')+shRectangle(at,0,L,30.32,31.25,SH_LEDGE);
    for(let z=2.45;z<8.5;z+=1.16)s+=edge(at(0,z,.068),at(L,z,.068),'#a88f78',.12);
    for(let i=0;i<count;i++){
      const m=(i+.5)*bay;
      s+=shWindow(at,m,3.4,6.3,view?1.32:1.1,i%2===0);
      for(let z=11.0;z<29;z+=4.35)s+=shWindow(at,m,z,z+2.65,Math.min(1.2,bay*.34),i%3===0);
      if(i<count-1)s+=shRectangle(at,(i+1)*bay-.31,(i+1)*bay+.31,8.6,29.28,'#cdb9a0');
      if(UPX<.42){
        for(const z of [11,15.35,19.7,24.05])s+=edge(at(m-.58,z-.39),at(m+.58,z-.39),'#8a8178',.22);
      }
    }
    return s;
  });
  const portico=()=>{
    if(!vis([...frame.east,0]))return '';
    const base=shVolume(frame.ring(0,11.31,10.2,1.95),0,.6,'#a49180');
    const beam=shVolume(frame.ring(0,11.45,10.45,2.1),7.7,8.95,'#c5b197');
    return base.draw()+[-3.6,-1.2,1.2,3.6].map(u=>shDoric(frame,u,12.2,.62,7.75,.55)).join('')+beam.draw();
  };
  const tower=()=>{
    const lowerFaces=shWalls(lower,42.6,53.1,'#b9a58e',(at,L)=>{
      let svg='';
      for(const f of [.23,.5,.77])svg+=shWindow(at,L*f,45.7,51.92,.69,false);
      return svg+shRectangle(at,0,L,43,43.75,'#c8b7a1');
    });
    const clocks=shWalls(dial,54.5,64.4,'#c1ae97',(at,L)=>shClockFace(at,L/2,59.63,2.55));
    const cap=loft(atZ(lanternBase,72.1),atZ(lanternTop,74.85),n=>tone(n,soft('#8f887e')));
    const top=frame.point(...towerCenter,75.4), tip=frame.point(...towerCenter,79.2);
    const flag=shape([tip,frame.point(towerCenter[0]+2.35,towerCenter[1]+.1,78.99),
      frame.point(towerCenter[0]+2.28,towerCenter[1]+.13,77.82),frame.point(...towerCenter,77.91)],'#bb4746',.23);
    return upperTiers[0].draw()+lowerFaces+shape(atZ(lower,53.08),SH_ROOF,.6)
      +upperTiers[1].draw()+clocks+shape(atZ(dial,64.3),SH_ROOF,.4)
      +upperTiers.slice(2,-1).map(t=>t.draw()).join('')+cap+upperTiers.at(-1).draw()
      +stick(top,tip,.08,'#a09886')+flag;
  };
  return obj(b.ring,79.2,()=>mainFacade()+portico()+cap.draw()+planOrder(blocks.map(p=>({...p,svg:p.draw()})))+tower());
}

function shBank() {
  const b=findBuilding('r2380996'),holes=b.holes||[];
  const front=shAxis([-27.8,0], [.106,.9944]);
  const roofLevel=28.1, domeCenter=[-39.1,-.4];
  const domeBase=polygon(...domeCenter,9.7,8,Math.PI/8);
  const domeDrum=polygon(...domeCenter,7.35,16,Math.PI/16);
  const domeRings=[[7.35,37.6],[7.03,40.15],[6.28,43.5],[5.13,46.25],[3.62,48.25],[1.86,49.65],[1.08,50.1]]
    .map(([radius,z])=>atZ(polygon(...domeCenter,radius,24),z));
  const pillarRuns = () => {
    if(!vis([...front.east,0]))return '';
    const podium=shVolume(front.ring(0,-.2,22.45,2.8),0,5.9,'#b39d86');
    const frieze=shVolume(front.ring(0,0,23,2.7),21.3,23.9,'#caba9f');
    const pediment=[
      front.point(-11.3,1.08,23.9),front.point(11.3,1.08,23.9),front.point(0,1.08,27.1)
    ];
    return podium.draw()+[-9.6,-5.76,-1.92,1.92,5.76,9.6].map(u=>shDoric(front,u,1.03,5.95,21.21,.59)).join('')
      +frieze.draw()+shape(pediment,'#cfbda3',.61);
  };
  const exterior=()=>shWalls(b.ring,0,roofLevel,'#baa58c',(at,L)=>{
    let svg=shRectangle(at,0,L,0,1.25,'#a89888')+shRectangle(at,0,L,5.08,5.63,SH_LEDGE)
      +shRectangle(at,0,L,22.75,23.57,'#c9b89f')+shRectangle(at,0,L,26.95,27.62,SH_LEDGE);
    const n=Math.max(1,Math.round(L/4.1)),bay=L/n;
    if(L<2.1)return svg;
    for(let i=0;i<n;i++){
      const m=(i+.5)*bay;
      for(const z of [2.28,7,11.2,15.4,19.45,24.1])svg+=shWindow(at,m,z,z+2.05,Math.min(1.12,bay*.42),i%3===1);
      if(i<n-1)svg+=shRectangle(at,(i+1)*bay-.17,(i+1)*bay+.17,5.8,22.8,'#c7b59c');
    }
    return svg;
  });
  const dome=()=>{
    const base=shWalls(domeBase,roofLevel,33.6,'#b3a18e',(at,L)=>
      shRectangle(at,0,L,32.22,33.3,SH_LEDGE)+shWindow(at,L/2,29.4,31.8,1.55));
    const drum=shWalls(domeDrum,33.6,37.6,'#b4a695',(at,L)=>
      shWindow(at,L/2,34.22,36.8,Math.min(1.0,L*.55))+shRectangle(at,0,L,37,37.45,SH_LEDGE));
    const curves=domeRings.slice(1).map((ring,i)=>loft(domeRings[i],ring,n=>tone(n,soft('#9ca3a0')))).join('');
    const ribs=Array.from({length:24},(_,i)=>{
      if(i%2)return '';
      const next=(i+1)%24,n=vNewell([domeRings[0][i],domeRings[0][next],domeRings[1][next],domeRings[1][i]]);
      return vis(n)?domeRings.slice(1).map((r,k)=>edge(domeRings[k][i],r[i],'#6f7776',.13)).join(''):'';
    }).join('');
    const spool=polygon(...domeCenter,1.05,10);
    return base+shape(atZ(domeBase,33.59),'#b0a291',.5)+drum+shape(atZ(domeDrum,37.59),'#9da19b',.4)
      +curves+ribs+shVolume(spool,49.9,52.05,'#aaa99b','#929990').draw()
      +peak(spool,52.05,[...domeCenter,53.25],'#95978e')
      +stick([...domeCenter,53.25],[...domeCenter,54.4],.047,'#958375');
  };
  return obj(b.ring,54.4,()=>{
    const inner=holes.map(h=>shWalls(h,0,roofLevel,'#a59484',null,true)).join('');
    const cover=[b.ring,...holes].map(r=>pd(atZ(r,roofLevel))).join('');
    return inner+exterior()+pillarRuns()+'<path d="'+cover+'" fill="#ab9f8f" fill-rule="evenodd" stroke="#584e53" stroke-width=".45"/>'+dome();
  });
}

function shShipping() {
  const b=findBuilding('w178408820'),r=b.ring;
  const roofZ=17.0;
  return obj(r,20.5,()=>{
    const shell=shWalls(r,0,roofZ,'#c7b09b',(at,L,n)=>{
      if(L<4.1)return '';
      let svg = shRectangle(at,0,L,4.12,4.67,'#d4bea3') + shRectangle(at,0,L,12.8,13.27,'#d4bea3')
        + shRectangle(at,0,L,16.21,16.75,'#d8c4aa');
      const cols=Math.max(1,Math.round(L/3.3)),bay=L/cols;
      for(let i=0;i<cols;i++){
        const m=bay*(i+.5),w=Math.min(1.12,bay*.44);
        for(const z of [1.2,5.0,9.07,13.63])svg+=shWindow(at,m,z,z+2.27,w,i%2===0);
        if(n[0]>.7 && L>13)svg+=shRectangle(at,i*bay+.15,i*bay+.32,4.67,13.05,'#d3baa1');
      }
      if(n[0]>.7 && L>13)svg+=shape([at(L*.21,16.77),at(L*.77,16.77),at(L*.5,19.67)],'#cfb9a1',.62);
      return svg;
    });
    return shell+shape(atZ(r,roofZ),SH_ROOF,.62);
  });
}

function shRussell() {
  const b=findBuilding('w380340030'),r=b.ring, wall=8.0;
  const {c,ax,L,W}=b.obb;
  const top=roofOver({c,ax,L:L*.97,W:W*.91},wall,
    {roof:'hipped',pitch:16,roofColour:'#8d766d',roofTex:'slate',eaves:.27});
  return obj(r,13.2,()=>shWalls(r,0,wall,'#c1a58a',(at,wide)=>{
    if(wide<4)return '';
    const n=Math.max(1,Math.round(wide/3.45)),bay=wide/n;
    let svg=shRectangle(at,0,wide,.2,.81,'#9d8571')+shRectangle(at,0,wide,3.55,4.02,'#d7bba0');
    for(let i=0;i<n;i++){
      const m=(i+.5)*bay;
      svg+=shWindow(at,m,.86,3.11,Math.min(1.29,bay*.6));
      svg+=shWindow(at,m,4.6,7.23,Math.min(1.26,bay*.55));
    }
    return svg;
  })+shape(atZ(r,wall),'#9b8273',.39)+top());
}

const LANDMARKS = [
  {name:'上海海關大樓',ids:CUSTOMS,build:shCustoms},
  {name:'前匯豐銀行大樓',ids:['r2380996'],build:shBank},
  {name:'輪船招商局大樓',ids:['w178408820'],build:shShipping},
  {name:'旗昌洋行舊址',ids:['w380340030'],build:shRussell},
];
