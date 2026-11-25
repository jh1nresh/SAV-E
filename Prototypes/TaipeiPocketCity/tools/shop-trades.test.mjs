import test from 'node:test';
import assert from 'node:assert/strict';
import {placePinStyle} from '../place-pins.js';
import {streetShopPinStyle,streetShopProperties} from '../shop-trades.js';

const loaded={hasImage:()=>true};
const pin=placePinStyle(loaded);
const detail=streetShopPinStyle(loaded,pin);
function evaluate(expr,props,zoom){
  if(!Array.isArray(expr))return expr;
  const [op,...args]=expr,run=value=>evaluate(value,props,zoom);
  switch(op){
    case 'get':return props[args[0]];
    case 'zoom':return zoom;
    case 'step':return run(args[0])>=args[2]?run(args[3]):run(args[1]);
    case '==':return run(args[0])===run(args[1]);
    case 'case':return run(args[0])?run(args[1]):run(args[2]);
    case 'coalesce':return args.map(run).find(v=>v!=null);
    case 'match':{
      const input=run(args[0]);
      for(let i=1;i<args.length-1;i+=2)if([args[i]].flat().includes(input))return run(args[i+1]);
      return run(args.at(-1));
    }
    default:throw new Error('Unsupported '+op);
  }
}

test('shop glyphs replace the regular symbol only at street scale without changing the name or collision',()=>{
  const {['icon-image']:image,...layout}=detail.layout;
  const {['icon-image']:old,...oldLayout}=pin.layout;
  assert.deepEqual(layout,oldLayout);
  const optical={category:'optician',placeId:'poi/node/11233541705',name:'大千眼鏡'};
  assert.equal(evaluate(image,optical,18.99),evaluate(old,optical,18.99));
  assert.equal(evaluate(image,optical,19),'place-trade-optics');
  assert.equal(evaluate(detail.layout['text-field'],optical,20),'大千眼鏡');
  for(const p of [{category:'unknown'},{category:'commerce_store',categoryLabel:'特色店家'},
    {category:'attraction',placeId:'poi/way/1159328965'}]){
    assert.equal(evaluate(image,p,20),evaluate(old,p,20));
    assert.equal(evaluate(detail.paint['text-color'],p,20),evaluate(pin.paint['text-color'],p,20));
  }
  const [,,...cases]=image[4];
  const categories=cases.filter((_,i)=>i%2===0).slice(0,-1).flat();
  assert.equal(new Set(categories).size,categories.length);
});

test('shop details retain the source identity and more specific labels when categories are localized',()=>{
  const shop={name:'大千眼鏡',category:'optician',categoryLabel:'optician',placeId:'poi/node/11233541705',
    point:[121.5119733,25.0530478]};
  assert.deepEqual(streetShopProperties(shop),{...shop,categoryLabel:'眼鏡行'});
  const precise={...shop,categoryLabel:'驗光所'};
  assert.equal(streetShopProperties(precise),precise);
  const unspecified={...shop,category:'shop',categoryLabel:'特色店家'};
  assert.equal(streetShopProperties(unspecified),unspecified);
});
