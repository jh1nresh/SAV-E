export class TrekKmlExportError extends Error {}

export interface TrekKmlPlaceRow {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  category: string;
  status: string;
}

export const trekKmlPlacesSql = `
  select id, name, address, latitude, longitude, category, status
  from places
  where user_id = $1
    and id = any($2::uuid[])
  order by array_position($2::uuid[], id)
`;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const maxExportTextBytes = 256 * 1024;
const maxPlaceTextBytes = {
  id: 64,
  name: 512,
  address: 4096,
  category: 128,
  status: 128,
} as const;

export function normalizeTrekKmlExportRequest(body: unknown): string[] {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new TrekKmlExportError("place_ids must be an array of UUIDs");
  }

  const placeIds = (body as { place_ids?: unknown }).place_ids;
  if (!Array.isArray(placeIds)) {
    throw new TrekKmlExportError("place_ids must be an array of UUIDs");
  }
  if (placeIds.length < 1 || placeIds.length > 100) {
    throw new TrekKmlExportError("place_ids must contain between 1 and 100 UUIDs");
  }

  const normalized = placeIds.map((placeId) => {
    if (typeof placeId !== "string" || !uuidPattern.test(placeId.trim())) {
      throw new TrekKmlExportError("place_ids contains an invalid UUID");
    }
    return placeId.trim().toLowerCase();
  });

  if (new Set(normalized).size !== normalized.length) {
    throw new TrekKmlExportError("place_ids must not contain duplicates");
  }
  return normalized;
}

export function buildTrekKml(places: TrekKmlPlaceRow[]): string {
  if (places.length === 0) throw new TrekKmlExportError("at least one place is required");

  let totalTextBytes = 0;
  const normalizedPlaces = places.map((place) => {
    const name = requiredText(place.name, "place name");
    const id = requiredText(place.id, "place id");
    const address = optionalText(place.address);
    const category = optionalText(place.category);
    const status = optionalText(place.status);
    assertTextWithinLimit(id, "place id", maxPlaceTextBytes.id);
    assertTextWithinLimit(name, "place name", maxPlaceTextBytes.name);
    assertTextWithinLimit(address, "place address", maxPlaceTextBytes.address);
    assertTextWithinLimit(category, "place category", maxPlaceTextBytes.category);
    assertTextWithinLimit(status, "place status", maxPlaceTextBytes.status);

    totalTextBytes += [id, name, address, category, status]
      .reduce((sum, value) => sum + (value ? Buffer.byteLength(value, "utf8") : 0), 0);
    if (totalTextBytes > maxExportTextBytes) {
      throw new TrekKmlExportError(`export text exceeds ${maxExportTextBytes} bytes`);
    }

    const latitude = Number(place.latitude);
    const longitude = Number(place.longitude);
    if (!Number.isFinite(latitude)
      || !Number.isFinite(longitude)
      || latitude < -90
      || latitude > 90
      || longitude < -180
      || longitude > 180
      || (latitude === 0 && longitude === 0)
    ) {
      throw new TrekKmlExportError(`place ${id} has invalid coordinates`);
    }

    return { id, name, address, category, status, latitude, longitude };
  });

  const placemarks = normalizedPlaces.map((place) => {
    const description = [
      place.address ? `Address: ${place.address}` : undefined,
      place.category ? `Category: ${place.category}` : undefined,
      place.status ? `Status: ${place.status}` : undefined,
      `SAV-E place ID: ${place.id}`,
    ].filter((line): line is string => Boolean(line)).join("\n");

    return [
      "      <Placemark>",
      `        <name>${escapeXml(place.name)}</name>`,
      `        <description>${escapeXml(description)}</description>`,
      "        <Point>",
      `          <coordinates>${place.longitude},${place.latitude},0</coordinates>`,
      "        </Point>",
      "      </Placemark>",
    ].join("\n");
  }).join("\n");

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<kml xmlns="http://www.opengis.net/kml/2.2">',
    "  <Document>",
    "    <name>SAV-E Map Stamps</name>",
    "    <Folder>",
    "      <name>SAV-E Map Stamps</name>",
    placemarks,
    "    </Folder>",
    "  </Document>",
    "</kml>",
    "",
  ].join("\n");
}

export function trekKmlResponseHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Expose-Headers": "Content-Disposition",
    "Cache-Control": "private, no-store",
    "Content-Disposition": 'attachment; filename="save-map-stamps.kml"',
    "Content-Type": "application/vnd.google-earth.kml+xml; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  };
}

function requiredText(value: unknown, field: string): string {
  const text = optionalText(value);
  if (!text) throw new TrekKmlExportError(`${field} is required`);
  return text;
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function assertTextWithinLimit(value: string | undefined, field: string, maxBytes: number): void {
  if (value && Buffer.byteLength(value, "utf8") > maxBytes) {
    throw new TrekKmlExportError(`${field} exceeds ${maxBytes} bytes`);
  }
}

function escapeXml(value: string): string {
  const validXmlText = [...value].filter((character) => {
    const codePoint = character.codePointAt(0) as number;
    return codePoint === 0x9
      || codePoint === 0xa
      || codePoint === 0xd
      || (codePoint >= 0x20 && codePoint <= 0xd7ff)
      || (codePoint >= 0xe000 && codePoint <= 0xfffd)
      || (codePoint >= 0x10000 && codePoint <= 0x10ffff);
  }).join("");

  return validXmlText
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
