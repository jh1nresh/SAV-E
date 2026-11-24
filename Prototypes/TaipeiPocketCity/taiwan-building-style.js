// Pocket City assets/kit/projection.js (ceramic, metal, clear and accent inks) and
// kit/city.js canopy(); examples/gion/city.json (warm timber, tile, fascias) and
// portofino/city.json (painted plaster, shutters, canvas). These supply colour
// relationships, not local architectural styles or claims about a building's paint.
// Taiwanese wall/roof pairs come from survey-layer.js hybridMaterial(). Street-level
// frames, glass and fascias draw on city-shopfronts.js drawing and its category roles.

const joinery = {
  timber: ['#624534', '#978f72', '#eddbb9'],
  almond: ['#665438', '#a5a694', '#f3dfb6'],
  plum: ['#654e63', '#a49b9d', '#efddcb'],
  moss: ['#45655e', '#85a39a', '#e6ddc6'],
  slate: ['#4f596f', '#7e9298', '#e1dbd1'],
  pewter: ['#526764', '#a4b9af', '#eef0e7'],
  bronze: ['#695444', '#a49d8f', '#dfccb1'],
  jade: ['#416a65', '#93b8a8', '#dae7d7'],
  metal: ['#586878', '#91afb9', '#e3e6dd'],
};

// Small, localised areas of fabric, painted fascia and display objects can carry stronger inks.
const textiles = {
  terracotta: ['#af7762', '#6f3a32', '#f4b829'],
  tea: ['#688d86', '#375f48', '#93d3b0'],
  indigo: ['#7a8aa8', '#2c4b5e', '#cfb274'],
  straw: ['#cfb274', '#5e4634', '#71b693'],
  plum: ['#a17080', '#654e63', '#f3a6bb'],
  chalk: ['#f3ead6', '#3d4a53', '#d49c1f'],
  evergreen: ['#54826a', '#375f48', '#f4df9b'],
  ochre: ['#c49458', '#665438', '#ef8867'],
  harbour: ['#295f90', '#304b60', '#f7d785'],
  shutter: ['#337446', '#29573d', '#f4e4c1'],
  poppy: ['#d25a41', '#7c433a', '#f7d785'],
};

// Each row is a finish schedule: body, cap, openings and a compatible street accent.
const finishes = {
  // Direct pigments from Pocket City's Portofino painted-front palette sit alongside Taipei's survey tones.
  saffron:    ['#f5c460', '#a9a39a', 'moss', 'harbour'],
  salmon:     ['#f1a672', '#cb7753', 'timber', 'shutter'],
  coral:      ['#e27351', '#7c7f88', 'slate', 'chalk'],
  ochreTile:  ['#e69a52', '#cb7753', 'moss', 'harbour'],
  tilewash:   ['#f4e4c1', '#c58067', 'moss', 'poppy'],
  paper:      ['#f3ddba', '#858b9b', 'almond', 'tea'],
  cream:      ['#f4e4c1', '#c58067', 'moss', 'chalk'],
  apricot:    ['#e3b88e', '#a9a39a', 'timber', 'evergreen'],
  brick:      ['#c7866d', '#858b9b', 'bronze', 'indigo'],
  pistachio:  ['#b5cba8', '#9ab0b9', 'moss', 'straw'],
  mist:       ['#a5c1cc', '#bbbba8', 'slate', 'terracotta'],
  rose:       ['#edb19b', '#a49d94', 'plum', 'chalk'],
  honey:      ['#f7d785', '#9e9a94', 'timber', 'indigo'],
  stucco:     ['#dcd2bd', '#ccb196', 'bronze', 'plum'],
  pearl:      ['#e9ddc4', '#9ab0b9', 'pewter', 'ochre'],
  porcelain:  ['#f1e7d0', '#74767e', 'timber', 'tea'],
  lacquer:    ['#be7864', '#74767e', 'timber', 'ochre'],
  ochrewash:  ['#e2bb8c', '#83858c', 'timber', 'evergreen'],
  mineral:    ['#b5beb4', '#858b9b', 'pewter', 'ochre'],
  zinc:       ['#a7bcc2', '#8f989b', 'slate', 'chalk'],
  sageMetal:  ['#b4c3ab', '#91a69e', 'pewter', 'indigo'],
  skyGlass:   ['#81b0c1', '#96a8b4', 'metal', 'chalk'],
  jadeGlass:  ['#9dbcad', '#9baaa5', 'jade', 'straw'],
  pearlGlass: ['#a7c1c8', '#9ab0b9', 'metal', 'indigo'],
  limestone:  ['#d2cab2', '#bbbba8', 'bronze', 'tea'],
};

const schedules = {
  residential: ['paper','salmon','pistachio','stucco','mist','brick','tilewash','rose','saffron','apricot','pearl','cream'],
  retail: ['saffron','pistachio','salmon','rose','coral','paper','mist','ochreTile','tilewash','honey'],
  school: ['cream','brick','pistachio','pearl','salmon'],
  industrial: ['zinc','mineral','sageMetal','brick'],
  traditional: ['porcelain','lacquer','ochrewash'],
  tower: ['skyGlass','jadeGlass','limestone','pearlGlass'],
  civic: ['limestone','porcelain','pearl','brick'],
  hall: ['mineral','pearl','sageMetal','stucco'],
};
const plans = Object.fromEntries(Object.entries(schedules).map(([family, names]) =>
  [family, names.map(name => {
    const [wall, roof, opening, fabric] = finishes[name];
    const [frame, glass, trim] = joinery[opening];
    const [awning, sign, accent] = textiles[fabric];
    return Object.freeze({family, wall, roof, frame, glass, trim, awning, sign, accent});
  })]
));

function hash(id) {
  let n = 2166136261;
  for (const ch of String(id)) n = Math.imul(n ^ ch.charCodeAt(0), 16777619);
  return (n ^ (n >>> 16)) >>> 0;
}

const groups = {
  traditional: ['temple','shrine','pagoda'],
  school: ['school','college','university','kindergarten','classroom','dormitory_school'],
  industrial: ['industrial','factory','warehouse','works','manufacture','depot','hangar','silo'],
  civic: ['civic','public','government','townhall','library','community_centre','hospital','museum',
    'court_house','courthouse','fire_station','church','chapel','cathedral','mosque','synagogue'],
  retail: ['retail','commercial','supermarket','kiosk','mall','marketplace','restaurant','cafe','fast_food','bakery'],
  residential: ['house','terrace','semidetached_house','bungalow','apartments','residential','dormitory','hotel'],
};
const kinds = new Map(Object.entries(groups).flatMap(([family, values])=>values.map(v=>[v,family])));
const normal = value => typeof value === 'string' ? value.trim().toLowerCase() : '';

function familyFor(tags, shape) {
  const use = normal(tags['building:use'] || tags.use);
  const form = normal(tags.building || tags.buildingType || tags.type);
  const amenity = normal(tags.amenity);
  if (amenity === 'place_of_worship') {
    const religion = normal(tags.religion);
    return form === 'temple' || form === 'shrine' || ['taoist','buddhist','chinese_folk'].includes(religion)
      ? 'traditional' : 'civic';
  }
  const known = kinds.get(amenity) || kinds.get(use) || kinds.get(form) || kinds.get(normal(tags.tourism));
  if (known === 'traditional' || known === 'school' || known === 'industrial' || known === 'civic') return known;
  const height = parseFloat(shape.height ?? tags.render_height ?? tags.height)
    || 3.2*(parseFloat(tags['building:levels']) || 0);
  if (height >= 38 || form === 'skyscraper') return 'tower';
  if (known) return known;
  const shop = shape.shop || tags.shop;
  if (shop && shop !== 'no') return 'retail';
  const area = Number(shape.area) || Number(shape.width)*Number(shape.depth);
  // Broad, low shells have different finishes from shophouses; this does not identify a factory.
  return area >= 1350 && height <= 18 ? 'hall' : 'residential';
}

const surfaceColours = {
  white:'#f4efe4', cream:'#f3ddba', beige:'#dcd2bd', yellow:'#e6bf65', orange:'#dd955e',
  red:'#b96351', brown:'#916a50', maroon:'#884a48', pink:'#dab0ac', purple:'#9a7f9b',
  blue:'#87a9ba', green:'#91ae92', grey:'#a2a6a4', gray:'#a2a6a4', silver:'#bcc4c4',
  black:'#4a4948', ivory:'#f1e7d0', tan:'#c9a782', turquoise:'#83b6af', teal:'#678f89',
  darkred:'#914d46', darkgreen:'#52725f', darkgray:'#737a79', darkgrey:'#737a79',
  olive:'#929153', lightsteelblue:'#acbdcd', lightyellow:'#f6e7a8', slategrey:'#82909a', slategray:'#82909a',
  lightpink:'#edbfc6', salmon:'#e59881', dimgray:'#777973', indianred:'#b96c65', darkblue:'#465d88',
  aqua:'#7ac9c4', gold:'#e3b550', palegreen:'#b3d6a4', darkseagreen:'#92b396', orangered:'#da784e',
  lightblue:'#aec8cf', lightgray:'#c9cdca', lightgrey:'#c9cdca', lightgreen:'#b5cba8',
};
const localColours = new Map([
  ['白色','white'],['藍色','blue'],['灰色','grey'],['綠色','green'],['紅','red'],['紅色','red'],
  ['米色','beige'],['粉色磁磚','pink'],['黑','black'],
]);
function explicitColour(value) {
  for (const raw of normal(value).split(/[;、]/)) {
    const t = raw.trim();
    if (/^#[0-9a-f]{6}$/.test(t)) return t;
    if (/^#[0-9a-f]{3}$/.test(t)) return '#'+t.slice(1).split('').map(c=>c+c).join('');
    const named = localColours.get(t) || t.replace(/[ _-]/g,'');
    if (Object.hasOwn(surfaceColours,named)) return surfaceColours[named];
  }
}

// For an unpainted surface, material tags narrow the range instead of forcing one hue everywhere.
const materialColours = {
  brick:['#c7866d','#b77962','#c88d72'], stone:['#bcb6a4','#c5bcac','#acaea3'],
  sandstone:['#cfb38d','#d8c09c'], concrete:['#babbb3','#c6c5b9','#d2cfc2'],
  glass:['#81b0c1','#9dbcad','#a7c1c8'], wood:['#a47c5d','#a98c67','#97765a'],
  metal:['#aab6b9','#aebbb0','#a2b3bd'], copper:['#87a99a','#9cac92'],
  tiles:['#c58067','#ae7964','#83858c'], slate:['#74767e','#858b9b'],
  plaster:['#f3ddba','#dcd2bd','#e9ddc4'], grass:['#98ae7c','#91a47c'],
};
const equivalentMaterials = new Map([
  ['bricks','brick'],['granite','stone'],['limestone','stone'],['cement','concrete'],['reinforced_concrete','concrete'],
  ['timber','wood'],['wooden','wood'],['steel','metal'],['zinc','metal'],['aluminium','metal'],
  ['corrugated_metal','metal'],['sheet_metal','metal'],['metal_sheet','metal'],['tile','tiles'],
  ['roof_tiles','tiles'],['clay_tiles','tiles'],['stucco','plaster'],['render','plaster'],
  ['green_roof','grass'],['vegetation','grass'],
]);
function fromMaterial(value, seed) {
  for (const raw of normal(value).split(';')) {
    const key = raw.trim();
    const material = equivalentMaterials.get(key) || key;
    if (Object.hasOwn(materialColours,material)) {
      const tones = materialColours[material];
      return tones[seed % tones.length];
    }
  }
}

/** Stable art for both a distant extrusion and its detailed mesh. Dimensions are metres and m². */
export function buildingStyle(id, tags = {}, shape = {}) {
  const seed = hash(id), family = familyFor(tags, shape), choices = plans[family];
  const plan = choices[seed % choices.length];
  const wallPaint = tags['building:colour'] || tags['building:color'] || tags['facade:colour'] || tags.colour || tags.color;
  const roofPaint = tags['roof:colour'] || tags['roof:color'];
  const wallMaterial = tags['building:material'] || tags['facade:material'] || tags.material;
  const roofMaterial = tags['roof:material'];
  if (!(wallPaint || roofPaint || wallMaterial || roofMaterial)) return plan;
  const wall = explicitColour(wallPaint) || fromMaterial(wallMaterial,seed) || plan.wall;
  const roof = explicitColour(roofPaint) || fromMaterial(roofMaterial,seed>>>8) || plan.roof;
  return {...plan, wall, roof};
}

const merchandise = {
  food: ['restaurant','fast_food','food_court','meal','inspection_store','bar','pub','deli','noodle','food'],
  cafe: ['cafe','coffee','tea','bubble_tea','beverages','ice_cream','bakery','confectionery'],
  produce: ['supermarket','grocery','greengrocer','fruit','vegetables','convenience','seafood','butcher','market','marketplace'],
  books: ['books','bookshop','stationery','newsagent','library'],
  apparel: ['clothes','shoes','fashion','boutique','tailor','apparel','jewelry','jewellery'],
  health: ['pharmacy','chemist','optician','medical_supply','clinic','dentist'],
  flowers: ['florist','garden_centre','flowers'],
  cycle: ['bicycle','bicycle_shop','bicycle_repair_station','motorcycle'],
};
const displays = new Map(Object.entries(merchandise).flatMap(([kind, values]) => values.map(v=>[v,kind])));
const shopFabrics = {
  food: ['poppy','shutter','straw','harbour'], cafe: ['tea','chalk','ochre','plum'],
  produce: ['evergreen','straw','ochre','chalk'], books: ['indigo','straw','tea'],
  apparel: ['plum','indigo','chalk'], health: ['tea','chalk','evergreen'],
  flowers: ['plum','evergreen','straw'], cycle: ['indigo','terracotta','tea'],
};

/** Ground-floor objects depend on mapped shop type; generic shops get a display window. */
export function storefrontStyle(category, shopId, building) {
  const detail = displays.get(normal(category)) || 'display';
  const choices = shopFabrics[detail];
  const fabric = choices ? textiles[choices[hash(shopId) % choices.length]] : null;
  const [awning, sign, accent] = fabric || [building.awning, building.sign, building.accent];
  return {detail, awning, sign, accent, frame:building.frame, glass:building.glass, trim:building.trim};
}
