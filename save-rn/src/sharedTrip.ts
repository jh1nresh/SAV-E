import { Buffer } from "buffer";
import { Place, SharedTripData } from "./models";

export function buildSharedTripData(
  name: string,
  city: string,
  places: Place[]
): SharedTripData {
  return {
    name,
    city,
    stops: places.map((place) => ({
      id: place.id,
      name: place.name,
      address: place.address,
      lat: place.latitude,
      lng: place.longitude,
      time: place.time,
      note: place.note,
    })),
  };
}

export function buildTripLink(
  trip: SharedTripData,
  baseUrl = "https://wanderly.app/trip"
): string {
  const json = JSON.stringify(trip);
  const base64 = Buffer.from(json, "utf8").toString("base64");
  const encoded = encodeURIComponent(base64);
  return `${baseUrl}?d=${encoded}`;
}

export function decodeTripLink(link: string): SharedTripData | null {
  try {
    const url = new URL(link);
    const payload = url.searchParams.get("d");
    if (!payload) return null;
    const json = Buffer.from(decodeURIComponent(payload), "base64").toString("utf8");
    return JSON.parse(json) as SharedTripData;
  } catch {
    return null;
  }
}

export function buildAppleMapsUrl(place: Place): string {
  const daddr = encodeURIComponent(place.address || `${place.latitude},${place.longitude}`);
  const q = encodeURIComponent(place.name);
  return `https://maps.apple.com/?daddr=${daddr}&q=${q}`;
}
