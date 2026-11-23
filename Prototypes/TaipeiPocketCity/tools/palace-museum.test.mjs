import test from 'node:test';
import assert from 'node:assert/strict';
import {buildPalaceModel, palaceFacadeAngle} from '../palace-museum.js';

const anchor = [121.548544, 25.102274];
const frontage = [[121.5482712, 25.1017663], [121.5491092, 25.1021239]];
const metresPerDegree = [100805, 111319];
const angle = palaceFacadeAngle * Math.PI / 180;
const cos = Math.cos(angle), sin = Math.sin(angle);
const mesh = buildPalaceModel();
const points = [];
for (let i = 0; i < mesh.length; i += 6) {
  const [east, north, z, , , packed] = mesh.subarray(i, i + 6);
  points.push([east * cos + north * sin, north * cos - east * sin, z, packed - 2]);
}

function near(actual, expected, tolerance) {
  assert.ok(Math.abs(actual - expected) < tolerance, `Expected ${actual} within ${tolerance} of ${expected}`);
}

function extent(rows, axis) {
  return [Math.min(...rows.map(row => row[axis])), Math.max(...rows.map(row => row[axis]))];
}

const has = (x, y, z, color) => points.some(point => point[3] === color &&
  Math.hypot(point[0] - x, point[1] - y, point[2] - z) < 0.08);

function area(a, b, c) {
  const [x, y, z] = b.map((value, index) => value - a[index]);
  const [u, v, w] = c.map((value, index) => value - a[index]);
  return Math.hypot(y * w - z * v, z * u - x * w, x * v - y * u) / 2;
}

test('palace geometry fits the survey triangle and color format', () => {
  assert.ok(mesh instanceof Float32Array);
  assert.equal(mesh.length % 18, 0);
  assert.ok(mesh.byteLength < 1.2 * 1024 * 1024);
  assert.ok(mesh.every(Number.isFinite));
  for (let i = 0; i < points.length; i += 3) {
    const [a, b, c] = points.slice(i, i + 3);
    assert.ok(area(a, b, c) > 1e-4, `Degenerate triangle ${i / 3}`);
    assert.ok(a[3] >= 0 && a[3] <= 0xffffff && Number.isInteger(a[3]));
    assert.equal(b[3], a[3]);
    assert.equal(c[3], a[3]);
  }
});

test('palace mass and entrance follow the surveyed WGS84 frontage', () => {
  const projected = frontage.map(point => {
    const [e, n] = point.map((value, index) => (value - anchor[index]) * metresPerDegree[index]);
    return [e * cos + n * sin, n * cos - e * sin];
  });
  const [west, east] = extent(points, 0);
  const [south, north] = extent(points, 1);
  near(west, -69.55, 0.3);
  near(east, 66, 0.3);
  near(north, 43.28, 1.0);
  near(south, -91, 0.15);
  near(projected[0][1], projected[1][1], 0.1);
  near(projected[0][1], -39.4, 0.15);
  assert.ok(has(-9.7, -39.94, 44.7, 0x41514c));
  assert.ok(has(6.8, -39.94, 47.55, 0x41514c));
});

test('green hip roofs sweep upward at the central corners, with lower side pavilions', () => {
  const ridge = points.filter(point => point[3] === 0xc48445);
  const [, center] = extent(ridge.filter(point => Math.abs(point[0]) < 20), 2);
  const [, west] = extent(ridge.filter(point => point[0] < -32), 2);
  const [, east] = extent(ridge.filter(point => point[0] > 32), 2);
  near(center, 64.58, 0.01);
  near(west, 59.13, 0.04);
  near(east, 59.13, 0.04);
  assert.ok(has(-23.6, -6.8, 60.33, 0x4a8173));
  assert.ok(has(-2.1, -6.075, 59.3, 0x518779));
  assert.ok(has(-9.25, 7.4, 64.58, 0xc48445));
});

test('paired white stair flights rise above the forecourt and straddle the glass entrance', () => {
  for (const x of [-21, -13.1, 10.5, 18.4]) {
    assert.ok(has(x, -61.2, 39.4, 0xc5bbab));
    assert.ok(has(x, -48.95, 44.7, 0xeee4cf));
  }
  assert.ok(has(-13.05, -60.65, 39.65, 0x6f8988));
  assert.ok(has(10.45, -49, 44.18, 0x6f8988));
  assert.ok(has(-19.7, -90.8, 34, 0xc5bbab));
  assert.ok(has(16.5, -82.3, 35.65, 0xeee4cf));
});
