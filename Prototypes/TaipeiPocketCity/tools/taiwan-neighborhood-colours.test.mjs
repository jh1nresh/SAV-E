import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {makeTaiwanCoverage} from '../taiwan-coverage.js';
import {applyStreetMaterials,decodeMaterialShard,indexStreetShard,localStreetFeatures} from '../taiwan-streets.js';
import {buildTaiwanCells} from '../taiwan-cell-geometry.js';
import {roofDrawing} from '../taiwan-roofs.js';

const root=new URL('../taiwan/',import.meta.url);
const load=name=>{
  const bytes=readFileSync(new URL(name,root));
  return JSON.parse(name.endsWith('.gz')?gunzipSync(bytes):bytes);
};
// Centers of ordinary commercial streets, selected from the same public place index as the pins.
const locations=[
  ["南投縣", 120.695074, 23.944481],
  ["嘉義市", 120.442657, 23.469233],
  ["嘉義縣", 120.246324, 23.466587],
  ["基隆市", 121.73959, 25.131362],
  ["宜蘭縣", 121.74876, 24.745367],
  ["屏東縣", 120.493824, 22.672377],
  ["彰化縣", 120.557545, 24.083589],
  ["新北市", 121.479422, 25.018191],
  ["新竹市", 120.96914, 24.80534],
  ["新竹縣", 121.005478, 24.838519],
  ["桃園市", 121.288179, 24.988394],
  ["澎湖縣", 119.564663, 23.564257],
  ["臺中市", 120.661665, 24.155354],
  ["臺南市", 120.214658, 22.994361],
  ["臺東縣", 121.147005, 22.752906],
  ["花蓮縣", 121.601211, 23.987193],
  ["苗栗縣", 120.824645, 24.570162],
  ["連江縣", 119.951692, 26.156421],
  ["金門縣", 118.318681, 24.435727],
  ["雲林縣", 120.533857, 23.713269],
  ["高雄市", 120.285092, 22.624063],
];

test('each non-Taipei county paints local houses, roofs and façades from its real street shard',()=>{
  const coverage=makeTaiwanCoverage(load('townships.geojson.gz'),load('cells.json'));
  const materials=load('materials/index.json');
  assert.deepEqual(locations.map(([county])=>county).sort(),Object.keys(materials.counties).sort());
  for(const [county,x,y] of locations){
    assert.equal(coverage.at(x,y)?.county,county);
    const a=Math.floor(x*32),b=Math.floor(y*32),key=a+'-'+b;
    const materialKey=Math.floor(a/materials.tilesPerGroup)+'-'+Math.floor(b/materials.tilesPerGroup);
    const shard=indexStreetShard(key,load('streets/'+key+'.json.gz'));
    const bounds=[x-.0014,y-.0014,x+.0014,y+.0014];
    const scope={contains:(lng,lat)=>coverage.at(lng,lat)?.county===county,exclude:()=>false};
    const data=localStreetFeatures([shard],bounds,19,scope);
    if(materials.tiles.includes(materialKey))applyStreetMaterials(data.buildings,[decodeMaterialShard(load('materials/'+materialKey+'.json.gz'))]);
    const scene={...scope,view:bounds,center:[x,y],tiles:{
      ways:data.roads,pois:data.pois,buildings:data.buildings,woods:[],fields:[],water:[],
    }};
    const {details}=buildTaiwanCells({...scene,zoom:19});
    const middle=buildTaiwanCells({...scene,zoom:15}).details;
    const midInk=new Map(middle.filter(f=>f.properties.kind==='building'||f.properties.kind==='roof')
      .map(f=>[f.properties.kind+JSON.stringify(f.geometry),f.properties.color]));
    for(const f of details.filter(f=>f.properties.kind==='building'||f.properties.kind==='roof')){
      assert.equal(midInk.get(f.properties.kind+JSON.stringify(f.geometry)),f.properties.color,county+' zoom colour continuity');
    }
    const inks=kind=>new Set(details.filter(f=>f.properties.kind===kind).map(f=>f.properties.color));
    assert.ok(inks('building').size>=3,county+' wall finishes');
    assert.ok(inks('roof').size>=2,county+' roof finishes');
    assert.ok(inks('window-frame').size>=2,county+' window frames');
  }
});

test('roof planes follow the recorded shape, leave courtyards open and preserve summit height',()=>{
  const rect=[[120,23],[120.00018,23],[120.00018,23.00009],[120,23.00009],[120,23]];
  const style={wall:'#f1a672',roof:'#74767e'};
  for(const shape of ['gabled','hipped','pyramidal']){
    const {eave,faces}=roofDrawing([rect],12,{'roof:shape':shape},style,19);
    assert.ok(eave<12);assert.equal(faces.length,4);
    assert.equal(Math.max(...faces.flatMap(face=>face.p.map(p=>p[2]))),12);
  }
  assert.equal(roofDrawing([rect],12,{'roof:shape':'gabled',suppressPitchedRoof:true},style,19),undefined);
  assert.ok(roofDrawing([rect],12,{},style,19).rim[1].length);
  assert.equal(roofDrawing([rect,rect],12,{'roof:shape':'hipped'},style,19),undefined);
});


test('tall streetside towers keep their glazing and floor divisions up to the roof',()=>{
  const outline=[[120,23],[120.00024,23],[120.00024,23.00022],[120,23.00022],[120,23]];
  const building={id:45,properties:{render_height:86},geometry:{type:'Polygon',coordinates:[outline]}};
  const {details}=buildTaiwanCells({view:[119.9999,22.9999,120.0004,23.0004],center:[120.00015,23.0001],
    zoom:19,contains:()=>true,exclude:()=>false,tiles:{buildings:[building],ways:[],pois:[],woods:[],fields:[],water:[]}});
  const panes=details.filter(f=>f.properties.kind==='curtain-wall');
  assert.equal(panes.length,4);
  assert.ok(panes.every(f=>f.properties.height>85));
  assert.ok(details.some(f=>f.properties.kind==='spandrel'&&f.properties.base>75));
});
