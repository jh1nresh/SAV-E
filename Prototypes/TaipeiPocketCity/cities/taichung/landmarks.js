// The Municipal Office at Minquan Road. The corner domed pavilion and Ionic
// entrance portico follow the building's own modern street photographs.
const TC_IVORY='#dfd7c6', TC_CORNICE='#eee5d2', TC_WINDOW='#5b6263';

function tcMunicipalOffice(){
  const b=findBuilding('w569913342'),r=b.ring;
  const pavilion=[-39.91,-22.37],u=[.701,-.713],v=[.713,.701];
  const frame=(a,d,z)=>[pavilion[0]+a*u[0]+d*v[0],pavilion[1]+a*u[1]+d*v[1],z];
  const plan=(a,d,w,h)=>rect(a,d,w,h).map(([x,y])=>frame(x,y,0).slice(0,2));
  const trimmed=(ring,from,to,stone=TC_IVORY,roof='#9b948c') =>
    block(ring,from,to,{facade:'civic',wall:stone,flatRoof:roof,trim:TC_CORNICE,frame:'#aaa391',glass:['#6e7775','#81908a'],floor:3.21,bay:3.9,shop:'none'});
  const volume=trimmed(r,0,10.0);
  const base=block(r,0,.57,{facade:'plain',wall:'#a29a8c',flatRoof:'#b7ad98',shop:'none'});
  const skirt=block(r,9.68,10.24,{facade:'plain',wall:TC_CORNICE,flatRoof:'#b3a895',shop:'none'});
  const tower=polygon(...pavilion,4.3,16,Math.PI/16);
  const drum=trimmed(tower,10.19,12.68,TC_IVORY,'#66716c');
  const domeRings=[[4.58,12.68],[4.44,13.53],[3.97,14.83],[3.08,16.02],[1.94,16.79],[.78,17.19]]
    .map(([radius,z])=>atZ(polygon(...pavilion,radius,24,Math.PI/24),z));
  const porticoBase=trimmed(plan(0,6.05,7.9,1.8),0,.82,'#b7ab9a','#c8bda9');
  const architrave=trimmed(plan(0,5.92,8.05,1.68),8.67,9.56,TC_CORNICE,'#c4b8a0');
  const roofWing=(center,axis,L,W)=>roofOver({c:center,ax:axis,L,W},10.24,
    {roof:'hipped',pitch:17,roofColour:'#726c65',roofTex:'slate',eaves:.2});
  const wingW=roofWing([-52.45,-34.5],[.708,.706],14.25,8.7);
  const wingN=roofWing([-42.02,-20.72],[.545,-.839],10.9,5.1);
  const front=()=>{
    if(!vis([...v,0]))return '';
    const columns=[-3,-1.1,1.1,3].map(a=>{
      const [x,y]=frame(a,6.36,0), stem=polygon(x,y,.41,12);
      return loft(atZ(stem,.84),atZ(stem,8.7),n=>tone(n,soft(TC_CORNICE)))+
        shape(atZ(stem,8.7),TC_CORNICE,.26);
    }).join('');
    const relief=shape([frame(-4.01,6.67,9.55),frame(4.01,6.67,9.55),frame(0,6.67,11.01)],TC_CORNICE,.56);
    const ridge=shape([frame(-4.01,6.67,9.55),frame(0,6.67,11.01),frame(0,5.11,11.01),frame(-4.01,5.11,9.55)],'#a99987',.4)+
      shape([frame(4.01,6.67,9.55),frame(0,6.67,11.01),frame(0,5.11,11.01),frame(4.01,5.11,9.55)],'#968c7d',.4);
    const arc=Array.from({length:11},(_,i)=>frame(1.25*Math.cos(i*Math.PI/10),4.79,3.55+1.25*Math.sin(i*Math.PI/10)));
    const door=shape([frame(-1.25,4.79,.82),frame(1.25,4.79,.82),...arc],'#655b52',.47);
    return door+porticoBase.draw()+columns+architrave.draw()+ridge+relief;
  };
  return obj(r,18.65,()=>base.draw()+volume.draw()+skirt.draw()+wingW()+wingN()+front()+drum.draw()
    +domeRings.slice(1).map((ring,i)=>loft(domeRings[i],ring,n=>tone(n,soft('#646964')))).join('')
    +shape(domeRings.at(-1),'#8a8174',.35)+peak(polygon(...pavilion,.78,10),17.19,[...pavilion,18.65],'#71695e'));
}
const LANDMARKS=[{name:'臺中市役所',ids:['w569913342'],build:tcMunicipalOffice}];
