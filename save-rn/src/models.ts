export type PlaceCategory =
  | "food"
  | "cafe"
  | "bar"
  | "attraction"
  | "stay"
  | "shopping";

export type PlaceStatus = "wantToGo" | "visited";
export type ImportKind = "place" | "event" | "draft";

export type SourcePlatform =
  | "instagram"
  | "threads"
  | "xiaohongshu"
  | "googleMaps"
  | "appleMaps"
  | "luma"
  | "other";

export type Place = {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  category: PlaceCategory;
  status: PlaceStatus;
  sourcePlatform: SourcePlatform;
  priceRange?: string;
  note?: string;
  time?: string;
  sourceUrl?: string;
  importKind?: ImportKind;
  eventLabel?: string;
};

export type SharedStop = {
  id: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
  time?: string;
  note?: string;
};

export type SharedTripData = {
  name: string;
  city: string;
  stops: SharedStop[];
};

export type TripStop = {
  id: string;
  placeId?: string | null;
  placeName: string;
  day: number;
  orderIndex: number;
  startTime?: string | null;
  duration?: number | null;
  note?: string | null;
};

export type TripRecord = {
  id: string;
  name: string;
  city: string;
  isOptimized: boolean;
  createdAt?: string;
  tripStops: TripStop[];
};

export const categoryLabel: Record<PlaceCategory, string> = {
  food: "Food",
  cafe: "Cafe",
  bar: "Bar",
  attraction: "Attraction",
  stay: "Stay",
  shopping: "Shopping",
};

export const statusLabel: Record<PlaceStatus, string> = {
  wantToGo: "Want to Go",
  visited: "Visited",
};
