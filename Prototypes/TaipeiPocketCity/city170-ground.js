import missingGrade from './city170-grade-ids.js';

// Sparse supplement to the vertical tags retained in Taipei's original street packs.
const elevated=new Set(Object.entries(missingGrade).flatMap(([prefix,ids])=>ids.map(id=>prefix+'/'+id)));
export function surfaceFeature(feature){
  // This independently mapped lap sits inside track relation 7932249. Older packs
  // polygonized the closed way, painting over its entire recreation-ground infield.
  if(feature.id==='pitch/way/1469168936' && feature.properties.category==='track' &&
     feature.geometry.type==='Polygon' && feature.geometry.coordinates.length===1){
    return {...feature,properties:{...feature.properties,kind:'track-axis'},
      geometry:{type:'LineString',coordinates:feature.geometry.coordinates[0]}};
  }
  return elevated.has(feature.id)?{...feature,properties:{...feature.properties,offGround:true}}:feature;
}
