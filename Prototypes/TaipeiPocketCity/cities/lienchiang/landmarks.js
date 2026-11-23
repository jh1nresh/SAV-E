// OSM node 5146186234 fixes the light itself. The two nearby building ways stay
// in the scene at their independent survey anchors.
const bx=(120.5103445-SCENE.meta.lon)*111320*Math.cos(SCENE.meta.lat*Math.PI/180);
const by=(26.3657582-SCENE.meta.lat)*110574;
const LANDMARKS=[{name:'東湧燈塔',ids:[],build(){
  const ring=(r,z)=>atZ(polygon(bx,by,r,32),z);
  const course=(r1,z1,r2,z2,colour)=>loft(ring(r1,z1),ring(r2,z2),n=>tone(n,soft(colour)))+shape(ring(r2,z2),colour,0);
  return obj(polygon(bx,by,3.75,32),14.2,()=>{
    let svg=course(3.75,0,3.75,.65,'#d1c7b3')+course(3.15,.65,2.0,9.2,'#f4efdf');
    svg+=course(2.03,9.2,2.78,9.85,'#e5dfce')+course(2.78,9.85,2.78,10.12,'#d8d3c4');
    for(let i=0;i<24;i++){
      const a=2*Math.PI*i/24,b=a+Math.PI/12;
      const p=(t,z)=>[bx+2.69*Math.cos(t),by+2.69*Math.sin(t),z];
      svg+=stick(p(a,10.12),p(a,10.96),.048,'#6e746c')+edge(p(a,10.96),p(b,10.96),'#626961',.072);
    }
    svg+=course(1.66,10.12,1.66,12.5,'#a9c0b7');
    for(let i=0;i<12;i++){
      const a=i*Math.PI/6,x=bx+1.68*Math.cos(a),y=by+1.68*Math.sin(a);
      svg+=stick([x,y,10.1],[x,y,12.5],.062,'#52605c');
    }
    return svg+course(1.96,12.50,1.56,13.10,'#e8e4d8')+course(1.56,13.1,.22,14.0,'#eeeadd')+stick([bx,by,14],[bx,by,14.6],.08,'#4b5754');
  });
}}];
