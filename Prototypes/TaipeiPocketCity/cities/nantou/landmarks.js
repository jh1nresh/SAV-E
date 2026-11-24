// Ci'en Pagoda. The tower uses the exact OSM polygon; the separate mapped
// overlook apron is a one-metre platform, separated before prep because the
// building:part tag otherwise causes the kit to replace the tower outline.
const CE_STONE='#d1ba96', CE_WALL='#b18a5b', CE_ROOF='#425f54', CE_TRIM='#bf9864';

function ciEnPagoda() {
  const building=findBuilding('w1198896246');
  const [cx,cy]=building.obb.c;
  const platform=[[-32.61,23.0],[9.35,38.26],[23.44,-.49],[-18.52,-15.75]];
  const pad=block(platform,0,.48,{facade:'plain',wall:'#ada99c',flatRoof:'#d6cbb8',shop:'none'});
  const plinth=block(building.ring,.48,2.8,{facade:'plain',wall:'#a79781',flatRoof:'#cabb9f',shop:'none'});
  const facade=(r,z0,z1,storey)=>{
    const vertices=ccw(r);
    return vertices.map((a,i)=>{
      const b=vertices[(i+1)%vertices.length],dx=b[0]-a[0],dy=b[1]-a[1],L=Math.hypot(dx,dy);
      const n=[dy/L,-dx/L,0],p=(s,z)=>[a[0]+dx*s+n[0]*.04,a[1]+dy*s+n[1]*.04,z];
      if(!vis(n))return '';
      const paint=(s,t,a,b,c,ink=.3)=>shape([p(s,a),p(t,a),p(t,b),p(s,b)],c,ink);
      const winBase=z0+.62,winTop=z1-.42;
      let rails='';
      if(storey>0){
        rails=paint(0,1,z0+.16,z0+.31,'#dfddd1')+paint(0,1,z0+.87,z0+1.04,'#e8e2d6');
        for(const s of [.04,.2,.36,.52,.68,.84,.96])rails+=paint(s-.026,s+.026,z0+.27,z0+1.04,'#e7e1d7',.17);
      }
      return paint(0,1,z0,z1,tone(n,soft(CE_WALL)),.62)
         +paint(.08,.92,z0+.28,z1-.28,CE_STONE)
         +paint(.32,.68,winBase,winTop,'#514342')
         +paint(.38,.62,winBase+.11,winTop-.07,storey===0?'#775444':'#737675')
         +edge(p(.5,winBase+.04),p(.5,winTop-.08),'#b6a38e',.19)
         +paint(0,1,z0,z0+.26,CE_TRIM)+rails;
    }).join('');
  };
  const decks=[];
  let z=2.8;
  const levels=[5.18,4.72,4.49,4.32,4.17,4.01,3.84,3.71,3.52];
  for(let i=0;i<levels.length;i++){
    const radius=4.27-i*.225, height=levels[i], eaveHeight=z+height*.68;
    const outer=polygon(cx,cy,radius,8,Math.PI/8);
    const eaves=polygon(cx,cy,radius+.68,8,Math.PI/8);
    const under=polygon(cx,cy,radius+.35,8,Math.PI/8);
    const waist=polygon(cx,cy,radius*.84,8,Math.PI/8);
    const lid=polygon(cx,cy,radius*.66,8,Math.PI/8);
    const base=z,upper=z+height;
    decks.push(()=>{
      const r0=atZ(eaves,eaveHeight+.04),r1=atZ(waist,eaveHeight+.5),r2=atZ(lid,upper);
      return facade(outer,base,eaveHeight,i)+shape(atZ(outer,eaveHeight),'#b88861',.35)
        +loft(atZ(under,eaveHeight-.17),r0,n=>tone(n,soft(CE_TRIM)))
        +loft(r0,r1,n=>tone(n,soft(CE_ROOF)))+loft(r1,r2,n=>tone(n,soft(CE_ROOF)))+shape(r2,'#647a69',.44);
    });
    z=upper;
  }
  return obj(building.ring,46,()=>{
    const crown=[[1.23,z],[1.32,z+.52],[.96,z+1.1],[.69,z+1.56],[.74,z+1.88],[.3,z+2.13]]
      .map(([r,h])=>atZ(polygon(cx,cy,r,12),h));
    const finial=crown.slice(1).map((r,i)=>loft(crown[i],r,n=>tone(n,soft('#ae8d5f')))).join('');
    const rim=ccw(platform);
    const rails=rim.map((a,i)=>{
      const b=rim[(i+1)%rim.length],len=Math.hypot(b[0]-a[0],b[1]-a[1]);
      let svg=edge([...a,1.16],[...b,1.16],'#e6decc',.15);
      for(let d=0;d<len;d+=2.4){
        const p=[a[0]+d*(b[0]-a[0])/len,a[1]+d*(b[1]-a[1])/len];
        svg+=stick([...p,.48],[...p,1.28],.087,'#d9d4c6');
      }
      return svg;
    }).join('');
    return pad.draw()+plinth.draw()+decks.map(draw=>draw()).join('')+finial+shape(crown.at(-1),'#b1976a',.31)
       +sticksAtTip(cx,cy,z)+rails;
  });
}

function sticksAtTip(x,y,z){return stick([x,y,z+2.13],[x,y,46],.085,'#ad8248')+ball([x,y,z+2.48],.29,soft('#c19b57'));}

const LANDMARKS=[{name:'慈恩塔',ids:['w1198896246'],build:ciEnPagoda}];

// Keep the mapped viewing court open; simplify the procedural woodland scatter.
SCENE.trees=SCENE.trees.filter(([x,y],i)=>i%3===0 && !(Math.abs(x+4.6)<24 && Math.abs(y-11.25)<22));
