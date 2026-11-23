// The residence's L-shaped footprint follows OSM. The veranda openings and
// receding masonry are modelled separately from the two intersecting tiled roofs.
const CONSUL_BRICK='#ab5440', CONSUL_ARCH='#c28059', CONSUL_TILE='#b3694d';
function consulFaces(ring, top, plinth){
  return ccw(ring).map((a,i,r)=>{
    const b=r[(i+1)%r.length],length=Math.hypot(b[0]-a[0],b[1]-a[1]);
    if(length<.12)return '';
    const u=[(b[0]-a[0])/length,(b[1]-a[1])/length],n=[u[1],-u[0],0];
    if(!vis(n))return '';
    const at=(s,z,d=0)=>[a[0]+s*u[0]+d*n[0],a[1]+s*u[1]+d*n[1],z];
    const brick=tone(n,soft(CONSUL_BRICK)), lining=tone(n,soft(CONSUL_ARCH));
    const slab=(left,right,low,high,color,d=0)=>shape([at(left,low,d),at(right,low,d),at(right,high,d),at(left,high,d)],color,.25);
    let svg=slab(0,length,0,plinth,tone(n,soft('#867d70')))
      +slab(0,length,plinth,top,'#704c3a',-.7)
      +slab(0,length,top-.36,top,tone(n,soft('#d59365')),.04);
    const bays=Math.max(1,Math.round(length/2.7)),w=length/bays;
    const half=w*.335,spring=top-1.52,base=plinth+.16;
    for(let j=0;j<bays;j++){
      const mid=(j+.5)*w, left=mid-half, right=mid+half;
      const points=Array.from({length:11},(_,k)=>{
        const theta=Math.PI*k/10;
        return [mid+half*Math.cos(theta),spring+Math.min(half,.93)*Math.sin(theta)];
      }).reverse();
      svg+=slab(j*w,left,plinth,spring,brick)+slab(right,(j+1)*w,plinth,spring,brick)
        +slab(left,right,plinth,base,lining)+slab(left,right,base+.14,top-.52,'#514239',-.73);
      svg+=slab(j*w,left,spring,top-.36,brick)+slab(right,(j+1)*w,spring,top-.36,brick);
      for(let k=1;k<points.length;k++){
        const [[s0,z0],[s1,z1]]=points.slice(k-1,k+1);
        svg+=shape([at(s0,z0),at(s1,z1),at(s1,top-.36),at(s0,top-.36)],brick,.17)
          +shape([at(s0,z0,.025),at(s1,z1,.025),at(s1,z1+.13,.025),at(s0,z0+.13,.025)],lining,.13)
          +shape([at(s0,z0),at(s1,z1),at(s1,z1,-.69),at(s0,z0,-.69)],'#97694d',.13);
      }
      for(const s of [left,right])svg+=shape([at(s,base),at(s,spring),at(s,spring,-.69),at(s,base,-.69)],lining,.16);
      svg+=slab(mid-.16,mid+.16,base+.2,top-1.52,'#977a58',-.75);
      if(plinth>1.2)svg+=slab(mid-.30,mid+.3,.4,plinth-.31,'#514738',.022);
    }
    for(let s=.13;s<length-.11;s+=.3)svg+=slab(s,s+.12,top-.29,top-.14,'#925339',.071);
    return svg+slab(0,length,plinth-.11,plinth+.04,'#bda68d',.04)
      +slab(0,length,top-.04,top+.48,'#ad5e45',.045)
      +slab(0,length,top+.40,top+.53,'#bc805d',.072);
  }).join('');
}

function consulResidence(){
  const b=findBuilding('w205060859'),{c,ax}=b.obb;
  const offset=(u,v)=>[c[0]+ax[0]*u-ax[1]*v,c[1]+ax[1]*u+ax[0]*v];
  const widthRoof=roofOver({c:offset(.02,-4.57),ax,L:21.91,W:9.43},6.45,
    {roof:'hipped',rise:3.37,roofColour:CONSUL_TILE,roofTex:'pantile',eaves:.45});
  const returnRoof=roofOver({c:offset(5.96,4.56),ax,L:9.68,W:9.36},6.34,
    {roof:'hipped',rise:3.02,roofColour:CONSUL_TILE,roofTex:'pantile',eaves:.4});
  const at=(u,v,z)=>[...offset(u,v),z];
  const stair=()=>Array.from({length:8},(_,i)=>{
    const v=-12.5+i*.41,z=(i+1)*.185;
    const a=at(-6.5,v,z),b=at(-4.3,v,z);
    return shape([a,b,at(-4.3,v+.41,z),at(-6.5,v+.41,z)],'#b6947b',.18)
      +shape([at(-6.5,v,z-.185),at(-4.3,v,z-.185),b,a],'#a16c52',.18);
  }).join('');
  return obj(b.ring,9.9,()=>consulFaces(b.ring,6.45,1.48)+shape(atZ(b.ring,6.41),CONSUL_BRICK,.38)
    +widthRoof()+returnRoof()+stair());
}

const LANDMARKS=[{name:'打狗英國領事館官邸',ids:['w205060859'],build:consulResidence}];
