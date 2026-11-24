import {createHash, randomUUID} from 'node:crypto';
import {readFile, rename, unlink, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {gunzipSync} from 'node:zlib';

const districts=['松山區','信義區','大安區','中山區','中正區','大同區','萬華區','文山區','南港區','內湖區','士林區','北投區'];
const numerals='一二三四五六七八九十';
const day=24*60*60*1000;
const mapCategories={food:['restaurant','餐廳'],restaurant:['restaurant','餐廳'],cafe:['cafe','咖啡廳'],
  shopping:['shop','店家'],market:['marketplace','市場'],attraction:['attraction','景點'],
  entertainment:['attraction','休閒'],lodging:['lodging','住宿']};
const normalize=value=>(value??'').normalize('NFKC').replaceAll('臺','台').replace(/\s/g,'');
const foldName=value=>normalize(value).toLowerCase();
const identity=place=>JSON.stringify([place.provider,place.providerPlaceID]);
const distance=(place,[lng,lat])=>Math.hypot((lng-place.longitude)*100780,(lat-place.latitude)*110800);

function streetAddress(value){
  const normalized=normalize(value).replace(/^(?:\d{3,6})?(?:台灣)?(?:台北市)?/u,'');
  const district=districts.find(district=>normalized.startsWith(district));
  const street=(district?normalized.slice(district.length):normalized)
    .replace(/([路街道])([1-9]|10)段/gu,(_,kind,section)=>kind+numerals[Number(section)-1]+'段')
    .replace(/(\d+)號之(\d+)/gu,'$1-$2號').replace(/(\d)之(?=\d)/gu,'$1-');
  const match=street.match(/^([^\d號]+(?:路|街|大道|道)(?:[一二三四五六七八九十]+段)?(?:\d+巷)?(?:\d+弄)?\d+(?:-\d+)?號)(.*)$/u);
  if(!match)return null;
  const unit=match[2].toUpperCase().replace(/^(B?\d+)F/u,'$1樓');
  return {district,door:match[1],unit};
}

function group(rows,keyFor){
  const grouped=new Map();
  for(const row of rows){
    const key=keyFor(row);
    if(!grouped.has(key))grouped.set(key,[]);
    grouped.get(key).push(row);
  }
  return grouped;
}

export function buildSavvyPlaceSources(index,map,localized=[],reviewed=[]){
  const city=map.features.filter(row=>row.geometry?.type==='Point'&&row.properties?.placeId);
  const cityByID=group(city,row=>row.properties.placeId);
  const byName=group(city,row=>foldName(row.properties.name));
  const translations=new Map(localized.map(row=>[identity(row),row]));
  const posts=group(index.posts.filter(row=>row.platform==='threads'||row.platform==='instagram'),row=>identity(row.place));
  const evidence=place=>{
    const translation=translations.get(identity(place));
    return streetAddress(translation?.expectedAddress===place.address?translation.address:place.address);
  };
  const find=({place},{properties,geometry},address,unit,limit=45)=>{
    const mapAddress=streetAddress(properties.detail);
    return address?.district&&(mapAddress?.district??properties.district)===address.district
      && address.door===mapAddress?.door && unit===mapAddress.unit
      && distance(place,geometry.coordinates)<=limit;
  };
  const mapped=new Map(), reserved=new Set(), proposed=[];
  for(const row of reviewed){
    const key=identity(row);
    const source=posts.get(key)?.[0];
    const candidates=cityByID.get(row.placeId);
    const target=candidates?.[0];
    if(candidates?.length!==1||reserved.has(row.placeId)||mapped.has(key)
      ||target.properties.name!==row.cityName||target.properties.district!==row.district
      ||streetAddress(target.properties.detail)?.door!==row.door
      ||streetAddress(target.properties.detail)?.unit!==(row.cityUnit??'')){
      throw Error('Invalid reviewed Savvy place mapping '+row.placeId);
    }
    reserved.add(row.placeId);
    if(!source)continue;
    const address=evidence(source.place);
    if(source.place.name!==row.savvyName||address?.door!==row.door||address.district!==row.district
      ||address.unit!==(row.savvyUnit??'')
      ||!find(source,target,address,row.cityUnit??'',85))throw Error('Changed reviewed Savvy venue '+row.placeId);
    mapped.set(key,{placeId:row.placeId,method:'reviewed'});
  }
  const reasons=new Map();
  for(const [key,originals] of posts){
    if(mapped.has(key))continue;
    const source=originals[0],address=evidence(source.place);
    if(!address?.district){reasons.set(key,'missing_taipei_street_address');continue;}
    const candidates=(byName.get(foldName(source.place.name))??[]).filter(row=>find(source,row,address,address.unit));
    if(candidates.length!==1){reasons.set(key,candidates.length?'multiple_city_matches':'no_exact_city_match');continue;}
    proposed.push({key,placeId:candidates[0].properties.placeId});
  }
  const claims=group(proposed,row=>row.placeId);
  for(const {key,placeId} of proposed){
    if(reserved.has(placeId)||claims.get(placeId).length!==1||cityByID.get(placeId).length!==1){
      reasons.set(key,'city_identity_conflict');continue;
    }
    mapped.set(key,{placeId,method:'name_address_coordinates'});
  }
  const projectedVenue=(originals,placeId,method)=>{
    const {provider,providerPlaceID}=originals[0].place;
    return {placeId,provider,providerPlaceID,method,posts: originals.slice()
      .sort((a,b)=>(a.highlightRank??Infinity)-(b.highlightRank??Infinity))
      .map(({platform,sourceURL,title,authorHandle,cover,verifiedAt,visibleUntil})=>({
        platform,url:sourceURL,title,authorHandle,cover,
        expiresAt:new Date(Math.min(Date.parse(index.expiresAt),Date.parse(verifiedAt)+day,
          visibleUntil?Date.parse(visibleUntil):Infinity)).toISOString(),
      }))};
  };
  const venues=[...mapped].map(([key,{placeId,method}])=>projectedVenue(posts.get(key),placeId,method));
  const verifiedPins=[];
  for(const [key,originals] of posts){
    if(mapped.has(key))continue;
    const {place}=originals[0];
    const placeId=`savvy/${place.provider}/${encodeURIComponent(place.providerPlaceID)}`;
    if(cityByID.has(placeId))throw Error('Reserved Savvy place ID collision');
    const [category,categoryLabel]=Object.hasOwn(mapCategories,place.category)?mapCategories[place.category]:['other','地點'];
    verifiedPins.push({...projectedVenue(originals,placeId,'verified_savvy_location'),
      point:[place.longitude,place.latitude],name:place.name,detail:place.address,
      district:evidence(place)?.district??'',category,categoryLabel});
  }
  return {schemaVersion:1,expiresAt:index.expiresAt,venues,verifiedPins,
    coverage:{mapPlaces:city.length,savvyPlaces:posts.size,mapped:venues.length,unmatched:posts.size-venues.length,
      unmatchedMapPlaces:city.length-venues.length,verifiedPins:verifiedPins.length,
      originals:venues.reduce((sum,row)=>sum+row.posts.length,0),
      additionalOriginals:verifiedPins.reduce((sum,row)=>sum+row.posts.length,0),
      reasons:Object.fromEntries([...group([...reasons.values()],reason=>reason)].map(([reason,rows])=>[reason,rows.length]))}};
}

async function main([indexPath,mapPath,localizedPath,outputPath,projectionPath='backend/dist/publicDiscovery.js']){
  if(!outputPath)throw Error('Usage: node build-savvy-place-sources.mjs index.json map.json.gz localized.json output.json [backend projection module]');
  const [{projectCurrentPublicDiscoveryManifest},indexBytes,mapBytes,localBytes,reviewedBytes]=await Promise.all([
    import(pathToFileURL(resolve(projectionPath))),readFile(indexPath),readFile(mapPath),readFile(localizedPath),
    readFile(new URL('./savvy-reviewed-place-links.json',import.meta.url)),
  ]);
  const mapJSON=mapPath.endsWith('.gz')?gunzipSync(mapBytes):mapBytes;
  const snapshot=buildSavvyPlaceSources(projectCurrentPublicDiscoveryManifest(JSON.parse(indexBytes)),
    JSON.parse(mapJSON),JSON.parse(localBytes),JSON.parse(reviewedBytes));
  const temp=outputPath+'.'+randomUUID()+'.tmp';
  try{await writeFile(temp,JSON.stringify(snapshot)+'\n',{flag:'wx'});await rename(temp,outputPath);}
  finally{await unlink(temp).catch(error=>{if(error.code!=='ENOENT')throw error;});}
  const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
  console.log(JSON.stringify({...snapshot.coverage,indexSHA256:digest(indexBytes),mapSHA256:digest(mapJSON)}));
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)await main(process.argv.slice(2));
