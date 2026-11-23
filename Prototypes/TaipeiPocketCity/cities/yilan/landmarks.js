// Building perimeter: OSM w196842735. Eastward high point, 20° roof and 70°
// end slopes: https://yilancraft.lym.gov.tw/ch/audience-service/faq/
// Architect Yao's project description and photos: https://www.lym.gov.tw/export/sites/lym/files/e-news/4-5-new-2022A/20190919-e-kj-4-23.pdf
function lanyangMuseum(){
  const b=findBuilding('w196842735'),fp=ccw(b.ring);
  const top=([x,y])=>Math.min(34.7,Math.max(.48,.364*(x+81)-.077*(y+13)));
  const lean=(p,h)=>[p[0]-h*.27,p[1]+h*.065,h];
  const roof=fp.map(p=>lean(p,top(p)));
  const stone=['#838576','#8f8875','#a59982','#776d5d','#a3947a','#b0aa96'];
  return obj(fp,35.0,()=>{
    let svg='';
    for(let i=0;i<fp.length;i++){
      const a=fp[i],b=fp[(i+1)%fp.length],dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy);
      const n=[dy/len,-dx/len,0];if(!vis(n))continue;
      const glaze=(a[1]+b[1])*.5>6 || (a[0]+b[0])*.5>13;
      const pt=(t,h,delta=.015)=>lean([a[0]+dx*t+n[0]*delta,a[1]+dy*t+n[1]*delta],h);
      svg+=shape([pt(0,0),pt(1,0),pt(1,top(b)),pt(0,top(a))],tone(n,soft(glaze?'#657f7c':'#8f8574')),.65);
      const cells=Math.max(1,Math.round(len/(glaze?2.4:3.75)));
      for(let j=0;j<cells;j++){
        const lo=j/cells,hi=(j+1)/cells,h0=top(pt(lo,0)),h1=top(pt(hi,0));
        for(let base=0,band=0;base<Math.max(h0,h1);base+=2.28,band++){
          const z0=Math.min(h0,base),z1=Math.min(h1,base),t0=Math.min(h0,base+2.22),t1=Math.min(h1,base+2.22);
          if(Math.max(t0-z0,t1-z1)<.04)continue;
          const color=glaze?(band%4===0?'#95ada2':band%3===0?'#6e8f86':'#69817c'):stone[(i*13+j*7+band*3)%stone.length];
          svg+=shape([pt(lo,z0,.029),pt(hi,z1,.029),pt(hi,t1,.029),pt(lo,t0,.029)],tone(n,soft(color)),.28);
        }
      }
    }
    svg+=shape(roof,'#9b927e',.93);
    for(let x=-110,k=0;x<26;x+=3.36,k++){
      const line=[];
      for(let i=0;i<fp.length;i++){
        const a=fp[i],b=fp[(i+1)%fp.length];
        if((a[0]<x)===(b[0]<x))continue;
        line.push(a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0]));
      }
      line.sort((a,b)=>a-b);
      for(let i=0;i+1<line.length;i+=2){
        const p=[x,line[i]],q=[x,line[i+1]];
        svg+=edge(lean(p,top(p)+.035),lean(q,top(q)+.035),k%4===0?'#706957':'#b5a78a',k%4===0?.22:.12);
      }
    }
    return svg;
  });
}
const LANDMARKS=[{name:'蘭陽博物館',ids:['w196842735'],build:lanyangMuseum}];
