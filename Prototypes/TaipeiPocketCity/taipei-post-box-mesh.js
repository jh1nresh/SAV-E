const green={enamel:'#43866b',edge:'#2d6554',crown:'#67a483',stand:'#3b7460'};
const red={enamel:'#c65549',edge:'#a53d37',crown:'#de7664',stand:'#ae4a3d'};

export function drawPostBox(kind,slots,{box,prism}){
  const {enamel,edge,crown,stand}=kind==='post-box-express'?red:green;
  // The Taiwanese street box has a low plinth, a single stand and a broad enamel head.
  prism([0,0,0],[.15,.15],[[-.018,1],[.037,1],[.059,.76]],8,edge);
  prism([0,0,0],[.079,.079],[[.035,1],[.578,.91]],8,stand);
  box(0,0,.538,.31,.31,.066,edge);
  box(0,0,.597,.44,.56,.447,enamel);
  prism([0,0,0],[.46/Math.SQRT2,.58/Math.SQRT2],
    [[1.043,1],[1.097,.91],[1.138,.68]],4,crown,Math.PI/4);

  const columns=slots===1?[0]:[-.139,.139];
  const rows=slots===4?[.849,.976]:[.976];
  for(const z of rows){
    for(const y of columns){
      box(.221,y,z,.009,.212,.034,'#483c33');
      box(.227,y,z+.033,.021,.225,.017,edge);
    }
  }
  box(.224,0,.695,.009,.24,.071,'#f1e8ce');
  box(.222,-.21,.706,.008,.027,.027,edge);
}
