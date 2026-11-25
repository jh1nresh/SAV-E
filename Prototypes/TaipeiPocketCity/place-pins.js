// A vivid disc carries the category. Dark glyphs and captions stay legible on the illustrated map.
const badge=(disc,ink,label,solid,lines='')=>({disc,ink,label,solid,lines});
const styles = {
  food: badge('#ff9c42','#542805','#a34506',
    'M5.6 5.5h1.5v5h1v-5h1.5v5h1v-5h1.5v5a3.4 3.4 0 0 1-2.3 3.2V19H8v-5.3a3.4 3.4 0 0 1-2.4-3.2z M17.6 5v14h-2v-5h-2c0-4.7 1.1-7.2 4-9z'),
  cafe: badge('#f5bb66','#58300c','#85460a',
    'M5 8h11v4.7a5.5 5.5 0 0 1-11 0z','M16 9h1.2a2.2 2.2 0 0 1 0 4.4H16 M6 18.4h10'),
  shop: badge('#73d8cc','#104b47','#096963',
    'M6.6 9h10.8l1.1 9.5h-13z','M9 9V8a3 3 0 0 1 6 0v1'),
  fashion: badge('#cbacf7','#542284','#7338a4',
    'M8.9 5.7a3.4 3.4 0 0 0 6.2 0l4.5 2.6-1.8 3.4-2-1v7.7H8.2v-7.7l-2 1-1.8-3.4z'),
  market: badge('#ffbc66','#61300c','#934702',
    'M6 6.2h12l1.5 4.7q-1.7 2.1-3.6 0-2 2.1-3.9 0-2 2.1-4 0-1.8 2.1-3.5 0z M6 13h2.2v3.4h7.6V13H18v5.5H6z'),
  books: badge('#9ec5ff','#223e76','#345792',
    'M4.8 6.7q3.4-1 6.2 1v10q-2.8-2-6.2-1z M19.2 6.7q-3.4-1-6.2 1v10q2.8-2 6.2-1z'),
  sports: badge('#83d9b8','#194f42','#166752','',
    'M5 7h14v10H5z M12 7v10 M14 12a2 2 0 1 1-4 0 2 2 0 1 1 4 0'),
  nature: badge('#8cdf73','#24501b','#337352',
    'M12 3.8l5.2 6.8h-2.1l3.4 4.9H13v3.8h-2v-3.8H5.5l3.4-4.9H6.8z'),
  culture: badge('#fb9cce','#692449','#983268',
    'M4.6 9.8 12 5l7.4 4.8v1H4.6z M6.4 12h2.2v4.2H6.4z M10.9 12h2.2v4.2h-2.2z M15.4 12h2.2v4.2h-2.2z M5.5 17.3h13v1.6h-13z'),
  tower: badge('#fb9cce','#692449','#983268',
    'M11.3 4.7h1.4v2.1h1.7L14 10h1.4l-.6 3.2h1.6l-.7 3.4h1.4V19H7v-2.4h1.4l-.7-3.4h1.6L8.7 10h1.4l-.4-3.2h1.6z'),
  transit: badge('#7dbcff','#123e73','#24599b','',
    'M7 6.5q0-1 1.5-1h7q1.5 0 1.5 1v8q0 1.2-1.5 1.2h-7Q7 15.7 7 14.5z M7 11h10 M9.5 15.8l-2 2.8 M14.5 15.8l2 2.8'),
  bike: badge('#79c9ff','#173f69','#1a608f','',
    'M8.6 15.4a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z M20.4 15.4a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z M6 15.4l3.2-5.7 3 5.1 2.9-5.1H9.2 M14 6.9h2l2 8.5'),
  parking: badge('#86b9ff','#193f7e','#2a5a9b',
    'M8 5.5h5.3a4.5 4.5 0 0 1 0 9H11v4H8z M11 8.2v3.6h2.1a1.8 1.8 0 0 0 0-3.6z'),
  school: badge('#ffd16d','#503709','#7e5409',
    'M3.5 9.5 12 5l8.5 4.5L12 14z M7 12.8l5 2.6 5-2.6v3.1q-5 4.4-10 0z'),
  health: badge('#ff9f9d','#662a36','#983649','M10 5h4v5h5v4h-5v5h-4v-5H5v-4h5z'),
  stay: badge('#9ec5ff','#223e76','#345792','M5 9h3v3H5z M9 10h8q2 0 2 2v2H9z',
    'M4 6v12 M4 14h16v4'),
  other: badge('#c0cbd3','#344650','#485c68',
    'M12 5.3a5 5 0 0 1 5 5c0 3.5-5 8.5-5 8.5s-5-5-5-8.5a5 5 0 0 1 5-5z M14 10.3a2 2 0 1 0-4 0 2 2 0 1 0 4 0z'),
};

const groups = {
  stay:['stay'],
  shop:['shopping','shop','mall','department_store','supermarket','convenience','electronics','gift','hardware','optician','florist','greengrocer','商場','超商','超市','商店','店家','特色店家','deli','bakery_shop','mobile_phone','houseware','furniture','cosmetics','pet','bicycle','computer','toys','stationery','alcohol','confectionery','variety_store','hifi','camera','boutique_store'],
  fashion:['clothes','shoes','jewelry','boutique','服飾'],
  market:['market-area','marketplace','市場','夜市'],
  food:['food','restaurant','fast_food','food_court','street_food','bakery','inspection_store','餐廳','餐飲店家','麵包','小吃店','夜市小吃','早餐店'],
  cafe:['cafe','coffee','tea','bar','beverages','咖啡','咖啡廳','茶飲'],
  books:['books','library','書店'],
  sports:['sports_centre','pitch','stadium','sports_hall','recreation_ground'],
  nature:['park','garden','nature_reserve','playground','zoo','廣場','公園'],
  culture:['museum','gallery','arts_centre','theatre','attraction','monument','memorial','景點','場館','古蹟','歷史店屋'],
  transit:['station','bus_station','subway_entrance','捷運'],
  bike:['bicycle_rental','自行車租借站'],
  parking:['parking','parking_entrance','停車場'],
  school:['school','university','college','kindergarten','educational_institution','學校'],
  health:['chemist','pharmacy','clinic','hospital','dentist','藥局'],
};
const byCategory = new Map(Object.entries(groups).flatMap(([type,values])=>values.map(value=>[value,type])));
export function placePinType(category){return byCategory.get(category) ?? 'other';}
export function pinLabelColor(type){return styles[type].label;}

function pinCanvas(type,style=styles[type]){
  const canvas=document.createElement('canvas');
  const {disc,ink,solid,lines}=style;
  canvas.width=canvas.height=72;
  const ctx=canvas.getContext('2d');
  ctx.scale(3,3);
  ctx.beginPath();ctx.arc(12,12,10.7,0,Math.PI*2);
  ctx.fillStyle=disc;ctx.fill();
  ctx.lineWidth=1.7;ctx.strokeStyle='#fffcf3';ctx.stroke();
  ctx.beginPath();ctx.arc(12,12,9.9,0,Math.PI*2);
  ctx.lineWidth=0.75;ctx.strokeStyle=ink;ctx.stroke();
  ctx.fillStyle=ctx.strokeStyle=ink;
  if(solid)ctx.fill(new Path2D(solid),'evenodd');
  if(lines){
    ctx.lineWidth=type==='bike'?1.45:1.8;
    ctx.lineJoin='round';ctx.lineCap='round';ctx.stroke(new Path2D(lines));
  }
  return canvas;
}
export function placeButtonIcon(category){
  const type=placePinType(category);
  const canvas=pinCanvas(type);
  canvas.setAttribute('aria-hidden','true');
  return {canvas,color:pinLabelColor(type)};
}
export function registerPlaceBadge(map,id,style,type){
  if(map.hasImage?.(id))return;
  const canvas=pinCanvas(type,style);
  map.addImage(id,canvas.getContext('2d').getImageData(0,0,72,72),{pixelRatio:3});
}
export function placePinStyle(map){
  for(const [type,style] of Object.entries(styles))registerPlaceBadge(map,'place-pin-'+type,style,type);
  const category=['case',['==',['get','category'],'commerce_store'],['coalesce',['get','categoryLabel'],''],['coalesce',['get','category'],'']];
  const byType=fn=>['case',['==',['get','placeId'],'poi/way/1159328965'],fn('tower'),
    ['match',category,...Object.entries(groups).flatMap(([type,values])=>[values,fn(type)]),fn('other')]];
  return {
    layout:{
      'icon-image':byType(type=>'place-pin-'+type),'icon-size':1.16,
      'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport','icon-padding':2,
      'text-field':['get','name'],'text-font':['Noto Sans Bold'],
      'text-size':['interpolate',['linear'],['zoom'],17,14,20,16],
      'text-pitch-alignment':'viewport','text-rotation-alignment':'viewport',
      'text-anchor':'left','text-offset':[1.12,0],'text-max-width':10,'text-padding':4,
      'symbol-sort-key':['to-number',['get','rank'],1],
    },
    paint:{'text-color':byType(pinLabelColor),'text-halo-color':'#fffcf3','text-halo-width':1.8},
  };
}
