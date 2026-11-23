// All temple halls are separate mapped parcels. The photographed entrance
// complex has dark red columns, golden glazed tiles, blue-green ridges and
// higher side pavilions over the Dragon and Tiger gates.
const BG_OCHRE='#b88b49',BG_RED='#a24b43',BG_STONE='#a49a86',BG_RIDGE='#56837c';

function bgPlan(c,ax,L,W) {
  const side=[-ax[1],ax[0]];
  return rect(0,0,L,W).map(([x,y])=>[c[0]+x*ax[0]+y*side[0],c[1]+x*ax[1]+y*side[1]]);
}

function bgRoof(frame,base,rise,accent=true) {
  const {c,ax,L,W}=frame;
  const bottom=bgPlan(c,ax,L,W),middle=bgPlan(c,ax,L*.84,W*.57),ridge=bgPlan(c,ax,L*.71,W*.08);
  return () => {
    const r0=atZ(bottom,base+.16),r1=atZ(middle,base+rise*.48),r2=atZ(ridge,base+rise);
    let svg=loft(r0,r1,n=>tone(n,soft(BG_OCHRE)))+loft(r1,r2,n=>tone(n,soft('#a77c42')))
      +shape(r2,BG_RIDGE,.4);
    for(let i=0;i<4;i++){
      const j=(i+1)%4;
      svg+=edge(r0[i],r0[j],BG_RIDGE,.28)+edge(r1[i],r2[i],'#779085',.21);
    }
    if(accent){
      for(const i of [0,1]){
        const a=r2[i],sgn=i?1:-1;
        const mid=[a[0]+ax[0]*sgn*.57,a[1]+ax[1]*sgn*.57,a[2]+.3];
        const point=[a[0]+ax[0]*sgn*.78,a[1]+ax[1]*sgn*.78,a[2]+.86];
        svg+=edge(a,mid,BG_RIDGE,.36)+edge(mid,point,'#6c9181',.28)+ball(mid,.16,soft('#bd794f'));
      }
      const z=base+rise, crown=[c[0],c[1],z+.61];
      svg+=stick([c[0],c[1],z],crown,.09,'#938257')+ball(crown,.19,soft('#ae6d55'));
    }
    return svg;
  };
}

function bgWalls(r,from,to,toneColor,publicDoor){
  const ring=ccw(r);
  return ring.map((a,i)=>{
    const b=ring[(i+1)%ring.length],L=Math.hypot(b[0]-a[0],b[1]-a[1]);
    if(L<.16)return '';
    const u=[(b[0]-a[0])/L,(b[1]-a[1])/L],n=[u[1],-u[0],0];
    if(!vis(n))return '';
    const at=(s,z,d=.045)=>[a[0]+u[0]*s+d*n[0],a[1]+u[1]*s+d*n[1],z];
    const box=(l,r,low,high,c,ink=.23)=>shape([at(l,low),at(r,low),at(r,high),at(l,high)],c,ink);
    let svg=box(0,L,from,to,tone(n,soft(toneColor)),.62)+box(0,L,from,from+.61,BG_STONE)
      +box(0,L,to-.57,to-.17,'#54776f')+box(0,L,to-.69,to-.54,'#c39a64');
    if(L<2.8)return svg;
    const count=Math.max(1,Math.round(L/2.6)),step=L/count;
    for(let j=0;j<count;j++){
      const mid=(j+.5)*step, half=Math.min(.95,step*.37);
      svg+=box(mid-half,mid+half,from+.64,to-.79,'#563e36');
      if(publicDoor&&n[1]<-.4)svg+=box(mid-half+.09,mid+half-.07,from+.69,to-1.08,'#873d37');
      if(UPX<.65)for(let k=-half+.13;k<half-.08;k+=.2)svg+=edge(at(mid+k,from+.82,.056),at(mid+k,to-.87,.056),'#bd795a',.105);
      svg+=box(j*step,j*step+.30,from+.47,to-.36,BG_RED,.28);
    }
    return svg;
  }).join('');
}

function bgHall(id,type) {
  const b=findBuilding(id), {c,ax,L,W}=b.obb;
  const isGate=type==='gate'||type==='sideGate', isMain=type==='main', isBurner=type==='burner', isAnnex=type==='annex';
  const base=isBurner?2.55:isMain?5.45:isGate?4.5:isAnnex?4.3:4.1;
  const rise=Math.min(3.5,Math.max(1.18,W*(isMain?.35:.29)));
  const roofFrame={c,ax,L:L*.99+(isAnnex?.3:.65),W:W*.96+.45};
  const roof=bgRoof(roofFrame,base,rise,!isAnnex);
  const high=isMain||isGate||type==='rear';
  const top=base+rise*.62+1.7, upper=high?bgPlan(c,ax,L*(isGate?.67:.64),W*(isGate?.65:.62)):null;
  const topper=upper?bgRoof({c,ax,L:L*.74,W:W*.72},top,rise*.68,true):null;
  const shellColor=isAnnex?'#bfa28a':isBurner?'#a86d51':'#a45a47';
  return obj(b.ring,high?top+rise*.68+.88:base+rise+.77,()=>{
    let baseDrawing=bgWalls(b.ring,0,base,shellColor,isGate||isMain)+shape(atZ(b.ring,base),'#a17b58',.39)+roof();
    if(high)baseDrawing+=bgWalls(upper,base+rise*.58,top,'#9a5444',false)
      +shape(atZ(upper,top),'#aa8257',.4)+topper();
    return baseDrawing;
  });
}

const BG_HALLS=[
  [7894,'媽祖正殿','main'],[7895,'觀音佛祖殿','rear'],[7896,'三官殿','hall'],[7897,'文昌殿','hall'],
  [7898,'聖父母殿','rear'],[7899,'光明殿','hall'],[7900,'西側洋樓','annex'],[7901,'東側洋樓','annex'],
  [7902,'後院附屬建物','annex'],[7903,'辦公室','annex'],[7904,'福德正神殿','hall'],[7905,'註生娘娘殿','hall'],
  [7906,'廟院西廊','annex'],[7907,'廟院東廊','annex'],[7908,'廟院附屬廊屋','annex'],[7909,'附屬屋','annex'],
  [7910,'招待室','annex'],[7912,'金爐','burner'],[7913,'虎門','sideGate'],[7914,'龍門','sideGate'],[7915,'三川門','gate'],
];
const LANDMARKS=BG_HALLS.map(([suffix,name,type])=>{
  const id='w127403'+suffix;
  return {name,ids:[id],build:()=>bgHall(id,type)};
});
