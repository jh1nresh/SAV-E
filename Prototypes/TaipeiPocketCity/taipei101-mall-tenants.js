// Branch floors are confirmed by the venue and tenant directories. Locations are
// the existing OSM shop nodes, just outside the retail wing used for the cutaway.
const tenants=[
  {
    id:'node/2718780533',streetPinId:'din-tai-fung',name:'鼎泰豐',level:'B1',category:'restaurant',categoryLabel:'餐廳',
    point:[121.5645173,25.0334657],
    floorSourceUrl:'https://www.taipei-101.com.tw/tw/food/content/7218f865-fad9-49a3-a543-436c981c0cb7',
    branchUrl:'https://www.dintaifung.com.tw/store.php',
  },
  {
    id:'node/4943315872',name:'Apple 台北 101',level:'1F',category:'electronics',categoryLabel:'電子用品',
    point:[121.5643036,25.0337553],
    floorSourceUrl:'https://www.taipei-101.com.tw/tw/shopping/brandsearch/content/37749f6d-69c1-4c08-8f50-39cbfe4f109c',
    branchUrl:'https://www.apple.com/tw/retail/taipei101/',
  },
];

export const mallAdjacentTenants=tenants.map(({point,...tenant})=>({
  type:'Feature',id:tenant.id,geometry:{type:'Point',coordinates:point},
  properties:{...tenant,kind:'shop',adjacent:true,source:'OpenStreetMap',
    url:'https://www.openstreetmap.org/'+tenant.id},
}));
