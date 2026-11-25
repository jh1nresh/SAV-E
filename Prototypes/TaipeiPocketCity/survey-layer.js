import {buildTaipei101Tower} from './taipei101-tower.js';
import {taipeiDome,buildTaipeiDome,isDomeSurveyTile} from './taipei-dome.js';
import {buildPalaceModel} from './palace-museum.js';
import {esliteSongyan,esliteSurveyTiles,esliteSurveyMatch} from './taipei-eslite-songyan.js';
import {sunYatSenHall,buildSunYatSenHall,isMemorialSurveyTile} from './sun-yat-sen-hall.js';

const landmarkBuilders=new Map([['palace-museum',buildPalaceModel],[sunYatSenHall.id,buildSunYatSenHall],[taipeiDome.id,buildTaipeiDome]]);

const vertexSource=`#version 300 es
layout(location=0) in vec3 a_position;
layout(location=1) in vec3 a_building;
layout(location=2) in vec2 a_wallDirection;
uniform mat4 u_transform;
out vec3 v_position;
flat out vec3 v_building;
flat out vec2 v_wallDirection;
void main() {
  v_position=a_position;
  v_building=a_building;
  v_wallDirection=a_building.z>=2.0?vec2(0.0):a_wallDirection;
  gl_Position=u_transform*vec4(a_position,1.0);
}
`;
const fragmentSource=`#version 300 es
precision highp float;
in vec3 v_position;
flat in vec3 v_building;
flat in vec2 v_wallDirection;
uniform float u_zoom;
uniform vec2 u_focusOffset;
uniform int u_mallCorners;
uniform vec3 u_mallTile;
uniform vec4 u_mallBounds;
uniform vec2 u_mallRing[48];
uniform vec4 u_streetOffsets;
uniform vec2 u_linkOffset;
uniform vec4 u_linkRuns[6];
uniform sampler2D u_districtMaterialMask;
uniform bool u_districtMaterialDetail;
uniform vec4 u_districtMaterialTransform;
uniform vec3 u_cityLandmarks;
uniform bool u_replaceMemorialShell;
uniform bool u_replaceDomeShell;
uniform bool u_replaceEsliteShell;
uniform vec3 u_songyanOffset;
uniform vec3 u_dihuaOffset;
uniform vec4 u_songyanLimit;
uniform vec3 u_songyanMatches[4];
uniform bool u_songyanTile;
uniform bool u_anatomy;
uniform bool u_hybrid;
out vec4 outColor;

vec3 wall(float tint, float height) {
  vec3 stone=vec3(.845,.788,.683);
  if(tint<.18) stone=vec3(.911,.838,.712);
  else if(tint<.36) stone=vec3(.800,.753,.683);
  else if(tint<.52) stone=vec3(.804,.676,.568);
  else if(tint<.67) stone=vec3(.717,.761,.708);
  else if(tint<.79) stone=vec3(.835,.774,.757);
  if(height>385.0) return vec3(.428,.659,.593);
  return mix(stone,vec3(.620,.720,.762),smoothstep(27.0,72.0,height)*.88);
}

float strip(float meshCoord,float interval,float width) {
  float f=abs(fract(meshCoord/interval)-.5);
  float a=max(fwidth(meshCoord)/interval,.012);
  return 1.0-smoothstep(width-a,width+a,f);
}

float facadeCoordinate(vec2 position,vec3 normal) {
  // Survey triangles carry a constant tangent. Differentiating a tangent reconstructed
  // with dFdx/dFdy inside strip's fwidth produces undefined second derivatives.
  if(dot(v_wallDirection,v_wallDirection)>.5)return dot(position,v_wallDirection);
  return dot(position,normalize(vec2(normal.y,-normal.x))); // Legacy authored mesh.
}

// Local illustrations use a few steady material families with separate roof colors.
vec3 hybridMaterial(float tone, float height, bool roof) {
  vec3 low=vec3(.951,.866,.729);
  if(tone>.25)low=vec3(.891,.720,.558);
  if(tone>.43)low=vec3(.780,.527,.428);
  if(tone>.56)low=vec3(.864,.825,.742);
  if(tone>.73)low=vec3(.709,.798,.657);
  if(tone>.88)low=vec3(.647,.758,.801);
  vec3 high=tone<.35?vec3(.504,.690,.758)
    :tone<.61?vec3(.654,.755,.784)
    :tone<.85?vec3(.616,.739,.680):vec3(.823,.792,.700);
  vec3 wallColor=mix(low,high,smoothstep(16.0,52.0,height));
  if(!roof)return wallColor;
  vec3 cap=tone<.13?vec3(.520,.546,.608)
    :tone<.37?vec3(.801,.696,.589)
    :tone<.57?vec3(.773,.503,.403)
    :tone<.83?vec3(.735,.732,.658):vec3(.602,.692,.727);
  return mix(cap,high*.93,smoothstep(20.0,58.0,height)*.8);
}

// The four material steps apply to solid faces; recessed glass and trim use their own inks.
vec3 anatomyTone(vec3 material, vec3 normal) {
  if(u_hybrid){
    float sun=dot(normal,normalize(vec3(-.56,.48,.68)));
    if(normal.z>.66)return mix(material,vec3(1.0,.950,.835),.15);
    if(sun>.43)return mix(material,vec3(.986,.922,.776),.07);
    if(sun>.01)return mix(material,vec3(.356,.442,.590),.12);
    return mix(material,vec3(.278,.350,.524),.29);
  }
  float facing=dot(normal,normalize(vec3(-.54,-.64,.59)));
  if(normal.z>.66) return mix(material,vec3(.986,.949,.838),.17);
  if(facing>.43) return material;
  if(facing>-.16) return mix(material,vec3(.37,.39,.42),.12);
  return mix(material,vec3(.29,.33,.37),.26);
}

vec3 anatomyFinish(vec3 material, vec3 normal, vec2 site, float level, float height, float tone, bool authored, bool retail) {
  vec3 finish=anatomyTone(material,normal);
  if(authored || normal.z>.66 || height<5.1) return finish;
  float x=facadeCoordinate(site,normal);
  float rhythm=height>45.0?2.23:2.85;
  float detail=smoothstep(16.6,18.65,u_zoom);
  float windowArea=smoothstep(3.75,5.5,level)*(1.0-smoothstep(height-.8,height-.15,level));
  float recess=strip(x+tone*2.85,rhythm,.27)*strip(level-1.10,3.2,.235);
  float pane=strip(x+tone*2.85,rhythm,.205)*strip(level-1.01,3.2,.16);
  vec3 glass=mix(vec3(.31,.38,.40),vec3(.46,.56,.55),clamp(dot(normal,vec3(-.40,-.52,.1))+.2,0.0,1.0));
  if(u_hybrid)glass=mix(vec3(.286,.395,.497),vec3(.482,.644,.691),
    clamp(dot(normal,vec3(-.45,.38,.07))+.37,0.0,1.0));
  finish=mix(finish,mix(glass*.72,glass,pane),recess*windowArea*(.35+.44*detail));
  float sill=strip(x+tone*2.85,rhythm,.27)*strip(level-.15,3.2,.034);
  finish=mix(finish,vec3(.93,.88,.76),sill*windowArea*.51*detail);

  float rim=smoothstep(height-1.12,height-.84,level)*(1.0-smoothstep(height-.67,height-.33,level));
  finish=mix(finish,mix(finish,vec3(.96,.91,.80),.63),rim*.64*detail);
  if(retail && height>12.0 && level>0.1 && level<5.75){
    float frontage=smoothstep(.1,.45,level)*(1.0-smoothstep(5.27,5.75,level));
    float window=strip(x+1.0,2.8,.36)*smoothstep(.45,.72,level)*(1.0-smoothstep(3.59,3.83,level));
    vec3 storefrontColor=vec3(.787,.504,.270);
    if(u_hybrid){
      float bay=fract(floor((x+tone*4.0)/6.4)*.37+tone);
      storefrontColor=bay<.27?vec3(.820,.368,.285):bay<.51?vec3(.243,.504,.459)
        :bay<.75?vec3(.827,.592,.249):vec3(.454,.478,.678);
    }
    vec3 wood=anatomyTone(u_hybrid?mix(storefrontColor,vec3(.345,.284,.223),.39):vec3(.574,.451,.340),normal);
    vec3 amber=vec3(.934,.651,.338);
    float displays=strip(x+.34,.85,.25)*smoothstep(.55,1.18,level)*(1.0-smoothstep(2.18,2.86,level));
    vec3 interior=mix(vec3(.202,.261,.264),amber,displays*.79);
    finish=mix(finish,mix(wood,interior,window),frontage*.98);
    float header=smoothstep(3.86,4.04,level)*(1.0-smoothstep(4.52,4.80,level));
    finish=mix(finish,anatomyTone(storefrontColor,normal),header*.89);
    float ledge=smoothstep(4.82,5.01,level)*(1.0-smoothstep(5.18,5.34,level));
    finish=mix(finish,vec3(.930,.848,.685),ledge*.75);
  }
  return finish*mix(.88,1.0,smoothstep(0.0,2.6,level));
}

vec3 heritageFinish(float code,vec3 normal,float level,float height){
  bool memorial=code<.46;
  bool hotel=code>=.46&&code<.75;
  float eave=memorial?43.0:hotel?41.5:14.8;
  vec3 plaster=hotel?vec3(.675,.302,.238):vec3(.915,.867,.734);
  vec3 tile=memorial?vec3(.239,.376,.560):hotel?vec3(.827,.543,.258):vec3(.286,.572,.444);
  float roof=step(eave,level)*smoothstep(.08,.45,normal.z);
  float plinth=1.0-smoothstep(hotel?5.5:11.0,hotel?8.0:14.0,level);
  vec3 material=mix(plaster,vec3(.790,.750,.650),plinth);
  float seam=strip(v_position.x+v_position.y,hotel?1.4:1.08,.047);
  material=mix(material,mix(tile,tile*vec3(.79,.85,.90),seam*.48),roof);
  float ridge=roof*smoothstep(height-1.4,height-.45,level);
  material=mix(material,memorial?tile*1.15:vec3(.914,.729,.390),ridge*.62);
  if(hotel&&level>9.0&&level<40.0&&normal.z<.25){
    float panel=strip(v_position.x+v_position.y,4.8,.23)*strip(level-1.6,3.25,.23);
    material=mix(material,vec3(.293,.276,.275),panel*.66);
  }
  return anatomyTone(material,normal);
}

${esliteSurveyMatch}

void main() {
  if(u_replaceEsliteShell&&isEsliteSurveyPart(v_building))discard;
  vec3 n=normalize(cross(dFdx(v_position),dFdy(v_position)));
  if(n.z<-.5)n=-n;
  float base=v_building.x, height=v_building.y, tone=v_building.z;
  // Exact signatures of the surveyed stadium body and its narrow surrounding apron.
  if(u_replaceDomeShell&&abs(base-7.52979)<.002&&
      ((abs(height-60.41006)<.002&&abs(tone-.315)<.0001)||
       (abs(height-55.75004)<.002&&abs(tone-.345)<.0001)))discard;
  if(u_replaceMemorialShell && abs(base-8.23)<.006 && abs(height-9.77)<.006 && abs(tone-.495)<.0002)discard;
  float level=v_position.z-base;
  vec2 site=v_position.xy+u_focusOffset;
  vec2 mallSite=v_position.xy*u_mallTile.z+u_mallTile.xy;
  if(u_mallCorners>0&&all(greaterThanEqual(mallSite,u_mallBounds.xy))&&all(lessThanEqual(mallSite,u_mallBounds.zw))){
    bool inMall=false;
    vec2 a=u_mallRing[u_mallCorners-1];
    for(int i=0;i<u_mallCorners;i++){
      vec2 b=u_mallRing[i];
      if((a.y>mallSite.y)!=(b.y>mallSite.y)&&mallSite.x<(b.x-a.x)*(mallSite.y-a.y)/(b.y-a.y)+a.x)inMall=!inMall;
      a=b;
    }
    if(inMall)discard;
  }
  // Taipei 101's four survey strips are separate 129.06 m features within 32 m of its center.
  // The tower mesh already draws its own trim. Hide both the survey core and these strips.
  bool towerTrim=tone<1.0&&abs(height-129.06038)<.02&&abs(base-4.94)<.02&&dot(site,site)<1024.0;
  if(tone<0.0||towerTrim)discard;
  bool authored=tone>=2.0;
  float packedColor=max(0.0,tone-2.0);
  vec3 original=vec3(floor(packedColor/65536.0),mod(floor(packedColor/256.0),256.0),mod(packedColor,256.0))/255.0;
  if(u_songyanTile){
    vec3 ink=anatomyTone(original,n);
    if(height>4.2&&n.z>.66&&abs(level-height)<.14){
      float joint=strip(v_position.y+.022*v_position.x,3.6,.022);
      ink*=1.0-.13*joint;
    }
    outColor=vec4(ink,1.0);
    return;
  }
  if(u_dihuaOffset.z>.5 && !authored){
    vec2 q=v_position.xy+u_dihuaOffset.xy;
    float inward=q.x+1.454+.10296*q.y;
    // Remove only the survey face in front of the new recessed passage.
    bool eastShell=abs(base-3.14007)<.015 &&
      (abs(height-8.61983)<.012 || abs(height-7.10005)<.012 || abs(height-6.97)<.012);
    if(eastShell && q.y> -9.553 && q.y<27.974 && inward>-.12 && inward<1.57 && v_position.z<10.46)discard;
    float westDepth=-(q.x+9.469+.0997*q.y);
    bool westShell=abs(base-2.95)<.015 && abs(height-7.66)<.015;
    if(westShell && q.y> -4.924 && q.y<.227 && westDepth>-.12 && westDepth<1.62 && v_position.z<10.13)discard;
  }
  vec2 songyan=v_position.xy+u_songyanOffset.xy;
  if(u_songyanOffset.z>.5&&!authored&&all(greaterThanEqual(songyan,u_songyanLimit.xy))&&
     all(lessThanEqual(songyan,u_songyanLimit.zw))){
    for(int i=0;i<4;i++){
      if(all(lessThan(abs(v_building-u_songyanMatches[i]),vec3(.0015))))discard;
    }
  }
  vec3 surface=authored?original:wall(tone,height);
  float neighborhood=smoothstep(16.5,17.55,u_zoom)
    *(1.0-smoothstep(140.0,207.0,length((site-vec2(63.0,60.0))*vec2(.96,.85))));
  bool mall=site.x>-103.0&&site.x<56.0&&site.y>-53.0&&site.y<104.0;
  bool east=site.x>82.0;
  vec3 clay=vec3(.841,.554,.439);
  vec3 cream=vec3(.938,.827,.664);
  vec3 jade=vec3(.449,.700,.665);
  if(!authored){
    vec3 material=height>44.0?(east?jade:vec3(.533,.698,.720))
      :mix(cream,clay,smoothstep(.18,.78,tone));
    surface=mix(surface,material,neighborhood*.88);
  }
  bool roof=abs(n.z)>.66;
  float light=max(dot(n,normalize(vec3(-.38,.58,.73))),0.0);
  if(roof){
    vec3 cap=vec3(.794,.742,.652);
    if(tone<.16)cap=vec3(.699,.518,.426);
    else if(tone<.35)cap=vec3(.749,.701,.651);
    else if(tone<.61)cap=vec3(.720,.754,.733);
    if(!authored)surface=mix(cap,surface*.86,smoothstep(18.0,54.0,height)*.70);
    if(!authored){
      vec3 terrace=mix(vec3(.853,.695,.521),vec3(.656,.748,.547),smoothstep(.23,.62,tone));
      surface=mix(surface,terrace,neighborhood*(height<78.0?.66:.25));
      if(height>385.0)surface=vec3(.640,.785,.689);
    }
    surface*=.92+.10*light;
  }else{
    surface=mix(surface*vec3(.77,.81,.87),surface,light*.64+.24);
    float detail=smoothstep(16.6,18.45,u_zoom);
    vec3 paperShadow=vec3(.337,.375,.504);
    float shade=light>.40?0.04:light>.14?.14:.25;
    surface=mix(surface,paperShadow,neighborhood*shade*.78);
    if(!authored&&height>5.1 && level>1.35 && level<height-.75){
      float u=facadeCoordinate(v_position.xy,n);
      float rhythm=height>45.0?2.23:2.85;
      float windows=strip(u+tone*2.85,rhythm,.253)*strip(level-1.1,3.2,.203);
      vec3 glass=mix(surface*vec3(.62,.72,.77),vec3(.428,.610,.639),height>38.0?.48:.25);
      surface=mix(surface,glass,windows*detail*.77);
      if(height>385.0){
        float belt=strip(level,42.0,.026)*smoothstep(16.0,17.0,u_zoom);
        surface=mix(surface,vec3(.698,.808,.708),belt*.60);
      }
    }
    if(!authored&&(mall||east)&&height>12.0&&level>0.1&&level<8.0){
      float u=facadeCoordinate(site,n);
      float bay=floor((u+1.0)/8.4);
      float selection=mod(bay,4.0);
      vec3 frame=selection<1.0?vec3(.785,.364,.265):selection<2.0?vec3(.228,.524,.481)
        :selection<3.0?vec3(.638,.436,.388):vec3(.813,.602,.302);
      float pane=strip(u+1.0,2.8,.35)*smoothstep(.22,.57,level)*(1.0-smoothstep(3.56,3.83,level));
      float shopfront=1.0-smoothstep(4.85,5.16,level);
      vec3 display=mix(vec3(.175,.284,.322),vec3(.995,.814,.457),
        strip(u+.34,.85,.32)*smoothstep(.3,1.0,level)*(1.0-smoothstep(1.95,3.0,level))*.91);
      surface=mix(surface,mix(frame,display,pane)*(.90+light*.12),neighborhood*shopfront*.93);
      float ledge=smoothstep(4.75,4.95,level)*(1.0-smoothstep(5.15,5.4,level));
      surface=mix(surface,cream,neighborhood*ledge);
      float trim=smoothstep(4.50,4.67,level)*(1.0-smoothstep(4.75,4.84,level));
      surface=mix(surface,vec3(.26,.30,.30),neighborhood*trim*.60);
    }
    surface*=mix(.83,1.0,smoothstep(-1.0,min(5.5,height*.40),level));
  }
  vec2 linkSite=v_position.xy+u_linkOffset;
  float linkCoverage=0.0;
  for(int i=0;i<6;i++){
    vec4 run=u_linkRuns[i];
    vec2 edges=max(run.xy-linkSite,linkSite-run.zw);
    linkCoverage=max(linkCoverage,1.0-smoothstep(0.0,15.0,max(edges.x,edges.y)));
  }
  float link=linkCoverage*smoothstep(16.55,17.6,u_zoom)*(1.0-neighborhood);
  if(link>0.0){
    vec3 sandstone=mix(vec3(.904,.788,.634),vec3(.743,.550,.470),smoothstep(.10,.90,tone));
    vec3 modern=mix(vec3(.738,.777,.702),vec3(.515,.657,.672),smoothstep(27.0,81.0,height));
    vec3 material=u_hybrid?hybridMaterial(tone,height,roof):mix(sandstone,modern,smoothstep(13.0,48.0,height));
    bool storefront=linkSite.x>370.0&&linkSite.y>278.0&&linkSite.y<745.0;
    vec3 crafted=anatomyFinish(material,n,linkSite,level,height,tone,false,storefront);
    surface=mix(surface,crafted,link);
  }
  if(u_districtMaterialDetail && u_zoom>14.4){
    vec2 uv=u_districtMaterialTransform.xy+v_position.xy*u_districtMaterialTransform.zw;
    vec2 mask=texture(u_districtMaterialMask,uv).rg;
    float district=mask.r*smoothstep(16.50,17.65,u_zoom)
      *(1.0-neighborhood)*(1.0-linkCoverage);
    if(district>0.0&&!authored){
      vec3 terracotta=mix(vec3(.905,.791,.651),vec3(.754,.566,.473),smoothstep(.08,.92,tone));
      vec3 concrete=mix(vec3(.754,.777,.691),vec3(.526,.647,.660),smoothstep(30.0,75.0,height));
      vec3 material=mix(terracotta,concrete,smoothstep(13.0,48.0,height));
      if(roof&&height<22.0)material=mix(material,vec3(.745,.529,.411),.30);
      if(u_hybrid)material=hybridMaterial(tone,height,roof);
      bool nearbyShop=u_hybrid&&mask.g>.45&&height<38.0;
      // Project from the local survey tile. A city-scale offset amplifies interpolation
      // noise in the face normal and makes otherwise straight windows shimmer.
      vec3 styled=anatomyFinish(material,n,v_position.xy,level,height,tone,false,nearbyShop);
      surface=mix(surface,styled,district);
    }
    if(u_hybrid&&!authored&&height>9.0){
      ivec2 size=textureSize(u_districtMaterialMask,0);
      ivec2 pixel=clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
      float landmarkCode=texelFetch(u_districtMaterialMask,pixel,0).b;
      if(abs(landmarkCode-30.0/255.0)<.006){
        // Keep surveyed roofs and wall shapes. Long window bays and sills distinguish campus façades.
        vec3 plaster=mix(vec3(.902,.798,.654),vec3(.841,.672,.544),tone);
        vec3 schoolRoof=mix(vec3(.687,.665,.592),vec3(.655,.531,.440),tone);
        vec3 campus=anatomyFinish(roof?schoolRoof:plaster,n,v_position.xy,level,height,tone,false,false);
        if(!roof){
          float ledge=strip(level,3.25,.047)*smoothstep(2.0,4.0,level);
          campus=mix(campus,vec3(.976,.898,.727),ledge*.68);
        }
        surface=mix(surface,campus,smoothstep(16.2,17.6,u_zoom)*.88);
      }
      if(landmarkCode>.22){
        bool memorial=landmarkCode<.46;
        bool hotel=landmarkCode>=.46&&landmarkCode<.75;
        if(memorial&&u_cityLandmarks.x>.5&&abs(base-6.05)<.05&&height>13.9)discard;
        if(hotel&&u_cityLandmarks.y>.5&&abs(base-33.38)<.05&&height>32.0)discard;
        if(landmarkCode>.75&&u_cityLandmarks.z>.5&&abs(base-37.59)<.05&&height>15.5)discard;
        surface=mix(surface,heritageFinish(landmarkCode,n,level,height),smoothstep(14.4,16.15,u_zoom));
      }
    }
  }
  if(u_anatomy && neighborhood>0.0){
    vec3 stone=mix(vec3(.849,.789,.664),vec3(.725,.594,.496),smoothstep(.23,.89,tone));
    vec3 glass=east?vec3(.460,.626,.614):vec3(.507,.627,.637);
    vec3 material=authored?original:mix(stone,glass,smoothstep(34.0,76.0,height));
    if(u_hybrid&&!authored)material=hybridMaterial(tone,height,roof);
    vec3 crafted=anatomyFinish(material,n,site,level,height,tone,authored,mall||east);
    surface=mix(surface,crafted,neighborhood);
  }
  vec2 yongchun=v_position.xy+u_streetOffsets.xy;
  vec2 songshan=v_position.xy+u_streetOffsets.zw;
  float yongchunDistance=max(abs(yongchun.x),abs(yongchun.y));
  float songshanDistance=max(abs(songshan.x),abs(songshan.y));
  bool heritage=songshanDistance<yongchunDistance;
  float plot=smoothstep(16.55,17.6,u_zoom)
    *(1.0-smoothstep(90.0,110.0,min(yongchunDistance,songshanDistance)));
  if(plot>0.0){
    vec2 streetSite=heritage?songshan:yongchun;
    bool retail=!heritage&&abs(streetSite.y-16.0)<42.0;
    bool oldFactory=heritage&&height<24.0;
    vec3 stone=mix(vec3(.899,.782,.629),vec3(.735,.544,.472),smoothstep(.10,.90,tone));
    vec3 concrete=mix(vec3(.740,.784,.705),vec3(.519,.650,.666),smoothstep(24.0,74.0,height));
    vec3 material=mix(stone,concrete,smoothstep(14.0,49.0,height));
    if(u_hybrid&&!oldFactory)material=hybridMaterial(tone,height,roof);
    if(oldFactory){
      material=roof?mix(vec3(.657,.403,.348),vec3(.502,.443,.393),tone)
        :mix(vec3(.895,.807,.670),vec3(.753,.628,.514),tone);
    }
    vec3 crafted=anatomyFinish(material,n,streetSite,level,height,tone,oldFactory,retail);
    surface=mix(surface,crafted,plot);
  }
  outColor=vec4(surface,1.0);
}
`;

function makeShader(gl,type,body){
  const shader=gl.createShader(type);
  gl.shaderSource(shader,body);gl.compileShader(shader);
  if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(shader));
  return shader;
}
export function program(gl,vertex=vertexSource,fragment=fragmentSource){
  const p=gl.createProgram();
  const v=makeShader(gl,gl.VERTEX_SHADER,vertex);
  const f=makeShader(gl,gl.FRAGMENT_SHADER,fragment);
  gl.attachShader(p,v);gl.attachShader(p,f);gl.linkProgram(p);
  gl.deleteShader(v);gl.deleteShader(f);
  if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(p));
  return p;
}
export function transform(matrix,tile,out){
  for(let i=0;i<4;i++){
    out[i]=matrix[i]*tile.m;
    out[4+i]=-matrix[4+i]*tile.m;
    out[8+i]=matrix[8+i]*tile.m;
    out[12+i]=matrix[i]*tile.mx+matrix[4+i]*tile.my+matrix[12+i];
  }
}
function intersects(tile,box){
  const [w,s,e,n]=tile.box;
  return w<=box[2]&&e>=box[0]&&s<=box[3]&&n>=box[1];
}
async function unpack(url,signal){
  const response=await fetch(url,{signal});
  if(!response.ok)throw Error(`Building tile returned ${response.status}`);
  return new Response(response.body.pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
}

export const buildingZoom=14.4;
const MiB=1024*1024;

// Both Taipei survey levels contain the same vertices. Small tiles allow the
// phone to fill the nearest streets progressively without decoding a 25 MiB block.
function phoneNeighborhood(tiles){
  const chosen=[];
  let bytes=0;
  for(const tile of tiles){
    bytes+=tile.verts*24;
    if(bytes>16*MiB||chosen.length>=48)break;
    chosen.push(tile);
  }
  return chosen;
}

// The survey format is an unindexed triangle list with six floats per vertex.
// Give both halves of a planar wall the same direction even if their winding differs.
export function surveyWallDirections(vertices) {
  const directions=new Int16Array(vertices.length/3);
  for(let i=0;i<vertices.length;i+=18){
    const ux=vertices[i+6]-vertices[i], uy=vertices[i+7]-vertices[i+1], uz=vertices[i+8]-vertices[i+2];
    const vx=vertices[i+12]-vertices[i], vy=vertices[i+13]-vertices[i+1], vz=vertices[i+14]-vertices[i+2];
    const tx=uz*vx-ux*vz, ty=uz*vy-uy*vz;
    const length=Math.hypot(tx,ty);
    if(length===0)continue;
    const orientation=Math.abs(tx)>length*1e-6?Math.sign(tx):Math.sign(ty);
    const scale=orientation*32767/length;
    const x=Math.round(tx*scale), y=Math.round(ty*scale);
    for(let j=i/3;j<i/3+6;j+=2){
      directions[j]=x;
      directions[j+1]=y;
    }
  }
  return directions;
}

export class SurveyLayer {
  id='survey';
  type='custom';
  renderingMode='3d';
  #enabled=true;
  #landmarkDrawn=false;
  #songyanDrawn=false;
  #cityLandmarksVisible=new Float32Array(3);
  #fetched=new Map();
  #pending=new Map();
  #failures=new Map();
  #wanted=[];
  #displayed=[];
  #mode=null;
  #status;
  #matrix=new Float32Array(16);
  visibleWallTiles=new Set();
  #disposed=false;
  #phoneTiles;
  #phoneSettleTimer;
  #phoneSettled=true;
  #pausePhoneTiles=()=>{
    clearTimeout(this.#phoneSettleTimer);
    this.#phoneSettled=false;
  };
  #settlePhoneTiles=()=>{
    this.#pausePhoneTiles();
    this.#phoneSettleTimer=setTimeout(()=>{
      this.#phoneTiles=undefined;
      this.#phoneSettled=true;
      this.map.triggerRepaint();
    },150);
  };

  constructor(index,status,landmark,anatomy,streetCenters,linkScene,districtMaterial,hybrid=false,cityLandmarks=[],phone=false) {
    this.phone=phone;
    this.districtMaterial=districtMaterial;
    this.linkScene=linkScene;
    this.streetCenters=streetCenters;
    this.anatomy=anatomy;
    this.hybrid=hybrid;
    this.index=index;this.landmark=landmark;
    this.cityLandmarks=cityLandmarks;
    this.songyan=null;
    this.#status=status;
  }
  onAdd(map,gl) {
    this.map=map;this.gl=gl;
    if(this.phone){
      map.on('movestart',this.#pausePhoneTiles);
      map.on('moveend',this.#settlePhoneTiles);
      map.on('resize',this.#settlePhoneTiles);
    }
    this.program=program(gl);
    this.matrixLocation=gl.getUniformLocation(this.program,'u_transform');
    this.zoomLocation=gl.getUniformLocation(this.program,'u_zoom');
    this.focusLocation=gl.getUniformLocation(this.program,'u_focusOffset');
    this.mallCornersLocation=gl.getUniformLocation(this.program,'u_mallCorners');
    this.mallTileLocation=gl.getUniformLocation(this.program,'u_mallTile');
    this.mallBoundsLocation=gl.getUniformLocation(this.program,'u_mallBounds');
    this.mallRingLocation=gl.getUniformLocation(this.program,'u_mallRing[0]');
    this.streetLocation=gl.getUniformLocation(this.program,'u_streetOffsets');
    this.linkOffsetLocation=gl.getUniformLocation(this.program,'u_linkOffset');
    this.linkRunsLocation=gl.getUniformLocation(this.program,'u_linkRuns[0]');
    this.districtMaterialDetailLocation=gl.getUniformLocation(this.program,'u_districtMaterialDetail');
    this.districtMaterialTransformLocation=gl.getUniformLocation(this.program,'u_districtMaterialTransform');
    this.districtMaterialMaskLocation=gl.getUniformLocation(this.program,'u_districtMaterialMask');
    this.cityLandmarkLocation=gl.getUniformLocation(this.program,'u_cityLandmarks');
    this.memorialShellLocation=gl.getUniformLocation(this.program,'u_replaceMemorialShell');
    this.domeShellLocation=gl.getUniformLocation(this.program,'u_replaceDomeShell');
    this.esliteShellLocation=gl.getUniformLocation(this.program,'u_replaceEsliteShell');
    this.dihuaLocation=gl.getUniformLocation(this.program,'u_dihuaOffset');
    this.songyanOffsetLocation=gl.getUniformLocation(this.program,'u_songyanOffset');
    this.songyanTileLocation=gl.getUniformLocation(this.program,'u_songyanTile');
    this.songyanLimitLocation=gl.getUniformLocation(this.program,'u_songyanLimit');
    this.songyanMatchesLocation=gl.getUniformLocation(this.program,'u_songyanMatches[0]');
    this.districtMaterialTexture=gl.createTexture();
    const activeTexture=gl.getParameter(gl.ACTIVE_TEXTURE);
    gl.activeTexture(gl.TEXTURE0);
    const previousTexture=gl.getParameter(gl.TEXTURE_BINDING_2D);
    gl.bindTexture(gl.TEXTURE_2D,this.districtMaterialTexture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    if(this.districtMaterial?.image){
      const flip=gl.getParameter(gl.UNPACK_FLIP_Y_WEBGL);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,this.districtMaterial.image);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,flip);
    }else{
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array(4));
    }
    gl.bindTexture(gl.TEXTURE_2D,previousTexture);
    gl.activeTexture(activeTexture);
    this.linkRuns=new Float32Array(24).fill(1000000);
    if(this.linkScene)this.linkRuns.set(this.linkScene.runs.flat());
    this.anatomyLocation=gl.getUniformLocation(this.program,'u_anatomy');
    this.hybridLocation=gl.getUniformLocation(this.program,'u_hybrid');
    map.triggerRepaint();
  }
  onRemove(){
    this.#disposed=true;
    if(this.phone){
      clearTimeout(this.#phoneSettleTimer);
      this.map.off('movestart',this.#pausePhoneTiles);
      this.map.off('moveend',this.#settlePhoneTiles);
      this.map.off('resize',this.#settlePhoneTiles);
    }
    for(const ctl of this.#pending.values())ctl.abort();
    for(const b of this.#fetched.values())this.#delete(b);
    this.gl.deleteProgram(this.program);
    this.gl.deleteTexture(this.districtMaterialTexture);
  }
  setEnabled(value) {
    this.#enabled=value;
    this.map?.triggerRepaint();
  }
  setMallCutaway(ring){
    this.mallMask=null;
    if(ring){
      const {x:mx,y:my}=ring[0],m=ring[0].meterInMercatorCoordinateUnits();
      const points=ring.slice(0,-1).map(p=>[(p.x-mx)/m,(my-p.y)/m]);
      if(points.length<3||points.length>48)throw Error('Unsupported mall footprint');
      const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
      this.mallMask={mx,my,m,ring:new Float32Array(points.flat()),bounds:[Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)]};
    }
    this.map?.triggerRepaint();
  }
  setSongyan(asset){
    this.songyan={...asset,matchValues:new Float32Array(asset.matches.flat())};
    this.map.triggerRepaint();
  }
  get ready(){
    return this.#displayed.length>0;
  }
  get diagnostics(){
    return {mode:this.#mode,requested:this.#wanted.length,visible:this.#displayed.map(t=>t.id),
      live:this.#pending.size,failed:this.#failures.size,landmark:this.#landmarkDrawn,songyan:this.#songyanDrawn,
      triangles:this.#displayed.reduce((sum,t)=>sum+t.verts/3,0)};
  }
  #select(level) {
    const box=this.map.getBounds().toArray().flat();
    const pad=Math.min(.0045,Math.max(.0013,(box[2]-box[0])*.16));
    const padded=[box[0]-pad,box[1]-pad,box[2]+pad,box[3]+pad];
    const {lng,lat}=this.map.getCenter();
    return this.index.levels[level].filter(t=>intersects(t,padded))
      .map(t=>({tile:t,distance:Math.hypot((t.lngLat[0]-lng)*.90,t.lngLat[1]-lat)}))
      .sort((a,b)=>a.distance-b.distance).map(({tile})=>tile);
  }
  #delete(entry){
    if(entry.directionBuffer)this.gl.deleteBuffer(entry.directionBuffer);
    this.gl.deleteBuffer(entry.buffer);this.gl.deleteVertexArray(entry.vao);
  }
  #start(k,tile,level){
    const ctl=new AbortController();
    this.#pending.set(k,ctl);
    const url=tile.mesh??new URL(`./data/${level}/${tile.file??tile.id}.bin.gz`,import.meta.url);
    if(tile.id==='dihua-fronts')url.searchParams.set('v',String(tile.verts));
    const builder=level==='landmark'&&tile.id==='101'
      ?()=>buildTaipei101Tower(tile.source.min)
      :level==='city-streets/landmark'&&landmarkBuilders.get(tile.id);
    const payload=builder?Promise.resolve().then(()=>builder().buffer):unpack(url,ctl.signal);
    payload.then(data=>{
      if(this.#disposed||ctl.signal.aborted)return;
      const verts=data.byteLength/24;
      if(builder?verts===0||verts%3!==0:verts!==tile.verts)throw Error('Building tile has invalid size');
      const gl=this.gl, vao=gl.createVertexArray(), buffer=gl.createBuffer();
      gl.bindVertexArray(vao);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
      gl.bufferData(gl.ARRAY_BUFFER,new Uint8Array(data),gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,24,0);
      gl.enableVertexAttribArray(1);gl.vertexAttribPointer(1,3,gl.FLOAT,false,24,12);
      let directionBuffer=null, directionBytes=0;
      if(level===200||level===1000){
        const directions=surveyWallDirections(new Float32Array(data));
        directionBuffer=gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER,directionBuffer);
        gl.bufferData(gl.ARRAY_BUFFER,directions,gl.STATIC_DRAW);
        gl.enableVertexAttribArray(2);gl.vertexAttribPointer(2,2,gl.SHORT,true,0,0);
        directionBytes=directions.byteLength;
      }
      gl.bindVertexArray(null);gl.bindBuffer(gl.ARRAY_BUFFER,null);
      this.#fetched.set(k,{vao,buffer,directionBuffer,verts,bytes:data.byteLength+directionBytes,seen:performance.now()});
      this.#failures.delete(k);
    }).catch(error=>{
      if(!ctl.signal.aborted){
        this.#failures.set(k,performance.now()+4000);
        console.warn(error.message,url.pathname);
      }
    }).finally(()=>{
      this.#pending.delete(k);
      if(!this.#disposed)this.map.triggerRepaint();
    });
  }
  #update(zoom){
    const eligible=zoom>=buildingZoom&&this.#enabled;
    const mid=eligible&&!this.phone?this.#select(1000):[];
    const use=eligible&&mid.length<=60;
    const closeCandidates=this.phone
      ?(eligible?(this.#phoneTiles??=phoneNeighborhood(this.#select(200))):[])
      :(zoom>=16.4&&use?this.#select(200):[]);
    const near=closeCandidates.length<=170?closeCandidates:[];
    const queue=(level,tiles)=>tiles.map(tile=>({key:level+'/'+tile.id,tile,level}));
    const close=queue(200,near), distant=queue(1000,use?mid:[]);
    const drawClose=close.length>0&&(this.phone||close.every(t=>this.#fetched.has(t.key)));
    this.#wanted=close.length?close:distant;
    // The upper tower can still be in frame when its footprint is outside the ground view.
    // Submit the separate mesh at both detail levels and let the GPU clip it to the camera.
    const art=this.landmark&&eligible
      ?{key:'landmark/101',tile:this.landmark,level:'landmark'}:null;
    const view=eligible&&(this.cityLandmarks.length||this.songyan||this.dihua)?this.map.getBounds().toArray().flat():null;
    const heritage=view?this.cityLandmarks.filter(tile=>intersects(tile,view))
      .map(tile=>({key:`city-streets/landmark/${tile.id}`,tile,level:'city-streets/landmark'})):[];
    const songyan=view&&this.songyan&&zoom>=17&&intersects(this.songyan,view)
      ?{key:`city-streets/landmark/${this.songyan.file}`,tile:this.songyan,level:'city-streets/landmark'}:null;
    const dihua=view&&this.dihua&&zoom>=17.6&&intersects(this.dihua,view)
      ?{key:'city-streets/landmark/dihua-fronts',tile:this.dihua,level:'city-streets/landmark'}:null;
    const wanted=[...(dihua?[dihua]:[]),...(art?[art]:[]),...(songyan?[songyan]:[]),...heritage,...close,...distant];
    const keys=new Set(wanted.map(t=>t.key));
    for(const [key,ctl] of this.#pending)if(!keys.has(key))ctl.abort();
    const now=performance.now();
    for(const {key,tile,level} of wanted){
      if(this.#pending.size>=(this.phone?2:9))break;
      if(!this.#fetched.has(key)&&!this.#pending.has(key)&&!(this.#failures.get(key)>now)) this.#start(key,tile,level);
    }
    // Switch at one instant. A building is never drawn from both tile levels.
    this.#mode=use?(drawClose?200:1000):null;
    const current=drawClose?close:distant;
    this.#displayed=current.filter(t=>this.#fetched.has(t.key)).map(t=>({...t.tile,key:t.key}));
    const wallRows=drawClose?this.#displayed:[];
    if(this.visibleWallTiles.size!==wallRows.length || wallRows.some(t=>!this.visibleWallTiles.has(t.id))){
      this.visibleWallTiles=new Set(wallRows.map(t=>t.id));
    }
    this.#landmarkDrawn=!!art&&this.#fetched.has(art.key);
    if(this.#landmarkDrawn){
      const {verts}=this.#fetched.get(art.key);
      this.#displayed.push({...art.tile,key:art.key,verts});
    }
    this.#songyanDrawn=!!songyan&&this.#fetched.has(songyan.key);
    if(this.#songyanDrawn)this.#displayed.push({...songyan.tile,key:songyan.key});
    this.dihuaDrawn=!!dihua&&this.#fetched.has(dihua.key);
    if(this.dihuaDrawn)this.#displayed.push({...dihua.tile,key:dihua.key});
    this.#cityLandmarksVisible.fill(0);
    this.memorialDrawn=false;
    this.domeDrawn=false;
    this.esliteDrawn=false;
    for(const {key,tile} of heritage){
      const asset=this.#fetched.get(key);
      if(!asset)continue;
      this.#displayed.push({...tile,key,verts:asset.verts});
      if(tile.id===sunYatSenHall.id)this.memorialDrawn=true;
      else if(tile.id===taipeiDome.id)this.domeDrawn=true;
      else if(tile.id===esliteSongyan.id)this.esliteDrawn=true;
      else this.#cityLandmarksVisible[tile.style]=1;
    }
    for(const t of wanted){
      const entry=this.#fetched.get(t.key);
      if(entry)entry.seen=now;
    }
    let bytes=0;
    for(const b of this.#fetched.values())bytes+=b.bytes;
    if(bytes>(this.phone?24:95)*MiB||this.#fetched.size>(this.phone?72:235)){
      const stale=[...this.#fetched].filter(([k])=>!keys.has(k)).sort((a,b)=>a[1].seen-b[1].seen);
      for(const [key,item] of stale){
        this.#delete(item);this.#fetched.delete(key);bytes-=item.bytes;
        if(bytes<(this.phone?20:80)*MiB&&this.#fetched.size<(this.phone?60:190))break;
      }
    }
    const landmarkFailed=art&&this.#failures.has(art.key)&&intersects(art.tile,this.map.getBounds().toArray().flat());
    const message=landmarkFailed?'台北 101 模型讀取中斷，移動地圖可重試。'
      :this.#wanted.some(t=>this.#failures.has(t.key))?'部分建物讀取中斷，移動地圖可重試。'
      :this.#pending.size>0&&!this.ready?'載入 2025 建物…':'';
    this.#status(message);
  }
  pickDihuaEntrance(point) {
    if(!this.#enabled || !this.dihuaDrawn || !this.dihuaMatrix || this.map.getZoom()<19.25)return;
    const matrix=this.dihuaMatrix, canvas=this.map.getCanvas();
    for(const {number,corners} of this.dihua.entrances??[]){
      const projected=corners.map(([x,y,z])=>{
        const component=i=>matrix[i]*x+matrix[i+4]*y+matrix[i+8]*z+matrix[i+12];
        const w=component(3);
        return w>0?[(1+component(0)/w)*canvas.clientWidth/2,(1-component(1)/w)*canvas.clientHeight/2]:null;
      });
      // Front-facing openings wind clockwise in world space, counterclockwise on screen.
      if(projected.every(Boolean) && projected.every(([x,y],i)=>{
        const [nx,ny]=projected[(i+1)%4];
        return (nx-x)*(point.y-y)-(ny-y)*(point.x-x)<=0;
      }))return number;
    }
  }
  render(gl,options) {
    const zoom=this.map.getZoom();
    // Reuse already uploaded geometry while a pinch or camera flight is in progress.
    // The settled view starts its own bounded requests on the next render.
    if(!this.phone||(this.#phoneSettled&&!this.map.isMoving()))this.#update(zoom);
    if(!this.#enabled||zoom<buildingZoom||!this.#displayed.length)return;
    gl.useProgram(this.program);
    gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);
    gl.disable(gl.CULL_FACE);gl.disable(gl.BLEND);
    gl.uniform1f(this.zoomLocation,zoom);
    gl.uniform1i(this.mallCornersLocation,this.mallMask?this.mallMask.ring.length/2:0);
    if(this.mallMask){
      gl.uniform2fv(this.mallRingLocation,this.mallMask.ring);
      gl.uniform4fv(this.mallBoundsLocation,this.mallMask.bounds);
    }
    gl.uniform4fv(this.linkRunsLocation,this.linkRuns);
    const activeTexture=gl.getParameter(gl.ACTIVE_TEXTURE);
    gl.activeTexture(gl.TEXTURE0);
    const previousTexture=gl.getParameter(gl.TEXTURE_BINDING_2D);
    gl.bindTexture(gl.TEXTURE_2D,this.districtMaterialTexture);
    gl.uniform1i(this.districtMaterialMaskLocation,0);
    gl.uniform1i(this.districtMaterialDetailLocation,this.districtMaterial?.image?1:0);
    gl.uniform1i(this.anatomyLocation,this.anatomy?1:0);
    gl.uniform1i(this.hybridLocation,this.hybrid?1:0);
    gl.uniform3fv(this.cityLandmarkLocation,this.#cityLandmarksVisible);
    if(this.#songyanDrawn){
      gl.uniform4fv(this.songyanLimitLocation,this.songyan.limit);
      gl.uniform3fv(this.songyanMatchesLocation,this.songyan.matchValues);
    }
    for(const tile of this.#displayed){
      const {vao}=this.#fetched.get(tile.key);
      gl.uniform1i(this.memorialShellLocation,this.memorialDrawn&&isMemorialSurveyTile(tile.key)?1:0);
      gl.uniform1i(this.domeShellLocation,this.domeDrawn&&isDomeSurveyTile(tile.key)?1:0);
      gl.uniform1i(this.esliteShellLocation,this.esliteDrawn&&esliteSurveyTiles.has(tile.key)?1:0);
      if(this.mallMask){
        const {mx,my,m}=this.mallMask;
        gl.uniform3f(this.mallTileLocation,(tile.mx-mx)/m,(my-tile.my)/m,tile.m/m);
      }
      gl.uniform1i(this.songyanTileLocation,tile.id==='songyan'||tile.id==='dihua-fronts'||tile.id===esliteSongyan.id?1:0);
      gl.uniform3f(this.dihuaLocation,this.dihua?(tile.mx-this.dihua.mx)/tile.m:0,
        this.dihua?(this.dihua.my-tile.my)/tile.m:0,this.dihuaDrawn?1:0);
      gl.uniform3f(this.songyanOffsetLocation,
        this.songyan?(tile.mx-this.songyan.mx)/tile.m:0,
        this.songyan?(this.songyan.my-tile.my)/tile.m:0,
        this.#songyanDrawn?1:0);
      gl.uniform2f(this.focusLocation,
        this.landmark?(tile.mx-this.landmark.mx)/tile.m:1e5,
        this.landmark?(this.landmark.my-tile.my)/tile.m:1e5);
      const [yongchun,songshan]=this.streetCenters;
      gl.uniform4f(this.streetLocation,
        yongchun?(tile.mx-yongchun.x)/tile.m:1e5,
        yongchun?(yongchun.y-tile.my)/tile.m:1e5,
        songshan?(tile.mx-songshan.x)/tile.m:1e5,
        songshan?(songshan.y-tile.my)/tile.m:1e5);
      const anchor=this.linkScene?.anchor;
      gl.uniform2f(this.linkOffsetLocation,
        anchor?(tile.mx-anchor.x)/tile.m:0,
        anchor?(anchor.y-tile.my)/tile.m:0);
      if(this.districtMaterial?.image){
        const [west,north,east,south]=this.districtMaterial.bounds;
        gl.uniform4f(this.districtMaterialTransformLocation,(tile.mx-west)/(east-west),(tile.my-north)/(south-north),
          tile.m/(east-west),-tile.m/(south-north));
      }
      transform(options.defaultProjectionData.mainMatrix,tile,this.#matrix);
      if(tile.id==='dihua-fronts'){
        this.dihuaMatrix??=new Float32Array(16);
        this.dihuaMatrix.set(this.#matrix);
      }
      gl.uniformMatrix4fv(this.matrixLocation,false,this.#matrix);
      gl.bindVertexArray(vao);
      gl.drawArrays(gl.TRIANGLES,0,tile.verts);
    }
    gl.bindVertexArray(null);
    gl.bindTexture(gl.TEXTURE_2D,previousTexture);
    gl.activeTexture(activeTexture);
  }
}
