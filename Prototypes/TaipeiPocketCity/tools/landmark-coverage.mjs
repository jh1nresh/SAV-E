// Inventory the actual promoted pins plus public classes with a recognisable built form.
// A source pin or a model file alone never closes visual review.
import {readFileSync, realpathSync, existsSync, mkdirSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {cityLandmarks,districtLandmarks} from '../taipei-priority-places.js';

const tools=path.dirname(fileURLToPath(import.meta.url));
const categories=new Set(['museum','memorial','monument','theatre','arts_centre','attraction','zoo']);
const models={
  'poi/way/1159328965':['101','taipei101-tower.js'],
  'poi/way/1052759757':['chiang-kai-shek','data/city-streets/landmark/chiang-kai-shek.bin.gz'],
  'poi/way/557039975':['grand-hotel','data/city-streets/landmark/grand-hotel.bin.gz'],
  'poi/way/827791918':['palace-museum','palace-museum.js'],
  'poi/way/229061328':['songyan','data/city-streets/landmark/songyan-v5.bin.gz'],
  'poi/way/189788192':['sun-yat-sen-hall','sun-yat-sen-hall.js'],
};
const focalViews={
  'poi/way/189788192':{center:[121.56029,25.03998],bearing:-9,pitch:56,near:18.05},
  'poi/way/1159328965':{bearing:-25,pitch:54,near:17.55},
  'poi/way/229061328':{center:[121.56149,25.04350],bearing:-65,pitch:42,near:17.62},
};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');

// Match local ESM and worker references that are also followed by the iOS packager.
// The audit runs against the packaged directory, where the packager itself is absent.
const localModule=/(?:\bfrom\s*|\bimport\s*\(?\s*|\bnew URL\(\s*)['"](\.{1,2}\/[^'"?\s]+?\.m?js)(?:\?[^'"]*)?['"]/g;

function rendererFingerprint(root){
  const pending=['app.js','assets/maplibre-gl-worker.mjs','index.html','style.css','assets/maplibre-gl.css',
    'assets/base-style.json','data/survey-index.json','data/city-streets/index.json','data/city170-material.png'];
  const hashes=new Map();
  while(pending.length){
    const name=pending.pop();
    if(hashes.has(name))continue;
    const file=path.join(root,name);
    if(!existsSync(file))return null;
    const bytes=readFileSync(file);
    hashes.set(name,sha(bytes));
    if(!/\.m?js$/.test(name))continue;
    for(const [,ref] of bytes.toString('utf8').matchAll(localModule)){
      const dependency=path.join(path.dirname(name),ref);
      if(dependency.startsWith('../'))return null;
      pending.push(dependency);
    }
  }
  const h=createHash('sha256');
  for(const name of [...hashes.keys()].sort())h.update(name+'\0'+hashes.get(name)+'\n');
  return h.digest('hex');
}

function fingerprint(root,asset,renderer){
  if(!renderer)return null;
  const files=[asset];
  if(asset.includes('/city-streets/landmark/')||asset==='palace-museum.js')files.push('data/city-streets/landmarks.json');
  if(asset.includes('songyan'))files.push('data/city-streets/songyan-v5.json.gz');
  if(asset==='taipei101-tower.js')files.push('data/landmark-101.json');
  const h=createHash('sha256').update(renderer+'\n');
  for(const name of files){const f=path.join(root,name);if(!existsSync(f))return null;h.update(name+'\0'+sha(readFileSync(f))+'\n');}
  return h.digest('hex');
}

export function approved(receipt,modelDigest,cameras,evidence){
  if(!modelDigest||receipt?.digest!==modelDigest||!receipt.reference?.startsWith('https://'))return false;
  if(receipt.views?.far?.sha256===receipt.views?.near?.sha256)return false;
  return ['far','near'].every(k=>{
    const view=receipt.views?.[k];
    if(view?.camera!==cameras[k]||!/^[-a-z0-9]+\.webp$/.test(view?.file??''))return false;
    const f=path.join(evidence,view.file);
    if(!existsSync(f)||sha(readFileSync(f))!==view.sha256)return false;
    // Pillow is also used by the atlas builder. Decode the pixels, not just the RIFF header.
    const decode=spawnSync('python3',['-c',[
      'import sys',
      'from PIL import Image',
      'with Image.open(sys.argv[1],formats=["WEBP"]) as image:',
      '    image.load()',
      '    sys.exit(0 if image.width and image.height else 1)',
    ].join('\n'),f],{stdio:'ignore',timeout:5000});
    return decode.status===0;
  });
}

export function inventory(data,receipts={},evidence=path.join(tools,'landmark-evidence')){
  const promoted=new Set([...cityLandmarks,...districtLandmarks]);
  const places=JSON.parse(gunzipSync(readFileSync(path.join(data,'city-place-index.json.gz'))));
  const candidates=places.features.filter(f=>f.properties.name&&(promoted.has(f.id)||models[f.id]||categories.has(f.properties.category)));
  const root=path.dirname(data);
  const renderer=rendererFingerprint(root);
  const hasHallRenderer=readFileSync(path.join(root,'survey-layer.js'),'utf8').includes("from './sun-yat-sen-hall.js'");
  const rows=candidates.map(f=>{
    const id=f.id,{name,district,category}=f.properties;
    const registered=models[id];
    // The memorial module is a separate PR. Treat the main branch's ordinary survey
    // building as pending until that renderer actually imports the authored asset.
    const model=registered?.[0]==='sun-yat-sen-hall'&&!hasHallRenderer ? null : registered;
    const digest=model&&fingerprint(root,model[1],renderer);
    const pose=focalViews[id]??{},center=pose.center??f.geometry.coordinates;
    const camera=z=>'?view='+[...center,z].join(',')+'&bearing='+(pose.bearing??0)+'&pitch='+(pose.pitch??45);
    const cameras={far:camera(16.9),near:camera(pose.near??18.15)};
    const priority=cityLandmarks.includes(id)?1:districtLandmarks.includes(id)?2:3;
    return {id,name,district,category,priority,model:model?.[0]??null,digest:digest??null,cameras,
      state:approved(receipts[id],digest,cameras,evidence)?'雙鏡位已對照':digest?'已有專屬模型，待雙鏡位複核':
        model?'缺少預期專屬資產':'待核對造型'};
  }).sort((a,b)=>a.priority-b.priority||a.id.localeCompare(b.id));
  const found=new Set(rows.map(r=>r.id));
  return {rows,missingPriority:[...promoted].filter(id=>!found.has(id))};
}

export function report(data,output,base='http://127.0.0.1:42104/taipei-pocket-city/',evidence=path.join(tools,'landmark-evidence')){
  mkdirSync(output,{recursive:true});
  const receiptsFile=path.join(evidence,'reviews.json');
  const receipts=existsSync(receiptsFile)?JSON.parse(readFileSync(receiptsFile)): {};
  const {rows,missingPriority}=inventory(data,receipts,evidence);
  const counts={};for(const r of rows)counts[r.state]=(counts[r.state]??0)+1;
  const current=new Map(rows.map(row=>[row.id,row]));
  const staleReviews=Object.keys(receipts).filter(id=>current.get(id)?.state!=='雙鏡位已對照');
  const missingModels=rows.filter(row=>row.model&&!row.digest).map(row=>row.id);
  const summary={candidates:rows.length,missingPriority,missingModels,staleReviews,counts};
  writeFileSync(path.join(output,'taipei-landmark-coverage.json'),JSON.stringify({...summary,rows},null,1)+'\n');
  const link=(query)=>new URL(query,base).href;
  const lines=['# 台北地標造型複核','',
    '收錄地圖優先標記、已登錄的地標模型，以及具名的博物館、紀念設施、劇場、藝文中心、動物園與景點。每列依公開地點 ID 追蹤。公園應按園景特徵檢查。','',
    '兩個鏡位使用相同中心、方向和俯角。模型與渲染版本、來源參照、兩張畫面都吻合才計入已對照。','',
    ...Object.entries(counts).map(([key,value])=>'- '+key+' '+value+' 筆'),'',
    '|地點|行政區|檢查狀態|實際地圖鏡位|','|---|---|---|---|'];
  for(const r of rows)lines.push('|'+[r.name.replaceAll('|','／'),r.district,r.state,
    '[街區]('+link(r.cameras.far)+') · [近看]('+link(r.cameras.near)+')'].join('|')+'|');
  writeFileSync(path.join(output,'taipei-landmark-coverage.md'),lines.join('\n')+'\n');
  return summary;
}
if(process.argv[1]&&existsSync(process.argv[1])&&realpathSync(process.argv[1])===fileURLToPath(import.meta.url)){
  const [data,output,preview,evidence]=process.argv.slice(2);
  if(!data||!output)throw Error('Usage: node tools/landmark-coverage.mjs <packaged PocketCity/data> <output directory> [preview URL] [evidence directory]');
  const summary=report(data,output,preview,evidence);
  console.log(JSON.stringify(summary));
  if(summary.missingPriority.length||summary.missingModels.length||summary.staleReviews.length)process.exitCode=1;
}
