// Execute the original Pocket City wall painter, then transport its paint to surveyed faces.
// No invented building geometry or heights; facade details remain illustration.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),crypto=require('node:crypto');
const {createCanvas,Canvas,Path2D}=require('@napi-rs/canvas');
const kit=path.join(__dirname,'kit');
const {scene,city}=JSON.parse(fs.readFileSync(path.join(__dirname,'input.json')));
const names=['projection','models','streetFigures','city','foliage','painter'];
const parts=JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(kit,'source.json.gz'))));
const source=[parts.projection,parts.models,parts.streetFigures,`const SCENE=${JSON.stringify(scene)},CITY=${JSON.stringify(city)};`,parts.city,parts.foliage,parts.painter].join('\n');
const engine=new Function('self','OffscreenCanvas','Path2D',source+`\nUPX=.24;SEASON={};return {facades,paint:paintSingaporeElevation,style:makeStyle};`)({PHONE_PROFILE:false,PAGE_SEARCH:''},Canvas,Path2D);
const W=256,H=512,atlas=createCanvas(W*4,H*3),ctx=atlas.getContext('2d'),rows=[];
for(let i=0;i<12;i++){
  const family=['office','apartment','glass'][Math.floor(i/4)],tall=family==='glass',seed=i%4,unitFloor=tall?3.6:3.2,unitBay=tall?3.1:2.4,L=unitBay*4,wallH=unitFloor*6;
  const image=createCanvas(W,H),g=image.getContext('2d');g.scale(W/L,H/wallH);
  // F.transform normally projects the wall to a software camera. The atlas is already wall-local.
  const wallContext=new Proxy(g,{get:(o,k)=>k==='transform'?()=>{}:typeof o[k]==='function'?o[k].bind(o):o[k],set:(o,k,v)=>(o[k]=v,true)});
  const st=engine.style({...city.styles.default,...(tall?city.styles.rules[0].set:{}),facade:family,floor:unitFloor,bay:unitBay});
  const face={start:[0,0],along:[1,0],n:[0,-1,0],len:L,z:0,h:wallH,st,cut:false,shop:false,seed,body:st.wall[seed%st.wall.length]};
  g.fillStyle=face.body;g.fillRect(0,0,L,wallH);
  const id=engine.facades.push(face)-1;engine.paint(wallContext,id);
  ctx.drawImage(image,(i%4)*W,Math.floor(i/4)*H);
  rows.push({id:i,family:st.facade,seed,metres:[L,wallH],floor:unitFloor,bay:unitBay});
}
const out=path.resolve(__dirname,'../../assets/pocket-survey');fs.mkdirSync(out,{recursive:true});
const bytes=atlas.toBuffer('image/png');fs.writeFileSync(path.join(out,'facades.png'),bytes);
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
fs.writeFileSync(path.join(out,'facades.json'),JSON.stringify({source:'Pocket City original paintSingaporeElevation',licence:'MIT',sourceFiles:Object.fromEntries(names.map(n=>[n,hash(parts[n])])),citySHA256:hash(JSON.stringify(city)),imageSHA256:hash(bytes),size:[W*4,H*3],rows,geometry:'Municipal LOD1_2025 geometry unchanged',illustrative:['window frame pattern','floor rhythm','facade colours']},null,2)+'\n');
console.log(JSON.stringify({bytes:bytes.length,rows:rows.length,output:out}));
