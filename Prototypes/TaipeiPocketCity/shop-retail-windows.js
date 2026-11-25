// Store types come from the public frontage data. The display contents are illustrations.
export const retailWindowTypes = new Map([
  ['books','books'], ['greengrocer','produce'], ['copyshop','copyshop'],
  ['pet','pet-supplies'], ['lottery','lottery'], ['stationery','stationery'],
  ['gift','gifts'], ['alcohol','wine'], ['wine','wine'], ['watches','watches'],
  ['photo','camera'], ['camera','camera'], ['toys','toys'],
  ['musical_instrument','instruments'], ['sports','sporting-goods'],
]);

export function drawRetailWindow(trade, {face,slab,shape,rod,rim,bottle}, paint){
  const {ink,wood,cream,glass,teal,leather,berry,ochre,sage,grape}=paint;
  const counter=(height=.49)=>slab(-.74,.74,height-.11,height,.22,wood);
  const shelf=(height)=>slab(-.70,.70,height-.053,height,.21,wood);
  const palette=[teal,ochre,berry,sage,grape];

  switch(trade){
    case 'books':
      // Modular shelving refers to the 0.44 × 0.4 m Polyfork bookshelf-5e881a.
      face(-.68,.68,.10,1.50,.075,wood);
      for(const level of [.26,.69,1.12]){
        shelf(level);
        for(const [i,x] of [-.55,-.38,-.21,.02,.22,.40].entries()){
          const top=level+[.24,.30,.27][i%3];
          face(x,x+.11,level,top,.18,palette[(i+Math.round(level*10))%palette.length]);
          face(x+.02,x+.09,top-.06,top-.04,.183,cream);
        }
      }
      break;
    case 'produce':
      counter(.35);
      for(const [i,cx] of [-.47,0,.47].entries()){
        const left=cx-.21,right=cx+.21,y=.38+i*.07;
        slab(left,right,y-.07,y+.03,.22,wood);
        face(left+.018,right-.018,y+.02,y+.21,.11,ink);
        for(const [j,x] of [cx-.13,cx,cx+.13].entries()){
          const color=[ochre,berry,sage][i], bottom=y+.055+(j%2)*.05;
          shape([[x-.052,bottom],[x+.049,bottom],[x+.041,bottom+.084],[x-.038,bottom+.086]],.17,color);
          face(x-.04,x+.035,bottom+.086,bottom+.10,.16,i===2?teal:cream);
        }
        face(left,right,y-.02,y+.037,.224,leather);
      }
      break;
    case 'copyshop':
      slab(-.62,.28,.08,.60,.21,teal);
      slab(-.65,.29,.60,.69,.23,ink);
      slab(-.65,.29,.69,.98,.24,cream);
      face(-.59,.23,.74,.79,.244,ink);
      face(-.17,.17,.86,.94,.245,glass);
      slab(-.59,.24,.98,1.04,.22,ink);
      face(-.49,.03,.96,.997,.25,cream);
      shelf(.45);
      for(const y of [.46,.52,.58,.64])face(.39,.68,y,y+.036,.16,cream);
      break;
    case 'pet-supplies':
      counter(.42);
      for(const [x,height,color] of [[-.46,.45,sage],[-.10,.55,teal],[.25,.36,berry]]){
        shape([[x-.13,.42],[x+.13,.42],[x+.10,.42+height],[x-.11,.42+height]],.18,color);
        face(x-.075,x+.075,.58,.70,.19,cream);
      }
      shape([[.38,.42],[.68,.42],[.72,.54],[.34,.54]],.22,ochre);
      face(.35,.71,.53,.56,.23,cream);
      break;
    case 'lottery':
      slab(-.68,.68,.13,.61,.21,berry);
      slab(-.73,.73,.61,.71,.24,ochre);
      for(const [i,x] of [-.52,-.26,0,.26,.52].entries()){
        shape([[x-.09,.72],[x+.09,.72],[x+.074,1.06],[x-.074,1.06]],.19,palette[i]);
        face(x-.052,x+.052,.80,.92,.194,cream);
      }
      break;
    case 'stationery':
      counter(.43);
      for(const [x,color] of [[-.45,teal],[-.08,ochre],[.35,berry]]){
        slab(x-.12,x+.13,.43,.62,.20,color);
        for(const [dx,top] of [[-.05,.90],[.01,1.04],[.062,.86]]){
          rod(x+dx,.63,x+dx+.025,top,.028,.16,ink);
        }
      }
      for(const y of [.445,.493,.541])face(-.67,-.56,y,y+.032,.22,cream);
      break;
    case 'gifts':
      counter(.39);
      for(const [x,y,width,height,color] of [[-.44,.39,.36,.36,berry],[.01,.39,.43,.53,teal],[.48,.39,.29,.27,ochre]]){
        slab(x-width/2,x+width/2,y,y+height,.20,color);
        face(x-.022,x+.022,y,y+height,.205,cream);
        face(x-width/2,x+width/2,y+height*.62,y+height*.71,.205,cream);
        rod(x-.08,y+height+.065,x,y+height,.027,.18,cream);
        rod(x,y+height,x+.08,y+height+.069,.027,.18,cream);
      }
      break;
    case 'wine':
      // Bottles refer to the 0.30 m Polyfork wine-bottle-75a822.
      face(-.67,.67,.1,1.33,.073,wood);
      for(const y of [.30,.69,1.08]){
        shelf(y);
        for(const [i,x] of [-.48,-.16,.16,.48].entries()){
          bottle(x,y,.30,.16,i%3===0?berry:sage);
          face(x-.037,x+.037,y+.06,y+.13,.168,cream);
        }
      }
      break;
    case 'watches':
      slab(-.72,.72,.21,.36,.23,wood);
      for(const [i,x] of [-.43,0,.43].entries()){
        slab(x-.17,x+.17,.36,.62,.18,ink);
        face(x-.066,x+.066,.53,.87,.20,palette[i]);
        rim(x,.72,.104,.219,ochre,8);
        face(x-.061,x+.061,.67,.77,.217,cream);
        rod(x,.72,x+.035,.75,.014,.225,ink);
      }
      break;
    case 'camera':
      counter(.49);
      for(const [x,width,color] of [[-.38,.34,ink],[.28,.38,leather]]){
        slab(x-width/2,x+width/2,.55,.80,.18,color);
        face(x-width*.28,x-width*.08,.80,.87,.17,ink);
        rim(x,.67,.105,.205,glass,10);
        rim(x,.67,.061,.212,ink,8);
      }
      break;
    case 'toys':
      shelf(.40);
      slab(-.62,-.31,.40,.63,.18,berry);
      slab(-.64,-.31,.63,.81,.17,ochre);
      shape([[-.68,.81],[-.28,.81],[-.48,1.00],[-.57,1.00]],.17,teal);
      slab(-.15,.58,.49,.61,.19,teal);
      slab(.22,.57,.61,.84,.17,berry);
      for(const x of [-.01,.20,.46])rim(x,.45,.048,.199,ink,8);
      break;
    case 'instruments':
      for(const [x,y,color] of [[-.34,.05,leather],[.30,.18,ochre]]){
        shape([[x-.15,y+.13],[x+.11,y+.09],[x+.18,y+.30],[x-.11,y+.42]],.17,color);
        shape([[x-.10,y+.39],[x+.155,y+.28],[x+.09,y+.57],[x-.12,y+.55]],.17,color);
        rim(x+.012,y+.43,.064,.184,ink,10);
        rod(x+.025,y+.53,x+.077,y+1.17,.081,.179,wood);
        face(x+.03,x+.127,y+1.15,y+1.27,.19,ink);
      }
      break;
    case 'sporting-goods':
      counter(.41);
      for(const [x,color] of [[-.48,ochre],[-.14,cream],[.24,berry]]){
        rim(x,.55,.132,.183,color,10);
        face(x-.052,x+.052,.50,.60,.179,color);
      }
      rim(.51,.96,.157,.17,teal,10);
      rod(.51,.80,.46,.48,.043,.172,ink);
      rod(.39,.96,.63,.96,.022,.173,cream);
      rod(.51,.84,.51,1.08,.022,.173,cream);
      break;
  }
}
