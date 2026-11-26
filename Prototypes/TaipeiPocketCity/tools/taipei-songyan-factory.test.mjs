import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {gzipSync,gunzipSync} from 'node:zlib';
import {SurveyLayer} from '../survey-layer.js';
import {songyanFactory as site,legacyFactoryVertices} from '../taipei-songyan-factory.js';

const factory=await readFile(site.mesh);
const waterfrontURL=new URL('../assets/taipei-songyan-waterfront.bin.gz',import.meta.url);
const waterfront=await readFile(waterfrontURL);
const oldTotal=91908;
const oldPrefix=29766;
const triangles=gzipSync(Buffer.alloc(3*24));

test('four registered Songyan buildings retain the authored vertices, colors and surveyed grounds',()=>{
  const mesh=gunzipSync(factory);
  assert.equal(mesh.length,30822*24);
  assert.equal(site.verts,30822);
  // Frozen registered output from the accepted scene. The four ranges below
  // independently pin the building order, elevations and vertex count.
  assert.equal(createHash('sha256').update(mesh).digest('hex'),'541c8203cacd663f879c0253439d00879838b1c513ca76f6cdcd740440dbbb71');
  const groups=[[23802,5.39,11.649],[3384,5.51026,9.53039],[2382,7.17971,21.5],[1254,5.51026,6.13954]];
  let offset=0;
  for(const [count,base,height] of groups){
    let min=Infinity,max=-Infinity;
    for(let n=0;n<count;n++,offset+=24){
      const [x,y,z,ground,h,ink]=[0,4,8,12,16,20].map(i=>mesh.readFloatLE(offset+i));
      assert.ok(Number.isFinite(x+y+z+ground+h+ink));
      assert.ok(Math.abs(base-ground)<.001&&Math.abs(h-height)<.001&&Number.isInteger(ink));
      const lon=(site.mx+x*site.m)*360-180;
      const lat=Math.atan(Math.sinh(Math.PI*(1-2*(site.my-y*site.m))))*180/Math.PI;
      const [w,s,e,north]=site.box;
      assert.ok(lon>=w-1e-8&&lon<=e+1e-8&&lat>=s-1e-8&&lat<=north+1e-8);
      min=Math.min(min,z);max=Math.max(max,z);
    }
    assert.ok(Math.abs(min-base)<.001&&Math.abs(max-base-height)<.001);
  }
  assert.equal(offset,mesh.length);
});

test('the waterfront slice begins after exactly the four legacy building parts',{skip:!process.env.POCKET_TAIPEI_DATA},async()=>{
  const old=gunzipSync(await readFile(join(process.env.POCKET_TAIPEI_DATA,'city-streets/landmark/songyan-v5.bin.gz')));
  const adjusted=gunzipSync(waterfront);
  assert.equal(old.length,oldTotal*24);
  assert.equal(adjusted.length,old.length);
  assert.equal(legacyFactoryVertices,oldPrefix);
  const end=oldPrefix*24;
  assert.equal(createHash('sha256').update(old.subarray(0,end)).digest('hex'),'14e6ac7ce398ffec08c28ea1d3482f29102939fdcddcdc9dc19c291f04e6d695');
  assert.deepEqual(adjusted.subarray(0,end),old.subarray(0,end));
  for(let i=end;i<old.length;i+=24){
    assert.ok(old.subarray(i,i+8).equals(adjusted.subarray(i,i+8)),'nature vertex XY or draw order changed');
    assert.ok(old.subarray(i+12,i+24).equals(adjusted.subarray(i+12,i+24)),'nature material or metadata changed');
    assert.ok(Number.isFinite(adjusted.readFloatLE(i+8)));
  }
});

function scene(t){
  const anchor={mx:site.mx,my:site.my,m:site.m,box:site.box,lngLat:site.center,verts:3};
  const tile=id=>({...anchor,id});
  const index={levels:{1000:[tile('306_2770'),tile('adjacent')],200:[tile('1532_13853'),tile('1533_13853'),tile('adjacent')]}};
  const legacy={...anchor,id:'songyan',file:'songyan-v5',verts:oldTotal,mesh:waterfrontURL,
    matches:[[5.39,11.1502,.815],[5.5103,9.5296,.865],[7.1797,13.2805,.115],[7.1797,4.7404,.005]],
    limit:[-260,-82,5,72]};
  const layer=new SurveyLayer(index,()=>{},null,true,[],null,null,true,[site]);
  const requests=[],draws=[];
  let completeFactory,repaint,zoom=17.8,mask=0;
  const pendingFactory=new Promise(resolve=>{completeFactory=resolve;});
  t.mock.method(globalThis,'fetch',async url=>{
    requests.push(url.pathname);
    if(url.href===site.mesh.href)return pendingFactory;
    if(url.href===waterfrontURL.href)return new Response(waterfront);
    if(url.pathname.includes('/200/')||url.pathname.includes('/1000/'))return new Response(triangles);
    throw Error('Unexpected asset '+url.pathname);
  });
  const noop=()=>{};
  const gl=new Proxy({
    getUniformLocation:(_,key)=>key,getShaderParameter:()=>true,getProgramParameter:()=>true,
    uniform3f:(key,x,y,z)=>{if(key==='u_factoryTile')mask=z;},
    drawArrays:(_,first,count)=>draws.push([first,count,mask>0]),
  },{get:(obj,key)=>obj[key]??noop});
  const map={getZoom:()=>zoom,triggerRepaint:()=>repaint?.(),
    getCenter:()=>({lng:site.center[0],lat:site.center[1]}),
    getBounds:()=>({toArray:()=>[site.box.slice(0,2),site.box.slice(2)]})};
  layer.onAdd(map,gl);
  layer.setSongyan(legacy);
  t.after(()=>layer.onRemove());
  async function frame(held=0){
    // A completed upload (including failure) always triggers a repaint. Wait
    // for that event instead of racing a fixed number of event-loop ticks.
    while(true){
      const painted=new Promise(resolve=>{repaint=resolve;});
      draws.length=0;
      layer.render(gl,{defaultProjectionData:{mainMatrix:new Float32Array(16)}});
      if(layer.diagnostics.live===held)return draws.slice();
      await painted;
    }
  }
  return {layer,frame,completeFactory,requests,setZoom:value=>{zoom=value;}};
}

test('replacement is atomic, preserves the nature suffix and targets the correct tiles at both LODs',async t=>{
  const s=scene(t);
  const unmasked=[0,3,false],masked=[0,3,true];
  assert.deepEqual(await s.frame(1),[unmasked,unmasked,unmasked,[0,oldTotal,false]]);
  assert.ok(s.requests.some(url=>url.endsWith('/taipei-songyan-factory.bin.gz')));
  assert.equal(s.layer.factoryDrawn,false);
  s.completeFactory(new Response(factory));
  assert.deepEqual(await s.frame(),[masked,masked,unmasked,[oldPrefix,oldTotal-oldPrefix,false],[0,site.verts,false]]);
  assert.equal(s.layer.diagnostics.mode,200);
  s.setZoom(15.5);
  assert.deepEqual(await s.frame(),[masked,unmasked,[0,site.verts,false]]);
  assert.equal(s.layer.diagnostics.mode,1000);
  assert.equal(s.layer.diagnostics.failed,0);
});

for(const failure of ['is missing','has the wrong vertex count']){
  test('when the factory mesh '+failure+', the full original art and survey stay visible',async t=>{
    const s=scene(t);
    const unmasked=[0,3,false];
    await s.frame(1);
    t.mock.method(console,'warn',()=>{});
    s.completeFactory(failure==='is missing'?new Response(null,{status:404}):new Response(triangles));
    assert.deepEqual(await s.frame(),[unmasked,unmasked,unmasked,[0,oldTotal,false]]);
    assert.equal(s.layer.factoryDrawn,false);
    assert.equal(s.layer.diagnostics.failed,1);
    s.setZoom(15.5);
    assert.deepEqual(await s.frame(),[unmasked,unmasked]);
    assert.equal(s.layer.diagnostics.mode,1000);
  });
}
