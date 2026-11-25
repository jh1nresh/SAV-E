// Pocket City artwork from the accepted Songyan scene, registered to Taipei's LOD1 survey.
export const esliteSongyan={
  id:'taipei-eslite-songyan',name:'誠品生活松菸',ground:7.01002,verts:33717,
  center:[121.56129218172221,25.044560320424733],mx:.8376702560603394,my:.4281043630862923,m:2.754280943659238e-8,
  box:[121.56049024559881,25.044261419824103,121.56212315039633,25.044879261932483],
  bearing:-54,pitch:49,zoom:17.46,mobileZoom:17.16,
  mesh:new URL('./assets/taipei-eslite-songyan.bin.gz',import.meta.url),
};

// Base, height and tone uniquely identify these 16 survey parts in the listed tiles.
export const esliteSurveyParts=[
  [7.01002,4.43021,.185],[7.01002,6.43008,.505],[7.01002,12.27015,.235],
  [7.01002,17.13022,.645],[7.01002,21.30025,.015],[7.01002,25.31013,.945],
  [7.01002,29.39025,.945],[7.01002,33.55969,.865],[7.01002,41.89975,.295],
  [7.01002,46.06978,.165],[7.01002,49.97010,.395],[7.01002,54.28005,.805],
  [7.01002,58.77991,.075],[7.01002,69.50983,.335],[7.01026,4.31973,.585],[7.01026,5.61989,.185],
];
export const esliteSurveyTiles=new Set(['200/1532_13854','200/1533_13854','1000/306_2770']);
export const esliteSurveyMatch=`bool isEsliteSurveyPart(vec3 building){
  return ${esliteSurveyParts.map(fields=>
    `all(lessThan(abs(building-vec3(${fields.join(',')})),vec3(.0015)))`).join('||\n    ')};
}`;
