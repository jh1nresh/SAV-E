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
  ['variety_store','mixed-shelves'], ['religion','ritual-goods'],
  ['antiques','curio-cabinet'], ['art','gallery'], ['frame','frame-rack'],
  ['food','pantry-goods'], ['grocery','pantry-goods'], ['general','pantry-goods'],
  ['nuts','pantry-goods'], ['oil','pantry-goods'], ['health_food','pantry-goods'],
  ['butcher','wrapped-meat'], ['garden_centre','nursery'],
  ['locksmith','key-board'], ['tailor','sewing-bench'],
  ['perfumery','fragrance'], ['music','record-shelves'],
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
    case 'mixed-shelves':
      for(const [index,y] of [.25,.63,1.02].entries()){
        shelf(y);
        for(const [i,x] of [-.52,-.18,.16,.49].entries()){
          const w=[.13,.102,.14,.086][(index+i)%4],h=[.16,.23,.12,.20][(index*2+i)%4];
          face(x-w,x+w,y,y+h,.18,palette[(index+i)%5]);
          face(x-w+.025,x+w-.025,y+h-.06,y+h-.023,.186,cream);
        }
      }
      break;
    case 'ritual-goods':
      shelf(.34);shelf(.89);
      for(const [i,x] of [-.49,-.17,.17,.49].entries()){
        const h=[.12,.18,.15,.19][i];
        slab(x-.13,x+.13,.34,.34+h,.19,i%2?ochre:berry);
        face(x-.12,x+.12,.37,.402,.195,cream);
      }
      for(const [x,color] of [[-.40,leather],[.33,ochre]]){
        shape([[x-.16,1.04],[x+.16,1.04],[x+.11,.91],[x-.11,.91]],.196,color);
        face(x-.18,x+.18,1.035,1.061,.204,cream);
      }
      face(-.078,.078,.90,1.29,.176,wood);
      for(const x of [-.046,0,.045])rod(x,1.28,x+.026,1.49,.016,.178,ochre);
      break;
    case 'curio-cabinet':
      face(-.64,.64,.14,1.39,.087,wood);
      for(const y of [.34,.83]){
        shelf(y);
        bottle(-.41,y,.37,.188,y>.5?grape:sage);
        face(-.14,.14,y+.02,y+.29,.19,cream);
        rim(.38,y+.16,.128,.198,y>.5?leather:teal,8);
        face(.30,.46,y+.015,y+.078,.179,ink);
      }
      break;
    case 'gallery':
      // Polyfork's 0.51 by 0.70 m framed-wall-art-d2c8a2 informs frame proportions.
      face(-.68,.68,.24,1.44,.083,cream);
      for(const [x,y,w,h,color] of [[-.35,.54,.49,.67,teal],[.30,.48,.45,.57,berry]]){
        face(x-w/2,x+w/2,y,y+h,.122,wood);
        face(x-w/2+.04,x+w/2-.04,y+.049,y+h-.05,.131,cream);
        shape([[x-w*.36,y+h*.29],[x+w*.36,y+h*.34],[x+w*.16,y+h*.69],[x-w*.22,y+h*.60]],.138,color);
      }
      break;
    case 'frame-rack':
      shelf(.23);
      for(const [x,w,y,h,color] of [[-.38,.49,.25,.98,wood],[.26,.49,.27,.78,ochre],[.05,.41,.29,.58,leather]]){
        const left=x-w/2,right=x+w/2;
        face(left,right,y,y+h,.14+y*.1,color);
        face(left+.065,right-.065,y+.063,y+h-.064,.141+y*.1,cream);
      }
      break;
    case 'pantry-goods':
      for(const y of [.33,.79]){
        shelf(y);
        for(const [i,x] of [-.50,-.18,.14,.47].entries()){
          if((i+(y>.5?1:0))%2===0){
            const h=.25+i*.022;
            bottle(x,y,h,.195,i%2?ochre:sage);
            face(x-.04,x+.04,y+.055,y+.115,.199,cream);
          }else{
            shape([[x-.122,y],[x+.122,y],[x+.09,y+.29],[x-.09,y+.29]],.173,i%3===0?berry:ochre);
            face(x-.067,x+.067,y+.10,y+.18,.177,cream);
          }
        }
      }
      break;
    case 'wrapped-meat':
      slab(-.71,.71,.15,.67,.222,teal);
      face(-.67,.67,.51,.63,.226,cream);
      face(-.69,.69,.69,1.05,.132,glass);
      for(const [x,color] of [[-.44,berry],[0,leather],[.43,berry]]){
        shape([[x-.17,.72],[x+.17,.72],[x+.142,.89],[x-.142,.89]],.178,cream);
        face(x-.108,x+.108,.759,.84,.185,color);
        face(x-.022,x+.093,.803,.849,.189,cream);
      }
      face(-.70,.70,1.01,1.066,.237,ink);
      break;
    case 'nursery':
      // Compare the 0.62 m tall Polyfork potted-autumn-mums-08db8c for scale.
      // The nursery keeps the Pocket Nature greens without assigning a species.
      face(-.66,.66,.13,1.49,.089,cream);
      shelf(.19);
      for(const [x,y,h,color] of [[-.46,.20,.69,sage],[0,.45,.78,teal],[.46,.20,.56,sage]]){
        const base=y+.22;
        shape([[x-.14,base],[x+.14,base],[x+.101,y],[x-.101,y]],.169,leather);
        face(x-.155,x+.155,base-.045,base,.18,ochre);
        rod(x,base,x+.018,base+h*.61,.022,.174,color);
        for(const [side,height] of [[-1,.30],[1,.54],[-1,.71]]){
          const z=base+h*height;
          shape([[x,z],[x+side*.065,z+.124],[x+side*.17,z+.15],[x+side*.12,z+.034]],.186,color);
        }
      }
      face(-.17,.17,.38,.45,.16,wood);
      break;
    case 'key-board':
      slab(-.68,.68,.21,.34,.218,wood);
      face(-.64,.32,.45,1.30,.108,teal);
      for(const y of [.70,1.04])for(const x of [-.46,-.16,.13]){
        rim(x,y,.047,.158,ochre,6);
        face(x-.015,x+.015,y-.158,y-.037,.16,cream);
        face(x,x+.051,y-.146,y-.11,.16,cream);
      }
      slab(.32,.67,.34,.47,.211,ink);
      face(.39,.56,.46,.70,.209,glass);
      face(.49,.69,.62,.70,.206,ink);
      break;
    case 'sewing-bench':
      slab(-.72,.72,.32,.43,.231,wood);
      slab(-.64,-.06,.43,.52,.207,ink);
      face(-.26,-.099,.52,.93,.205,teal);
      face(-.62,-.11,.80,.93,.204,teal);
      face(-.58,-.49,.63,.81,.209,ink);
      rod(-.536,.55,-.536,.67,.016,.22,cream);
      for(const [x,color] of [[.08,berry],[.31,grape],[.55,sage]]){
        face(x-.067,x+.067,.44,1.11,.175,color);
        face(x-.044,x+.044,1.04,1.10,.185,cream);
      }
      break;
    case 'fragrance':
      for(const y of [.33,.67,1.01]){
        shelf(y);
        for(const [i,x] of [-.46,-.15,.17,.48].entries()){
          const top=y+.18+(i%2)*.067;
          face(x-.088,x+.088,y,top,.181,palette[i]);
          face(x-.037,x+.037,top,top+.066,.181,wood);
          face(x-.059,x+.059,y+.057,y+.13,.189,cream);
        }
      }
      break;
    case 'record-shelves':
      slab(-.70,.70,.24,.42,.222,wood);
      for(const [i,x] of [-.46,-.16,.15,.46].entries()){
        face(x-.12,x+.12,.41,.75,.182,palette[i]);
        face(x-.088,x+.088,.60,.68,.185,cream);
      }
      rim(-.36,1.12,.178,.172,ink,10);
      rim(-.36,1.12,.039,.179,ochre,6);
      face(.07,.53,.89,1.32,.158,leather);
      face(.136,.466,.94,1.27,.165,cream);
      rod(.22,1.03,.39,1.19,.046,.172,teal);
      break;
  }
}
