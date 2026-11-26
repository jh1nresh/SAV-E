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

// Illustrated at street zoom. The rules inform height and depth; the mapped
// court supplies the axis and span. Keep the posts within the known outline.
const netStyles={
  tennis:{posts:1.07,centre:.914,edge:1.07,depth:null,frame:'#496d64'},
  volleyball:{posts:2.55,centre:2.24,edge:2.24,depth:1,frame:'#597c78'},
  badminton:{posts:1.55,centre:1.524,edge:1.55,depth:.76,frame:'#877055'},
};

function playingArea(feature){
  const {properties:p,geometry:g}=feature;
  if(p.offGround||p.kind!=='pitch'||p.category!=='pitch'||g.type!=='Polygon'||g.coordinates.length!==1)return;
  if(Number(p.layer??0)!==0 || ['bridge','tunnel','indoor','covered'].some(tag=>p[tag]&&p[tag]!=='no'))return;
  const template=Object.hasOwn(draws,p.sport)&&draws[p.sport];
  const soccer=p.sport==='soccer';
  const ring=g.coordinates[0];
  if((!soccer&&!template)||ring.length!==5||ring.some(point=>!Array.isArray(point)||!Number.isFinite(point[0])||!Number.isFinite(point[1]))||
    ring[0][0]!==ring[4][0]||ring[0][1]!==ring[4][1])return;
  const q=ring.slice(0,4);
  const metresEast=111320*Math.cos(q[0][1]*Math.PI/180);
  const edges=q.map(([x,y],i)=>[(q[(i+1)%4][0]-x)*metresEast,(q[(i+1)%4][1]-y)*110574]);
  const lengths=edges.map(([x,y])=>Math.hypot(x,y));
  const angleTolerance=soccer?.035:.10;
  if(edges.some(([x,y],i)=>{
    const j=(i+1)%4;
    return Math.abs(x*edges[j][0]+y*edges[j][1])>angleTolerance*lengths[i]*lengths[j];
  }))return;
  if(lengths[0]<lengths[1]){q.push(q.shift());lengths.push(lengths.shift());}
  // Exclude sports complexes or shapes containing multiple courts.
  if(soccer){
    // Require the footprint of one adult pitch, allowing a narrow run-off.
    // Reject tapered or skewed lots, indoor/roof courts and non-grass surfaces.
    if(Number(p.level??0)!==0||p.location&&p.location!=='outdoor'&&p.location!=='surface'||
      p.surface&&!['grass','artificial_turf'].includes(p.surface))return;
    if(lengths.some((m,i)=>i%2?m<64||m>79:m<100||m>114))return;
    if(Math.abs(lengths[0]-lengths[2])>1.5||Math.abs(lengths[1]-lengths[3])>1.5)return;
  }else if(lengths.some((m,i)=>m<template.size[i%2]*.82||m>template.size[i%2]*1.18))return;
  const at=([u,v])=>[0,1].map(axis=>(1-v)*((1-u)*q[0][axis]+u*q[1][axis])+v*((1-u)*q[3][axis]+u*q[2][axis]));
  return {at,lengths,template};
}

// IFAB Law 1, https://www.theifab.com/laws/latest/the-field-of-play/.
// The inset is illustrative and keeps both the markings and goal supports on
// the mapped surface. Offsets below are metres in the pitch's own axes.
const goalInset=1.65, touchInset=1.25, halfGoal=3.66;
function soccerMarkings(at,[length,width]){
  const near=goalInset,far=length-goalInset,side=width/2-touchInset;
  const point=(x,y)=>at([x/length,.5+y/width]);
  const lines=[];
  function line(...points){lines.push(points.map(([x,y])=>point(x,y)));}
  function arc(cx,cy,radius,start,end,steps){
    const points=[];
    for(let i=0;i<=steps;i++){
      const t=start+(end-start)*i/steps;
      points.push([cx+radius*Math.cos(t),cy+radius*Math.sin(t)]);
    }
    line(...points);
  }
  line([near,-side],[far,-side],[far,side],[near,side],[near,-side]);
  line([length/2,-side],[length/2,side]);
  arc(length/2,0,9.15,0,2*Math.PI,48);
  // Short round marks remain legible in the shared line layer.
  line([length/2-.12,0],[length/2+.12,0]);
  const arcAngle=Math.acos((16.5-11)/9.15);
  for(const direction of [1,-1]){
    const x=direction===1?near:far;
    for(const depth of [5.5,16.5]){
      const half=halfGoal+depth,edge=x+direction*depth;
      line([x,-half],[edge,-half],[edge,half],[x,half]);
    }
    const spot=x+direction*11;
    line([spot-.12,0],[spot+.12,0]);
    const facing=direction===1?0:Math.PI;
    arc(spot,0,9.15,facing-arcAngle,facing+arcAngle,20);
    for(const edge of [-1,1]){
      const start=edge===direction?-Math.PI/2:0;
      const turn=direction===1?0:Math.PI;
      arc(x,edge*side,1,start+turn,start+turn+Math.PI/2,6);
    }
  }
  return lines;
}

// Draw reconstructed sports details only inside a qualified, single playing area.
export function courtDetails(feature, withEquipment=false){
  const area=playingArea(feature);
  if(!area)return [];
  const {at,lengths,template}=area;
  const lines=feature.properties.sport==='soccer'?soccerMarkings(at,lengths):template.marks.map(line=>line.map(at));
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
  if(feature.properties.sport==='soccer'){
    for(const end of [0,1]){
      const x=end===0?goalInset:length-goalInset;
      const shaft=.06,centre=halfGoal+shaft;
      for(const sign of [-1,1]){
        part(end+'-post-'+sign,rectangle(x,sign*centre,shaft,shaft),0,2.56,'#f7f2df');
      }
      part(end+'-crossbar',rectangle(x,0,shaft,centre+shaft),2.44,2.56,'#f7f2df');
    }
  }
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
  const net=netStyles[feature.properties.sport];
  if(net){
    const span=width/2-.10;
    for(const side of [-1,1]){
      part('net-post-'+side,rectangle(length/2,side*span,.085,.085),0,net.posts,net.frame);
    }
    // Use a few visible cords rather than drawing a dense, flickering mesh.
    const segments=6, step=2*span/segments;
    for(let i=0;i<segments;i++){
      const y=-span+step*(i+.5);
      const top=net.centre+(net.edge-net.centre)*Math.abs(y/span)**2;
      const bottom=net.depth===null?.045:top-net.depth;
      part('net-tape-'+i,rectangle(length/2,y,.045,step/2),top-.055,top,'#f6ebd2');
      part('net-lower-'+i,rectangle(length/2,y,.031,step/2),bottom,bottom+.045,'#53645b');
      for(let j=-1;j<=1;j++){
        part('net-cord-'+i+'-'+j,rectangle(length/2,y+j*step/3,.031,.026),bottom+.025,top-.03,'#425950');
      }
    }
  }
  return result;
}

export function courtMarkings(feature){
  return courtDetails(feature)[0];
}
