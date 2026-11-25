import test from 'node:test';
import assert from 'node:assert/strict';
import {bikeDockParts,bikeStationPlace} from '../city170-bike-docks.js';
import {streetShopProperties} from '../shop-trades.js';
import {surveyedShopCamera} from '../city-shop-search.js';
import * as views from '../taipei-frontage-cameras.js';

test('a searched storefront uses its surveyed wall angle; points and obstructed shops keep their existing views',()=>{
  const row=['捷安特北投車行分店','北投區','',121.49919961,25.13511061,234.97,'poi/node/3704017725'];
  const camera=surveyedShopCamera(row,views,{clientWidth:980,clientHeight:960});
  assert.ok(camera.pitch<58);
  assert.equal(camera.bearing,270-row[5]+views.frontageViewPresets[views.frontageViews[row[6]]][0]);
  assert.ok(camera.zoom<=21.6 && camera.mobileZoom<=21.6);
  assert.ok(Math.abs(camera.center[0]-row[3])<.00002);
  assert.equal(surveyedShopCamera([...row.slice(0,5),null,row[6]],views),undefined);
  assert.equal(surveyedShopCamera(row,null),undefined);
  const blocked=Object.keys(views.frontageViews).find(id=>views.frontageViews[id]===-1 && !views.frontagePartialViews?.[id]);
  assert.ok(blocked);
  assert.equal(surveyedShopCamera([...row.slice(0,6),blocked],views,{clientWidth:390,clientHeight:700}).pitch,12);
  assert.equal(surveyedShopCamera([...row.slice(0,6),'missing-id'],views),undefined);
  for(const [width,height] of [[390,684],[810,965],[1280,1200]]){
    const c=surveyedShopCamera(row,views,{clientWidth:width,clientHeight:height});
    const compact=width<600;
    const ratio=height/2**c.zoom;
    const preset=views.frontageViewPresets[views.frontageViews[row[6]]];
    const anchors=compact?views.frontageViewHeights.mobile:views.frontageViewHeights.desktop;
    assert.ok(anchors.some(h=>Math.abs(ratio-h/2**preset[compact?3:2])<1e-12));
  }
});

test('a partial solution only opens at a verified eye distance for the active display',()=>{
  const rows={...views,frontageViews:{example:-1},frontagePartialViews:{example:[-1,2,-1,-1,-1,-1,-1]}};
  const row=['商店','','',121.52,25.04,50,'example'];
  const phone=surveyedShopCamera(row,rows,{clientWidth:390,clientHeight:650});
  assert.equal(phone.bearing,270-50+views.frontageViewPresets[2][0]);
  assert.ok(Math.abs(650/2**phone.zoom-667/2**views.frontageViewPresets[2][3])<1e-12);
  assert.equal(surveyedShopCamera(row,rows,{clientWidth:840,clientHeight:650}).pitch,12);
  assert.equal(surveyedShopCamera(row,rows,{clientWidth:390,clientHeight:900}).pitch,12);
});

test('point-only and matched shops preserve source labels and localize raw OSM trade codes',()=>{
  for(const [code,label] of [['bicycle','自行車店'],['mobile_phone','手機行'],['pub','酒吧']]){
    const place={category:code,categoryLabel:code,detail:'北投區',source:'OpenStreetMap'};
    assert.deepEqual(streetShopProperties(place),{...place,categoryLabel:label});
    assert.equal(streetShopProperties({...place,categoryLabel:'單車維修店'}).categoryLabel,'單車維修店');
  }
});

test('docking post uses a branded station node, with at-ground geometry and identifiable card',()=>{
  const properties={kind:'poi',category:'bicycle_rental',brand:'YouBike 2.0',categoryLabel:'bicycle_rental',detail:'bicycle_rental'};
  const feature={id:'poi/node/8889601923',properties,geometry:{type:'Point',coordinates:[121.54825,25.04092]}};
  const parts=bikeDockParts(feature);
  assert.equal(parts.length,7);
  assert.equal(parts[0].properties.base,0);
  assert.ok(parts.every(f=>f.properties.top>f.properties.base));
  assert.ok(parts.some(f=>f.id.endsWith('/solar')));
  const geometries=parts.flatMap(f=>f.geometry.coordinates[0]);
  assert.ok(geometries.every(([x,y])=>Math.abs(x-121.54825)<.000003 && Math.abs(y-25.04092)<.000003));
  for(const overrides of [{brand:undefined},{indoor:'yes'},{offGround:true},{layer:'1'},{building:'yes'},{access:'private'}]){
    assert.deepEqual(bikeDockParts({...feature,properties:{...properties,...overrides}}),[]);
  }
  assert.deepEqual(bikeDockParts({...feature,id:'poi/way/999'}),[]);
  assert.equal(bikeStationPlace(properties).categoryLabel,'YouBike 2.0 租借站');
  assert.equal(bikeStationPlace({...properties,detail:'市府資料'}).detail,'市府資料');
});
