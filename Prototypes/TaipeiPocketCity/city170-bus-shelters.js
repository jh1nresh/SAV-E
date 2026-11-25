import {addStreetFurniture} from './city170-street-furniture.js';

// An illustrated frame at a documented covered bus stop. Polyfork's free Bus Shelter
// (https://polyfork.dev/asset/bus-shelter-f786b4) supplies the 4 × 1.9 × 2.6 m scale. The stop retains its map pin.
const loadStops=async()=>(await import(new URL('./city170-bus-shelter-points.js',import.meta.url).href)).default;

export function shelterParts([id,lonE7,latE7,angle,bench,width,depth]){
  const lon=lonE7/1e7,lat=latE7/1e7;
  const c=Math.cos(angle*Math.PI/180),s=Math.sin(angle*Math.PI/180);
  const east=111320*Math.cos(lat*Math.PI/180);
  const horizontal=width/4, perpendicular=depth/1.9;
  const point=(u,v)=>[
    lon+(u*horizontal*c-v*perpendicular*s)/east,
    lat+(u*horizontal*s+v*perpendicular*c)/110574,
  ];
  const parts=[];
  function box(u,v,width,depth,base,height,color){
    const a=u-width/2,b=u+width/2,f=v+depth/2,r=v-depth/2;
    parts.push({type:'Feature',id:id*16+parts.length,properties:{base,height,color},
      geometry:{type:'Polygon',coordinates:[[point(a,r),point(b,r),point(b,f),point(a,f),point(a,r)]]}});
  }
  for(const u of [-1.66,1.66]){
    box(u,-.63,.23,.24,0,.12,'#a39e8a');
    box(u,-.63,.12,.13,.12,2.43,'#536c67');
  }
  box(0,-.64,3.38,.08,1.98,2.05,'#82968b');
  box(0,0,4,1.9,2.36,2.5,'#53877a');
  box(0,.03,3.9,1.76,2.5,2.6,'#91afa0');
  box(0,.935,3.96,.03,2.36,2.405,'#e2bc7c');
  box(-1.38,-.63,.48,.075,.92,1.72,'#526966');
  box(-1.38,-.581,.39,.018,1.02,1.60,'#f1deaf');
  if(bench){
    for(const u of [-.70,.74])box(u,-.31,.11,.27,0,.39,'#646f65');
    box(.02,-.31,1.84,.40,.39,.48,'#bc9167');
  }
  return parts;
}

export function addBusShelters(map,before){
  addStreetFurniture(map,before,'city170-bus-shelters',18.4,loadStops,shelterParts,.00003);
}
