import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { importSPKI, jwtVerify } from "npm:jose@5.9.6";
import type { JWTPayload, KeyLike } from "npm:jose@5.9.6";

type JsonBody = Record<string, unknown>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
};

const supabaseUrl = requireEnv("SUPABASE_URL");
const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const privyAppId = requireEnv("PRIVY_APP_ID");
const privyVerificationKey = requireEnv("PRIVY_VERIFICATION_KEY");

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let verificationKeyPromise: Promise<KeyLike> | undefined;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return jsonResponse(null, 204);
  }

  try {
    const userId = await verifiedPrivySubject(request);
    await ensureProfile(userId);

    const route = routeFromUrl(request.url);

    if (route.resource === "places") {
      return await handlePlaces(request, route.id, userId);
    }
    if (route.resource === "trips") {
      return await handleTrips(request, route.id, userId);
    }
    if (route.resource === "profile") {
      return await handleProfile(request, userId);
    }

    return jsonResponse({ error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, status);
  }
});

async function handlePlaces(
  request: Request,
  placeId: string | undefined,
  userId: string,
): Promise<Response> {
  if (request.method === "GET" && !placeId) {
    const { data, error } = await supabase
      .from("places")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false });
    return result(data, error);
  }

  if (request.method === "POST" && !placeId) {
    const body = await readJson(request);
    const row = withOwner(body, userId);
    const { data, error } = await supabase.from("places").insert(row).select(
      "*",
    ).single();
    return result(data, error, 201);
  }

  if (request.method === "PATCH" && placeId) {
    const body = writableFields(await readJson(request), ["id", "updated_at"]);
    const { data, error } = await supabase
      .from("places")
      .update(body)
      .eq("id", placeId)
      .eq("user_id", userId)
      .select("*")
      .maybeSingle();
    if (error) return result(null, error);
    if (!data) return jsonResponse({ error: "Place not found" }, 404);
    return jsonResponse(data);
  }

  if (request.method === "DELETE" && placeId) {
    const { data, error } = await supabase
      .from("places")
      .delete()
      .eq("id", placeId)
      .eq("user_id", userId)
      .select("id")
      .maybeSingle();
    if (error) return result(null, error);
    if (!data) return jsonResponse({ error: "Place not found" }, 404);
    return jsonResponse(null, 204);
  }

  return jsonResponse({ error: "Unsupported places route" }, 405);
}

async function handleTrips(
  request: Request,
  tripId: string | undefined,
  userId: string,
): Promise<Response> {
  if (request.method === "GET" && !tripId) {
    const { data, error } = await supabase
      .from("trips")
      .select("*,trip_stops(*)")
      .eq("user_id", userId)
      .order("created_at", { ascending: false });
    return result(data, error);
  }

  if (request.method === "POST" && !tripId) {
    const body = await readJson(request);
    const stops = Array.isArray(body.trip_stops) ? body.trip_stops : [];
    const tripRow = withOwner(writableFields(body, ["trip_stops"]), userId);

    const { data: trip, error: tripError } = await supabase.from("trips")
      .insert(tripRow).select("*").single();
    if (tripError) return result(null, tripError);

    if (stops.length > 0) {
      const stopRows = stops.map((stop) => ({
        ...writableFields(asObject(stop)),
        trip_id: trip.id,
      }));
      const { error: stopsError } = await supabase.from("trip_stops").insert(
        stopRows,
      );
      if (stopsError) return result(null, stopsError);
    }

    const { data, error } = await supabase
      .from("trips")
      .select("*,trip_stops(*)")
      .eq("id", trip.id)
      .eq("user_id", userId)
      .single();
    return result(data, error, 201);
  }

  if (request.method === "PATCH" && tripId) {
    const body = writableFields(await readJson(request), [
      "id",
      "trip_stops",
      "updated_at",
    ]);
    const { data, error } = await supabase
      .from("trips")
      .update(body)
      .eq("id", tripId)
      .eq("user_id", userId)
      .select("*,trip_stops(*)")
      .maybeSingle();
    if (error) return result(null, error);
    if (!data) return jsonResponse({ error: "Trip not found" }, 404);
    return jsonResponse(data);
  }

  if (request.method === "DELETE" && tripId) {
    const { data, error } = await supabase
      .from("trips")
      .delete()
      .eq("id", tripId)
      .eq("user_id", userId)
      .select("id")
      .maybeSingle();
    if (error) return result(null, error);
    if (!data) return jsonResponse({ error: "Trip not found" }, 404);
    return jsonResponse(null, 204);
  }

  return jsonResponse({ error: "Unsupported trips route" }, 405);
}

async function handleProfile(
  request: Request,
  userId: string,
): Promise<Response> {
  if (request.method === "GET") {
    const { data: profile, error } = await supabase.from("profiles").select("*")
      .eq("id", userId).single();
    if (error) return result(null, error);

    const [
      { count: savedCount },
      { count: visitedCount },
      { data: trips, error: tripsError },
    ] = await Promise.all([
      supabase.from("places").select("id", { count: "exact", head: true }).eq(
        "user_id",
        userId,
      ),
      supabase.from("places").select("id", { count: "exact", head: true }).eq(
        "user_id",
        userId,
      ).eq("status", "visited"),
      supabase.from("trips").select("city").eq("user_id", userId),
    ]);
    if (tripsError) return result(null, tripsError);

    const citiesCount = new Set(
      (trips ?? []).map((trip) => trip.city).filter(Boolean),
    ).size;
    return jsonResponse({
      ...profile,
      saved_count: savedCount ?? 0,
      visited_count: visitedCount ?? 0,
      cities_count: citiesCount,
    });
  }

  if (request.method === "PATCH") {
    const body = pickFields(await readJson(request), [
      "display_name",
      "avatar_url",
    ]);
    const { data, error } = await supabase
      .from("profiles")
      .update(body)
      .eq("id", userId)
      .select("*")
      .single();
    return result(data, error);
  }

  return jsonResponse({ error: "Unsupported profile route" }, 405);
}

async function ensureProfile(userId: string): Promise<void> {
  const { data, error } = await supabase.from("profiles").select("id").eq(
    "id",
    userId,
  ).maybeSingle();
  if (error) throw new ApiError(500, error.message);
  if (data) return;

  const { error: insertError } = await supabase.from("profiles").insert({
    id: userId,
    display_name: "SAV-E User",
  });
  if (insertError) throw new ApiError(500, insertError.message);
}

async function verifiedPrivySubject(request: Request): Promise<string> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ApiError(401, "Missing bearer token");

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
  if (!verificationKeyPromise) {
    verificationKeyPromise = importVerificationKey();
  }
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

function routeFromUrl(rawUrl: string): { resource: string; id?: string } {
  const url = new URL(rawUrl);
  const parts = url.pathname.split("/").filter(Boolean);
  const functionIndex = parts.lastIndexOf("save-api");
  const routeParts = functionIndex >= 0
    ? parts.slice(functionIndex + 1)
    : parts;
  return { resource: routeParts[0] ?? "", id: routeParts[1] };
}

async function readJson(request: Request): Promise<JsonBody> {
  if (!request.body) return {};
  return asObject(await request.json());
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
  const blocked = new Set(["user_id", "created_at", ...omit]);
  const result: JsonBody = {};
  for (const [key, value] of Object.entries(body)) {
    if (!blocked.has(key)) result[key] = value;
  }
  return result;
}

function pickFields(body: JsonBody, allowed: string[]): JsonBody {
  const allowedSet = new Set(allowed);
  const result: JsonBody = {};
  for (const [key, value] of Object.entries(body)) {
    if (allowedSet.has(key)) result[key] = value;
  }
  return result;
}

function result(
  data: unknown,
  error: { message: string } | null,
  successStatus = 200,
): Response {
  if (error) return jsonResponse({ error: error.message }, 500);
  return jsonResponse(data, successStatus);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
