// Store types come from the public frontage data. The display contents are illustrations.
export const retailWindowTypes = new Map([
  ['books','books'], ['greengrocer','produce'], ['copyshop','copyshop'],
  ['pet','pet-supplies'], ['lottery','lottery'], ['stationery','stationery'],
  ['gift','gifts'], ['alcohol','wine'], ['wine','wine'], ['watches','watches'],
  ['photo','camera'], ['camera','camera'], ['toys','toys'],
  ['musical_instrument','instruments'], ['sports','sporting-goods'],
  ['telecommunication','phone-display'], ['mobile','phone-display'],
  ['kitchen','cookware'], ['outdoor','camping'], ['bed','bedding'],
  ['confectionery','confections'], ['herbalist','herb-drawers'],
  ['curtain','curtains'], ['paint','paint-swatches'], ['hifi','speakers'],
  ['bag','luggage'],
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
    case 'phone-display':
      counter(.49);
      face(-.69,.69,.09,.36,.225,teal);
      for(const [x,y,color] of [[-.49,.64,teal],[-.18,.78,grape],[.14,.68,sage],[.46,.85,berry]]){
        slab(x-.10,x+.10,.49,y-.025,.165,wood);
        face(x-.083,x+.083,y-.05,y+.25,.191,ink);
        face(x-.061,x+.061,y-.017,y+.216,.196,color);
        face(x-.031,x+.031,y+.203,y+.215,.198,cream);
      }
      break;
    case 'cookware':
      shelf(.34);shelf(.97);
      slab(-.68,.68,.12,.34,.22,ink);
      for(const [x,wide,color] of [[-.41,.23,leather],[.29,.27,teal]]){
        shape([[x-wide,.62],[x+wide,.62],[x+wide-.04,.38],[x-wide+.04,.38]],.191,color);
        face(x-wide-.03,x+wide+.03,.61,.67,.199,cream);
        face(x-.055,x+.055,.67,.73,.189,ink);
        face(x-wide-.095,x-wide,.56,.61,.178,ink);
        face(x+wide,x+wide+.095,.56,.61,.178,ink);
      }
      for(const x of [-.30,.33]){
        face(x-.19,x+.19,.98,1.09,.171,ink);
        face(x+.18,x+.31,1.03,1.08,.169,wood);
      }
      break;
    case 'camping':
      // The 0.36 m Polyfork camping-lantern-21d14b and 0.6 m adventurer-s-backpack-b1365c
      // are size references. Use flat-colour silhouettes small enough for the window.
      shelf(.25);
      shape([[-.65,.27],[-.07,.27],[-.13,.79],[-.56,.79]],.173,teal);
      shape([[-.62,.61],[-.095,.61],[-.125,.84],[-.56,.84]],.182,sage);
      face(-.55,-.20,.34,.51,.187,leather);
      for(const x of [-.50,-.22])face(x,x+.033,.53,.76,.187,cream);
      face(-.46,-.29,.82,.88,.17,ink);
      face(.31,.58,.25,.32,.189,ink);
      face(.35,.54,.32,.52,.195,cream);
      face(.39,.50,.34,.50,.197,ochre);
      face(.30,.59,.52,.58,.189,teal);
      rod(.33,.58,.44,.67,.024,.181,ink);
      rod(.44,.67,.56,.58,.024,.181,ink);
      break;
    case 'bedding':
      // Soft stacked layers use the Polyfork hotel-king-bed-c15761 bedding reference.
      face(-.66,.59,.20,1.10,.086,wood);
      for(const y of [.42,.56,.70,.84]){
        slab(-.69,.61,y-.112,y,.21,y===.56?teal:y===.84?leather:cream);
        face(-.66,.58,y-.022,y-.007,.217,cream);
      }
      shape([[-.63,.87],[-.10,.87],[-.03,1.06],[-.57,1.12]],.205,sage);
      shape([[.07,.87],[.58,.87],[.52,1.08],[.13,1.10]],.206,cream);
      break;
    case 'confections':
      slab(-.71,.71,.15,.44,.21,leather);
      for(const y of [.48,.79]){
        shelf(y);
        for(const [i,x] of [-.44,0,.44].entries()){
          const color=palette[(i+(y>.5?2:0))%palette.length];
          slab(x-.18,x+.18,y,y+.11,.19,color);
          face(x-.155,x+.155,y+.10,y+.18,.196,cream);
          face(x-.036,x+.036,y+.025,y+.165,.201,berry);
        }
      }
      break;
    case 'herb-drawers':
      face(-.70,.70,.10,1.34,.086,wood);
      for(const y of [.23,.45,.67,.89]){
        for(const x of [-.45,0,.45]){
          face(x-.204,x+.204,y-.084,y+.084,.173,leather);
          face(x-.053,x+.053,y-.013,y+.02,.184,cream);
        }
      }
      shelf(1.01);
      for(const [i,x] of [-.41,-.16,.13,.39].entries())bottle(x,1.03,.24,.168,i%2?ochre:sage);
      break;
    case 'curtains':
      rod(-.73,1.4,.73,1.4,.04,.17,ink);
      for(const [x,color] of [[-.66,grape],[.24,sage]]){
        for(const [i,low] of [.18,.25,.45,.56].entries()){
          const left=x+i*.117;
          shape([[left,1.39],[left+.113,1.39],[left+.134,low],[left-.016,low+.01]],
            .172+i*.009,i%2?color:cream);
        }
      }
      face(-.63,-.16,.61,.67,.22,ochre);
      face(.27,.68,.61,.67,.22,leather);
      break;
    case 'paint-swatches':
      shelf(.29);shelf(.59);
      for(const [i,x] of [-.51,-.17,.17,.51].entries()){
        for(const y of [.30,.60]){
          face(x-.113,x+.113,y,y+.21,.176,cream);
          face(x-.113,x+.113,y+.055,y+.123,.185,palette[i]);
          face(x-.123,x+.123,y+.192,y+.225,.185,ink);
        }
        face(x-.08,x+.08,1.04+i*.038,1.24+i*.038,.18,palette[i]);
      }
      break;
    case 'speakers':
      for(const x of [-.47,.47]){
        slab(x-.187,x+.187,.18,1.14,.20,wood);
        face(x-.157,x+.157,.22,1.10,.211,ink);
        rim(x,.59,.115,.219,cream,8);
        rim(x,.925,.063,.219,sage,6);
      }
      slab(-.24,.24,.26,.44,.218,ink);
      face(-.19,.055,.31,.38,.229,teal);
      face(.11,.182,.31,.38,.229,cream);
      break;
    case 'luggage':
      shelf(.22);
      for(const [x,w,h,color] of [[-.38,.47,.70,teal],[.26,.46,.59,berry]]){
        slab(x-w/2,x+w/2,.28,.28+h,.205,color);
        face(x-.08,x+.08,.29+h,.34+h,.195,ink);
        for(const dx of [-.12,0,.12])face(x+dx-.013,x+dx+.013,.35,.19+h,.213,cream);
        for(const dx of [-.135,.135])face(x+dx-.046,x+dx+.046,.22,.29,.213,ink);
      }
      break;
  }
}
