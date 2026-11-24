// Offline street geometry from the same dated OSM extract as the national POI index.
import {readTaiwanJSON} from './taiwan-coverage.js?v=streets-2';
import {taiwanCellAt} from './taiwan-cell-geometry.js?v=streets-2';

const SCALE=100000,SPAN=3125,START=16;
const empty=()=>({roads:[],buildings:[],pois:[],tiles:0});
const intersects=(a,b)=>a[0]<=b[2]&&a[2]>=b[0]&&a[1]<=b[3]&&a[3]>=b[1];
const collection=features=>({type:'FeatureCollection',features});
function walkCoords(line,tile,visit){
  let x=tile[0]*SPAN,y=tile[1]*SPAN;
  for(let i=0;i<line.length;i+=2){x+=line[i];y+=line[i+1];visit(x,y);}
}
function coords(line,tile){
  const points=[];walkCoords(line,tile,(x,y)=>points.push([x/SCALE,y/SCALE]));return points;
}

export function indexStreetShard(key,rows){
  const tile=key.split('-').map(Number);
  return rows.map(row=>{
    let w=Infinity,s=Infinity,e=-Infinity,n=-Infinity;
    walkCoords(row[0]===0?row[5]:row[4][0],tile,(x,y)=>{
      w=Math.min(w,x);s=Math.min(s,y);e=Math.max(e,x);n=Math.max(n,y);
    });
    return {tile,row,bounds:[w/SCALE,s/SCALE,e/SCALE,n/SCALE]};
  });
}
function segmentBounds(a,b){return [Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[0],b[0]),Math.max(a[1],b[1])];}
export function localStreetFeatures(shards,view,zoom,{contains,exclude,overlapsAuthored=()=>false,interiorTiles}){
  const result=empty(),seen=new Set(),places=new Set();
  result.tiles=shards.length;
  const touchesAuthored=overlapsAuthored(view);
  const allowed=(x,y)=>(interiorTiles?.has(Math.floor(x*32)+'-'+Math.floor(y*32))||contains(x,y))&&!exclude(x,y);
  for(const shard of shards)for(const {tile,row,bounds} of shard){
    if(!intersects(view,bounds)||row[0]===1&&zoom<17)continue;
    const id=row.slice(0,3).join('/');
    if(seen.has(id))continue;
    seen.add(id);
    if(row[0]===0){
      const [,osmId,,roadClass,name,path]=row,points=coords(path,tile);
      // A long way may enter a custom street scene or Taipei along only one segment.
      // Keep the pieces on each side, and keep the local labels off the custom pavement.
      let line=[],piece=0;
      const emit=()=>{
        if(line.length>1)result.roads.push({type:'Feature',id:id+'/'+piece++,geometry:{type:'LineString',coordinates:line},
          properties:{osmId,roadClass,class:['primary','minor','service','path'][roadClass],ordinaryRoad:true,name,label:name}});
        line=[];
      };
      for(let i=1;i<points.length;i++){
        const a=points[i-1],b=points[i],box=segmentBounds(a,b);
        if(!intersects(view,box)||(touchesAuthored&&overlapsAuthored(box))||!allowed((a[0]+b[0])/2,(a[1]+b[1])/2)){emit();continue;}
        if(!line.length)line.push(a);line.push(b);
      }
      emit();
    }else{
      const [,osmId,,height,encoded,shops=[]]=row;
      const rings=encoded.map(line=>{const p=coords(line,tile);p.push(p[0]);return p;});
      if(!allowed(...rings[0][0])||(touchesAuthored&&overlapsAuthored(bounds,rings)))continue;
      result.buildings.push({type:'Feature',id:Math.abs(osmId),geometry:{type:'Polygon',coordinates:rings},
        properties:{localFootprint:true,render_height:height}});
      for(const [place,kind,x,y] of shops){
        if(places.has(place))continue;
        places.add(place);
        result.pois.push({type:'Feature',geometry:{type:'Point',coordinates:[(tile[0]*SPAN+x)/SCALE,(tile[1]*SPAN+y)/SCALE]},
          properties:{mappedShop:place,subclass:kind}});
      }
    }
  }
  return result;
}
function ringBounds(ring){
  let w=Infinity,s=Infinity,e=-Infinity,n=-Infinity;
  for(const [x,y] of ring){w=Math.min(w,x);s=Math.min(s,y);e=Math.max(e,x);n=Math.max(n,y);}
  return [w,s,e,n];
}
// Integrate the intersection with the union of visible OSM tile fragments. A shared wall,
// a small overlap at a party wall, or two copies of the same clipped fragment cannot claim a house.
function edgesOf(rings){
  const edges=[];
  for(const ring of rings)for(let i=1;i<ring.length;i++){
    const a=ring[i-1],b=ring[i];
    if(a[1]===b[1])continue;
    edges.push({x:a[0],y:a[1],slope:(b[0]-a[0])/(b[1]-a[1]),
      lo:Math.min(a[1],b[1]),hi:Math.max(a[1],b[1]),w:Math.min(a[0],b[0]),e:Math.max(a[0],b[0])});
  }
  return edges;
}
const xAt=(edge,y)=>edge.x+(y-edge.y)*edge.slope;
function intervals(edges,y){
  const xs=[];
  for(const edge of edges)if(y>edge.lo&&y<edge.hi)xs.push(xAt(edge,y));
  xs.sort((a,b)=>a-b);
  const result=[];
  for(let i=1;i<xs.length;i+=2)result.push([xs[i-1],xs[i]]);
  return result;
}
function areaOf(ring){
  const [x,y]=ring[0];
  let twice=0;
  for(let j=1;j<ring.length;j++){
    const a=ring[j-1],b=ring[j];
    twice+=(a[0]-x)*(b[1]-y)-(b[0]-x)*(a[1]-y);
  }
  return Math.abs(twice)/2;
}
function coversBuilding(rings,box,items){
  const footprint=areaOf(rings[0])-rings.slice(1).reduce((sum,r)=>sum+areaOf(r),0);
  if(!items.length||footprint<=0)return false;
  const target=footprint*2/3;
  const [w,s,e,n]=box;
  const cap=items.reduce((sum,item)=>{
    const a=item.bounds;return sum+Math.max(0,Math.min(e,a[2])-Math.max(w,a[0]))*Math.max(0,Math.min(n,a[3])-Math.max(s,a[1]));
  },0);
  if(cap<target)return false;
  const subject=edgesOf(rings),others=items.map(item=>item.edges??=edgesOf(item.rings));
  const edges=[...subject,...others.flat()].filter(a=>a.lo<n&&a.hi>s),cuts=new Set([s,n]);
  for(const a of edges){if(a.lo>s)cuts.add(a.lo);if(a.hi<n)cuts.add(a.hi);}
  // Slice at vertices and edge crossings. The covered width is linear between consecutive cuts.
  for(let j=0;j<edges.length;j++){
    const a=edges[j];
    if(a.e<w||a.w>e)continue;
    for(let k=j+1;k<edges.length;k++){
      const b=edges[k],lo=Math.max(s,a.lo,b.lo),hi=Math.min(n,a.hi,b.hi);
      if(lo>=hi||a.e<b.w||b.e<a.w||a.slope===b.slope)continue;
      const cross=lo+(xAt(b,lo)-xAt(a,lo))/(a.slope-b.slope);
      if(cross>lo&&cross<hi)cuts.add(cross);
    }
  }
  let area=0,prior=s;
  for(const next of [...cuts].sort((a,b)=>a-b)){
    if(next<=prior)continue;
    const mid=(next+prior)/2,inside=intervals(subject,mid);
    const spans=others.flatMap(edges=>intervals(edges,mid)).sort((a,b)=>a[0]-b[0]);
    let last=-Infinity,length=0;
    for(const [a,b] of spans){
      const start=Math.max(last,a);
      if(start<b)for(const [left,right] of inside)length+=Math.max(0,Math.min(right,b)-Math.max(left,start));
      last=Math.max(last,b);
    }
    area+=(next-prior)*length;prior=next;
    if(area>=target)return true;
  }
  return false;
}
// Retain the primary source's surveyed/supplied height wherever it already draws the building.
export function missingStreetBuildings(mapped,local,view){
  if(!mapped.length)return local;
  const buckets=new Map();
  function cells(box,visit){
    const clip=[Math.max(view[0],box[0]),Math.max(view[1],box[1]),Math.min(view[2],box[2]),Math.min(view[3],box[3])];
    if(clip[0]>clip[2]||clip[1]>clip[3])return;
    const [left,bottom]=taiwanCellAt(clip[0],clip[1]),[right,top]=taiwanCellAt(clip[2],clip[3]);
    for(let x=left;x<=right;x++)for(let y=bottom;y<=top;y++)visit(x+','+y);
  }
  for(const f of mapped){
    if(f.properties.hide_3d===true)continue;
    const g=f.geometry,parts=g.type==='Polygon'?[g.coordinates]:g.type==='MultiPolygon'?g.coordinates:[];
    for(const rings of parts){
      const item={rings,bounds:ringBounds(rings[0])};
      cells(item.bounds,key=>{if(!buckets.has(key))buckets.set(key,[]);buckets.get(key).push(item);});
    }
  }
  return local.filter(f=>{
    const rings=f.geometry.coordinates,b=ringBounds(rings[0]),checked=new Set();
    cells(b,key=>{for(const item of buckets.get(key)??[]){
      if(intersects(item.bounds,b))checked.add(item);
    }});
    return !coversBuilding(rings,b,[...checked]);
  });
}
// Detect an existing base-map label only on a parallel segment of the same named street.
// Adjacent alley names or another same-named road elsewhere in the viewport stay visible.
export function assignRoadLabels(roads,primary){
  const names=new Map();
  for(const feature of primary){
    const p=feature.properties,g=feature.geometry;
    const labels=new Set([p['name:zh-Hant'],p['name:zh'],p['name:nonlatin'],p.name].filter(Boolean));
    for(const name of labels){
      if(!names.has(name))names.set(name,[]);
      const found=names.get(name);
      for(const line of g.type==='MultiLineString'?g.coordinates:g.type==='LineString'?[g.coordinates]:[]){
        for(let i=1;i<line.length;i++)found.push([line[i-1],line[i]]);
      }
    }
  }
  for(const road of roads){
    road.properties.label=road.properties.name;
    const segments=names.get(road.properties.name);
    if(!segments?.length)continue;
    let covered=0,length=0;
    const line=road.geometry.coordinates;
    for(let i=1;i<line.length;i++){
      const a=line[i-1],b=line[i],sx=Math.cos((a[1]+b[1])*Math.PI/360)*111320;
      const dx=(b[0]-a[0])*sx,dy=(b[1]-a[1])*110574,d=Math.hypot(dx,dy);
      length+=d;
      if(!d)continue;
      const x=(a[0]+b[0])/2,y=(a[1]+b[1])/2;
      if(segments.some(([u,v])=>{
        const vx=(v[0]-u[0])*sx,vy=(v[1]-u[1])*110574,span=vx*vx+vy*vy;
        if(!span||Math.abs(dx*vx+dy*vy)<.78*d*Math.sqrt(span))return false;
        const ax=(x-u[0])*sx,ay=(y-u[1])*110574,t=Math.max(0,Math.min(1,(ax*vx+ay*vy)/span));
        return Math.hypot(ax-t*vx,ay-t*vy)<9;
      }))covered+=d;
    }
    if(length&&covered/length>=.7)road.properties.label='';
  }
}
// A physical road is often split into many OSM ways at intersections. Choose a single, visible
// line-center label per nearby name. Clipping also keeps long ways' anchors inside the viewport.
function clipSegment(a,b,[w,s,e,n]){
  const dx=b[0]-a[0],dy=b[1]-a[1];
  let lo=0,hi=1;
  for(const [p,q] of [[-dx,a[0]-w],[dx,e-a[0]],[-dy,a[1]-s],[dy,n-a[1]]]){
    if(p===0){if(q<0)return;continue;}
    const t=q/p;
    if(p<0)lo=Math.max(lo,t);else hi=Math.min(hi,t);
    if(lo>=hi)return;
  }
  return [[a[0]+dx*lo,a[1]+dy*lo],[a[0]+dx*hi,a[1]+dy*hi]];
}
export function streetLabelCandidates(roads,view,zoom){
  const sx=111320*Math.cos((view[1]+view[3])*Math.PI/360),sy=110574;
  const gap=zoom>=18?120:240,byName=new Map(),chosen=[];
  for(const road of roads){
    const name=road.properties.name,line=road.geometry.coordinates;
    if(!name)continue;
    if(!byName.has(name))byName.set(name,[]);
    let run=[],length=0;
    function flush(){
      if(run.length<2)return;
      const midpoint=run[Math.floor((run.length-1)/2)],next=run[Math.floor(run.length/2)];
      byName.get(name).push({road,run,length,x:(midpoint[0]+next[0])/2,y:(midpoint[1]+next[1])/2});
      run=[];length=0;
    }
    for(let i=1;i<line.length;i++){
      const clipped=clipSegment(line[i-1],line[i],view);
      if(!clipped){flush();continue;}
      const [a,b]=clipped,tail=run.at(-1);
      if(tail&&(Math.abs(tail[0]-a[0])>1e-10||Math.abs(tail[1]-a[1])>1e-10))flush();
      if(!run.length)run.push(a);
      run.push(b);length+=Math.hypot((a[0]-b[0])*sx,(a[1]-b[1])*sy);
    }
    flush();
  }
  for(const options of byName.values()){
    // Prefer the base cartography wherever its duplicate was positively identified.
    const anchors=options.filter(o=>!o.road.properties.label);
    for(const opt of options.sort((a,b)=>b.length-a.length)){
      if(!opt.road.properties.label||anchors.some(o=>Math.hypot((o.x-opt.x)*sx,(o.y-opt.y)*sy)<gap))continue;
      anchors.push(opt);
      chosen.push({...opt.road,geometry:{type:'LineString',coordinates:opt.run}});
    }
  }
  return chosen;
}
function requestView(bounds,center){
  // Bound the far edge of a steeply pitched mobile view while still loading every adjacent street.
  const dx=.021,dy=.017;
  return [Math.max(bounds[0],center[0]-dx),Math.max(bounds[1],center[1]-dy),
    Math.min(bounds[2],center[0]+dx),Math.min(bounds[3],center[1]+dy)];
}
function roadWidth(extra){
  const width=f=>['match',['get','roadClass'],0,6*f+extra,1,4.5*f+extra,2,3.2*f+extra,1.35*f+extra];
  return ['interpolate',['exponential',2],['zoom'],16,width(.8),21,width(25.6)];
}
export function addTaiwanStreets(map,before,predicates,onChange){
  const id='tw-ordinary-streets',labels=id+'-labels';
  map.addSource(id,{type:'geojson',data:collection([]),maxzoom:19});
  map.addSource(labels,{type:'geojson',data:collection([]),maxzoom:19});
  const ground=map.getLayer('city-atlas-context')?'city-atlas-context':before;
  const lines={type:'line',source:id,minzoom:START,layout:{'line-join':'round','line-cap':'round'}};
  map.addLayer({...lines,id:id+'-edges',paint:{'line-color':'#b9b1a0','line-width':roadWidth(.75)}},ground);
  map.addLayer({...lines,id:id+'-pavement',paint:{
    'line-color':['match',['get','roadClass'],0,'#e8cc9d',1,'#eddfc8',2,'#f1e7d8','#d6cbac'],'line-width':roadWidth(0)}},ground);
  map.addLayer({id:id+'-names',type:'symbol',source:labels,minzoom:16.4,filter:['!=',['get','label'],''],
    layout:{'symbol-placement':'line-center','text-field':['get','label'],'text-font':['Noto Sans Regular'],
      'text-size':['interpolate',['linear'],['zoom'],16,10,19,13],'text-padding':4,'symbol-spacing':280,
      'symbol-sort-key':['get','roadClass'],'text-max-angle':38},
    paint:{'text-color':'#665849','text-halo-color':'#fff6e6','text-halo-width':1.5}},before);

  const cache=new Map(),pending=new Map(),failures=new Map();
  let keys,interiorTiles,dead=false,packVersion=0,baseVersion=0,lastBase=-1,last='',labelIDs='',result=empty(),activeKeys=[];
  map.on('sourcedata',event=>{if(event.sourceId==='openmaptiles'&&event.sourceDataType==='content')baseVersion++;});
  function load(key,file,accept){
    if(pending.has(key)||(failures.get(key)??0)>Date.now()-5000)return;
    const controller=new AbortController();
    pending.set(key,controller);
    readTaiwanJSON(file,{signal:controller.signal}).then(data=>{
      if(dead||pending.get(key)!==controller)return;
      accept(data);packVersion++;failures.delete(key);onChange();
    }).catch(error=>{
      if(!dead&&!controller.signal.aborted){failures.set(key,Date.now());console.warn('Taiwan streets',file,error);}
    }).finally(()=>{if(pending.get(key)===controller)pending.delete(key);});
  }
  function refresh(bounds,center,zoom){
    const visible=zoom>=START&&intersects(bounds,[114,10,123,27]);
    const view=requestView(bounds,center),wanted=[];
    if(visible){
      if(!keys)load('index','streets/index.json?rev=261123-2',m=>{
        if(m.version!==1||m.tileSpan!==SPAN||m.scale!==SCALE)throw Error('Unsupported street index');
        keys=new Set(m.tiles);interiorTiles=new Set(m.interiorTiles??[]);
      });
      if(keys){
        for(let x=Math.floor(view[0]*32);x<=Math.floor(view[2]*32);x++)for(let y=Math.floor(view[1]*32);y<=Math.floor(view[3]*32);y++){
          const key=x+'-'+y;if(!keys.has(key))continue;wanted.push(key);
          if(cache.has(key)){const value=cache.get(key);cache.delete(key);cache.set(key,value);}
          else load(key,'streets/'+key+'.json.gz',data=>{
            cache.set(key,indexStreetShard(key,data));
            let rowCount=[...cache.values()].reduce((sum,rows)=>sum+rows.length,0);
            for(const old of cache.keys()){
              if(cache.size<=8&&rowCount<=48000)break;
              if(activeKeys.includes(old))continue;
              rowCount-=cache.get(old).length;cache.delete(old);
            }
          });
        }
      }
    }
    activeKeys=wanted;
    for(const [key,controller] of pending)if(key!=='index'&&!wanted.includes(key)){controller.abort();pending.delete(key);}
    const signature=visible?[packVersion,...view,zoom>=17].join('/'):'off';
    const changed=signature!==last;
    if(changed){
      last=signature;
      result=visible?localStreetFeatures(wanted.filter(k=>cache.has(k)).map(k=>cache.get(k)),view,zoom,{...predicates,interiorTiles}):empty();
      map.getSource(id).setData(collection(result.roads));
    }
    if(changed||baseVersion!==lastBase){
      lastBase=baseVersion;
      let primary=[];
      if(result.roads.length&&map.getSource('openmaptiles')){
        const classes=[];
        for(const [layer,values] of [['highway-name-path',['path']],['highway-name-minor',['minor','service','track']],
          ['highway-name-major',['primary','secondary','tertiary','trunk']]]){
          if(map.getLayer(layer)&&map.getLayoutProperty(layer,'visibility')!=='none')classes.push(...values);
        }
        if(classes.length)primary=map.querySourceFeatures('openmaptiles',
          {sourceLayer:'transportation_name',filter:['match',['get','class'],classes,true,false]});
      }
      assignRoadLabels(result.roads,primary);
      const named=streetLabelCandidates(result.roads,view,zoom),next=named.map(r=>r.id).join('|');
      if(changed||next!==labelIDs)map.getSource(labels).setData(collection(named));
      labelIDs=next;
    }
    return result;
  }
  map.on('remove',()=>{dead=true;for(const controller of pending.values())controller.abort();pending.clear();cache.clear();});
  return {refresh,state:()=>({shards:result.tiles,streets:result.roads.length,named:result.roads.filter(r=>r.properties.name).length,
    buildings:result.buildings.length,mappedShopfronts:result.pois.length})};
}
