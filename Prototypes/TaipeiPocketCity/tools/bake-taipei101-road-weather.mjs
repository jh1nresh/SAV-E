// Offline authoring tool. Use @napi-rs/canvas with the frozen original scene.
import vm from 'node:vm';
import {readFileSync,writeFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {asphaltColors} from '../taipei-asphalt.js';
const {createCanvas,Path2D}=createRequire(import.meta.url)('@napi-rs/canvas');
const html=gunzipSync(readFileSync(new URL('./fixtures/taipei101-pocket-city.html.gz',import.meta.url))).toString(),parts=Object.fromEntries([...html.matchAll(/<script type="text\/plain" id="([^"]+)">([\s\S]*?)<\/script>/g)].map(m=>[m[1],m[2]]));
const script=['projection','models','streetFigures','data','landmarks','city','foliage','painter'].map(k=>parts[k]).join('\n');
for(const [mode,color] of Object.entries(asphaltColors)){
  const W=2048, canvas=createCanvas(W,W);
  const ctx=vm.createContext({Path2D,OffscreenCanvas:class {constructor(w,h){return createCanvas(w,h)}},canvas,self:{PHONE_PROFILE:false,PAGE_SEARCH:''},URLSearchParams,console});
  vm.runInContext(script+`
  setSeason('warm');YAW=-90;PITCH=90;CAM_R=[1,0,0];CAM_U=[0,1,0];CAM_V=[0,0,1];CAM_D=[0,-1,0];
  OX=OY=0;RC=[0,0];RCZ=0;const ppm=canvas.width/SCENE.meta.size;
  UPX=CAM_K/ppm; INK_K=.83*UPX;paintScale=1/UPX;
  const ctx=canvas.getContext('2d');ctx.setTransform(paintScale,0,0,paintScale,canvas.width/2,canvas.height/2);
  ctx.lineCap=ctx.lineJoin='round';
  const groundArtwork=cityGround().replaceAll('fill="'+ROAD+'"','fill="${color}"');
  // Cast shadows are live map geometry; render the kit's pigment, paving joints, kerbs and markings.
  const noShadows=groundArtwork.replace(/<g opacity="\\.45">[\\s\\S]*?<\\/g>/,'');
  paintOps(ctx,compileInk(noShadows));
  `,ctx);
  // Feather the outer two metres into the continuous city, retaining alignment of every painted feature.
  const drawing=canvas.getContext('2d'),pixels=drawing.getImageData(0,0,W,W);
  for(let y=0;y<W;y++)for(let x=0;x<W;x++){
    const edge=Math.min(x,y,W-1-x,W-1-y)/(W/200*2);
    if(edge<1)pixels.data[(y*W+x)*4+3]=Math.round(255*edge);
  }
  drawing.putImageData(pixels,0,0);
  const png=canvas.toBuffer('image/png');
  if(mode==='day'){
    assert.ok(png.equals(readFileSync(new URL('../assets/taipei101-single-ground.png',import.meta.url))),
      'The frozen daylight painting must reproduce exactly before deriving its wet asphalt.');
  }else{
    writeFileSync(new URL('../assets/taipei101-ground-'+mode+'.png',import.meta.url),png);
  }
}
