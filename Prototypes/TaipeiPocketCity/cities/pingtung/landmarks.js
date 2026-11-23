// The iron tower rises 21.4 m. The base radius is taken from the OSM outline.
const LIGHTHOUSE_WHITE='#f2eee0', LANTERN_FRAME='#596863';
function eluanbiLight(){
  const b=findBuilding('w310320724'),[x,y]=b.obb.c;
  const ring=(r,z,count=32)=>atZ(polygon(x,y,r,count),z);
  const tiers=[[3.57,0],[3.57,.38],[3.34,.64],[3.34,1.28],[2.75,1.57],
    [2.65,3.85],[2.32,8.4],[2.04,12.8],[1.86,16.42],[2.03,16.66],
    [2.46,17.05],[2.46,17.25],[2.13,17.59]];
  const lanternRadius=1.51;
  const draw=()=>{
    let svg=tiers.slice(1).map(([r,z],i)=>loft(ring(...tiers[i]),ring(r,z),n=>tone(n,soft(LIGHTHOUSE_WHITE)))).join('');
    svg+=shape(ring(2.13,17.59),'#d4d4c9',.25);
    const sash=ring(lanternRadius,17.62,12),middle=ring(lanternRadius,18.75,12),top=ring(lanternRadius,19.44,12);
    svg+=loft(sash,middle,n=>tone(n,soft('#80a3a5')))+loft(middle,top,n=>tone(n,soft('#afc9be')));
    for(let i=0;i<12;i++) svg+=stick(sash[i],top[i],.046,LANTERN_FRAME);
    for(const [radius,height] of [[1.57,17.68],[1.56,18.76],[1.57,19.43]]){
      svg+=loft(ring(radius,height-.042),ring(radius,height+.042),()=>LANTERN_FRAME);
    }
    svg+=loft(ring(1.78,19.43),ring(1.68,19.81),n=>tone(n,soft('#c1c1b3')))
      +loft(ring(1.68,19.81),ring(1.16,20.52),n=>tone(n,soft('#c1c1b3')))
      +loft(ring(1.16,20.52),ring(.34,20.97),n=>tone(n,soft('#aaa99d')))
      +peak(polygon(x,y,.34,32),20.97,[x,y,21.14],'#7f847a')+stick([x,y,21.04],[x,y,21.4],.057,LANTERN_FRAME);
    const deck=ring(2.36,17.32,24),rail=ring(2.36,18.19,24);
    for(let i=0;i<deck.length;i++){
      svg+=stick(deck[i],rail[i],.03,LANTERN_FRAME)+stick(rail[i],rail[(i+1)%rail.length],.028,LANTERN_FRAME);
    }
    const detail=(degrees,low,high,r0,r1,width)=>{
      const a=degrees*Math.PI/180,co=Math.cos(a),si=Math.sin(a),px=(r,w,z)=>[x+co*r-si*w,y+si*r+co*w,z];
      if(!vis([co,si,0]))return '';
      return shape([px(r0,-width,low),px(r0,width,low),px(r1,width,high),px(r1,-width,high)],'#9b9e93',.3)
        +shape([px(r0+.026,-width*.69,low+.09),px(r0+.026,width*.69,low+.09),px(r1+.026,width*.69,high-.08),px(r1+.026,-width*.69,high-.08)],'#495855',.14);
    };
    return svg+detail(-88,.04,2.25,3.58,2.73,.78)+detail(91,5.3,6.65,2.57,2.48,.25)
      +detail(-88,9.3,10.65,2.29,2.2,.25)+detail(91,13.35,14.63,2.04,1.97,.24);
  };
  return obj(b.ring,21.4,draw);
}
const LANDMARKS=[{name:'鵝鑾鼻燈塔',ids:['w310320724'],build:eluanbiLight}];

// The perimeter is OpenStreetMap way 310320728, projected onto the scene's
// 190 m plot using prep.py's rotation. Its masonry rendered in local metres.
const LIGHTHOUSE_WALL=[[-21.72,-46.33],[7.68,-41.11],[37.32,-35.36],[22.63,18.07],[-32.64,7.72]];
function compoundWall(){
  const rings=LIGHTHOUSE_WALL.map((a,i)=>{
    const b=LIGHTHOUSE_WALL[(i+1)%LIGHTHOUSE_WALL.length];
    const d=norm([b[0]-a[0],b[1]-a[1],0]),p=[d[1]*.28,-d[0]*.28];
    return ccw([[a[0]+p[0],a[1]+p[1]],[b[0]+p[0],b[1]+p[1]],
      [b[0]-p[0],b[1]-p[1]],[a[0]-p[0],a[1]-p[1]]]);
  });
  const panels=rings.map(r=>block(r,0,2.03,{facade:'plain',wall:'#ede9dd',top:'#e3e0d4',shop:'none'}));
  const [x,y]=LIGHTHOUSE_WALL[0];
  const post=block(rect(x,y,3.45,3.38),0,4.35,{facade:'plain',wall:LIGHTHOUSE_WHITE,top:'#e9e4d6',shop:'none'});
  return obj(LIGHTHOUSE_WALL,4.35,()=>panels.map(panel=>panel.draw()).join('')+post.draw());
}
function lighthouseQuarters(){
  const building=findBuilding('w310320726'),{c,ax,L,W}=building.obb;
  const volume=block(building.ring,0,5.1,{facade:'civic',wall:LIGHTHOUSE_WHITE,top:'#ece9e1',shop:'none',
    glass:['#aeb9b0','#899893'],frame:'#b6b9af',trim:'#eee8d8',floor:6});
  const at=(x,y,z)=>[c[0]+ax[0]*x-ax[1]*y,c[1]+ax[1]*x+ax[0]*y,z];
  const bay=L/5;
  const arcade=()=>Array.from({length:5},(_,i)=>{
    const s=-L/2+bay*(i+.5),v=-W/2-.045,r=bay*.32;
    const top=Array.from({length:12},(_,k)=>{
      const t=Math.PI*k/11;
      return at(s+r*Math.cos(t),v,2.92+r*Math.sin(t));
    });
    const opening=[at(s-r,v,.78),at(s+r,v,.78),...top];
    return shape(opening,'#a6a89d',.35)+edge(at(s-r,v-.01,.86),at(s+r,v-.01,.86),'#ddd9cb',.22);
  }).join('');
  return obj(building.ring,5.3,()=>volume.draw()+arcade());
}
LANDMARKS.push({name:'鵝鑾鼻燈塔白色圍牆',ids:[],build:compoundWall},
  {name:'鵝鑾鼻燈塔官舍',ids:['w310320726'],build:lighthouseQuarters});
