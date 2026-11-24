// 國家圖書館《臺灣記憶》新竹車站明信片與建築說明：
// https://tm.ncl.edu.tw/article?u=001_002_0000362370
// 站體沿線足印、兩個站翼與站前廣場承自 OSM w293504390 / w160223979。
function hsinchuStation(){
  const b=findBuilding('w293504390'),fp=ccw(b.ring),{c,ax,L,W}=b.obb;
  const xy=(u,v)=>[c[0]+ax[0]*u-ax[1]*v,c[1]+ax[1]*u+ax[0]*v];
  const outline=(u,v,l,w)=>ccw([xy(u-l/2,v-w/2),xy(u+l/2,v-w/2),xy(u+l/2,v+w/2),xy(u-l/2,v+w/2)]);
  const stone='#c7ab87',shell='#dfc8a4',tile='#526262',green='#5b776e';
  const brick=(ring,z0,z1,facade='civic')=>block(ring,z0,z1,{facade,wall:shell,trim:'#b29475',glass:['#797e76','#918e7d'],floor:3.9,bay:3.25,top:'#a5947f'});
  const center=outline(0,0,22,14.9),entry=outline(0,-6.9,11.4,6.0);
  const core=brick(center,.14,8.3), porch=brick(entry,.22,7.3,'plain');
  const wings=[-1,1].map(side=>{
    const u=side*23.6, ring=outline(u,0,25.2,14.25);
    return {ring,body:brick(ring,.19,6.32),cap:roofOver({c:xy(u,0),ax,L:25.2,W:14.25},6.32,{roof:'hipped',rise:4.85,roofColour:tile,roofTex:'slate',eaves:.45})};
  });
  const tower=outline(0,-4.06,6.35,5.95), turret=brick(tower,7.95,13.04,'plain');
  const lower=outline(0,-4.06,6.4,6.05), waist=outline(0,-4.06,4.9,4.9),tip=outline(0,-4.06,2.2,2.2);
  return obj(fp,19.2,()=>{
    let out='';
    const low=brick(fp,0,4.2,'plain');out+=low.draw();
    const parts=wings.map(({ring,body,cap})=>({fp:ring,z1:11.2,svg:body.draw()+cap()}));
    const coreRoof=roofOver({c,ax,L:22,W:14.9},8.3,{roof:'hipped',rise:3.1,roofColour:tile,roofTex:'slate'});
    parts.push({fp:center,z1:11.4,svg:core.draw()+coreRoof()});
    let ledge=porch.draw();
    const front=vis([ax[1],-ax[0],0]);
    if(front){
      const y=-9.93;
      for(const u of [-3.15,0,3.15]){
        const ring=Array.from({length:13},(_,i)=>{const a=i*Math.PI/12;return [...xy(u+1.22*Math.cos(a),y),4.65+1.12*Math.sin(a)]});
        ledge+=shape([[...xy(u-1.22,y),.72],[...xy(u+1.22,y),.72],...ring],'#665b4c',.65);
      }
    }
    if(!front)parts.push({fp:entry,z1:7.35,svg:ledge});
    let cap=turret.draw();
    cap+=loft(atZ(lower,13.04),atZ(waist,15.15),n=>tone(n,soft(green)));
    cap+=loft(atZ(waist,15.15),atZ(tip,17.04),n=>tone(n,soft(green)))+shape(atZ(tip,17.04),green,.35);
    const p=xy(0,-4.06);
    cap+=peak(tip,17.04,[...p,18.05],green)+ball([...p,18.42],.36,soft('#b99a58'));
    for(const v of [-1,1]){
      const outward=[-ax[1]*v,ax[0]*v,0];if(!vis(outward))continue;
      const letter=Array.from({length:20},(_,i)=>{const a=i*Math.PI/10;return [...xy(Math.cos(a)*.86,-4.06+v*3.03),11.18+.86*Math.sin(a)]});
      cap+=shape(letter,'#eae2ce',.7);
      cap+=edge([...xy(0,-4.06+v*3.05),11.18],[...xy(.41,-4.06+v*3.05),11.65],'#564d43',.11);
      cap+=edge([...xy(0,-4.06+v*3.05),11.18],[...xy(-.49,-4.06+v*3.05),11.2],'#564d43',.10);
    }
    parts.push({fp:tower,z0:7.95,z1:18.8,svg:cap});
    return out+planOrder(parts)+(front?ledge:'');
  });
}
const LANDMARKS=[{name:'新竹車站',ids:['w293504390'],build:hsinchuStation}];
