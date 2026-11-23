// 內政部臺灣宗教文化地圖（照片及位置）與客家委員會建築說明：
// https://taiwangods.moi.gov.tw/html/cultural/3_0011.aspx?i=252
// https://cloud.hakka.gov.tw/Details?p=62880&pid=274844
function sanyuanTemple(){
  const b=findBuilding('r7290036'),fp=ccw(b.ring),{c,ax}=b.obb;
  const xy=(u,v)=>[c[0]+ax[0]*v-ax[1]*u,c[1]+ax[1]*v+ax[0]*u];
  const part=(u,v,w,d,h,colour='#aa5440')=>{
    const rec=(width,depth,z)=>[[u-width/2,v-depth/2],[u+width/2,v-depth/2],[u+width/2,v+depth/2],[u-width/2,v+depth/2]].map(([x,y])=>[...xy(x,y),z]);
    const ring=ccw(rec(w,d,0).map(([x,y])=>[x,y]));
    const body=block(ring,.15,h,{facade:'temple',wall:colour,trim:'#c5a47c',dark:'#61403e',wood:'#734439',bay:2.22,top:'#9f6a56'});
    return {fp:ring,z1:h+3.1,draw(){
      const rows=[rec(w+.70,d+.8,h+.17),rec(w+.21,d*.72,h+.60),rec(w-.54,d*.36,h+1.52),rec(w-1.50,.26,h+2.39)];
      let out=body.draw();
      if(v>0&&w>13&&vis([ax[0],ax[1],0])){
        const front=v+d/2+.038;
        const panel=(a,b,z0,z1,color)=>shape([[...xy(a,front),z0],[...xy(b,front),z0],[...xy(b,front),z1],[...xy(a,front),z1]],color,.42);
        out+=panel(-w/2,w/2,.19,h-.08,'#b97153');
        for(const bay of [-5.1,0,5.1]){
          out+=panel(bay-1.70,bay+1.70,.27,h-1.35,'#583c36');
          out+=panel(bay-1.42,bay+1.42,.36,h-1.54,'#76514a');
          out+=edge([...xy(bay,front+.02),.4],[...xy(bay,front+.02),h-1.55],'#3b3031',.12);
        }
        for(const i of [-8.1,-2.7,2.7,8.1])out+=stick([...xy(i,front+.13),.33],[...xy(i,front+.13),h-.4],.19,'#923c32');
        out+=panel(-1.45,1.45,h-.97,h-.42,'#285f58');
      }
      for(let i=0;i<rows.length-1;i++)out+=loft(rows[i],rows[i+1],n=>tone(n,soft('#a05843')));
      out+=shape(rows.at(-1),'#8e503a',.45);
      const ridge=[[-w/2+.27,2.88],[-w/2+1.58,2.38],[0,2.38],[w/2-1.58,2.38],[w/2-.27,2.88]].map(([dx,z])=>[...xy(u+dx,v),h+z]);
      for(let i=0;i<ridge.length-1;i++)out+=edge(ridge[i],ridge[i+1],'#d9a666',.22);
      if(w>13){
        out+=ball([...xy(u,v),h+2.69],.28,soft('#d6a44d'));
        out+=edge([...xy(u-.46,v),h+2.48],[...xy(u-1.12,v),h+2.88],'#679385',.20);
        out+=edge([...xy(u+.46,v),h+2.48],[...xy(u+1.12,v),h+2.88],'#679385',.20);
      }
      return out;
    }};
  };
  const parts=[part(.2,-7.1,19.0,11.8,5.55),part(.1,8.0,19.1,9.4,5.18),part(-7.1,.7,4.6,7.3,3.55),part(7.05,.53,4.65,7.8,3.55)];
  return obj(fp,8.8,()=>planOrder(parts.map(p=>({...p,svg:p.draw()}))));
}
const LANDMARKS=[{name:'湖口三元宮',ids:['r7290036'],build:sanyuanTemple}];
