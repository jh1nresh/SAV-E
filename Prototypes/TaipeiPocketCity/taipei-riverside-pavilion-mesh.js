// Original low-poly shelters. Polyfork's Park Picnic Shelter (park-picnic-shelter-9548a3)
// informed the open timber supports and eaves. Form and dimensions are illustrative.
export function drawRiversidePavilion(kind,{box,face}){
  const broad=kind==='river-pavilion';
  const [edgeX,edgeY,postX,postY]=broad?[2.05,1.55,1.55,1.05]:[1.55,1.15,1.22,.78];
  const timber=broad?'#816c53':'#718278', eave=broad?'#9d7354':'#738980';
  const roof=broad?'#b97050':'#608f83', trim=broad?'#965a42':'#456f68';
  const height=broad?2.45:2.35, rise=broad?.79:.38, ridgeX=broad?.67:.77;

  for(const x of [-postX,postX])for(const y of [-postY,postY]){
    box(x,y,-.35,.19,.19,height+.35,timber);
    box(x,y,-.35,.26,.26,.48,'#b3aa94');
  }
  for(const y of [-postY,postY])box(0,y,height-.24,postX*2+.19,.16,.18,eave);
  for(const x of [-postX,postX])box(x,0,height-.24,.16,postY*2+.19,.18,eave);
  box(0,0,height-.095,edgeX*2,edgeY*2,.12,trim);

  const a=[-edgeX,-edgeY,height+.025], b=[edgeX,-edgeY,height+.025];
  const c=[edgeX,edgeY,height+.025], d=[-edgeX,edgeY,height+.025];
  const left=[-ridgeX,0,height+rise], right=[ridgeX,0,height+rise];
  face([a,b,right,left],roof,1);
  face([d,c,right,left],roof,.85);
  face([a,d,left,left],roof,.91);
  face([b,c,right,right],roof,.8);
  box(0,0,height+rise-.012,ridgeX*2,.10,.055,trim);
}
