// Optional source recapture. The checked-in source pack is sufficient for build.mjs.
// node recover.mjs /path/to/original/taiwan-landmarks-map
import {readFile,writeFile} from 'node:fs/promises';
import {gzipSync} from 'node:zlib';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const legacy=resolve(process.argv[2]),url=file=>pathToFileURL(join(legacy,file)).href;
const T=await import(url('vendor/three.module.min.js'));
const source=await readFile(join(legacy,'landmarks.js'),'utf8');
const dataText=await readFile(join(legacy,'data/jiufen.json'),'utf8'),data=JSON.parse(dataText);
const importText=text=>import('data:text/javascript;base64,'+Buffer.from(text).toString('base64'));
const replaceImport=text=>text.replace("'./vendor/three.module.min.js'",JSON.stringify(url('vendor/three.module.min.js')));
const scenery=await readFile(join(legacy,'scenery.js'),'utf8');
const {elevation}=await importText(replaceImport(scenery).replace("'./landmarks.js'",JSON.stringify(url('landmarks.js')))+'\nexport {elevation};');
// Keep the original parent groups and repetitions so a renderer can identify the stairs and each shop.
if(!source.includes('  packShuqi(street);'))throw Error('Unknown source model');
const {landmark}=await importText(replaceImport(source).replace('  packShuqi(street);',''));
globalThis.document={createElement:()=>{const canvas={};canvas.getContext=()=>({fillRect(){},strokeRect(){},fillText(text){canvas.label=text;}});return canvas;}};
const height=(x,z)=>elevation(data,x,z);
const model=landmark(data,height,height);model.updateMatrixWorld(true);
const children=model.children[0].children;
if(children.length!==37)throw Error('Unexpected number of street groups: '+children.length);
const geometries=[], geometriesById=new Map(),groups=[],polygons=[];
const round=n=>Math.round(n*1e6)/1e6;
const array=values=>Array.from(values,round);
for(const [index,part] of children.entries()){
  const isShop=index>=1&&index<=14,neighbor=index===15||index===16;
  const name=index===0?'豎崎路石階':index===5?'阿妹茶樓':isShop?'坡地店屋 '+index:index===15?'昇平戲院':index===16?'街廓鄰房':'露台植栽';
  const id=index===0?'steps':isShop?'shop-'+index:neighbor?'neighbor-'+(index-14):'gardens';
  let row=groups.find(item=>item.id===id);
  if(!row){row={id,name,meshes:[]};groups.push(row);}
  if(isShop||neighbor){
    const plinth=part.children[0],box=plinth.geometry;
    box.computeBoundingBox();
    const a=box.boundingBox.min,b=box.boundingBox.max;
    polygons.push([[a.x,a.z],[a.x,b.z],[b.x,b.z],[b.x,a.z]].map(([x,z])=>{
      const p=new T.Vector3(x,0,z).applyMatrix4(plinth.matrixWorld);return [p.x,-p.z];}));
  }
  part.traverse(mesh=>{
    if(!mesh.isMesh)return;
    const item={matrix:array(mesh.matrixWorld.elements),tint:mesh.material.color.getHexString()};
    if(mesh.material.map){item.sign=mesh.material.map.image.label;item.size=[mesh.geometry.parameters.width,mesh.geometry.parameters.height];}
    else{
      const g=mesh.geometry;
      if(!geometriesById.has(g)){
        geometriesById.set(g,geometries.length);
        geometries.push({positions:array(g.attributes.position.array),normals:array(g.attributes.normal.array),
          ...(g.attributes.color&&{colors:array(g.attributes.color.array)}),indices:g.index?array(g.index.array):null});
      }
      item.geometry=geometriesById.get(g);
    }
    row.meshes.push(item);
  });
}
const {lat,lon,hero,shuqi}=data;
const control={lat,lon,hero,route:shuqi.route,width:shuqi.width,polygons};
const helper=new URL('./recover-support.py',import.meta.url);
const extras=JSON.parse(execFileSync(process.env.PYTHON??'python3',[helper.pathname],{input:JSON.stringify(control)}));
const checksum=s=>createHash('sha256').update(s).digest('hex');
const pack={version:1,sourceSha256:{landmarks:checksum(source),scenery:checksum(scenery),data:checksum(dataText)},
  lat,lon,hero,route:shuqi.route,width:shuqi.width,sourceAnchorHeight:height(...hero),routeSourceHeights:shuqi.route.map(p=>height(...p)),
  ...extras,groups,geometries};
await writeFile(new URL('./source.json.gz',import.meta.url),gzipSync(JSON.stringify(pack),{level:9}));
console.log(groups.length+' groups, '+geometries.length+' source meshes');
