// Road width and centreline are mapped. Clearance, slab and parapets are illustrative.
export const bridgeDeckMaterial=[146/255,147/255,148/255];
const concrete=[196/255,190/255,170/255];
const fascia=[119/255,124/255,119/255],soffit=[92/255,98/255,94/255];
const smooth=t=>t*t*(3-2*t);
const mix=(a,b,t)=>a+(b-a)*t;
const validPoint=p=>p?.length>=2&&Number.isFinite(p[0])&&Number.isFinite(p[1]);

function roadEdges(line,project,half){
  const corners=[];
  for(const ll of line){
    if(!validPoint(ll))return [];
    const point=project(...ll);
    if(!validPoint(point))return [];
    const last=corners.at(-1);
    const length=last?Math.hypot(point[0]-last.x,point[1]-last.y):0;
    if(last&&length<.001)continue;
    const corner={ll,x:point[0],y:point[1],s:(last?.s??0)+length};
    if(last)last.forward=[(corner.x-last.x)/length,(corner.y-last.y)/length];
    corners.push(corner);
  }
  if(corners.length<2)return [];
  for(let i=0;i<corners.length;i++){
    const c=corners[i],a=corners[i-1]?.forward??c.forward,b=c.forward??a;
    const denom=1+a[0]*b[0]+a[1]*b[1];
    if(denom<.15)return []; // A near U-turn has no well-defined joined road edge here.
    c.dx=-(a[1]+b[1])*half/denom;
    c.dy=(a[0]+b[0])*half/denom;
    if(i){
      const prev=corners[i-1];
      // Both sides must still advance along this segment. Densify the joined
      // edges afterwards, so close samples on a bend don't cross one another.
      const along=(c.dx-prev.dx)*a[0]+(c.dy-prev.dy)*a[1];
      if(c.s-prev.s<=Math.abs(along)+.001)return [];
    }
  }
  return corners;
}

function groundSection(lng,lat,dx,dy,project,elevation){
  // Invert the local projection differential to sample the actual left and
  // right road edges. This also works with a translated or rotated local frame.
  const step=.00001,origin=project(lng,lat),u=project(lng+step,lat),v=project(lng,lat+step);
  if(![origin,u,v].every(validPoint))return;
  const ux=u[0]-origin[0],uy=u[1]-origin[1],vx=v[0]-origin[0],vy=v[1]-origin[1];
  const det=ux*vy-uy*vx;
  if(!Number.isFinite(det)||Math.abs(det)<1e-16)return;
  const dLng=step*(vy*dx-vx*dy)/det,dLat=step*(ux*dy-uy*dx)/det;
  const ground=[elevation(lng+dLng,lat+dLat),elevation(lng,lat),elevation(lng-dLng,lat-dLat)];
  if(ground.every(Number.isFinite))return ground;
}

export function bridgeMesh(span,project,elevation){
  if(!Array.isArray(span?.line)||!Number.isFinite(span.width)||span.width<=0)return [];
  const half=span.width/2,corners=roadEdges(span.line,project,half);
  if(corners.length<2)return [];
  const length=corners.at(-1).s,sections=[];
  for(let i=1;i<corners.length;i++){
    const a=corners[i-1],b=corners[i],steps=Math.max(2,Math.ceil((b.s-a.s)/6));
    for(let j=i===1?0:1;j<=steps;j++){
      const t=j/steps,dx=mix(a.dx,b.dx,t),dy=mix(a.dy,b.dy,t);
      const ground=groundSection(mix(a.ll[0],b.ll[0],t),mix(a.ll[1],b.ll[1],t),dx,dy,project,elevation);
      if(!ground)return [];
      sections.push({x:mix(a.x,b.x,t),y:mix(a.y,b.y,t),dx,dy,s:mix(a.s,b.s,t),ground,rise:0});
    }
  }
  const start=sections[0].ground,end=sections.at(-1).ground;
  // Smoothly carry the endpoint crossfalls through the span. A low, rounded
  // envelope over higher sampled ground avoids copying every DEM bump into
  // the road. A cliff too close to a landing cannot be fit without a spike.
  for(const section of sections){
    section.base=start.map((h,i)=>mix(h,end[i],section.s/length));
    section.excess=Math.max(0,...section.ground.map((h,i)=>h-section.base[i]));
    const toEnd=Math.min(section.s,length-section.s);
    if(section.excess>toEnd*.28+.05)return [];
  }
  for(let i=0;i<sections.length;i++){
    const {s,excess}=sections[i];
    if(excess<=1e-8)continue;
    const radius=Math.min(s,length-s,Math.max(12,excess*14));
    const lift=section=>excess*(1-smooth(Math.abs(section.s-s)/radius));
    for(let j=i;j>=0&&s-sections[j].s<radius;j--)sections[j].rise=Math.max(sections[j].rise,lift(sections[j]));
    for(let j=i+1;j<sections.length&&sections[j].s-s<radius;j++)sections[j].rise=Math.max(sections[j].rise,lift(sections[j]));
  }
  const run=Math.min(length/2,80),kerb=Math.min(.27,half*.1),inner=1-kerb/half;
  const rows=sections.map(section=>{
    const edge=Math.min(section.s,length-section.s);
    const approach=smooth(Math.min(1,edge/run));
    const deck=section.base.map(z=>z+section.rise+run*.065*approach);
    const depth=Math.min(.54,run*.025)*approach;
    const rail=Math.min(.55,run*.045)*smooth(Math.min(1,edge/5));
    const point=(side,z=0)=>[section.x+section.dx*side,section.y+section.dy*side,
      mix(deck[1],deck[side<0?2:0],Math.abs(side))+z];
    return {left:point(1),centre:point(0),right:point(-1),bottomL:point(1,-depth),bottomC:point(0,-depth),bottomR:point(-1,-depth),
      lipL:point(1,rail),lipR:point(-1,rail),innerL:point(inner,rail),innerR:point(-inner,rail),
      bedL:point(inner),bedR:point(-inner)};
  });
  const mesh=[];
  function triangle(a,b,c,color){
    const x=b[0]-a[0],y=b[1]-a[1],z=b[2]-a[2],u=c[0]-a[0],v=c[1]-a[1],w=c[2]-a[2];
    if(Math.hypot(y*w-z*v,z*u-x*w,x*v-y*u)<1e-9)return;
    mesh.push(...a,...color,...b,...color,...c,...color);
  }
  for(let i=1;i<rows.length;i++){
    const a=rows[i-1],b=rows[i];
    function strip(left,right,color){
      triangle(a[left],a[right],b[right],color);
      triangle(a[left],b[right],b[left],color);
    }
    strip('bedL','centre',bridgeDeckMaterial);strip('centre','bedR',bridgeDeckMaterial);
    strip('lipL','innerL',concrete);strip('innerR','lipR',concrete);
    strip('innerL','bedL',fascia);strip('bedR','innerR',fascia);
    strip('bottomL','lipL',fascia);strip('lipR','bottomR',fascia);
    strip('bottomR','bottomC',soffit);strip('bottomC','bottomL',soffit);
  }
  return new Float32Array(mesh);
}
