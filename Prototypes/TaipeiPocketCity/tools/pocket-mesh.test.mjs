import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {exportMesh, triangulate, triangulateEvenOdd} from './export-pocket-mesh.mjs';

const cities = JSON.parse(await readFile(new URL('../cities/catalog.json',import.meta.url))).map(c=>c.id);
const file = (city, name) => readFile(new URL(`../cities/${city}/${name}`, import.meta.url));
const triangleArea = ([a, b, c]) => Math.abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])) / 2;
const polygonArea = ring => Math.abs(ring.reduce((area, [x, y], i) => {
  const [u, v] = ring[(i + 1) % ring.length];
  return area + x * v - y * u;
}, 0)) / 2;
const vertices = (mesh, {first, count}) => Array.from({length:count}, (_, i) => {
  const at = (i + first) * 16;
  return [mesh.readFloatLE(at), mesh.readFloatLE(at + 4), mesh.readFloatLE(at + 8),
    mesh.readUIntBE(at + 12, 3), mesh[at + 15]];
});

const readCity = async city => ({mesh:await file(city, 'map-mesh.bin'), parts:JSON.parse(await file(city, 'map-mesh.json')).parts});

const band = (points, color, height) => points.filter(p => p[3] === color && Math.abs(p[2] - height) < .001);

test('triangulation keeps reentrant walls and a roof courtyard open', () => {
  const bend = [[0,0,1],[4,0,1],[4,4,1],[2,2,1],[0,4,1],[0,0,1]];
  const outer = [[0,0,1],[8,0,1],[8,8,1],[0,8,1]];
  const inner = [[2,3,1],[6,3,1],[6,6,1],[2,6,1]];
  const area = tris => tris.reduce((sum, tri) => sum + triangleArea(tri), 0);
  assert.equal(area(triangulate(bend)), 12);
  assert.equal(area(triangulateEvenOdd([outer,inner])), 52);
});

for (const city of cities) {
  test(`${city} mesh reproduces the inlined kit and covers its declared segments`, async () => {
    const [{mesh,parts}, html] = await Promise.all([readCity(city), file(city,'index.html')]);
    const rebuilt = exportMesh(html.toString('utf8'));
    assert.ok(mesh.equals(rebuilt.buffer));
    assert.deepEqual(parts, rebuilt.parts);
    let endpoint = 0;
    for (const part of parts) {
      assert.equal(part.first, endpoint);
      assert.ok(part.count % 3 === 0 && part.count > 0);
      assert.ok(part.at.length === 2 && part.at.every(Number.isFinite));
      assert.ok(vertices(mesh, part).every(([x,y,z,,a]) => [x,y,z].every(Number.isFinite) && a === 255));
      endpoint += part.count;
    }
    assert.equal(endpoint * 16, mesh.byteLength);
  });
}

test('fort, temple, observatory and Customs House retain authored structure', async () => {
  const landmarks = [
    ['tamsui','淡水紅毛城主堡',19.05,10,40],
    ['beijing','祈年殿',37.38,100,70],
    ['los-angeles','Griffith Observatory',25.25,350,80],
    ['shanghai','上海海關大樓',79.2,100,35],
  ];
  for (const [city,name,height,minSlopes,minColors] of landmarks) {
    const {mesh,parts} = await readCity(city);
    const points = vertices(mesh,parts.find(part => part.name === name));
    assert.ok(Math.abs(Math.max(...points.map(([, , z]) => z)) - height) < .035, name);
    assert.ok(new Set(points.map(p=>p[3])).size >= minColors, name);
    let slopes = 0;
    for (let i = 0; i < points.length; i += 3) {
      if (new Set(points.slice(i,i+3).map(p=>Math.round(p[2]*1000))).size === 3) slopes++;
    }
    assert.ok(slopes >= minSlopes, name);
  }
});

test('exported bank roof area matches its WGS-aligned kit footprint less the courtyard', async () => {
  const {mesh,parts} = await readCity('shanghai');
  const scene = JSON.parse(await file('shanghai','scene.json'));
  const bank = scene.buildings.find(b => b.id === 'r2380996');
  assert.ok(bank.holes.length > 0);
  const roof = band(vertices(mesh,parts.find(part => part.name === '前匯豐銀行大樓')),0xab9f8f,28.1);
  const expected = polygonArea(bank.ring) - bank.holes.reduce((sum, ring) => sum + polygonArea(ring), 0);
  let area = 0;
  for (let i=0; i<roof.length; i+=3) area += triangleArea(roof.slice(i,i+3));
  assert.ok(Math.abs(area - expected) < .1, `Roof area ${area} differs from the mapped ${expected} m²`);
});
