export const neighborhoodServiceLabels=new Map(Object.entries({
  interior_decoration:'室內裝飾', pawnbroker:'當舖', medical_supply:'醫療用品',
  travel_agency:'旅行社', funeral_directors:'禮儀服務', baby_goods:'嬰童用品',
  tattoo:'刺青工作室', repair:'維修服務', second_hand:'二手商品',
  pet_grooming:'寵物美容', party:'派對用品', wigs:'假髮店', houseware:'家居用品',
  bathroom_furnishing:'衛浴用品', fishing:'釣具行', fashion_accessories:'服飾配件',
  hearing_aids:'助聽器門市', photograph:'照相館', appliance:'家電行', outpost:'包裹取貨點',
}));

export const serviceWindowLabels=new Map([
  ...Object.entries({
    shoes:'鞋店', beauty:'美容店', cosmetics:'美妝店', massage:'按摩店', jewelry:'珠寶店',
    motorcycle:'機車行', motorcycle_repair:'機車維修', car:'汽車展售店', car_repair:'汽車維修',
    car_parts:'汽車零件店', tyres:'輪胎行', hardware:'五金行', doityourself:'工具建材行',
    laundry:'洗衣店', dry_cleaning:'乾洗店', furniture:'家具店',
    computer:'電腦行', electronics:'電子用品店', mobile_phone:'手機行',
  }),
  ...neighborhoodServiceLabels,
]);
