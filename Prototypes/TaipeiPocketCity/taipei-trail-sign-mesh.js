// Original timber guidepost. Post and staggered boards reference Polyfork's
// Trail Signpost (bd29a7). The boards carry no inferred arrows or wording.
export function drawTrailGuidepost({box}){
  const timber='#645447', end='#947960', face='#7c735a';
  box(0,0,-.26,.15,.15,2.23,timber);
  box(0,0,-.26,.25,.23,.38,'#a29b82');
  box(0,0,1.96,.153,.153,.043,end);
  box(-.12,0,1.66,.91,.080,.185,timber);
  box(.14,0,1.39,.85,.080,.181,timber);
  for(const side of [-1,1]){
    box(-.12,side*.043,1.689,.849,.011,.129,face);
    box(.14,side*.043,1.419,.789,.011,.126,'#65766a');
    box(-.49,side*.05,1.705,.059,.015,.094,'#c4a877');
    box(.47,side*.05,1.433,.059,.015,.089,'#b5a475');
  }
}
