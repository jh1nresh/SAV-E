import marketScenes from './taipei-market-stalls-data.js';

const marketIds=new Set(['tcma-market-11','tcma-market-35']);
export function withMarketScenery(feature){
  if(!marketIds.has(feature.id))return feature;
  return {...feature,properties:{...feature.properties,detail:feature.properties.detail+' · 攤位為街景示意'}};
}
export function marketStallLife(records,packs){
  const scenes=packs.flatMap(key=>marketScenes[key]?[marketScenes[key]]:[]);
  if(!scenes.length)return records;
  const replaced=new Set(scenes.flatMap(scene=>scene.replacePaths??[]));
  const retained=replaced.size?records.map(row=>({...row,
    paths:Object.fromEntries(Object.entries(row.paths).filter(([key])=>!replaced.has(key))),
  })):records;
  return [...retained,...scenes];
}

const canopies=['#ca624e','#449486','#d19749','#537e99','#a66d82','#71895b'];
const canvas='#f7e1af',steel='#6e7772',wood='#9c6c4d',enamel='#b7cbc0',sauce='#b34e3e';

// Illustrative local carts. Polyfork's Market Stall (1.96 × 2.02 × 1.13 m)
// and Sopaipilla Cart (1.6 × 2.07 × 1.6 m) inform the scale, not the style or vendor.
export function drawMarketStall(kind,index,{box,prism,face}){
  const fabric=canopies[index%canopies.length];
  const counter=kind==='market-counter';
  if(kind==='market-canopy'){
    for(const u of [-.93,.93])for(const v of [-.59,.59])box(u,v,0,.08,.08,2.04,steel);
    for(let i=0;i<8;i++){
      const a=-1.08+i*.27,b=a+.27;
      const color=i%2?canvas:fabric;
      face([[a,-.76,2.02],[b,-.76,2.02],[b,0,2.26],[a,0,2.26]],color,.92);
      face([[a,0,2.26],[b,0,2.26],[b,.76,2.02],[a,.76,2.02]],color,1.06);
      box((a+b)/2,.74,1.91,.27,.04,.11,color);
    }
    box(0,-.34,0,1.84,.65,.78,wood);
    box(0,.15,.14,1.91,.67,.64,fabric);
    box(0,.15,.78,1.98,.73,.09,canvas);
    for(const [u,color] of [[-.58,'#6b935d'],[0,'#da9053'],[.55,'#b98c50']]){
      box(u,.14,.87,.40,.41,.10,wood);
      for(const x of [-.10,.08])for(const y of [.05,.23])
        prism([u+x,y,.98],[.088,.081],[[0,.85],[.12,.59]],6,color);
    }
    return;
  }
  for(const u of [-.72,.72])for(const v of [-.38,.38]){
    box(u,v,0,.2,.12,.16,steel);
    box(u,v,.11,.095,.095,.16,steel);
  }
  box(0,0,.22,1.72,.94,.60,counter?wood:fabric);
  box(0,0,.82,1.81,1.04,.10,enamel);
  box(0,.51,.53,1.52,.028,.17,fabric);
  if(counter){
    // A lit display case on a compact service counter.
    box(0,-.13,.91,1.52,.66,.46,'#8caaa4');
    box(0,-.13,1.37,1.59,.69,.065,canvas);
    for(const u of [-.39,.10,.51])box(u,.21,1.04,.23,.026,.19,'#e0c498');
    return;
  }
  box(-.28,-.08,.92,1.02,.71,.065,steel);
  for(const v of [-.29,-.11,.07,.25])box(-.28,v,.985,.91,.032,.034,'#3f4d49');
  box(.56,.12,.92,.36,.35,.13,wood);
  for(const u of [.45,.57,.67])prism([u,.12,1.05],[.045,.045],[[0,.86],[.17,1],[.21,.46]],6,sauce);
  for(const u of [-.8,.80])box(u,-.4,.90,.062,.062,1.03,steel);
  box(0,-.39,1.87,1.69,.12,.16,canvas);
  for(const u of [-.51,-.19,.25,.54])box(u,-.325,1.92,.13,.028,.06,fabric);
}
