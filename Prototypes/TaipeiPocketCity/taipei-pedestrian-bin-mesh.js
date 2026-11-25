export function drawPedestrianBin({box,prism}){
  const steel='#9aa7a1', lip='#c1c9bf', edge='#65756d', aperture='#303934';
  // Brushed metal body and recessed side opening based on the Taipei cabinet.
  // Polyfork's Street Bin supplies an outdoor scale reference.
  box(0,0,-.012,.51,.56,.068,edge);
  box(0,0,.055,.47,.52,.577,steel);
  box(-.062,0,.632,.346,.52,.215,steel);
  for(const side of [-1,1])box(.173,side*.214,.632,.135,.092,.216,steel);
  box(.107,0,.640,.026,.334,.158,aperture);
  box(.021,0,.815,.435,.521,.072,lip);
  prism([.002,0,0],[.251,.276],[[.874,1],[.968,.77],[.978,.64]],8,steel);
  box(.242,0,.602,.022,.516,.039,lip);
  // A simple faceplate with no address, serial number or printed text.
  box(.240,0,.335,.013,.288,.107,'#51786f');
}
