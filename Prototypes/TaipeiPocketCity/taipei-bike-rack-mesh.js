// Original rack illustrations. Polyfork's Bicycle Parking Rack (282058) and
// Bike Rack (a1e7c3) inform the slotted steel and inverted-U proportions.
const dark='#596965', steel='#a7b6ad', plate='#737d72';

export function drawBicycleRack(kind,{box,face}){
  if(kind==='bike-frame-stand'){
    for(const x of [-.37,.37]){
      box(x,0,-.17,.13,.19,.205,plate);
      box(x,0,.01,.068,.068,.67,dark);
      const dx=Math.sign(x);
      face([[x-.034,-.034,.65],[x-.034-dx*.10,-.034,.79],
        [x+.034-dx*.10,-.034,.79],[x+.034,-.034,.65]],steel,.92);
      face([[x-.034,.034,.65],[x-.034-dx*.10,.034,.79],
        [x+.034-dx*.10,.034,.79],[x+.034,.034,.65]],steel,.78);
    }
    box(0,0,.755,.56,.068,.067,steel);
    return;
  }
  for(const x of [-.66,.66])box(x,0,-.17,.16,.49,.213,plate);
  for(const y of [-.21,.21])box(0,y,.027,1.58,.059,.084,dark);
  for(const centre of [-.57,-.19,.19,.57]){
    for(const x of [centre-.077,centre+.077]){
      box(x,-.198,.061,.038,.042,.137,steel);
      face([[x-.019,-.211,.167],[x-.019,.178,.325],
        [x+.019,.178,.325],[x+.019,-.211,.167]],steel,1);
      face([[x+.019,-.211,.130],[x+.019,.178,.288],
        [x+.019,.178,.325],[x+.019,-.211,.167]],plate,.86);
      box(x,.187,.076,.038,.042,.245,steel);
    }
  }
}
