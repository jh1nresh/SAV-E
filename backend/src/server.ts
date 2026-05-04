import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { importSPKI, jwtVerify, type JWTPayload, type KeyLike } from "jose";
import pg from "pg";

type JsonBody = Record<string, unknown>;
type QueryValue = string | number | boolean | Date | string[] | null;

const { Pool } = pg;

const databaseUrl = requireEnv("DATABASE_URL");
const privyAppId = requireEnv("PRIVY_APP_ID");
const privyVerificationKey = requireEnv("PRIVY_VERIFICATION_KEY");

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: databaseUrl.includes("railway.internal")
    ? undefined
    : { rejectUnauthorized: false },
});

let verificationKeyPromise: Promise<KeyLike> | undefined;

const placeFields = [
  "id",
  "name",
  "address",
  "latitude",
  "longitude",
  "google_place_id",
  "category",
  "status",
  "rating",
  "note",
  "source_url",
  "source_platform",
  "source_image_url",
  "extracted_dishes",
  "price_range",
  "recommender",
  "google_rating",
  "google_price_level",
  "opening_hours",
  "created_at",
] as const;

const tripFields = [
  "id",
  "name",
  "city",
  "start_date",
  "end_date",
  "is_optimized",
  "created_at",
] as const;

const tripStopFields = [
  "id",
  "place_id",
  "place_name",
  "day",
  "order_index",
  "start_time",
  "duration",
  "note",
] as const;

const profileFields = ["display_name", "avatar_url"] as const;

createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    return sendJson(response, null, 204);
  }

  try {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (request.method === "GET" && url.pathname === "/") {
      return sendJson(response, { ok: true, service: "wanderly-backend" });
    }

    const userId = await resolveUserId(request);
    await ensureProfile(userId);

    const [resource, id] = url.pathname.split("/").filter(Boolean);

    if (resource === "places") return await handlePlaces(request, response, id, userId);
    if (resource === "trips") return await handleTrips(request, response, id, userId);
    if (resource === "profile") return await handleProfile(request, response, userId);

    return sendJson(response, { error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return sendJson(response, { error: message }, status);
  }
}).listen(Number(process.env.PORT ?? 3000), () => {
  console.log(`Wanderly backend listening on ${process.env.PORT ?? 3000}`);
});

async function handlePlaces(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !placeId) {
    const { rows } = await pool.query(
      "select * from places where user_id = $1 order by created_at desc",
      [userId],
    );
    return sendJson(response, rows.map(formatPlace));
  }

  if (request.method === "POST" && !placeId) {
    const body = withOwner(await readJson(request), userId);
    const insert = buildInsert("places", body, [...placeFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatPlace(rows[0]), 201);
  }

  if (request.method === "PATCH" && placeId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "created_at", "updated_at"]);
    const update = buildUpdate("places", body, placeFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, placeId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Place not found" }, 404);
    return sendJson(response, formatPlace(rows[0]));
  }

  if (request.method === "DELETE" && placeId) {
    const { rows } = await pool.query(
      "delete from places where id = $1 and user_id = $2 returning id",
      [placeId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Place not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported places route" }, 405);
}

async function handleTrips(
  request: IncomingMessage,
  response: ServerResponse,
  tripId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !tripId) {
    const { rows } = await pool.query(tripsSelect("where t.user_id = $1 order by t.created_at desc"), [userId]);
    return sendJson(response, rows.map(formatTrip));
  }

  if (request.method === "POST" && !tripId) {
    const body = await readJson(request);
    const stops = Array.isArray(body.trip_stops) ? body.trip_stops.map(asObject) : [];
    const tripBody = withOwner(writableFields(body, ["trip_stops"]), userId);
    const client = await pool.connect();

    try {
      await client.query("begin");
      const insert = buildInsert("trips", tripBody, [...tripFields, "user_id"]);
      const { rows: tripRows } = await client.query(`${insert.sql} returning *`, insert.values);
      const trip = tripRows[0] as { id: string };

      for (const stop of stops) {
        const stopBody = { ...writableFields(stop, ["trip_id", "created_at"]), trip_id: trip.id };
        const stopInsert = buildInsert("trip_stops", stopBody, [...tripStopFields, "trip_id"]);
        await client.query(stopInsert.sql, stopInsert.values);
      }

      const { rows } = await client.query(tripsSelect("where t.id = $1 and t.user_id = $2"), [trip.id, userId]);
      await client.query("commit");
      return sendJson(response, formatTrip(rows[0]), 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (request.method === "PATCH" && tripId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "trip_stops", "created_at", "updated_at"]);
    const update = buildUpdate("trips", body, tripFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, tripId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning id`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Trip not found" }, 404);

    const { rows: trips } = await pool.query(tripsSelect("where t.id = $1 and t.user_id = $2"), [tripId, userId]);
    return sendJson(response, formatTrip(trips[0]));
  }

  if (request.method === "DELETE" && tripId) {
    const { rows } = await pool.query(
      "delete from trips where id = $1 and user_id = $2 returning id",
      [tripId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Trip not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported trips route" }, 405);
}

async function handleProfile(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const { rows } = await pool.query(
      `select
        p.*,
        (select count(*)::int from places where user_id = p.id) as saved_count,
        (select count(*)::int from places where user_id = p.id and status = 'visited') as visited_count,
        (select count(distinct city)::int from trips where user_id = p.id and city <> '') as cities_count
      from profiles p
      where p.id = $1`,
      [userId],
    );
    return sendJson(response, formatProfile(rows[0]));
  }

  if (request.method === "PATCH") {
    const body = pickFields(await readJson(request), profileFields);
    const update = buildUpdate("profiles", body, profileFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, userId];
    const { rows } = await pool.query(`${update.sql} where id = $${values.length} returning *`, values);
    return sendJson(response, formatProfile(rows[0]));
  }

  return sendJson(response, { error: "Unsupported profile route" }, 405);
}

async function ensureProfile(userId: string): Promise<void> {
  await pool.query(
    `insert into profiles (id, display_name)
     values ($1, 'Wanderly User')
     on conflict (id) do nothing`,
    [userId],
  );
}

async function resolveUserId(request: IncomingMessage): Promise<string> {
  const header = request.headers.authorization ?? "";
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) return verifiedPrivySubject(token);

  const guestId = request.headers["x-wanderly-guest-id"];
  const normalizedGuestId = Array.isArray(guestId) ? guestId[0] : guestId;
  if (typeof normalizedGuestId === "string" && /^guest_[0-9a-fA-F-]{36}$/.test(normalizedGuestId)) {
    return normalizedGuestId;
  }

  throw new ApiError(401, "Missing bearer token or guest id");
}

async function verifiedPrivySubject(token: string): Promise<string> {
  const key = await verificationKey();
  const { payload } = await jwtVerify(token, key, {
    issuer: "privy.io",
    audience: privyAppId,
  });

  return subjectFromPayload(payload);
}

function subjectFromPayload(payload: JWTPayload): string {
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new ApiError(401, "Invalid Privy subject");
  }
  return payload.sub;
}

async function verificationKey(): Promise<KeyLike> {
  verificationKeyPromise ??= importVerificationKey();
  return verificationKeyPromise;
}

async function importVerificationKey(): Promise<KeyLike> {
  const pem = normalizePem(privyVerificationKey);
  try {
    return await importSPKI(pem, "ES256");
  } catch {
    return await importSPKI(pem, "EdDSA");
  }
}

function normalizePem(key: string): string {
  const value = key.replace(/\\n/g, "\n").trim();
  if (value.includes("BEGIN PUBLIC KEY")) return value;
  return `-----BEGIN PUBLIC KEY-----\n${value}\n-----END PUBLIC KEY-----`;
}

async function readJson(request: IncomingMessage): Promise<JsonBody> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  return asObject(JSON.parse(raw));
}

function asObject(value: unknown): JsonBody {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as JsonBody;
  }
  throw new ApiError(400, "Expected JSON object");
}

function withOwner(body: JsonBody, userId: string): JsonBody {
  return { ...writableFields(body), user_id: userId };
}

function writableFields(body: JsonBody, omit: string[] = []): JsonBody {
  const blocked = new Set(["user_id", ...omit]);
  return Object.fromEntries(Object.entries(body).filter(([key]) => !blocked.has(key)));
}

function pickFields<T extends readonly string[]>(body: JsonBody, allowed: T): JsonBody {
  const allowedSet = new Set<string>(allowed);
  return Object.fromEntries(Object.entries(body).filter(([key]) => allowedSet.has(key)));
}

function buildInsert(table: string, body: JsonBody, allowed: readonly string[]): { sql: string; values: QueryValue[] } {
  const columns = Object.keys(pickFields(body, allowed)).filter((column) => body[column] !== undefined);
  if (columns.length === 0) throw new ApiError(400, "No writable fields");

  const values = columns.map((column) => body[column] as QueryValue);
  const params = columns.map((_, index) => `$${index + 1}`);
  return {
    sql: `insert into ${table} (${columns.join(", ")}) values (${params.join(", ")})`,
    values,
  };
}

function buildUpdate(
  table: string,
  body: JsonBody,
  allowed: readonly string[],
): { sql: string; values: QueryValue[] } | undefined {
  const columns = Object.keys(pickFields(body, allowed)).filter((column) => body[column] !== undefined);
  if (columns.length === 0) return undefined;

  const values = columns.map((column) => body[column] as QueryValue);
  const assignments = columns.map((column, index) => `${column} = $${index + 1}`);
  return {
    sql: `update ${table} set ${assignments.join(", ")}`,
    values,
  };
}

function tripsSelect(whereClause: string): string {
  return `
    select
      t.*,
      coalesce(
        json_agg(ts order by ts.day, ts.order_index) filter (where ts.id is not null),
        '[]'::json
      ) as trip_stops
    from trips t
    left join trip_stops ts on ts.trip_id = t.id
    ${whereClause}
    group by t.id
  `;
}

function sendJson(response: ServerResponse, body: unknown, status = 200): void {
  response.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, x-wanderly-guest-id",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Content-Type": "application/json",
  });
  response.end(status === 204 ? undefined : JSON.stringify(body));
}

function formatPlace(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatTrip(row: JsonBody): JsonBody {
  return formatDates({
    ...row,
    trip_stops: Array.isArray(row.trip_stops)
      ? row.trip_stops.map((stop) => formatDates(asObject(stop)))
      : [],
  });
}

function formatProfile(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatDates(row: JsonBody): JsonBody {
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => {
      if (value instanceof Date) return [key, toIsoSeconds(value)];
      return [key, value];
    }),
  );
}

function toIsoSeconds(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
