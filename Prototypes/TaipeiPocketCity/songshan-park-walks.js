// Mapped, ground-level footways in 富錦一號、延壽一號 and the southern part of 民生公園.
// Reuse the street pack's line so the illustrated walker follows the rendered path.
const parkFootways=new Set(['walk/way/557896961','walk/way/1471704252','walk/way/1471704270']);

export function parkWalksForPack(pack,life){
  if(pack.id!=='p225_2038')return life;
  const added={};
  const existing=new Set(Object.values(life.paths).map(path=>path.way));
  for(const feature of pack.features.features){
    if(!parkFootways.has(feature.id)||feature.geometry.type!=='LineString')continue;
    const way=Number(feature.id.split('/').at(-1));
    if(!existing.has(way))added[feature.id]={way,points:feature.geometry.coordinates,people:1};
  }
  return Object.keys(added).length?{...life,paths:{...life.paths,...added}}:life;
}
