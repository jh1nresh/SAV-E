import {cityPlaceID} from './savvy-place-sources.js';

// Shared with native Saved cards; keep branch identity and attribution together.
import entries from './place-photo-data.js';

const photosById = new Map(entries.map(entry => [entry.id, entry]));

export const photoPlaces = entries.map(({id, name, point, categoryLabel, detail}) => ({
  placeId:id, name, point, categoryLabel, detail,
  source: 'OpenStreetMap',
  url: `https://www.openstreetmap.org/${id.slice(4)}`,
}));

export function originalPlacePhoto(place) {
  const id = cityPlaceID(place);
  const entry = photosById.get(id);
  if (!entry) return null;
  return {
    file: entry.file,
    src: new URL(`./assets/place-photos/${entry.file}`, import.meta.url).href,
    alt: entry.alt,
    credit: entry.credit,
    url: `https://commons.wikimedia.org/wiki/File:${encodeURIComponent(entry.commonsFile)}`,
  };
}
