// The mapped silhouette fixes the toe-to-heel direction and the actual ground span.
const SHOE_BLUE = ['#2c84b4','#4eabd0','#5eb5d5','#297aab','#7fcbe0','#2e74a0'];
function glassShoe(){
  const b=findBuilding('w1352427633'),{c,ax}=b.obb;
  const at=(s,v,z)=>[c[0]+s*ax[0]-v*ax[1],c[1]+s*ax[1]+v*ax[0],z];
  // s runs from the counter and heel at the north end to the toe at the south.
  const sections=[[-12.1,7.5,14.25,2.25,3.05],[-11.25,8.2,16.2,3.55,3.8],
    [-9.8,8.5,17.76,4.35,4.1],[-7.7,8.0,16.65,4.85,4.75],[-5.3,6.55,15.05,5.15,5.35],
    [-2.8,4.45,12.7,5.7,5.95],[-.1,2.2,9.4,5.9,6.3],[2.25,.65,6.92,5.85,6.26],
    [4.85,.32,4.95,5.45,5.8],[7.25,.26,4,4.35,4.7],[9.6,.26,3.12,3.1,3.55],[12.35,.36,1.75,.3,.54]];
  const side=(row,side,t)=>{
    const [s,z0,z1,w0,w1]=row;
    return at(s,side*(w0+(w1-w0)*t+.36*Math.sin(Math.PI*t)),z0+(z1-z0)*t);
  };
  const draw=()=>{
    let result='';
    for(const sign of [-1,1])for(let i=1;i<sections.length;i++){
      const a=sections[i-1],b=sections[i];
      for(let j=0;j<5;j++){
        const p=side(a,sign,j/5),q=side(b,sign,j/5),r=side(b,sign,(j+1)/5),s=side(a,sign,(j+1)/5);
        result+=shape([p,q,r],SHOE_BLUE[(i*3+j+1+(sign>0?1:0))%6],.18)
          +shape([p,r,s],SHOE_BLUE[(i+j*5+3+(sign>0?1:0))%6],.18)
          +edge(p,r,'#83c0cc',.22)+edge(q,r,'#6eb0c6',.16);
      }
    }
    for(let i=1;i<sections.length;i++){
      const a=sections[i-1],b=sections[i];
      result+=shape([side(a,-1,0),side(a,1,0),side(b,1,0),side(b,-1,0)],'#2b739d',.2);
      const p=side(a,-1,1),q=side(a,1,1),r=side(b,1,1),s=side(b,-1,1);
      const middle=at((a[0]+b[0])/2,0,(a[2]+b[2])/2+.14);
      for(const [j,triangle] of [[p,q,middle],[q,r,middle],[r,s,middle],[s,p,middle]].entries()){
        result+=shape(triangle,SHOE_BLUE[(i+j*2)%6],.18);
      }
    }
    for(const row of [sections[0],sections.at(-1)]){
      result+=shape([side(row,-1,0),side(row,1,0),side(row,1,1),side(row,-1,1)],'#75c4df',.25);
    }
    // A narrow, separate stiletto heel supports the airy curved sole.
    const heel=(s,z,w,l)=>[at(s-l,-w,z),at(s+l,-w,z),at(s+l,w,z),at(s-l,w,z)];
    const lower=heel(-9.65,.18,.64,.70),middle=heel(-9.7,4.3,1.03,1.01),upper=heel(-9.75,8.52,1.76,1.63);
    result+=loft(lower,middle,n=>tone(n,soft('#d4d6cd')))+loft(middle,upper,n=>tone(n,soft('#e0e3d9')));
    for(let j=1;j<=3;j++){
      const z=.06*j,s=-9.64;
      result+=shape(heel(s,z,.91,.93),'#abbcc0',.14);
    }
    return result;
  };
  return obj(b.ring,17.76,draw);
}
const LANDMARKS=[{name:'高跟鞋教堂',ids:['w1352427633'],build:glassShoe}];
