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

export function courtMarkings(feature){
  const {properties:p,geometry:g}=feature;
  if(p.offGround||p.kind!=='pitch'||p.category!=='pitch'||g.type!=='Polygon'||g.coordinates.length!==1)return;
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
  const lines=template.marks.map(line=>line.map(at));
  if(p.sport==='basketball')lines.push(Array.from({length:25},(_,i)=>{
    const t=i*Math.PI/12;
    return at([.5+1.8/lengths[0]*Math.cos(t),.5+1.8/lengths[1]*Math.sin(t)]);
  }));
  return {type:'Feature',id:'markings/'+feature.id,properties:{kind:'court-markings'},
    geometry:{type:'MultiLineString',coordinates:lines}};
}
