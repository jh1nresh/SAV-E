let snapshot;
const file=new URL('./savvy-place-sources.json',import.meta.url);

export function cityPlaceID(place){
  const id=place?.placeId??place?.id;
  if(typeof id!=='string')return undefined;
  const osm=id.match(/^osm-(node|way|relation)-(\d+)$/);
  return osm?`poi/${osm[1]}/${osm[2]}`:id;
}

function originalURL(platform,value){
  try{
    const url=new URL(value);
    if(url.protocol!=='https:'||url.port||url.username||url.password||url.search||url.hash)return null;
    if(platform==='instagram'&&url.hostname==='www.instagram.com'&&/^\/(?:p|reel|tv)\/[\w-]+\/$/.test(url.pathname))return url.href;
    if(platform==='threads'&&url.hostname==='www.threads.com'&&/^\/@[\w.]+\/post\/[\w-]+$/.test(url.pathname))return url.href;
  }catch{}
  return null;
}

function approvedCover(cover,time){
  if(!cover||!(Date.parse(cover.expiresAt)>time)||!['author','provider'].includes(cover.permission))return null;
  try{
    const url=new URL(cover.url);
    if(url.protocol==='https:'&&!url.port&&!url.username&&!url.password
      &&/(^|\.)(cdninstagram\.com|fbcdn\.net)$/.test(url.hostname))return url.href;
  }catch{}
  return null;
}

export function validSavvyPosts(posts,time=Date.now(),snapshotExpiry=Infinity){
  if(!Array.isArray(posts))return [];
  return posts.flatMap(post=>{
    if(!post||typeof post!=='object')return [];
    const url=originalURL(post.platform,post.url);
    const expiresAt=Math.min(Date.parse(post.expiresAt),snapshotExpiry);
    if(!url||!(expiresAt>time))return [];
    const cover=approvedCover(post.cover,time);
    return [{...post,url,expiresAt,cover,coverPermission:cover?post.cover.permission:null,coverExpiry:cover?Date.parse(post.cover.expiresAt):Infinity}];
  });
}

async function loadSnapshot(now){
  snapshot??=fetch(file,{credentials:'omit',cache:'no-store'}).then(async response=>{
    if(!response.ok)throw Error('Savvy place sources unavailable');
    const data=await response.json();
    const verifiedPins=data.verifiedPins??[];
    if(data.schemaVersion!==1||!Array.isArray(data.venues)||!Array.isArray(verifiedPins)){
      throw Error('Invalid Savvy place source projection');
    }
    const rows=[...data.venues,...verifiedPins];
    const byPlace=new Map(rows.map(row=>[row.placeId,row.posts]));
    if(byPlace.size!==data.venues.length+verifiedPins.length)throw Error('Duplicate Savvy place source mapping');
    return {rows,byPlace,verifiedPins,expiresAt:Date.parse(data.expiresAt)};
  }).catch(()=>{snapshot=null;return null;});
  const data=await snapshot;
  if(data&&!(data.expiresAt>now)){snapshot=null;return null;}
  return data;
}

export async function reviewedSavvyPosts(place){
  const id=cityPlaceID(place);
  if(!id)return [];
  const data=await loadSnapshot(Date.now());
  return data?validSavvyPosts(data.byPlace.get(id),Date.now(),data.expiresAt):[];
}

export function verifiedSavvyMapProjection(rows,time,snapshotExpiry){
  const features=[];
  let nextExpiry=Infinity;
  for(const row of rows){
    if(!row||typeof row!=='object')continue;
    const {placeId,point,name,detail,district,category,categoryLabel,posts}=row;
    if(typeof placeId!=='string'||!placeId.startsWith('savvy/')||typeof name!=='string'||!name.trim()
      ||typeof detail!=='string'||typeof district!=='string'||typeof category!=='string'||typeof categoryLabel!=='string'
      ||!Array.isArray(point)||point.length!==2||!point.every(Number.isFinite)
      ||Math.abs(point[0])>180||Math.abs(point[1])>90)continue;
    const originals=validSavvyPosts(posts,time,snapshotExpiry);
    if(!originals.length)continue;
    const sourcesExpireAt=Math.max(...originals.map(post=>post.expiresAt));
    nextExpiry=Math.min(nextExpiry,sourcesExpireAt);
    features.push({type:'Feature',id:placeId,geometry:{type:'Point',coordinates:point},properties:{
      placeId,name,detail,district,category,categoryLabel,sourcesExpireAt,source:'Savvy',
    }});
  }
  return {featureCollection:{type:'FeatureCollection',features},nextExpiry};
}

export async function loadVerifiedSavvyMapPins(){
  const data=await loadSnapshot(Date.now());
  return verifiedSavvyMapProjection(data?.verifiedPins??[],Date.now(),data?.expiresAt??0);
}

// LiveMapPlace.discovery uses this exact provider-qualified ID. Only an active
// reviewed mapping can replace a native Explore marker with its atlas pin.
export function nativeExploreVenues(rows,time,snapshotExpiry){
  const venues=new Map();
  for(const {placeId,provider,providerPlaceID,posts} of rows){
    const originals=validSavvyPosts(posts,time,snapshotExpiry);
    if(originals.length)venues.set('public:'+provider+':'+providerPlaceID,{
      placeId,expiresAt:Math.max(...originals.map(post=>post.expiresAt)),
    });
  }
  return venues;
}

export async function loadNativeExploreVenues(){
  const data=await loadSnapshot(Date.now());
  return nativeExploreVenues(data?.rows??[],Date.now(),data?.expiresAt??0);
}
