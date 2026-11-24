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
// The mapped temple turns diagonally to Zhonghua Road. Two main halls sit on
// its longitudinal axis, with narrow side ranges around the interior court.
const temple=SCENE.buildings.find(b=>b.id==='w1112414810');
const pt=hallFrame(temple.obb.c[0]-3,temple.obb.c[1]+2,Math.atan2(.7613,.6484));
const clay=['#c86b46','#b85e41'],gold='#dfaa5e';
const LANDMARKS=[{name:'臺東天后宮',ids:[temple.id],build(){return [
  hall(pt,0,-13,28,9.1,4.8,.15,3.1,clay,gold),
  hall(pt,0,5,25,13,6.3,.75,4,clay,gold),
  hall(pt,0,5,14,7.8,1,8.1,2.8,clay,gold),
  hall(pt,-14,1,4.1,17,3.7,.2,1.3,clay,gold),hall(pt,14,1,4.1,17,3.7,.2,1.3,clay,gold),
];}}];
