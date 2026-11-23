// The museum outline is OSM w200028241 inside the named OSM campus w355386414.
// Council grounds and the photographed museum model show the oval silver canopy,
// a glass gallery, central rooflights and a white pedestrian truss bridge.
// https://thcdc.hakka.gov.tw/1240/1310/11914/24669/post
// https://commons.wikimedia.org/wiki/Category:Taiwan_Hakka_Museum
function hakkaMuseum(){
  const b=findBuilding('w200028241'),fp=ccw(b.ring),baseZ=3.8,roofZ=15.3;
  const inner=fp.map(([x,y])=>[27.18+(x-27.18)*.975,-16.62+(y+16.62)*.975]);
  return obj(fp,16,()=>{
    let svg=loft(atZ(inner,0),atZ(inner,baseZ),n=>tone(n,soft('#665951')));
    for(let i=0;i<inner.length;i++){
      const a=inner[i],b=inner[(i+1)%inner.length],dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy);
      const n=[dy/len,-dx/len,0];if(!vis(n))continue;
      const p=(t,z)=>[a[0]+dx*t+.036*n[0],a[1]+dy*t+.036*n[1],z];
      const glass=n[0]<-.2;
      svg+=shape([p(0,baseZ),p(1,baseZ),p(1,roofZ-.5),p(0,roofZ-.5)],tone(n,soft(glass?'#4e6561':'#a2866e')),.5);
      if(glass){
        const bays=Math.max(1,Math.round(len/3.0));
        for(let j=0;j<bays;j++){
          const lo=(j+.036)/bays,hi=(j+.964)/bays;
          for(const [z0,z1] of [[baseZ+.15,8.4],[8.65,11.3],[11.55,roofZ-.64]]){
            svg+=shape([p(lo,z0),p(hi,z0),p(hi,z1),p(lo,z1)],tone(n,soft(j%4?'#688787':'#8da6a2')),.38);
          }
        }
      }
    }
    svg+=loft(atZ(fp,roofZ-.58),atZ(fp,roofZ),n=>tone(n,soft('#aeb3ab')));
    svg+=shape(atZ(fp,roofZ),'#c4c4b6',.92);
    // Parallel seams follow the metal roof's outer outline without spilling onto the grounds.
    for(let yy=-81,j=0;yy<51;yy+=4.2,j++){
      const xs=[];
      for(let i=0;i<fp.length;i++){
        const a=fp[i],b=fp[(i+1)%fp.length];
        if((a[1]<yy)===(b[1]<yy))continue;
        xs.push(a[0]+(yy-a[1])*(b[0]-a[0])/(b[1]-a[1]));
      }
      xs.sort((a,b)=>a-b);
      for(let i=0;i+1<xs.length;i+=2)svg+=edge([xs[i],yy,roofZ+.011],[xs[i+1],yy,roofZ+.011],j%4?'#dddbca':'#aaa99a',.09);
    }
    const rooflight=rect(32.5,-23,35.6,56);
    svg+=shape(atZ(rooflight,roofZ+.04),'#d7d7c7',.7);
    for(let i=0;i<6;i++)for(let j=0;j<9;j++){
      svg+=shape(atZ(rect(18+i*5.8,-46+j*5.7,5.04,4.96),roofZ+.053),j%3?'#9daea8':'#8ba3a0',.43);
    }
    return svg;
  });
}
function trussBridge(){
  const a=[-83.5,11.4],b=[-24,14.9],dx=b[0]-a[0],dy=b[1]-a[1],l=Math.hypot(dx,dy);
  const xy=(t,w,z)=>[a[0]+t*dx-w*dy/l,a[1]+t*dy+w*dx/l,z];
  const fp=ccw([xy(0,-2.3,0),xy(1,-2.3,0),xy(1,2.3,0),xy(0,2.3,0)].map(([x,y])=>[x,y]));
  return obj(fp,9.1,()=>{
    let svg='';
    for(const t of [.34,.59]){
      for(const side of [-1,1])svg+=stick(xy(t,0,.04),xy(t+.055,2.16*side,4.68),.45,'#a2947b');
    }
    const floor=block(fp,4.66,5.22,{facade:'plain',wall:'#bbb8a7',top:'#d7cab1'});
    svg+=floor.draw();
    for(const w of [-2.25,2.25]){
      const n=[Math.sign(w)*-dy/l,Math.sign(w)*dx/l,0];
      if(vis(n))svg+=`<g opacity=".45">${shape([xy(0,w,5.18),xy(1,w,5.18),xy(1,w,6.32),xy(0,w,6.32)],'#a2c0b5',.3)}</g>`;
      svg+=edge(xy(0,w,5.28),xy(1,w,5.28),'#f1e9d7',.21);
      svg+=edge(xy(0,w,8.98),xy(1,w,8.98),'#f1e9d7',.21);
      for(let i=0;i<15;i++){
        const from=i/15,to=(i+1)/15;
        svg+=stick(xy(from,w,i%2?5.3:8.98),xy(to,w,i%2?8.98:5.3),.13,'#eee9d8');
      }
    }
    for(let i=0;i<=15;i+=2)svg+=edge(xy(i/15,-2.24,8.98),xy(i/15,2.24,8.98),'#f1e9d7',.15);
    return svg;
  });
}
const LANDMARKS=[{name:'臺灣客家文化館',ids:['w200028241'],build:hakkaMuseum},
  {name:'園區白色桁架空橋',ids:[],build:trussBridge}];
