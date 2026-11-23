import {addPocketArt} from '../apple-pocket-art.js';

let renderer;
const art = addPocketArt({
  addTileOverlay(overlay) { renderer = overlay.render; },
  removeTileOverlay() { renderer = null; },
}, {
  TileOverlay: class {
    constructor(render) { this.render = render; }
  },
});

let pending = 0;
globalThis.pocketCityTile = async (x, y, z, scale) => {
  if (!renderer || pending >= 3) return null;
  pending += 1;
  try {
    const canvas = await renderer(x, y, z, scale);
    return canvas ? canvas.toDataURL('image/png').slice('data:image/png;base64,'.length) : null;
  } finally {
    pending -= 1;
  }
};
addEventListener('pagehide', () => art.dispose(), {once: true});
globalThis.webkit.messageHandlers.pocketCityReady.postMessage(true);
