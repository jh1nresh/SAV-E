// Two planted, folded concrete roofs. The paired boundary chains follow the two
// real OSM footprints in scene.json, starting at the walk-up end of each wing.
const XS_WINGS = [
  {id:'w1001894428', name:'向山行政中心', lawn:'#91a553',
   spans:[[[5,4,3],[6,7]], [[3,2,1],[7,8,9]], [[1,0],[9,10,11]], [[0,13],[11,12]]]},
  {id:'w1001894430', name:'向山遊客中心', lawn:'#a1aa58',
   spans:[[[5,6,7,8,9,10],[4,3]], [[10,11,12,13],[3,2,1]], [[13,14],[1,0]]]}
];

function xiangWing(wing) {
  const {ring} = findBuilding(wing.id);
  const mix = (a,b,t) => a.map((v,i) => v+(b[i]-v)*t);
  const length = (a,b) => Math.hypot(b[0]-a[0],b[1]-a[1]);
  function boundary(indices) {
    const vertices = indices.map(i => ring[i]), lengths = [0];
    for (let i=1; i<vertices.length; i++) lengths.push(lengths[i-1]+length(vertices[i-1],vertices[i]));
    const stops = lengths.map(v => v/lengths.at(-1));
    return {stops, total:lengths.at(-1), at(t) {
      const i = Math.max(1,stops.findIndex(v => v>=t-1e-7));
      return mix(vertices[i-1],vertices[i],(t-stops[i-1])/(stops[i]-stops[i-1]));
    }};
  }
  const stations = [];
  for (const [left,right] of wing.spans) {
    const a=boundary(left), b=boundary(right);
    const n=Math.ceil(Math.max(a.total,b.total)/4);
    const stops=new Set([...a.stops,...b.stops,...Array.from({length:n+1},(_,i)=>i/n)]);
    for (const t of [...stops].sort((v,w)=>v-w)) {
      const outer=a.at(t), inner=b.at(t), center=mix(outer,inner,.5);
      const previous=stations.at(-1);
      const segment=previous?length(previous.center,center):0;
      if (previous && segment<.05) continue;
      stations.push({outer,inner,center,d:(previous?.d||0)+segment});
    }
  }
  const total=stations.at(-1).d;
  // The long arm rises out of the lawn; the short span projects unsupported
  // above the court. The published clear opening is 8 m over a 34 m span.
  function level(s,f) {
    const t=Math.min(1,s.d/75), rise=t*t*(3-2*t);
    return .55+8.55*rise+.25*Math.sin(Math.PI*f);
  }
  const material=(a,b,c,d,col) => shape([a,b,c,d],col,0);
  function at(s,f,z) { return [...mix(s.outer,s.inner,f),z]; }
  const strips=[];
  for (let i=1; i<stations.length; i++) {
    const a=stations[i-1], b=stations[i];
    const groundZ=.12;
    const roof=(s,f)=>at(s,f,level(s,f));
    const underside=(s,f)=>at(s,f,level(s,f)-.48);
    const planes=[];
    // The light perimeter coping and walkway sit on each roof, surrounding
    // the grass strip and the central paved maintenance / viewing terrace.
    const d=(a.d+b.d)/2;
    const bands=[[0,.045,'#e1d8c6'],[.045,.13,'#c5bfac'],[.13,.69,wing.lawn],
      [.69,.83,wing.lawn],[.83,.955,'#a1a487'],[.955,1,'#e9deca']];
    for(const [f,g,col] of bands) planes.push([roof(a,f),roof(b,f),roof(b,g),roof(a,g),col]);
    // The two charcoal viewing terraces in the aerial photograph curl back
    // along the short arms. Stone joints cross the terrace, not the grass.
    const terraceWidth=s=>{
      const fromCorner=Math.max(0,Math.min(1,(s.d-total*.57)/17));
      const beforeTip=Math.max(0,Math.min(1,(total-s.d-1.1)/4));
      return .54*Math.sin(fromCorner*Math.PI/2)*Math.sin(beforeTip*Math.PI/2);
    };
    const ta=terraceWidth(a),tb=terraceWidth(b);
    if(ta+tb>.005) {
      const terrace=(s,f,h)=>at(s,f,level(s,f)+h);
      const left=(s,w,h)=>terrace(s,.53-w/2,h);
      const right=(s,w,h)=>terrace(s,.53+w/2,h);
      planes.push([left(a,ta,.15),left(b,tb,.15),right(b,tb,.15),right(a,ta,.15),'#979788']);
      if(ta>.1 && b.d-a.d>1.3) {
        const la=left(a,ta,.19),lb=left(b,tb,.19),ra=right(a,ta,.19),rb=right(b,tb,.19);
        planes.push([la,mix(la,lb,.045),mix(ra,rb,.045),ra,'#777d70']);
      }
    }
    for(const f of [0,1]) {
      const side=(s,z)=>at(s,f,z);
      const hA=level(a,f)-.48, hB=level(b,f)-.48;
      planes.push([side(a,hA),side(b,hB),roof(b,f),roof(a,f),f?'#d3c7b4':'#e1d7c6']);
      const canopyStart=total-34;
      const undersideLift=s=>{
        const t=Math.min(1,Math.max(0,(s.d-canopyStart)/8));
        return groundZ+(level(s,f)-.63-groundZ)*Math.sin(t*Math.PI/2);
      };
      const zA=undersideLift(a), zB=undersideLift(b);
      if(Math.max(hA-zA,hB-zB)>.12) {
        // Outer elevations have the long board-formed pale wall. The court
        // looks into a recessed dark ribbon of glazing between concrete fins.
        const faceF=f?.94:.018;
        const glass=d>(f?24:45) && d<canopyStart-2;
        const skin=glass?(f?'#5f7775':'#657974'):f?'#c0b9a8':'#d0c6b6';
        planes.push([at(a,faceF,zA),at(b,faceF,zB),at(b,faceF,hB),at(a,faceF,hA),skin]);
        if(glass) {
          planes.push([at(a,faceF,hA-.7),at(b,faceF,hB-.7),at(b,faceF,hB),at(a,faceF,hA),'#c9c4b7']);
        }
        if(glass && b.d-a.d>1.5) {
          const jamb=(left,right)=>mix(at(a,faceF,left),at(b,faceF,right),.055);
          planes.push([at(a,faceF,zA),jamb(zA,zB),jamb(hA,hB),at(a,faceF,hA),'#b6b4a5']);
        }
      }
    }
    planes.push([underside(a,0),underside(a,1),underside(b,1),underside(b,0),'#aaa494']);
    if(i===1||i===stations.length-1) {
      const s=i===1?a:b;
      planes.push([underside(s,0),underside(s,1),roof(s,1),roof(s,0),'#d7cbb8']);
    }
    strips.push({center:mix(a.center,b.center,.5),planes});
  }
  return obj(ring,9.4,()=>strips.slice().sort((a,b)=>depthOf([...a.center,4])-depthOf([...b.center,4]))
    .map(({planes})=>planes.slice().sort((a,b)=>depthOf(avg(a.slice(0,4)))-depthOf(avg(b.slice(0,4))))
      .map(([a,b,c,d,col])=>material(a,b,c,d,col)).join('')).join(''));
}

const LANDMARKS=XS_WINGS.map(wing=>({name:wing.name,ids:[wing.id],build:()=>xiangWing(wing)}));
