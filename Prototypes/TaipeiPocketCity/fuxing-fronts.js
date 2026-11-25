// The position, width, and direction still come from each survey-aligned row.
// Openbook locates 信義書局 at 復興南路二段173號 and describes its magazine stock.
// https://readingpass.openbook.org.tw/node/62988
// Dreamland's documentary photographs show the red fascia under the covered
// arcade, stone jamb, dark window frames, and steep magazine displays.
// https://www.dream-land.com.tw/56%E4%BF%A1%E7%BE%A9%E6%9B%B8%E5%B1%80/
// https://www.dream-land.com.tw/wp-content/uploads/2016/09/IMG_7052-1024x683.jpg
// Simba and Giorgio's addresses/categories are sourced. Their façades and the
// other ground-floor shop displays in the study square are illustrated.
// https://www.ubereats.com/tw/store/simba-cafe/UoHVnV0RUJGIMOdUGqxz_A
// https://www.openstreetmap.org/node/3724051663
// https://www.openstreetmap.org/node/3724051664

import {bookstoreId,inFuxing} from './fuxing-block.js';

const fixtureIds={
  simba:'poi/node/3724051663',
  giorgio:'poi/node/3724051664',
};
const ink='#51433a', paper='#f8e3bc', stone='#c6b6a0';
const covers=['#edbd71','#b96956','#85a28a','#a5bac1','#eee0b7','#7e8fa6','#d68677'];

export function frontageParts({point,quad,panel,rgb,sign}){
  function surface(vertices,fill){
    quad(vertices.map(p=>point(...p)),rgb(fill));
  }
  function face(left,right,low,high,depth,fill){
    panel(left,right,low,high,depth,rgb(fill));
  }
  function block(left,right,low,high,back,forward,fill,shade=fill){
    face(left,right,low,high,forward,fill);
    face(left,right,low,high,back,shade);
    for(const side of [left,right]){
      surface([[side,low,back],[side,low,forward],[side,high,forward],[side,high,back]],shade);
    }
    for(const level of [low,high]){
      surface([[left,level,back],[right,level,back],[right,level,forward],[left,level,forward]],shade);
    }
  }
  function board(left,right,bottom,top,depth,fill,letter=paper){
    block(left,right,bottom,top,depth-.07,depth,fill,ink);
    // A narrow dark return defines the sign edge even with the name layer off.
    face(left+.015,right-.015,bottom+.025,bottom+.049,depth+.003,ink);
    sign(left+.11,right-.11,bottom+.060,top-.051,depth+.011,rgb(letter));
  }
  return {surface,face,block,board};
}

function threshold(p,half,fill,depth=.47){
  p.block(-half,half,.025,.084,.01,depth,fill,stone);
  for(let x=-half+.41;x<half-.08;x+=.41){
    p.surface([[x,.086,.012],[x+.012,.086,.012],[x+.012,.086,depth],[x,.086,depth]],'#ad9a82');
  }
}

function magazineTable(p,left,right,seed,depth,lip,top){
  if(right-left<.55)return;
  const back=depth-.32;
  for(const x of [left+.065,right-.125]){
    p.block(x,x+.059,.087,lip,depth-.068,depth-.012,'#9f7957',ink);
    p.block(x,x+.059,.087,top-.065,back,back+.075,'#aa8560',ink);
    p.surface([[x,.35,depth],[x+.06,.35,depth],[x+.06,.42,back],[x,.42,back]],'#69513f');
  }
  const rack=(x,f,raise=0)=>[x,lip+(top-lip)*f+raise,depth-.32*f];
  p.surface([rack(left,0),rack(right,0),rack(right,1),rack(left,1)],'#9a744f');
  p.block(left,right,lip-.045,lip+.035,depth-.034,depth+.035,'#c49c66','#846547');
  p.face(left+.015,right-.015,lip-.005,lip+.022,depth+.036,ink);
  const books=Math.max(2,Math.round((right-left)/.38));
  for(let i=0;i<books;i++){
    const lo=left+(right-left)*(i+.16)/books;
    const hi=left+(right-left)*(i+.88)/books;
    const h=.70+.10*(i%3);
    const color=covers[(i+seed)%covers.length];
    p.surface([rack(lo,.055,.019),rack(hi,.055,.019),rack(hi,h,.019),rack(lo,h,.019)],color);
    p.surface([rack(lo,.058,.026),rack(hi,.058,.026),rack(hi,.114,.026),rack(lo,.114,.026)],'#f2dcad');
    p.surface([rack(lo+.021,h-.14,.027),rack(hi-.024,h-.14,.027),rack(hi-.024,h-.055,.027),rack(lo+.021,h-.055,.027)],paper);
    const center=(lo+hi)*.5;
    p.surface([rack(lo+.05,.19,.024),rack(hi-.04,.19,.024),rack(hi-.01,.31,.024),rack(center,.48,.024)],
      covers[(i+seed+3)%covers.length]);
  }
}

function bookshop(p,half,top){
  const left=-half+.19,right=half-.14;
  const doorLeft=-.62,doorRight=.60, jamb=right-.51;
  // Model the two jambs and soffit out from the still-solid LOD1 surface.
  p.face(left,right,.085,top-.115,.014,'#463e38');
  threshold(p,half,'#d6c4a5',.76);
  p.block(left,left+.20,.085,top-.31,.02,.37,'#827568','#6f6256');
  p.block(jamb,right,.085,top-.12,.015,.39,'#b7a79a','#918478');
  for(const [i,span] of [[0,.38],[1,.32],[2,.47],[3,.35],[4,.31]]){
    const bottom=.39+i*.46;
    p.face(jamb+.028,right-.048,bottom,bottom+.019,.397,'#817564');
    p.face(jamb+.037,jamb+span,bottom+.025,bottom+.071,.398,'#c9b7a0');
  }
  p.block(left,right,top-.33,top-.075,.015,.51,'#e3d6bb','#bba88d');
  p.block(left+.08,right-.10,top-.315,top-.285,.18,.39,'#efe2c6','#aea087');
  p.board(left+.22,jamb-.10,top-.99,top-.22,.58,'#b94131','#fff2d5');
  p.block(jamb-.035,right-.022,1.42,2.30,.38,.473,'#709f51','#435b43');
  p.face(jamb+.02,right-.064,2.17,2.245,.477,'#9eb375');
  for(const side of [[left+.23,doorLeft-.12],[doorRight+.12,jamb-.13]]){
    const [a,b]=side;
    p.block(a,b,.27,2.38,.019,.075,'#786352',ink);
    p.face(a+.044,b-.043,.34,2.34,.082,'#8c9d91');
    p.face(a+.063,b-.062,1.96,2.25,.084,'#b4bb9d');
    p.face(a+.044,b-.043,1.78,1.82,.108,'#6f6153');
    for(const h of [.63,1.18,1.65]){
      p.face(a+.066,b-.06,h,h+.047,.109,'#e0c393');
      for(let i=0;i<6;i++){
        const x=a+.074+(b-a-.144)*i/6;
        const width=(b-a-.145)/7;
        p.face(x,x+width,h+.051,h+.26+(i%3)*.054,.101,covers[(i+Math.round(h*9))%covers.length]);
      }
    }
    p.face((a+b)/2-.032,(a+b)/2+.032,.27,2.38,.115,ink);
  }
  p.face(doorLeft,doorRight,.084,2.43,.044,'#413a34');
  p.face(doorLeft+.075,doorRight-.05,.11,2.30,.052,'#4a4037');
  p.face(doorLeft+.12,doorLeft+.41,.32,1.88,.063,'#96734c');
  p.face(doorLeft+.17,doorLeft+.37,.83,1.68,.069,'#c59c66');
  for(const z of [.91,1.19,1.43]){
    p.face(doorLeft+.135,doorLeft+.39,z,z+.033,.072,'#e0ba7f');
    p.face(doorLeft+.19,doorLeft+.24,z+.037,z+.16,.077,'#825b46');
    p.face(doorLeft+.27,doorLeft+.33,z+.036,z+.19,.077,'#a98455');
  }
  p.block(doorLeft-.062,doorLeft+.019,.084,2.42,.039,.24,'#544b43','#71604f');
  p.block(doorRight-.013,doorRight+.069,.084,2.42,.039,.24,'#544b43','#71604f');
  p.block(doorLeft-.051,doorRight+.063,2.35,2.456,.029,.23,'#4b4239','#6c5e4d');
  p.face(doorLeft+.30,doorRight-.35,2.17,2.231,.064,'#dfb87c');
  p.block(doorLeft+.023,doorRight-.016,.064,.110,.048,.59,'#bb9b77','#9d8162');
  p.surface([[doorLeft+.05,.112,.064],[doorRight-.06,.112,.064],
    [doorRight-.06,.112,.57],[doorLeft+.05,.112,.57]],'#c6ae89');
  p.face(doorLeft+.05,doorRight-.06,.092,.107,.598,'#8a6e52');
  magazineTable(p,left+.16,doorLeft-.20,2,.78,.61,1.42);
  magazineTable(p,doorRight+.15,jamb-.06,0,.66,.54,1.17);
  // A face-out open spread gives the bookstall a readable silhouette at phone scale.
  const spine=left+.83;
  const page=(u,v)=>[spine+u,1.12+v+.10*Math.abs(u),.815-.49*v+.13*Math.abs(u)];
  for(const side of [-1,1]){
    const u=side*.36;
    p.surface([page(0,0),page(u,.045),page(u,.59),page(0,.51)],side<0?'#f5dea5':'#ffefc4');
    p.surface([page(u*.20,.19),page(u*.84,.22),page(u*.84,.42),page(u*.20,.39)],side<0?'#ac7758':'#6f8b85');
  }
  p.surface([page(-.018,.0),page(.018,.0),page(.018,.51),page(-.018,.51)],'#866f51');
}

function canopy(p,left,right,bottom,reach,fill,edge,stripes=0){
  const slope=(a,b,raise=0)=>[[a,bottom+.28+raise,.09],[b,bottom+.28+raise,.09],
    [b,bottom+raise,reach],[a,bottom+raise,reach]];
  p.surface(slope(left,right),fill);
  for(let i=1;i<stripes;i++){
    const x=left+(right-left)*i/stripes;
    p.surface(slope(x,x+.040,.008),edge);
  }
  p.face(left,right,bottom-.112,bottom,reach,fill);
  p.face(left,right,bottom-.116,bottom-.093,reach+.004,edge);
}

function cabinet(p,left,right,depth,palette,kind){
  if(right-left<.55)return;
  p.block(left,right,.085,.225,.012,depth,palette.trim,ink);
  p.block(left,right,.225,.97,.017,depth,kind==='apparel'?'#827572':palette.glass,ink);
  p.face(left+.064,right-.06,.91,.94,depth+.010,'#e5c5a0');
  for(const h of [.34,.62]){
    p.face(left+.055,right-.051,h,h+.022,depth+.008,'#a67f60');
    if(kind==='apparel')continue;
    const count=Math.max(2,Math.round((right-left)/.25));
    for(let i=0;i<count;i++){
      const width=(right-left-.127)/count;
      const x=left+.057+i*width;
      const tall=(kind==='drinks'?.21:.15)-(i%3)*.022;
      if(kind==='glasses'){
        const lens=width*.23, top=h+.11;
        for(const a of [x+.019,x+.019+lens+.024]){
          p.face(a,a+lens,h+.048,top,depth+.014,'#aa9b8b');
          p.face(a+.009,a+lens-.009,h+.056,top-.008,depth+.018,'#c2c8ad');
        }
        p.face(x+.017+lens,x+.047+lens,h+.076,h+.091,depth+.020,ink);
      }else{
        p.face(x+.011,x+width*.69,h+.023,h+.025+tall,depth+.014,covers[(i+(h>.4?3:0))%covers.length]);
      }
    }
  }
}

function jacket(p,x,width,color){
  const u=x+width*.5, z=1.90, d=.127;
  p.face(u-.027,u+.027,z+.01,z+.18,d,'#dfc3a0');
  p.surface([[x,z-.36,d],[x+width*.19,z-.055,d],[x+width*.36,z-.02,d],[x+width*.24,z-.46,d]],color);
  p.surface([[x+width*.64,z-.025,d],[x+width*.82,z-.055,d],[x+width,z-.36,d],[x+width*.78,z-.47,d]],color);
  p.surface([[x+width*.25,z-.79,d],[x+width*.76,z-.79,d],[x+width*.79,z-.079,d],[x+width*.22,z-.079,d]],color);
  p.surface([[u-width*.125,z-.046,d+.006],[u+width*.125,z-.046,d+.006],
    [u+width*.031,z-.265,d+.006],[u-width*.035,z-.265,d+.006]],'#776961');
  p.face(u-.021,u+.021,z-.735,z-.265,d+.008,'#e1b298');
  for(const z0 of [z-.619,z-.47,z-.324]){
    p.face(u+.028,u+.055,z0,z0+.023,d+.011,'#dbc29e');
  }
}

function coffeeCounter(p,a,b,theme){
  p.block(a,b,.084,1.13,.108,.386,'#ac8357','#755b45');
  p.block(a-.025,b+.025,1.12,1.19,.088,.421,'#d1b486','#92734e');
  p.face(a+.035,b-.035,.26,.34,.395,'#80654e');
  const width=Math.min(.60,(b-a)*.43);
  p.block(a+.10,a+.10+width,1.19,1.54,.12,.307,'#777c71','#4d5b54');
  p.face(a+.14,a+.10+width-.028,1.24,1.34,.31,theme.sign);
  p.face(a+.16,a+.10+width-.048,1.47,1.512,.31,'#bfbb9d');
  const cups=Math.min(4,Math.floor((b-a-width-.2)/.11));
  for(let i=0;i<cups;i++){
    const x=b-.15-i*.129;
    p.block(x,x+.086,1.19,1.31,.246,.338,paper,'#a68465');
    p.face(x+.009,x+.076,1.24,1.263,.344,theme.sign);
  }
}

const themes={
  simba:{wall:'#d2b99e',trim:'#715844',glass:'#7d9e93',sign:'#436b5d',awning:'#688e73',edge:'#ead7ae',detail:'drinks'},
  giorgio:{wall:'#a88775',trim:'#514448',glass:'#8c8b84',sign:'#583d48',detail:'apparel'},
  apparel:{wall:'#cbb19f',trim:'#856a64',glass:'#8fa19a',sign:'#926d75',detail:'apparel'},
  bakery:{wall:'#e1c69b',trim:'#a47952',glass:'#b4aa8c',sign:'#9b6c4c',awning:'#bd9965',edge:'#f0d7a2',detail:'products'},
  drinks:{wall:'#d9bea0',trim:'#775d48',glass:'#91a69a',sign:'#547a70',awning:'#7c9a87',edge:'#ecd8b2',detail:'drinks'},
  dining:{wall:'#d4ac89',trim:'#845e4e',glass:'#929d8c',sign:'#97554b',awning:'#b57056',edge:'#f0d0a5',detail:'products'},
  grocery:{wall:'#e2c09a',trim:'#8b6c4f',glass:'#8e9b81',sign:'#7f704e',detail:'products'},
  optician:{wall:'#d9c5ad',trim:'#777270',glass:'#8aa29c',sign:'#596e72',detail:'glasses'},
  travel:{wall:'#caad8c',trim:'#755f4e',glass:'#a3ab96',sign:'#6c7f85',detail:'products'},
};
const grouped=new Map(Object.entries({
  clothes:'apparel', shoes:'apparel', jewelry:'apparel',
  cafe:'drinks', beverages:'drinks', tea:'drinks',
  bakery:'bakery', pastry:'bakery', confectionery:'bakery',
  restaurant:'dining',fast_food:'dining',inspection_store:'dining',
  supermarket:'grocery', convenience:'grocery', alcohol:'grocery',
  optician:'optician', travel_agency:'travel',
}));

function illustratedShop(p,half,top,theme){
  const width=2*half, left=-half+.11, right=half-.11;
  const door=Math.min(.66,width*.22), openingLeft=-door+.13, openingRight=door+.13;
  const columns=[[left+.103,openingLeft-.111],[openingRight+.111,right-.103]];
  p.face(left,right,.081,top,.020,theme.wall);
  threshold(p,half,theme===themes.giorgio?'#ad9184':'#d1b99d');
  p.block(left,right,top-.16,top,.013,.28,theme.trim,'#aa9277');
  p.board(left+.074,right-.074,top-.671,top-.185,.187,theme.sign);
  for(const x of [left,right-.105]){
    p.block(x,x+.105,.081,top-.14,.017,.228,theme.trim,'#927460');
  }
  p.face(openingLeft-.06,openingRight+.06,.085,2.55,.041,ink);
  p.face(openingLeft,openingRight,.133,2.48,.056,theme.detail==='apparel'?'#676864':'#788b79');
  p.face(openingLeft+.04,openingRight-.03,2.21,2.365,.063,'#b5c0a8');
  p.face(openingRight-.16,openingRight-.107,.99,1.33,.107,paper);
  for(const x of [openingLeft-.049,openingRight]){
    p.block(x,x+.043,.085,2.54,.024,.15,theme.trim);
  }
  for(const [a,b] of columns){
    if(b-a<.26)continue;
    p.block(a,b,.21,2.537,.021,.081,theme.trim,ink);
    p.face(a+.042,b-.042,.255,2.495,.089,theme.glass);
    p.face(a+.058,b-.058,2.21,2.355,.094,'#b5c0a8');
    if(theme.detail==='apparel'){
      p.face(a+.064,b-.065,2.021,2.054,.108,'#d3b4a8');
      const hanger=Math.min(1.08,(b-a)*.72);
      jacket(p,(a+b-hanger)*.5,hanger,theme===themes.giorgio?(a<0?'#bf846e':'#a7aa8d'):'#916e80');
    }else{
      const shelf=theme.detail==='drinks'?1.18:1.4;
      p.face(a+.067,b-.061,shelf,shelf+.043,.104,'#ceaa7e');
      if(theme===themes.simba){
        for(let i=0;i<4;i++){
          const x=a+.112+(b-a-.21)*i/4;
          p.face(x,x+.135,shelf+.048,shelf+.232,.111,['#e5cda4','#8b9b71','#be885f','#dabe90'][i]);
          p.face(x+.015,x+.126,shelf+.205,shelf+.229,.121,paper);
        }
      }
    }
    if(theme===themes.simba && a<0){
      coffeeCounter(p,a+.075,b-.075,theme);
    }else{
      cabinet(p,a+.06,b-.06,.123,theme,theme.detail);
    }
  }
  if(theme.awning && width>=3){
    canopy(p,left+.055,right-.055,2.303,theme===themes.simba?.89:.51,theme.awning,theme.edge,theme===themes.simba?8:5);
  }
}

export function buildFuxingFront(row,geometry){
  if(!inFuxing(...row.center))return false;
  const {half,top}=geometry;
  const p=frontageParts(geometry);
  if(row.id===bookstoreId){
    bookshop(p,half,top);
    return true;
  }
  const type=row.id===fixtureIds.simba?'simba':row.id===fixtureIds.giorgio?'giorgio':grouped.get(row.category);
  if(!type)return false;
  illustratedShop(p,half,top,themes[type]);
  return true;
}
