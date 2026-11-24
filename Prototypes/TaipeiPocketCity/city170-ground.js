import missingGrade from './city170-grade-ids.js';

// Sparse supplement to the vertical tags retained in Taipei's original street packs.
const elevated=new Set(Object.entries(missingGrade).flatMap(([prefix,ids])=>ids.map(id=>prefix+'/'+id)));
export function surfaceFeature(feature){
  return elevated.has(feature.id)?{...feature,properties:{...feature.properties,offGround:true}}:feature;
}
