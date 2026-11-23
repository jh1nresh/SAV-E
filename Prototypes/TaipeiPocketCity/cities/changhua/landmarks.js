// The railway roundhouse retains its curved mapped wall. The turntable is
// OSM way 220285048, projected from the source coordinates to the scene.
const CH_C=[25.8535,-19.0974], CH_RADIUS=9.77;
const CH_WALL='#b5ae89', CH_DARK='#4d5857', CH_MULLION='#8ca4a5';

function roundhouse(){
  const b=findBuilding('w220285047'),ring=ccw(b.ring);
  const body=block(ring,0,6.0,{facade:'plain',wall:CH_WALL,flatRoof:'#a29d86',shop:'none',bay:180});
  const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
  const fronts=Array.from({length:12},(_,i)=>{
    const theta=(82+i*9.65)*Math.PI/180,d=[Math.cos(theta),Math.sin(theta)];
    let nearest=null;
    for(let j=0;j<ring.length;j++){
      const a=ring[j],b=ring[(j+1)%ring.length],u=[b[0]-a[0],b[1]-a[1]];
      const den=cross(d,u);
      if(Math.abs(den)<1e-6)continue;
      const q=[a[0]-CH_C[0],a[1]-CH_C[1]],dist=cross(q,u)/den,s=cross(q,d)/den;
      if(dist<12||s<0||s>1||nearest&&dist>=nearest.dist)continue;
      nearest={a,u,s,dist,d};
    }
    return nearest;
  }).filter(Boolean);
  return obj(ring,9.6,()=>{
    let frontsSvg='';
    const ridgeline=[];
    for(let i=0;i<fronts.length;i++){
      const {a,u,s,d,dist}=fronts[i],L=Math.hypot(...u),n=[u[1]/L,-u[0]/L,0];
      const at=(j,z,v=.042)=>[a[0]+u[0]*s+u[0]/L*j+n[0]*v,a[1]+u[1]*s+u[1]/L*j+n[1]*v,z];
      const rect=(l,r,b,t,c,ink=.35)=>shape([at(l,b),at(r,b),at(r,t),at(l,t)],c,ink);
      if(vis(n)){
        frontsSvg+=rect(-2.12,2.12,.18,4.13,'#a8a482')+rect(-1.92,1.92,.20,4.02,'#495052')
          +rect(-1.97,1.97,4.55,5.43,'#718686')+rect(-2.08,2.07,5.38,5.67,'#c0b69a');
        for(let k=-1.55;k<1.9;k+=.46)frontsSvg+=edge(at(k,4.61,.05),at(k,5.38,.05),CH_MULLION,.12);
        frontsSvg+=edge(at(-1.91,4.97,.05),at(1.91,4.97,.05),CH_MULLION,.12);
      }
      const x=CH_C[0]+d[0]*(dist+2.05),y=CH_C[1]+d[1]*(dist+2.05);
      const vent=polygon(x,y,.62,10),hole=polygon(x,y,.41,10),lip=polygon(x,y,.73,10);
      ridgeline.push({at:[x,y,7.4],svg:loft(atZ(lip,6.0),atZ(vent,6.44),n=>tone(n,soft('#a69e7b')))
        +loft(atZ(vent,6.44),atZ(vent,8.93),n=>tone(n,soft('#a59e7d')))
        +loft(atZ(hole,8.93),atZ(hole,9.19),n=>tone(n,soft(CH_DARK)))
        +shape(atZ(lip,9.26),'#797968',.42)});
    }
    return body.draw()+frontsSvg+byDepth(ridgeline);
  });
}

function turntable(){
  const [x,y]=CH_C,r=polygon(x,y,CH_RADIUS,44),angle=2.83;
  const u=[Math.cos(angle),Math.sin(angle)],v=[-u[1],u[0]];
  const at=(a,b,z)=>[x+u[0]*a+v[0]*b,y+u[1]*a+v[1]*b,z];
  return obj(r,1.05,()=>{
    const wood=shape([at(-9.38,-1.27,.16),at(9.38,-1.27,.16),at(9.38,1.27,.16),at(-9.38,1.27,.16)],'#8a7460',.55);
    let rail='';
    for(const d of [-.54,.54])rail+=edge(at(-9.15,d,.24),at(9.15,d,.24),'#58605d',.12);
    for(const d of [-1.22,1.22]){
      rail+=edge(at(-8.92,d,.78),at(8.92,d,.78),'#7c6a57',.16);
      for(let a=-8.8;a<=9;a+=1.2)rail+=edge(at(a,d,.17),at(a,d,.78),'#7c6a57',.105);
    }
    return shape(atZ(r,.03),'#66675e',.9)+wood+rail;
  });
}
function depot(){
  const b=findBuilding('w307329570');
  const body=block(b.ring,0,5.65,{facade:'warehouse',wall:'#b8a88d',flatRoof:'#9a9287',trim:'#c1b69a',glass:['#6d8185','#819493'],shop:'none',floor:3.36,bay:3.4});
  const roof=roofOver({c:[-37.1,19.6],ax:[0,1],L:29.8,W:8.2},5.65,{roof:'gabled',pitch:13,roofColour:'#969891',roofTex:'slate',eaves:.2});
  return obj(b.ring,7,()=>body.draw()+roof());
}
const LANDMARKS=[
  {name:'彰化扇形車庫',ids:['w220285047'],build:()=>[roundhouse(),turntable()]},
  {name:'彰化機務段',ids:['w307329570'],build:depot}
];
