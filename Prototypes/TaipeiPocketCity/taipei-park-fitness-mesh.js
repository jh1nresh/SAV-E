// Representative steel frames and moving parts based on Taipei park equipment.
const paint=['#4c9280','#4f829d','#a45f50','#688f5b'];
const trim=['#e4b659','#e0a95e','#e6c479','#d29457'];
const steel='#b9c4ba', grips='#4d5b55';

export function drawParkFitness(kind,index,{box,prism,face}){
  const frame=paint[index%paint.length], accent=trim[index%trim.length];

  function beam(from,to,width,color){
    const [dx,dy,dz]=to.map((value,i)=>value-from[i]);
    const length=Math.hypot(dx,dy,dz);
    const spread=Math.hypot(dx,dy);
    const side=spread?[-dy/spread,dx/spread,0]:[1,0,0];
    const top=[-dz*side[1]/length,dz*side[0]/length,(dx*side[1]-dy*side[0])/length];
    const profile=[[1,1],[-1,1],[-1,-1],[1,-1]].map(([u,v])=>
      side.map((value,i)=>(u*value+v*top[i])*width/2));
    const start=profile.map(offset=>offset.map((value,i)=>value+from[i]));
    const end=profile.map(offset=>offset.map((value,i)=>value+to[i]));
    for(let i=0;i<4;i++){
      const next=(i+1)%4;
      face([start[i],start[next],end[next],end[i]],color,[1.02,.86,.74,.94][i]);
    }
    face([...start].reverse(),color,.87);
    face(end,color,1.06);
  }

  const post=(x,y,h,width=.13)=>box(x,y,0,width,width,h,frame);
  const round=(x,y,z,r,h,color)=>prism([x,y,z],[r,r],[[0,1],[h,1]],10,color);
  function wheels(radius,hubHeight,solid){
    post(0,0,hubHeight+.12,.17);
    box(0,0,hubHeight,2*(radius+.08),.10,.085,steel);
    for(const x of [-radius-.08,radius+.08]){
      const centre=[x,-.11,hubHeight];
      const rim=Array.from({length:10},(_,i)=>[x+radius*Math.cos(i*Math.PI/5),-.11,hubHeight+radius*Math.sin(i*Math.PI/5)]);
      for(let i=0;i<rim.length;i++){
        const next=rim[(i+1)%rim.length];
        if(solid)face([centre,rim[i],next,centre],accent,1.03);
        else beam(rim[i],next,.064,accent);
      }
      for(let i=0;i<rim.length;i+=solid?5:2)beam(centre,rim[i],.050,solid?frame:steel);
      box(x,-.14,hubHeight-.058,.12,.082,.116,grips);
    }
  }

  switch(kind){
    case 'fitness-pullup':
      for(const x of [-.82,.82])post(x,0,2.25);
      box(0,0,2.15,1.68,.077,.077,steel);
      for(const x of [-.58,.58])box(x,0,2.15,.18,.087,.087,accent);
      break;
    case 'fitness-parallel':
      for(const y of [-.30,.30]){
        for(const x of [-.73,.73])post(x,y,1.11);
        box(0,y,1.12,1.82,.09,.09,steel);
        for(const x of [-.83,.83])box(x,y,1.112,.16,.10,.101,accent);
      }
      break;
    case 'fitness-walker':
      for(const y of [-.47,.47]){
        post(.17,y,1.29,.15);
        beam([.17,y,1.20],[-.27,y,1.44],.095,frame);
        box(-.42,y,1.40,.31,.115,.11,grips);
      }
      box(.17,0,1.21,.13,.98,.11,steel);
      for(const y of [-.22,.22]){
        const x=y<0?.30:-.13;
        beam([.17,y,1.20],[x,y,.20],.093,frame);
        box(x,y,.16,.41,.22,.083,accent);
      }
      break;
    case 'fitness-twister':
      post(0,0,1.16,.16);
      box(0,0,1.11,1.40,.095,.095,steel);
      for(const x of [-.48,.48]){
        round(x,-.22,0,.14,.16,frame);
        round(x,-.22,.15,.28,.073,accent);
        box(x,-.035,1.105,.30,.108,.104,grips);
      }
      break;
    case 'fitness-wheel':
      wheels(.34,1.25,false);
      break;
    case 'fitness-shoulder':
      wheels(.23,1.30,true);
      break;
    case 'fitness-back':
      for(const x of [-.51,.51])post(x,0,1.27);
      box(0,0,1.21,1.18,.10,.10,steel);
      for(const z of [.64,.83,1.02]){
        box(0,-.075,z,.98,.10,.082,steel);
        for(const x of [-.21,0,.21])box(x,-.13,z-.008,.15,.16,.111,accent);
      }
      break;
    case 'fitness-pull':
      post(0,0,1.84,.16);
      for(const x of [-.54,.54]){
        beam([0,0,1.67],[x,0,2.08],.107,frame);
        beam([x,0,2.08],[x*1.30,0,1.64],.073,steel);
        box(x*1.30,0,1.54,.12,.27,.11,grips);
        post(x,0,.37);
        box(x,0,.36,.38,.35,.09,accent);
      }
      break;
    case 'fitness-ski':
      post(.53,0,1.04,.15);
      for(const y of [-.23,.23]){
        beam([.53,y,.10],[-.69,y,.10],.11,frame);
        beam([-.38,y,.22],[.41,y,1.46],.085,steel);
        box(.37,y,1.40,.24,.10,.10,grips);
        box(-.47,y,.17,.47,.218,.08,accent);
      }
      box(0,0,0,1.58,.108,.08,frame);
      break;
    case 'fitness-bench':
      post(-.67,0,.31,.22);
      post(.62,0,.64,.22);
      for(const y of [-.17,.17])beam([-.77,y,.29],[.66,y,.60],.085,frame);
      face([[-.82,-.25,.30],[.71,-.25,.64],[.71,.25,.64],[-.82,.25,.30]],accent,1.04);
      for(const y of [-.25,.25])beam([-.82,y,.29],[.71,y,.63],.055,accent);
      box(.78,0,.63,.11,.56,.10,grips);
      box(.62,0,.74,.13,.51,.10,grips);
      break;
    case 'fitness-rower':
      for(const x of [-.65,.65])box(x,0,0,.16,.62,.10,frame);
      box(0,0,.07,1.47,.14,.14,frame);
      post(-.38,0,.48,.16);
      box(-.38,0,.46,.43,.39,.10,accent);
      for(const y of [-.23,.23]){
        beam([.40,y,.26],[.14,y,.98],.084,frame);
        box(.08,y,.92,.21,.108,.106,grips);
        box(.43,y,.23,.29,.20,.085,accent);
      }
      break;
    case 'fitness-ladder':
      for(const y of [-.37,.37]){
        for(const x of [-1.02,1.02])post(x,y,2.15);
        box(0,y,2.10,2.20,.10,.10,frame);
      }
      for(let i=-3;i<=3;i++)box(i*.29,0,2.12,.078,.79,.077,i%2===0?accent:steel);
      break;
  }
}
