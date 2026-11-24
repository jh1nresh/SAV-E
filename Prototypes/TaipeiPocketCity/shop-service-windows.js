// Illustrative equipment for documented trades. Physical shop locations come from the frontage pack.
// The original meshes use dimensions from the free Polyfork tire-ccf0eb (0.70 × 0.68 m),
// hammer-fa3e51 (0.16 × 0.32 m), armchair-980c7c (0.88 × 0.90 m) and desk-monitor-32cfce
// (0.60 × 0.43 m). Display only the visible portion of large vehicles behind the opening.
export function drawServiceWindow(category,tools,paint){
  const {face,slab,shape,rod,rim,bottle}=tools;
  const {ink,wood,cream,glass,teal,leather,berry,ochre,sage,grape}=paint;
  switch(category){
    case 'shoes':
      for(const [height,heel,color] of [[.47,.26,leather],[.96,.17,teal]]){
        slab(-.65,.65,height-.06,height,.21,wood);
        for(const x of [-.32,.23]){
          shape([[x-.15,height+.035],[x+.19,height+.035],[x+.14,height+.12],[x-.11,height+heel]],.17,color);
          face(x-.16,x+.20,height,height+.04,.183,cream);
          rod(x-.07,height+heel*.83,x+.015,height+.12,.024,.187,cream);
        }
      }
      break;
    case 'cosmetics':
      slab(-.69,.69,.14,.49,.20,berry);
      for(const [x,h,color] of [[-.51,.22,berry],[-.31,.27,leather],[-.11,.19,grape]]){
        face(x-.052,x+.052,.49,.68,.17,ink);
        shape([[x-.039,.68],[x+.039,.68],[x+.039,.68+h],[x-.039,.64+h]],.18,color);
      }
      for(const x of [.16,.45])bottle(x,.49,.42,.16,sage);
      break;
    case 'beauty':
      // A vanity and folded linens also suit a brow, facial or nail studio.
      slab(-.68,.68,.55,.65,.22,wood);
      slab(-.52,.06,.70,1.45,.10,grape);
      face(-.46,0,.76,1.39,.112,glass);
      rod(-.40,1.04,-.12,1.30,.035,.12,cream);
      for(const y of [.65,.73,.81])slab(.15,.53,y,y+.067,.17,cream);
      bottle(-.02,.65,.22,.18,teal);
      break;
    case 'massage':
      // The padded treatment surface has a separate head cushion and a folding trestle.
      rod(-.57,.03,-.14,.52,.064,.12,wood);
      rod(-.14,.03,-.57,.52,.064,.12,wood);
      rod(.17,.03,.58,.52,.064,.12,wood);
      rod(.58,.03,.17,.52,.064,.12,wood);
      slab(-.75,.48,.49,.64,.22,sage);
      slab(.48,.76,.59,.72,.18,cream);
      slab(-.55,-.20,.64,.73,.21,cream);
      break;
    case 'jewelry':
      slab(-.68,.68,.32,.44,.21,wood);
      shape([[-.32,.44],[.32,.44],[.14,.78],[-.14,.78]],.12,ink);
      shape([[-.14,.78],[.14,.78],[.33,1.06],[-.33,1.06]],.12,ink);
      rod(-.25,1.02,-.12,.86,.032,.14,ochre);
      rod(-.12,.86,0,.81,.032,.14,ochre);
      rod(0,.81,.12,.86,.032,.14,ochre);
      rod(.12,.86,.25,1.02,.032,.14,ochre);
      shape([[0,.82],[.055,.76],[0,.68],[-.055,.76]],.15,teal);
      break;
    case 'motorcycle':
      for(const x of [-.49,.49])rim(x,.29,.24,.13,ink,10);
      shape([[-.66,.53],[-.12,.51],[.04,.67],[-.40,.76]],.19,teal);
      slab(-.43,-.06,.72,.79,.20,leather);
      shape([[-.16,.50],[.24,.48],[.31,.38],[-.09,.37]],.19,ink);
      rod(.24,.44,.33,.92,.088,.19,teal);
      rod(.32,.80,.49,.28,.054,.16,ink);
      rod(.33,.92,.19,.96,.05,.18,ink);
      face(.31,.43,.84,.92,.208,cream);
      break;
    case 'tyres':
    case 'car_parts':
    case 'car_repair':
    case 'motorcycle_repair':{
      const tires=category==='tyres', parts=category==='car_parts', moto=category==='motorcycle_repair';
      const radius=moto?.23:.34;
      const center=tires?-.35:-.37;
      slab(-.77,.76,.06,.14,.19,wood);
      rim(center,.14+radius,radius,.15,ink,12);
      rim(center,.14+radius,radius*.76,.16,parts?glass:ink,10);
      if(tires){
        rim(.36,.48,.34,.12,ink,12);
        rim(.36,.48,.26,.13,ink,10);
      }else if(parts){
        // Boxed parts and a pierced brake rotor on the retail shelf.
        rim(center,.48,.14,.17,glass,8);
        for(const x of [.10,.39])slab(x,x+.22,.14,.41,.17,teal);
      }else{
        // A service trolley beside the wheel distinguishes repair from a showroom.
        slab(.06,.62,.19,.63,.20,moto?teal:leather);
        for(const y of [.32,.47,.59])face(.13,.54,y-.025,y,.208,cream);
        rod(.12,.63,.35,.83,.054,.19,ink);
        rod(.35,.83,.35,.93,.049,.19,ink);
        rod(.35,.83,.45,.86,.049,.19,ink);
      }
      break;
    }
    case 'car':
      // The vehicle faces the window, so its bonnet and grille fit the bay.
      shape([[-.72,.62],[.72,.62],[.51,.97],[-.47,.97]],.10,ink);
      shape([[-.63,.66],[.63,.66],[.47,.90],[-.43,.90]],.12,glass);
      shape([[-.75,.40],[.75,.40],[.68,.68],[-.67,.68]],.19,teal);
      slab(-.70,.70,.28,.41,.22,ink);
      for(const x of [-.64,.42])face(x,x+.22,.45,.54,.21,cream);
      for(const y of [.40,.46])face(-.24,.24,y,y+.025,.22,ink);
      break;
    case 'hardware':
    case 'doityourself':
      slab(-.67,.67,.38,1.24,.09,wood);
      // Pegboard silhouettes: hammer, open spanner and saw.
      rod(-.42,.71,-.35,1.02,.048,.14,ochre);
      rod(-.42,1.03,-.26,1.00,.073,.15,ink);
      rod(-.13,.62,.00,.98,.056,.13,glass);
      rod(.00,.98,-.04,1.08,.043,.14,glass);
      rod(.00,.98,.10,1.02,.043,.14,glass);
      shape([[.20,.65],[.30,.57],[.51,.94],[.45,1.00]],.13,cream);
      rod(.44,.97,.55,1.05,.075,.15,ink);
      break;
    case 'laundry':
      for(const x of [-.35,.36]){
        slab(x-.30,x+.30,.04,.90,.21,cream);
        face(x-.27,x+.27,.71,.85,.225,teal);
        face(x+.12,x+.23,.76,.80,.24,ink);
        rim(x,.40,.22,.24,ink,12);
        rim(x,.40,.17,.244,glass,10);
      }
      break;
    case 'dry_cleaning':
      for(const x of [-.63,.63])face(x-.025,x+.025,.03,1.48,.12,ink);
      slab(-.67,.67,1.45,1.50,.16,wood);
      for(const [x,color] of [[-.34,sage],[.01,cream],[.34,grape]]){
        rod(x,1.46,x,1.36,.03,.14,ink);
        shape([[x-.16,1.25],[x,1.37],[x+.16,1.25],[x+.13,1.13]],.15,color);
        shape([[x-.13,1.25],[x+.13,1.25],[x+.14,.58],[x-.14,.58]],.16,color);
        face(x-.02,x+.02,.67,1.22,.17,glass);
      }
      break;
    case 'furniture':
      for(const x of [-.36,.30])face(x,x+.065,.035,.24,.14,wood);
      slab(-.37,.37,.45,.94,.16,sage);
      slab(-.43,.43,.24,.43,.24,teal);
      for(const x of [-.44,.31])slab(x,x+.13,.43,.63,.255,sage);
      break;
    case 'computer':
    case 'electronics':
    case 'mobile_phone':
      slab(-.70,.70,.42,.50,.23,wood);
      if(category==='mobile_phone'){
        for(const [x,color] of [[-.34,teal],[0,grape],[.34,ochre]]){
          slab(x-.08,x+.08,.50,.56,.19,ink);
          face(x-.083,x+.083,.55,.85,.15,ink);
          face(x-.066,x+.066,.58,.82,.157,color);
        }
      }else if(category==='computer'){
        face(-.28,-.04,.50,.55,.17,ink);
        face(-.19,-.13,.55,.67,.15,ink);
        slab(-.46,.14,.67,1.03,.16,ink);
        face(-.43,.11,.70,1.00,.17,glass);
        slab(.29,.53,.50,1.00,.15,teal);
        face(.34,.48,.88,.91,.16,ink);
      }else{
        // Paired speaker cabinets with separate woofers and tweeters.
        for(const x of [-.32,.32]){
          slab(x-.18,x+.18,.50,1.12,.17,ink);
          rim(x,.72,.12,.184,glass,8);
          rim(x,.98,.055,.184,cream,6);
        }
      }
      break;
  }
}
