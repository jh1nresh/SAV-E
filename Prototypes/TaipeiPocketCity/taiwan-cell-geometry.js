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
const roofPalette=['#c9b49c','#c6b79f','#ccb39c','#bdab98','#c0b9a8'];
const shops=new Set(['food','cafe','shop','fashion','market','books']);
const awnings={food:'#bf7354',cafe:'#648b80',shop:'#6e98a1',fashion:'#bc8291',market:'#c59356',books:'#848e6e'};

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
        if(intersects(b,view))distribute(cells,{bounds:b,a:xy(left),b:xy(right),width},'blockers');
      }
    }
  }
  for(const f of tiles.pois){
    if(f.geometry.type!=='Point')continue;
    const p=f.properties,name=p['name:zh-Hant']||p['name:zh']||p.name;
    let kind=placePinType(p.subclass);
    if(!shops.has(kind))kind=placePinType(p.class);
    if(!name||!shops.has(kind))continue;
    const pt=f.geometry.coordinates,b=[...pt,...pt];
    if(inBox(pt,view))distribute(cells,{bounds:b,pt,kind},'shops');
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
function facade(rings,height,shop,details){
  const ring=rings[0],wall=ring.map(xy),target=shop?xy(shop.pt):null;
  let side,area=0,best=-Infinity;
  for(let i=1;i<wall.length;i++){
    const a=wall[i-1],b=wall[i],dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);
    area+=a[0]*b[1]-b[0]*a[1];
    if(length<4||clippingEdge(ring[i-1],ring[i]))continue;
    const near=target?nearestOnSegment(target,a,b):null;
    const score=near?-near.distance:length;
    if(score>best){best=score;side={a,dx:dx/length,dy:dy/length,length,t:near?.t??.5};}
  }
  if(!side||area===0)return;
  const {a,dx,dy,length,t}=side,sign=Math.sign(area),half=Math.min(5.4,length*.39);
  const mid=Math.max(half+.15,Math.min(length-half-.15,t*length));
  const point=(s,d)=>geographic([a[0]+dx*(mid+s)+sign*dy*d,a[1]+dy*(mid+s)-sign*dx*d]);
  function panel(start,end,depth,base,top,color,kind){
    const ring=[point(start,-.08),point(end,-.08),point(end,depth),point(start,depth)];
    details.push(feature([[...ring,ring[0]]],base,top,color,kind));
  }
  if(shop&&height>=3.1){
    panel(-half,half,1.05,2.70,2.95,awnings[shop.kind],'awning');
    panel(-half*.86,half*.86,.13,.42,2.58,'#668482','glazing');
  }
  const sill=shop?4.25:1.05;
  for(let floor=sill;floor+1.25<Math.min(height,19);floor+=3.2){
    for(let bay=0;bay<3;bay++){
      const start=-half+(bay+.15)*2*half/3;
      panel(start,start+half*.45,.17,floor,floor+1.2,'#829a96','window');
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
  if(!cells.length)return {details,trees:[],cells:0};
  const workArea=[Math.min(...cells.map(c=>c.bounds[0])),Math.min(...cells.map(c=>c.bounds[1])),
    Math.max(...cells.map(c=>c.bounds[2])),Math.max(...cells.map(c=>c.bounds[3]))];
  prepareGround(cells,workArea,tiles);
  const buildings=[],seen=new Set(),origin=xy(center);
  forPolygons(tiles.buildings,(f,rings)=>{
    const ring=rings[0],b=boundsOf(ring);
    if(!intersects(b,workArea))return;
    distribute(cells,{bounds:b,rings},'blockers');
    if(f.properties.hide_3d===true||!intersects(b,view)||overlapsAuthored(b,rings)||!allowed(...ring[0]))return;
    const key=JSON.stringify(ring);
    if(seen.has(key))return;
    seen.add(key);
    const mid=xy([(b[0]+b[2])/2,(b[1]+b[3])/2]);
    buildings.push({f,rings,b,distance:Math.hypot(mid[0]-origin[0],mid[1]-origin[1])});
  });
  buildings.sort((a,b)=>a.distance-b.distance);
  for(const {f,rings,b} of buildings.slice(0,600)){
    const h=Math.max(1,Number(f.properties.render_height)||5.5);
    // No artificial border at the 170 m grid: the entire real roof (holes included) is one feature.
    const seed=Number(f.id)||Math.round(h*37);
    const color=roofPalette[Math.floor(hash(seed,451)*roofPalette.length)];
    details.push(feature(rings,h,h+.26,color,'roof'));
    if(zoom<18||details.length>900||Number(f.properties.render_min_height)>0)continue;
    const shop=cells.filter(c=>intersects(b,c.bounds)).flatMap(c=>c.shops)
      .find(s=>inBox(s.pt,b)&&inPolygon(s.pt,rings));
    facade(rings,h,shop,details);
  }
  return {details,trees:grow(cells,view,zoom,allowed),cells:cells.length};
}
