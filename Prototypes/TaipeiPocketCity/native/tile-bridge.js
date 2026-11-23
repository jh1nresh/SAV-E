import {addPocketArt} from '../apple-pocket-art.js';

function report(state) {
  globalThis.webkit.messageHandlers.pocketCityState.postMessage(state);
}

let renderer;
const art = addPocketArt({
  addTileOverlay(overlay) { renderer = overlay.render; },
  removeTileOverlay() { renderer = null; },
}, {
  TileOverlay: class {
    constructor(render) { this.render = render; }
  },
}, state => {
  if (state === 'degraded') report(state);
});

let pending = 0;
function hasPaint(canvas) {
  const pixels = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data;
  if (!pixels) throw Error('Pocket City canvas unavailable');
  for (let i = 3; i < pixels.length; i += 4) if (pixels[i]) return true;
  return false;
}

globalThis.pocketCityTile = async (x, y, z, scale, checkPaint) => {
  if (!renderer || pending >= 3) return null;
  pending += 1;
  try {
    const canvas = await renderer(x, y, z, scale);
    if (!canvas) return null;
    return {
      png: canvas.toDataURL('image/png').slice('data:image/png;base64,'.length),
      painted: checkPaint && hasPaint(canvas),
    };
  } catch {
    report('degraded');
    return null;
  } finally {
    pending -= 1;
  }
};
addEventListener('pagehide', () => art.dispose(), {once: true});
report('bridge');
