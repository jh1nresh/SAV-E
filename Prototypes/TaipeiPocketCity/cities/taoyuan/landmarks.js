// 桃園市政府「武德殿前世今生」原建物與修復照片：
// https://ws.tycg.gov.tw/001/Upload/86/relfile/13654/1157576/1.pdf
function wudeHall(id,main){
  const b=findBuilding(id),{c,ax,L,W}=b.obb,fp=ccw(b.ring);
  const roofZ=main?4.9:3.1,rise=main?4.05:2.35;
  const xy=(u,v)=>[c[0]+u*ax[0]-v*ax[1],c[1]+u*ax[1]+v*ax[0]];
  const boxAt=(x,y,l,w)=>ccw([xy(x-l/2,y-w/2),xy(x+l/2,y-w/2),xy(x+l/2,y+w/2),xy(x-l/2,y+w/2)]);
  const plinth=block(fp,0,.72,{facade:'plain',wall:'#c3b7a1',top:'#d2c6b4'});
  const wall=block(fp,.72,roofZ,{facade:'timber',wall:'#d9cbb4',trim:'#d4c6ad',wood:'#654b38',slat:'#754f3b',bay:2.65,floor:4.3,shop:'none'});
  const roof=roofOver({c,ax,L,W},roofZ,{roof:'hipped',rise,roofColour:'#59666d',roofTex:'kawara',eaves:.76});
  const portico=boxAt(0,-W/2-1.22,5.3,2.5);
  return obj(fp,roofZ+rise+.5,()=>{
    let out=plinth.draw()+wall.draw()+roof();
    if(!main)return out;
    if(vis([ax[1],-ax[0],0])){
      const plane=-W/2-.028;
      const panel=(a,b,z0,z1,colour)=>shape([[...xy(a,plane),z0],[...xy(b,plane),z0],[...xy(b,plane),z1],[...xy(a,plane),z1]],colour,.38);
      out+=panel(-L/2,L/2,.92,4.57,'#e7ded0');
      out+=panel(-1.28,1.28,.91,3.75,'#543f31');
      for(const q of [-7.5,-4.63,4.63,7.5]){
        out+=panel(q-1.11,q+1.11,1.54,3.5,'#8f8f81');
        for(const u of [-.97,0,.97])out+=edge([...xy(q+u,plane-.015),1.55],[...xy(q+u,plane-.015),3.51],'#625544',.11);
        out+=edge([...xy(q-1.11,plane-.015),2.58],[...xy(q+1.11,plane-.015),2.58],'#665a48',.095);
      }
    }
    const porch=block(portico,0,.54,{facade:'plain',wall:'#baa991',top:'#d1c2a8'});
    const eaves=roofOver({c:xy(0,-W/2-1.12),ax,L:5.3,W:2.45},3.25,{roof:'gabled',ridge:'long',rise:1.18,roofColour:'#5f6d74',roofTex:'kawara',eaves:.42});
    let svg=porch.draw();
    for(const [u,v] of [[-2.45,-W/2-.2],[2.45,-W/2-.2],[-2.45,-W/2-2.30],[2.45,-W/2-2.30]]) {
      const point=xy(u,v);
      svg+=stick([...point,.47],[...point,3.25],.13,'#534735');
    }
    svg+=edge([...xy(-2.53,-W/2-2.36),3.12],[...xy(2.53,-W/2-2.36),3.12],'#6d4d37',.20)+eaves();
    // Timber columns and knee braces frame the low porch below the tile roof.
    for(const s of [-1,1])svg+=edge([...xy(s*2.42,-W/2-2.31),2.47],[...xy(s*1.84,-W/2-2.31),3.14],'#715540',.13);
    return planOrder([{fp,z1:roofZ+rise,svg:out},{fp:portico,z1:4.45,svg}]);
  });
}
const LANDMARKS=[
  {name:'大溪武德殿',ids:['w405959857'],build:()=>wudeHall('w405959857',true)},
  {name:'武德殿附屬建築',ids:['w405959863'],build:()=>wudeHall('w405959863',false)},
];
