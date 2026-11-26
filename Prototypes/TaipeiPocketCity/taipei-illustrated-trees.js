import rejectedRoots from './taipei-tree-clearance-data.js';
import {onSongshanAthleticsField} from './songshan-athletics.js';

// Coordinates match the placement data to roughly one centimetre. Only the two
// decorative planting layers call this function; inventory and mapped trees
// have their own renderers.
const roots = new Set();
for (let i=0; i<rejectedRoots.length; i+=2) {
  roots.add((1210000000+rejectedRoots[i])+','+(250000000+rejectedRoots[i+1]));
}
export function misplacedIllustratedTree(x,y) {
  return onSongshanAthleticsField(x,y) || roots.has(Math.round(x*1e7)+','+Math.round(y*1e7));
}
