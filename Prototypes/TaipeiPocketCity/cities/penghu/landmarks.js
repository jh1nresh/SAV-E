// Local timber-hall drawing primitives. The authored axes, courtyards and roof orders
// below each assembly are specific to the surveyed site.
function hallFrame(x,y,angle){
  const c=Math.cos(angle),s=Math.sin(angle);
  return (u,v,z=0)=>[x+c*u-s*v,y+s*u+c*v,z];
}
function solid(ring,bottom,top,colour){
  const a=atZ(ring,bottom),b=atZ(ring,top);
  return loft(a,b,n=>tone(n,soft(colour)))+shape(b,colour,.32);
}
function hallPlan(pt,x,y,w,d){return [[-1,-1],[1,-1],[1,1],[-1,1]].map(([a,b])=>pt(x+a*w/2,y+b*d/2).slice(0,2));}
function roofSheet(pt,x,y,w,d,z,rise,colour,ridge,turn){
  let svg='';
  const top=(u,v)=>{
    const hip=Math.max(0,(Math.abs(u)-(w*.5-d*.32))/(d*.32));
    const slope=Math.max(Math.abs(v)/(d*.5),Math.min(1,hip));
    const curl=turn*Math.pow(Math.abs(2*u/w),5);
    return pt(x+u,y+v,z+rise*Math.pow(Math.max(0,1-slope),1.43)+curl);
  };
  const nx=18,ny=6;
  for(let side of [-1,1])for(let i=0;i<nx;i++)for(let j=0;j<ny;j++){
    const at=(a,b)=>top(w*(a/nx-.5),side*d*b/(2*ny));
    const a=at(i,j),b=at(i+1,j),c=at(i+1,j+1),e=at(i,j+1);
    const tint=i%3===0?colour[1]:colour[0];
    svg+=shape([a,b,c],tint,0)+shape([c,e,a],tint,0);
    if(j===ny-1)svg+=edge(e,c,ridge,.14);
  }
  for(let i=0;i<24;i++)svg+=edge(top(w*(i/24-.5),0),top(w*((i+1)/24-.5),0),ridge,.26);
  return svg;
}
function hall(pt,x,y,w,d,wallHeight,base,rise,roof,trim){
  const fp=hallPlan(pt,x,y,w,d),columns=Math.max(4,2*Math.round(w/7));
  return obj(fp,base+wallHeight+rise+1,()=>{
    const floor=solid(fp,base,base+.5,'#c4b7a1');
    let svg=floor+solid(hallPlan(pt,x,y+.45,w-.9,d-1.7),base+.5,base+wallHeight,'#b86549');
    // A recessed entrance behind the column row, visible from the forecourt.
    for(let i=0;i<=columns;i++){
      const u=x-w*.44+i*w*.88/columns,front=y-d*.5+.22;
      svg+=stick(pt(u,front,base+.42),pt(u,front,base+wallHeight),.23,'#973d34');
      if(i<columns){
        const mid=u+w*.44/columns,yFace=front+1.05;
        svg+=shape([pt(mid-.53,yFace,base+.52),pt(mid+.53,yFace,base+.52),pt(mid+.53,yFace,base+wallHeight-.55),pt(mid-.53,yFace,base+wallHeight-.55)],'#523e37',.4);
      }
    }
    return svg+roofSheet(pt,x,y,w+1.8,d+1.6,base+wallHeight,rise,roof,trim,1.15);
  });
}
// The mapped rectangle (OSM way 330868213) encloses the entire temple precinct.
// Its axis is taken from the long west edge. The three halls and flanking
// passages are illustrated within the enclosure, retaining both open courts.
const pt=hallFrame(0,0,.116);
const roof=['#a35d4c','#a96751'],trim='#b3ac91';
const LANDMARKS=[{name:'開臺澎湖天后宮',ids:[],build(){return [
  hall(pt,0,-17,15.8,7,3.2,.25,2.8,roof,trim),hall(pt,0,-1,15.3,8.4,4,.24,3.3,roof,trim),
  hall(pt,0,16,15.2,7.2,4.4,.36,3.1,roof,trim),
  hall(pt,-7.65,0,2.6,26,2.4,.08,.85,roof,trim),hall(pt,7.65,0,2.6,26,2.4,.08,.85,roof,trim),
];}}];
