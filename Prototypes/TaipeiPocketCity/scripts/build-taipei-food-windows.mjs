// node scripts/build-taipei-food-windows.mjs <PocketCity/data> > taipei-food-window-evidence.js
import {readFileSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {completeFrontagePack} from '../taipei-frontage-pack.js';
import {advertisedFoodWindow,cuisineWindow} from '../shop-food-windows.js';

const root=process.argv[2];
if(!root)throw Error('Pass the PocketCity/data directory containing city170 and city170-frontages.');
const packets=dir=>readdirSync(dir).filter(name=>/^p\d+_\d+\.json\.gz$/.test(name)).sort();
const load=(dir,name)=>JSON.parse(gunzipSync(readFileSync(join(dir,name))));
const frontage=join(root,'city170-frontages'), city=join(root,'city170');
const walls=new Map();
for(const name of packets(frontage)){
  for(const row of completeFrontagePack(name.split('.')[0],load(frontage,name)))walls.set(row.id,row);
}
const groups=new Map();
for(const name of packets(city)){
  for(const feature of load(city,name).features.features){
    const {category,cuisine,name:businessName}=feature.properties;
    const wall=walls.get(feature.id);
    if(!wall||wall.category!==category)continue;
    const cue=cuisineWindow(category,cuisine)??(wall.name===businessName?advertisedFoodWindow(category,businessName):null);
    if(!cue)continue;
    const [source,entity,id]=feature.id.split('/');
    if(source!=='poi'||!['node','way','relation'].includes(entity)||!/^\d+$/.test(id))throw Error(feature.id);
    const key=[category,cue,entity].join('|');
    if(!groups.has(key))groups.set(key,new Set());
    groups.get(key).add(id);
  }
}
console.log('// Generated from the 170 m OpenStreetMap POI packs and located frontages by scripts/build-taipei-food-windows.mjs.');
console.log('// Each display matches an exact POI ID and category with cuisine tags or a matching advertised specialty.');
console.log('const groups=[');
for(const [key,ids] of [...groups].sort(([a],[b])=>a.localeCompare(b,'en'))){
  const row=key.split('|');
  console.log('  '+JSON.stringify([...row,[...ids].sort((a,b)=>Number(a)-Number(b)).join(' ')])+',');
}
console.log('];');
console.log(`const cues=new Map();
for(const [category,cue,entity,ids] of groups){
  for(const id of ids.split(' '))cues.set(category+'/'+entity+'/'+id,cue);
}
export function mappedFoodWindow(row){
  return row.id.startsWith('poi/')?cues.get(row.category+'/'+row.id.slice(4)):undefined;
}`);
