// Illustrative local meshes. Polyfork's playground-slide-8b764c,
// backyard-swing-set-38637e and sandbox-224517 inform the proportions.
const palette=['#d69b49','#54998d','#cf775d','#648db0'];
const rail='#eee2b9', timber='#92745c', metal='#566762';

export function drawPlaygroundObject(kind,index,{box,prism,face}){
  const base=palette[index%palette.length];
  const accent=palette[(index+1)%palette.length];
  function chute(start,end,top){
    face([[start,-.32,top],[end,-.32,.14],[end,.32,.14],[start,.32,top]],accent,1.03);
    for(const y of [-.34,.34]){
      face([[start,y,top],[end,y,.14],[end,y,.24],[start,y,top+.10]],base,.91);
    }
  }
  switch(kind){
    case 'play-tower':
      for(const x of [-1.12,.02])for(const y of [-.47,.47])box(x,y,0,.14,.14,1.93,timber);
      box(-.55,0,.94,1.31,1.09,.12,rail);
      box(-.55,0,1.91,1.55,1.29,.17,base);
      for(const y of [-.46,.46])box(-.55,y,1.25,1.18,.10,.10,base);
      for(let i=0;i<4;i++)box(-1.35-.11*i,0,.84-.23*i,.16,.59,.081,timber);
      chute(.04,1.81,1.04);
      break;
    case 'play-slide':
      chute(-1.19,1.28,1.27);
      for(const y of [-.34,.34]){
        face([[-1.20,y,.025],[1.30,y,.025],[1.30,y,.17],[-1.20,y,1.22]],rail,.91);
      }
      for(let i=0;i<4;i++)box(-1.35-.11*i,0,.99-.27*i,.18,.58,.19,rail);
      break;
    case 'play-swing':
      for(const x of [-1.50,1.50])for(const y of [-.75,.75]){
        face([[x-.064,y,.02],[x+.064,y,.02],[x+.064,0,2.27],[x-.064,0,2.27]],timber,1);
        face([[x,y-.067,.02],[x,y+.067,.02],[x,.067,2.27],[x,-.067,2.27]],timber,.84);
      }
      box(0,0,2.23,3.33,.15,.15,base);
      for(const seat of [-.73,.73]){
        for(const x of [seat-.225,seat+.225])box(x,0,.58,.043,.043,1.66,metal);
        box(seat,0,.54,.58,.35,.095,accent);
      }
      break;
    case 'play-rider':
      prism([0,0,0],[.21,.19],[[0,1],[.07,1],[.12,.72]],8,timber);
      prism([0,0,.12],[.12,.11],[[0,1],[.17,1],[.26,.86]],7,metal);
      box(-.04,0,.37,.65,.28,.20,base);
      box(.20,0,.48,.26,.24,.28,accent);
      box(.22,0,.66,.051,.43,.055,metal);
      break;
    case 'play-climb':
      for(const y of [-.53,.53]){
        for(const x of [-.87,.87])box(x,y,0,.115,.115,1.53,timber);
        box(0,y,1.49,1.92,.12,.12,base);
      }
      for(let i=0;i<5;i++)box(-.77+i*.385,0,1.51,.078,1.14,.07,accent);
      for(const x of [-.87,.87])for(const z of [.27,.55,.83,1.12])box(x,0,z,.085,1.07,.078,rail);
      break;
    case 'play-sand':
      box(0,0,.015,1.74,1.62,.11,'#dccc9f');
      for(const x of [-.89,.89])box(x,0,0,.17,1.83,.28,timber);
      for(const y of [-.87,.87])box(0,y,0,1.82,.16,.28,timber);
      break;
  }
}
