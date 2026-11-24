import {MercatorCoordinate} from './assets/maplibre-gl.mjs';
import {program,transform} from './survey-layer.js';
import {buildFuxingFront} from './fuxing-fronts.js';

const minZoom=17.55;
const layerId='city-shopfronts';
const vertex=`#version 300 es
layout(location=0) in vec3 position;
layout(location=1) in vec3 color;
layout(location=2) in vec2 signUV;
layout(location=3) in vec3 center;
layout(location=4) in vec2 tangent;
uniform mat4 matrix;
out vec3 lit;
out vec2 uv;
void main(){
  vec4 origin=matrix*vec4(center,1.0);
  vec4 side=matrix*vec4(center+vec3(tangent,0.0),1.0);
  vec4 top=matrix*vec4(center+vec3(0.0,0.0,1.0),1.0);
  // Screen-space winding also hides the side walls and canopies of a back-facing shop.
  bool front=determinant(mat3(origin.xyw,side.xyw,top.xyw))>0.0;
  gl_Position=front?matrix*vec4(position,1.0):vec4(2.0,2.0,2.0,1.0);
  lit=color;
  uv=signUV;
}`;
const fragment=`#version 300 es
precision highp float;
in vec3 lit;
in vec2 uv;
uniform sampler2D signTexture;
uniform bool showNames;
out vec4 outColor;
void main(){
  if(uv.x>=0.0 && (!showNames || texture(signTexture,uv).a<0.62)) discard;
  outColor=vec4(lit,1.0);
}`;

const drawing={
  meal: ['#a75f48','#6d473d','#8a7259','#7b998f','awning'],
  cafe: ['#547f74','#45655e','#856f57','#85a39a','awning'],
  grocery: ['#927642','#665438','#ad8c68','#82958c','shelves'],
  apparel: ['#a17080','#654e63','#ab897e','#92a29f','clothes'],
  health: ['#597e82','#426166','#a9a396','#85a49e','cross'],
  craft: ['#6c7796','#4f596f','#8c7964','#7e9298','books'],
  retail: ['#786c58','#5c5a52','#a28d7c','#829991','plain'],
};
const categories={
  inspection_store:['餐飲店家','meal'],restaurant:['餐廳','meal'],fast_food:['速食','meal'],food_court:['美食廣場','meal'],
  cafe:['咖啡店','cafe'],ice_cream:['冰品店','cafe'],bakery:['烘焙店','cafe'],
  bar:['酒吧','meal'],pub:['酒館','meal'],tea:['茶店','cafe'],
  convenience:['便利商店','grocery'],supermarket:['超級市場','grocery'],grocery:['雜貨店','grocery'],
  greengrocer:['蔬果店','grocery'],butcher:['肉品店','grocery'],seafood:['海產店','grocery'],
  confectionery:['糖果甜點店','grocery'],general:['商店','grocery'],mall:['商場','grocery'],
  clothes:['服飾店','apparel'],shoes:['鞋店','apparel'],boutique:['精品店','apparel'],
  cosmetics:['美妝店','apparel'],hairdresser:['髮廊','apparel'],beauty:['美容店','apparel'],
  pharmacy:['藥局','health'],chemist:['藥妝店','health'],optician:['眼鏡店','health'],
  books:['書店','craft'],stationery:['文具店','craft'],gift:['禮品店','craft'],
  department_store:['百貨公司','grocery'],florist:['花店','grocery'],bicycle:['自行車店','craft'],
  hardware:['五金行','craft'],electronics:['電子用品店','craft'],jewelry:['珠寶店','apparel'],
};
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
const colored=Object.fromEntries(Object.entries(drawing).map(([key,values])=>{
  const [fascia,frame,wall,glass]=values.slice(0,4).map(rgb);
  return [key,{fascia,frame,wall,glass,detail:values[4]}];
}));
const cream=rgb('#f3dfb6'), stone=rgb('#b5a597'), highlights=rgb('#a6bbb1');
const stock=['#c58866','#d7b475','#659185','#9c7890','#8099ad'].map(rgb);
const clamp=(value,min,max)=>Math.max(min,Math.min(max,value));
const placeGroup=category=>Object.hasOwn(categories,category)?categories[category]:['店家','retail'];

function shopRow(row){
  return row && typeof row.id==='string' && row.id && typeof row.name==='string' && row.name.trim() &&
    Array.isArray(row.center) && row.center.length===2 && row.center.every(Number.isFinite) &&
    Number.isFinite(row.angle) && Number.isFinite(row.width) && row.width>=1.5;
}

function cardFor(row){
  const match=row.id.match(/(?:^|[/-])(node|way|relation)[/-](\d+)$/);
  const rawUrl=row.url??row.source?.url;
  const url=typeof rawUrl==='string'&&rawUrl.startsWith('https://')?rawUrl
    :match?`https://www.openstreetmap.org/${match[1]}/${match[2]}`:undefined;
  const source=row.source?.label??row.source?.name??(typeof row.source==='string'?row.source:undefined)
    ??(match?'OpenStreetMap':undefined);
  const categoryLabel=typeof row.categoryLabel==='string'&&row.categoryLabel.trim()||placeGroup(row.category)[0];
  return {id:row.id,name:row.name,categoryLabel,
    kind:'shopfront',detail:'店面位置與外觀為示意',source,url};
}

function nameAtlas(map, count, maxTexture){
  const canvas=map.getCanvas().ownerDocument.createElement('canvas');
  const width=192,height=32,cols=Math.min(4,Math.floor(maxTexture/width));
  canvas.width=cols*width;
  canvas.height=Math.min(maxTexture,Math.max(height,Math.ceil(count/cols)*height));
  const ctx=canvas.getContext('2d');
  if(!ctx)return {canvas,write:()=>null};
  ctx.fillStyle='#fff';
  ctx.font='bold 23px system-ui, sans-serif';
  ctx.textAlign='center';
  ctx.textBaseline='middle';
  let index=0;
  return {canvas,write(text,fitSign=false){
    const left=(index%cols)*width,top=Math.floor(index++/cols)*height;
    if(top+height>canvas.height)return null;
    const name=text.trim().slice(0,40);
    ctx.font=fitSign?'600 26px "Songti TC", serif':'bold 23px system-ui, sans-serif';
    ctx.fillText(name,left+width/2,top+height/2,width-16);
    const inset=fitSign?Math.max(1,(width-Math.min(ctx.measureText(name).width,width-16))/2-8):1;
    return [(left+inset)/canvas.width,(top+1)/canvas.height,
      (left+width-inset)/canvas.width,(top+height-1)/canvas.height];
  }};
}

function buildShop(vertices,row,center,scale,atlas,fuxing=false){
  const [x,y,z]=center;
  const angle=row.angle*Math.PI/180, nx=Math.cos(angle),ny=Math.sin(angle);
  const tx=-ny,ty=nx;
  const half=clamp(row.width,1.5,9)*.5, top=3.25, offset=.14;
  const type=placeGroup(row.category)[1];
  const paint=colored[type];
  const seed=Array.from(row.id).reduce((value,c)=>(value*31+c.charCodeAt(0))>>>0,0);
  const timbers=[rgb('#846b4d'),rgb('#996d4d'),rgb('#74624e')];
  const trim=timbers[seed%timbers.length];
  const first=vertices.length/13;
  function point(s,h,d){return [x+tx*s+nx*(offset+d),y+ty*s+ny*(offset+d),z+h*scale];}
  function quad(points,color,texture){
    const uv=texture?[[texture[0],texture[3]],[texture[2],texture[3]],
      [texture[2],texture[1]],[texture[0],texture[1]]]:null;
    for(const i of [0,1,2,0,2,3]){
      vertices.push(...points[i],...color,...(uv?.[i]??[-1,-1]),...center,tx,ty);
    }
  }
  function corners(a,b,low,high,depth){
    return [point(a,low,depth),point(b,low,depth),point(b,high,depth),point(a,high,depth)];
  }
  function panel(a,b,low,high,depth,color,texture){
    if(b>a&&high>low)quad(corners(a,b,low,high,depth),color,texture);
  }
  function sign(a,b,low,high,depth,color){
    const nameUV=atlas.write(row.name,true);
    if(nameUV)panel(a,b,low,high,depth,color,nameUV);
  }
  if(fuxing && buildFuxingFront(row,{half,top,point,quad,panel,rgb,sign})){
    return {row,first,count:vertices.length/13-first,hit:corners(-half,half,.08,top,.055)};
  }
  panel(-half,half,.08,top,0,paint.wall);
  panel(-half,half,.08,.35,.018,stone);
  panel(-half,half,top-.57,top-.045,.036,paint.fascia);
  const nameUV=atlas.write(row.name);
  if(nameUV)panel(-half+.10,half-.10,top-.52,top-.10,.057,cream,nameUV);
  // A narrow cornice, a threshold and end posts give the one-storey bay a readable edge.
  panel(-half,half,.07,.14,.14,stone);
  for(const side of [-half+.02,half-.12])panel(side,side+.10,.15,2.70,.093,trim);
  quad([point(-half,top,.04),point(half,top,.04),point(half,top,.24),point(-half,top,.24)],cream);
  panel(-half,half,top-.07,top,.24,paint.frame);
  const door=Math.min(.61,half*.36);
  panel(-door-.085,door+.085,.12,2.67,.025,paint.frame);
  panel(-door,door,.22,2.56,.041,paint.glass);
  panel(-door+.06,door-.06,1.45,2.44,.049,highlights);
  panel(door-.18,door-.11,1.07,1.40,.053,cream);
  for(const [start,end] of [[-half+.10,-door-.13],[door+.13,half-.10]]){
    if(end-start<.25)continue;
    panel(start,end,.44,2.60,.02,paint.frame);
    panel(start+.073,end-.073,.53,2.51,.038,paint.glass);
    panel(start+.10,end-.10,2.23,2.40,.042,highlights);
    if(['books','shelves','awning'].includes(paint.detail)){
      const items=paint.detail==='awning'?2:4;
      const step=(end-start-.18)/items;
      for(const shelf of (paint.detail==='awning'?[.7]:[.7,1.26])){
        panel(start+.09,end-.09,shelf,shelf+.053,.055,cream);
        for(let i=0;i<items;i++){
          const left=start+.10+i*step;
          panel(left,left+step*.72,shelf+.058,shelf+.22+.055*(i%3),.052,stock[i]);
        }
      }
    }else if(paint.detail==='clothes'){
      const center=(start+end)/2, width=(end-start)*.26;
      panel(start+.10,end-.10,1.94,1.99,.051,cream);
      panel(center-width,center+width,.85,1.83,.054,stock[3]);
      panel(center-width*1.38,center+width*1.38,1.49,1.77,.054,stock[3]);
    }else if(paint.detail==='cross'){
      const center=(start+end)/2, width=Math.min(.22,(end-start)*.22);
      panel(center-width*.32,center+width*.32,1.09,1.69,.052,cream);
      panel(center-width,center+width,1.29,1.49,.053,cream);
    }
  }
  if(type==='craft' && row.category==='books' && half>1.5){
    // Low angled book display with a timber lip outside the window.
    const lo=-half+.20,hi=-door-.17;
    const shelf=(s,h)=>point(s,h,.31+(1.08-h)*.31);
    quad([shelf(lo,.55),shelf(hi,.55),shelf(hi,1.08),shelf(lo,1.08)],trim);
    for(let i=0;i<5;i++){
      const start=lo+(hi-lo)*(i+.1)/5,end=lo+(hi-lo)*(i+.91)/5;
      quad([shelf(start,.59),shelf(end,.59),shelf(end,.99-.025*(i%2)),shelf(start,.99-.025*(i%2))],stock[(i+seed)%stock.length]);
    }
    panel(lo,hi,.53,.60,.49,trim);
  }
  if(paint.detail==='awning' && half>=1.1){
    const left=-half+.065,right=half-.065,depth=.64;
    const canopy=(a,b,color,lift=0)=>{
      quad([point(a,2.60+lift,depth),point(b,2.60+lift,depth),
        point(b,2.82+lift,.035),point(a,2.82+lift,.035)],color);
    };
    canopy(left,right,paint.fascia);
    const stripe=type==='cafe'?.38:.61;
    if(seed%3 || type==='cafe'){
      for(let i=left+.12;i<right-.1;i+=stripe)canopy(i,Math.min(right,i+stripe*.34),cream,.012);
    }
    panel(left,right,2.49,2.60,depth,paint.fascia);
  }
  return {row,first,count:vertices.length/13-first,hit:corners(-half,half,.08,top,.055)};
}

function projectedFace(shop,matrix,width,height){
  const corners=shop.hit.map(([x,y,z])=>{
    const component=i=>matrix[i]*x+matrix[i+4]*y+matrix[i+8]*z+matrix[i+12];
    const w=component(3);
    return w>0?[(1+component(0)/w)*width/2,(1-component(1)/w)*height/2]:null;
  });
  if(!corners.every(Boolean))return null;
  const [[ax,ay],[bx,by],[cx,cy]]=corners;
  return (bx-ax)*(cy-ay)-(by-ay)*(cx-ax)<0?corners:null;
}

function hitShop(shop,matrix,point,width,height){
  const corners=projectedFace(shop,matrix,width,height);
  if(!corners)return false;
  return corners.every(([x,y],index)=>{
    const [nx,ny]=corners[(index+1)%4];
    return (nx-x)*(point.y-y)-(ny-y)*(point.x-x)<0;
  });
}

async function readPack(id, signal){
  const url=new URL(`./data/city170-frontages/${id}.json.gz?v=survey-health`,import.meta.url);
  const response=await fetch(url,{signal});
  if(!response.ok||!response.body)throw Error(`Shopfront pack returned ${response.status}`);
  return new Response(response.body.pipeThrough(new DecompressionStream('gzip'))).json();
}

export function addCityShopfronts(map,openPlace,firstLabel,updateBuilt=()=>{},surveyTiles,onPickMiss=()=>{}){
  const cache=new Map(),loading=new Map(),failures=new Map();
  const matrix=new Float32Array(16);
  let active=new Set(),enabled=true,removed=false,dirty=true;
  let anchor,window,shown=[],vertices=0,textureLimit,tap,queries=[];
  let lastPick=null,walls,retry,showNames=true,fuxingEnabled=true,namesLocation;
  let gl,buffer,vao,pipeline,texture,matrixLocation,signLocation;

  function unloadQueries(){
    for(const {query} of queries)gl.deleteQuery(query);
    queries=[];
    tap=null;
  }
  function kick(){
    clearTimeout(retry);
    if(!enabled||removed||map.getZoom()<minZoom)return;
    const blocked=[...active].map(id=>failures.get(id)).filter(t=>t>Date.now());
    if(blocked.length)retry=setTimeout(kick,Math.max(1,Math.min(...blocked)-Date.now()+5));
    for(const id of active){
      if(loading.size>=6)break;
      if(cache.has(id)||loading.has(id)||(failures.get(id)??0)>Date.now())continue;
      const controller=new AbortController();
      loading.set(id,controller);
      readPack(id,controller.signal).then(payload=>{
        if(removed||controller.signal.aborted)return;
        if(!Array.isArray(payload))throw Error('Invalid city shopfront pack');
        cache.set(id,payload.filter(shopRow));
        failures.delete(id);
        for(const key of cache.keys()){
          if(cache.size<=32)break;
          if(!active.has(key))cache.delete(key);
        }
        if(active.has(id))dirty=true;
      }).catch(error=>{
        if(removed||controller.signal.aborted)return;
        failures.set(id,Date.now()+4500);
        console.warn('City shopfronts',id,error.message);
      }).finally(()=>{
        loading.delete(id);
        if(!removed){kick();map.triggerRepaint();}
      });
    }
  }
  const terrain=event=>{if(event.sourceId==='dem')dirty=true;};
  const cameraMove=()=>{tap=null;if(queries.length)unloadQueries();};
  const click=event=>{
    unloadQueries();
    if(event.defaultPrevented)return;
    if(!enabled||map.getZoom()<minZoom||!shown.length){onPickMiss(event.point);return;}
    const {clientWidth,clientHeight}=map.getCanvas();
    if(!shown.some(shop=>hitShop(shop,matrix,event.point,clientWidth,clientHeight))){
      lastPick={tested:0,visible:0,id:null};
      onPickMiss(event.point);return;
    }
    tap={point:event.point,deadline:performance.now()+750};
    map.triggerRepaint();
  };

  function assemble(bounds){
    const [w,s,e,n]=bounds, padX=(e-w)*.19,padY=(n-s)*.19;
    window=[w-padX,s-padY,e+padX,n+padY];
    const [west,south,east,north]=window;
    const data=new Map();
    for(const id of active){
      for(const row of cache.get(id)??[]){
        if(!walls?.has(row.surveyTile))continue;
        const [lon,lat]=row.center;
        if(lon>=west&&lon<=east&&lat>=south&&lat<=north)data.set(row.id,row);
      }
    }
    const at=MercatorCoordinate.fromLngLat(map.getCenter());
    anchor={mx:at.x,my:at.y,m:at.meterInMercatorCoordinateUnits()};
    const atlas=nameAtlas(map,data.size,textureLimit);
    const out=[];
    shown=[];
    for(const row of data.values()){
      const ground=Number.isFinite(row.groundZ)?row.groundZ:map.queryTerrainElevation(row.center);
      if(!Number.isFinite(ground))continue;
      const z=Number.isFinite(row.surveyBase)?Math.max(ground,row.surveyBase):ground;
      const height=Number.isFinite(row.surveyTop)?row.surveyTop-z:3.38;
      if(height<1.9)continue;
      const world=MercatorCoordinate.fromLngLat(row.center);
      const origin=[(world.x-anchor.mx)/anchor.m,(anchor.my-world.y)/anchor.m,z];
      shown.push(buildShop(out,row,origin,Math.min(1,(height-.13)/3.25),atlas,fuxingEnabled));
    }
    gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(out),gl.STATIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER,null);
    const flip=gl.getParameter(gl.UNPACK_FLIP_Y_WEBGL);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,atlas.canvas);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,flip);
    updateBuilt(shown.map(shop=>shop.row.id));
    vertices=out.length/13;
    dirty=false;
  }

  function missTap(){
    const point=tap?.point;
    unloadQueries();
    if(point)onPickMiss(point);
  }
  function resolveTap(){
    if(!queries.length)return;
    if(performance.now()>=tap.deadline){missTap();return;}
    if(queries.some(({query})=>!gl.getQueryParameter(query,gl.QUERY_RESULT_AVAILABLE))){
      map.triggerRepaint();
      return;
    }
    const visible=queries.filter(({query})=>gl.getQueryParameter(query,gl.QUERY_RESULT));
    const winner=visible[0];
    lastPick={tested:queries.length,visible:visible.length,id:winner?.shop.row.id??null};
    if(!winner){missTap();return;}
    unloadQueries();
    openPlace(cardFor(winner.shop.row),winner.shop.row);
  }

  function depthPick(){
    const {clientWidth,clientHeight}=map.getCanvas();
    const picked=shown.filter(shop=>hitShop(shop,matrix,tap.point,clientWidth,clientHeight));
    if(!picked.length){missTap();return;}
    const [left,bottom,width,height]=gl.getParameter(gl.VIEWPORT);
    const x=left+Math.floor(tap.point.x*width/clientWidth);
    const y=bottom+height-1-Math.floor(tap.point.y*height/clientHeight);
    const scissor=gl.getParameter(gl.SCISSOR_BOX), hadScissor=gl.isEnabled(gl.SCISSOR_TEST);
    const color=gl.getParameter(gl.COLOR_WRITEMASK);
    gl.enable(gl.SCISSOR_TEST);
    gl.scissor(x,y,1,1);
    gl.colorMask(false,false,false,false);
    gl.depthMask(false);
    for(const shop of picked){
      const query=gl.createQuery();
      if(!query)continue;
      gl.beginQuery(gl.ANY_SAMPLES_PASSED,query);
      gl.drawArrays(gl.TRIANGLES,shop.first,shop.count);
      gl.endQuery(gl.ANY_SAMPLES_PASSED);
      queries.push({query,shop});
    }
    gl.colorMask(...color);
    gl.depthMask(true);
    gl.scissor(...scissor);
    if(!hadScissor)gl.disable(gl.SCISSOR_TEST);
    if(queries.length)map.triggerRepaint();
    else missTap();
  }

  map.addLayer({
    id:layerId,type:'custom',renderingMode:'3d',
    onAdd(_map,glContext){
      gl=glContext;
      pipeline=program(gl,vertex,fragment);
      matrixLocation=gl.getUniformLocation(pipeline,'matrix');
      namesLocation=gl.getUniformLocation(pipeline,'showNames');
      signLocation=gl.getUniformLocation(pipeline,'signTexture');
      texture=gl.createTexture();
      textureLimit=gl.getParameter(gl.MAX_TEXTURE_SIZE);
      buffer=gl.createBuffer();
      vao=gl.createVertexArray();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
      for(const [index,size,offset] of [[0,3,0],[1,3,3],[2,2,6],[3,3,8],[4,2,11]]){
        gl.enableVertexAttribArray(index);
        gl.vertexAttribPointer(index,size,gl.FLOAT,false,52,offset*4);
      }
      gl.bindVertexArray(null);
      gl.bindBuffer(gl.ARRAY_BUFFER,null);
      map.on('sourcedata',terrain);
      map.on('moveend',kick);
      map.on('move',cameraMove);
      map.on('click',click);
    },
    render(_gl,options){
      if(!enabled||map.getZoom()<minZoom||!active.size){
        if(shown.length){shown=[];updateBuilt([]);dirty=true;}
        unloadQueries();
        return;
      }
      const nextWalls=surveyTiles();
      if(walls!==nextWalls){walls=nextWalls;dirty=true;}
      resolveTap();
      const bounds=map.getBounds().toArray().flat();
      const [w,s,e,n]=bounds;
      const previousTextureUnit=gl.getParameter(gl.ACTIVE_TEXTURE);
      gl.activeTexture(gl.TEXTURE0);
      const previousTexture=gl.getParameter(gl.TEXTURE_BINDING_2D);
      gl.bindTexture(gl.TEXTURE_2D,texture);
      if(dirty||!window||w<window[0]||s<window[1]||e>window[2]||n>window[3]){
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
        assemble(bounds);
      }
      if(vertices){
        transform(options.defaultProjectionData.mainMatrix,anchor,matrix);
        gl.useProgram(pipeline);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.depthMask(true);
        gl.disable(gl.CULL_FACE);
        gl.disable(gl.BLEND);
        gl.uniformMatrix4fv(matrixLocation,false,matrix);
        gl.uniform1i(signLocation,0);
        gl.uniform1i(namesLocation,showNames?1:0);
        gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES,0,vertices);
        if(tap&&!queries.length)depthPick();
        gl.bindVertexArray(null);
      }
      gl.bindTexture(gl.TEXTURE_2D,previousTexture);
      gl.activeTexture(previousTextureUnit);
    },
    onRemove(){
      removed=true;clearTimeout(retry);
      unloadQueries();
      for(const request of loading.values())request.abort();
      map.off('sourcedata',terrain);
      map.off('moveend',kick);
      map.off('move',cameraMove);
      map.off('click',click);
      gl.deleteBuffer(buffer);
      gl.deleteVertexArray(vao);
      gl.deleteTexture(texture);
      gl.deleteProgram(pipeline);
    },
  },firstLabel);
  return {
    setNames(value){showNames=value;map.triggerRepaint();},
    openNamedPlace(id){
      const shop=shown.find(shop=>shop.row.id===id);
      if(!shop)return false;
      openPlace(cardFor(shop.row),shop.row);
      return true;
    },
    setFuxing(value){
      if(value===fuxingEnabled)return;
      fuxingEnabled=value;dirty=true;unloadQueries();map.triggerRepaint();
    },
    setPacks(ids){
      const next=new Set(ids.filter(id=>typeof id==='string'&&/^p\d+_\d+$/.test(id)));
      if(next.size!==active.size||[...next].some(id=>!active.has(id))){
        active=next;
        dirty=true;
        unloadQueries();
        for(const [id,request] of loading)if(!active.has(id))request.abort();
        map.triggerRepaint();
      }
      kick();
    },
    setEnabled(value){
      enabled=!!value;
      if(!enabled){
        shown=[];updateBuilt([]);
        unloadQueries();
        for(const request of loading.values())request.abort();
      }
      else {dirty=true;kick();}
      map.triggerRepaint();
    },
    state(){
      const canvas=map.getCanvas(),width=canvas.clientWidth,height=canvas.clientHeight;
      const facing=[];
      for(const shop of shown){
        const face=projectedFace(shop,matrix,width,height);
        if(!face || face.every(([x])=>x<0) || face.every(([x])=>x>width)
          || face.every(([,y])=>y<0) || face.every(([,y])=>y>height))continue;
        const point={x:face.reduce((sum,[x])=>sum+x,0)/4,y:face.reduce((sum,[,y])=>sum+y,0)/4};
        facing.push({id:shop.row.id,name:shop.row.name,point});
      }
      return {enabled,packs:[...active],loaded:[...active].filter(id=>cache.has(id)).length,
        pending:loading.size,failed:[...active].filter(id=>failures.has(id)).length,
        drawn:shown.length,frontFacing:facing.length,targets:facing.slice(0,24),lastPick};
    },
  };
}
