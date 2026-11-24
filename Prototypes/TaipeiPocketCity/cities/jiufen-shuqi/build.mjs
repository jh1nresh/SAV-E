// Rebuild the georeferenced mesh, scene and catalog metadata from the recovered source primitives.
// node cities/jiufen-shuqi/build.mjs
import {readFile,writeFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {geographicPoint} from '../geography.js';
import {buildingStyle} from '../../taiwan-building-style.js';

const local=name=>new URL(name,import.meta.url);
const source=JSON.parse(gunzipSync(await readFile(local('source.json.gz'))));
const {lon,lat,hero,route,groups,geometries}=source;
const meta={lon,lat,rotation:0,size:90,half:45,north:[0,1,0],drive:'right',place:'九份豎崎路'};
const at=[hero[0],-hero[1]];
const round=(value,scale=1e7)=>Math.round(value*scale)/scale;
const project=p=>geographicPoint(meta,p).map(n=>round(n));
const coordinates=arr=>typeof arr[0]==='number'?project(arr):arr.map(coordinates);
const footprint={type:source.footprintLocal.type,coordinates:coordinates(source.footprintLocal.coordinates)};
let west=Infinity,south=Infinity,east=-Infinity,north=-Infinity;
function extend(x,y){
  west=Math.min(west,x);east=Math.max(east,x);south=Math.min(south,y);north=Math.max(north,y);
}
function boundsOf(array){if(typeof array[0]==='number')extend(...array);else array.forEach(boundsOf);}
boundsOf(footprint.coordinates);
const parts=[],triangles=[],lanterns=[];
const linear=b=>b<=.04045?b/12.92:((b+.055)/1.055)**2.4;
const srgb=b=>Math.round(Math.max(0,Math.min(1,b<=.0031308?12.92*b:1.055*b**(1/2.4)-.055))*255);
const toLinear=hex=>hex.match(/../g).map(value=>linear(parseInt(value,16)/255));
const [sun,sky,earth]=['fff6e7','e7effe','8295b0'].map(toLinear);
const unit=v=>{const l=Math.hypot(...v);return l?v.map(x=>x/l):[0,1,0];};
const sunDirection=unit([-700,1100,550]);
function light(color,normal){
  const hemi=.5+.5*normal[1],direct=Math.max(0,sunDirection.reduce((n,v,i)=>n+v*normal[i],0));
  return color.map((v,i)=>srgb(v*((sky[i]*hemi+earth[i]*(1-hemi))*2.12+sun[i]*1.72*direct)/Math.PI));
}
function transform(m,[x,y,z]){
  return [0,1,2].map(i=>m[i]*x+m[i+4]*y+m[i+8]*z+m[i+12]);
}
function normalMatrix(m){
  // These legacy object matrices are rotation times diagonal scale, without shear.
  return [0,4,8].map(i=>{
    const col=m.slice(i,i+3),squared=col.reduce((n,v)=>n+v*v,0);
    return col.map(v=>v/squared);
  });
}
// The source used a triangulated height grid. Preserve the original rise and fit the
// sub-metre difference against the current, cached Terrarium tile at the seven turns.
const residual=source.routeDEMHeights.map((value,i)=>value-source.routeSourceHeights[i]
  -(source.demAnchorHeight-source.sourceAnchorHeight));
function adjustment(x,z){
  let closest=Infinity,result=0;
  for(let i=1;i<route.length;i++){
    const a=route[i-1],b=route[i],dx=b[0]-a[0],dz=b[1]-a[1];
    const t=Math.max(0,Math.min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)));
    const distance=(x-a[0]-t*dx)**2+(z-a[1]-t*dz)**2;
    if(distance<closest){closest=distance;result=residual[i-1]*(1-t)+residual[i]*t;}
  }
  return result;
}
function put([x,y,z],color,offset){
  extend(...project([x,-z]));
  triangles.push([x,-z,y-source.sourceAnchorHeight+(offset??adjustment(x,z)),...color]);
}
function paintSign(item,offset){
  const [w,h]=item.size;
  function rect(x1,y1,x2,y2,depth,hex){
    const p=[[x1,y1],[x1,y2],[x2,y2],[x2,y1]].map(([x,y])=>
      transform(item.matrix,[(x/256-.5)*w,(.5-y/66)*h,depth]));
    const rgb=hex.match(/../g).map(v=>parseInt(v,16));
    for(const i of [0,1,2,0,2,3])put(p[i],rgb,offset);
  }
  rect(0,0,256,66,.003,'453b30');
  for(const r of [[4,4,252,6],[4,60,252,62],[4,6,6,60],[250,6,252,60]])rect(...r,.009,'ad915b');
  for(const r of source.signGlyphs[item.sign])rect(...r,.015,'e5c68a');
}
const lampTints=new Set(['b33c37','b44435']);
const paneTints=new Set(['9f8a63','afd0b3','a6ad87']);
const warmWood=new Set(['795840','403d34','634c3c','503d34','725945','514e46','494e47']);
const mix=(a,b,t)=>a.map((v,i)=>Math.round(v+(b[i]-v)*t));
function paperLantern(item,offset,teahouse){
  const m=item.matrix;
  const radiusX=Math.hypot(m[0],m[2])*(teahouse?1.48:1.26);
  const radiusZ=Math.hypot(m[8],m[10])*(teahouse?1.48:1.26);
  const halfHeight=m[5]*(teahouse?1.34:1.19);
  lanterns.push([m[12],-m[14],m[13]-source.sourceAnchorHeight+offset,Math.max(radiusX,radiusZ)].map(v=>round(v,1e4)));
  const position=(a,y,r)=>[m[12]+Math.cos(a)*r*radiusX,m[13]+y*halfHeight,m[14]+Math.sin(a)*r*radiusZ];
  // Latitude bands trace the curved bamboo ribs. Dark meridians are narrow folds in the red paper.
  const profile=[
    [-1.06,.35],[-.94,.49],[-.82,.69],[-.55,.89],[-.5,.87],[-.46,.92],
    [-.08,.995],[0,.98],[.06,1],[.46,.92],[.51,.89],[.56,.88],[.83,.66],[.96,.45],[1.04,.34],
  ];
  const divisions=36;
  const band=(lo,hi,paint)=>{
    for(let j=0;j<divisions;j++){
      const vertex=(ring,k)=>{
        const a=2*Math.PI*k/divisions,rib=k%3===0;
        return [position(a,ring[0],ring[1]),paint(ring[0],a,rib)];
      };
      const points=[vertex(lo,j),vertex(lo,j+1),vertex(hi,j+1),vertex(hi,j)];
      for(const i of [0,1,2,0,2,3])put(points[i][0],points[i][1],offset);
    }
  };
  const paper=(v,a,rib)=>{
    const core=(1-Math.min(1,Math.abs(v))**1.75)*(.94+.06*Math.cos(a+.3));
    const shell=mix([179,29,35],[255,88,43],core);
    return rib||[-.5,0,.51].includes(v)?mix(shell,[179,32,27],.27):shell;
  };
  for(let j=1;j<profile.length;j++)band(profile[j-1],profile[j],paper);
  const brass=(_v,a)=>mix([145,75,31],[255,190,83],.5+.5*Math.cos(a));
  band([1.035,.34],[1.12,.32],brass);
  band([1.12,.32],[1.12,0],brass);
  band([-1.10,.32],[-1.035,.35],brass);
  band([-1.10,.32],[-1.10,0],()=>[255,182,78]);
  // Golden knot and short silk tassel, attached to the original suspension axis.
  band([-1.24,.061],[-1.1,.055],()=>[239,172,73]);
  band([-1.53,.095],[-1.24,.048],()=>[191,53,35]);
}
function glowOnWood(rgb,position,normal,lamps){
  let weight=0;
  for(const lamp of lamps){
    const dx=lamp[0]-position[0],dy=lamp[1]-position[1],dz=lamp[2]-position[2];
    const d2=dx*dx+dy*dy+dz*dz;
    if(d2>10)continue;
    const toward=Math.max(0,(dx*normal[0]+dy*normal[1]+dz*normal[2])/Math.sqrt(Math.max(.01,d2)));
    weight=Math.max(weight,(1-d2/10)**2*(.18+.82*toward));
  }
  return mix(rgb,[232,130,58],weight*.47);
}
function lightWoodBox(item,offset,lamps){
  const m=item.matrix,dims=[0,4,8].map(i=>Math.hypot(...m.slice(i,i+3))),color=toLinear(item.tint);
  // Extra vertices let each lantern illuminate a small section of the longer balcony or fascia.
  for(let face=0;face<3;face++)for(const side of [-1,1]){
    const u=(face+1)%3,v=(face+2)%3,nu=Math.ceil(dims[u]/1.2),nv=Math.ceil(dims[v]/1.2);
    const normal=m.slice(face*4,face*4+3).map(x=>side*x/dims[face]),base=light(color,normal);
    const grid=[];
    for(let j=0;j<=nv;j++)for(let i=0;i<=nu;i++){
      const p=[0,0,0];p[face]=side*.5;p[u]=i/nu-.5;p[v]=j/nv-.5;
      const point=transform(m,p);grid.push([point,glowOnWood(base,point,normal,lamps)]);
    }
    for(let j=0;j<nv;j++)for(let i=0;i<nu;i++){
      const a=j*(nu+1)+i,b=a+1,c=b+nu+1,d=c-1;
      for(const k of [a,b,c,a,c,d])put(grid[k][0],grid[k][1],offset);
    }
  }
}
// Tint only the reusable shop-house finishes. Identifiable buildings, signs, lanterns,
// greenery, the stone foundations and the stair flight keep their recovered materials.
const plaster = new Set(['b69170','d0b18b','976952','a98869','b48265','c5a278','c3a081',
  '9c775f','ccb793','b09073','a77658','bda888','bd9877','bdad93']);
const tiles = new Set(['59666a','716050','766156','566669','704d43','5d6261','794d46',
  '52615e','6c615d','634f45','646967','555f5b','79584e','64706d']);
const sash = new Set(['5f7165','63493b','817961']);
function streetFinish(item, style){
  if(!style)return item.tint;
  const src=item.tint;
  const finish = plaster.has(src)?style.wall : tiles.has(src)?style.roof :
    sash.has(src)?style.frame : paneTints.has(src)||src==='aab5a6'?style.glass :
    src==='a05545'?style.awning : null;
  if(!finish)return src;
  // Let the hillside street retain its weathered pigment underneath the illustrated wash.
  const old=src.match(/../g).map(v=>parseInt(v,16)), paint=finish.slice(1).match(/../g).map(v=>parseInt(v,16));
  return mix(old,paint,.72).map(v=>v.toString(16).padStart(2,'0')).join('');
}
for(const group of groups){
  const first=triangles.length,base=group.meshes[0].matrix;
  // Rigid shop walls, windows, lamps and sign move as one. Individual treads follow the DEM correction.
  const offset=group.id==='steps'?undefined:adjustment(base[12],base[14]);
  const teahouse=group.id==='shop-5';
  const streetShop=!teahouse&&group.id.startsWith('shop-');
  const style=streetShop||group.id==='neighbor-2' ? buildingStyle('jiufen/'+group.id,
    {building:streetShop?'retail':'residential'}) : null;
  const localLights=teahouse?group.meshes.filter(m=>lampTints.has(m.tint)).map(m=>m.matrix.slice(12,15)):[];
  for(const item of group.meshes){
    if(lampTints.has(item.tint)){paperLantern(item,offset,teahouse);continue;}
    if(teahouse&&item.geometry===1&&warmWood.has(item.tint)){lightWoodBox(item,offset,localLights);continue;}
    if(item.sign){paintSign(item,offset);continue;}
    const {positions,normals,colors,indices}=geometries[item.geometry];
    const color=toLinear(streetFinish(item,style)),basis=normalMatrix(item.matrix);
    const count=indices?.length??positions.length/3;
    for(let j=0;j<count;j++){
      const i=(indices?.[j]??j)*3,n=normals.slice(i,i+3);
      const normal=unit([0,1,2].map(k=>basis.reduce((acc,v,axis)=>acc+v[k]*n[axis],0)));
      // The kit's hipped-roof triangles are double-sided. Bake the exterior sky-facing face.
      if(item.geometry!==0&&!indices&&normal[1]<-.001&&normal[1]>-.9999&&!colors)
        for(let k=0;k<3;k++)normal[k]*=-1;
      const rgb=colors?color.map((v,k)=>v*colors[i+k]):color;
      const position=transform(item.matrix,positions.slice(i,i+3));
      // The recovered tread has three top quads, one riser, then two outside skirts.
      // Extend just the hidden skirt bottoms through the DEM on the low side of a step.
      const corner=j%6;
      if(group.id==='steps'&&j%36>=24&&(corner===2||corner>=4))position[1]-=.72;
      let tint=light(rgb,normal);
      if(teahouse&&paneTints.has(item.tint)){
        // The three original glazing colors identify front shop, upper sash and side windows.
        const shades={'9f8a63':[247,179,94],'afd0b3':[255,202,127],'a6ad87':[230,164,91]};
        const warmth=.65+.27*(positions[i+1]+.5)+.06*Math.sin(item.matrix[12]+item.matrix[14]);
        tint=mix([164,94,58],shades[item.tint],warmth);
      }
      put(position,tint,offset);
    }
  }
  parts.push({id:group.id,name:group.name,first,count:triangles.length-first,at});
}
const bytes=Buffer.alloc(triangles.length*16);
for(const [i,[x,y,z,r,g,b]] of triangles.entries()){
  if(![x,y,z,r,g,b].every(Number.isFinite))throw Error('Invalid source vertex');
  const j=i*16;
  bytes.writeFloatLE(x,j);bytes.writeFloatLE(y,j+4);bytes.writeFloatLE(z,j+8);
  bytes[j+12]=r;bytes[j+13]=g;bytes[j+14]=b;bytes[j+15]=255;
}
const center=project(at),bounds=[west,south,east,north];
const landmarkSites=[
  {name:'阿妹茶樓',osmType:'node',osmId:'2071356259',point:[121.843663,25.108535]},
  {name:'昇平戲院',osmType:'way',osmId:'272732655',point:[121.843249,25.108518]},
];
const metadata={name:'九份',landmark:'豎崎路、阿妹茶樓與昇平戲院',format:'recovered-mesh',center,bounds,sizeMeters:90,
  landmarkIds:[],landmarkSites,footprint,camera:{center,bearing:143,pitch:49,zoom:19.55,mobileZoom:18.85},
  sources:[
    {title:'OpenStreetMap・豎崎路階梯路線及鄰房輪廓',url:'https://www.openstreetmap.org/?mlat=25.10853&mlon=121.84366#map=19/25.10853/121.84366'},
    ...landmarkSites.map(s=>({title:s.name,url:'https://www.openstreetmap.org/'+s.osmType+'/'+s.osmId})),
    {title:'Mapzen Terrarium・九份山坡地形',url:'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/14/13737/7010.png'},
  ]};
const scene={meta,buildings:[],lawns:[],sand:[],water:[],roads:[],walk:[],paths:[],trees:[],species:[],routes:[],
  lanterns,people:[],centerlines:[{name:'豎崎路',p:route.map(([x,z])=>[x,-z])}],pois:[]};
async function output(name,data){
  if(process.argv.includes('--check')){
    if(!(await readFile(local(name))).equals(Buffer.from(data)))throw new Error('Rebuild '+name);
  }else await writeFile(local(name),data);
}
for(const [name,obj] of [['scene.json',scene],['metadata.json',metadata],['map-mesh.json',{parts}]]){
  await output(name,JSON.stringify(obj)+'\n');
}
await output('map-mesh.bin',bytes);
console.log(parts.length+' terrain-registered mesh parts, '+triangles.length/3+' triangles, '+bytes.length+' bytes');
