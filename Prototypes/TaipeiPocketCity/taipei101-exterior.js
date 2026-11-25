// Exported from the accepted Pocket City HTML, registered to landmark-101.json.
// Positions are metres east/north of the surveyed tower. RGB already contains
// the original artist's per-face lighting and facade, trim and glazing colors.
export const taipei101Exterior={
  verts:22482,mesh:new URL('./assets/taipei101-pocket-city.bin.gz',import.meta.url),
  box:[121.56385,25.03327,121.56587,25.03465],
};
export const taipei101SurveyTiles=new Set([
  '200/1534_13847','200/1534_13848','200/1535_13848','1000/306_2769','1000/307_2769',
]);
export const taipei101ShellMatch=`bool isTaipei101Shell(vec3 building,vec2 site){
  if(building.z>=2.0)return false;
  // Within these bounds, every 4.94 m survey body belongs to 101. The five
  // independent entrance canopies have their own surveyed ground signatures.
  if(all(greaterThanEqual(site,vec2(-97.,-44.)))&&all(lessThanEqual(site,vec2(44.,106.)))){
    if(abs(building.x-4.94)<.002)return true;
    return all(lessThan(abs(building-vec3(9.47968,2.90066,.145)),vec3(.0015)))||
      all(lessThan(abs(building-vec3(9.60995,3.31041,.625)),vec3(.0015)))||
      all(lessThan(abs(building-vec3(9.56021,3.00014,.225)),vec3(.0015)))||
      all(lessThan(abs(building-vec3(8.88992,2.89987,.155)),vec3(.0015)))||
      all(lessThan(abs(building-vec3(9.50021,2.89987,.315)),vec3(.0015)));
  }
  // Only the NW corner of Breeze Nanshan is present in the original plot.
  // Keep both surveyed volumes outside the two rotated clipping edges.
  vec2 q=site-vec2(105.96899,104.78233);
  if(q.x-.017338*q.y>0.0||q.y+.017573*q.x>0.0)return false;
  return all(lessThan(abs(building-vec3(8.28989,21.97048,.175)),vec3(.0015)))||
    all(lessThan(abs(building-vec3(8.28989,56.74049,.105)),vec3(.0015)));
}`;
