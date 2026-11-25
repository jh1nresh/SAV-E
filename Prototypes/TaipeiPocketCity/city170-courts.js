// Painted markings are illustrative. Use only a mapped single court of a plausible size.
const draws={
  basketball:{size:[28,15],marks:[[[.5,0],[.5,1]],[[0,.34],[.19,.34],[.19,.66],[0,.66]],
    [[1,.34],[.81,.34],[.81,.66],[1,.66]]]},
  tennis:{size:[23.77,10.97],marks:[[[0,.125],[1,.125]],[[0,.875],[1,.875]],
    [[.23,.125],[.23,.875]],[[.77,.125],[.77,.875]],[[.23,.5],[.77,.5]]]},
  volleyball:{size:[18,9],marks:[[[.5,0],[.5,1]],[[1/3,0],[1/3,1]],[[2/3,0],[2/3,1]]]},
  badminton:{size:[13.4,6.1],marks:[[[0,.075],[1,.075]],[[0,.925],[1,.925]],[[.35,0],[.35,1]],
    [[.65,0],[.65,1]],[[0,.5],[.35,.5]],[[.65,.5],[1,.5]]]},
};

function playingArea(feature){
  const {properties:p,geometry:g}=feature;
  if(p.offGround||p.kind!=='pitch'||p.category!=='pitch'||g.type!=='Polygon'||g.coordinates.length!==1)return;
  if(Number(p.layer??0)!==0 || ['bridge','tunnel','indoor','covered'].some(tag=>p[tag]&&p[tag]!=='no'))return;
  const template=Object.hasOwn(draws,p.sport)&&draws[p.sport];
  const ring=g.coordinates[0];
  if(!template||ring.length!==5)return;
  const q=ring.slice(0,4);
  const metresEast=111320*Math.cos(q[0][1]*Math.PI/180);
  const edges=q.map(([x,y],i)=>[(q[(i+1)%4][0]-x)*metresEast,(q[(i+1)%4][1]-y)*110574]);
  const lengths=edges.map(([x,y])=>Math.hypot(x,y));
  if(edges.some(([x,y],i)=>{
    const j=(i+1)%4;
    return Math.abs(x*edges[j][0]+y*edges[j][1])>.10*lengths[i]*lengths[j];
  }))return;
  if(lengths[0]<lengths[1]){q.push(q.shift());lengths.push(lengths.shift());}
  // Exclude sports complexes or shapes containing multiple courts.
  if(lengths.some((m,i)=>m<template.size[i%2]*.82||m>template.size[i%2]*1.18))return;
  const at=([u,v])=>[0,1].map(axis=>(1-v)*((1-u)*q[0][axis]+u*q[1][axis])+v*((1-u)*q[3][axis]+u*q[2][axis]));
  return {at,lengths,template};
}

// Draw reconstructed sports details only inside a qualified, single playing area.
export function courtDetails(feature, withEquipment=false){
  const area=playingArea(feature);
  if(!area)return [];
  const {at,lengths,template}=area;
  const lines=template.marks.map(line=>line.map(at));
  if(feature.properties.sport==='basketball'){
    lines.push(Array.from({length:25},(_,i)=>{
      const t=i*Math.PI/12;
      return at([.5+1.8/lengths[0]*Math.cos(t),.5+1.8/lengths[1]*Math.sin(t)]);
    }));
    // Scale the painted three-point arcs with the mapped rectangle, including junior courts.
    const radius=6.75, wing=6.6, angle=Math.asin(wing/radius);
    for(const end of [0,1]){
      const fromEnd=(m,v)=>at([end===0?m/28:1-m/28,v]);
      const arc=[fromEnd(0,.5-wing/15)];
      for(let i=0;i<=28;i++){
        const t=angle*(i/14-1);
        arc.push(fromEnd(1.575+radius*Math.cos(t),.5+radius*Math.sin(t)/15));
      }
      arc.push(fromEnd(0,.5+wing/15));
      lines.push(arc);
    }
  }
  const paint={type:'Feature',id:'markings/'+feature.id,properties:{kind:'court-markings'},
    geometry:{type:'MultiLineString',coordinates:lines}};
  const result=[paint];
  if(!withEquipment)return result;
  const [length,width]=lengths;
  // These are Pocket City illustrations. OSM supplies the court extent and sport.
  // Silhouette reference: polyfork.dev/asset/yard-basketball-post-b71ee3.
  function part(id,outline,base,top,color,inner){
    function ring(points){
      const path=points.map(([x,y])=>at([x/length,y/width+.5]));
      return [...path,path[0]];
    }
    result.push({type:'Feature',id:feature.id+'/'+id,properties:{kind:'court-equipment',base,top,color},
      geometry:{type:'Polygon',coordinates:inner?[ring(outline),ring(inner)]:[ring(outline)]}});
  }
  const rectangle=(x,y,dx,dy)=>[[x-dx,y-dy],[x+dx,y-dy],[x+dx,y+dy],[x-dx,y+dy]];
  if(feature.properties.sport==='basketball'){
    for(const end of [0,1]){
      const x=offset=>end===0?offset:length-offset;
      const circle=r=>Array.from({length:16},(_,i)=>[x(1.575)+r*Math.cos(i*Math.PI/8),r*Math.sin(i*Math.PI/8)]);
      part(end+'-post',rectangle(x(.18),0,.15,.15),0,3.40,'#486765');
      part(end+'-arm',rectangle(x(.70),0,.52,.10),3.23,3.40,'#587976');
      part(end+'-board',rectangle(x(1.2),0,.09,.9),2.90,3.95,'#f5ecd2');
      part(end+'-rim',circle(.29),3.02,3.10,'#ce633d',circle(.19).reverse());
    }
  }
  if(feature.properties.sport==='tennis'){
    for(const side of [-1,1]){
      part('net-post-'+side,rectangle(length/2,side*(width/2-.10),.09,.09),0,1.07,'#496d64');
    }
    part('net-tape',rectangle(length/2,0,.06,width/2-.10),.91,1.02,'#f6ebd2');
  }
  return result;
}

export function courtMarkings(feature){
  return courtDetails(feature)[0];
}
