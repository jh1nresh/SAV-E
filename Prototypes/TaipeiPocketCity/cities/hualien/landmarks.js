// Pine Garden's own building outline is resolved into OSM building parts.
// The long main wing faces the garden through a two-storey colonnade.
const PINE_MAIN='w1350032556', PINE_GROUP='w712411693';
const PINE_PLASTER='#cccbb8', PINE_STONE='#aaa99b', PINE_ROOF='#696d6c';
function gardenPiers(b){
  const {c,ax,L,W}=b.obb;
  const point=(s,v,z)=>[c[0]+ax[0]*s-ax[1]*v,c[1]+ax[1]*s+ax[0]*v,z];
  const w=L/8, skirts=[.68,4.02], side=-W/2;
  const band=(a,b,z0,z1,color,d=0)=>shape([point(a,side-d,z0),point(b,side-d,z0),
    point(b,side-d,z1),point(a,side-d,z1)],color,.25);
  let out='';
  for(const low of skirts){
    const top=low+2.94;
    const sc=low<1?PINE_STONE:PINE_PLASTER;
    out+=band(-L/2,L/2,low-.22,low+.15,sc,.4)+band(-L/2,L/2,top-.23,top,PINE_PLASTER,.41);
    for(let i=0;i<8;i++){
      const start=-L/2+i*w, end=start+w, mid=(start+end)/2, radius=w*.348;
      const left=mid-radius,right=mid+radius,spring=low+1.80;
      out+=band(start,left,low+.14,top-.23,PINE_PLASTER,.37)+band(right,end,low+.14,top-.23,PINE_PLASTER,.37);
      const arch=Array.from({length:11},(_,j)=>{
        const t=Math.PI*(1-j/10);
        return [mid+radius*Math.cos(t),spring+.71*Math.sin(t)];
      });
      for(let j=1;j<arch.length;j++){
        const [[a,z],[b,q]]=arch.slice(j-1,j+1);
        out+=shape([point(a,side-.37,z),point(b,side-.37,q),point(b,side-.37,top-.23),point(a,side-.37,top-.23)],PINE_PLASTER,.15)
          +shape([point(a,side-.37,z),point(b,side-.37,q),point(b,side+.05,q),point(a,side+.05,z)],'#a49b86',.09);
      }
      out+=band(left,right,low+.20,low+2.39,low<1?'#71796e':'#5b685d',-.046);
      out+=band(mid-.51,mid+.51,low+.47,low+2.14,'#6e8079',-.027)
        +band(mid-.036,mid+.036,low+.47,low+2.1,'#a8ae97',-.013);
      if(low>1){
        out+=band(left,right,low+.50,low+.59,'#e4deca',.44);
        for(let r=left+.08;r<right-.07;r+=.16)out+=band(r,r+.063,low+.08,low+.53,'#dedbc6',.43);
      }
    }
  }
  // Garden-side climbing vegetation grows on the far corner of the gallery.
  for(let i=0;i<40;i++){
    const s=L/2-1.7+rnd(i*9.53)*1.65,z=.32+rnd(i*6.43)*6.65;
    const size=.19+rnd(i*3.5)*.25;
    out+=shape([point(s,side-.45,z-size),point(s+size,side-.45,z),
      point(s,side-.45,z+size),point(s-size,side-.45,z)],['#6c8853','#81995a','#526f49'][i%3],.12);
  }
  return out;
}
function pineGardenHouse(){
  const b=findBuilding(PINE_MAIN);
  const main=block(b.ring,0,7.3,{facade:'civic',wall:PINE_PLASTER,top:PINE_ROOF,
     floor:3.45,glass:['#7b8b80','#9da797','#688070'],trim:'#e8dbc2',shop:'none'});
  const mainRoof=roofOver(b.obb,7.3,{roof:'hipped',rise:2.23,roofColour:PINE_ROOF,roofTex:'slate',eaves:.53});
  const wings=SCENE.buildings.filter(part=>part.of===PINE_GROUP&&part.id!==PINE_MAIN&&part.id!=='w1350032557');
  const annexes=wings.map(wing=>{
    const h=wing.id==='w918981668'?5.8:4.6;
    const mass=block(wing.ring,0,h,{facade:'civic',wall:'#d6cbb3',top:PINE_ROOF,glass:['#7c897e'],trim:'#e0d6ba',shop:'none'});
    const roof=roofOver(wing.obb,h,{roof:'hipped',rise:h*.23,roofColour:PINE_ROOF,roofTex:'slate',eaves:.32});
    return {fp:wing.ring,z1:h*1.23,draw:()=>mass.draw()+roof()};
  });
  return obj(b.ring,9.65,()=>{
    const volumes=annexes.map(annex=>({...annex,svg:annex.draw()}));
    const n=[b.obb.ax[1],-b.obb.ax[0],0];
    volumes.push({fp:b.ring,z1:9.65,svg:main.draw()+(vis(n)?gardenPiers(b):'')+mainRoof()});
    return planOrder(volumes);
  });
}
const LANDMARKS=[{name:'松園別館',ids:[PINE_GROUP,PINE_MAIN],build:pineGardenHouse}];
