import {placePinStyle,pinLabelColor} from './place-pins.js?v=street-trades-1';
import {streetShopPinStyle} from './shop-trades.js?v=neighborhood-services-1';
export const city170PlaceLayers = ['city170-poi-labels', 'city170-shop-names', 'city170-vendor-awnings', 'city170-poi-dots'];

const name = ['coalesce', ['get', 'name'], ''];
const category = ['coalesce', ['get', 'category'], ''];
const named = ['!=', name, ''];
const inCityDetail = ['!=', ['get', 'protected'], true];
const atGround = ['all', ['!=',['get','offGround'],true], ['==', ['to-number', ['get', 'layer'], 0], 0],
  ...['bridge', 'tunnel', 'indoor'].map(tag => ['==', ['coalesce', ['get', tag], 'no'], 'no']),
];

function kinds(...values) {
  return ['in', ['get', 'kind'], ['literal', values]];
}

function fade(start, end, opacity) {
  return ['interpolate', ['linear'], ['zoom'], start, 0, end, opacity];
}

function groundWidth(defaultWidth, maximum, edge = 0) {
  const width = ['min', maximum, ['max', 1, ['to-number', ['get', 'width'], defaultWidth]]];
  // Taipei's latitude gives 1.85 map pixels per metre at zoom 17.
  return ['interpolate', ['exponential', 2], ['zoom'],
    15, ['*', 0.4625, ['+', width, edge]],
    20, ['*', 14.8, ['+', width, edge]],
  ];
}

function addSprite(map, id, draw, size = 24) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size * 2;
  const ctx = canvas.getContext('2d');
  ctx.scale(2, 2);
  ctx.lineJoin = 'round';
  draw(ctx);
  map.addImage(id, ctx.getImageData(0, 0, canvas.width, canvas.height), { pixelRatio: 2 });
}

function drawVendorAwning(ctx) {
  ctx.fillStyle = '#ecd2a7';
  ctx.fillRect(5, 9, 14, 12);
  ctx.strokeStyle = '#805343';
  ctx.strokeRect(5, 9, 14, 12);
  ctx.fillStyle = '#8e6452';
  ctx.fillRect(7, 11, 10, 5);
  ctx.fillStyle = '#b77e61';
  ctx.fillRect(5, 16, 14, 2);

  ctx.beginPath();
  ctx.moveTo(2, 10);
  ctx.lineTo(5.5, 4);
  ctx.lineTo(18.5, 4);
  ctx.lineTo(22, 10);
  ctx.lineTo(22, 12);
  ctx.lineTo(2, 12);
  ctx.closePath();
  ctx.fillStyle = '#f9e3b7';
  ctx.fill();
  ctx.save();
  ctx.clip();
  ctx.fillStyle = '#c27153';
  for (const x of [2, 10, 18]) ctx.fillRect(x, 4, 4, 8);
  ctx.restore();
  ctx.stroke();
}

const groveTrees = [
  {
    colors: ['#4f7a56', '#75a46a', '#a6c783'],
    crowns: [[8, 11, 5.9, 5.7], [15.7, 11.2, 5.9, 6.1], [11.8, 8.6, 6.2, 6.3]],
  },
  {
    colors: ['#557958', '#7e9b62', '#b5c484'],
    crowns: [[12.5, 12.8, 7.1, 6.8], [10.7, 9.8, 5.8, 6.3], [12.7, 7.2, 4.4, 6.1]],
  },
  {
    colors: ['#52714f', '#83a667', '#b8cc8b'],
    crowns: [[7.4, 12, 6.1, 4.8], [16.6, 11.7, 6, 5.3], [12, 8.3, 6.9, 5.1]],
  },
  {
    colors: ['#496e5d', '#6f9e73', '#a9c98e'],
    crowns: [[8.2, 11.8, 5.7, 5.5], [15.5, 10.3, 6.3, 6.3], [11.4, 7.4, 5.6, 5.5]],
  },
];

function drawGroveTree(ctx, { colors, crowns }) {
  ctx.beginPath();
  ctx.ellipse(14.2, 21.3, 7.5, 1.6, -0.16, 0, 2 * Math.PI);
  ctx.fillStyle = '#3e634238';
  ctx.fill();

  ctx.lineCap = 'round';
  ctx.lineWidth = 2.25;
  ctx.strokeStyle = '#67543c';
  ctx.beginPath();
  ctx.moveTo(12.1, 21.9);
  ctx.lineTo(12.2, 13.9);
  ctx.lineTo(15.4, 11.5);
  ctx.stroke();

  ctx.lineWidth = 0.8;
  ctx.strokeStyle = '#385e46';
  for (const [i, [x, y, rx, ry]] of crowns.entries()) {
    ctx.beginPath();
    ctx.ellipse(x, y, rx, ry, i === 2 ? -0.17 : 0.12, 0, 2 * Math.PI);
    ctx.fillStyle = colors[i];
    ctx.fill();
    ctx.stroke();
  }
  const [x, y, rx, ry] = crowns[2];
  ctx.beginPath();
  ctx.ellipse(x - rx * 0.24, y - ry * 0.29, rx * 0.44, ry * 0.31, -0.36, 0, 2 * Math.PI);
  ctx.fillStyle = '#f2e8a343';
  ctx.fill();
}

function drawWaterTexture(ctx) {
  ctx.lineCap = 'round';
  ctx.lineWidth = 0.8;
  for (const [x, y, length] of [[20, 16, 6], [92, 30, 11], [55, 58, 9], [15, 83, 8], [101, 106, 7], [67, 118, 5]]) {
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.quadraticCurveTo(x + length * 0.55, y - 0.85, x + length, y - 0.25);
    ctx.strokeStyle = '#e6f2d866';
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x + 1.9, y + 2.15);
    ctx.lineTo(x + length * 0.8, y + 1.85);
    ctx.strokeStyle = '#33687947';
    ctx.stroke();
  }
}

function drawGrassTexture(ctx) {
  ctx.lineCap = 'round';
  ctx.lineWidth = 0.65;
  for (const [x, y] of [[14, 12], [81, 16], [44, 33], [112, 57], [28, 72], [75, 82], [18, 107], [51, 116], [108, 105]]) {
    ctx.beginPath();
    ctx.moveTo(x - 1.5, y - 1.2);
    ctx.lineTo(x, y);
    ctx.lineTo(x + 1.45, y - 2.4);
    ctx.moveTo(x + 2.5, y + 0.4);
    ctx.lineTo(x + 3.95, y - 0.85);
    ctx.strokeStyle = '#55764355';
    ctx.stroke();
  }
}

export function addCity170Style(map, sourceId, firstLabel) {
  const layers = map.getStyle().layers;
  const schools = map.getSource('city170-schools') ? 'city170-schools' : sourceId;
  const prepared = 'city170-prepared';
  const underRoads = map.getLayer('waterway_tunnel') ? 'waterway_tunnel' : firstLabel;
  // River art and the generic water layer load independently. Keep the illustration visible in either order.
  const underRiver = ['taipei-river-art-shore', 'landcover_sand'].find(id => map.getLayer(id)) ?? underRoads;
  // Existing authored streets and survey buildings remain above the shared ground detail.
  const underStreet = layers.find(layer => /^street-.+-(road-edge|road|walk-edge|walk)$/.test(layer.id))?.id
    ?? (map.getLayer('atlas-shadows') ? 'atlas-shadows' : map.getLayer('survey') ? 'survey' : firstLabel);
  const underBuildings = map.getLayer('survey') ? 'survey' : firstLabel;
  const underLabels = layers.find(layer => /^street-.+-road-labels$/.test(layer.id))?.id;
  const add = (layer, before) => map.addLayer({ source: sourceId, ...layer }, before);
  const detailFilter = (...values) => ['all', kinds(...values), inCityDetail];
  const gradeFilter = kind => ['all', detailFilter(kind), atGround];

  add({
    id: 'city170-forest',
    type: 'fill',
    minzoom: 12.65,
    filter: kinds('forest'),
    paint: {
      'fill-color': ['match',category,'grassland','#c3ce83','wetland','#86b7a0','scrub','#a6b97e','#83a56b'],
      'fill-opacity': fade(12.65, 15, 0.82),
    },
  }, underRoads);
  add({
    id: 'city170-park',
    type: 'fill',
    minzoom: 13.1,
    filter: kinds('park'),
    paint: {
      'fill-color': ['match', category, ['garden', 'grass', 'recreation_ground'], '#c5d890', '#aed08c'],
      'fill-outline-color': '#96b374',
      'fill-opacity': fade(13.1, 15.65, 0.82),
    },
  }, underRoads);
  addSprite(map, 'city170-grass-texture', drawGrassTexture, 128);
  add({
    id: 'city170-grass-texture',
    type: 'fill',
    minzoom: 17,
    filter: kinds('park', 'forest'),
    paint: {
      'fill-pattern': 'city170-grass-texture',
      'fill-opacity': fade(17, 18.4, 0.66),
    },
  }, underRoads);
  add({
    id: 'city170-water',
    type: 'fill',
    minzoom: 12.85,
    filter: kinds('water'),
    paint: {
      'fill-color': '#83bfcc',
      'fill-outline-color': '#6ea7b3',
      'fill-opacity': fade(12.85, 15.2, 0.9),
    },
  }, underRiver);
  addSprite(map, 'city170-water-texture', drawWaterTexture, 128);
  add({
    id: 'city170-water-texture',
    type: 'fill',
    minzoom: 17,
    filter: kinds('water'),
    paint: {
      'fill-pattern': 'city170-water-texture',
      'fill-opacity': fade(17, 18.4, 0.68),
    },
  }, underRiver);
  for (const [id, color, width, opacity] of [
    ['shallows', '#b9d9bf', 2.8, 0.58],
    ['shoreline', '#629a9e', 0.85, 0.76],
  ]) {
    add({
      id: 'city170-water-' + id,
      type: 'line',
      minzoom: 17,
      filter: kinds('water'),
      layout: { 'line-join': 'round' },
      paint: {
        'line-color': color,
        'line-width': ['interpolate', ['linear'], ['zoom'], 17, width * 0.64, 20, width * 1.42],
        'line-opacity': fade(17, 18.15, opacity),
      },
    }, underRiver);
  }
  const fountains='city170-fountain-water';
  if(map.getSource(fountains)){
    const role=['get','role'];
    for(const [key,color] of [['shallows','#aad5ca'],['surface','#75b8b2'],['depth','#5a9da6']]){
      add({
        id:fountains+'-'+key,source:fountains,type:'fill',minzoom:16.85,
        filter:['==',role,key],
        paint:{'fill-color':color,'fill-opacity':fade(16.85,17.85,.94)},
      },underRiver);
    }
    add({
      id:fountains+'-glints',source:fountains,type:'line',minzoom:17.55,
      filter:['==',role,'glint'],
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':'#d8eee1','line-width':['interpolate',['linear'],['zoom'],17.55,.55,20.5,1.25],
        'line-opacity':fade(17.55,18.45,.82)},
    },underRiver);
  }
  if(map.getSource('city170-farmland')){
    add({
      id:'city170-field-plots',source:'city170-farmland',type:'fill',minzoom:14,
      paint:{'fill-color':['match',category,'orchard','#a3ba76','#c7c789'],
      'fill-outline-color':'#a5ae77','fill-opacity':fade(14,16,.80)},
    },'city170-forest');
    // Cartographic textures distinguish cultivation at street scale. Boundaries follow OSM.
    for(const orchard of [false,true]){
      const id=orchard?'city170-orchard-texture':'city170-farm-texture';
      addSprite(map,id,ctx=>{
        ctx.lineCap='round';
        if(orchard){
          for(const [x,y] of [[8,9],[25,25]]){
            ctx.fillStyle='#73894f88';ctx.beginPath();ctx.ellipse(x,y,2.7,2,.2,0,Math.PI*2);ctx.fill();
            ctx.fillStyle='#dae4ad';ctx.fillRect(x-.6,y-1.25,1.5,.8);
          }
        }else{
          ctx.strokeStyle='#8d9d684d';ctx.lineWidth=1;
          for(let x=-32;x<64;x+=8){ctx.beginPath();ctx.moveTo(x,32);ctx.lineTo(x+16,0);ctx.stroke();}
        }
      },32);
      add({id,type:'fill',source:'city170-farmland',minzoom:16,
        filter:['==',category,orchard?'orchard':'farmland'],
        paint:{'fill-pattern':id,'fill-opacity':fade(16,17.5,.72)}},'city170-forest');
    }
  }
  if(map.getSource('city170-waterways')){
    for(const seasonal of [false,true])add({
      id:seasonal?'city170-seasonal-stream':'city170-surface-stream',source:'city170-waterways',
      type:'line',minzoom:14,filter:['==',['get','seasonal'],seasonal],
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':seasonal?'#89aaa1':'#70aeb9','line-opacity':fade(14,16,.85),
        'line-width':['interpolate',['exponential',1.55],['zoom'],14,.6,18,
          ['match',category,'river',4,'canal',3,'stream',2.5,1.4],21,
          ['match',category,'river',12,'canal',8,'stream',5.8,3]],
        ...(seasonal?{'line-dasharray':[2,2]}:{})},
    },underRoads);
    // Where only a stream centreline is surveyed, keep the light within its cartographic stroke.
    add({
      id:'city170-stream-glints', source:'city170-waterways', type:'line', minzoom:16.8,
      filter:['all',['==',['get','seasonal'],false],['in',category,['literal',['river','stream']]]],
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':'#d4e8cb','line-opacity':fade(16.8,18.2,.78),
        'line-width':['interpolate',['linear'],['zoom'],16.8,.45,19,.9,21,1.4],
        'line-dasharray':[3,8]},
    },underRoads);
  }
  add({
    id: 'city170-school',
    source: schools,
    type: 'fill',
    minzoom: 14.8,
    filter: kinds('school'),
    paint: {
      'fill-color': ['match', category, 'university', '#e6c797', 'kindergarten', '#ebd8b6', '#edcea0'],
      'fill-outline-color': '#b59165',
      'fill-opacity': fade(14.8, 16.65, 0.91),
    },
  }, underRoads);
  add({
    id: 'city170-pitch',
    type: 'fill',
    minzoom: 15.25,
    filter: ['all',kinds('pitch'),atGround],
    paint: {
      'fill-color': ['case', ['==', category, 'track'], '#bd856e',
        ['match', ['coalesce', ['get', 'sport'], category],
          ['basketball', 'volleyball'], '#bc836c',
          ['tennis', 'badminton'], '#7d9e93',
          ['running', 'athletics'], '#cd947a',
          '#a1bd74',
        ],
      ],
      'fill-outline-color': ['case', ['==', category, 'track'], '#966855', '#f6edcf'],
      'fill-opacity': fade(15.25, 17, 0.97),
    },
  }, underRoads);
  add({
    id: 'city170-pitch-linework',
    type: 'line',
    minzoom: 16.8,
    filter: ['all', kinds('pitch'),atGround, ['!=', category, 'track']],
    paint: {
      'line-color': '#fbf0d2',
      'line-width': ['interpolate', ['linear'], ['zoom'], 16.8, 0.7, 20, 1.65],
      'line-dasharray': [2.4, 1.25],
      'line-opacity': fade(16.8, 18, 0.86),
    },
  }, underRoads);
  add({
    id: 'city170-track-outline',
    type: 'line',
    minzoom: 16.65,
    filter: ['all', kinds('pitch'),atGround, ['==', category, 'track']],
    paint: {
      'line-color': '#835d49',
      'line-width': ['interpolate', ['linear'], ['zoom'], 16.65, 0.65, 20, 1.5],
      'line-opacity': fade(16.65, 18.05, 0.66),
    },
  }, underRoads);

  add({
    id: 'city170-building-footprints',
    type: 'fill',
    minzoom: 16.75,
    filter: detailFilter('building'),
    paint: {
      'fill-color': '#c9bba1',
      'fill-outline-color': '#bfae90',
      'fill-opacity': fade(16.75, 18.1, 0.48),
    },
  }, underStreet);
  add({
    id: 'city170-road-edge',
    type: 'line',
    minzoom: 16.35,
    filter: gradeFilter('road'),
    layout: { 'line-join': 'round', 'line-cap': 'round' },
    paint: {
      'line-color': '#c7b7a1',
      'line-width': groundWidth(5.4, 24, 0.9),
      'line-opacity': fade(16.35, 17.35, 0.95),
    },
  }, underStreet);
  add({
    id: 'city170-road',
    type: 'line',
    minzoom: 16.35,
    filter: gradeFilter('road'),
    layout: { 'line-join': 'round', 'line-cap': 'round' },
    paint: {
      'line-color': ['match', category,
        ['trunk', 'primary', 'secondary'], '#8994a4',
        ['living_street', 'service'], '#a19fa1',
        '#969dab',
      ],
      'line-width': groundWidth(5.4, 24),
      'line-opacity': fade(16.35, 17.35, 0.98),
    },
  }, underStreet);
  add({
    id: 'city170-walk',
    type: 'line',
    minzoom: 15.7,
    filter: gradeFilter('walk'),
    layout: { 'line-join': 'round', 'line-cap': 'round' },
    paint: {
      'line-color': ['match', category, ['path', 'track', 'bridleway'], '#c29e72', '#f0d1a2'],
      'line-width': groundWidth(1.8, 8),
      'line-opacity': fade(15.7, 17.4, 0.9),
    },
  }, underStreet);
  if (map.getSource(prepared)) {
    for (const [kind, color, zoom, fullZoom, opacity] of [
      ['skill-paving', '#f0d1a2', 16.65, 17.35, 0.93],
      ['lane', '#fcf2dc', 17.35, 18, 0.9],
      ['crossing', '#fff0d4', 16.95, 17.65, 0.98],
    ]) {
      add({
        id: 'city170-prepared-' + kind,
        source: prepared,
        type: 'fill',
        minzoom: zoom,
        filter: kinds(kind),
        paint: { 'fill-color': color, 'fill-antialias': false, 'fill-opacity': fade(zoom, fullZoom, opacity) },
      }, kind === 'skill-paving' ? 'city170-road-edge' : underBuildings);
    }
    groveTrees.forEach((tree, i) => addSprite(map, 'city170-grove-' + i, ctx => drawGroveTree(ctx, tree)));
    add({
      id: 'city170-grove-trees',
      source: prepared,
      type: 'symbol',
      minzoom: 16.65,
      filter: kinds('grove-tree'),
      layout: {
        'icon-image': ['match', ['to-number', ['get', 'variant'], 0],
          1, 'city170-grove-1', 2, 'city170-grove-2', 3, 'city170-grove-3', 'city170-grove-0',
        ],
        // A 20-pixel crown at half scale on z17 spans about 5.4 metres in Taipei.
        'icon-size': ['interpolate', ['exponential', 2], ['zoom'], 16, 0.25, 20, 4],
        'icon-anchor': 'bottom',
        'icon-offset': [0, 1.9],
        'icon-pitch-alignment': 'map',
        'icon-rotation-alignment': 'viewport',
        'icon-allow-overlap': true,
        'icon-ignore-placement': true,
      },
      paint: { 'icon-opacity': fade(16.65, 17.55, 0.94) },
    }, underBuildings);
  }
  add({
    id: 'city170-trees',
    type: 'circle',
    minzoom: 16.65,
    filter: detailFilter('tree'),
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 16.65, 2, 18.4, 5.5, 20, 10],
      'circle-color': '#678c61',
      'circle-stroke-color': '#476b53',
      'circle-stroke-width': 0.7,
      'circle-opacity': fade(16.65, 17.75, 0.9),
      'circle-stroke-opacity': fade(16.65, 17.75, 0.84),
      'circle-pitch-alignment': 'map',
      'circle-pitch-scale': 'map',
    },
  }, underStreet);
  add({
    id: 'city170-tree-crowns',
    type: 'circle',
    minzoom: 17.3,
    filter: detailFilter('tree'),
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 17.3, 1.75, 18.4, 3.9, 20, 7],
      'circle-color': '#96b879',
      'circle-opacity': fade(17.3, 18.05, 0.9),
      'circle-translate': [-0.7, -1.1],
      'circle-translate-anchor': 'map',
      'circle-pitch-alignment': 'map',
      'circle-pitch-scale': 'map',
    },
  }, underStreet);

  // Keep a court's pigment and lines in the same terrain paint pass.
  add({
    id:'city170-playing-area-fill',source:'city170-playing-areas',type:'fill',minzoom:17,filter:kinds('pitch'),
    paint:{'fill-color':['match',['get','sport'],['basketball','volleyball'],'#bc836c','#7d9e93'],
      'fill-outline-color':'#f6edcf'},
  },underBuildings);
  add({
    id:'city170-court-markings',source:'city170-playing-areas',type:'line',minzoom:17,filter:kinds('court-markings'),
    paint:{'line-color':'#fff2d5','line-width':['interpolate',['linear'],['zoom'],17,.7,20,1.65],
      'line-opacity':fade(17,18,.92)},
  },underBuildings);
  add({
    id:'city170-court-equipment',source:'city170-equipment',type:'fill-extrusion',minzoom:18.5,filter:kinds('court-equipment','bike-dock'),
    paint:{'fill-extrusion-base':['get','base'],'fill-extrusion-height':['get','top'],
      'fill-extrusion-color':['get','color'],'fill-extrusion-vertical-gradient':false},
  },firstLabel);
  add({
    id:'city170-stair-treads',type:'line',minzoom:17.35,
    filter:['all',gradeFilter('walk'),['==',category,'steps'],['==',['coalesce',['get','covered'],'no'],'no']],
    layout:{'line-cap':'butt','line-join':'round'},
    paint:{'line-color':'#94765c','line-width':groundWidth(1.6,5),
      'line-dasharray':[.15,.50],'line-opacity':fade(17.35,18.4,.9)},
  },underBuildings);
  // Street names use the base map and the existing authored road-name layer.
  // Campus and shop labels share the map's collision pass with those labels.
  const pin=placePinStyle(map);
  add({
    id: 'city170-school-names',
    source: schools,
    type: 'symbol',
    minzoom: 15.7,
    filter: ['all', kinds(schools === sourceId ? 'school' : 'school-label'), named],
    layout: {
      ...pin.layout,'icon-image':'place-pin-school',
      'text-field': name,
      'text-font': ['Noto Sans Bold'],
      'text-size': ['interpolate', ['linear'], ['zoom'], 15.7, 12, 19, 16],
      'text-max-width': 11,
      'text-padding': 9,
      'symbol-sort-key': ['to-number', ['get', 'rank'], 1],
    },
    paint: {
      'text-color': pinLabelColor('school'),
      'text-halo-color': '#fff4df',
      'text-halo-width': 1.45,
    },
  }, underLabels);
  const isVendor = ['==', ['get', 'vendor'], true];
  const places = ['all', detailFilter('poi', 'vendor'),
    ['!', ['in', category, ['literal', ['school', 'university', 'college', 'kindergarten']]]],
  ];
  add({
    id: 'city170-poi-dots',
    type: 'circle',
    minzoom: 17.8,
    filter: ['all',places,['!',named]],
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 17.8, 2.6, 20, 4.7],
      'circle-color': ['case', isVendor, '#c16d52', ['match', category,
        ['marketplace', 'market', 'street_vendor', 'street_food', 'food_court'], '#c16d52',
        ['restaurant', 'fast_food', 'cafe', 'bakery'], '#ad7651',
        '#567d71',
      ]],
      'circle-stroke-color': '#fff6e5',
      'circle-stroke-width': 0.9,
      'circle-opacity': fade(17.8, 18.35, 0.98),
      'circle-stroke-opacity': fade(17.8, 18.35, 0.98),
    },
  }, underLabels);
  addSprite(map, 'city170-vendor-awning', drawVendorAwning);
  add({
    id: 'city170-vendor-awnings',
    type: 'symbol',
    minzoom: 18.15,
    filter: ['all', places, isVendor],
    layout: {
      'icon-image': 'city170-vendor-awning',
      'icon-size': ['interpolate', ['linear'], ['zoom'], 18.15, 0.7, 20, 1.18],
      'icon-anchor': 'bottom',
      'icon-padding': 3,
      'icon-allow-overlap': true,
      'icon-ignore-placement': true,
      'symbol-sort-key': ['to-number', ['get', 'rank'], 1],
    },
    paint: { 'icon-opacity': fade(18.15, 18.6, 1) },
  }, underLabels);
  // Street-scale labels use the same collision system as road and school names.
  add({
    id:'city170-shop-names', type:'symbol', minzoom:16.95, maxzoom:17.8,
    filter:['all',places,named,['any',['==',['get','commerceListed'],true],['in',category,['literal',[
      'commerce_store','inspection_store','restaurant','cafe','bakery','convenience','fast_food','clothes',
      'hairdresser','pharmacy','beverages','supermarket','deli','optician','beauty','books',
      'ice_cream','tea','bar','shoes','florist','gift','jewelry','electronics','hardware'
    ]]]]],
    layout:{...pin.layout,'text-padding':9},paint:pin.paint,
  },underLabels);
  add({
    id: 'city170-poi-labels',
    type: 'symbol',
    minzoom: 17.8,
    filter: ['all', places, named],
    ...streetShopPinStyle(map,pin),
  }, underLabels);
  return pin;
}
