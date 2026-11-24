// Georeferenced 170 m Pocket City plot centred on the surveyed west-facing shop row.
const origin=[121.543674,25.027489];
const halfLat=85/110574,halfLon=85/(111320*Math.cos(origin[1]*Math.PI/180));
const [x,y]=origin;
const bounds=[x-halfLon,y-halfLat,x+halfLon,y+halfLat];
export function inFuxing(lon,lat){
  return lon>=bounds[0]&&lon<=bounds[2]&&lat>=bounds[1]&&lat<=bounds[3];
}
export const bookstoreId='poi/node/3403899627';
export function frontageCamera(x,y,angle){
  const normal=angle*Math.PI/180;
  const center=[x+Math.cos(normal)*1.1/100780,y+Math.sin(normal)*1.1/110800];
  return {center,bearing:270-angle-5,pitch:58,mobilePitch:58,zoom:21.40,mobileZoom:21.38};
}
export const bookshopView=frontageCamera(121.54367371,25.02748876,179.8);

// Pull back to the south-west to keep the bookshop and both neighbours together.
export const shopRowView={...bookshopView,center:[121.543662,25.027503],bearing:70,pitch:65,mobilePitch:65,zoom:20.88,mobileZoom:20.70};
export const bookshopEvidence={
  name:'信義書局',categoryLabel:'書店',kind:'shopfront',
  detail:'復興南路二段 · 招牌、騎樓與雜誌陳列參照攝影紀錄繪製',
  source:'書店裡的影像詩',url:'https://www.dream-land.com.tw/56%E4%BF%A1%E7%BE%A9%E6%9B%B8%E5%B1%80/',
};
