// Ordinary plots reserve their rectangle. Recovered street scenes can reserve only
// the part of the slope occupied by their artwork, leaving neighbouring buildings intact.
export function plotOverlaps(row,box,building){
  const [w,s,e,n]=box,[a,b,c,d]=row.bounds;
  if(w>c||e<a||s>d||n<b)return false;
  if(!row.footprint)return true;
  const {type,coordinates}=row.footprint;
  const polygons=type==='Polygon'?[coordinates]:coordinates;
  if(building)return polygons.some(rings=>polygonsTouch(rings,building));
  return polygons.some(rings=>rings.some(ring=>ringTouchesBox(ring,box))||
    (inside(rings[0],w,s)&&!rings.slice(1).some(hole=>inside(hole,w,s))));
}

function inside(ring,x,y){
  let hit=false;
  for(let i=1;i<ring.length;i++){
    const [a,b]=ring[i-1],[c,d]=ring[i];
    if((b>y)!==(d>y)&&x<(c-a)*(y-b)/(d-b)+a)hit=!hit;
  }
  return hit;
}

function ringTouchesBox(ring,[w,s,e,n]){
  // Clip each line segment to both coordinate intervals.
  for(let i=1;i<ring.length;i++){
    const [x,y]=ring[i-1],[u,v]=ring[i];
    let low=0,high=1;
    for(const [p,q,min,max] of [[x,u,w,e],[y,v,s,n]]){
      if(p===q){if(p<min||p>max){high=-1;break;}continue;}
      const left=(min-p)/(q-p),right=(max-p)/(q-p);
      low=Math.max(low,Math.min(left,right));high=Math.min(high,Math.max(left,right));
    }
    if(low<=high)return true;
  }
  return false;
}

function polygonsTouch(left,right){
  function covers(rings,[x,y]){
    return inside(rings[0],x,y)&&!rings.slice(1).some(h=>inside(h,x,y));
  }
  if(covers(left,right[0][0])||covers(right,left[0][0]))return true;
  for(const l of left)for(const r of right){
    for(let i=1;i<l.length;i++)for(let j=1;j<r.length;j++){
      if(segmentsTouch(l[i-1],l[i],r[j-1],r[j]))return true;
    }
  }
  return false;
}

function segmentsTouch(a,b,c,d){
  for(let k=0;k<2;k++){
    if(Math.max(a[k],b[k])<Math.min(c[k],d[k])||
       Math.max(c[k],d[k])<Math.min(a[k],b[k]))return false;
  }
  const side=(p,q,r)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
  return side(a,b,c)*side(a,b,d)<=0&&side(c,d,a)*side(c,d,b)<=0;
}
