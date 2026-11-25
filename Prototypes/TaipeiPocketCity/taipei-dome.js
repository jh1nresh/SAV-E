import {domeRing,domeGeography,domeApron} from './taipei-dome-geography.js';

// The building outline and apron match the two Taipei LOD1 bodies. The
// silver roof profile follows the architect's photographs, at the survey height.
// https://www.archasia.asia/en/projects/taipeidome
const ground=7.52979,height=60.41006;
export const taipeiDome={
  ...domeGeography,id:'taipei-dome',name:'臺北大巨蛋',ground,
  bearing:-23,pitch:49,zoom:17.4,mobileZoom:16.75,
};

export function isDomeSurveyTile(key){
  return key==='200/1532_13852'||key==='1000/306_2770';
}

export function addDomeApron(map,before){
  map.addSource('taipei-dome-apron',{type:'geojson',data:domeApron});
  map.addLayer({
    id:'taipei-dome-apron',type:'fill',source:'taipei-dome-apron',minzoom:16.65,
    paint:{'fill-color':'#c9bfaa','fill-opacity':['interpolate',['linear'],['zoom'],16.65,0,17.4,.93]},
  },before);
}

const profiles=[
  [-.012,.984,0x9b9d91],[.091,1,0x48676b],[.186,1,0xc1c2b8],
  [.255,1,0xadb4ae],[.375,.992,0xced0c6],[.469,.977,0x89969a],
  [.602,.944,0xafbac0],[.727,.884,0xc2c9c6],[.836,.802,0xcdd1cb],
  [.923,.675,0xd7d7cc],[.973,.501,0xdbd9cd],[.994,.348,0xcbcfc5],[1,.204,0xd6d6cd],
];

export function buildTaipeiDome(){
  const rows=profiles.map(([z,r])=>domeRing.map(([x,y])=>[x*r+z*1.39,y*r-z*1.63,z*height]));
  const mesh=[];
  function triangle(a,b,c,ink){
    for(const [x,y,z] of [a,b,c])mesh.push(x,y,z+ground,ground,height,ink+2);
  }
  const length=domeRing.length;
  for(let j=0;j<rows.length-1;j++){
    const lower=rows[j],upper=rows[j+1],color=profiles[j][2];
    for(let i=0;i<length;i++){
      const n=(i+1)%length,[a,b,c,d]=[lower[i],lower[n],upper[n],upper[i]];
      triangle(a,b,c,color);
      triangle(a,c,d,color);
      if(j>=5&&i%2===0){
        // Narrow stands follow the curvature. Offset from the panel so orbiting
        // never brings the finish and the metal seams into the same depth plane.
        const s=.034/Math.hypot(a[0]-b[0],a[1]-b[1]);
        const offset=p=>[p[0]+(b[1]-a[1])*s,p[1]-(b[0]-a[0])*s,Math.min(height,p[2]+.025)];
        const along=(p,q,t)=>p.map((v,k)=>v+(q[k]-v)*t);
        const left=offset(a),right=offset(along(a,b,.018));
        const top=offset(d),topRight=offset(along(d,c,.018));
        triangle(left,right,topRight,0x98a7a7);
        triangle(left,topRight,top,0x98a7a7);
      }
    }
  }
  const foot=rows[0],crown=rows.at(-1);
  for(let i=0;i<length;i++){
    const next=(i+1)%length;
    triangle([0,0,foot[0][2]],foot[next],foot[i],profiles[0][2]);
    triangle([1.39,-1.63,height],crown[i],crown[next],profiles.at(-1)[2]);
  }
  return new Float32Array(mesh);
}
