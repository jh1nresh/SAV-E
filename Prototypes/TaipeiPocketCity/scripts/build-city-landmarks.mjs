import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {gzipSync} from 'node:zlib';
import {landmark} from '../../taiwan-landmarks-map/landmarks.js';
import * as T from '../../taiwan-landmarks-map/vendor/three.module.min.js';

const shapes=[
  {id:'chiang-kai-shek',name:'中正紀念堂',center:[121.521820,25.034637],ground:22.8,top:77.38,xz:1.19,style:0,bearing:-24,pitch:44},
  {id:'grand-hotel',name:'圓山大飯店',center:[121.526290,25.078622],ground:38.0,top:102.22,xz:1.12,style:1,bearing:-22,pitch:44},
  {id:'palace-museum',name:'國立故宮博物院',center:[121.548544,25.102274],ground:43.7,top:64.58,xz:1.05,style:2,bearing:-12,pitch:44},
];
const base=path.dirname(fileURLToPath(import.meta.url));
const destination=process.argv[2]??path.join(base,'../data/city-streets');
const directory=path.join(destination,'landmark');
fs.mkdirSync(directory,{recursive:true});
for(const item of shapes){
  const [lon,lat]=item.center;
  const mx=(lon+180)/360;
  const my=(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2;
  const m=1/(40075016.686*Math.cos(lat*Math.PI/180));
  const model=landmark({id:item.id,hero:[0,0]},()=>0,()=>0);
  model.updateMatrixWorld(true);
  const limits=new T.Box3().setFromObject(model);
  const vertical=(item.top-item.ground)/limits.max.y;
  const vertex=new T.Vector3(), values=[];
  model.traverse(mesh=>{
    if(!mesh.isMesh)return;
    const pos=mesh.geometry.getAttribute('position');
    const index=mesh.geometry.getIndex();
    const color=mesh.material.color.getHex()+2;
    for(let i=0;i<(index?.count??pos.count);i++){
      vertex.fromBufferAttribute(pos,index?index.getX(i):i).applyMatrix4(mesh.matrixWorld);
      values.push(vertex.x*item.xz,-vertex.z*item.xz,item.ground+vertex.y*vertical,item.ground,item.top-item.ground,color);
    }
  });
  const buffer=new Float32Array(values);
  const extent=.0013;
  item.mx=mx;item.my=my;item.m=m;item.verts=buffer.length/6;
  item.box=[lon-extent,lat-extent,lon+extent,lat+extent];
  const file=path.join(directory,item.id+'.bin.gz');
  fs.writeFileSync(file,gzipSync(Buffer.from(buffer.buffer),{level:5}));
  console.log(item.name,item.verts/3,'triangles',item.ground,item.top);
}
fs.writeFileSync(path.join(destination,'landmarks.json'),JSON.stringify(shapes)+'\n');
