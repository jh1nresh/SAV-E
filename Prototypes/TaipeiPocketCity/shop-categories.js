export const shopCategories={
  inspection_store:['餐飲店家','meal'],restaurant:['餐廳','meal'],fast_food:['速食','meal'],food_court:['美食廣場','meal'],
  cafe:['咖啡店','cafe'],ice_cream:['冰品店','cafe'],bakery:['烘焙店','cafe'],
  bar:['酒吧','meal'],pub:['酒館','meal'],tea:['茶店','cafe'],
  convenience:['便利商店','grocery'],supermarket:['超級市場','grocery'],grocery:['雜貨店','grocery'],
  greengrocer:['蔬果店','grocery'],butcher:['肉品店','grocery'],seafood:['海產店','grocery'],
  confectionery:['糖果甜點店','grocery'],general:['商店','grocery'],mall:['商場','grocery'],
  clothes:['服飾店','apparel'],shoes:['鞋店','apparel'],boutique:['精品店','apparel'],
  cosmetics:['美妝店','apparel'],hairdresser:['髮廊','apparel'],beauty:['美容店','apparel'],
  pharmacy:['藥局','health'],chemist:['藥妝店','health'],optician:['眼鏡店','health'],
  books:['書店','craft'],stationery:['文具店','craft'],gift:['禮品店','craft'],
  department_store:['百貨公司','grocery'],florist:['花店','grocery'],bicycle:['自行車店','craft'],
  hardware:['五金行','craft'],electronics:['電子用品店','craft'],jewelry:['珠寶店','apparel'],
  car:['汽車展售店','retail'],beverages:['飲料店','grocery'],coffee:['咖啡專賣店','grocery'],pastry:['西點店','cafe'],
  deli:['熟食店','grocery'],food:['食品行','grocery'],alcohol:['酒類專賣店','grocery'],wine:['葡萄酒專賣店','grocery'],
  chocolate:['巧克力店','grocery'],nuts:['堅果店','grocery'],pasta:['麵食專賣店','grocery'],health_food:['健康食品店','grocery'],
};

export function storefrontCategory({category,categoryLabel}){
  if(category==='commerce_store'&&categoryLabel==='餐飲店家')return ['餐飲店家','meal'];
  return Object.hasOwn(shopCategories,category)?shopCategories[category]:['店家','retail'];
}
