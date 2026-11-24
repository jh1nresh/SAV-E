// Fort, residence and South Gate. Local XY metres follow the preserved OSM rings
// in scene.json. Roof subdivisions and heights are proportions from the museum
// plan and the New Taipei tourism site's views of both sides of the courtyard.
const BRICK = '#a8513d';
const TILE = '#b75e41';
const mortar = '#c68a69';
const arcadeGreen = '#407464';

// The archive's two aerial views show a clear lawn between the fort and the
// residence. The prep tool's park scatter has no mapped trees in this plot.
SCENE.trees = SCENE.trees.filter(([x,y]) => !(x > 15 && x < 49 && y > 10 && y < 40)
  && !(x > 43 && x < 77 && y > 12 && y < 18));

function onEdge(ring, decoration) {
  const r = ccw(ring);
  return r.map((a, i) => {
    const b = r[(i + 1) % r.length];
    const length = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (length < .1) return '';
    const u = [(b[0] - a[0]) / length, (b[1] - a[1]) / length];
    const n = [u[1], -u[0], 0];
    const at = (s, z, d = .035) => [a[0] + s * u[0] + d * n[0], a[1] + s * u[1] + d * n[1], z];
    return vis(n) ? decoration(at, length, n) : '';
  }).join('');
}

function facadeRect(at, left, right, bottom, top, color, ink = .32) {
  return shape([at(left, bottom), at(right, bottom), at(right, top), at(left, top)], color, ink);
}

function arch(at, x, base, half, spring, color) {
  const curve = Array.from({length: 11}, (_, i) => {
    const theta = i * Math.PI / 10;
    return at(x + half * Math.cos(theta), spring + half * Math.sin(theta));
  });
  return shape([at(x - half, base), at(x + half, base), ...curve], color, .37);
}

function trimLedge(ring, bottom, top, color) {
  return block(ring, bottom, top, {facade: 'plain', wall: color, flatRoof: color, shop: 'none'});
}

function tiledPart(ring, z, h, roofFrame) {
  const wall = block(ring, z, h, {facade: 'brick', wall: BRICK, floor: 3.6, trim: mortar, shop: 'none', shutters: arcadeGreen});
  const roof = roofOver(roofFrame, h, {roof: 'hipped', pitch: 26, eaves: .24, roofColour: TILE, roofTex: 'pantile'});
  return {fp: ring, z1: h + 3.6, draw: () => wall.draw() + roof()};
}

function tamsuiFort() {
  const b = findBuilding('r3986680');
  const core = [[-.89, 11.35], [15.93, 11.31], [16.06, 27.96], [-.77, 28.02]];
  const turret = rect(.15, 12.4, 2.05, 1.85);
  const turretWall = trimLedge(turret, 8.4, 13.1, '#925b4e');
  const stairHeadRing = rect(2.45, 14.9, 3.1, 2.55);
  const stairHead = tiledPart(stairHeadRing, 11.65, 12.9, {c: [2.45, 14.9], ax: [1,0], L: 3.1, W: 2.55});
  const annex = [
    tiledPart(rect(-6.5, 18.75, 8, 3.2), 0, 2.3, {c: [-6.5,18.75], ax:[1,0], L:8, W:3.2}),
    tiledPart(rect(-10.02, 22.5, .95, 10.6), 0, 2.4, {c:[-10.02,22.5], ax:[0,1], L:10.6, W:.95}),
    tiledPart(rect(-4.95, 27.5, 9.75, .85), 0, 2.45, {c:[-4.95,27.5], ax:[1,0], L:9.75, W:.85}),
  ];
  const entrance = rect(9.34, 10.18, 7.2, 2.75);
  const entryWall = trimLedge(entrance, 0, 4.75, '#9d5640');
  const parapet = [];
  for (let i = 0; i < core.length; i++) {
    const a = core[i], next = core[(i + 1) % core.length];
    const L = Math.hypot(next[0] - a[0], next[1] - a[1]);
    const ax = [(next[0] - a[0]) / L, (next[1] - a[1]) / L];
    const n = [-ax[1], ax[0]];
    for (let j = 0; j < 8; j++) {
      const middle = (j + .5) * L / 8;
      const center = [a[0] + ax[0] * middle + n[0] * .21, a[1] + ax[1] * middle + n[1] * .21];
      const ring = rect(0, 0, L / 8 - .01, .43).map(([x,y]) => [center[0] + x*ax[0] + y*n[0], center[1] + x*ax[1] + y*n[1]]);
      const h = j % 2 ? 12.13 : 12.48;
      parapet.push(trimLedge(ring, 11.65, h, '#ab5847'));
      parapet.push(trimLedge(ring, h, h + .13, '#776e64'));
    }
  }
  const drawCore = () => {
    const roofDeck = shape(atZ(core,11.65),TILE,.7) + sheetInk(atZ(core,11.66),'tiles',[1,0,0],[0,1,0]);
    const coreWalls = onEdge(core, (at, width, n) => {
      const m = width / 2;
      const wallColor = n[1] < -.5 ? '#c76a52' : n[0] < 0 ? '#ad5947' : '#b95947';
      let details = facadeRect(at,0,width,0,11.65,wallColor,.64)
        + facadeRect(at,0,width,0,.82,'#837765',.44)
        + edge(at(0,6.72,.046),at(width,6.72,.046),'#a14f43',.18);
      for (const offset of [-4.35, 3.9]) {
        details += facadeRect(at, m + offset -.31, m + offset + .31, 4.92, 6.26, '#563846');
        details += facadeRect(at, m + offset -.54, m + offset + .54, 4.76, 4.93, '#dfb39b');
        details += facadeRect(at, m + offset -.31, m + offset + .31, 2.07, 3.05, '#654245');
      }
      if (UPX < .32) for (let z=.19;z<.82;z+=.2) details+=edge(at(0,z,.048),at(width,z,.048),'#aea08d',.10);
      if (n[1] < -.85) details += arch(at, m + 1, .1, .95, 1.86, '#472e31');
      return details;
    });
    const steps = [];
    for (let i = 0; i < 4; i++) {
      const y = 8.48 + i * .35;
      const r = rect(9.28, y, 2.65, .36);
      steps.push(shape(atZ(r, .26 * (i + 1)), '#aaa395', .32));
      steps.push(shape([...atZ(r.slice(0,2),.26*i),...atZ(r.slice(0,2).reverse(),.26*(i+1))], '#877e73', .35));
    }
    const front = entryWall.draw() + onEdge(entrance, (at, width, n) => n[1] < -.85 ?
      arch(at,width/2,1,1.15,2.5,'#574034') + facadeRect(at, .5,1.6,1.35,2.64,arcadeGreen) + facadeRect(at,width-1.6,width-.5,1.35,2.64,arcadeGreen) : '')
      + roofOver({c:[9.34,10.18],ax:[1,0],L:7.2,W:2.75},4.73,{roof:'gabled',pitch:28,eaves:.22,roofColour:TILE,roofTex:'pantile'})();
    const low = planOrder([{fp:core,z1:11.65,svg:coreWalls+roofDeck},
      ...annex.map(p=>({...p,svg:p.draw()})), {fp:entrance,z1:5.6,svg:steps.join('')+front}]);
    const pole = [1.13,13.15,12.7], tip = [1.13,13.15,19.05];
    const flag = shape([tip,[4.4,13.35,18.92],[4.43,13.29,17.52],[1.13,13.15,17.5]],'#bf4044',.25)
      +shape([tip,[2.76,13.25,18.98],[2.76,13.25,18.23],[1.13,13.15,18.27]],'#31527b',0)
      +ball([1.96,13.21,18.63],.15,soft('#f5eadb'));
    return low+planOrder([...parapet, turretWall, stairHead].map(p=>({...p,svg:p.draw()})))+
      stick(pole,tip,.06,'#eee8da')+flag;
  };
  return obj(b.ring, 19.1, drawCore);
}

function tamsuiResidence() {
  const b = findBuilding('w290499654');
  const main = [[46.46,17.29],[74.69,17.31],[74.72,26.93],[73.19,26.93],[73.19,29.59],[70.34,29.59],
    [70.36,36.21],[50.01,35.94],[50.0,29.81],[47.72,29.8],[47.7,26.85],[46.48,26.86]];
  const wing = [[51.03,35.95],[63.4,36.21],[63.44,49.54],[51.06,49.52]];
  const clothes = '#a45a42';
  const stone = '#96816a';
  const arcade = (ring, floors, high, lower) => {
    const body = trimLedge(ring, 0, high, clothes);
    const base = trimLedge(ring, 0, .68, stone);
    return () => body.draw()+base.draw()+onEdge(ring,(at,L,n) => {
      if (L < 4.3) return '';
      let s = '';
      const count = Math.max(1,Math.round(L / 3.8));
      for (let i = 0; i < count; i++) for (let storey = 0; storey < floors; storey++) {
        const bay = L/count, middle = (i+.5)*bay, lowerFloor = .64 + storey*3.7;
        const half = Math.min(1.19,bay*.33), spring = lowerFloor+1.62;
        s += arch(at,middle,lowerFloor,half+.17,spring,'#c08059');
        s += arch(at,middle,lowerFloor,half,spring,n[1]>.7?'#614844':'#452f32');
        if (storey || i!==Math.round(count/2)-1 || lower) {
          s += facadeRect(at,middle-half,middle+half,lowerFloor+.03,lowerFloor+.55,arcadeGreen);
          for(let k=1;k<8;k++) {
            const x=middle-half+k*half/4;
            s+=edge(at(x, lowerFloor+.07,.044), at(x,lowerFloor+.51,.044),'#99a68a',.16);
          }
        }
        if (UPX < .46) for(let k=0;k<=8;k++) {
          const a=k*Math.PI/8;
          s+=edge(at(middle+half*Math.cos(a),spring+half*Math.sin(a),.043),
            at(middle+(half+.17)*Math.cos(a),spring+(half+.17)*Math.sin(a),.043),'#865748',.16);
        }
      }
      for (const z of [.73,4.24,high-.32].filter(z=>z<high)) s+=edge(at(0,z),at(L,z),mortar,.33);
      return s;
    });
  };
  const southBody = arcade(main, 2, 8.25, false);
  const serviceWing = arcade(wing, 1, 4.2, true);
  const roofStyle = {roof:'hipped',pitch:24,eaves:.29,roofColour:TILE,roofTex:'pantile'};
  const southRoof = roofOver({c:[60.57,22.06],ax:[1,0],L:28.26,W:9.58},8.25,roofStyle);
  const northRoof = roofOver({c:[60.2,31.05],ax:[1,0],L:20.33,W:10.18},8.25,roofStyle);
  const shoulders = [[47.71,28.35],[72.38,28.43]].map(c => roofOver({c,ax:[0,1],L:3.15,W:2.16},8.25,roofStyle));
  const westRoof = roofOver({c:[57.24,42.73],ax:[0,1],L:13.6,W:12.48},4.2,roofStyle);
  const chimneys = [[55.65,29.1],[65.6,23.07]].map(([x,y]) => trimLedge(rect(x,y,.95,.79),9.5,11.12,'#ad644b'));
  return obj(b.ring, 11.25, () => {
    const steps = [];
    for (let i=0;i<4;i++) {
      const r=rect(60.48,16.56+i*.2,2.5,.24);
      steps.push(shape(atZ(r,.16*(i+1)),'#aba292',.34));
    }
    return planOrder([{fp:main,z1:11.25,svg:southBody()+steps.join('')+northRoof()+shoulders.map(r=>r()).join('')+southRoof()+chimneys.map(c=>c.draw()).join('')},
      {fp:wing,z1:6.7,svg:serviceWing()+westRoof()}]);
  });
}

function tamsuiSouthGate() {
  const b = findBuilding('w297301287');
  const stone = '#8f8476';
  const gate = trimLedge(b.ring,0,3.2,stone);
  const c = b.obb.c, ax = b.obb.ax, across = [-ax[1], ax[0]];
  const at = (x,y) => [c[0]+x*ax[0]+y*across[0],c[1]+x*ax[1]+y*across[1]];
  const battlements = [];
  for (const side of [-1,1]) for(let i=-2;i<=2;i++){
    const p = rect(i*2.05,side*3.67,1.08,.5).map(([x,y])=>at(x,y));
    battlements.push(trimLedge(p,3.2,3.88,stone));
  }
  return obj(b.ring,3.88,() => gate.draw()+onEdge(b.ring,(at,L) => L>10 ? arch(at,L/2,.03,1.25,1.66,'#4d4138')+
    facadeRect(at,L/2-.86,L/2+.86,2.79,3.06,'#bcaa8c'):'')+planOrder(battlements.map(p=>({...p,svg:p.draw()}))));
}

const LANDMARKS = [
  {name: '淡水紅毛城主堡', ids: ['r3986680'], build: tamsuiFort},
  {name: '前清英國領事官邸', ids: ['w290499654'], build: tamsuiResidence},
  {name: '南門', ids: ['w297301287'], build: tamsuiSouthGate},
];
