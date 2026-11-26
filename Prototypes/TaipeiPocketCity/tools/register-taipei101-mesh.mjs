// Rebuild from the accepted, frozen Pocket City HTML. Its projection, all model
// functions and all 11 authored/OSM model groups are run by the shared exporter.
import {readFile,writeFile} from 'node:fs/promises';
import {gzipSync,gunzipSync} from 'node:zlib';
import {pathToFileURL} from 'node:url';
import {realpathSync} from 'node:fs';
import {exportMesh} from './export-pocket-mesh.mjs';

const input=new URL('./fixtures/taipei101-pocket-city.html.gz',import.meta.url);
const output=new URL('../assets/taipei101-pocket-city.bin.gz',import.meta.url);
const inkOutput=new URL('../assets/taipei101-pocket-city-ink.bin.gz',import.meta.url);
const radians=deg=>deg*Math.PI/180;
const merc=(lon,lat)=>[(lon+180)/360,(1-Math.asinh(Math.tan(radians(lat)))/Math.PI)/2];
// survey landmark-101.json, at the centre of the tower (OSM way 198637969).
const anchor={mx:.8376800257453572,my:.42813775317984215,m:2.754036392361926e-8,ground:4.939998465560478};
export function registerScene(html){
  const meta=JSON.parse(html.match(/<script type="application\/json" id="sceneMeta">([^<]+)<\/script>/)[1]);
  const angle=radians(meta.rotation),eastDegree=111320*Math.cos(radians(meta.lat));
  const {buffer,parts,ink,fallback}=exportMesh(html,{paintedInk:true});
  const data=Buffer.alloc(buffer.length/16*24);
  const inkData=Buffer.alloc(ink.length*32);
  const isFallback=new Uint8Array(buffer.length/16);
  let solidVerts=isFallback.length;
  for(const [start,end] of fallback){isFallback.fill(1,start,end);solidVerts-=end-start;}
  let nextSolid=0,nextFallback=solidVerts;
  for(const part of parts){
    const breeze=part.name==='微風南山';
    // Only the two cropped, adjoining Breeze volumes connect to a taller,
    // continuous building outside the source plot. Match the surveyed roof
    // breaks there. 101, its mall, entrances and the three small parts keep Z.
    const ground=breeze?8.28989:anchor.ground;
    function position(x,y,z){
      const lon=meta.lon+(x*Math.cos(angle)-y*Math.sin(angle))/eastDegree;
      const lat=meta.lat+(x*Math.sin(angle)+y*Math.cos(angle))/110574;
      const [mx,my]=merc(lon,lat);
      const height=breeze?(z<=16.6?z*21.97048/16.6:21.97048+(z-16.6)*(56.74049-21.97048)/(35.8-16.6)):z;
      if(!Number.isFinite(mx+my+height))throw Error('Invalid authored vertex');
      return [(mx-anchor.mx)/anchor.m,(anchor.my-my)/anchor.m,ground+height];
    }
    const end=part.first+part.count;
    let top=0;
    for(let i=part.first;i<end;i++)top=Math.max(top,buffer.readFloatLE(i*16+8));
    const solidFirst=nextSolid;
    for(let i=part.first;i<end;i++){
      const src=i*16,dst=(isFallback[i]?nextFallback++:nextSolid++)*24;
      const xyZ=position(buffer.readFloatLE(src),buffer.readFloatLE(src+4),buffer.readFloatLE(src+8));
      if(buffer[src+15]!==255)throw Error('Non-opaque building face');
      const values=[...xyZ,ground,top,buffer.readUIntBE(src+12,3)+2];
      values.forEach((v,k)=>data.writeFloatLE(v,dst+4*k));
    }
    part.first=solidFirst;
    part.count=nextSolid-solidFirst;
    // The map expands each source centerline into a depth-tested screen quad.
    // Width > 0 is CSS pixels. A negative width is in projection units, as in
    // the original painter's explicit stroke-width style.
    for(let i=part.firstInk;i<part.firstInk+part.inkCount;i++){
      const {a,b,rgb:[r,g,bColor],width}=ink[i];
      const values=[...position(...a),...position(...b),(r<<16)|(g<<8)|bColor,width];
      values.forEach((v,k)=>inkData.writeFloatLE(v,i*32+4*k));
    }
  }
  return {data,parts,inkData,solidVerts};
}
if(process.argv[1]&&pathToFileURL(realpathSync(process.argv[1])).href===import.meta.url){
  const html=gunzipSync(await readFile(input)).toString();
  const {data,parts,inkData}=registerScene(html);
  await writeFile(output,gzipSync(data,{level:9}));
  await writeFile(inkOutput,gzipSync(inkData,{level:9}));
  console.log(`Wrote ${data.length/24} vertices in ${parts.length} groups and ${inkData.length/32} ink segments.`);
}
