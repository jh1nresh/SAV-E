// OSM way/189788192 fixes the corner tips and the south-facing entrance projection.
// NLSC PHOTO2 (2024, z19/224457/439179) shows a dark square flat centre, four gold skirts
// and a raised south canopy. Front elevation: newtaipei.travel/file/2554, printed page 4.
// Published body: 100 m square, 30.4 m high. Surface colours and sub-metre details are illustrative.
const center=[121.56029235,25.040019575];
const radians=Math.PI/180, north=center[1]*radians;
const ground=8.21, height=30.4;
export const sunYatSenHall={
  id:'sun-yat-sen-hall',name:'國父紀念館',center,bearing:-9,pitch:56,zoom:18.05,mobileZoom:17.35,
  ground,top:ground+height,mx:(center[0]+180)/360,my:(1-Math.asinh(Math.tan(north))/Math.PI)/2,
  m:1/(40075016.68557849*Math.cos(north)),box:[121.559735,25.039479,121.560852,25.040546],
};

// At both prepared resolutions exactly this object has base 8.23, height 9.77 and tone .495.
export function isMemorialSurveyTile(key) {
  return key==='200/1532_13851' || key==='1000/306_2770';
}

const colors={
  roof:[0xd7a347,0xe0ad51,0xdba84c,0xe5b457], glazed:0xeac16a, tileLip:0xd8a24d,
  rim:0xd7c29c, rimLight:0xf0dfbd, shade:0x625b56, soffit:0xb0a18c,
  deck:0x977b73, deckField:0x95766d, deckSeam:0x896e65, parapet:0xbea68f,
  stone:0xc0b8a7, step:0xd8cfc0, riser:0xab9c89, stoneShadow:0x998d7d,
  red:0x9d534b, panel:0xb36355, redInk:0x7f403c, entry:0x444849,
  glass:0x52625e, glint:0x738079, frame:0x8e755d, plaque:0x313738, gold:0xeecc7f,
};

export function buildSunYatSenHall() {
  const mesh=[];
  const yaw=-1.88*radians, cs=Math.cos(yaw), sn=Math.sin(yaw);
  function triangle(a,b,c,tone) {
    for(const [x,y,z] of [a,b,c])mesh.push(x*cs-y*sn,x*sn+y*cs,z+ground,ground,height,tone+2);
  }
  function quad(a,b,c,d,color){ triangle(a,b,c,color);triangle(a,c,d,color); }
  function box(x0,x1,y0,y1,z0,z1,color,side=color) {
    const top=[[x0,y0,z1],[x1,y0,z1],[x1,y1,z1],[x0,y1,z1]];
    quad(...top,color);
    for(let i=0;i<4;i++){
      const a=top[i],b=top[(i+1)%4];
      quad([a[0],a[1],z0],[b[0],b[1],z0],b,a,side);
    }
  }
  function ribbon(a,b,width,depth,color,side=color) {
    const dx=b[0]-a[0],dy=b[1]-a[1], length=Math.hypot(dx,dy);
    if(length<.001)return;
    const u=-dy*width/(2*length),v=dx*width/(2*length);
    const p=[[a[0]+u,a[1]+v,a[2]],[a[0]-u,a[1]-v,a[2]],
      [b[0]-u,b[1]-v,b[2]],[b[0]+u,b[1]+v,b[2]]];
    quad(...p,color);
    if(!depth)return;
    for(let i=0;i<4;i++) {
      const x=p[i],y=p[(i+1)%4];
      quad([x[0],x[1],x[2]-depth],[y[0],y[1],y[2]-depth],y,x,side);
    }
  }
  function cylinder(x,y,r,z0,z1) {
    for(let i=0;i<12;i++){
      const a=2*Math.PI*i/12,b=2*Math.PI*(i+1)/12;
      const l=[x+r*Math.cos(a),y+r*Math.sin(a)],h=[x+r*Math.cos(b),y+r*Math.sin(b)];
      quad([...l,z0],[...h,z0],[...h,z1],[...l,z1],colors.stone);
    }
  }
  function rotate(u,v,side,z){
    return [[u,-v,z],[v,u,z],[-u,v,z],[-v,-u,z]][side];
  }
  function skin(side,f,t) {
    const corner=Math.abs(f)**7;
    const outer=50.1+4.2*corner, inner=27.3;
    const u=f*(outer*(1-t)+inner*t),v=outer*(1-t)+inner*t;
    // The section falls into a shallow concave sweep and curls back up at the corners.
    const z=12.8+14.05*t**1.8+(1-t)**2*(1.0+4.15*corner);
    return rotate(u,v,side,z);
  }
  const lower=(p,d)=>[p[0],p[1],p[2]-d];
  function skirt(side) {
    const samples=52, rings=[0,.055,.16,.3,.47,.67,.84,1];
    for(let i=0;i<samples;i++){
      const f=-1+2*i/samples,g=-1+2*(i+1)/samples;
      for(let j=0;j<rings.length-1;j++){
        const a=skin(side,f,rings[j]),b=skin(side,g,rings[j]),
          c=skin(side,g,rings[j+1]),d=skin(side,f,rings[j+1]);
        quad(a,b,c,d,colors.roof[(i+side)%4]);
        if(i%2===0)ribbon(lower(a,-.038),lower(d,-.038),.09,0,colors.glazed);
        if(i===0)ribbon(lower(a,-.20),lower(d,-.20),.48,.28,colors.rimLight,colors.tileLip);
      }
      const a=skin(side,f,0),b=skin(side,g,0);
      ribbon(a,b,.45,.38,colors.rimLight,colors.rim);
      quad(lower(a,.38),lower(b,.38),lower(b,.80),lower(a,.80),colors.shade);
      const back=p=>[p[0]*.885,p[1]*.885,p[2]-.92];
      quad(lower(a,.8),lower(b,.8),back(b),back(a),colors.soffit);
      if(i%4===0)ribbon(lower(a,.82),back(a),.28,.24,colors.stoneShadow);
    }
  }
  // Broad low terrace, recessed red wall panels and the shaded public perimeter arcade.
  box(-47.5,47.5,-47.5,47.5,-.48,1.35,colors.stone,colors.stoneShadow);
  box(-46.65,46.65,-46.65,46.65,1.35,1.72,colors.step,colors.riser);
  box(-40.9,40.9,-40.9,40.9,1.72,15.2,colors.soffit,colors.red);
  for(let side=0;side<4;side++){
    for(let i=0;i<13;i++){
      const u=-43.7+(87.4/13)*i;
      const [x,y]=rotate(u,43.7,side,0);
      cylinder(x,y,.69,1.68,14.32);
      const a=rotate(u-.84,43.7,side,14.38),b=rotate(u+.84,43.7,side,14.38);
      ribbon(a,b,1.7,.53,colors.soffit,colors.stoneShadow);
      const left=u+1.35,right=u+5.42;
      if((side!==0 || Math.abs((left+right)/2)>14) && left> -40 && right<40){
        quad(rotate(left,41.06,side,2.50),rotate(right,41.06,side,2.50),
          rotate(right,41.06,side,10.95),rotate(left,41.06,side,10.95),colors.panel);
      }
    }
    skirt(side);
  }

  // Square flat roof is visible in real aerial views; fine joints and a low pale curb distinguish it from tile.
  box(-27.4,27.4,-27.4,27.4,24.0,26.82,colors.deck);
  for(let j=-25;j<=25;j+=5){
    box(j-.055,j+.055,-27.2,27.2,26.82,26.85,colors.deckSeam);
    box(-27.2,27.2,j-.055,j+.055,26.82,26.85,colors.deckSeam);
  }
  box(-7.4,1.7,-1.7,6.7,26.84,26.92,0xa99b86);
  for(let side=0;side<4;side++)
    ribbon(rotate(-27.5,27.5,side,27.25),rotate(27.5,27.5,side,27.25),.55,.55,colors.rimLight,colors.parapet);

  // Elevated south entry roof matches the separate rectangular projection in the orthophoto.
  const cuts=[[-56.8,26.65],[-55.6,26.05],[-51.3,26.3],[-45.2,27.8],[-40,29.7],[-36,28.15],[-30,27.0],[-26.8,26.96]];
  function port(i,f){
    const [y,z]=cuts[i], width=14.05+1.1*Math.abs((y+26.8)/30);
    return [f*width,y,z+.68*Math.abs(f)**7];
  }
  for(let i=0;i<cuts.length-1;i++){
    for(let j=0;j<22;j++){
      const f=-1+j/11,g=f+1/11;
      quad(port(i,f),port(i,g),port(i+1,g),port(i+1,f),colors.roof[j%4]);
      if(j%2===0)ribbon(lower(port(i,f),-.045),lower(port(i+1,f),-.045),.11,0,colors.glazed);
      if(!i){
        const a=port(0,f),b=port(0,g);
        quad(a,b,lower(b,1.25),lower(a,1.25),colors.rim);
        ribbon(a,b,.52,.28,colors.rimLight);
      }
    }
    for(const sign of [-1,1]){
      const a=port(i,sign),b=port(i+1,sign);
      quad(a,b,[b[0],b[1],12.95],[a[0],a[1],12.95],colors.stoneShadow);
      ribbon(lower(a,-.02),lower(b,-.02),.55,.42,colors.rimLight);
    }
  }
  box(-14.0,14.0,-55.25,-40.8,24.5,25.45,colors.soffit,colors.shade);
  box(-13.8,13.8,-47.0,-40.84,1.73,24.45,colors.entry);
  for(let i=0;i<9;i++){
    const x=-12.3+i*3;
    box(x,x+2.7,-47.09,-47.0,2.0,19.8,i%3===1?colors.glint:colors.glass);
    box(x,x+.15,-47.19,-47.09,1.9,19.95,colors.frame);
  }
  box(-13.85,13.85,-47.16,-47.0,5.4,5.68,colors.frame);
  for(const x of [-13.35,-4.48,4.48,13.35]){
    cylinder(x,-52.1,.9,1.7,24.65);
    box(x-1.04,x+1.04,-53.2,-51.0,23.85,24.52,colors.stone);
  }
  box(-11.9,11.9,-52.95,-51.35,20.9,21.8,colors.stone);
  box(-5.05,5.05,-53.02,-52.82,19.0,21.75,colors.gold);
  box(-4.89,4.89,-53.10,-53.015,19.16,21.59,colors.plaque);

  // Five small inscription characters, set right-to-left on the south-facing plaque.
  const lettering=[
    ['11 81 89 19 11','32 38 68','33 55 56 36 33','62 76 86','74 57','74 84'],
    ['34 52','64 83','22 62 87','83 65 48 19'],
    ['22 14 34 15 46','16 46','27 18','37 39','53 82 85 55 58 87'],
    ['16 43 55 84','38 68','34 66','53 64','47 38','58 79','18 26','79 88'],
    ['12 33 44','25 45','24 28 42','34 45 46 25','52 64 83','55 85 86 56 55','57 87 89 59 57'],
  ];
  lettering.forEach((glyph,i)=>{
    const cx=3.70-i*1.84;
    for(const stroke of glyph){
      const pts=stroke.split(' ').map(p=>[cx+(+p[0]-5)*.165,21.25-(+p[1]-1)*.19]);
      for(let j=0;j<pts.length-1;j++){
        const [x,z]=pts[j],[u,v]=pts[j+1],len=Math.hypot(u-x,v-z);
        if(!len)continue;
        const a=(v-z)*.055/len,b=-(u-x)*.055/len;
        quad([x-a,-53.115,z-b],[u-a,-53.115,v-b],[u+a,-53.115,v+b],[x+a,-53.115,z+b],colors.gold);
      }
    }
  });
  box(-17.25,17.25,-51.88,-46.30,-.15,1.72,colors.step,colors.riser);
  for(let i=0;i<9;i++){
    const y=-59.4+i*.84,z=(i+1)*1.72/9;
    box(-17.25,17.25,y,y+.845,-.11,z,colors.step,colors.riser);
  }
  return new Float32Array(mesh);
}
