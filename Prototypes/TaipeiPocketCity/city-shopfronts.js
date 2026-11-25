import {storefrontCategory} from './shop-categories.js';
import {drawServiceWindow} from './shop-service-windows.js?v=neighborhood-services-1';
import {drawRetailWindow,retailWindowTypes} from './shop-retail-windows.js?v=neighborhood-1';
import {neighborhoodServiceLabels,serviceWindowLabels} from './shop-service-labels.js?v=neighborhood-services-1';
import {categoryFoodWindow,cuisineWindow,drawFoodWindow} from './shop-food-windows.js';
import {mappedFoodWindow} from './taipei-food-window-evidence.js';
export {storefrontCategory};
import {MercatorCoordinate} from './assets/maplibre-gl.mjs';
import {program,transform} from './survey-layer.js';
import {drawDihuaShop} from './dihua-shop-art.js?v=dihua-shops-1';
import {buildFuxingFront} from './fuxing-fronts.js?v=dihua-shops-1';
import {decodeMapJSON} from './pocket-city-atlas.js?v=taipei-fronts-2';
import {completeFrontagePack} from './taipei-frontage-pack.js?v=registered-frontages-1';

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
  // Painted plaques carry the ink and field on one surface, without a second depth-tested text decal.
  if(lit.r<0.0){
    vec3 field=vec3(-lit.r-1.0,lit.gb);
    float coverage=showNames?texture(signTexture,uv).a:0.0;
    outColor=vec4(mix(field,vec3(1.0,0.89,0.67),coverage),1.0);
    return;
  }
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
  morning: ['#c69957','#79553c','#ad8d65','#9fa492','awning'],
  grill: ['#984d43','#6e4440','#9f7767','#8f9d92','awning'],
  seafood: ['#508782','#40635f','#9d8a71','#a1bbb1','awning'],
  dessert: ['#b57e90','#715866','#a78c83','#a5b2a5','awning'],
  salon: ['#948180','#665a58','#b09883','#95aca9','plain'],
  botanical: ['#65846b','#526b59','#ab967d','#91a79b','plain'],
  cycle: ['#567c87','#4b6367','#a3927c','#859d9b','plain'],
  optical: ['#65848a','#506467','#ad9e86','#92aba9','plain'],
  retail: ['#786c58','#5c5a52','#a28d7c','#829991','plain'],
};
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
const colored=Object.fromEntries(Object.entries(drawing).map(([key,values])=>{
  const [fascia,frame,wall,glass]=values.slice(0,4).map(rgb);
  return [key,{fascia,frame,wall,glass,detail:values[4]}];
}));
const cream=rgb('#f3dfb6'), stone=rgb('#b5a597'), highlights=rgb('#a6bbb1');
const stock=['#c58866','#d7b475','#659185','#9c7890','#8099ad'].map(rgb);
const clamp=(value,min,max)=>Math.max(min,Math.min(max,value));


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
  const label=typeof row.categoryLabel==='string'&&row.categoryLabel.trim();
  const categoryLabel=label&&label!==row.category?label:serviceWindowLabels.get(row.category)??storefrontCategory(row)[0];
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
  return {canvas,write(text,fitSign=false,heavy=false){
    const left=(index%cols)*width,top=Math.floor(index++/cols)*height;
    if(top+height>canvas.height)return null;
    const name=text.trim().slice(0,40);
    ctx.font=heavy?'bold 28px system-ui, sans-serif':fitSign?'600 26px "Songti TC", serif':'bold 23px system-ui, sans-serif';
    ctx.fillText(name,left+width/2,top+height/2,width-16);
    const inset=fitSign?Math.max(1,(width-Math.min(ctx.measureText(name).width,width-16))/2-8):1;
    return [(left+inset)/canvas.width,(top+1)/canvas.height,
      (left+width-inset)/canvas.width,(top+height-1)/canvas.height];
  }};
}

// Stock and furniture are illustrative. The trade, surveyed facade and available width
// come from the matched shop. Draw one display per bay so shelves cannot mask its shape.
const tradeWindows = new Map([
  ['hairdresser','salon'], ['florist','flowers'], ['bicycle','cycle'],
  ['coffee','coffee-stock'],
  ['optician','glasses'], ['convenience','cooler'], ['supermarket','checkout'],
  ['clothes','garments'], ['bakery','bread'], ['pastry','pastries'],
  ['beverages','bottles'], ['chemist','drugstore'],
]);
const retailWindowNames=new Set(retailWindowTypes.values());
const tradePaint={
  salon:'salon',flowers:'botanical',cycle:'cycle',glasses:'optical','coffee-stock':'cafe',
  'morning-griddle':'morning','sandwich-board':'morning','box-counter':'morning',
  'iron-grill':'grill','char-grill':'grill','seafood-counter':'seafood','dessert-case':'dessert',
};
const fixtureInk=rgb('#494845'), timber=rgb('#a87554'), porcelain=rgb('#f2dfb5'),
  teal=rgb('#47877e'), leather=rgb('#ac6856'), petal=rgb('#d47774'), leaf=rgb('#688c5e');
const enamel=rgb('#abccc1'), grape=rgb('#937796'), ochre=rgb('#d79e55'),
  crust=rgb('#bd8346'), sage=rgb('#5c927e'), berry=rgb('#b86d82');
const servicePaint={ink:fixtureInk,wood:timber,cream:porcelain,glass:highlights,teal,leather,berry,ochre,sage,grape};
// Polyfork's glass-door drinks fridge (0.8 × 1.9 m), dressing mirror (0.75 × 1.6 m)
// and 0.18 × 0.14 m loaf inform the proportions. The mesh is drawn locally.
function tradeWindow(trade, left, right, point, quad){
  const middle=(left+right)/2;
  // Real-world proportions survive narrow storefronts. The display sits above its sill.
  const scale=Math.min((right-left-.06)/1.65,1);
  if(scale<=0)return;
  const at=(x,y,z)=>point(middle+x*scale,.56+y*scale,z);
  const face=(a,b,lo,hi,d,color)=>quad([at(a,lo,d),at(b,lo,d),at(b,hi,d),at(a,hi,d)],color);
  function slab(a,b,lo,hi,d,color){
    face(a,b,lo,hi,d,color);
    quad([at(a,hi,.052),at(b,hi,.052),at(b,hi,d),at(a,hi,d)],porcelain);
    quad([at(b,lo,.052),at(b,lo,d),at(b,hi,d),at(b,hi,.052)],fixtureInk);
  }
  function shape(coords,d,color){quad(coords.map(([x,y])=>at(x,y,d)),color);}
  function rod(x,y,xx,yy,width,d,color){
    const len=Math.hypot(xx-x,yy-y),dx=-(yy-y)*width/(2*len),dy=(xx-x)*width/(2*len);
    shape([[x+dx,y+dy],[xx+dx,yy+dy],[xx-dx,yy-dy],[x-dx,y-dy]],d,color);
  }
  function rim(x,y,r,d,color,segments=10){
    for(let i=0;i<segments;i++){
      const a=2*Math.PI*i/segments,b=2*Math.PI*(i+1)/segments;
      rod(x+r*Math.cos(a),y+r*Math.sin(a),x+r*Math.cos(b),y+r*Math.sin(b),r*.19,d,color);
    }
  }
  function bottle(x,bottom,height,d,color){
    const shoulder=bottom+height*.69, neck=bottom+height*.83;
    const w=height*.20;
    face(x-w,x+w,bottom,shoulder,d,color);
    shape([[x-w,shoulder],[x+w,shoulder],[x+w*.45,neck],[x-w*.45,neck]],d,color);
    face(x-w*.45,x+w*.45,neck,bottom+height,d,porcelain);
  }
  switch(trade){
    case 'cooler':
      slab(-.34,.34,.015,1.63,.19,fixtureInk);
      face(-.29,.29,.11,1.44,.194,enamel);
      face(-.27,.27,1.48,1.57,.201,porcelain);
      for(const shelf of [.29,.78]){
        face(-.27,.27,shelf-.04,shelf,.207,porcelain);
        for(const [x,color] of [[-.17,ochre],[0,teal],[.17,berry]])bottle(x,shelf,.32,.212,color);
      }
      face(.26,.30,.67,.99,.232,fixtureInk);
      break;
    case 'checkout':
      // A basket with an open handle sits on the belt next to the tilted terminal.
      slab(-.74,.73,.04,.56,.21,sage);
      slab(-.77,.76,.56,.64,.26,fixtureInk);
      shape([[-.65,.88],[-.13,.88],[-.19,.65],[-.59,.65]],.19,ochre);
      rod(-.58,.88,-.48,1.04,.034,.20,fixtureInk);
      rod(-.48,1.04,-.28,1.04,.034,.20,fixtureInk);
      rod(-.28,1.04,-.20,.88,.034,.20,fixtureInk);
      for(const x of [-.51,-.39,-.27])face(x-.022,x+.022,.71,.82,.20,porcelain);
      face(.34,.43,.64,.85,.14,fixtureInk);
      shape([[.18,.84],[.53,.80],[.55,1.03],[.20,1.07]],.18,enamel);
      break;
    case 'garments':
      // A dressed tailor's form on a foot, with a tall mirror behind it.
      slab(-.69,-.08,.09,1.48,.10,timber);
      face(-.64,-.13,.17,1.42,.105,highlights);
      rod(-.58,.76,-.21,1.23,.045,.112,porcelain);
      slab(.02,.58,.015,.08,.19,fixtureInk);
      face(.27,.33,.08,.93,.13,timber);
      face(.24,.36,1.29,1.52,.12,timber);
      shape([[-.01,1.28],[.13,1.40],[.47,1.40],[.61,1.28]],.18,grape);
      shape([[.09,1.28],[.51,1.28],[.44,1.03],[.16,1.03]],.18,grape);
      shape([[.16,1.03],[.44,1.03],[.57,.56],[.03,.56]],.19,grape);
      rod(.20,1.385,.30,1.32,.031,.195,porcelain);
      rod(.30,1.32,.40,1.385,.031,.195,porcelain);
      break;
    case 'bread':
    case 'pastries':{
      const isBread=trade==='bread';
      // Two timber trays or a chilled pastry counter, with stock above the tray lip.
      slab(-.73,.73,.08,.37,.21,isBread?timber:sage);
      for(const shelf of [.43,.91]){
        slab(-.69,.69,shelf-.055,shelf,.23,isBread?crust:porcelain);
        for(const x of [-.43,0,.43]){
          if(isBread){
            face(x-.12,x+.12,shelf,shelf+.08,.16,crust);
            shape([[x-.12,shelf+.08],[x+.12,shelf+.08],
              [x+.075,shelf+.15],[x-.075,shelf+.15]],.16,ochre);
            rod(x-.045,shelf+.085,x+.003,shelf+.136,.022,.17,porcelain);
          }else{
            face(x-.13,x+.13,shelf,shelf+.10,.16,crust);
            shape([[x-.13,shelf+.10],[x+.13,shelf+.10],
              [x+.13,shelf+.18],[x-.13,shelf+.15]],.17,porcelain);
            face(x-.026,x+.026,shelf+.15,shelf+.22,.18,berry);
          }
        }
      }
      if(!isBread){
        rod(-.70,.38,-.70,1.26,.031,.25,enamel);
        rod(.70,.38,.70,1.26,.031,.25,enamel);
        face(-.70,.70,1.24,1.28,.25,enamel);
      }
      break;
    }
    case 'bottles':
      for(const shelf of [.24,.86]){
        slab(-.69,.69,shelf-.07,shelf,.20,timber);
        for(const [x,h,color] of [[-.43,.35,sage],[-.14,.42,ochre],[.16,.32,berry],[.44,.39,teal]]){
          bottle(x,shelf,h,.15,color);
        }
      }
      break;
    case 'drugstore':
      for(const shelf of [.35,.83]){
        slab(-.67,.67,shelf-.045,shelf,.17,enamel);
        for(const [x,color] of [[-.47,sage],[-.15,berry],[.18,ochre],[.47,teal]]){
          face(x-.08,x+.08,shelf,shelf+.30,.15,porcelain);
          face(x-.08,x+.08,shelf+.17,shelf+.23,.158,color);
        }
      }
      bottle(-.27,1.13,.29,.15,berry);
      bottle(.22,1.13,.36,.15,sage);
      break;
    case 'salon':
      face(-.52,.52,.65,1.59,.063,timber);
      face(-.45,.45,.72,1.52,.071,highlights);
      rod(-.38,1.05,-.06,1.41,.04,.074,porcelain);
      slab(-.27,.27,.03,.11,.24,fixtureInk);
      face(-.065,.065,.105,.40,.16,fixtureInk);
      slab(-.36,.36,.38,.52,.26,leather);
      slab(-.29,.29,.53,.85,.19,leather);
      for(const side of [-.36,.27])slab(side,side+.09,.52,.65,.27,fixtureInk);
      break;
    case 'flowers':
      for(const [x,y] of [[-.54,1.13],[-.10,1.36],[.29,1.18],[.53,1.32]]){
        const foot=x<0?-.25:.30;
        rod(foot,.42,x,y,.045,.12,leaf);
        shape([[x*.7,.68],[x*.7-.14,.84],[x*.7-.16,.88],[x*.7+.025,.80]],.133,leaf);
        const r=.105;
        shape([[x-r,y],[x-.04,y+r],[x+.06,y+r],[x+r,y]],.14,x>0?porcelain:petal);
        shape([[x-r,y],[x+r,y],[x+.04,y-r],[x-.06,y-r]],.14,x>0?porcelain:petal);
      }
      for(const x of [-.26,.30]){
        shape([[x-.14,.02],[x+.14,.02],[x+.23,.49],[x-.23,.49]],.19,timber);
        slab(x-.235,x+.235,.45,.52,.22,leather);
      }
      break;
    case 'cycle':
      for(const x of [-.49,.49])rim(x,.31,.28,.10,fixtureInk);
      for(const [x,y,xx,yy] of [[-.49,.31,-.07,.32],[-.07,.32,-.20,.69],[-.20,.69,-.49,.31],
        [-.20,.69,.28,.7],[.28,.7,-.07,.32],[.49,.31,.29,.78]]){
        rod(x,y,xx,yy,.052,.14,teal);
      }
      rod(-.20,.69,-.25,.82,.05,.15,fixtureInk);
      face(-.38,-.12,.80,.88,.17,leather);
      rod(.29,.78,.25,.92,.05,.16,fixtureInk);
      face(.22,.42,.90,.96,.17,fixtureInk);
      break;
    case 'espresso':
      slab(-.76,.76,.27,.38,.22,timber);
      slab(-.55,.42,.38,.47,.18,fixtureInk);
      slab(-.52,-.37,.47,.90,.15,teal);
      slab(-.55,.46,.76,1.05,.21,teal);
      face(-.27,.36,.73,.78,.205,fixtureInk);
      for(const x of [-.12,.21]){
        face(x-.035,x+.035,.64,.74,.16,fixtureInk);
        shape([[x-.07,.47],[x+.07,.47],[x+.10,.60],[x-.10,.60]],.18,porcelain);
      }
      break;
    case 'coffee-stock':
      slab(-.75,.75,.26,.35,.22,timber);
      for(const [x,h] of [[-.45,.98],[0,1.06],[.45,.89]]){
        shape([[x-.14,.36],[x+.14,.36],[x+.12,h],[x-.12,h]],.13,timber);
        face(x-.12,x+.12,h-.055,h,.145,fixtureInk);
        face(x-.085,x+.085,.48,.64,.15,porcelain);
      }
      break;
    case 'dining':
      for(const side of [-.55,.49])face(side,side+.065,.02,.58,.12,fixtureInk);
      slab(-.75,.75,.54,.65,.24,timber);
      for(const x of [-.32,.32]){
        shape([[x-.09,.65],[x+.09,.65],[x+.22,.84],[x-.22,.84]],.15,porcelain);
        face(x-.23,x+.23,.819,.855,.17,teal);
      }
      break;
    case 'glasses':
      slab(-.70,.70,.27,.37,.20,timber);
      for(const x of [-.29,.29])rim(x,.85,.24,.12,fixtureInk,8);
      rod(-.068,.89,.068,.89,.055,.13,timber);
      for(const side of [-1,1])rod(side*.51,.89,side*.64,.94,.049,.13,timber);
      break;
    default:{
      const tools={face,slab,shape,rod,rim,bottle};
      if(serviceWindowLabels.has(trade))drawServiceWindow(trade,tools,servicePaint);
      else if(retailWindowNames.has(trade))drawRetailWindow(trade,tools,servicePaint);
      else drawFoodWindow(trade,tools,servicePaint);
    }
  }
}

export function buildShop(vertices,row,center,scale,atlas,fuxing=false){
  const [x,y,z]=center;
  const angle=row.angle*Math.PI/180, nx=Math.cos(angle),ny=Math.sin(angle);
  const tx=-ny,ty=nx;
  const half=clamp(row.width,1.5,9)*.5, top=3.25, offset=.14;
  const type=storefrontCategory(row)[1];
  const seed=Array.from(row.id).reduce((value,c)=>(value*31+c.charCodeAt(0))>>>0,0);
  const knownCuisine=typeof row.cuisine==='string'?cuisineWindow(row.category,row.cuisine):mappedFoodWindow(row);
  const trade=knownCuisine??categoryFoodWindow(row.category,seed,row.categoryLabel)??tradeWindows.get(row.category)
    ??(serviceWindowLabels.has(row.category)?row.category:retailWindowTypes.get(row.category));
  const paint=colored[tradePaint[trade]??type];
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
  function plaque(a,b,low,high,depth,fill){
    const field=rgb(fill), uv=atlas.write(row.name,true,true);
    const color=uv?[-1-field[0],field[1],field[2]]:field;
    panel(a,b,low,high,depth,color,uv);
  }
  const geometry={half,top,point,quad,panel,rgb,sign,plaque};
  if(drawDihuaShop(row,geometry) || (fuxing && buildFuxingFront(row,geometry))){
    return {row,first,count:vertices.length/13-first,hit:corners(-half,half,.08,top,.055),
      lip:row.arcadeDepth?corners(-half,half,.08,top,row.arcadeDepth+.14):null};
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
  // Keep the original openings when adding stock inside an existing window.
  const doorCenter=trade&&!neighborhoodServiceLabels.has(trade)&&half<2.85?half-.14-door:0;
  const dl=doorCenter-door,dr=doorCenter+door;
  panel(dl-.085,dr+.085,.12,2.67,.025,paint.frame);
  panel(dl,dr,.22,2.56,.041,paint.glass);
  panel(dl+.06,dr-.06,1.45,2.44,.049,highlights);
  panel(dr-.18,dr-.11,1.07,1.40,.053,cream);
  for(const [start,end] of [[-half+.10,dl-.13],[dr+.13,half-.10]]){
    if(end-start<.25)continue;
    panel(start,end,.44,2.60,.02,paint.frame);
    panel(start+.073,end-.073,.53,2.51,.038,paint.glass);
    panel(start+.10,end-.10,2.23,2.40,.042,highlights);
    if(trade){
      if(start<dl){
        panel(start+.073,end-.073,.53,2.20,.043,paint.glass.map(c=>c*.81));
        panel(start+.06,end-.06,.46,.53,.14,trim);
        tradeWindow(trade,start+.07,end-.07,point,quad);
      }
    }else if(['books','shelves','awning'].includes(paint.detail)){
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

function projectedFace(shop,matrix,width,height,points=shop.hit){
  const corners=points.map(([x,y,z])=>{
    const component=i=>matrix[i]*x+matrix[i+4]*y+matrix[i+8]*z+matrix[i+12];
    const w=component(3);
    return w>0?[(1+component(0)/w)*width/2,(1-component(1)/w)*height/2]:null;
  });
  if(!corners.every(Boolean))return null;
  const [[ax,ay],[bx,by],[cx,cy]]=corners;
  return (bx-ax)*(cy-ay)-(by-ay)*(cx-ax)<0?corners:null;
}

function hitShop(shop,matrix,point,width,height){
  const faces=shop.lip?[shop.hit,shop.lip]:[shop.hit];
  return faces.some(points=>{
    const corners=projectedFace(shop,matrix,width,height,points);
    return corners && corners.every(([x,y],index)=>{
      const [nx,ny]=corners[(index+1)%4];
      return (nx-x)*(point.y-y)-(ny-y)*(point.x-x)<0;
    });
  });
}

export async function readShopfrontPack(id, signal){
  const url=new URL(`./data/city170-frontages/${id}.json.gz?v=survey-health`,import.meta.url);
  const response=await fetch(url,{signal});
  if(!response.ok||!response.body)throw Error(`Shopfront pack returned ${response.status}`);
  return completeFrontagePack(id,await decodeMapJSON(response));
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
      readShopfrontPack(id,controller.signal).then(payload=>{
        if(removed||controller.signal.aborted)return;
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
