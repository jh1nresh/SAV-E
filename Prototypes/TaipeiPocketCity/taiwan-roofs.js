// The Pocket City kit uses a coping and small service boxes for flat roofs, and lit planes
// on a common ridge for pitched roofs. Keep every part inside its real building outline.
function mixPoint(a,b,t){return a.map((v,i)=>v+(b[i]-v)*t);}
export function roofDrawing(rings,height,tags,paint,zoom){
  if(tags.suppressPitchedRoof||rings.length!==1||rings[0].length!==5||height<3)return;
  const q=rings[0].slice(0,4);
  const north=110574,east=111320*Math.cos(q[0][1]*Math.PI/180);
  const edges=q.map((p,i)=>[(q[(i+1)%4][0]-p[0])*east,(q[(i+1)%4][1]-p[1])*north]);
  const lengths=edges.map(v=>Math.hypot(...v));
  if(Math.min(...lengths)<2.8||edges.some(([x,y],i)=>{
    const j=(i+1)%4;return Math.abs(x*edges[j][0]+y*edges[j][1])>.32*lengths[i]*lengths[j];
  }))return;
  const center=mixPoint(mixPoint(q[0],q[2],.5),mixPoint(q[1],q[3],.5),.5);
  const shape=tags['roof:shape'];
  if(['gabled','hipped','pyramidal'].includes(shape)){
    if(lengths[0]<lengths[1])q.push(q.shift());
    const width=Math.min(...lengths),length=Math.max(...lengths);
    const rise=Math.min(height*.3,width*.20,5.5),eave=height-rise;
    const a=mixPoint(q[0],q[3],.5),b=mixPoint(q[1],q[2],.5);
    const inset=shape==='gabled'?0:shape==='pyramidal'?.5:Math.min(.5,width*.5/length);
    const ridge=[mixPoint(a,b,inset),mixPoint(b,a,inset)].map(p=>[...p,height]);
    const [p0,p1,p2,p3]=q.map(p=>[...p,eave]),[r0,r1]=ridge;
    const gableColor=shape==='gabled'?paint.wall:paint.roof;
    return {eave,center,faces:[
      {p:[p0,p1,r1,r0],color:paint.roof},{p:[p2,p3,r0,r1],color:paint.roof},
      {p:[p3,p0,r0],color:gableColor},{p:[p1,p2,r1],color:gableColor},
    ]};
  }
  if(zoom<17.8||(shape&&shape!=='flat'))return;
  const inner=q.map((p,i)=>mixPoint(mixPoint(p,q[(i+1)%4],.23/lengths[i]),q[(i+3)%4],.23/lengths[(i+3)%4]));
  const rim=[rings[0],[...inner,inner[0]].reverse()];
  const flat={rim};
  if(lengths[0]*lengths[1]>120&&zoom>=18.8){
    // The kit's understated rooftop fixture. Use adjacent edge directions so it follows the roof.
    const at=(u,v)=>[center[0]+u*edges[0][0]/east/lengths[0]+v*edges[1][0]/east/lengths[1],
      center[1]+u*edges[0][1]/north/lengths[0]+v*edges[1][1]/north/lengths[1]];
    const box=[at(-1.3,-.90),at(1.3,-.90),at(1.3,.90),at(-1.3,.90)];
    flat.fixture=[[...box,box[0]]];
  }
  return flat;
}
