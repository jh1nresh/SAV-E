const metal='#59665e', footing='#898c7f', housing='#464f4b', lens='#f4ddab';

export function drawStreetlight(style,{box,prism}){
  const alongRoad=style<2;
  const count=style%2+1;
  // All dimensions are fractions of the measured pole height. Arm and fixture
  // silhouettes are illustrations referenced against the Polyfork cobra light.
  prism([0,0,0],[.013,.013],[[-.004,1],[.972,.60]],5,metal);
  box(0,0,-.006,.045,.045,.034,footing);
  if(!alongRoad&&count===1){
    box(0,0,.944,.067,.057,.056,housing);
    box(0,0,.944,.054,.046,.016,lens);
    return;
  }
  const reach=alongRoad?.114:.042;
  const width=alongRoad?.043:.040;
  for(const side of count===2?[-1,1]:[1]){
    box(side*reach*.38,0,.949,reach*.92,.017,.021,metal);
    box(side*reach,0,.960,width,.032,.040,housing);
    box(side*reach,0,.959,width*.79,.024,.016,lens);
  }
}
