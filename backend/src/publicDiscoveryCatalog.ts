const destinations = new Map([
  ["Attraction_379000000A_002265", {
    name: "白石湖休閒農業區", address: "臺北市內湖區", latitude: 25.105136, longitude: 121.594043, category: "area",
  }],
  ["Attraction_379000000A_000008", {
    name: "雙溪生活水岸自行車道", address: "臺北市士林區", latitude: 25.09992, longitude: 121.52802, category: "route",
  }],
]);

export function isCatalogDestinationID(id: unknown): id is string {
  return typeof id === "string" && destinations.has(id);
}

export function matchesCatalogDestination(place: Record<string, unknown>): boolean {
  return isCatalogDestinationID(place.providerPlaceID) && Object.entries(destinations.get(place.providerPlaceID)!)
    .every(([field, value]) => place[field] === value);
}
