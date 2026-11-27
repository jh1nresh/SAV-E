// Optional local Debug catalog. Curator references stay separate from verified
// public discovery and never become personal saves or visit records.
let loading;
const file = new URL('./CreatorPlaceSources.json', import.meta.url);
export function validateCreatorCatalog(data) {
  if (data?.schemaVersion !== 1 || data.scope !== 'local_creator_preview'
      || data.creator !== 'zeke_6973' || !Array.isArray(data.entries) || data.entries.length > 2000) return null;
  const ids = new Set(), cids = new Set();
  for (const row of data.entries) {
    if (!row || typeof row.placeId !== 'string' || !row.placeId || ids.has(row.placeId) || cids.has(row.cid)
        || typeof row.cid !== 'string' || !/^[1-9]\d{0,19}$/.test(row.cid)
        || typeof row.name !== 'string' || !row.name || typeof row.address !== 'string'
        || typeof row.category !== 'string' || typeof row.city !== 'string'
        || !Number.isFinite(row.latitude) || !Number.isFinite(row.longitude)
        || Math.abs(row.latitude) > 90 || Math.abs(row.longitude) > 180
        || typeof row.isNew !== 'boolean'
        || (row.isNew && row.placeId !== 'creator/lala/' + row.cid)
        || !Array.isArray(row.posts) || !Array.isArray(row.lists)
        || !row.lists.length || row.lists.some(s => !['wish','visited'].includes(s))) return null;
    for (const post of row.posts) {
      if (!post || post.author !== data.creator || typeof post.text !== 'string' || post.text.length > 4000
          || !/^https:\/\/www\.threads\.com\/@zeke_6973\/post\/[\w-]+$/.test(post.url)
          || !/^\d{4}-\d{2}-\d{2}$/.test(post.date)) return null;
    }
    ids.add(row.placeId); cids.add(row.cid);
  }
  return data;
}
export async function loadCreatorCatalog() {
  if (!loading) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);
    loading = fetch(file, {credentials:'omit', cache:'no-store', signal:controller.signal})
      .then(r => r.ok ? r.text() : '').then(text => text.length <= 2_000_000 && text ? JSON.parse(text) : null)
      .then(validateCreatorCatalog).catch(() => null).finally(() => clearTimeout(timeout));
  }
  return loading;
}
export function appendCreatorPlaces(city, catalog) {
  if (!catalog) return city;
  const ids = new Set(city.features.map(f => f.properties.placeId));
  // Native-only existing venues also need their canonical pin when the optional
  // expiring public-post snapshot is absent. Never mint a second creator ID.
  const added = catalog.entries.filter(r => !ids.has(r.placeId)).map(r => ({
    type:'Feature', id:r.placeId, geometry:{type:'Point', coordinates:[r.longitude,r.latitude]},
    properties:{placeId:r.placeId, name:r.name, detail:r.address, district:r.city,
      category:r.category.includes('景點')?'attraction':r.category.includes('飲料')?'cafe':'restaurant',
      categoryLabel:r.category, creatorSource:true, source:'拉拉熊公開清單',
      url:'https://www.google.com/maps?cid='+r.cid},
  }));
  const byID = new Map(catalog.entries.map(r => [r.placeId,r]));
  const features = city.features.map(f => {
    const row = byID.get(f.properties.placeId);
    return row && !f.properties.name?.trim()
      ? {...f, properties:{...f.properties,name:row.name,detail:row.address}} : f;
  });
  return {...city, features:[...features, ...added]};
}
export function withoutCreatorDuplicates(featureCollection, catalog) {
  if (!catalog) return featureCollection;
  const ids = new Set(catalog.entries.map(r => r.placeId));
  return {...featureCollection,features:featureCollection.features.filter(f => !ids.has(f.properties.placeId))};
}
export function creatorEntry(catalog, placeId) {
  return catalog?.entries.find(r => r.placeId === placeId) ?? null;
}
