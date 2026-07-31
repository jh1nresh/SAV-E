export const maxTrekPlanningMapStamps = 100;
export const trekPlanningOAuthScopes = ["trips:write", "places:write"] as const;
export const trekPlanningShareOAuthScope = "trips:share" as const;

export type TrekPlanningShareMode = "private" | "map_only";

export type TrekPlanningToolName =
  | "create_trip"
  | "get_trip_summary"
  | "create_and_assign_place"
  | "update_assignment_time"
  | "reorder_day_assignments"
  | "create_share_link";

export type TrekPlanningFailedAt = "validate" | TrekPlanningToolName;

export type TrekPlanningErrorCode =
  | "INVALID_REQUEST"
  | "TREK_UNAUTHORIZED"
  | "TREK_FORBIDDEN"
  | "TREK_RATE_LIMITED"
  | "TREK_UNAVAILABLE"
  | "TREK_TOOL_REJECTED"
  | "TREK_RESPONSE_INVALID"
  | "TREK_EXECUTION_FAILED";

export interface TrekMcpToolTransport {
  callTool(params: {
    name: TrekPlanningToolName;
    arguments: Record<string, unknown>;
  }): Promise<unknown>;
}

export interface TrekConfirmedMapStampInput {
  localPlaceId: string;
  confirmationState: "confirmed_map_stamp";
  name: string;
  address?: string | null;
  latitude: number;
  longitude: number;
  day: number;
  orderIndex: number;
  startTime?: string | null;
  endTime?: string | null;
}

export interface TrekPlanningRequest {
  requestId: string;
  localTripId: string;
  title: string;
  startDate?: string | null;
  endDate?: string | null;
  currency?: string | null;
  shareMode: TrekPlanningShareMode;
  mapStamps: readonly TrekConfirmedMapStampInput[];
}

export interface TrekPlanningReceipt {
  requestId: string;
  localTripId: string;
  status: "completed" | "failed";
  remoteTripId: number | null;
  importedMapStampCount: number;
  shareCreated: boolean;
  mapStampMappings: readonly TrekMapStampMapping[];
  completedTools: readonly TrekPlanningToolName[];
  retryPolicy: "manual_only";
  failedAt?: TrekPlanningFailedAt;
  errorCode?: TrekPlanningErrorCode;
}

export interface TrekMapStampMapping {
  localPlaceId: string;
  remotePlaceId: number;
  remoteAssignmentId: number;
  remoteDayId: number;
}

export class TrekPlanningTransportError extends Error {
  constructor(
    public readonly code: Exclude<TrekPlanningErrorCode, "INVALID_REQUEST" | "TREK_RESPONSE_INVALID">,
  ) {
    super(code);
    this.name = "TrekPlanningTransportError";
  }
}

class TrekPlanningInputError extends Error {}
class TrekPlanningResponseError extends Error {}

interface NormalizedTrekPlanningRequest extends Omit<TrekPlanningRequest, "mapStamps" | "currency"> {
  currency?: string;
  mapStamps: TrekConfirmedMapStampInput[];
}

interface TrekDayReference {
  id: number;
  dayNumber: number;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const isoDatePattern = /^\d{4}-\d{2}-\d{2}$/;
const clockTimePattern = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const millisecondsPerDay = 86_400_000;
const defaultTrekTripDays = 7;
const maxTrekTripDays = 90;

const requestFields = new Set([
  "requestId",
  "localTripId",
  "title",
  "startDate",
  "endDate",
  "currency",
  "shareMode",
  "mapStamps",
]);

const mapStampFields = new Set([
  "localPlaceId",
  "confirmationState",
  "name",
  "address",
  "latitude",
  "longitude",
  "day",
  "orderIndex",
  "startTime",
  "endTime",
]);

export class TrekPlanningAdapter {
  constructor(private readonly transport: TrekMcpToolTransport) {}

  async execute(input: TrekPlanningRequest): Promise<TrekPlanningReceipt> {
    let requestId = safeReceiptId(input, "requestId");
    let localTripId = safeReceiptId(input, "localTripId");
    let remoteTripId: number | null = null;
    let importedMapStampCount = 0;
    let shareCreated = false;
    let failedAt: TrekPlanningFailedAt = "validate";
    const mapStampMappings: TrekMapStampMapping[] = [];
    const completedTools: TrekPlanningToolName[] = [];

    try {
      const request = normalizeRequest(input);
      requestId = request.requestId;
      localTripId = request.localTripId;

      failedAt = "create_trip";
      const createdTrip = await this.callTool("create_trip", createTripArguments(request), completedTools);
      remoteTripId = positiveIntegerAt(createdTrip, ["trip", "id"]);

      failedAt = "get_trip_summary";
      const initialSummary = await this.callTool(
        "get_trip_summary",
        { tripId: remoteTripId },
        completedTools,
      );
      const days = parseDays(initialSummary);
      const dayIdByNumber = new Map(days.map((day) => [day.dayNumber, day.id]));
      const assignmentsByDayId = new Map<number, number[]>();

      for (const mapStamp of request.mapStamps) {
        const dayId = dayIdByNumber.get(mapStamp.day);
        if (!dayId) throw new TrekPlanningResponseError("TREK day mapping is incomplete");

        failedAt = "create_and_assign_place";
        const created = await this.callTool(
          "create_and_assign_place",
          createPlaceArguments(remoteTripId, dayId, mapStamp),
          completedTools,
        );
        const mapping: TrekMapStampMapping = {
          localPlaceId: mapStamp.localPlaceId,
          remotePlaceId: positiveIntegerAt(created, ["place", "id"]),
          remoteAssignmentId: positiveIntegerAt(created, ["assignment", "id"]),
          remoteDayId: dayId,
        };
        mapStampMappings.push(mapping);
        importedMapStampCount += 1;
        assignmentsByDayId.set(dayId, [
          ...(assignmentsByDayId.get(dayId) ?? []),
          mapping.remoteAssignmentId,
        ]);

        if (mapStamp.startTime !== undefined || mapStamp.endTime !== undefined) {
          failedAt = "update_assignment_time";
          await this.callTool(
            "update_assignment_time",
            assignmentTimeArguments(remoteTripId, mapping.remoteAssignmentId, mapStamp),
            completedTools,
          );
        }
      }

      for (const [dayId, assignmentIds] of assignmentsByDayId) {
        if (assignmentIds.length < 2) continue;
        failedAt = "reorder_day_assignments";
        await this.callTool(
          "reorder_day_assignments",
          { tripId: remoteTripId, dayId, assignmentIds },
          completedTools,
        );
      }

      if (request.shareMode === "map_only") {
        failedAt = "create_share_link";
        const shareResult = await this.callTool(
          "create_share_link",
          {
            tripId: remoteTripId,
            share_map: true,
            share_bookings: false,
            share_packing: false,
            share_budget: false,
            share_collab: false,
          },
          completedTools,
        );
        nonEmptyStringAt(shareResult, ["token"]);
        shareCreated = true;
      }

      failedAt = "get_trip_summary";
      const finalSummary = await this.callTool(
        "get_trip_summary",
        { tripId: remoteTripId },
        completedTools,
      );
      verifyFinalSummary(finalSummary, remoteTripId, request.mapStamps.length);

      return {
        requestId,
        localTripId,
        status: "completed",
        remoteTripId,
        importedMapStampCount,
        shareCreated,
        mapStampMappings,
        completedTools,
        retryPolicy: "manual_only",
      };
    } catch (error) {
      return {
        requestId,
        localTripId,
        status: "failed",
        remoteTripId,
        importedMapStampCount,
        shareCreated,
        mapStampMappings,
        completedTools,
        retryPolicy: "manual_only",
        failedAt,
        errorCode: planningErrorCode(error),
      };
    }
  }

  private async callTool(
    name: TrekPlanningToolName,
    args: Record<string, unknown>,
    completedTools: TrekPlanningToolName[],
  ): Promise<Record<string, unknown>> {
    const rawResult = await this.transport.callTool({ name, arguments: args });
    const decoded = decodeTrekMcpToolResult(rawResult);
    completedTools.push(name);
    return decoded;
  }
}

export function decodeTrekMcpToolResult(result: unknown): Record<string, unknown> {
  if (!isRecord(result)) throw new TrekPlanningResponseError("MCP result must be an object");
  if (result.isError === true) throw new TrekPlanningTransportError("TREK_TOOL_REJECTED");

  if (isRecord(result.structuredContent)) return result.structuredContent;
  if (!Array.isArray(result.content)) throw new TrekPlanningResponseError("MCP result has no content");

  for (let index = result.content.length - 1; index >= 0; index -= 1) {
    const item = result.content[index];
    if (!isRecord(item) || item.type !== "text" || typeof item.text !== "string") continue;
    try {
      const parsed: unknown = JSON.parse(item.text);
      if (isRecord(parsed)) return parsed;
    } catch {
      // TREK may include a human-readable notice before its JSON payload.
    }
  }

  throw new TrekPlanningResponseError("MCP result has no JSON object payload");
}

function normalizeRequest(input: TrekPlanningRequest): NormalizedTrekPlanningRequest {
  if (!isRecord(input)) throw new TrekPlanningInputError("request must be an object");
  assertNoUnexpectedFields(input, requestFields, "request");

  const requestId = requiredUuid(input.requestId, "requestId");
  const localTripId = requiredUuid(input.localTripId, "localTripId");
  const title = boundedText(input.title, "title", 200);
  const startDate = optionalDate(input.startDate, "startDate");
  const endDate = optionalDate(input.endDate, "endDate");
  if ((startDate === null) !== (endDate === null)) {
    throw new TrekPlanningInputError("startDate and endDate must be provided together");
  }
  if (startDate && endDate && endDate < startDate) {
    throw new TrekPlanningInputError("endDate must be on or after startDate");
  }

  const currency = optionalCurrency(input.currency);
  if (input.shareMode !== "private" && input.shareMode !== "map_only") {
    throw new TrekPlanningInputError("shareMode must be private or map_only");
  }
  if (!Array.isArray(input.mapStamps) || input.mapStamps.length === 0) {
    throw new TrekPlanningInputError("mapStamps must contain at least one confirmed Map Stamp");
  }
  if (input.mapStamps.length > maxTrekPlanningMapStamps) {
    throw new TrekPlanningInputError(`mapStamps must contain at most ${maxTrekPlanningMapStamps} items`);
  }

  const mapStamps = input.mapStamps.map((mapStamp, index) => normalizeMapStamp(mapStamp, index));
  const localPlaceIds = mapStamps.map((mapStamp) => mapStamp.localPlaceId);
  if (new Set(localPlaceIds).size !== localPlaceIds.length) {
    throw new TrekPlanningInputError("mapStamps must not contain duplicate localPlaceId values");
  }
  const positions = mapStamps.map((mapStamp) => `${mapStamp.day}:${mapStamp.orderIndex}`);
  if (new Set(positions).size !== positions.length) {
    throw new TrekPlanningInputError("mapStamps must not contain duplicate day/order positions");
  }

  const tripDayCount = expectedTripDayCount(startDate, endDate);
  if (mapStamps.some((mapStamp) => mapStamp.day > tripDayCount)) {
    throw new TrekPlanningInputError("mapStamps contains a day outside the TREK trip window");
  }

  mapStamps.sort((left, right) => left.day - right.day || left.orderIndex - right.orderIndex);
  return {
    requestId,
    localTripId,
    title,
    startDate,
    endDate,
    currency,
    shareMode: input.shareMode,
    mapStamps,
  };
}

function normalizeMapStamp(value: unknown, index: number): TrekConfirmedMapStampInput {
  if (!isRecord(value)) throw new TrekPlanningInputError(`mapStamps[${index}] must be an object`);
  assertNoUnexpectedFields(value, mapStampFields, `mapStamps[${index}]`);
  if (value.confirmationState !== "confirmed_map_stamp") {
    throw new TrekPlanningInputError(`mapStamps[${index}] is not confirmed`);
  }

  const address = optionalBoundedText(value.address, `mapStamps[${index}].address`, 500);
  return {
    localPlaceId: requiredUuid(value.localPlaceId, `mapStamps[${index}].localPlaceId`),
    confirmationState: "confirmed_map_stamp",
    name: boundedText(value.name, `mapStamps[${index}].name`, 200),
    address,
    latitude: boundedNumber(value.latitude, `mapStamps[${index}].latitude`, -90, 90),
    longitude: boundedNumber(value.longitude, `mapStamps[${index}].longitude`, -180, 180),
    day: boundedInteger(value.day, `mapStamps[${index}].day`, 1, maxTrekTripDays),
    orderIndex: boundedInteger(value.orderIndex, `mapStamps[${index}].orderIndex`, 0, maxTrekPlanningMapStamps - 1),
    startTime: optionalClockTime(value.startTime, `mapStamps[${index}].startTime`),
    endTime: optionalClockTime(value.endTime, `mapStamps[${index}].endTime`),
  };
}

function createTripArguments(request: NormalizedTrekPlanningRequest): Record<string, unknown> {
  return compactObject({
    title: request.title,
    start_date: request.startDate ?? undefined,
    end_date: request.endDate ?? undefined,
    currency: request.currency,
  });
}

function createPlaceArguments(
  tripId: number,
  dayId: number,
  mapStamp: TrekConfirmedMapStampInput,
): Record<string, unknown> {
  return compactObject({
    tripId,
    dayId,
    name: mapStamp.name,
    lat: mapStamp.latitude,
    lng: mapStamp.longitude,
    address: mapStamp.address || undefined,
  });
}

function assignmentTimeArguments(
  tripId: number,
  assignmentId: number,
  mapStamp: TrekConfirmedMapStampInput,
): Record<string, unknown> {
  return compactObject({
    tripId,
    assignmentId,
    place_time: mapStamp.startTime,
    end_time: mapStamp.endTime,
  });
}

function parseDays(summary: Record<string, unknown>): TrekDayReference[] {
  if (!Array.isArray(summary.days) || summary.days.length === 0) {
    throw new TrekPlanningResponseError("TREK summary has no days");
  }
  const days = summary.days.map((value, index) => {
    if (!isRecord(value)) throw new TrekPlanningResponseError(`TREK day ${index} is invalid`);
    return {
      id: positiveIntegerAt(value, ["id"]),
      dayNumber: positiveIntegerAt(value, ["day_number"]),
    };
  });
  if (new Set(days.map((day) => day.dayNumber)).size !== days.length) {
    throw new TrekPlanningResponseError("TREK summary has duplicate day numbers");
  }
  return days;
}

function verifyFinalSummary(
  summary: Record<string, unknown>,
  remoteTripId: number,
  expectedAssignments: number,
): void {
  if (positiveIntegerAt(summary, ["trip", "id"]) !== remoteTripId) {
    throw new TrekPlanningResponseError("TREK summary trip does not match");
  }
  const days = summary.days;
  if (!Array.isArray(days)) throw new TrekPlanningResponseError("TREK summary has no days");
  const assignmentCount = days.reduce((count, day) => {
    if (!isRecord(day) || !Array.isArray(day.assignments)) {
      throw new TrekPlanningResponseError("TREK summary has invalid assignments");
    }
    return count + day.assignments.length;
  }, 0);
  if (assignmentCount < expectedAssignments) {
    throw new TrekPlanningResponseError("TREK summary is missing imported assignments");
  }
}

function expectedTripDayCount(startDate: string | null, endDate: string | null): number {
  if (!startDate || !endDate) return defaultTrekTripDays;
  const start = Date.parse(`${startDate}T00:00:00Z`);
  const end = Date.parse(`${endDate}T00:00:00Z`);
  return Math.min(Math.floor((end - start) / millisecondsPerDay) + 1, maxTrekTripDays);
}

function positiveIntegerAt(value: unknown, path: readonly string[]): number {
  let current = value;
  for (const key of path) {
    if (!isRecord(current)) throw new TrekPlanningResponseError(`TREK response is missing ${path.join(".")}`);
    current = current[key];
  }
  if (!Number.isInteger(current) || (current as number) <= 0) {
    throw new TrekPlanningResponseError(`TREK response has invalid ${path.join(".")}`);
  }
  return current as number;
}

function nonEmptyStringAt(value: unknown, path: readonly string[]): string {
  let current = value;
  for (const key of path) {
    if (!isRecord(current)) throw new TrekPlanningResponseError(`TREK response is missing ${path.join(".")}`);
    current = current[key];
  }
  if (typeof current !== "string" || current.trim().length === 0) {
    throw new TrekPlanningResponseError(`TREK response has invalid ${path.join(".")}`);
  }
  return current;
}

function requiredUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !uuidPattern.test(value.trim())) {
    throw new TrekPlanningInputError(`${field} must be a UUID`);
  }
  return value.trim().toLowerCase();
}

function boundedText(value: unknown, field: string, maxBytes: number): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new TrekPlanningInputError(`${field} must be a non-empty string`);
  }
  const normalized = value.trim();
  if (Buffer.byteLength(normalized, "utf8") > maxBytes) {
    throw new TrekPlanningInputError(`${field} exceeds ${maxBytes} bytes`);
  }
  return normalized;
}

function optionalBoundedText(value: unknown, field: string, maxBytes: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new TrekPlanningInputError(`${field} must be a string or null`);
  const normalized = value.trim();
  if (Buffer.byteLength(normalized, "utf8") > maxBytes) {
    throw new TrekPlanningInputError(`${field} exceeds ${maxBytes} bytes`);
  }
  return normalized || null;
}

function optionalDate(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !isoDatePattern.test(value)) {
    throw new TrekPlanningInputError(`${field} must be an ISO date`);
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new TrekPlanningInputError(`${field} must be a valid calendar date`);
  }
  return value;
}

function optionalCurrency(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string" || !/^[A-Za-z]{3}$/.test(value.trim())) {
    throw new TrekPlanningInputError("currency must be a three-letter code");
  }
  return value.trim().toUpperCase();
}

function optionalClockTime(value: unknown, field: string): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string" || !clockTimePattern.test(value)) {
    throw new TrekPlanningInputError(`${field} must use HH:mm or null`);
  }
  return value;
}

function boundedNumber(value: unknown, field: string, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new TrekPlanningInputError(`${field} must be between ${minimum} and ${maximum}`);
  }
  return value;
}

function boundedInteger(value: unknown, field: string, minimum: number, maximum: number): number {
  if (!Number.isInteger(value) || (value as number) < minimum || (value as number) > maximum) {
    throw new TrekPlanningInputError(`${field} must be an integer between ${minimum} and ${maximum}`);
  }
  return value as number;
}

function assertNoUnexpectedFields(value: Record<string, unknown>, allowed: ReadonlySet<string>, field: string): void {
  const unexpected = Object.keys(value).filter((key) => !allowed.has(key));
  if (unexpected.length > 0) {
    throw new TrekPlanningInputError(`${field} contains unexpected fields`);
  }
}

function compactObject(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function planningErrorCode(error: unknown): TrekPlanningErrorCode {
  if (error instanceof TrekPlanningInputError) return "INVALID_REQUEST";
  if (error instanceof TrekPlanningResponseError) return "TREK_RESPONSE_INVALID";
  if (error instanceof TrekPlanningTransportError) return error.code;
  return "TREK_EXECUTION_FAILED";
}

function safeReceiptId(input: unknown, key: "requestId" | "localTripId"): string {
  if (!isRecord(input) || typeof input[key] !== "string" || !uuidPattern.test(input[key].trim())) {
    return "invalid";
  }
  return input[key].trim().toLowerCase();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
