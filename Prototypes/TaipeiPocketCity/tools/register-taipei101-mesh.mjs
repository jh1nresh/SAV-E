// Rebuild from the accepted, frozen Pocket City HTML. Its projection, all model
// functions and all 11 authored/OSM model groups are run by the shared exporter.
import {readFile,writeFile} from 'node:fs/promises';
import {gzipSync,gunzipSync} from 'node:zlib';
import {pathToFileURL} from 'node:url';
import {realpathSync} from 'node:fs';
import {exportMesh} from './export-pocket-mesh.mjs';

const input=new URL('./fixtures/taipei101-pocket-city.html.gz',import.meta.url);
const output=new URL('../assets/taipei101-pocket-city.bin.gz',import.meta.url);
const radians=deg=>deg*Math.PI/180;
const merc=(lon,lat)=>[(lon+180)/360,(1-Math.asinh(Math.tan(radians(lat)))/Math.PI)/2];
// survey landmark-101.json, at the centre of the tower (OSM way 198637969).
const anchor={mx:.8376800257453572,my:.42813775317984215,m:2.754036392361926e-8,ground:4.939998465560478};
export function registerScene(html){
  const meta=JSON.parse(html.match(/<script type="application\/json" id="sceneMeta">([^<]+)<\/script>/)[1]);
  const angle=radians(meta.rotation),eastDegree=111320*Math.cos(radians(meta.lat));
  const {buffer,parts}=exportMesh(html);
  const data=Buffer.alloc(buffer.length/16*24);
  for(const part of parts){
    const breeze=part.name==='微風南山';
    // Only the two cropped, adjoining Breeze volumes connect to a taller,
    // continuous building outside the source plot. Match the surveyed roof
    // breaks there. 101, its mall, entrances and the three small parts keep Z.
    const ground=breeze?8.28989:anchor.ground;
    const end=part.first+part.count;
    let top=0;
    for(let i=part.first;i<end;i++)top=Math.max(top,buffer.readFloatLE(i*16+8));
    for(let i=part.first;i<end;i++){
      const src=i*16,dst=i*24,x=buffer.readFloatLE(src),y=buffer.readFloatLE(src+4),z=buffer.readFloatLE(src+8);
      const lon=meta.lon+(x*Math.cos(angle)-y*Math.sin(angle))/eastDegree;
      const lat=meta.lat+(x*Math.sin(angle)+y*Math.cos(angle))/110574;
      const [mx,my]=merc(lon,lat);
      const height=breeze?(z<=16.6?z*21.97048/16.6:21.97048+(z-16.6)*(56.74049-21.97048)/(35.8-16.6)):z;
      const rgb=buffer.readUIntBE(src+12,3);
      if(buffer[src+15]!==255||!Number.isFinite(mx+my+height))throw Error('Invalid authored vertex');
      const values=[(mx-anchor.mx)/anchor.m,(anchor.my-my)/anchor.m,ground+height,ground,top,rgb+2];
      values.forEach((value,k)=>data.writeFloatLE(value,dst+4*k));
    }
  }
  return {data,parts};
}
if(process.argv[1]&&pathToFileURL(realpathSync(process.argv[1])).href===import.meta.url){
  const html=gunzipSync(await readFile(input)).toString();
  const {data,parts}=registerScene(html);
  await writeFile(output,gzipSync(data,{level:9}));
  console.log(`Wrote ${data.length/24} vertices in ${parts.length} groups.`);
}
