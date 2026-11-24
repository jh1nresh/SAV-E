import {taiwanCellAt,taiwanCellBounds} from './taiwan-cell-geometry.js';

export async function readTaiwanJSON(path,options){
  const response=await fetch(new URL('./taiwan/'+path,import.meta.url),options);
  if(!response.ok)throw Error('Taiwan map data '+response.status+' '+path);
  if(!path.endsWith('.gz'))return response.json();
  // Hosts may already have decoded a .gz response via Content-Encoding.
  const blob=await response.blob();
  const bytes=new Uint8Array(await blob.slice(0,2).arrayBuffer());
  if(bytes[0]!==31||bytes[1]!==139)return JSON.parse(await blob.text());
  return new Response(blob.stream().pipeThrough(new DecompressionStream('gzip'))).json();
}

// A horizontal ray only intersects the edges at the query latitude.
function latitudeBands(points){
  let south=Infinity,north=-Infinity;
  for(const [,y] of points){south=Math.min(south,y);north=Math.max(north,y);}
  const count=Math.max(1,Math.min(256,Math.ceil(points.length/10)));
  const step=(north-south)/count||1;
  const bands=Array.from({length:count},()=>[]);
  const band=y=>Math.max(0,Math.min(count-1,Math.floor((y-south)/step)));
  for(let i=0,j=points.length-1;i<points.length;j=i++){
    const a=points[j],b=points[i];
    if(a[1]===b[1])continue;
    const low=band(Math.min(a[1],b[1])),high=band(Math.max(a[1],b[1]));
    for(let k=low;k<=high;k++)bands[k].push(i);
  }
  return (x,y)=>{
    if(y<south||y>=north)return false;
    let inside=false;
    for(const i of bands[band(y)]){
      const a=points[i],b=points[i===0?points.length-1:i-1];
      if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;
    }
    return inside;
  };
}
export function makeTaiwanCoverage(collection,grid){
  const buckets=new Map();
  const rows=new Map(grid.rows.map(([y,...limits])=>[y,limits]));
  for(const f of collection.features){
    const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;
    for(const rings of polygons){
      const bounds=[Infinity,Infinity,-Infinity,-Infinity];
      for(const [x,y] of rings[0]){
        bounds[0]=Math.min(bounds[0],x);bounds[1]=Math.min(bounds[1],y);
        bounds[2]=Math.max(bounds[2],x);bounds[3]=Math.max(bounds[3],y);
      }
      const item={rings,bounds,town:f.properties};
      for(let a=Math.floor(bounds[0]*10);a<=Math.floor(bounds[2]*10);a++){
        for(let b=Math.floor(bounds[1]*10);b<=Math.floor(bounds[3]*10);b++){
          const key=a+','+b;
          if(!buckets.has(key))buckets.set(key,[]);
          buckets.get(key).push(item);
        }
      }
    }
  }
  function at(x,y){
    const bucket=buckets.get(Math.floor(x*10)+','+Math.floor(y*10));
    for(const item of bucket??[]){
      const [w,s,e,n]=item.bounds;
      if(x<w||x>e||y<s||y>n)continue;
      item.tests??=item.rings.map(latitudeBands);
      if(item.tests[0](x,y)&&!item.tests.some((test,i)=>i>0&&test(x,y)))return item.town;
    }
  }
  function cellsIn(bounds){
    const [left,bottom]=taiwanCellAt(bounds.getWest(),bounds.getSouth());
    const [right,top]=taiwanCellAt(bounds.getEast(),bounds.getNorth());
    const result=[];
    for(let y=bottom;y<=top;y++){
      const ranges=rows.get(y)??[];
      for(let i=0;i<ranges.length;i+=2){
        for(let x=Math.max(left,ranges[i]);x<=Math.min(right,ranges[i+1]);x++){
          const [w,s,e,n]=taiwanCellBounds(x,y);
          result.push({type:'Feature',properties:{},geometry:{type:'Polygon',coordinates:[[[w,s],[e,s],[e,n],[w,n],[w,s]]]}});
        }
      }
    }
    return result;
  }
  return {at,cellsIn,count:grid.count,towns:collection.features.length};
}
