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
    case 'interior_decoration':
      slab(-.66,.54,.08,.36,.20,wood);
      // A working material board with long finish samples and a fabric roll.
      slab(-.69,.49,.45,1.41,.10,ink);
      for(const [x,z,color] of [[-.58,1.26,sage],[-.35,1.18,cream],[-.12,1.33,teal],[.11,1.11,leather]]){
        face(x,x+.15,.55,z,.13,color);
      }
      slab(.35,.65,.36,.50,.22,ochre);
      rim(.64,.43,.067,.224,cream,8);
      break;
    case 'pawnbroker':
      // A secure service counter, with no suggestion about what is held behind it.
      slab(-.74,.74,.13,.65,.21,wood);
      slab(-.76,.76,.64,.72,.23,leather);
      face(-.64,.64,.72,1.42,.11,glass);
      for(const x of [-.63,-.39,-.16,.09,.35,.61])face(x-.019,x+.019,.76,1.39,.17,ink);
      face(-.65,.65,1.39,1.45,.19,ink);
      slab(-.22,.17,.72,.79,.215,cream);
      break;
    case 'medical_supply':
      // The large wheel and foot support keep a generic mobility aid identifiable.
      rim(-.37,.37,.27,.18,ink,12);
      rim(-.37,.37,.19,.184,glass,9);
      rim(.23,.24,.12,.18,ink,8);
      rod(-.63,.74,-.41,.30,.048,.20,teal);
      rod(-.40,.30,.24,.37,.053,.19,teal);
      rod(.24,.37,.25,.24,.056,.19,teal);
      slab(-.40,.08,.50,.56,.19,teal);
      face(.12,.38,.14,.20,.21,ink);
      slab(.40,.69,.10,.57,.095,cream);
      face(.44,.65,.26,.32,.105,teal);
      break;
    case 'travel_agency':
      slab(-.72,.72,.15,.54,.20,teal);
      slab(-.74,.71,.53,.61,.22,wood);
      // A folded route map and two stacks of leaflets.
      shape([[-.61,.75],[-.29,.86],[-.29,1.35],[-.61,1.23]],.12,glass);
      shape([[-.29,.86],[.04,.77],[.04,1.25],[-.29,1.35]],.14,cream);
      shape([[.04,.77],[.39,.87],[.39,1.35],[.04,1.25]],.12,glass);
      rod(-.52,.98,-.20,1.11,.025,.155,berry);
      rod(-.20,1.11,.23,1.03,.025,.155,berry);
      for(const [x,y,color] of [[.45,.61,ochre],[.41,.69,sage]])slab(x,.67,y,y+.068,.19,color);
      break;
    case 'funeral_directors':
      // Quiet reception setting. No religious objects are inferred from the trade tag.
      slab(-.71,.71,.22,.45,.22,wood);
      face(-.58,-.49,.04,.23,.14,ink);
      face(.49,.58,.04,.23,.14,ink);
      shape([[-.27,.45],[.27,.45],[.18,.70],[-.18,.70]],.18,cream);
      for(const [x,z,color] of [[-.37,.96,cream],[-.18,1.17,glass],[.02,1.29,cream],[.23,1.11,cream],[.37,.93,glass]]){
        rod(x*.35,.65,x,z,.022,.15,sage);
        shape([[x-.07,z],[x-.035,z+.084],[x+.052,z+.08],[x+.075,z+.011]],.17,color);
      }
      break;
    case 'baby_goods':
      // Baby Pram (Polyfork, 1.15 m side profile, 1.24 m tall) informs the silhouette.
      for(const x of [-.40,.37])rim(x,.23,.139,.21,ink,10);
      rod(-.40,.25,.19,.71,.052,.18,wood);
      rod(.36,.25,-.20,.72,.052,.18,wood);
      shape([[-.47,.73],[.41,.73],[.30,.51],[-.36,.51]],.18,sage);
      shape([[-.42,.73],[.035,.73],[-.04,1.08],[-.31,1.14]],.16,ochre);
      rod(-.30,1.11,-.08,.77,.023,.17,cream);
      rod(.32,.73,.55,1.08,.045,.18,ink);
      rod(.55,1.08,.72,1.12,.047,.18,teal);
      break;
    case 'tattoo':
      // Adjustable studio chair and an articulated lamp.
      rod(-.50,.12,.15,.12,.063,.14,ink);
      rod(-.07,.13,-.07,.55,.087,.14,ink);
      slab(-.37,.18,.52,.67,.22,grape);
      shape([[.11,.61],[.29,.56],[.53,1.09],[.40,1.16]],.21,grape);
      slab(.39,.59,1.10,1.23,.18,ink);
      rod(-.55,.03,-.55,1.04,.047,.16,wood);
      rod(-.55,1.04,-.36,1.39,.042,.16,wood);
      rod(-.36,1.39,-.13,1.33,.041,.16,wood);
      shape([[-.24,1.34],[-.04,1.34],[-.09,1.20],[-.27,1.21]],.18,cream);
      break;
    case 'repair':
      // Field Workbench (Polyfork) supplies proportions for the feet and bench height.
      for(const x of [-.60,.55])face(x-.047,x+.047,.06,.58,.14,ink);
      slab(-.71,.70,.53,.65,.23,wood);
      slab(-.53,-.23,.65,.83,.17,teal);
      face(-.60,-.13,.79,.88,.204,ink);
      face(-.47,-.24,.827,.90,.22,cream);
      rod(-.58,.73,-.32,.73,.028,.224,cream);
      slab(.14,.59,.65,1.02,.15,leather);
      face(.20,.53,.77,.80,.16,cream);
      face(.20,.53,.91,.94,.16,cream);
      break;
    case 'second_hand':
      // A small changing assortment of pre-owned lamps, bags and a folded textile.
      slab(-.72,.72,.20,.32,.19,wood);
      face(-.52,-.48,.32,.80,.15,ink);
      shape([[-.71,.79],[-.30,.79],[-.37,1.11],[-.61,1.11]],.16,ochre);
      slab(-.14,.30,.32,.61,.20,sage);
      rod(-.09,.59,-.065,.74,.033,.21,leather);
      rod(-.065,.74,.19,.74,.033,.21,leather);
      rod(.19,.74,.24,.59,.033,.21,leather);
      for(const y of [.32,.40,.48])slab(.39,.64,y,y+.06,.19,y>.4?cream:berry);
      break;
    case 'pet_grooming':
      slab(-.70,.57,.56,.65,.23,teal);
      for(const dx of [-.39,.21]){
        rod(dx-.18,.07,dx+.17,.55,.035,.12,ink);
        rod(dx+.18,.07,dx-.17,.55,.035,.11,ink);
      }
      rod(.49,.65,.49,1.37,.052,.15,wood);
      rod(.49,1.37,.09,1.37,.047,.15,wood);
      rod(.09,1.35,.09,.93,.020,.16,ochre);
      rim(.09,.87,.073,.16,ochre,8);
      for(const y of [.65,.73])slab(-.55,-.27,y,y+.061,.17,cream);
      break;
    case 'party':
      slab(-.67,.60,.15,.34,.21,berry);
      for(const [x,z,color] of [[-.46,1.18,teal],[-.08,1.43,berry],[.30,1.20,ochre],[.53,1.02,grape]]){
        rod(x,z-.18,.05,.39,.018,.13,wood);
        shape([[x-.14,z],[x-.087,z+.13],[x+.08,z+.15],[x+.15,z+.043]],.18,color);
        shape([[x-.14,z],[x+.15,z+.043],[x+.09,z-.13],[x-.053,z-.16]],.18,color);
        face(x-.06,x-.031,z+.047,z+.09,.185,cream);
      }
      break;
    case 'wigs':
      slab(-.71,.71,.26,.35,.20,wood);
      for(const [x,y,color] of [[-.36,.43,ink],[.34,.46,leather]]){
        face(x-.048,x+.048,.34,y+.15,.15,cream);
        shape([[x-.13,y+.13],[x+.14,y+.12],[x+.12,y+.47],[x-.10,y+.48]],.17,cream);
        shape([[x-.21,y+.18],[x-.12,y+.24],[x-.05,y+.50],[x-.14,y+.57]],.19,color);
        shape([[x-.17,y+.37],[x+.16,y+.35],[x+.10,y+.62],[x-.086,y+.63]],.20,color);
        shape([[x+.07,y+.43],[x+.04,y+.24],[x+.18,y+.13],[x+.17,y+.52]],.19,color);
      }
      break;
    case 'houseware':
      slab(-.65,.65,.16,.34,.22,wood);
      // Simple cookware and plates do not depend on a brand or shelf inventory.
      for(const [x,z,color] of [[-.43,.46,cream],[-.21,.51,ochre],[.04,.47,sage]]){
        rim(x,z,.13,.17,color,8);
        face(x-.048,x+.048,z-.052,z+.05,.14,glass);
      }
      slab(.26,.59,.34,.59,.18,teal);
      rod(.59,.51,.71,.62,.039,.18,wood);
      face(.30,.56,.57,.63,.19,ink);
      break;
    case 'bathroom_furnishing':
      // Basin and faucet. The reference sink is about a metre wide.
      face(-.44,.30,.74,1.39,.11,glass);
      face(-.44,.30,1.38,1.42,.14,cream);
      rod(-.36,.90,-.09,1.18,.025,.13,cream);
      slab(-.58,.49,.13,.59,.21,sage);
      shape([[-.54,.72],[.51,.72],[.41,.55],[-.45,.55]],.22,cream);
      face(-.49,.46,.699,.748,.23,glass);
      rod(-.04,.74,-.04,.95,.041,.20,ink);
      rod(-.04,.95,.15,.96,.044,.21,ink);
      break;
    case 'fishing':
      slab(-.69,.70,.10,.22,.22,wood);
      for(const [x,dx,h,color] of [[-.57,.36,1.34,ochre],[-.27,.36,1.38,teal],[.01,.38,1.29,cream]]){
        rod(x,.20,x+dx,h,.026,.14,color);
        rod(x+.027,.29,x+.09,.48,.043,.17,ink);
        rim(x+.14,.43,.057,.18,leather,8);
      }
      slab(.37,.67,.21,.47,.21,teal);
      break;
    case 'fashion_accessories':
      slab(-.71,.70,.24,.36,.19,wood);
      shape([[-.62,.81],[.05,.81],[-.04,.75],[-.54,.75]],.20,leather);
      shape([[-.54,.79],[-.05,.79],[-.14,1.06],[-.42,1.06]],.18,ochre);
      face(-.49,-.095,.81,.85,.20,grape);
      face(-.30,-.25,.36,.76,.14,ink);
      slab(.22,.64,.37,.64,.19,berry);
      rod(.30,.64,.36,.79,.026,.195,wood);
      rod(.36,.79,.52,.79,.026,.195,wood);
      rod(.52,.79,.57,.64,.026,.195,wood);
      break;
    case 'hearing_aids':
      slab(-.67,.67,.16,.48,.21,sage);
      for(const [x,color] of [[-.28,cream],[.29,ochre]]){
        slab(x-.17,x+.17,.48,.85,.12,ink);
        rod(x-.07,.59,x-.12,.72,.064,.17,color);
        rod(x-.12,.72,x+.04,.80,.064,.17,color);
        rod(x+.04,.80,x+.12,.73,.046,.17,color);
        rod(x+.12,.73,x+.08,.65,.025,.17,color);
      }
      face(-.48,.48,.49,.53,.16,glass);
      break;
    case 'photograph':
      face(-.66,.07,.15,1.47,.08,glass);
      face(-.63,-.59,.18,1.47,.09,cream);
      for(const x of [.01,.53])rod(.27,.85,x,.10,.047,.147,ink);
      rod(.27,.85,.33,.065,.043,.158,ink);
      slab(.08,.48,.85,1.09,.18,ink);
      rim(.30,.96,.134,.206,glass,10);
      slab(.17,.34,1.08,1.15,.17,wood);
      break;
    case 'appliance':
      slab(-.67,.67,.12,.33,.22,teal);
      face(-.33,-.26,.31,.73,.14,wood);
      rim(-.30,.96,.275,.16,ink,12);
      for(const [x,y] of [[-.43,.93],[-.33,1.12],[-.16,.90]]){
        rod(-.30,.96,x,y,.080,.164,cream);
      }
      rim(-.30,.96,.059,.18,ochre,8);
      slab(.16,.58,.33,.61,.17,sage);
      face(.21,.53,.56,.61,.185,ink);
      break;
    case 'outpost':
      slab(-.72,.71,.15,.50,.21,teal);
      slab(-.73,.72,.48,.56,.225,wood);
      for(const [x,y,w,h] of [[-.59,.57,.49,.30],[-.45,.87,.28,.26],[.14,.56,.52,.43]]){
        slab(x,x+w,y,y+h,.185,ochre);
        face(x+w*.41,x+w*.55,y,y+h,.20,cream);
        face(x+w*.59,x+w*.87,y+h*.53,y+h*.68,.205,glass);
      }
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
