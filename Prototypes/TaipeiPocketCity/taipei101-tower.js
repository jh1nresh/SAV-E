// The survey tile supplies the geographic anchor and ground elevation. The exterior
// follows the authored Pocket City diorama and the engineer's building description.
// https://www.thorntontomasetti.com/project/taipei-101
const HEIGHT=508, STONE=0xcbb596, TRIM=0xbcc7aa;
const GLASS=[0x578f84,0x6aa89a], RIB=0x8db8a8, BRONZE=0xcfad64;
const mix=(a,b,t)=>a.map((v,i)=>v+(b[i]-v)*t);

function ring(width,depth,bevel,z,north=0){
  const w=width/2,d=depth/2,k=Math.min(bevel,w*.4,d*.4);
  return [[-w+k,-d],[w-k,-d],[w,-d+k],[w,d-k],[w-k,d],[-w+k,d],[-w,d-k],[-w,-d+k]]
    .map(([x,y])=>[x,y+north,z]);
}

export function buildTaipei101Tower(ground){
  const vertices=[];
  function triangle(a,b,c,color){
    for(const [x,y,z] of [a,b,c])vertices.push(x,y,z+ground,ground,HEIGHT,color+2);
  }
  function quad(a,b,c,d,color){
    triangle(a,b,c,color);
    triangle(a,c,d,color);
  }
  function perimeter(lower,upper,color){
    for(let i=0;i<8;i++){
      const j=(i+1)%8;
      quad(lower[i],lower[j],upper[j],upper[i],color);
    }
  }

  function windowLines(lower,upper,rows,columns,crest){
    for(let i=0;i<8;i++){
      const j=(i+1)%8;
      const [a,b,c,d]=[lower[i],lower[j],upper[j],upper[i]];
      const dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);
      const straight=i%2===0,bays=straight?columns:2;
      function point(u,v,offset){
        const [x,y,z]=mix(mix(a,b,u),mix(d,c,u),v);
        return [x+offset*dy/length,y-offset*dx/length,z];
      }
      function mark(u0,v0,u1,v1,depth,ink){
        quad(point(u0,v0,depth),point(u1,v0,depth),point(u1,v1,depth),point(u0,v1,depth),ink);
      }
      for(let col=1;col<bays;col++){
        const primary=col%4===0,u=col/bays,half=(primary?.21:.105)/length;
        mark(u-half,.015,u+half,.985,.075,primary?RIB:0x78aa9c);
      }
      for(let row=1;row<=rows;row++){
        const primary=row%4===0,v=row/(rows+1),half=(primary?.18:.10)/(d[2]-a[2]);
        mark(.008,v-half,.992,v+half,.12,primary?0x537f74:0x729f91);
      }
      if(crest&&straight){
        const center=point(.5,.5,.24);
        const medal=Array.from({length:16},(_,k)=>{
          const t=k*Math.PI/8;
          return point(.5+3.25*Math.cos(t)/length,.5+3.25*Math.sin(t)/(d[2]-a[2]),.24);
        });
        for(let k=0;k<medal.length;k++)triangle(center,medal[k],medal[(k+1)%medal.length],BRONZE);
      }
    }
  }

  let last=ring(57,55,2.9,-.30,3);
  for(let i=0;i<8;i++)triangle([0,3,-.30],last[(i+1)%8],last[i],STONE);

  function level(start,end,color,rows=0,columns=0,crest=false){
    // The underside of each cornice joins the upper face below to the outer rim.
    // These transition faces keep the shell closed at every setback.
    if(start!==last)perimeter(last,start,TRIM);
    perimeter(start,end,color);
    if(rows)windowLines(start,end,rows,columns,crest);
    last=end;
  }
  const square=(width,z,bevel=2.9)=>ring(width,width,bevel,z);

  level(last,ring(57,55,2.9,3.5,3),STONE);
  // The surveyed platform extends farther north. Keep the centered shaft inside
  // its south edge so the two horizontal joins have no overlapping faces.
  level(ring(53.6,47.8,2.9,3.5),ring(53.6,47.8,2.9,13),STONE);
  level(ring(52.8,47,2.9,13),square(38.5,111),GLASS[0],21,16);
  level(square(40.5,111),square(41,119),GLASS[1],2,10,true);
  for(let i=0;i<8;i++){
    const base=119+i*33.4,top=45-i*.53;
    level(square(top*.79,base),square(top,base+30.4),GLASS[i%2],7,12);
    const rim=top+1.5;
    level(square(rim,base+30.4),square(rim,119+(i+1)*33.4),TRIM);
  }
  level(square(38,119+8*33.4),square(38,391.6),TRIM);
  level(square(22,391.6),square(18.8,430),0x68978d,8,8);
  level(square(19.2,430,2),square(19.2,439,2),0xb4baa3);
  level(square(14,439,2),square(8.5,448,1.25),0x90aaa0,2,5);
  level(square(5.2,448,1.25),square(2.4,490,1),GLASS[0]);
  for(let i=0;i<8;i++)triangle(last[i],last[(i+1)%8],[0,0,HEIGHT],0x587a73);

  return new Float32Array(vertices);
}
