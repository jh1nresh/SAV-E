// Four buildings from the authored Songyan scene, tied to the 2025 survey bases.
export const songyanFactory={
  id:'taipei-songyan-factory',name:'松山文創園區製菸工廠',verts:30822,
  mx:0.8376716111111111,my:0.4281076140692883,m:2.754257127884696e-08,
  center:[121.56050,25.04365],box:[121.55967048329431, 25.042867054803033, 121.56175127890302, 25.04408617300341],
  mesh:new URL('./assets/taipei-songyan-factory.bin.gz',import.meta.url),
};
export const factoryTiles=new Set(['200/1532_13853','200/1533_13853','1000/306_2770']);
export const legacyFactoryVertices=29766; // Exact building prefix of the 91,908-vertex songyan-v5 export.
const shells=[
  [5.39,11.15025,.815],[5.39,13.85981,.155],[5.39,13.80027,.355],
  [5.39,16.19012,.225],[5.39,16.28003,.645],[5.39,18.41029,.565],[5.39,18.24001,.675],
  [5.39,5.66979,.905],[5.39,5.74004,.615],[5.39,3.50023,.055],
  [5.51026,9.52962,.865],[7.17971,13.28051,.115],[7.17971,4.7404,.005],
  [5.51026,6.13954,.305],[5.51026,4.66003,.045],[5.51026,7.42973,.375],
];
export const factorySurveyMatch=`bool isFactoryShell(vec3 b,vec2 xy){
  if(any(lessThan(xy,vec2(-255.,-78.)))||any(greaterThan(xy,vec2(5.,73.))))return false;
  // This nursery roof continues over its neighbour. Clip only its surveyed overlap.
  if(all(lessThan(abs(b-vec3(5.51026,6.67955,.795)),vec3(.0015))))
    return all(greaterThanEqual(xy,vec2(-25.15,34.62)))&&all(lessThanEqual(xy,vec2(-2.92,55.65)));
  return ${shells.map(signature=>`all(lessThan(abs(b-vec3(${signature.join(',')})),vec3(.0015)))`).join('||\n    ')};
}`;
