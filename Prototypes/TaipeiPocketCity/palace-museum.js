// Local metres relative to the existing palace-museum landmark record.
// Positive x follows the main facade; negative y faces the forecourt.
export const palaceFacadeAngle = 25.2;
const angle = palaceFacadeAngle * Math.PI / 180;
const cos = Math.cos(angle), sin = Math.sin(angle);

const ink = {
  plaster: 0xd6af70, wing: 0xd8b680, plinth: 0xaa9d8b, stone: 0xeee4cf,
  riser: 0xc5bbab, bracket: 0x849990, shadow: 0x564f48, opening: 0x41514c,
  window: 0x647d75, glassDeep: 0x6f8988, mullion: 0xb6b9ab,
  tile: 0x518779, tileShade: 0x4a8173, tileLight: 0x578b7d, ridge: 0xc48445,
};

export function buildPalaceModel() {
  const vertices = [];
  function triangle(a, b, c, color) {
    // The two ends of a hip meet at one point on the last ring.
    if (a === b || b === c || c === a) return;
    for (const [x, y, z] of [a, b, c]) {
      vertices.push(x * cos - y * sin, x * sin + y * cos, z, 37.6, 27, color + 2);
    }
  }
  function quad(a, b, c, d, color) {
    triangle(a, b, c, color);
    triangle(a, c, d, color);
  }
  function box(x0, x1, y0, y1, z0, z1, color) {
    const lower = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]];
    const upper = lower.map(([x, y]) => [x, y, z1]);
    quad(...upper, color);
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      quad(lower[i], lower[j], upper[j], upper[i], color);
    }
  }
  function bar(a, b, width, depth, color) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const scale = width / (2 * Math.hypot(dx, dy));
    const sideX = -dy * scale, sideY = dx * scale;
    const top = [[a[0] + sideX, a[1] + sideY, a[2]], [a[0] - sideX, a[1] - sideY, a[2]],
      [b[0] - sideX, b[1] - sideY, b[2]], [b[0] + sideX, b[1] + sideY, b[2]]];
    const underside = top.map(([x, y, z]) => [x, y, z - depth]);
    quad(...top, color);
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      quad(underside[i], underside[j], top[j], top[i], color);
    }
  }

  function roof({ x, y, width, depth, eave, rise, ridgeWidth, lift, sides = 12 }) {
    const endLeft = [x - ridgeWidth / 2, y, eave + rise];
    const endRight = [x + ridgeWidth / 2, y, eave + rise];
    const rings = [0, 0.14, 0.32, 0.54, 0.76, 0.9, 1];
    const edge = (side, i, t) => {
      const f = -1 + 2 * i / sides;
      const [u, v] = [[f, -1], [1, f], [-f, 1], [-1, -f]][side];
      if (t === 1) {
        if (u === -1) return endLeft;
        if (u === 1) return endRight;
      }
      const a = u * (width / 2 * (1 - t) + ridgeWidth / 2 * t);
      // Western/eastern hips flare at the corners, especially near the eave.
      const b = v * depth / 2 * (1 - t) * (0.95 + 0.05 * u ** 4);
      const curved = rise * t ** 1.52 + lift * ((Math.abs(u) * Math.abs(v)) ** 5) * (1 - t) ** 2;
      return [x + a, y + b, eave + curved];
    };
    const fastener = ([u, v, z], fall) => [u, v, z + fall];
    for (let side = 0; side < 4; side++) {
      const rows = rings.map(t => Array.from({ length: sides + 1 }, (_, i) => edge(side, i, t)));
      for (let i = 0; i < sides; i++) {
        for (let j = 0; j < rows.length - 1; j++) {
          const color = i % 4 === 0 ? ink.tileShade : i % 4 === 2 ? ink.tileLight : ink.tile;
          quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i], color);
        }
        bar(fastener(rows[0][i], 0.1), fastener(rows[0][i + 1], 0.1), 0.25, 0.23, ink.ridge);
      }
      for (let j = 0; j < rows.length - 1; j++) {
        bar(fastener(rows[j][0], 0.14), fastener(rows[j + 1][0], 0.14), 0.25, 0.23, ink.ridge);
      }
    }
    bar(fastener(endLeft, 0.25), fastener(endRight, 0.25), 0.48, 0.45, ink.ridge);
    for (const endpoint of [endLeft, endRight]) {
      const [u, v, z] = endpoint;
      box(u - 0.35, u + 0.35, v - 0.3, v + 0.3, z, z + 0.63, ink.ridge);
    }
  }
  function cornice(x0, x1, y0, y1, z) {
    box(x0 - 0.35, x1 + 0.35, y0 - 0.35, y1 + 0.35, z - 0.7, z + 0.1, ink.stone);
    for (let x = x0 + 1; x < x1 - 0.5; x += 1.45) {
      box(x - 0.32, x + 0.32, y0 - 0.52, y0 - 0.31, z - 0.72, z - 0.27, ink.bracket);
    }
  }
  function windows(x0, x1, y, z0, z1, spacing) {
    for (let x = x0; x < x1; x += spacing) {
      box(x - 0.72, x + 0.72, y - 0.11, y + 0.09, z0, z1, ink.shadow);
      box(x - 0.47, x + 0.47, y - 0.14, y, z0 + 0.15, z1 - 0.13, ink.window);
    }
  }
  function balustrade(x0, y0, z0, x1, y1, z1) {
    const supports = Math.max(2, Math.round(Math.hypot(x1 - x0, y1 - y0) / 1.6));
    bar([x0, y0, z0 + 1.05], [x1, y1, z1 + 1.05], 0.28, 0.2, ink.stone);
    bar([x0, y0, z0 + 0.37], [x1, y1, z1 + 0.37], 0.31, 0.28, ink.stone);
    for (let i = 0; i <= supports; i++) {
      const t = i / supports;
      const x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t, z = z0 + (z1 - z0) * t;
      const end = i === 0 || i === supports;
      const radius = end ? 0.2 : 0.1;
      box(x - radius, x + radius, y - radius, y + radius, z - 0.25, z + (end ? 1.28 : 0.95), ink.stone);
    }
  }
  function stair(x0, x1, y0, y1, low, high) {
    const count = Math.round((high - low) / 0.22);
    const tread = (y1 - y0) / count;
    const rise = (high - low) / count;
    for (let i = 0; i < count; i++) {
      const y = y0 + i * tread, z = low + (i + 1) * rise;
      quad([x0, y, z], [x1, y, z], [x1, y + tread, z], [x0, y + tread, z], ink.stone);
      quad([x0, y, z - rise], [x1, y, z - rise], [x1, y, z], [x0, y, z], ink.riser);
    }
    balustrade(x0, y0, low, x0, y1, high);
    balustrade(x1, y0, low, x1, y1, high);
  }

  // Museum shell and north service wings. The front is articulated into
  // low connecting galleries, projecting side masses, and the central hall.
  box(-65.5, 60.3, -39.5, 5.9, 36.7, 44.7, ink.plinth);
  box(-41, 38, 5.8, 30.6, 41, 52.82, ink.wing);
  box(-30.4, -10.8, 30.5, 37.3, 43, 51.47, ink.wing);
  box(6.9, 26.9, 30.5, 43.2, 43, 51.47, ink.wing);
  box(-69.4, 65.9, -15, 5.8, 42, 52.9, ink.wing);
  box(-65.4, -28, -40.3, -14.9, 44.7, 52.9, ink.wing);
  box(25.1, 60.3, -40.3, -14.9, 44.7, 52.9, ink.wing);
  box(-62.6, -49, -47.7, -40.2, 37.8, 52.9, ink.wing);
  box(44.5, 60.2, -46.5, -40.2, 37.8, 52.9, ink.wing);
  box(-27.9, 25, -39.35, 5.7, 44.7, 51.65, ink.plaster);
  cornice(-27.9, 25, -39.35, 5.7, 51.6);
  roof({ x: -1.45, y: -16.8, width: 55, depth: 47.4, eave: 51.75, rise: 3.4, ridgeWidth: 38, lift: 0.55 });
  for (const [x0, x1, x, pavilionX] of [[-65.4, -28, -47, -55.6], [25.1, 60.3, 43.4, 51.2]]) {
    cornice(x0, x1, -40.3, -13.7, 52.75);
    roof({ x, y: -26.7, width: x1 - x0 + 2.4, depth: 29.8, eave: 52.9, rise: 3.15, ridgeWidth: 26, lift: 0.65 });
    box(pavilionX - 6.3, pavilionX + 6.3, -35.9, -25.7, 54.0, 55.8, ink.plaster);
    roof({ x: pavilionX, y: -30.7, width: 17.8, depth: 14.5, eave: 55.6, rise: 2.9, ridgeWidth: 5.5, lift: 0.85 });
  }
  roof({ x: -54.4, y: -5, width: 30, depth: 23.6, eave: 52.86, rise: 2.2, ridgeWidth: 19, lift: 0.42, sides: 6 });
  roof({ x: 52.2, y: -5.5, width: 27.6, depth: 24.5, eave: 52.86, rise: 2.2, ridgeWidth: 18, lift: 0.42, sides: 6 });
  roof({ x: -1.7, y: 15.5, width: 81, depth: 32.3, eave: 53, rise: 3.4, ridgeWidth: 60, lift: 0.55 });
  roof({ x: -20.6, y: 33.85, width: 20.7, depth: 8.6, eave: 51.6, rise: 1.9, ridgeWidth: 13, lift: 0.4, sides: 8 });
  roof({ x: 16.9, y: 36.85, width: 21.1, depth: 14.1, eave: 51.6, rise: 2.05, ridgeWidth: 11, lift: 0.4, sides: 8 });

  // Place the central pavilion at the high point in the survey tiles.
  box(-20.1, 15.9, -4.9, 20.8, 53.0, 59.4, ink.plaster);
  windows(-15.7, 13.8, -4.9, 55.35, 58.05, 2.18);
  cornice(-20.1, 15.9, -4.9, 20.8, 59.2);
  roof({ x: -2.1, y: 7.7, width: 43, depth: 29, eave: 59.3, rise: 4.65, ridgeWidth: 15, lift: 1.03 });
  box(-11, 8.1, -39.9, -39.3, 47.9, 50, ink.stone);
  box(-9.7, 6.8, -39.94, -39.35, 44.7, 47.55, ink.opening);
  for (const x of [-9.5, -5.8, -2.1, 1.6, 5.3]) {
    box(x, x + 0.32, -40.17, -39.9, 44.7, 47.55, ink.bracket);
  }

  // White-railed twin flights and the glazed recess between them.
  box(-31, 28, -49, -39.45, 40.3, 44.7, ink.plinth);
  balustrade(-30.8, -48.9, 44.7, -11.2, -48.9, 44.7);
  balustrade(8.5, -48.9, 44.7, 27.8, -48.9, 44.7);
  stair(-21, -13.1, -61.2, -48.95, 39.4, 44.7);
  stair(10.5, 18.4, -61.2, -48.95, 39.4, 44.7);
  for (let x = -13.05; x < 10.4; x += 2.35) {
    const right = Math.min(x + 2.35, 10.45);
    quad([x, -60.65, 39.65], [right, -60.65, 39.65], [right, -49, 44.18], [x, -49, 44.18], ink.glassDeep);
    const m = Math.min(x + 0.08, right);
    quad([x, -60.7, 39.66], [m, -60.7, 39.66], [m, -49, 44.22], [x, -49, 44.22], ink.mullion);
  }
  bar([-13, -54.8, 42], [10.45, -54.8, 42], 0.13, 0.1, ink.mullion);
  bar([-13, -60.7, 39.75], [10.45, -60.7, 39.75], 0.24, 0.15, ink.ridge);
  // The second set of split flights follows the forecourt approach on the DEM.
  box(-21, 18.4, -82.4, -76.2, 33.1, 35.65, ink.riser);
  stair(-19.7, -7.25, -90.8, -82.3, 34, 35.65);
  stair(4.05, 16.5, -90.8, -82.3, 34, 35.65);
  balustrade(-7.25, -82.5, 35.65, 4.05, -82.5, 35.65);

  return new Float32Array(vertices);
}
