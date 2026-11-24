import {footprintKey} from './authored-footprint.js?v=street-walls-1';
import {roofDrawing} from './taiwan-roofs.js?v=city-colour-3';
import {buildingStyle,storefrontStyle} from './taiwan-building-style.js?v=city-colour-3';
import {placePinType} from './place-pins.js';

export const CELL_METRES=170;
export const CELL_ORIGIN=[120,23.5];
const eastMetres=111320*Math.cos(CELL_ORIGIN[1]*Math.PI/180),northMetres=110574;
const xy=([lng,lat])=>[(lng-CELL_ORIGIN[0])*eastMetres,(lat-CELL_ORIGIN[1])*northMetres];
const geographic=([x,y])=>[CELL_ORIGIN[0]+x/eastMetres,CELL_ORIGIN[1]+y/northMetres];
export function taiwanCellAt(lng,lat){
  // Inverting a geographic cell corner can land a few nanometres below its integer index.
  return xy([lng,lat]).map(m=>Math.floor(m/CELL_METRES+1e-10));
}
export function taiwanCellBounds(column,row){
  return [...geographic([column*CELL_METRES,row*CELL_METRES]),
    ...geographic([(column+1)*CELL_METRES,(row+1)*CELL_METRES])];
}

const intersects=(a,b)=>a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
const inBox=([x,y],b)=>x>=b[0]&&x<=b[2]&&y>=b[1]&&y<=b[3];
function boundsOf(points){
  const b=[Infinity,Infinity,-Infinity,-Infinity];
  for(const [x,y] of points){
    b[0]=Math.min(b[0],x);b[1]=Math.min(b[1],y);b[2]=Math.max(b[2],x);b[3]=Math.max(b[3],y);
  }
  return b;
}
function inRing([x,y],ring){
  let inside=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const [a,b]=ring[i],[c,d]=ring[j];
    if((b>y)!==(d>y)&&x<(c-a)*(y-b)/(d-b)+a)inside=!inside;
  }
  return inside;
}
const inPolygon=(p,rings)=>inRing(p,rings[0])&&!rings.slice(1).some(hole=>inRing(p,hole));
function nearestOnSegment([x,y],a,b){
  const dx=b[0]-a[0],dy=b[1]-a[1],l2=dx*dx+dy*dy;
  const t=l2?Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/l2)):0;
  return {distance:Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy),t};
}
function hash(a,b){
  let n=Math.imul(a,0x1f123bb5)^Math.imul(b,0x5f356495);
  n=Math.imul(n^(n>>>16),0x45d9f3b);
  return ((n^(n>>>16))>>>0)/4294967296;
}
const feature=(rings,base,height,color,kind)=>({type:'Feature',geometry:{type:'Polygon',coordinates:rings},
  properties:{base,height,color,kind}});
const shops=new Set(['food','cafe','shop','fashion','market','books']);

// Used at neighborhood and street zoom so entering a block keeps its material family.
export function footprintStyle(f,rings,b){
  const tags=f.properties;
  const width=(b[2]-b[0])*eastMetres,depth=(b[3]-b[1])*northMetres;
  const id=tags.osmBuildingId??(f.id||footprintKey(rings[0]));
  return buildingStyle(id,tags,{height:tags.styleHeight??(Number(tags.render_height)||5.5),width,depth,area:tags.styleArea??width*depth,shop:tags.mappedShopKind});
}

function cellsInView(view,center){
  const [w,s,e,n]=view,[left,bottom]=taiwanCellAt(w,s),[right,top]=taiwanCellAt(e,n);
  const [cx,cy]=taiwanCellAt(...center),cells=[];
  for(let i=Math.max(left,cx-4);i<=Math.min(right,cx+4);i++)
    for(let j=Math.max(bottom,cy-4);j<=Math.min(top,cy+4);j++)
      cells.push({i,j,bounds:taiwanCellBounds(i,j),woods:[],blockers:[],shops:[]});
  return cells.sort((a,b)=>(a.i-cx)**2+(a.j-cy)**2-(b.i-cx)**2-(b.j-cy)**2);
}
function distribute(cells,item,key){
  for(const cell of cells)if(intersects(cell.bounds,item.bounds))cell[key].push(item);
}
function forPolygons(features,visit){
  for(const f of features){
    const {type,coordinates}=f.geometry;
    if(type==='Polygon')visit(f,coordinates);
    else if(type==='MultiPolygon')for(const polygon of coordinates)visit(f,polygon);
  }
}
function prepareGround(cells,view,tiles){
  const store=(features,key)=>forPolygons(features,(f,rings)=>{
    const b=boundsOf(rings[0]);
    if(intersects(view,b))distribute(cells,{bounds:b,rings,cover:f.properties.subclass??f.properties.class},key);
  });
  store(tiles.woods,'woods');store(tiles.water,'blockers');store(tiles.fields,'blockers');
  for(const f of tiles.ways){
    const {type,coordinates}=f.geometry;
    if(type!=='LineString'&&type!=='MultiLineString')continue;
    const p=f.properties;
    if(p.brunnel==='tunnel')continue;
    const width=({motorway:13,trunk:11,primary:8,secondary:7,tertiary:6,minor:4,
      path:2,track:3,rail:4,river:9,stream:3})[p.class]??3.5;
    for(const line of type==='LineString'?[coordinates]:coordinates){
      for(let i=1;i<line.length;i++){
        const left=line[i-1],right=line[i],b=boundsOf([left,right]);
        b[0]-=width/eastMetres;b[2]+=width/eastMetres;b[1]-=width/northMetres;b[3]+=width/northMetres;
        if(intersects(b,view))distribute(cells,{bounds:b,a:xy(left),b:xy(right),width,street:!!p.ordinaryRoad,named:!!p.name},'blockers');
      }
    }
  }
  for(const f of tiles.pois){
    if(f.geometry.type!=='Point')continue;
    const p=f.properties,name=p['name:zh-Hant']||p['name:zh']||p.name;
    let kind=placePinType(p.subclass);
    if(!shops.has(kind))kind=placePinType(p.class);
    if((!name&&!p.mappedShop)||!shops.has(kind))continue;
    const pt=f.geometry.coordinates,b=[...pt,...pt];
    if(inBox(pt,view))distribute(cells,{bounds:b,pt,kind,subclass:p.subclass||p.class,id:p.mappedShop},'shops');
  }
}

// Decorations sit on a real exterior segment. Windows and awning dimensions are illustrative.
// Ignore tile clipping edges: OpenMapTiles cuts vector polygons on its z14 grid, with buffers.
function clippingEdge(a,b){
  const fractionalTile=(v,scale)=>Math.abs(v*scale-Math.round(v*scale));
  const mx=lng=>(lng+180)/360,my=lat=>(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2;
  // Common clip buffers are whole multiples of 1/256 of the source tile.
  if(Math.abs(a[0]-b[0])<1e-10)return fractionalTile(mx(a[0]),16384*256)<1e-5;
  if(Math.abs(a[1]-b[1])<1e-10)return fractionalTile(my(a[1]),16384*256)<1e-5;
  return false;
}
function facade(rings,height,shop,details,neighbors,paint){
  const ring=rings[0],wall=ring.map(xy),target=shop?xy(shop.pt):null;
  const area=wall.slice(1).reduce((sum,b,i)=>sum+wall[i][0]*b[1]-b[0]*wall[i][1],0);
  const sign=Math.sign(area);
  const sides=[];
  for(let i=1;i<wall.length;i++){
    const a=wall[i-1],b=wall[i],dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);
    if(length<(shop?2.6:4)||clippingEdge(ring[i-1],ring[i]))continue;
    const near=target?nearestOnSegment(target,a,b):null;
    const mid=[(a[0]+b[0])/2,(a[1]+b[1])/2];
    const nx=sign*dy/length,ny=-sign*dx/length;
    const outside=geographic([mid[0]+nx*.85,mid[1]+ny*.85]);
    let streetScore=0,sharedWall=false;
    for(const edge of neighbors){
      if(edge.rings&&edge.rings!==rings&&inBox(outside,edge.bounds)&&inPolygon(outside,edge.rings))sharedWall=true;
      if(!edge.street)continue;
      const vx=edge.b[0]-edge.a[0],vy=edge.b[1]-edge.a[1],roadLength=Math.hypot(vx,vy);
      if(!roadLength||Math.abs(dx*vx+dy*vy)<.50*length*roadLength)continue;
      const hit=nearestOnSegment(mid,edge.a,edge.b);
      if(hit.distance>=24||hit.distance<.05)continue;
      const x=edge.a[0]+hit.t*vx,y=edge.a[1]+hit.t*vy;
      const facing=(nx*(x-mid[0])+ny*(y-mid[1]))/hit.distance;
      if(facing>.5)streetScore=Math.max(streetScore,(24-hit.distance)*facing+(edge.named?4:0));
    }
    if(sharedWall)continue;
    const score=streetScore*1.6+(near?-near.distance:Math.min(14,length)*.2);
    sides.push({a,dx:dx/length,dy:dy/length,length,t:near?.t??.5,score});
  }
  if(!sides.length||area===0)return;
  sides.sort((a,b)=>b.score-a.score);
  const street=sides[0];
  // A corner shop occupies its street frontage. Other exposed walls show upper-floor windows.
  drawWall(street,shop);
  const flank=sides.find(s=>Math.abs(s.dx*street.dx+s.dy*street.dy)<.65&&s.length>=5);
  if(flank)drawWall(flank,null);
  if(height>=38)for(const side of sides.filter(s=>s!==street&&s!==flank&&s.length>=6).slice(0,2))drawWall(side,null);

  function drawWall(side,shop){
    const {a,dx,dy,length,t}=side,half=Math.min(shop?7.2:11,length*(shop ? .46 : .47));
    const mid=Math.max(half+.15,Math.min(length-half-.15,t*length));
    const point=(s,d)=>geographic([a[0]+dx*(mid+s)+sign*dy*d,a[1]+dy*(mid+s)-sign*dx*d]);
    function panel(start,end,depth,base,top,color,kind){
      const ring=[point(start,-.08),point(end,-.08),point(end,depth),point(start,depth)];
      const part=feature([[...ring,ring[0]]],base,top,color,kind);
      if(shop?.id)part.properties.frontagePOI=shop.id;
      details.push(part);
    }
    // Glazing follows the full height of a tower. Scaled floor bands keep its
    // silhouette legible when a tall building fills the street camera.
    if(height>=38&&length>=5){
      const left=-mid+.45,right=length-mid-.45,bottom=4.4,top=height-.7;
      panel(left,right,.10,bottom,top,paint.glass,'curtain-wall');
      const sections=Math.min(9,Math.max(2,Math.round(length/4.8)));
      for(let i=0;i<=sections;i++){
        const x=left+(right-left)*i/sections;
        panel(x-.12,x+.12,.25,bottom,top,paint.frame,'mullion');
      }
      const spacing=Math.max(3.4,(height-bottom)/16);
      for(let level=bottom;level<top-.15;level+=spacing)panel(left,right,.28,level,level+.24,paint.trim,'spandrel');
    }
    if(shop&&height>=3.1){
      const front=storefrontStyle(shop.subclass||shop.kind,shop.id??shop.pt.join(','),paint);
      const {awning:fabric,sign:signColor,trim,glass,frame:joinery,accent}=front;
      const food=shop.kind==='food'||shop.kind==='market';
      const depth=food?1.22:.94,doorAt=-half*.42,door=Math.min(.78,half*.49);
      panel(-half,half,.17,.08,2.72,trim,'surround');
      panel(-half+.13,half-.13,.25,.32,2.53,glass,'glazing');
      panel(doorAt,doorAt+door,.31,.09,2.37,joinery,'door');
      panel(doorAt+.09,doorAt+door-.09,.35,.43,2.22,glass,'door-glass');
      panel(-half+.08,-half+.22,.30,.22,2.57,joinery,'shop-frame');
      panel(half*.38,half*.38+.12,.30,.22,2.57,joinery,'shop-frame');
      panel(-half+.11,half-.11,.31,1.86,1.96,joinery,'transom');
      panel(-half,half,depth,2.56,2.75,fabric,'awning');
      panel(-half,half,depth+.04,2.37,2.57,fabric,'valance');
      // The original shopfront kit paints a band across the top of the canopy as well as its lip.
      for(let j=0;j<(food?4:2);j++){
        const start=-half+(j+.3)*half/2;
        panel(start,start+half*.12,depth+.07,2.40,2.55,trim,'canopy-stripe');
        panel(start,start+half*.12,depth,2.75,2.78,trim,'canopy-stripe');

      }
      const displayStart=half*.02,displayEnd=half*.93;
      panel(displayStart,displayEnd,.37,.88,.96,joinery,'display-sill');
      const stock=[trim,accent,signColor,fabric];
      const count=front.detail==='books'?6:front.detail==='apparel'?2:4;
      for(let i=0;i<count;i++){
        const step=(displayEnd-displayStart)/count,start=displayStart+i*step;
        panel(start+.025,start+step*.77,.36,.97,1.16+(i%3)*.13,stock[i%stock.length],'display');
      }
      const top=Math.min(3.85,height-.07),bottom=2.79;
      panel(-half,half,.25,bottom,top,signColor,'shop-sign');
      panel(-half,half,.31,bottom,bottom+.085,trim,'sign-trim');
      panel(-half,half,.31,top-.085,top,trim,'sign-trim');
      // Projecting sign and inset display are illustrative. Only the map pin carries the sourced shop name.
      if(top>3.32){
        panel(half*.77,half*.77+.14,.99,top-.20,top-.11,joinery,'sign-bracket');
        panel(half*.77,half*.77+.16,.94,top-.77,top-.20,signColor,'blade-sign');
      }
    }
    if(height>=38)return;
    const sill=shop?4.25:1.05;
    const wide=paint.family==='school'||paint.family==='tower'||paint.family==='industrial';
    const bays=Math.max(1,Math.min(6,Math.round(2*half/(wide?4.2:3))));
    for(let floor=sill;floor+.85<Math.min(height-.15,22);floor+=3.2){
      const step=2*half/bays;
      for(let bay=0;bay<bays;bay++){
        const left=-half+(bay+.14)*step,right=left+step*(wide?.76:.62);
        panel(left,right,.15,floor,Math.min(height-.26,floor+1.46),paint.frame,'window-frame');
        panel(left+.08,right-.08,.20,floor+.10,Math.min(height-.36,floor+1.36),paint.glass,'window');
        panel(left-.05,right+.05,.24,floor-.08,floor+.05,paint.trim,'sill');
      }
    }
    if(height>4){
      panel(-half,half,.20,height-.46,height-.28,paint.trim,'cornice');
    }
  }
}

function grow(cells,view,zoom,allowed){
  const trees=[],stride=zoom<18?4:zoom<19?2:1;
  for(const c of cells){
    if(!c.woods.length)continue;
    for(let x=0;x<10;x+=stride)for(let y=0;y<10;y+=stride){
      const i=c.i*10+x,j=c.j*10+y,h=hash(i,j);
      const meters=[(i+.2+.6*h)*17,(j+.2+.6*hash(j,i+6701))*17],p=geographic(meters);
      if(!inBox(p,view))continue;
      const covers=c.woods.filter(f=>inBox(p,f.bounds)&&inPolygon(p,f.rings));
      if(!covers.length)continue;
      // OpenMapTiles also calls a lawn in a park "grass". Only park/garden
      // subclasses are eligible for sparse illustrative planting; pitches stay clear.
      const woodland=covers.some(f=>f.cover==='wood'||f.cover==='forest');
      const orchard=covers.some(f=>f.cover==='orchard');
      if(!woodland&&!orchard&&h>.12)continue;
      if(!allowed(...p)||c.blockers.some(f=>inBox(p,f.bounds)&&(f.rings?inPolygon(p,f.rings):
        nearestOnSegment(meters,f.a,f.b).distance<f.width)))continue;
      const height=orchard&&!woodland?3.3+1.6*h:5.5+3*h;
      trees.push([...p,height,orchard||h<.28?'round':'broad']);
      if(trees.length===360)return trees;
    }
  }
  return trees;
}

export function buildTaiwanCells({view,center,zoom,tiles,contains,exclude,overlapsAuthored=()=>false}){
  const cells=cellsInView(view,center),details=[],allowed=(lng,lat)=>contains(lng,lat)&&!exclude(lng,lat);
  if(!cells.length)return {details,mappedBodies:[],roofs:[],trees:[],cells:0};
  const close=zoom>=17;
  const workArea=close?[Math.min(...cells.map(c=>c.bounds[0])),Math.min(...cells.map(c=>c.bounds[1])),
    Math.max(...cells.map(c=>c.bounds[2])),Math.max(...cells.map(c=>c.bounds[3]))]:view;
  if(close)prepareGround(cells,workArea,tiles);
  const buildings=[],mappedBodies=[],roofs=[],seen=new Set(),origin=xy(center);
  forPolygons(tiles.buildings,(f,rings)=>{
    const ring=rings[0],b=boundsOf(ring);
    if(!intersects(b,view)&&(!close||!intersects(b,workArea)))return;
    if(close&&intersects(b,workArea))distribute(cells,{bounds:b,rings},'blockers');
    if(f.properties.hide_3d===true||!intersects(b,view)||overlapsAuthored(b,rings)||!allowed(...ring[0]))return;
    const key=JSON.stringify(ring);
    if(seen.has(key))return;
    seen.add(key);
    const mid=xy([(b[0]+b[2])/2,(b[1]+b[3])/2]);
    buildings.push({f,rings,b,distance:Math.hypot(mid[0]-origin[0],mid[1]-origin[1])});
  });
  buildings.sort((a,b)=>a.distance-b.distance);
  for(const [rank,{f,rings,b}] of buildings.entries()){
    const h=Math.max(1,Number(f.properties.render_height)||5.5);
    // No artificial border at the 170 m grid: the entire real roof (holes included) is one feature.
    const base=Math.min(h,Math.max(0,Number(f.properties.render_min_height)||0));
    if(!f.properties.localFootprint)mappedBodies.push(footprintKey(rings[0]));
    const paint=footprintStyle(f,rings,b);
    const detail=close&&rank<600&&intersects(b,workArea);
    const drawing=detail?roofDrawing(rings,h,f.properties,paint,zoom):null;
    const eave=drawing?.eave??h;
    details.push(feature(rings,Math.min(base,eave),eave,paint.wall,'building'));
    details.push(feature(rings,eave,eave+(drawing?.faces ? .01 : .15),paint.roof,'roof'));
    if(drawing?.faces)roofs.push(drawing);
    if(drawing?.rim)details.push(feature(drawing.rim,h+.15,h+.40,paint.trim,'roof-coping'));
    if(drawing?.fixture)details.push(feature(drawing.fixture,h+.15,h+.78,'#c3c8c2','roof-fixture'));
    if(!detail||zoom<18||details.length>2500||base>0)continue;
    const nearby=cells.filter(c=>intersects(b,c.bounds));
    const merchants=nearby.flatMap(c=>c.shops).filter(s=>inBox(s.pt,b)&&inPolygon(s.pt,rings));
    const shop=merchants.find(s=>s.id)??merchants[0];
    const neighbors=new Set(nearby.flatMap(c=>c.blockers));
    facade(rings,eave,shop,details,neighbors,paint);
  }
  return {details,mappedBodies,roofs,trees:close?grow(cells,view,zoom,allowed):[],cells:cells.length};
}
