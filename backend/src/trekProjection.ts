import type {
  TrekConfirmedMapStampInput,
  TrekPlanningRequest,
  TrekPlanningShareMode,
} from "./trekPlanningAdapter.js";
import { maxTrekPlanningMapStamps } from "./trekPlanningAdapter.js";

export class TrekProjectionError extends Error {}

/**
 * A trip stop joined to its confirmed place. Only stops whose place is a
 * confirmed Map Stamp with real coordinates can be projected — a clue without a
 * verified place has nothing to create in TREK.
 */
export interface TrekProjectionStopRow {
  place_id: string;
  place_name: string;
  day: number;
  order_index: number;
  start_time: string | null;
  duration: number | null;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  status: string | null;
}

export interface TrekProjectionTripRow {
  id: string;
  name: string;
  start_date: string | null;
  end_date: string | null;
}

/** Stops for a trip, joined to places, ordered the way the user arranged them. */
export const trekProjectionStopsSql = `
  select
    ts.place_id::text as place_id,
    ts.place_name,
    ts.day,
    ts.order_index,
    ts.start_time,
    ts.duration,
    p.address,
    p.latitude,
    p.longitude,
    p.status
  from trip_stops ts
  join places p on p.id = ts.place_id and p.user_id = $2
  where ts.trip_id = $1
  order by ts.day, ts.order_index
`;

export const trekProjectionTripSql = `
  select id::text as id, name, start_date, end_date
  from trips
  where id = $1 and user_id = $2
`;

const clockTimePattern = /^(?:[01]\d|2[0-3]):[0-5]\d/;
const shareModes = new Set<TrekPlanningShareMode>(["private", "map_only"]);

export function normalizeTrekProjectionRequestBody(body: unknown): {
  requestId: string;
  shareMode: TrekPlanningShareMode;
} {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new TrekProjectionError("TREK projection body must be an object");
  }
  const record = body as Record<string, unknown>;

  const requestId = record.requestId;
  if (typeof requestId !== "string" || requestId.trim().length === 0) {
    throw new TrekProjectionError("TREK projection requires a requestId");
  }

  // Default to the least-sharing option: a projection should never create a
  // public link unless the user explicitly asked for one.
  const rawShareMode = record.shareMode ?? "private";
  if (typeof rawShareMode !== "string" || !shareModes.has(rawShareMode as TrekPlanningShareMode)) {
    throw new TrekProjectionError("TREK projection shareMode must be private or map_only");
  }

  return { requestId: requestId.trim(), shareMode: rawShareMode as TrekPlanningShareMode };
}

/**
 * Builds the adapter request from stored rows, dropping stops that cannot be
 * projected. Returns the dropped count so the receipt can tell the user that
 * their trip landed in TREK minus the unconfirmed stops, rather than silently
 * projecting a shorter trip.
 */
export function buildTrekPlanningRequest(params: {
  requestId: string;
  shareMode: TrekPlanningShareMode;
  trip: TrekProjectionTripRow;
  stops: readonly TrekProjectionStopRow[];
}): { request: TrekPlanningRequest; skippedStopCount: number } {
  const projectable = params.stops.filter(isProjectable);
  const skippedStopCount = params.stops.length - projectable.length;

  if (projectable.length === 0) {
    throw new TrekProjectionError("This trip has no confirmed Map Stamps to project");
  }
  if (projectable.length > maxTrekPlanningMapStamps) {
    throw new TrekProjectionError(
      `TREK projection supports at most ${maxTrekPlanningMapStamps} Map Stamps`,
    );
  }

  const mapStamps: TrekConfirmedMapStampInput[] = projectable.map((stop) => ({
    localPlaceId: stop.place_id,
    confirmationState: "confirmed_map_stamp",
    name: stop.place_name,
    address: stop.address ?? null,
    latitude: stop.latitude as number,
    longitude: stop.longitude as number,
    day: stop.day,
    orderIndex: stop.order_index,
    startTime: normalizeClockTime(stop.start_time),
    endTime: null,
  }));

  return {
    request: {
      requestId: params.requestId,
      localTripId: params.trip.id,
      title: params.trip.name,
      startDate: normalizeIsoDate(params.trip.start_date),
      endDate: normalizeIsoDate(params.trip.end_date),
      shareMode: params.shareMode,
      mapStamps,
    },
    skippedStopCount,
  };
}

/** Day count the stub transport should pre-create for the projected trip. */
export function projectedDayCount(request: TrekPlanningRequest): number {
  return request.mapStamps.reduce((max, stamp) => Math.max(max, stamp.day), 1);
}

function isProjectable(stop: TrekProjectionStopRow): boolean {
  if (stop.status !== "confirmed" && stop.status !== "visited") return false;
  if (typeof stop.latitude !== "number" || typeof stop.longitude !== "number") return false;
  // (0,0) is the pipeline's "no coordinates yet" sentinel, not the Gulf of Guinea.
  if (stop.latitude === 0 && stop.longitude === 0) return false;
  return stop.place_name.trim().length > 0;
}

function normalizeClockTime(value: string | null): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const match = clockTimePattern.exec(trimmed);
  return match ? match[0].slice(0, 5) : null;
}

function normalizeIsoDate(value: string | null): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^\d{4}-\d{2}-\d{2}/.test(trimmed) ? trimmed.slice(0, 10) : null;
}
