// Explicit menu and service tags support these illustrative displays.
const cues=new Map([
  ['bubble-tea',['bubble_tea']], ['noodle-bowls',['noodle','noodles','ramen','beef_noodle','beef_noodles','udon','chinese_noodles','牛肉麵','牛肉面']],
  ['hot-pot',['hotpot','hot_pot']], ['dumplings',['dumpling','dumplings','gyoza']],
  ['pizza-slices',['pizza']], ['burger-tray',['burger','burgers']], ['sushi',['sushi']],
  ['tea-service',['tea','teahouse']], ['pastries',['cake','pastry']], ['espresso',['coffee','coffee_shop']],
].flatMap(([cue,values])=>values.map(value=>[value,cue])));
const localCues=new Map([
  ['morning-griddle',['breakfast','brunch']], ['sandwich-board',['sandwich','bagel']],
  ['iron-grill',['teppanyaki']], ['char-grill',['steak_house','steak','barbecue']],
  ['seafood-counter',['seafood']], ['rice-bowls',['beef_bowl']],
  ['curry-counter',['curry']], ['dessert-case',['dessert']], ['box-counter',['bento','便當']],
  ['braised-display',['滷味','魯味']], ['braised-rice',['滷肉飯','魯肉飯']],
  ['fried-counter',['fried_chicken','雞排','鹽酥雞','鹹酥雞']],
  ['steamer-buns',['小籠包','小籠湯包']],
].flatMap(([cue,values])=>values.map(value=>[value,cue])));
const cafeCategories=new Set(['cafe','restaurant','fast_food']);
export function cuisineWindow(category,cuisine){
  if(typeof cuisine!=='string')return null;
  const tokens=cuisine.toLowerCase().split(';').map(token=>token.trim());
  const known=tokens.map(token=>cues.get(token)).filter(Boolean);
  if(['tea','beverages'].includes(category))return known.includes('bubble-tea')?'bubble-tea':null;
  if(!cafeCategories.has(category))return null;
  // Multiple food types can coexist. Show a documented item; drink service takes priority at a café.
  if(category==='cafe'){
    for(const drink of ['bubble-tea','tea-service','espresso'])if(known.includes(drink))return drink;
  }
  // Keep the existing explicit specialty when a multi-tag record also has a broader service cue.
  return known[0]??tokens.map(token=>localCues.get(token)).find(Boolean)??null;
}

const advertisedSpecialties=[
  ['noodle-bowls',/牛肉[麵面]|拉[麵面]|涼[麵面]|刀削[麵面]|陽春[麵面]|擔仔[麵面]|米粉湯|粄條|客家板條/],
  ['dumplings',/水餃|鍋貼|煎餃|蒸餃/],
  ['steamer-buns',/小籠(?:包|湯包)/],
  ['morning-griddle',/早餐|早午餐/],
  ['box-counter',/便當|餐盒|鐵路飯包/],
  ['braised-display',/滷味|魯味/],
  ['braised-rice',/滷肉飯|魯肉飯/],
  ['fried-counter',/雞排(?!骨)|炸雞(?!排骨)|鹽酥雞|鹹酥雞/],
];
const otherFoods=/[，、,／/]|咖啡|奶茶|豆漿|火鍋|麻辣燙|壽司|鐵板燒|咖[哩喱]|披薩|漢堡|burger|潤餅|蔥油餅|斤餅|韭菜盒|水煎包|雲吞|餛飩|麵食|黑白切|清粥|炒[飯麵]|雞湯|雞肉飯|豬排飯|高麗菜飯|丼飯|油飯|肉羹|羹麵|魷魚羹|虱目魚湯|清燉豬腳/i;
const grilled=/[炭碳燒串]烤|烤雞/;
// Only the source build uses business names. Treat a named dish as a
// display cue when the mapped food business advertises a single specialty.
export function advertisedFoodWindow(category,name){
  if(!cafeCategories.has(category)||typeof name!=='string')return null;
  const matches=advertisedSpecialties.filter(([,words])=>words.test(name));
  if(matches.length!==1)return null;
  const [cue,words]=matches[0];
  if(otherFoods.test(name.replace(words,'')))return null;
  if(category==='cafe'&&cue!=='morning-griddle')return null;
  return cue==='fried-counter'&&grilled.test(name)?null:cue;
}

const diningWindows=['dining','menu-stand','sideboard'];
const cafeWindows=['coffee-counter','cafe-table'];
export function categoryFoodWindow(category,seed,categoryLabel){
  switch(category){
    case 'commerce_store':return categoryLabel==='餐飲店家'?'pickup-counter':null;
    case 'inspection_store':return 'pickup-counter';
    case 'restaurant':return diningWindows[seed%diningWindows.length];
    case 'cafe':return cafeWindows[seed%cafeWindows.length];
    case 'fast_food':return 'pickup-counter';
    case 'tea':return 'tea-tins';
    case 'bar':case 'pub':return 'bar-counter';
    case 'ice_cream':return 'ice-case';
    case 'deli':return 'deli-counter';
    case 'seafood':return 'seafood-counter';
    default:return null;
  }
}

// Proportions reference free Polyfork assets chalkboard-menu-board-a24d9d (1.02 × 1.12 m),
// counter-stool-73553a (0.53 × 0.75 m), pizza-slice-ddfb9d (0.20 × 0.05 × 0.32 m)
// and cazuela-pot-79f0ee (0.53 × 0.29 m). These meshes are drawn locally.
export function drawFoodWindow(trade,tools,paint){
  const {face,slab,shape,rod,bottle}=tools;
  const {ink,wood,cream,glass,teal,leather,berry,ochre,sage}=paint;
  const counter=()=>slab(-.70,.70,.34,.45,.21,wood);
  function cup(x,bottom,color){
    shape([[x-.065,bottom],[x+.065,bottom],[x+.089,bottom+.16],[x-.089,bottom+.16]],.17,color);
    face(x-.094,x+.094,bottom+.145,bottom+.17,.18,cream);
  }
  function menu(x,y,w,h){
    slab(x,x+w,y,y+h,.13,wood);
    face(x+.045,x+w-.045,y+.045,y+h-.045,.14,teal);
    for(const [offset,length] of [[.27,.52],[.49,.64],[.73,.40]]){
      face(x+w*.16,x+w*(.16+length),y+h*offset,y+h*offset+.025,.153,cream);
    }
  }
  function plate(x,y){
    shape([[x-.09,y],[x+.09,y],[x+.15,y+.046],[x-.15,y+.046]],.17,cream);
  }
  function stool(x){
    rod(x-.16,.03,x-.10,.62,.047,.12,wood);
    rod(x+.16,.03,x+.10,.62,.047,.12,wood);
    slab(x-.22,x+.22,.61,.70,.19,teal);
  }
  switch(trade){
    case 'morning-griddle':
      // Breakfast service counters are intentionally unstocked when the menu is unknown.
      counter();
      slab(-.63,.12,.45,.57,.22,ink);
      face(-.55,.04,.57,.65,.20,glass);
      for(const x of [-.50,-.29,-.08])face(x,x+.08,.48,.52,.224,cream);
      menu(.22,.45,.43,.66);
      face(.45,.60,.46,.55,.18,teal);
      break;
    case 'sandwich-board':
      counter();
      slab(-.67,.25,.45,.50,.22,ochre);
      for(const x of [-.50,-.19,.11]){
        shape([[x-.10,.50],[x+.09,.50],[x+.03,.65],[x-.09,.60]],.17,cream);
        rod(x-.10,.54,x+.07,.54,.025,.18,sage);
        rod(x-.08,.58,x+.05,.61,.024,.19,ochre);
      }
      menu(.34,.45,.32,.73);
      break;
    case 'iron-grill':
      counter();
      slab(-.67,.66,.45,.53,.23,ink);
      face(-.61,.61,.53,.59,.216,glass);
      for(const x of [-.45,.13]){
        face(x,x+.21,.60,.65,.20,cream);
        rod(x+.08,.63,x+.23,.93,.041,.19,ink);
      }
      slab(-.42,.42,1.12,1.25,.14,ink);
      face(-.35,.35,1.10,1.13,.176,cream);
      break;
    case 'char-grill':
      counter();
      slab(-.65,.57,.45,.65,.24,ink);
      for(const x of [-.48,-.22,.04,.30]){
        rod(x,.65,x+.22,.79,.029,.21,glass);
      }
      for(const x of [-.35,.18]){
        shape([[x-.11,.70],[x+.10,.69],[x+.13,.80],[x-.05,.84]],.22,leather);
      }
      face(-.63,-.39,.79,1.16,.15,wood);
      break;
    case 'seafood-counter':
      // Polyfork's 0.70 m seafood ice platter informs the raised chilled display.
      slab(-.71,.71,.11,.42,.23,teal);
      face(-.67,.67,.44,.73,.17,glass);
      for(const [x,color] of [[-.41,cream],[.02,berry],[.42,sage]]){
        shape([[x-.14,.55],[x+.07,.53],[x+.13,.63],[x-.04,.70]],.20,color);
        shape([[x+.07,.60],[x+.21,.53],[x+.19,.69],[x+.11,.63]],.20,color);
      }
      slab(-.70,.70,.72,.78,.22,cream);
      break;
    case 'rice-bowls':
    case 'curry-counter':{
      const curry=trade==='curry-counter';
      counter();
      for(const [x,y] of [[-.40,.49],[0,.48],[.42,.47]]){
        shape([[x-.10,y],[x+.10,y],[x+.19,y+.12],[x-.19,y+.12]],.18,curry?ochre:leather);
        face(x-.18,x+.18,y+.11,y+.15,.188,cream);
        face(x+.02,x+.13,y+.15,y+.21,.183,curry?leather:ochre);
      }
      if(curry)menu(-.42,.88,.66,.52);
      else for(const x of [-.16,.13])rod(x,.69,x+.16,.96,.026,.19,ink);
      break;
    }
    case 'dessert-case':
      slab(-.71,.71,.08,.49,.22,teal);
      for(const y of [.56,1.05]){
        slab(-.68,.68,y-.05,y,.20,wood);
        for(const [x,color] of [[-.46,cream],[-.06,berry],[.36,ochre]]){
          face(x-.13,x+.13,y,y+.045,.206,cream);
          face(x-.10,x+.10,y+.045,y+.20,.177,color);
          face(x-.09,x+.09,y+.19,y+.23,.182,cream);
        }
      }
      face(-.67,-.63,.49,1.38,.22,glass);
      face(.63,.67,.49,1.38,.22,glass);
      face(-.67,.67,1.34,1.38,.22,glass);
      break;
    case 'box-counter':
      counter();
      for(const [x,y,color] of [[-.43,.46,cream],[.06,.46,ochre],[.28,.68,cream]]){
        slab(x-.20,x+.20,y,y+.12,.20,color);
        face(x-.18,x+.18,y+.080,y+.100,.214,ink);
        face(x-.06,x+.06,y+.025,y+.069,.216,teal);
      }
      menu(-.63,.89,.40,.52);
      break;
    case 'braised-display':
      counter();
      // Broad shallow trays read through the cabinet without individual food textures.
      for(const [x,color] of [[-.45,leather],[0,ochre],[.45,teal]]){
        slab(x-.195,x+.195,.46,.53,.225,ink);
        for(const [dx,dy] of [[-.10,0],[.032,.034]]){
          shape([[x+dx-.048,.54],[x+dx+.082,.54],[x+dx+.062,.65+dy],[x+dx-.064,.64+dy]],.194,color);
        }
      }
      face(-.67,-.64,.51,.84,.235,glass);
      face(.64,.67,.51,.84,.235,glass);
      face(-.67,.67,.82,.85,.235,glass);
      break;
    case 'braised-rice':
      counter();
      // A wide rim and a single dark topping make the rice bowls legible.
      for(const x of [-.39,.31]){
        shape([[x-.12,.46],[x+.12,.46],[x+.25,.63],[x-.25,.63]],.19,cream);
        shape([[x-.23,.63],[x+.23,.63],[x+.17,.72],[x-.15,.71]],.18,cream);
        face(x-.11,x+.12,.64,.72,.204,leather);
        face(x+.13,x+.19,.64,.69,.2,sage);
      }
      slab(-.25,.25,.89,.94,.15,wood);
      face(-.17,.17,1.02,1.23,.15,teal);
      break;
    case 'fried-counter':
      counter();
      slab(-.64,.09,.46,.62,.235,ink);
      slab(-.59,.03,.62,.66,.234,glass);
      rod(-.44,.66,-.31,.91,.049,.21,ink);
      rod(-.14,.66,-.02,.92,.049,.21,ink);
      for(const [x,y] of [[.28,.46],[.53,.49]]){
        shape([[x-.09,y],[x+.09,y],[x+.14,y+.30],[x-.14,y+.30]],.198,cream);
        face(x-.13,x+.13,y+.24,y+.28,.205,ochre);
      }
      face(-.61,-.23,1.015,1.19,.16,teal);
      break;
    case 'menu-stand':
      rod(-.26,.015,-.14,.44,.062,.12,wood);
      rod(.32,.015,.22,.44,.062,.12,wood);
      menu(-.38,.23,.81,.92);
      break;
    case 'sideboard':
      slab(-.70,.70,.15,.65,.19,teal);
      slab(-.74,.74,.64,.71,.23,wood);
      for(const x of [-.44,-.12,.21])for(const y of [.71,.76,.81])plate(x,y);
      rod(.52,.72,.48,.98,.03,.14,cream);
      rod(.54,.72,.62,.98,.03,.145,cream);
      face(.44,.58,.71,.84,.17,ink);
      break;
    case 'cafe-table':
      stool(-.41);
      face(.15,.22,.025,.66,.13,ink);
      slab(-.13,.53,.65,.72,.20,wood);
      cup(.15,.72,teal);
      break;
    case 'coffee-counter':
      counter();
      menu(-.62,.45,.47,.58);
      for(const x of [.15,.41])cup(x,.45,teal);
      break;
    case 'pickup-counter':
      counter();
      for(const y of [.45,.49,.53])slab(-.58,-.08,y,y+.029,.19,teal);
      face(.18,.25,.45,.64,.13,ink);
      shape([[.07,.62],[.37,.59],[.41,.84],[.11,.87]],.17,ink);
      face(.14,.31,.69,.77,.18,cream);
      break;
    case 'tea-tins':
      for(const y of [.40,.93]){
        slab(-.67,.67,y-.07,y,.20,wood);
        for(const [x,color] of [[-.39,sage],[0,ochre],[.39,teal]]){
          slab(x-.105,x+.105,y,y+.26,.16,color);
          face(x-.115,x+.115,y+.24,y+.285,.18,cream);
        }
      }
      break;
    case 'tea-service':
      counter();
      shape([[-.40,.45],[-.05,.45],[.015,.64],[-.45,.64]],.16,teal);
      rod(-.41,.57,-.54,.69,.061,.18,teal);
      rod(-.005,.55,.10,.63,.047,.17,teal);
      rod(.10,.63,-.02,.67,.045,.17,teal);
      face(-.33,-.11,.645,.69,.18,cream);
      for(const x of [.27,.50])cup(x,.45,cream);
      break;
    case 'bubble-tea':
      counter();
      // A cup-sealing frame, feed reel and prepared lidded cups.
      slab(-.62,-.15,.45,.53,.18,teal);
      face(-.59,-.51,.53,.98,.14,teal);
      slab(-.61,-.16,.91,1.03,.18,teal);
      tools.rim(-.46,1.12,.105,.15,cream,8);
      for(const [x,color] of [[-.37,cream],[.12,ochre],[.41,berry]]){
        const bottom=x<0?.53:.45;
        cup(x,bottom,color);
        for(const dx of [-.035,.012])face(x+dx,x+dx+.025,bottom+.02,bottom+.045,.19,ink);
      }
      break;
    case 'noodle-bowls':
      counter();
      for(const x of [-.32,.33]){
        shape([[x-.10,.45],[x+.10,.45],[x+.24,.64],[x-.24,.64]],.17,teal);
        face(x-.24,x+.24,.625,.66,.18,cream);
        for(const dx of [0,.06])rod(x+dx,.64,x+.16+dx,.97,.023,.19,wood);
      }
      break;
    case 'hot-pot':
      counter();
      slab(-.30,.30,.45,.52,.20,ink);
      shape([[-.21,.52],[.21,.52],[.30,.78],[-.30,.78]],.18,leather);
      face(-.32,.32,.75,.80,.20,cream);
      for(const x of [-.38,.28])face(x,x+.10,.68,.72,.17,ink);
      rod(.09,.79,.25,.99,.034,.16,ink);
      break;
    case 'dumplings':
      counter();
      slab(-.62,.62,.45,.50,.19,teal);
      for(const x of [-.45,-.15,.15,.45]){
        shape([[x-.11,.50],[x+.11,.50],[x+.067,.63],[x-.029,.65]],.17,cream);
        rod(x-.031,.64,x+.012,.57,.021,.18,ochre);
      }
      break;
    case 'steamer-buns':
      counter();
      slab(-.66,-.06,.45,.59,.21,leather);
      for(const seam of [.49,.54])face(-.64,-.08,seam,seam+.018,.216,cream);
      for(const x of [-.52,-.34,-.16]){
        shape([[x-.073,.58],[x+.073,.58],[x+.050,.70],[x-.042,.72]],.19,cream);
      }
      slab(.13,.61,.45,.71,.2,leather);
      for(const seam of [.51,.58,.65])face(.16,.59,seam,seam+.016,.206,ochre);
      shape([[.12,.71],[.63,.71],[.52,.78],[.25,.78]],.20,cream);
      break;
    case 'pizza-slices':
      counter();
      for(const [x,y] of [[-.40,.48],[.10,.48],[-.14,.94]]){
        slab(x-.18,x+.19,y-.035,y,.20,wood);
        shape([[x-.14,y+.012],[x+.13,y+.012],[x+.12,y+.13],[x-.12,y+.16]],.17,ochre);
        rod(x-.12,y+.16,x+.12,y+.13,.035,.18,leather);
        face(x-.03,x+.027,y+.055,y+.093,.19,berry);
      }
      break;
    case 'burger-tray':
      counter();
      for(const x of [-.32,.31]){
        face(x-.21,x+.21,.45,.49,.19,cream);
        face(x-.16,x+.16,.49,.54,.16,ochre);
        face(x-.17,x+.17,.54,.59,.17,leather);
        face(x-.18,x+.18,.59,.62,.18,sage);
        shape([[x-.16,.62],[x+.16,.62],[x+.10,.70],[x-.10,.70]],.17,ochre);
      }
      break;
    case 'sushi':
      counter();
      slab(-.60,.60,.45,.50,.19,wood);
      for(const [x,top] of [[-.42,berry],[-.16,ochre],[.11,leather],[.38,berry]]){
        shape([[x-.075,.50],[x+.075,.50],[x+.08,.60],[x-.075,.61]],.15,cream);
        rod(x-.09,.62,x+.09,.60,.045,.17,top);
      }
      break;
    case 'bar-counter':
      stool(-.41);
      slab(-.08,.72,.71,.80,.23,wood);
      bottle(.48,.80,.38,.16,sage);
      for(const x of [.05,.22]){
        face(x-.013,x+.013,.80,.89,.16,cream);
        shape([[x-.016,.89],[x+.016,.89],[x+.074,1.01],[x-.074,1.01]],.17,glass);
      }
      break;
    case 'ice-case':
    case 'deli-counter':{
      const ice=trade==='ice-case';
      slab(-.69,.69,.12,.52,.21,ice?teal:wood);
      for(const [x,color] of [[-.41,ochre],[0,cream],[.41,ice?berry:sage]]){
        face(x-.18,x+.18,.52,.60,.18,glass);
        shape([[x-.12,.60],[x+.12,.60],[x+.085,ice?.73:.66],[x-.067,ice?.76:.68]],.15,color);
        if(ice)rod(x+.03,.69,x+.085,.87,.026,.16,cream);
      }
      rod(-.68,.52,-.61,.97,.033,.22,glass);
      rod(.68,.52,.61,.97,.033,.22,glass);
      face(-.61,.61,.95,.99,.22,glass);
      break;
    }
  }
}
