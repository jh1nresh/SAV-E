// The kit compiler clips each EPSG:3826 cell to Taipei before packing its paint.
import {decodeMapJSON} from './pocket-city-atlas.js';
import {districtStreetMarkings} from './xinyi-street-ground.js';

const kinds=['lane','crossing','skill-paving'];
const packId=/^\d+_\d+$/;
const validBox=b=>Array.isArray(b)&&b.length===4&&b.every(Number.isFinite)&&b[0]<=b[2]&&b[1]<=b[3];
const overlaps=(a,b)=>a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
const empty=()=>({type:'FeatureCollection',features:[]});
function combinedSignal(signals){
  if(typeof AbortSignal.any==='function')return {signal:AbortSignal.any(signals),cleanup(){}};
  // iOS 17.0–17.3 has timeout(), but not any(). Release both subscriptions
  // on first abort and after the complete read, including response decoding.
  const controller=new AbortController();
  const cleanup=()=>{for(const signal of signals)signal.removeEventListener('abort',abort);};
  const abort=event=>{controller.abort(event.target.reason);cleanup();};
  const aborted=signals.find(signal=>signal.aborted);
  if(aborted)controller.abort(aborted.reason);
  else for(const signal of signals)signal.addEventListener('abort',abort,{once:true});
  return {signal:controller.signal,cleanup};
}
async function read(name,signal){
  // A stalled local-resource handler must release the in-flight cache entry.
  // The existing street loader retries failures while the camera stays still.
  const timeout=AbortSignal.timeout(12000);
  const request=signal?combinedSignal([signal,timeout]):{signal:timeout,cleanup(){}};
  try{
    const res=await fetch(new URL('./assets/taipei200/'+name,import.meta.url),{signal:request.signal});
    if(!res.ok)throw Error('Taipei 200m '+name+' '+res.status);
    return await decodeMapJSON(res);
  }finally{request.cleanup();}
}
function manifest(value){
  const packs=value?.packs;
  if(value?.size!==200||value.crs!=='EPSG:3826'||!Array.isArray(packs)||!packs.length||
    packs.some(p=>!packId.test(p.id)||!validBox(p.bounds)||!Number.isInteger(p.cells)||p.cells<1)||
    new Set(packs.map(p=>p.id)).size!==packs.length||packs.reduce((n,p)=>n+p.cells,0)!==value.cells){
    throw Error('Invalid 200m street index');
  }
  return value;
}
function checkCell(id,row){
  const [bounds,origin,districts,groups]=row;
  if(!validBox(bounds)||!Array.isArray(origin)||origin.length!==2||!origin.every(Number.isFinite)||
    !Array.isArray(districts)||!districts.length||!Array.isArray(groups)||groups.length!==kinds.length||!groups.every(Array.isArray)){
    throw Error('Invalid 200m street cell '+id);
  }
  for(const polygons of groups)for(const polygon of polygons){
    if(!Array.isArray(polygon)||!polygon.length)throw Error('Invalid 200m polygon '+id);
    for(const ring of polygon){
      if(!Array.isArray(ring)||ring.length<8||ring.length%2)throw Error('Invalid 200m ring '+id);
      let x=0,y=0;
      for(let i=0;i<ring.length;i+=2){
        if(!Number.isSafeInteger(ring[i])||!Number.isSafeInteger(ring[i+1]))throw Error('Invalid 200m offset '+id);
        x+=ring[i];y+=ring[i+1];
      }
      if(x!==ring[0]||y!==ring[1])throw Error('Open 200m ring '+id);
    }
  }
}
function unpack(id,row){
  const [,[lon,lat],districts,groups]=row;
  const east=20*111320*Math.cos(lat*Math.PI/180),north=20*110574;
  const features=[];
  for(const [i,polygons] of groups.entries()){
    if(!polygons.length)continue;
    const coordinates=polygons.map(p=>p.map(ring=>{
      const points=[];let x=0,y=0;
      for(let j=0;j<ring.length;j+=2){
        x+=ring[j];y+=ring[j+1];
        points.push([lon+x/east,lat+y/north]);
      }
      return points;
    }));
    features.push({type:'Feature',id:id+'/'+kinds[i],properties:{kind:kinds[i],scene200:id},
      geometry:{type:'MultiPolygon',coordinates}});
  }
  return districtStreetMarkings(features,{districts});
}
// The original paint and tree records may finish before or after the new pack
// requests. Write one geographic snapshot at a time, keeping the older source
// visible while the adjacent packs load and if any one of them fails.
async function writePaint(source,features){
  // This MapLibre build resolves setData after its worker queue drains and
  // delivers GeoJSON processing failures as events on the source itself.
  let failure;
  const onError=event=>{failure=event.error??Error('200m MapLibre source failed');};
  source.on?.('error',onError);
  try{
    await source.setData({type:'FeatureCollection',features});
    if(failure)throw failure;
  }finally{source.off?.('error',onError);}
}
export function streetPaintUpdate(request){
  let scene,failure;
  const loaded=Promise.resolve(request).then(value=>{scene=value;},error=>{failure=error;});
  return async function apply(source,original,current,legacyReady){
    if(!current())return;
    if(!scene?.cells.length){
      await writePaint(source,original);
      if(!current())return;
      legacyReady();
    }
    await loaded;
    if(!current())return;
    if(failure)throw failure;
    if(!scene?.cells.length)return;
    const retained=original.filter(f=>!kinds.includes(f.properties.kind));
    try{
      await writePaint(source,[...retained,...scene.features]);
    }catch(error){
      if(current()){
        await writePaint(source,original);
        if(current())legacyReady();
      }
      throw error;
    }
    if(current())return scene;
  };
}
export function taipei200Scenes(remember,load=read){
  let index;
  async function inView(view){
    index??=await remember('200/index',async()=>manifest(await load('index.json')));
    const visible=index.packs.filter(p=>overlaps(p.bounds,view));
    const packs=await Promise.all(visible.map(pack=>remember('200/'+pack.id,async()=>{
      const rows=Object.entries(await load(pack.id+'.json.gz'));
      if(rows.length!==pack.cells)throw Error('Incomplete 200m pack '+pack.id);
      return rows.map(([id,row])=>{
        if(!packId.test(id)||id.split('_').map(n=>Math.floor(Number(n)/8)).join('_')!==pack.id){
          throw Error('Misregistered 200m cell '+id);
        }
        checkCell(id,row);
        return [id,row];
      });
    })));
    // Only the current viewport is expanded to geographic coordinates. The
    // atlas LRU holds the compact cell-local offsets for its neighbouring packs.
    const rows=packs.flat(),cells=rows.filter(([,row])=>overlaps(row[0],view));
    const painted=cells.map(([id,row])=>[id,row[0]]);
    const otherBoxes=[...index.packs.filter(p=>!visible.includes(p)).map(p=>p.bounds),
      ...rows.filter(([,row])=>!overlaps(row[0],view)).map(([,row])=>row[0])];
    // Terrain can settle after moveend and nudge the geographic viewport. A
    // previously committed cell still covers that view until a new cell enters.
    const visibleCells=box=>otherBoxes.some(b=>overlaps(b,box))?null:
      painted.filter(([,b])=>overlaps(b,box)).map(([id])=>id);
    return {cells:painted.map(([id])=>id),visibleCells,features:cells.flatMap(([id,row])=>unpack(id,row))};
  }
  return {inView,coverage:()=>index?{cellSize:index.size,crs:index.crs,cells:index.cells,
    packs:index.packs.length,districtCells:index.districtCells,sourceOSM:index.sourceOSM,sceneRecords:index.sceneRecords}:null};
}

// The native map can pan or disable its grid while the compressed outlines load.
export function taipei200Grid(map,load=read){
  let request,grid,visibleKey;
  function clear(){
    request?.abort();request=null;grid=null;
    if(visibleKey!==undefined){map.getSource('plots')?.setData(empty());visibleKey=undefined;}
  }
  async function show(enabled){
    const b=map.getBounds(),view=[b.getWest(),b.getSouth(),b.getEast(),b.getNorth()];
    if(!enabled||map.getZoom()<9.55||!overlaps(view,[121.45,24.95,121.67,25.22])){clear();return;}
    if(!grid){
      if(request)return;
      const active=request=new AbortController();
      try{
        const data=await load('grid.json.gz',active.signal);
        if(request!==active)return;
        if(data?.type!=='FeatureCollection'||!data.features?.length)throw Error('Invalid 200m grid');
        grid=data.features.map(f=>{
          // A clipped municipal border may include a detached line or point.
          const shells=g=>g.type==='Polygon'?[g.coordinates[0]]:
            g.type==='MultiPolygon'?g.coordinates.map(p=>p[0]):
            g.type==='GeometryCollection'?g.geometries.flatMap(shells):[];
          const rings=shells(f.geometry);
          const box=[Infinity,Infinity,-Infinity,-Infinity];
          for(const ring of rings)for(const [x,y] of ring){
            box[0]=Math.min(box[0],x);box[1]=Math.min(box[1],y);
            box[2]=Math.max(box[2],x);box[3]=Math.max(box[3],y);
          }
          return {box,f};
        });
      }catch(err){if(request===active)console.warn('Taipei 200m grid',err.message);return;}
      finally{if(request===active)request=null;}
      return show(true); // Use the current bounds, including pans made during the request.
    }
    const features=grid.filter(row=>overlaps(row.box,view)).map(row=>row.f);
    const key=features.map(f=>f.id).join(',');
    if(key!==visibleKey){map.getSource('plots')?.setData({type:'FeatureCollection',features});visibleKey=key;}
  }
  return {show,clear};
}
