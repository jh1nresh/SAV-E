#!/usr/bin/env node
// Rebuild with Node 18+ from a generated Pocket City HTML (no browser or npm deps).
// node tools/export-pocket-mesh.mjs cities/tamsui/index.html
// The input's inline kit is executed to draw the models. Use project-generated HTML.
// map-mesh.json offsets and counts refer to vertices, with one terrain anchor per building.
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createContext, runInContext} from 'node:vm';

const sections = ['projection', 'models', 'streetFigures', 'data', 'landmarks', 'city', 'foliage', 'painter'];
const stride = 16; // LE float32 scene x/y/z, then opaque RGB + alpha.
const precision = 10000;
const difference = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = ([x, y, z], [u, v, w]) => [y * w - z * v, z * u - x * w, x * v - y * u];
const dot = (a, b) => a.reduce((sum, value, axis) => sum + value * b[axis], 0);
const offset = (p, direction, distance) => p.map((value, axis) => value + direction[axis] * distance);
const pointKey = p => p.map(v => Math.round(v * precision)).join(',');
const signedArea = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);

function polygonNormal(points) {
  const normal = [0, 0, 0];
  for (let i = 1; i < points.length - 1; i++) {
    const n = cross(difference(points[i], points[0]), difference(points[i + 1], points[0]));
    for (let j = 0; j < 3; j++) normal[j] += n[j];
  }
  return normal;
}

export function triangulate(points) {
  const distinct = [];
  for (const point of points) {
    if (!distinct.length || pointKey(point) !== pointKey(distinct.at(-1))) distinct.push(point);
  }
  if (distinct.length > 1 && pointKey(distinct[0]) === pointKey(distinct.at(-1))) distinct.pop();
  if (distinct.length < 3) return [];
  const normal = polygonNormal(distinct);
  const drop = [0, 1, 2].sort((a, b) => Math.abs(normal[b]) - Math.abs(normal[a]))[0];
  if (Math.abs(normal[drop]) < 1e-8) return [];
  const axes = drop === 1 ? [2, 0] : drop === 2 ? [0, 1] : [1, 2];
  const flat = distinct.map(p => axes.map(axis => p[axis]));
  const order = flat.map((_, i) => i);
  const orientation = Math.sign(normal[drop]);
  const area = (a, b, c) => orientation * signedArea(flat[a], flat[b], flat[c]);
  const triangles = [];
  while (order.length > 3) {
    let clipped = false;
    for (let i = 0; i < order.length; i++) {
      const a = order[(i + order.length - 1) % order.length], b = order[i], c = order[(i + 1) % order.length];
      const turn = area(a, b, c);
      if (Math.abs(turn) < 1e-8) {
        order.splice(i, 1);
        clipped = true;
        break;
      }
      if (turn < 0 || order.some(j => j !== a && j !== b && j !== c &&
        area(a, b, j) >= -1e-8 && area(b, c, j) >= -1e-8 && area(c, a, j) >= -1e-8)) continue;
      triangles.push([distinct[a], distinct[b], distinct[c]]);
      order.splice(i, 1);
      clipped = true;
      break;
    }
    if (!clipped) throw new Error('Kit polygon cannot be triangulated');
  }
  if (Math.abs(area(...order)) >= 1e-8) triangles.push(order.map(index => distinct[index]));
  return triangles;
}

export function triangulateEvenOdd(rings) {
  // The kit uses multi-ring fills for planar caps with courtyards. In each
  // band, alternating edge pairs delimit the opaque strips.
  const norm = polygonNormal(rings[0]);
  const [discard, x, y] = [0, 1, 2].sort((a, b) => Math.abs(norm[b]) - Math.abs(norm[a]));
  if (Math.abs(norm[discard]) < 1e-8) return [];
  const ys = [...new Set(rings.flatMap(ring => ring.map(p => p[y])))].sort((a, b) => a - b);
  const edges = rings.flatMap(ring => ring.map((a, i) => [a, ring[(i + 1) % ring.length]]))
    .filter(([a, b]) => a[y] !== b[y]);
  const at = ([a, b], level) => {
    const t = (level - a[y]) / (b[y] - a[y]);
    return a.map((value, axis) => value + t * (b[axis] - value));
  };
  const triangles = [];
  for (let i = 1; i < ys.length; i++) {
    const start = ys[i - 1], end = ys[i], mid = (start + end) / 2;
    const crossings = edges.filter(([a, b]) => (a[y] < mid) !== (b[y] < mid))
      .sort((a, b) => at(a, mid)[x] - at(b, mid)[x]);
    if (crossings.length % 2) throw new Error('Kit path has an unpaired courtyard edge');
    for (let j = 0; j < crossings.length; j += 2) {
      const [a, b] = crossings.slice(j, j + 2);
      triangles.push(...triangulate([at(a, start), at(b, start), at(b, end), at(a, end)]));
    }
  }
  return triangles;
}

function verticalPlane(points, viewer) {
  const normal = polygonNormal(points), size = Math.hypot(...normal);
  if (size < 1e-8) return null;
  const direction = normal.map(v => v * (dot(normal, viewer) < 0 ? -1 : 1) / size);
  const plane = dot(points[0], direction);
  if (Math.abs(direction[2]) > .001 ||
      points.some(point => Math.abs(dot(point, direction) - plane) > .0002)) return null;
  const limits = [0, 1, 2].map(axis => {
    const values = points.map(point => point[axis]);
    return [Math.min(...values), Math.max(...values)];
  });
  return {direction, plane, limits};
}

function inkStrips(points, width, viewer) {
  const strips = [];
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i], along = difference(b, a);
    const horizontal = Math.hypot(along[0], along[1]);
    const upright = Math.abs(along[2]) > horizontal * 1.35;
    const reference = upright ? [viewer[0], viewer[1], 0] : [0, 0, 1];
    const perpendicular = cross(along, reference), magnitude = Math.hypot(...perpendicular);
    if (magnitude < 1e-8) continue;
    const normal = perpendicular.map(value => value / magnitude);
    const start = offset(a, reference, .009), end = offset(b, reference, .009);
    strips.push([offset(start,normal,width), offset(start,normal,-width),
      offset(end,normal,-width), offset(end,normal,width)]);
  }
  return strips;
}

function colorOf(text, backing = [216, 204, 184], opacity = 1) {
  let rgb;
  if (/^#[0-9a-f]{3,8}$/i.test(text)) {
    const hex = text.slice(1);
    const n = hex.length <= 4 ? [...hex].map(h => parseInt(h + h, 16)) : hex.match(/../g).map(h => parseInt(h, 16));
    rgb = n.slice(0, 3);
    if (n.length > 3) opacity *= n[3] / 255;
  } else if (/^rgba?\(/.test(text)) {
    const n = text.slice(text.indexOf('(') + 1, -1).split(',').map(Number);
    if (n.some(value => !Number.isFinite(value))) return null;
    rgb = n.slice(0, 3);
    if (n.length > 3) opacity *= n[3];
  }
  return rgb?.length === 3 ? rgb.map((value, channel) => Math.round(value * opacity + backing[channel] * (1 - opacity))) : null;
}

function extract(html) {
  const blocks = Object.fromEntries([...html.matchAll(/<script type="text\/plain" id="([^"]+)">([\s\S]*?)<\/script>/g)]
    .map(([, id, source]) => [id, source]));
  for (const section of sections) {
    if (!(section in blocks)) throw new Error(`Missing Pocket City kit script ${section}`);
  }
  const capture = /const pdR = \(rw,pts,close=true\)=>\{[\s\S]*?\n\};(?=\nconst pd = )/;
  if (!capture.test(blocks.projection)) throw new Error('Unsupported Pocket City projection');
  blocks.projection = blocks.projection.replace(capture, 'const pdR = (rw, pts, close=true) => capturePath(pts, close);');
  // Register model ownership at the original creation sites, so landmark builds
  // are run once and share their original building identifiers and footprints.
  const modelLine = 'models.push(buildingModel(b));';
  const landmarkLine = 'for(const lm of LANDMARK_LIST){try{const out=lm.build();for(const m of [].concat(out))if(m)models.push(m)}catch(e){console.error(\'landmark\',lm.name,e)}}';
  if (!blocks.city.includes(modelLine) || !blocks.city.includes(landmarkLine)) throw new Error('Unsupported Pocket City model registry');
  blocks.city = blocks.city.replace(modelLine, `models.push({...buildingModel(b), owner: b.of || b.id, label: b.n});`)
    .replace(landmarkLine, `for(const lm of LANDMARK_LIST) {
      for(const model of [].concat(lm.build())) if (model) models.push({...model, landmark: lm});
    }`);
  return sections.map(section => blocks[section]).join('\n');
}

function clipToWall(points, length, height) {
  // Sutherland–Hodgman against the kit Canvas façade's rectangular clip.
  for (const [axis, bound, sign] of [[0, 0, 1], [0, length, -1], [1, 0, 1], [1, height, -1]]) {
    if (!points.length) break;
    const clipped = [];
    for (let i = 0; i < points.length; i++) {
      const a = points[(i + points.length - 1) % points.length], b = points[i];
      const aIn = (a[axis] - bound) * sign >= 0, bIn = (b[axis] - bound) * sign >= 0;
      if (aIn !== bIn) {
        const t = (bound - a[axis]) / (b[axis] - a[axis]);
        clipped.push(a.map((v, j) => v + (b[j] - v) * t));
      }
      if (bIn) clipped.push(b);
    }
    points = clipped;
  }
  return points;
}

function wallPainter(face, painter, id) {
  const paints = [];
  const stack = [];
  let x = 0, y = 0, scale = 1, path = [];
  const point = (u, v) => [u * scale + x, v + y];
  const g = {
    save() { stack.push([x, y, scale, this.fillStyle]); },
    restore() { [x, y, scale, this.fillStyle] = stack.pop(); },
    // The outer transform describes this wall's screen frame; we keep wall-local axes.
    transform() {}, clip() {}, closePath() {}, fillText() {},
    scale(v) { scale *= v; },
    translate(u, v) { x += u * scale; y += v; },
    beginPath() { path = []; },
    rect(a, b, w, h) { path = [point(a,b), point(a+w,b), point(a+w,b+h), point(a,b+h)]; },
    moveTo(a, b) { path.push(point(a, b)); },
    lineTo(a, b) { path.push(point(a, b)); },
    fill() { paints.push([path, this.fillStyle]); },
    fillRect(a, b, w, h) { this.rect(a,b,w,h); this.fill(); },
  };
  painter(g, id);
  return paints.map(([path, paint], order) => {
    const offset = .014 + .017 * order / paints.length;
    return [clipToWall(path, face.len, face.h - face.z).map(([u, v]) => [
      face.start[0] + face.along[0] * u + face.n[0] * offset,
      face.start[1] + face.along[1] * u + face.n[1] * offset,
      face.h - v,
    ]), colorOf(paint, colorOf(face.body) || undefined)];
  });
}

function center(models) {
  const vertices = models.flatMap(m => m.fp);
  return [0, 1].map(axis => (Math.min(...vertices.map(p => p[axis])) + Math.max(...vertices.map(p => p[axis]))) / 2);
}

const cameras = [
  ...[14, 59].flatMap(pitch => Array.from({length: 8}, (_, i) => [22.5 + i * 45, pitch])),
  ...Array.from({length: 4}, (_, i) => [45 + i * 90, -15]),
];

// Preserve original polygon boundaries only. Triangulation diagonals are not ink.
function recordSourceStroke(paths,attrs,source,kit,cache,lines) {
  const style=source.replace(/\bd="[^"]*"/,'d=""');
  if(!cache.has(style))cache.set(style,kit.stroke('<path '+style+'/>'));
  const [stroke,width,opacity]=cache.get(style);
  if(opacity!==1)throw Error('Unsupported translucent architectural ink');
  const rgb=colorOf(stroke);
  if(!rgb || width<=0)return;
  const signedWidth=attrs.style?.includes('stroke-width:')?-width:width;
  for(const {points,close} of paths){
    for(let n=1;n<points.length+(close?1:0);n++){
      const a=points[n-1], b=points[n%points.length];
      const ka=pointKey(a), kb=pointKey(b);
      if(ka===kb)continue;
      const key=ka<kb?ka+';'+kb:kb+';'+ka;
      lines.set(key,{a,b,rgb,width:signedWidth});
    }
  }
}

export function exportMesh(html, {paintedInk=false}={}) {
  const paths = [];
  const capturePath = (points, close) => {
    paths.push({points: Array.from(points, p => [Number(p[0]), Number(p[1]), Number(p[2] ?? 0)]), close});
    return `@${paths.length - 1}@`;
  };
  const context = createContext({capturePath, self: {PHONE_PROFILE:false, PAGE_SEARCH:paintedInk?'?season=warm':''}, URLSearchParams, console,
    Path2D: class { moveTo() {} lineTo() {} }},
    {codeGeneration:{strings:false, wasm:false}});
  // The optional 101 transport asks the original Canvas compiler for its line
  // colors and widths. Fixed-width ink is evaluated at one CSS pixel per unit.
  const painter=paintedInk?`
    referenceView:[CITY.cameras.iso.yaw,CITY.cameras.iso.pitch],
    stroke(markup) {
      const [op]=compileInk(markup);
      return [op.stroke,op.width,op.alpha*op.strokeAlpha];
    },`:'';
  const script = `${extract(html)}\n({${painter}models, facades, buildings:SCENE.buildings, paint:paintSingaporeElevation, camera:(yaw,pitch)=>{
    setCam(yaw,pitch); PITCH=pitch; const basis=camBasis(yaw,pitch);
    CAM_R=basis.R; CAM_U=basis.U; CAM_V=basis.V; CAM_D=CAM_U.map(v=>-v);
    UPX=.72; ${paintedInk?'INK_K=.83;':'SEASON={};'}
  }})`;
  const kit = runInContext(script, context, {filename:'pocket-city-kit.js', timeout:15000});
  const groups = new Map();
  for (const model of kit.models) {
    const owner = model.landmark || model.owner;
    if (!groups.has(owner)) groups.set(owner, []);
    groups.get(owner).push(model);
  }
  const parts = [], vertices = [], ink=[], fallback=[];
  const paintCache=new Map();
  for (const [owner, models] of groups) {
    const first = vertices.length, firstInk=ink.length;
    const sourceLines=new Map();
    const faceKeys = new Set(), canvasFaces = new Set(), planes = new Map(), inkPaths = new Set();
    const add = (rings, rgb, viewer) => {
      if (!rgb || rings[0].length < 3) return;
      const key = rings.map(points => points.map(pointKey).sort().join(';')).join('|');
      if (faceKeys.has(key)) return;
      if (!rings.every(points => points.every(point => point.every(Number.isFinite)))) throw new Error('Non-finite kit geometry');
      faceKeys.add(key);
      // Paint that shares an authored wall plane needs a small outward offset
      // in draw order to stay visible once hardware depth testing replaces Canvas.
      const plane = viewer && verticalPlane(rings[0], viewer);
      let raised = rings;
      if (plane) {
        const {direction, plane: z, limits} = plane;
        const planeKey = [pointKey(direction), Math.round(z * precision)].join(',');
        const surfaces = planes.get(planeKey) || [];
        const earlierDepth = surfaces.reduce((depth, earlier) => {
          const intersects = limits.every(([min, max], axis) => {
            const [lo, hi] = earlier.limits[axis];
            if (max - min < .0002 && hi - lo < .0002) return Math.abs(min - lo) < .0002;
            return min < hi - .0002 && max > lo + .0002;
          });
          return intersects ? Math.max(depth, earlier.depth + .0015) : depth;
        }, 0);
        surfaces.push({limits, depth:earlierDepth});
        planes.set(planeKey, surfaces);
        if (earlierDepth) raised = rings.map(points => points.map(point => offset(point, direction, earlierDepth)));
      }
      const triangles = raised.length === 1 ? triangulate(raised[0]) : triangulateEvenOdd(raised);
      for (const triangle of triangles) for (const p of triangle) vertices.push([...p, ...rgb]);
    };
    // In the acceptance camera, the later visible face owns a shared edge.
    // Additional angles supply faces absent from that first view.
    const views=paintedInk?[kit.referenceView,...cameras]:cameras;
    for (const view of views) {
      const [yaw,pitch]=view;
      const referenceInkView=paintedInk && view===views[0];
      const viewLines=new Map();
      kit.camera(yaw, pitch);
      const a = yaw * Math.PI / 180, b = pitch * Math.PI / 180;
      const viewer = [Math.cos(a) * Math.cos(b), Math.sin(a) * Math.cos(b), Math.sin(b)];
      for (const model of models) {
        paths.length = 0;
        const svg = model.draw();
        for (const [, kind, source] of svg.matchAll(/<(path|elevation)\b([^>]*)>/g)) {
          const attrs = Object.fromEntries([...source.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value]));
          if (kind === 'elevation') {
            if(referenceInkView)continue;
            const id = Number(attrs.id);
            if (canvasFaces.has(id)) continue;
            canvasFaces.add(id);
            for (const [points, rgb] of wallPainter(kit.facades[id], kit.paint, id)) add([points], rgb);
          } else {
            if (!/^(?:@\d+@)+$/.test(attrs.d)) continue; // Screen-space ink stays in the kit.
            const captured = [...attrs.d.matchAll(/@(\d+)@/g)].map(([, index]) => paths[Number(index)]);
            if(paintedInk && attrs.stroke && attrs.stroke!=='none'){
              recordSourceStroke(captured, attrs, source, kit, paintCache, viewLines);
            }
            if(referenceInkView)continue; // Preserve the normal mesh and legacy strip camera order.
            if (attrs.fill && attrs.fill !== 'none' && captured.every(path => path.close)) {
              if (captured.length > 1 && attrs['fill-rule'] !== 'evenodd') throw new Error('Unsupported multi-ring fill rule');
              add(captured.map(path => path.points), colorOf(attrs.fill, undefined, Number(attrs.opacity || 1)), viewer);
            }
            if (attrs.fill === 'none' && attrs.stroke && attrs.stroke !== '#231e16' && captured.length === 1) {
              const [{points, close}] = captured;
              const key = points.map(pointKey).join(';') + attrs.stroke;
              const measured = Number(attrs['stroke-width'] || attrs.style?.match(/stroke-width:([\d.]+)/)?.[1] || 0);
              if (close || !measured || inkPaths.has(key)) continue;
              inkPaths.add(key);
              const rgb = colorOf(attrs.stroke);
              const stripStart=vertices.length;
              for (const strip of inkStrips(points, Math.min(.06, measured * .05), viewer)) add([strip], rgb);
              if(paintedInk&&vertices.length>stripStart)fallback.push([stripStart,vertices.length]);
            }
          }
        }
      }
      for(const [key,line] of viewLines)if(!sourceLines.has(key))sourceLines.set(key,line);
    }
    for(const line of sourceLines.values())ink.push(line);
    const count = vertices.length - first;
    if (!count) throw new Error(`Empty mesh for ${owner.name || owner}`);
    const natural = owner.ids?.flatMap(id => kit.buildings.filter(b => b.id === id || b.of === id));
    const at = center(natural?.length ? natural.map(b => ({fp:b.ring})) : models);
    const label = owner.name || models[0].label;
    parts.push({first,count,at:at.map(v => Math.round(v * precision) / precision), ...(label && {name:label}), ...(paintedInk&&{firstInk,inkCount:ink.length-firstInk})});
  }
  const buffer = Buffer.allocUnsafe(vertices.length * stride);
  for (const [i, [x, y, z, red, green, blue]] of vertices.entries()) {
    const offset = i * stride;
    buffer.writeFloatLE(x, offset);
    buffer.writeFloatLE(y, offset + 4);
    buffer.writeFloatLE(z, offset + 8);
    buffer[offset + 12] = red; buffer[offset + 13] = green; buffer[offset + 14] = blue; buffer[offset + 15] = 255;
  }
  return {buffer, parts,...(paintedInk&&{ink,fallback})};
}

async function main(inputs) {
  if (!inputs.length) throw new Error('Usage: node tools/export-pocket-mesh.mjs cities/<city>/index.html [...]');
  for (const path of inputs) {
    const {buffer, parts} = exportMesh(await readFile(path, 'utf8'));
    await writeFile(join(dirname(path), 'map-mesh.bin'), buffer);
    await writeFile(join(dirname(path), 'map-mesh.json'), JSON.stringify({parts}) + '\n');
    console.log(`${path}: ${buffer.length / (3 * stride)} triangles in ${parts.length} building parts`);
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) await main(process.argv.slice(2));
