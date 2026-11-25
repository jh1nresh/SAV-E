// Wetland texture represents mapped habitat, not a survey of individual stems or trees.
function bankPattern(map, name, draw) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 128;
  const ctx = canvas.getContext('2d');
  // Wrap marks on all four edges to keep the banks continuous across tiles.
  for (const x of [-128, 0, 128]) for (const y of [-128, 0, 128]) {
    ctx.save();
    ctx.translate(x, y);
    draw(ctx);
    ctx.restore();
  }
  map.addImage(name, ctx.getImageData(0, 0, 128, 128));
}

function mangrove(ctx) {
  // Overlapping crowns form a continuous cover with small openings at the margin.
  for (let i=0; i<49; i++) {
    const col=i%7, row=Math.floor(i/7);
    const x=col*128/7+Math.sin(i*8.1)*5, y=row*128/7+Math.cos(i*3.7)*5;
    const r=6.5+2.8*(1+Math.sin(i*2.3));
    for (const [dx,dy,scale,color] of [[1,2,1,'#426e5b57'],[-1,-1,.83,'#7d9e66c9'],
      [-.27*r,-.3*r,.6,'#9eb57899'],[.46*r,.08*r,.49,'#829e65a8']]) {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.ellipse(x+dx,y+dy,r*scale,r*scale*.67,-.2,0,Math.PI*2);
      ctx.fill();
    }
  }
}

function rushes(ctx) {
  ctx.lineCap = 'round';
  for (const [x,y] of [[6,11],[55,7],[90,33],[23,57],[68,74],[113,84],[41,104],[88,123]]) {
    for (const [dx,dy,color] of [[-4,-4,'#70865b'],[0,-7,'#617f5b'],[3,-5,'#d0ce8f']]) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.55;
      ctx.beginPath();
      ctx.moveTo(x,y);
      ctx.quadraticCurveTo(x+dx*.3,y+dy*.7,x+dx,y+dy);
      ctx.stroke();
    }
  }
}

function silt(ctx) {
  ctx.lineCap = 'round';
  for (const [x,y,size] of [[6,12,16],[62,27,9],[105,46,16],[26,76,11],[79,94,14],[113,120,8]]) {
    ctx.beginPath();
    ctx.strokeStyle = '#7f806459';
    ctx.lineWidth = 1.2;
    ctx.moveTo(x,y);
    ctx.quadraticCurveTo(x+size*.52,y+3,x+size,y-.5);
    ctx.stroke();
  }
}

export function addRiverbanks(map, source, anchor) {
  const property = ['get','habitat'];
  const fade = (a,b,v) => ['interpolate',['linear'],['zoom'],a,0,b,['*',v,['get','alpha']]];
  function fill(name, kind, paint, minzoom) {
    map.addLayer({id:source+'-'+name,type:'fill',source,minzoom,filter:['==',['get','k'],kind],paint},anchor);
  }
  const plant = source+'-mangrove-leaves', reed = source+'-rushes', sand = source+'-silt-marks';
  bankPattern(map, plant, mangrove);
  bankPattern(map, reed, rushes);
  bankPattern(map, sand, silt);
  fill('bank-reflection','bank-reflection',{'fill-color':'#538278','fill-opacity':fade(12,15,.60)},12);
  fill('bank-mud','bank-mud',{'fill-color':['match',property,'tidalflat','#c9c3a5','#b7af91'],'fill-opacity':fade(11.75,14,.95)},11.75);
  fill('bank-silt','bank-mud',{'fill-pattern':sand,'fill-opacity':fade(14,16.75,.85)},14);
  fill('bank-marsh','bank-marsh',{'fill-color':['match',property,'mangrove','#769d75','reedbed','#a7ae72','#a6b883'],
    'fill-opacity':fade(11.75,14,.96)},11.75);
  fill('bank-foliage','bank-marsh',{'fill-pattern':['match',property,'mangrove',plant,reed],'fill-opacity':fade(13.75,15.75,.84)},13.75);
  fill('bridge-reflection','bridge-reflection',{'fill-color':'#436d73','fill-opacity':fade(13,15.3,.50)},13);
}
