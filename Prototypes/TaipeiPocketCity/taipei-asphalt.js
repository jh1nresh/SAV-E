// Daylight asphalt is sampled from the accepted 200 m Taipei 101 ground painting.
export const asphaltColors={day:'#a9a9ab',cloudy:'#8891a0',drizzle:'#79869a',rain:'#636f87'};
export const asphalt=['to-color',['global-state','taipeiAsphalt'],asphaltColors.day];

const motorLayer=/^(?:road|bridge)_(?:minor|street|secondary_tertiary|trunk_primary|motorway|motorway_link|link|service_track)(_casing)?$/;

// Keep the overview's road hierarchy. Only close-up motor carriageways in the
// Taipei illustration receive asphalt; rails, paths and tunnels retain their symbols.
export function applyBaseAsphalt(layer,boundary){
  if(!motorLayer.test(layer.id)||layer.type!=='line')return;
  const original=layer.paint['line-color'];
  const local=['all',['!=',['get','class'],'track'],['within',boundary]];
  layer.paint['line-color']=['interpolate',['linear'],['zoom'],15.35,original,16.25,
    ['case',local,layer.id.endsWith('_casing')?'#c7b7a1':asphalt,original]];
}
