import { Place, PlaceCategory, SourcePlatform } from "./models";

const coordinatePattern = /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/;

export function parseSharedLink(input: string): Place | null {
  const normalized = normalizeInput(input);
  if (!normalized) return null;

  let url: URL;
  try {
    url = new URL(normalized);
  } catch {
    return null;
  }

  const host = url.hostname.toLowerCase();
  const platform = detectPlatform(host);

  if (platform === "googleMaps") {
    return buildGoogleMapsPlace(url);
  }

  if (platform === "appleMaps") {
    return buildAppleMapsPlace(url);
  }

  if (platform === "luma") {
    return buildEventPlace(url, "luma");
  }

  if (platform === "instagram" || platform === "threads" || platform === "xiaohongshu") {
    return buildSocialPlace(url, platform);
  }

  return buildGenericPlace(url);
}

function normalizeInput(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed) return null;
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (trimmed.includes(".")) return `https://${trimmed}`;
  return null;
}

function detectPlatform(host: string): SourcePlatform {
  if (host.includes("google.") || host.includes("maps.app.goo.gl")) return "googleMaps";
  if (host.includes("maps.apple.com")) return "appleMaps";
  if (host.includes("lu.ma")) return "luma";
  if (host.includes("instagram.com") || host.includes("instagr.am")) return "instagram";
  if (host.includes("threads.net")) return "threads";
  if (host.includes("xiaohongshu") || host.includes("xhslink")) return "xiaohongshu";
  return "other";
}

function buildGoogleMapsPlace(url: URL): Place {
  const name = decodeSegment(
    url.searchParams.get("q") ||
      url.searchParams.get("query") ||
      extractPlaceSegment(url.pathname) ||
      "Shared Google Maps Place"
  );
  const [latitude, longitude] = extractCoordinates(url);
  const address = decodeSegment(
    url.searchParams.get("daddr") ||
      url.searchParams.get("destination") ||
      extractAddressCandidate(url) ||
      "Imported from Google Maps"
  );

  return buildPlace({
    name: cleanName(name),
    address,
    latitude,
    longitude,
    category: inferCategory(`${name} ${address}`),
    sourcePlatform: "googleMaps",
    sourceUrl: url.toString(),
    note: "Imported from a Google Maps link.",
    importKind: "place",
  });
}

function buildAppleMapsPlace(url: URL): Place {
  const query = url.searchParams.get("q");
  const address = decodeSegment(
    url.searchParams.get("address") ||
      url.searchParams.get("daddr") ||
      query ||
      "Imported from Apple Maps"
  );
  const [latitude, longitude] = extractCoordinates(url);

  return buildPlace({
    name: cleanName(decodeSegment(query || "Shared Apple Maps Place")),
    address,
    latitude,
    longitude,
    category: inferCategory(`${query ?? ""} ${address}`),
    sourcePlatform: "appleMaps",
    sourceUrl: url.toString(),
    note: "Imported from an Apple Maps link.",
    importKind: "place",
  });
}

function buildEventPlace(url: URL, sourcePlatform: SourcePlatform): Place {
  const slug = url.pathname.split("/").filter(Boolean).pop() || "event";
  const eventName = titleize(slug.replace(/^e\//, ""));
  const city = inferCityFromName(eventName);
  const venueName = inferVenueNameFromSlug(slug) || `${eventName} Venue`;

  return buildPlace({
    name: venueName,
    address: city ? `${city} event` : "Imported event link",
    latitude: 37.7749,
    longitude: -122.4194,
    category: "attraction",
    sourcePlatform,
    sourceUrl: url.toString(),
    note: "Imported from an event link. Confirm the venue before driving there.",
    importKind: "event",
    eventLabel: eventName,
  });
}

function buildGenericPlace(url: URL): Place {
  const slug = url.pathname.split("/").filter(Boolean).pop() || url.hostname;
  const name = titleize(slug);

  return buildPlace({
    name,
    address: url.hostname,
    latitude: 37.7749,
    longitude: -122.4194,
    category: inferCategory(name),
    sourcePlatform: "other",
    sourceUrl: url.toString(),
    note: "Draft imported from a shared link. Confirm the real place before planning a route.",
    importKind: "draft",
  });
}

function buildSocialPlace(url: URL, sourcePlatform: SourcePlatform): Place {
  const slug = url.pathname.split("/").filter(Boolean).pop() || sourcePlatform;
  const name = titleize(slug);

  return buildPlace({
    name: cleanName(name),
    address: sourcePlatformLabel(sourcePlatform),
    latitude: 37.7749,
    longitude: -122.4194,
    category: inferCategory(name),
    sourcePlatform,
    sourceUrl: url.toString(),
    note: `Draft imported from ${sourcePlatformLabel(sourcePlatform)}. Confirm the real place before planning a route.`,
    importKind: "draft",
  });
}

function buildPlace(place: Omit<Place, "id" | "status" | "time" | "priceRange"> & Partial<Pick<Place, "time" | "priceRange">>): Place {
  return {
    id: buildId(place.name),
    status: "wantToGo",
    time: undefined,
    priceRange: undefined,
    ...place,
  };
}

function buildId(name: string): string {
  const base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `${base || "imported-place"}-${Date.now()}`;
}

function extractCoordinates(url: URL): [number, number] {
  const full = `${url.pathname}${url.search}${url.hash}`;
  const match = full.match(coordinatePattern);
  if (match) return [Number(match[1]), Number(match[2])];

  const ll = url.searchParams.get("ll");
  if (ll) {
    const [lat, lng] = ll.split(",").map(Number);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return [lat, lng];
  }

  return [37.7749, -122.4194];
}

function extractPlaceSegment(pathname: string): string | null {
  const segments = pathname.split("/").filter(Boolean);
  const placeIndex = segments.findIndex((segment) => segment === "place");
  if (placeIndex >= 0 && segments[placeIndex + 1]) return segments[placeIndex + 1];
  return segments.at(-1) || null;
}

function extractAddressCandidate(url: URL): string | null {
  const q = url.searchParams.get("q") || url.searchParams.get("query");
  if (!q) return null;
  if (/^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/.test(q)) return null;
  return q;
}

function decodeSegment(value: string): string {
  return decodeURIComponent(value.replace(/\+/g, " "));
}

function cleanName(value: string): string {
  return value
    .replace(/ - Google Maps$/i, "")
    .replace(/\| Google Maps$/i, "")
    .replace(/ - Apple Maps$/i, "")
    .trim();
}

function inferCategory(content: string): PlaceCategory {
  const lower = content.toLowerCase();
  if (/(cafe|coffee|bakery|tea|boba)/.test(lower)) return "cafe";
  if (/(bar|cocktail|wine|brew)/.test(lower)) return "bar";
  if (/(hotel|stay|resort)/.test(lower)) return "stay";
  if (/(shop|store|market)/.test(lower)) return "shopping";
  if (/(museum|park|event|gallery|festival|summit|conference)/.test(lower)) return "attraction";
  return "food";
}

function titleize(input: string): string {
  return input
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function inferCityFromName(name: string): string | null {
  if (/miami/i.test(name)) return "Miami";
  if (/san francisco|sf/i.test(name)) return "San Francisco";
  if (/new york|nyc/i.test(name)) return "New York";
  return null;
}

function inferVenueNameFromSlug(slug: string): string | null {
  const normalized = slug.toLowerCase();
  if (normalized.includes("-at-")) {
    const venuePart = normalized.split("-at-").pop();
    if (venuePart) return titleize(venuePart);
  }

  const conventionMatch = normalized.match(/(.*convention.*|.*hotel.*|.*club.*|.*center.*|.*hall.*)$/);
  if (conventionMatch?.[1]) return titleize(conventionMatch[1]);

  return null;
}

function sourcePlatformLabel(platform: SourcePlatform): string {
  switch (platform) {
    case "instagram":
      return "Instagram";
    case "threads":
      return "Threads";
    case "xiaohongshu":
      return "Xiaohongshu";
    default:
      return "Shared link";
  }
}
