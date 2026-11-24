// Refresh only the generic buildings in the Taiwanese Pocket City scene packs.
// POCKET_CITY_SKILL=~/.codex/skills/pocket-city node tools/style-taiwan-landmark-neighbors.mjs [--check] [city-id]
import {execFileSync} from 'node:child_process';
import {readFile,writeFile,readdir,mkdtemp,rename,unlink,rmdir} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import {buildingStyle,storefrontStyle} from '../taiwan-building-style.js';
import {exportMesh} from './export-pocket-mesh.mjs';

const root=fileURLToPath(new URL('../cities/',import.meta.url));
const skill=process.env.POCKET_CITY_SKILL || join(homedir(),'.codex','skills','pocket-city');
const readJSON=async path=>JSON.parse(await readFile(path,'utf8'));
const flag='taiwanStreetFinish';
const check=process.argv.includes('--check');
const target=process.argv.slice(2).find(arg=>arg!=='--check');
const rows=(await readJSON(join(root,'catalog.json'))).filter(r=>/縣$|市$/.test(r.area)&&(!target||target===r.id));
if(!rows.length)throw Error('No matching Taiwanese scene');

// Where a commercial POI is actually mapped inside this footprint, use the shop finish
// without adding a tenant to buildings with unknown occupants or to courtyard interiors.
function inside(p,ring){
  let hit=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const [a,b]=ring[j],[c,d]=ring[i];
    if((b>p.y)!==(d>p.y)&&p.x<(c-a)*(p.y-b)/(d-b)+a)hit=!hit;
  }
  return hit;
}
function partBytes(mesh,part){
  return mesh.subarray(part.first*16,(part.first+part.count)*16);
}
function validateProtected(before,after,names){
  for(const name of names){
    // Landmark models follow generic buildings; an OSM label can share the landmark name.
    const p=before.parts.findLast(p=>p.name===name),q=after.parts.findLast(p=>p.name===name);
    if(!p||!q||!partBytes(before.buffer,p).equals(partBytes(after.buffer,q)))
      throw Error('Authored landmark geometry or colour changed: '+name);
  }
}
async function build(folder,city,landmarks){
  const tmp=await mkdtemp(join(folder,'.street-finishes-'));
  const page=join(tmp,'index.html'), config=join(tmp,'city.json'), mesh=join(tmp,'map-mesh.bin'), index=join(tmp,'map-mesh.json');
  try{
    await writeFile(config,JSON.stringify(city,null,2)+'\n');
    execFileSync('python3',[join(skill,'scripts/build.py'),'--scene',join(folder,'scene.json'),
      '--city',config,'--landmarks',join(folder,'landmarks.js'),'--out',page],{stdio:'pipe'});
    const html=(await readFile(page,'utf8')).split(/\r?\n/).map(line=>line.trimEnd()).join('\n').trimEnd()+'\n';
    await writeFile(page,html);
    const before={buffer:await readFile(join(folder,'map-mesh.bin')),parts:(await readJSON(join(folder,'map-mesh.json'))).parts};
    const next=exportMesh(html);
    validateProtected(before,next,landmarks.map(l=>l.name));
    await writeFile(mesh,next.buffer);
    await writeFile(index,JSON.stringify({parts:next.parts})+'\n');
    for(const file of [config,page,mesh,index])await rename(file,join(folder,file.slice(tmp.length+1)));
  }finally{
    for(const f of [config,page,mesh,index])await unlink(f).catch(e=>{if(e.code!=='ENOENT')throw e;});
    await rmdir(tmp);
  }
}

for(const row of rows){
  const folder=join(root,row.id);
  const meta=await readJSON(join(folder,'metadata.json'));
  if(meta.format==='recovered-mesh'){
    execFileSync(process.execPath,[join(folder,'build.mjs'),...(check?['--check']:[])]);
    console.log(row.id+' recovered shop finishes');
    continue;
  }
  const scene=await readJSON(join(folder,'scene.json')), city=await readJSON(join(folder,'city.json'));
  const oldConfig=JSON.stringify(city);
  // Read the registered ids themselves; primary pins do not list annexes, secondary gates, etc.
  const landmarks=runInNewContext((await readFile(join(folder,'landmarks.js'),'utf8'))+
    '\nLANDMARKS.map(l=>({name:l.name,ids:l.ids||[]}))',{SCENE:scene},{timeout:1500,contextCodeGeneration:{strings:false,wasm:false}});
  const manual=Object.fromEntries(Object.entries(city.buildings||{}).filter(([,s])=>!s[flag]));
  const keep=new Set([...row.landmarkIds,...landmarks.flatMap(l=>l.ids),...Object.keys(manual)]);
  const saved=(await readdir(folder)).find(n=>/^osm(?:-bbox)?\.json$/.test(n));
  const osm=await readJSON(join(folder,saved));
  const tags=new Map(osm.elements.filter(e=>e.tags).map(e=>[e.type[0]+e.id,e.tags]));
  const styles={...manual};
  let count=0;
  for(const b of scene.buildings){
    if(keep.has(b.id)||keep.has(b.of))continue;
    const id=b.of||b.id, observed={...tags.get(id),...tags.get(b.id)};
    const tenant=scene.pois.find(p=>inside(p,b.ring)&&!(b.holes||[]).some(h=>inside(p,h))&&
      storefrontStyle(p.kind,p.name,{}).detail!=='display');
    const kind=observed.shop||observed.amenity||tenant?.kind;
    const shop=observed.shop&&observed.shop!=='no'||tenant||storefrontStyle(kind,id,{}).detail!=='display';
    const style=buildingStyle(id,observed,{height:b.h||b.lv*(city.level||3.2),width:b.obb.L,depth:b.obb.W,shop});
    const street=storefrontStyle(kind,tenant?.name||id,style);
    styles[b.id]={[flag]:true,wall:style.wall,roofColour:style.roof,flatRoof:style.roof,frame:style.frame,
      trim:style.trim,glass:[style.glass],dark:style.frame,wood:style.frame,
      ...(shop?{shop:'poi',shopWall:style.wall,awnings:[street.awning],fascia:[street.sign]}:{})};
    // Keep the source's scoped finishes (e.g. the red pantile house roofs near the Tainan
    // fort and the Tamsui university facade). Our derived coat supplies missing channels.
    for(const rule of city.styles?.rules||[]){
      const when=rule.if||{};
      if(Object.keys(when).length!==1||!Array.isArray(when.type)||!when.type.includes(b.type))continue;
      for(const field of Object.keys(rule.set))delete styles[b.id][field];
      if(!rule.more)break;
    }
    count++;
  }
  if(count||city.buildings)city.buildings=styles;
  if(check&&JSON.stringify(city)!==oldConfig)throw Error(row.id+': regenerate neighborhood finishes');
  if(!check&&count)await build(folder,city,landmarks);
  console.log(row.id+' '+count+' generic building parts; '+landmarks.length+' protected models');
}

if(!check)execFileSync('python3',['-B',fileURLToPath(new URL('./city_catalog.py',import.meta.url))]);
