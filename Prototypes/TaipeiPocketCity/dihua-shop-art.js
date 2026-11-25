// Street-level illustrations for the documented provisions and bamboo shops.
// Position and available bay width come from the survey. Merchandise is schematic.
import {frontageParts} from './fuxing-fronts.js?v=dihua-shops-1';

const ink='#574037', wood='#a76c48', cream='#efdcaf';

function arcade(p,half,depth,bamboo){
  const floor=bamboo?'#bcac99':'#d0c5b1';
  p.block(-half,half,.025,.09,0,depth,floor,'#988877');
  for(let s=-half+.48;s<half;s+=.54){
    p.surface([[s,.092,0],[s+.014,.092,0],[s+.014,.092,depth],[s,.092,depth]],'#ac9e89');
  }
  // Short returns and a continuous walking strip keep the displays behind the columns.
  // Open the ceiling in the illustration so the shop interior reads from above.
  p.block(-half,half,3.01,3.13,0,.33,'#a98f77','#aa9279');
  for(const x of [-half,half-.14]){
    p.block(x,x+.14,2.94,3.11,.24,depth,'#a68a6f','#87684f');
  }
  p.block(-half,half,2.88,3.09,depth-.17,depth,'#8c6250','#ae9071');
  for(const x of [-half,half-.15]){
    p.block(x,x+.15,.09,2.88,depth-.18,depth,'#aa8872','#876956');
    p.block(x-.014,x+.164,.09,.40,depth-.19,depth+.01,'#a09581','#8d7d6d');
  }
}

function provisions(p,h,depth,plaque){
  p.face(-h,h,.08,2.97,.015,'#a7654d');
  p.face(-h*.74,h*.74,.09,2.67,.04,'#493a31');
  for(const x of [-h*.75,h*.72]){
    p.block(x,x+.11,.09,2.66,.04,.18,'#86553f',ink);
  }
  p.face(-h*.34,h*.30,.10,2.01,.08,'#63574a');
  p.face(-h*.28,h*.24,.14,1.91,.09,'#343e35');
  for(const side of [-1,1]){
    const middle=side*h*.68,w=h*.26;
    p.face(middle-w,middle+w,.20,1.97,.09,'#745c43');
    for(let tier=0;tier<3;tier++){
      const z=.57+tier*.45;
      p.block(middle-w,middle+w,z,z+.055,.09,.27,cream,wood);
      for(let i=0;i<4;i++){
        const x=middle-w+(i+.22)*w/2,w0=w*.31;
        p.face(x,x+w0,z+.06,z+.30+.045*(i%2),.225,['#cfab70','#e2ca97','#986644','#a8a184'][(tier+i)%4]);
        p.face(x+.018,x+w0-.018,z+.10,z+.16,.23,'#f2ddb4');
      }
    }
    p.block(middle-w,middle+w,.10,.67,.12,.52,'#b48150','#8d6746');
    p.surface([[middle-w,.70,.52],[middle+w,.70,.52],[middle+w,.86,.20],[middle-w,.86,.20]],'#d1ac79');
    for(let i=0;i<4;i++){
      const x=middle-w+(i+.12)*w/2;
      p.surface([[x,.72,.49],[x+w*.36,.72,.49],[x+w*.36,.85,.24],[x,.85,.24]],i%2?'#dfbc86':'#b99767');
    }
  }
  // The documented facade has a gold-on-dark plaque and a split indigo curtain.
  plaque(-h*.41,h*.41,2.53,3.14,depth+.13,'#293f3d');
  const span=h*1.50;
  for(let i=0;i<4;i++){
    const left=-span/2+i*span/4;
    p.surface([[left,2.68,depth-.40],[left+span/4-.033,2.68,depth-.40],
      [left+span/4-.06,2.25+(i%2)*.035,depth-.35],[left+.02,2.22,depth-.35]],i%2?'#576d99':'#61799f');
  }
}

// Open, tapered vessels. The dark interior, rim and curved handles carry the silhouette at map scale.
function vessel(p,x,z,d,r,height,handle,steamer=false){
  const sides=12;
  const circle=(i,rad,high)=>[x+rad*Math.cos(i*2*Math.PI/sides),high,d+rad*.72*Math.sin(i*2*Math.PI/sides)];
  const lowR=steamer?r*.96:r*.67;
  for(let i=0;i<sides;i++){
    const j=i+1;
    p.surface([circle(i,lowR,z),circle(j,lowR,z),circle(j,r,z+height),circle(i,r,z+height)],
      ['#ad733e','#ca9656','#d6ae6c','#bf8a4e'][Math.floor(i/3)]);
    p.surface([circle(i,r,z+height),circle(j,r,z+height),circle(j,r*.80,z+height+.012),circle(i,r*.80,z+height+.012)],'#e1bc78');
    p.surface([[x,z+height-.065,d],circle(i,r*.80,z+height+.012),circle(j,r*.80,z+height+.012),[x,z+height-.065,d]],'#8a633e');
    if(steamer){
      const mid=z+height*.43;
      p.surface([circle(i,r*.99,mid),circle(j,r*.99,mid),circle(j,r,mid+.025),circle(i,r,mid+.025)],'#845e3f');
    }
  }
  if(handle){
    const pt=(i,w)=>[x+(r*.76+w)*Math.cos(i*Math.PI/8),z+height+(r*1.2+w)*Math.sin(i*Math.PI/8),d];
    for(let i=0;i<8;i++)p.surface([pt(i,0),pt(i+1,0),pt(i+1,.036),pt(i,.036)],'#c19756');
  }
}

function bambooShop(p,h,depth,plaque){
  p.face(-h,h,.09,2.97,.012,'#725d46');
  p.face(-h+.15,h-.15,.10,2.65,.025,'#474839');
  for(const side of [-1,1]){
    const x=side*h*.68, w=h*.26;
    p.block(x-w,x+w,.10,.42,.05,.67,'#a38055',ink);
    const r=Math.min(w*.72,.33);
    vessel(p,x,.43,.54,r,.33,side>0,side<0);
    if(side<0)vessel(p,x,.76,.54,r*.91,.21,false,true);
    p.block(x-w,x+w,1.24,1.30,.04,.43,'#bfa16b',ink);
    vessel(p,x,1.31,.25,r*.76,.24,true);
  }
  // Large hanging market baskets sit forward of the dark interior, with a clear opening between them.
  for(const side of [-1,1]){
    const x=side*h*.70;
    p.face(x-.019,x+.019,2.18,2.87,depth-.11,cream);
    vessel(p,x,1.35,depth-.11,.34,.47,true);
  }
  const pole=2.28;
  p.block(-h+.17,h-.17,pole,pole+.07,.62,.72,'#a48659',ink);
  for(const [i,ratio] of [-.72,-.34,.39,.74].entries()){
    const x=h*ratio,r=.24+.045*(i%2),z=1.36+.11*(i%3);
    p.face(x-.015,x+.015,z+.23+r,pole,.66,cream);
    vessel(p,x,z,.66,r,.23,true);
  }
  // A striped market bag contrasts with the honey-coloured bamboo steamers.
  p.face(-h+.16,-h+.65,.54,1.11,.58,'#4d8c77');
  for(const [i,c] of ['#b75e52','#e6b963','#476c84','#c46e63'].entries())
    p.face(-h+.16,-h+.65,.60+i*.12,.65+i*.12,.585,c);
  plaque(-h*.52,h*.52,2.53,3.14,depth+.13,'#7b4534');
}

export function drawDihuaShop(row,geometry){
  if(row.frontDesign!=='provisions'&&row.frontDesign!=='bamboo')return false;
  const p=frontageParts(geometry),h=geometry.half;
  arcade(p,h,row.arcadeDepth,row.frontDesign==='bamboo');
  if(row.frontDesign==='provisions')provisions(p,h,row.arcadeDepth,geometry.plaque);
  else bambooShop(p,h,row.arcadeDepth,geometry.plaque);
  return true;
}
