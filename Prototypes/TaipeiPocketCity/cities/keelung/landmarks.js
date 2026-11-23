// 基隆市文化局（國家文化記憶庫）與二二八事件紀念基金會街角／港面照片：
// https://tcmb.culture.tw/zh-tw/detail?id=302545&indexCode=Culture_Place
// https://www.228.org.tw/en/courses-1/%E5%9F%BA%E9%9A%86%E6%B8%AF
// r7667653 / w253032621 already traces the streamlined plan and rounded corner.
function harborBuilding(){
  const b=findBuilding('w253032621'),fp=ccw(b.ring);
  const pale='#e4cfaa',trim='#d0aa77',glass='#58615b';
  const base=block(fp,0,.85,{facade:'plain',wall:'#9a8064',top:'#be9e79'});
  const bands=[1.35,4.16,7.32,10.53,13.76,16.92];
  const rounded=polygon(-81.2,19.02,5.15,30);
  // The roof belvedere is set back within the rounded Port West Street corner.
  const deck=block(rounded,17.20,18.05,{facade:'plain',wall:trim,top:'#e5cbac'});
  const lookout=block(rounded,18.05,20.40,{facade:'civic',wall:pale,top:'#cfb391',trim:'#b38e64',bay:1.65,floor:2.3});
  return obj(fp,22.65,()=>{
    let out=base.draw()+loft(atZ(fp,.85),atZ(fp,17.35),n=>tone(n,soft(pale)));
    out+=shape(atZ(fp,17.35),'#c8ae8e',.65);
    for(let i=0;i<fp.length;i++){
      const p=fp[i],q=fp[(i+1)%fp.length],d=Math.hypot(q[0]-p[0],q[1]-p[1]);
      const normal=[(q[1]-p[1])/d,(p[0]-q[0])/d,0];
      if(!vis(normal))continue;
      const pt=(s,h,f=.028)=>[p[0]+(q[0]-p[0])*s+f*normal[0],p[1]+(q[1]-p[1])*s+f*normal[1],h];
      const bronze=tone(normal,soft(trim));
      for(const z of bands)out+=edge(pt(0,z,.08),pt(1,z,.08),bronze,.31);
      const bays=Math.max(1,Math.round(d/3.45));
      const width=Math.min(.44,1.57/(d/bays));
      for(let j=0;j<bays;j++)for(const [floor,z] of bands.slice(0,-1).entries()){
        const l=(j+.5-width/2)/bays,r=(j+.5+width/2)/bays;
        const h=floor===0?1.99:1.52, bottom=z+.58;
        out+=shape([pt(l,bottom),pt(r,bottom),pt(r,bottom+h),pt(l,bottom+h)],glass,.38);
        out+=edge(pt((l+r)*.5,bottom,.05),pt((l+r)*.5,bottom+h,.05), '#b8aa91',.055);
        if(floor===0&&d>8)out+=edge(pt(l,bottom),pt(r,bottom),'#988062',.13);
      }
    }
    out+=deck.draw()+lookout.draw();
    const roofline=atZ(rounded,20.42);
    out+=hullInk(roofline,.85);
    out+=edge([-81.2,19.02,20.4],[-81.2,19.02,22.65],'#807267',.09);
    return out;
  });
}
const LANDMARKS=[{name:'海港大樓',ids:['w253032621','w533421099','r7667653'],build:harborBuilding}];
