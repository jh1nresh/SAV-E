// 24-unit paths share the illustrated map's original disc, outlines, and caption metrics.
const service={disc:'#a6d9e8',ink:'#184953',label:'#276076'};
const leisure={disc:'#c8bcf1',ink:'#473367',label:'#62468a'};
const personal={disc:'#f0b3c8',ink:'#622f43',label:'#88415d'};
const goods={disc:'#96d7bc',ink:'#214d3e',label:'#26634f'};
const dining={disc:'#ffb469',ink:'#542805',label:'#954107'};
const make=(categories,name,colors,lines,solid='')=>({categories,name,...colors,lines,solid});

export const neighborhoodBadges={
  motorcycle:make(['motorcycle'],'機車行',service,
    'M8.1 15.7a2.1 2.1 0 1 1-4.2 0 2.1 2.1 0 1 1 4.2 0 M20 15.7a2.1 2.1 0 1 1-4.2 0 2.1 2.1 0 1 1 4.2 0 M6.5 12h5l1.1 2.4h2.2l1.6-4.1 1.5 5 M16.4 10.3l-.7-2.4h-2.5 M7.5 10.3h3'),
  repair:make(['car_repair','motorcycle_repair','repair'],'維修店',service,'',
    'M18.4 5.5a5.8 5.8 0 0 1-6.6 7.7l-4.7 5a1.8 1.8 0 0 1-2.6-2.5l5-4.8a5.2 5.2 0 0 1 6.4-6.5l-3.1 3.2.8 2.4 2.2.6z'),
  car:make(['car'],'汽車展售店',service,'M5.7 12.2 7.6 7.8h8.8l1.9 4.4 M7.7 15h1.5 M14.8 15h1.5',
    'M5 12h14v5.4h-1.7v1.2h-2v-1.2H8.7v1.2h-2v-1.2H5z M7.4 13.7v1.3h2v-1.3z M14.6 13.7v1.3h2v-1.3z'),
  wheel:make(['tyres','car_parts'],'輪胎與零件',service,'M12 9.1v2.9l2.6 1.5 M12 12l-2.6 1.6',
    'M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 1 1 0-14.8z M12 8a4 4 0 1 0 0 8 4 4 0 1 0 0-8z'),
  massage:make(['massage'],'按摩店',personal,'M5.3 17.4q6.7 3.1 13.6-.3',
    'M6.2 14.2c0-3.3 12-3.6 12-.3s-12 3.4-12 .3z M8.4 9.7c0-2.9 8.6-3.4 8.5-.5-.1 2.7-8.5 3.1-8.5.5z M10 6.2c0-2.4 5.6-2.9 5.5-.5s-5.5 2.5-5.5.5z'),
  beauty:make(['beauty'],'美容店',personal,'M9 14.5 7 18.6 M15.8 5.9l.7-1.4 M17.5 8h1.6',
    'M11.8 6a4.8 4.8 0 1 1 0 9.6 4.8 4.8 0 1 1 0-9.6z M11.8 7.7a3.1 3.1 0 1 0 0 6.2 3.1 3.1 0 1 0 0-6.2z'),
  cosmetic:make(['cosmetics','perfumery'],'美妝用品',personal,'M8.3 14h7.5v4.5H8.3z',
    'M10 13V7.8l4.4-3.5V13z'),
  copy:make(['copyshop'],'影印店',service,'M8 8V5.3h8V8 M8.2 14.5v4h7.6v-4 M8.7 16h6.6',
    'M5 9h14v6.3h-2v-2.1H7v2.1H5z M15.8 10.2v1.3h1.4v-1.3z'),
  dryclean:make(['dry_cleaning'],'乾洗店',service,'M10.1 8.3a2 2 0 1 1 3.7 1l-1.8 1.6v.7l7 4.3q1 .8-.5 1H5.5q-1.6-.2-.5-1l7-4.3'),
  ticket:make(['lottery','ticket'],'票券店',leisure,'M13.8 7.9v1 M13.8 11.8v1 M13.8 15.6v1',
    'M5 7h14v3.2a1.8 1.8 0 0 0 0 3.6V17H5v-3.2a1.8 1.8 0 0 0 0-3.6z M6.7 8.5v7h10.6v-7z'),
  pets:make(['pet','pet_grooming'],'寵物用品與照護',goods,'',
    'M8 15.3c.6-1.1 2-3.6 4-3.6s3.3 2.5 4 3.6c.7 1.8-.7 3.2-2.5 2.8l-1.5-.4-1.5.4c-1.7.4-3.1-1-2.5-2.8z M7.8 9.1a1.7 2.3-18 1 1-3.2 1 1.7 2.3-18 1 1 3.2-1z M11.5 7.4a1.6 2.2 0 1 1-3.2 0 1.6 2.2 0 1 1 3.2 0z M15.7 7.4a1.6 2.2 0 1 1-3.2 0 1.6 2.2 0 1 1 3.2 0z M19.2 10.1a1.7 2.3 18 1 1-3.2-1 1.7 2.3 18 1 1 3.2 1z'),
  sports:make(['sports'],'體育用品',leisure,'M18.6 12a6.6 6.6 0 1 1-13.2 0 6.6 6.6 0 1 1 13.2 0 M6 10q6.4 1.3 8 8 M9.6 5.9q1.8 5.5 8.4 7.4 M7.2 16.5l9.4-9.4'),
  outdoor:make(['outdoor'],'戶外用品',goods,'M4.7 17.7l7.1-11.5 7.5 11.5z M9.8 17.6l2.1-4.2 2.1 4.2'),
  play:make(['video_games','games'],'遊戲店',leisure,'M7.1 12.1h3.9 M9 10.2v3.9 M14.9 11.4h.2 M16.7 13.2h.2 M5 16.3l1.4-6.5q.6-1.8 2.2-1.8h6.8q1.8 0 2.2 1.8l1.4 6.5q.3 2.5-1.8 1.3L14.4 15H9.6l-2.8 2.6q-2.1 1.2-1.8-1.3z'),
  toys:make(['toys'],'玩具店',leisure,'M6.5 10.3 12 7l5.5 3.3v6.1L12 19.2l-5.5-2.8z M6.5 10.3l5.5 3 5.5-3 M12 13.3v5.9'),
  music:make(['music','musical_instrument'],'音樂店',leisure,'M10.2 15.5V7.2l7.2-1.6v8.6 M10.2 9.3l7.2-1.6',
    'M10.5 15.8c0 3.3-5.8 4.4-5.8 1.4 0-2.6 4.2-3.8 5.8-2.5z M17.7 14.3c0 3.3-5.7 4.3-5.7 1.3 0-2.5 4.1-3.8 5.7-2.5z'),
  art:make(['art'],'美術店',leisure,'M12.5 15.7q-1.2 2.6-4.9 2.3 1.3-1.3 1.2-2.8.2-2.3 2.4-2.4',
    'M10.8 12.9 17.1 5l1.8 1.5-6.3 8z'),
  camera:make(['photo','photograph','camera'],'攝影店',leisure,'M14.7 12.7a2.7 2.7 0 1 1-5.4 0 2.7 2.7 0 1 1 5.4 0 M5.2 8.4h3.5L10 6.3h4l1.4 2.1h3.4v9.1H5.2z'),
  stationery:make(['stationery','books;stationery'],'文具店',goods,'M6.1 17.9l1.1-4.3 7.7-7.7 3.2 3.2-7.7 7.7z M13.6 7.2l3.2 3.2'),
  telecom:make(['telecommunication'],'通訊服務',service,'M5.2 9.9a9.6 9.6 0 0 1 13.6 0 M8.1 12.6a5.6 5.6 0 0 1 7.8 0 M10.5 15.2a2.2 2.2 0 0 1 3 0',
    'M13 17.6a1 1 0 1 1-2 0 1 1 0 1 1 2 0'),
  bikeShop:make(['bicycle'],'自行車店',service,'M8.5 15.4a2.5 2.5 0 1 1-5 0 2.5 2.5 0 1 1 5 0 M20.4 15.4a2.5 2.5 0 1 1-5 0 2.5 2.5 0 1 1 5 0 M6 15.4l3.2-5.7 3 5.1 2.9-5.1H9.2 M14 6.9h2l2 8.5'),
  kitchen:make(['kitchen','houseware'],'廚房與家居用品',goods,'M6 11h12v3q0 3.3-3.2 3.3H9.2Q6 17.3 6 14z M4.5 11.5h1.3 M18.2 11.5h1.3 M7.3 9.1h9.4 M11 7.2h2'),
  bed:make(['bed'],'寢具店',goods,'M5.2 7.7v9.8 M18.8 11.6v5.9 M5.2 15.2h13.6 M7.9 12v-2h3v2 M12.6 9.9h3.9q2 0 2 2.2H5.6'),
  locksmith:make(['locksmith'],'鎖店',service,'M10.4 9.7a2.8 2.8 0 1 1-5.6 0 2.8 2.8 0 1 1 5.6 0 M9.9 11.8l7.4 6.2 1.4-1.7-1.6-1.3 1.1-1.3'),
  tea:make(['tea'],'茶店',dining,'M6 15.5q5.6.5 9-7 M6.5 15c-2-6.8 4-8.1 10.7-9-1.1 6.5-2.2 12.6-10.7 9z'),
  beans:make(['coffee'],'咖啡專賣店',dining,'M8.4 16.6q5.9-1.5 4.9-5.2-.6-2.7 2.5-4.9 M17 6.3c3 2.8 1.4 8.1-2 10.7-3.2 2.4-6.8 2.4-8.5.4-2.4-3 .1-8.2 3.5-10.3 2.7-1.8 5.2-2.1 7-.8z'),
  deli:make(['deli'],'熟食店',dining,'M5 16h14 M7 14.2q.2-5.4 5-5.4t5 5.4z M12 7.5v1.1'),
  candy:make(['confectionery','chocolate'],'糖果甜點店',dining,'M8.6 10.3 5.3 9.1l.2 4.1 3-1.1 M15.4 12l3.3-1.2-.2 4.1-3-1.1',
    'M14.4 8.5q3 2.4.3 5.9t-5.3 1.1q-2.8-2.4-.3-5.9t5.3-1.1z'),
  wine:make(['alcohol','wine'],'酒類專賣店',dining,'M10.3 5.3h3.4v4.2l1.9 2.5v6.7H8.4V12l1.9-2.5z M9 13.5h6'),
  vase:make(['antiques'],'古董店',goods,'M9.2 6.2h5.6 M9.7 6.5l.8 3-2.1 2.4q-2.3 3.2 1 5.5h5.2q3.3-2.3 1-5.5l-2.1-2.4.8-3'),
  clock:make(['watches'],'鐘錶店',personal,'M16.5 12a4.5 4.5 0 1 1-9 0 4.5 4.5 0 1 1 9 0 M12 10v2.2l1.8 1 M10 6.9V4.7h4v2.2 M10 17.1v2.2h4v-2.2'),
  luggage:make(['travel_agency'],'旅行社',service,'M6 8.3h12v9.1H6z M9.6 8.1V5.9h4.8v2.2 M9 9.3v7 M15 9.3v7'),
  fabric:make(['fabric','curtain','tailor','sewing'],'布料與縫紉',personal,'M7.7 6.2h8.6 M7.7 17.8h8.6 M9.1 6.6v10.8 M14.9 6.6v10.8 M9.6 10l4.8-1.6 M9.6 13.5l4.8-1.6 M15.8 17.9l2 .8'),
  lamp:make(['interior_decoration','lighting'],'室內裝飾',goods,'M9.1 6.3h5.8l2.6 6.2H6.5z M12 12.5v4.6 M8.9 17.9h6.2'),
  butcher:make(['butcher'],'肉品店',dining,'M6 16.8l4.2-4.4','M8.1 10.1 13.7 5l4.8 5.3-6 5.1z M13.5 7.2l-.8.7.8.8.8-.7z'),
  appliance:make(['appliance','electrical'],'家電用品',service,'M9 8V5 M15 8V5 M7.3 8.7h9.4v2a4.7 4.7 0 0 1-9.4 0z M12 15.5v1.1q0 2.3 2.6 2.3'),
  hearing:make(['hearing_aids'],'助聽器行',service,'M7.7 10a4.9 4.9 0 0 1 9.7.6q-.1 2.4-2.2 4l-1.4.9-.6 1.4q-.5 1.7-2.5 1.7-1.7 0-2.2-1.4 M10 10.2a2.5 2.5 0 0 1 5 .3q0 1.6-1.9 2.6'),
  bag:make(['bag'],'包袋店',personal,'M9 9.2V8.1a3 3 0 0 1 6 0v1.1 M6.7 10h10.6l1.1 7.8H5.6z M7.5 12.6l4.5 1.7 4.5-1.7'),
};

export const preciseShopLabels=new Map(Object.entries({
  lottery:'彩券行',ticket:'票券店',pet:'寵物用品店',pet_grooming:'寵物美容',
  music:'音樂店',musical_instrument:'樂器行',tailor:'裁縫店',curtain:'窗簾店',
  fabric:'布料店',sewing:'縫紉用品店',kitchen:'廚房用品店',houseware:'家居用品店',
  alcohol:'酒類專賣店',wine:'葡萄酒專賣店',perfumery:'香水店',
  yes:'商店',religion:'宗教用品店',trade:'專業用品店',second_hand:'二手商店',medical_supply:'醫療用品店',
}));

// Cuisine cues never replace a previously authored trade badge. A neutral dinner service retains cutlery.
export const foodBadges={
  takeaway:make([],'速食',dining,'M7.2 9h9.6l.7 9.1h-11z M9.8 9V7.4a2.2 2.2 0 0 1 4.4 0V9'),
  boba:make([],'手搖茶',dining,'M7.3 9.4h9.4l-1.2 8.8h-7z M7 9.3h10 M12.7 9.2l1.2-4h2.2 M10.5 15.1h.1 M13.3 16h.1'),
  hotpot:make([],'火鍋',dining,'M5.3 11h13.4l-1.1 4.8q-.6 1.5-2 1.5H8.4q-1.4 0-2-1.5z M4.5 12h1.2 M18.2 12h1.2 M10 8.8q-1.1-1.3.3-3 M13.6 8.8q-1.1-1.3.3-3'),
  noodles:make([],'麵食',dining,'M5 12h14q-1.4 6.1-7 6.1T5 12z M10.5 12l6.3-6.4 M13.2 12l5.2-4.6'),
  dumpling:make([],'餃子',dining,'M5.1 15.9q.8-7.4 7-7.9 5.7.1 6.8 7.9-6.7 3.6-13.8 0z M8.6 10.2l2.2 2 M12.6 8.7l.8 2.6 M15.8 10l-.5 2.1'),
  burger:make([],'漢堡',dining,'M6.2 10.1q.9-5 5.8-5.1 5 .1 5.8 5.1z M5.7 12.6l2.9.9 2.8-1.1 3 .9 3.8-.8 M6.3 16h11.4q-.4 2.4-2.3 2.4H8.6q-2 0-2.3-2.4'),
  pizza:make([],'披薩',dining,'M6.9 6.7q6-2 11.1 2.5l-9.7 9.2z M7.1 8.6q4.8-1.3 9.1 1.8 M10.9 11.9h.1 M12.6 13.3h.1'),
  sushi:make([],'壽司',dining,'M5.8 10.1q1.4-3.4 6.2-3.4t6.2 3.4q-1.4 3.3-6.2 3.3t-6.2-3.3z M6.2 11.1v3.1q1.1 3 5.8 3t5.8-3v-3.1 M10.9 10.1h2.2'),
  breakfast:make([],'早餐',dining,'M5.3 15.5h13.4 M8.5 13.8a3.5 3.5 0 0 1 7 0 M12 6.3v2 M5.7 9.2l1.4 1.2 M18.3 9.2l-1.4 1.2'),
  sandwich:make([],'三明治',dining,'M5.3 15.4 17.2 7l1.4 8.4z M5.7 17.6h12.8'),
  seafood:make([],'海鮮',dining,'M5 11.7q4.7-6.5 10.8-.9l3.4-2.2v6.8l-3.4-2.1q-5.8 5.3-10.8-1.6z M8.6 11.3h.1'),
};

const foodTags=[
  ['boba',['bubble_tea']],['hotpot',['hotpot','hot_pot']],
  ['noodles',['noodle','noodles','beef_noodle','beef_noodles','ramen','udon']],
  ['dumpling',['dumpling','dumplings','gyoza']],['sushi',['sushi']],
  ['burger',['burger','burgers']],['pizza',['pizza']],['sandwich',['sandwich']],
  ['breakfast',['breakfast','brunch']],['seafood',['seafood']],
];

export function foodPinExpression(value,fallback){
  // At the map zoom gate the publisher's semicolon-separated OSM cuisine can select a dish.
  // Matching tokens protects noodle shops from unrelated strings containing "noodle".
  const choices=[];
  for(const [type,words] of foodTags){
    const tests=words.map(word=>['in',word,['var','cuisineTokens']]);
    choices.push(tests.length===1?tests[0]:['any',...tests],value(type));
  }
  return ['let','cuisineTokens',['split',['downcase',['to-string',['get','cuisine']]],';'],
    ['case',...choices,['==',['get','category'],'fast_food'],value('takeaway'),fallback]];
}
