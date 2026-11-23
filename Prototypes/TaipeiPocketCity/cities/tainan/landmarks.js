// The four historic pavilions stay on their measured individual footprints.
// The raised brick podiums, stepped timber floors and curled tile roofs are
// reconstructed from the Chihkan Tower heritage photographs in city.json.
const CK_RED = '#a75341';
const CK_BASE = '#a67d68';
const CK_WOOD = '#643b32';
const CK_TILE = '#984f3b';

function ckPlan(c,ax,L,W) {
  const side=[-ax[1],ax[0]];
  return rect(0,0,L,W).map(([x,y])=>[c[0]+x*ax[0]+y*side[0],c[1]+x*ax[1]+y*side[1]]);
}

function ckRoof({c,ax,L,W},z,rise,paint=CK_TILE) {
  const bow = (length, width, height, lift) => {
    const four=ckPlan(c,ax,length,width);
    return four.flatMap(([x,y],i)=>{
      const next=four[(i+1)%4];
      return [[x,y,height+lift],[(x+next[0])/2,(y+next[1])/2,height]];
    });
  };
  return () => {
    const r0=bow(L,W,z+.13,.56),r1=bow(L*.86,W*.62,z+rise*.45,.27),r2=bow(L*.70,W*.063,z+rise,.25);
    const roof=loft(r0,r1,n=>tone(n,soft(paint)))+loft(r1,r2,n=>tone(n,soft(paint)));
    const crown=shape(r2,'#b97c54',.4);
    const eaves=r0.map((a,i)=>edge(a,r0[(i+1)%r0.length],'#80917b',.28)).join('');
    let tiles='';
    if(UPX<.7)for(let i=0;i<r0.length;i++){
      const j=(i+1)%r0.length;
      const panel=[r0[i],r0[j],r2[j],r2[i]],n=vNewell(panel);
      if(!vis(n))continue;
      const norm=v=>{const m=Math.hypot(...v)||1;return v.map(x=>x/m);};
      const g=norm(sub(r0[j],r0[i])),s=norm(sub(r2[i],r0[i]));
      tiles+=sheetInk(panel,'pantile',g,s);
    }
    let ridgeCaps='';
    for(const [i,j] of [[0,-1],[2,1]]){
      const a=r2[i],bend=[a[0]+ax[0]*j*.54,a[1]+ax[1]*j*.54,a[2]+.28];
      const tip=[a[0]+ax[0]*j*.74,a[1]+ax[1]*j*.74,a[2]+.83];
      ridgeCaps+=edge(a,bend,'#a97558',.28)+edge(bend,tip,'#a97558',.25)+ball(tip,.13,soft('#c69665'));
    }
    return roof+tiles+crown+eaves+ridgeCaps;
  };
}

function ckFacade(ring,low,high,color,stone=false) {
  const r=ccw(ring);
  return () => r.map((a,i) => {
    const b=r[(i+1)%r.length],L=Math.hypot(b[0]-a[0],b[1]-a[1]);
    if(L<.15)return '';
    const ux=(b[0]-a[0])/L,uy=(b[1]-a[1])/L,n=[uy,-ux,0];
    if(!vis(n))return '';
    const at=(s,z)=>[a[0]+s*ux+n[0]*.032,a[1]+s*uy+n[1]*.032,z];
    const plane=(l,r,bot,top,fill,ink=.28)=>shape([at(l,bot),at(r,bot),at(r,top),at(l,top)],fill,ink);
    let svg=plane(0,L,low,high,tone(n,soft(color)),.63);
    if(stone){
      for(let z=low+.38;z<high-.15;z+=.48)svg+=edge(at(0,z),at(L,z),'#9a6f5c',.14);
      if(L>8.7 && n[1]<-.6){
        const mid=L/2,W=1.1,z=low+1.53;
        const arch=Array.from({length:9},(_,k)=>at(mid+Math.cos(k*Math.PI/8)*W,z+Math.sin(k*Math.PI/8)*W));
        svg+=shape([at(mid-W,low+.06),at(mid+W,low+.06),...arch],'#574543',.45);
      }
    }else{
      const bays=Math.max(1,Math.round(L/3.5)),d=L/bays;
      for(let j=0;j<bays;j++){
        const left=j*d+.25,right=(j+1)*d-.25,m=(left+right)/2;
        svg+=plane(left,right,low+.45,high-.48,'#5b403a');
        svg+=plane(left+.15,right-.14,low+.47,(low+high)/2+.15,'#985448',.1);
        svg+=plane(m-.06,m+.06,low+.52,high-.55,'#bf7250',0);
        if(d>2.4)for(let x=left+.25;x<right-.15;x+=.34)svg+=edge(at(x,high-.61),at(x,(low+high)/2+.21),'#987a57',.12);
        svg+=plane(j*d,j*d+.27,low,high-.06,'#b16149',.12);
      }
      svg+=plane(0,L,high-.44,high-.09,'#84664e')+plane(0,L,low,low+.28,'#a07c65');
    }
    return svg;
  }).join('');
}

function ckModel(id,settings){
  const b=findBuilding(id),{c,ax,L,W}=b.obb;
  const baseHeight=settings.base;
  const ring=b.ring,base=ckFacade(ring,0,baseHeight,CK_BASE,true);
  const lower=ckPlan(c,ax,L*settings.lower,W*settings.lower);
  const lowerWall=ckFacade(lower,baseHeight,settings.lowerTop,CK_RED);
  const upper=settings.upper?ckPlan(c,ax,L*settings.upper,W*settings.upper):null;
  const upperWall=upper?ckFacade(upper,settings.lowerTop,settings.upperTop,CK_WOOD):null;
  const roof=ckRoof({c,ax,L:L*.96,W:W*.96},settings.lowerTop,settings.lowerRise,settings.tile);
  const tallRoof=upper ? ckRoof({c,ax,L:L*(settings.upper+.12),W:W*(settings.upper+.14)},settings.upperTop,settings.upperRise,settings.tile):null;
  return obj(ring,(settings.upperTop||settings.lowerTop)+(settings.upperRise||settings.lowerRise)+.6,()=>{
    const pedestal=base()+shape(atZ(ring,baseHeight),'#b4987c',.52);
    const lowerLevel=lowerWall()+shape(atZ(lower,settings.lowerTop),'#a66e58',.45)+roof();
    const tower=upper?upperWall()+shape(atZ(upper,settings.upperTop),'#965b47',.46)+tallRoof():'';
    return pedestal+lowerLevel+tower;
  });
}

const LANDMARKS=[
  {name:'海神廟',ids:['w561994807'],build:()=>ckModel('w561994807',{base:5.1,lower:.80,lowerTop:8.9,lowerRise:2.65,upper:.58,upperTop:12.78,upperRise:2.77,tile:'#9e563f'})},
  {name:'文昌閣',ids:['w183052614'],build:()=>ckModel('w183052614',{base:5.65,lower:.83,lowerTop:10.25,lowerRise:2.63,upper:.51,upperTop:14.08,upperRise:2.7,tile:'#a35c44'})},
  {name:'蓬壺書院',ids:['w561994806'],build:()=>ckModel('w561994806',{base:.58,lower:.87,lowerTop:3.45,lowerRise:1.55,tile:'#98604d'})},
  {name:'大士殿',ids:['w561994812'],build:()=>ckModel('w561994812',{base:.9,lower:.87,lowerTop:4.42,lowerRise:2.3,tile:'#995941'})}
];
