import {decodeMapJSON} from './pocket-city-atlas.js';

// Same four ink shades as the inventory crowns, multiplied by an illustrated
// leaf tint. The last value controls the width of each spray, never the tree height.
// Taipei park department tree guides and NPM South's Taxodium planting notes
// inform the foliage. These palettes depict the trees in leaf.
const styles=new Map(Object.entries({
  banyan:[.91,1.01,.86,1],
  bishopwood:[1.05,.98,.82,.91],
  camphor:[.87,.97,1.10,.97],
  sweetgum:[1.06,1.01,.84,.86],
  goldenrain:[1.17,1.04,.73,.83],
  paperbark:[.95,1.01,1.13,.78],
  cypress:[1.06,1.00,.77,.79],
}));

export const plainCanopy=[1,1,1,1];
export const treeCanopyKey=(lon,lat,kind)=>lon+','+lat+','+kind;

export function indexTreeCanopies(data){
  if(data?.version!==1 || !data.species)throw Error('Invalid Taipei tree canopy index');
  const canopies=new Map();
  for(const [species,rows] of Object.entries(data.species)){
    const style=styles.get(species);
    if(!style)continue;
    for(const [lon,lat,kind] of rows)canopies.set(treeCanopyKey(lon,lat,kind),style);
  }
  return canopies;
}

export async function loadTreeCanopies(){
  const response=await fetch(new URL('./assets/taipei-tree-canopies.json.gz?v=1',import.meta.url));
  if(!response.ok)throw Error(String(response.status));
  return indexTreeCanopies(await decodeMapJSON(response));
}
