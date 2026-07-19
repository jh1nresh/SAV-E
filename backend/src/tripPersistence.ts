export class TripSnapshotInputError extends Error {}

export interface NormalizedTripStopSnapshot {
  id?: string;
  place_id: string;
  day: number;
  order_index: number;
  start_time: string | null;
  duration: number | null;
  note: string | null;
}

export interface CanonicalTripStopSnapshot extends NormalizedTripStopSnapshot {
  place_name: string;
}

export interface OwnedTripPlaceRow {
  id: string;
  name: string;
}

export const maxTripStops = 100;
export const ownedTripForUpdateSql = `
  select id
  from trips
  where id = $1 and user_id = $2
  for update
`;
export const ownedTripPlacesSql = `
  select id, name
  from places
  where user_id = $1
    and id = any($2::uuid[])
  for key share
`;
export const deleteTripStopsSql = "delete from trip_stops where trip_id = $1";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedStopFields = new Set([
  "id",
  "trip_id",
  "place_id",
  "place_name",
  "day",
  "order_index",
  "start_time",
  "duration",
  "note",
]);

export function normalizeTripStopSnapshot(body: unknown): NormalizedTripStopSnapshot[] {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new TripSnapshotInputError("trip_stops must be an array");
  }

  const stops = (body as { trip_stops?: unknown }).trip_stops;
  if (!Array.isArray(stops)) {
    throw new TripSnapshotInputError("trip_stops must be an array");
  }
  if (stops.length > maxTripStops) {
    throw new TripSnapshotInputError(`trip_stops must contain at most ${maxTripStops} stops`);
  }

  const normalized = stops.map((value, index) => normalizeTripStop(value, index));
  const stopIds = normalized.flatMap((stop) => stop.id ? [stop.id] : []);
  if (new Set(stopIds).size !== stopIds.length) {
    throw new TripSnapshotInputError("trip_stops must not contain duplicate stop ids");
  }

  const positions = normalized.map((stop) => `${stop.day}:${stop.order_index}`);
  if (new Set(positions).size !== positions.length) {
    throw new TripSnapshotInputError("trip_stops must not contain duplicate day/order positions");
  }
  return normalized;
}

export function validateTripMetadataSnapshot(body: unknown, requireName: boolean): void {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new TripSnapshotInputError("trip must be an object");
  }
  const trip = body as Record<string, unknown>;
  if (requireName || trip.name !== undefined) {
    const name = requiredBoundedText(trip.name, "name", 256);
    if (name.trim().length === 0) throw new TripSnapshotInputError("name must not be empty");
  }
  if (trip.city !== undefined && trip.city !== null) {
    requiredBoundedText(trip.city, "city", 256);
  }
  if (trip.is_optimized !== undefined && typeof trip.is_optimized !== "boolean") {
    throw new TripSnapshotInputError("is_optimized must be a boolean");
  }

  const startDate = optionalISODate(trip.start_date, "start_date");
  const endDate = optionalISODate(trip.end_date, "end_date");
  if (startDate && endDate && endDate < startDate) {
    throw new TripSnapshotInputError("end_date must be on or after start_date");
  }
}

export function canonicalizeOwnedTripStops(
  stops: NormalizedTripStopSnapshot[],
  ownedPlaces: OwnedTripPlaceRow[],
): CanonicalTripStopSnapshot[] {
  const nameById = new Map(ownedPlaces.map((place) => [place.id.toLowerCase(), place.name]));
  const canonical = stops.map((stop) => {
    const placeName = nameById.get(stop.place_id);
    if (placeName === undefined) {
      throw new TripSnapshotInputError("trip_stops contains a place that is not owned by the user");
    }
    return { ...stop, place_name: placeName };
  });
  return canonical;
}

function normalizeTripStop(value: unknown, index: number): NormalizedTripStopSnapshot {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TripSnapshotInputError(`trip_stops[${index}] must be an object`);
  }

  const stop = value as Record<string, unknown>;
  const unexpected = Object.keys(stop).filter((field) => !allowedStopFields.has(field));
  if (unexpected.length > 0) {
    throw new TripSnapshotInputError(`trip_stops[${index}] contains unexpected fields`);
  }

  const id = optionalUuid(stop.id, `trip_stops[${index}].id`);
  const placeId = requiredUuid(stop.place_id, `trip_stops[${index}].place_id`);
  const day = boundedInteger(stop.day, `trip_stops[${index}].day`, 1, 365);
  const orderIndex = boundedInteger(stop.order_index, `trip_stops[${index}].order_index`, 0, maxTripStops - 1);
  const startTime = optionalBoundedText(stop.start_time, `trip_stops[${index}].start_time`, 64);
  const duration = optionalBoundedInteger(stop.duration, `trip_stops[${index}].duration`, 1, 1_440);
  const note = optionalBoundedText(stop.note, `trip_stops[${index}].note`, 4_096);

  return {
    id,
    place_id: placeId,
    day,
    order_index: orderIndex,
    start_time: startTime,
    duration,
    note,
  };
}

function requiredUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !uuidPattern.test(value.trim())) {
    throw new TripSnapshotInputError(`${field} must be a UUID`);
  }
  return value.trim().toLowerCase();
}

function optionalUuid(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requiredUuid(value, field);
}

function boundedInteger(value: unknown, field: string, minimum: number, maximum: number): number {
  if (!Number.isInteger(value) || (value as number) < minimum || (value as number) > maximum) {
    throw new TripSnapshotInputError(`${field} must be an integer between ${minimum} and ${maximum}`);
  }
  return value as number;
}

function optionalBoundedInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value === undefined || value === null) return null;
  return boundedInteger(value, field, minimum, maximum);
}

function optionalBoundedText(value: unknown, field: string, maxBytes: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new TripSnapshotInputError(`${field} must be a string or null`);
  }
  if (Buffer.byteLength(value, "utf8") > maxBytes) {
    throw new TripSnapshotInputError(`${field} exceeds ${maxBytes} bytes`);
  }
  return value;
}

function requiredBoundedText(value: unknown, field: string, maxBytes: number): string {
  if (typeof value !== "string") {
    throw new TripSnapshotInputError(`${field} must be a string`);
  }
  if (Buffer.byteLength(value, "utf8") > maxBytes) {
    throw new TripSnapshotInputError(`${field} exceeds ${maxBytes} bytes`);
  }
  return value;
}

function optionalISODate(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new TripSnapshotInputError(`${field} must be an ISO date`);
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new TripSnapshotInputError(`${field} must be a valid calendar date`);
  }
  return value;
}
