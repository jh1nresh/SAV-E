import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { importSPKI, jwtVerify, type JWTPayload, type KeyLike } from "jose";
import pg from "pg";
import { runSourceSearchRecovery, type SourceSearchCandidate } from "./sourceSearchWorker.js";
import {
  normalizeFollowRequest,
  normalizeVisibilityRequest,
  parseLens,
} from "./socialContracts.js";

type JsonBody = Record<string, unknown>;
type QueryValue = string | number | boolean | Date | string[] | JsonBody | JsonBody[] | null;

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

const profileFields = ["display_name", "avatar_url", "handle", "referral_code"] as const;

const captureFields = [
  "id",
  "source_type",
  "source_url",
  "raw_text",
  "title",
  "status",
  "created_at",
] as const;

const placeCandidateFields = [
  "id",
  "capture_id",
  "place_id",
  "name",
  "address",
  "city",
  "latitude",
  "longitude",
  "evidence",
  "confidence",
  "missing_info",
  "status",
  "created_at",
] as const;

const agentDecisionFields = [
  "id",
  "candidate_id",
  "action",
  "reason",
  "created_at",
] as const;

const agentCapabilityFields = [
  "id",
  "agent_family",
  "vertical",
  "action",
  "description",
  "risk_level",
  "input_schema",
  "output_schema",
  "enabled",
  "created_at",
] as const;

const agentToolCallFields = [
  "id",
  "capability_id",
  "capture_id",
  "recommendation_set_id",
  "input",
  "output",
  "status",
  "error",
  "created_at",
] as const;

const recommendationSetFields = [
  "id",
  "capture_id",
  "prompt",
  "summary",
  "context",
  "status",
  "created_at",
] as const;

const recommendationItemFields = [
  "id",
  "recommendation_set_id",
  "place_candidate_id",
  "place_id",
  "rank",
  "title",
  "rationale",
  "r8_score",
  "slr_status",
  "evidence",
  "created_at",
] as const;

const jsonbFields = new Set([
  "context",
  "evidence",
  "input",
  "input_schema",
  "output",
  "output_schema",
]);

createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    return sendJson(response, null, 204);
  }

  try {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (request.method === "GET" && url.pathname === "/") {
      return sendJson(response, { ok: true, service: "save-backend" });
    }

    const segments = url.pathname.split("/").filter(Boolean);
    const [resource, id] = segments;

    if (request.method === "GET" && resource === "referrals") {
      return await handleReferrals(request, response, id, url);
    }

    const userId = await resolveUserId(request);
    await ensureProfile(userId);

    if (resource === "places" && id && segments[2] === "visibility") {
      return await handlePlaceVisibility(request, response, id, userId);
    }
    if (resource === "places") return await handlePlaces(request, response, id, userId);
    if (resource === "trips") return await handleTrips(request, response, id, userId);
    if (resource === "profile") return await handleProfile(request, response, userId);
    if (resource === "follows") return await handleFollows(request, response, userId);
    if (resource === "social" && id === "signals") return await handleSocialSignals(request, response, url, userId);
    if (resource === "memory") {
      return await handleMemory(request, response, segments.slice(1), url, userId);
    }
    if (resource === "agents") {
      return await handleAgents(request, response, segments.slice(1), url, userId);
    }

    return sendJson(response, { error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return sendJson(response, { error: message }, status);
  }
}).listen(Number(process.env.PORT ?? 3000), () => {
  console.log(`SAV-E backend listening on ${process.env.PORT ?? 3000}`);
});

async function handlePlaces(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !placeId) {
    const rows = await fetchPlacesWithOptionalVisibility(userId);
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

async function fetchPlacesWithOptionalVisibility(userId: string): Promise<JsonBody[]> {
  try {
    const { rows } = await pool.query(
      `select p.*, pv.visibility
       from places p
       left join place_visibility pv on pv.place_id = p.id
       where p.user_id = $1
       order by p.created_at desc`,
      [userId],
    );
    return rows;
  } catch (error) {
    if (!isMissingRelationError(error)) throw error;

    console.warn("place_visibility table is missing; returning places with private visibility fallback.");
    const { rows } = await pool.query(
      `select p.*, 'private' as visibility
       from places p
       where p.user_id = $1
       order by p.created_at desc`,
      [userId],
    );
    return rows;
  }
}

async function handleTrips(
  request: IncomingMessage,
  response: ServerResponse,
  tripId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !tripId) {
    const { rows } = await pool.query(tripsSelect("where t.user_id = $1", "order by t.created_at desc"), [userId]);
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

async function handleFollows(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported follows route" }, 405);

  const followRequest = normalizeFollowRequest(await readJson(request));
  const target = await resolveFollowTarget(followRequest);
  const targetId = stringValue(target.id);
  if (!targetId) throw new ApiError(404, "Profile not found");
  if (targetId === userId) return sendJson(response, { error: "Cannot follow yourself" }, 400);

  const { rows } = await pool.query(
    `insert into follows (follower_id, following_id, lens, source, referral_code)
     values ($1, $2, $3, $4, $5)
     on conflict (follower_id, following_id) do update set
       lens = excluded.lens,
       source = excluded.source,
       referral_code = coalesce(excluded.referral_code, follows.referral_code)
     returning *`,
    [userId, targetId, followRequest.lens, followRequest.source, followRequest.referralCode ?? null],
  );

  return sendJson(response, {
    follow: formatFollow(rows[0]),
    profile: formatPublicProfile(target),
  }, 201);
}

async function handlePlaceVisibility(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "PATCH") return sendJson(response, { error: "Unsupported place visibility route" }, 405);

  await ensureOwnedPlaceReference(placeId, userId);
  const visibility = normalizeVisibilityRequest(await readJson(request));
  const { rows } = await pool.query(
    `insert into place_visibility (
       place_id,
       user_id,
       visibility,
       allow_friend_signal,
       allow_trending_signal,
       published_at
     )
     values ($1, $2, $3, $4, $5, case when $3 = 'private' then null else now() end)
     on conflict (place_id) do update set
       visibility = excluded.visibility,
       allow_friend_signal = excluded.allow_friend_signal,
       allow_trending_signal = excluded.allow_trending_signal,
       published_at = case
         when excluded.visibility = 'private' then null
         when place_visibility.published_at is null then now()
         else place_visibility.published_at
       end
     returning *`,
    [
      placeId,
      userId,
      visibility.visibility,
      visibility.allowFriendSignal,
      visibility.allowTrendingSignal,
    ],
  );

  return sendJson(response, formatDates(rows[0]));
}

async function handleSocialSignals(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported social signals route" }, 405);

  const lens = parseLens(url.searchParams.get("lens"), "forYou");
  const limit = clampLimit(url.searchParams.get("limit"));
  const signals: JsonBody[] = [];

  try {
    if (lens === "forYou" || lens === "friends") {
      signals.push(...await friendSignalPlaces(userId, limit));
    }
    if (lens === "forYou" || lens === "trending") {
      signals.push(...await trendingSignalPlaces(userId, limit));
    }
  } catch (error) {
    if (isMissingRelationError(error)) {
      console.warn("Social signal schema is missing; returning empty signals until migrations run.");
      return sendJson(response, []);
    }
    throw error;
  }

  return sendJson(response, signals.slice(0, limit));
}

async function handleReferrals(
  request: IncomingMessage,
  response: ServerResponse,
  referralCode: string | undefined,
  url: URL,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported referrals route" }, 405);

  const code = referralCode ?? url.searchParams.get("code") ?? undefined;
  const handle = url.searchParams.get("handle") ?? undefined;
  const profile = await referralProfile(code, handle);
  const profileId = stringValue(profile.id);
  if (!profileId) throw new ApiError(404, "Referral profile not found");
  const featuredPlaces = await referralFeaturedPlaces(profileId, stringValue(profile.referral_code) ?? code ?? "");

  return sendJson(response, {
    referrerId: profileId,
    handle: stringValue(profile.handle) ?? "",
    displayName: displayName(profile),
    referralCode: stringValue(profile.referral_code) ?? "",
    lens: "friends",
    avatarUrl: profile.avatar_url ?? null,
    trustedGuideCount: profile.trusted_guide_count ?? 0,
    featuredPlaces,
  });
}

async function handleMemory(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  url: URL,
  userId: string,
): Promise<void> {
  const [kind, id] = segments;

  if (kind === "captures" && id && segments[2] === "search-recovery") {
    return await handleCaptureSearchRecovery(request, response, id, userId);
  }
  if (kind === "captures") return await handleMemoryCaptures(request, response, id, userId);
  if (kind === "candidates") return await handleMemoryCandidates(request, response, id, url, userId);
  if (kind === "decisions") return await handleMemoryDecisions(request, response, url, userId);
  if (kind === "recommendations") return await handleMemoryRecommendations(request, response, id, userId);

  return sendJson(response, { error: "Unsupported memory route" }, 405);
}

async function handleCaptureSearchRecovery(
  request: IncomingMessage,
  response: ServerResponse,
  captureId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported capture search recovery route" }, 405);
  }

  await ensureCaptureOwner(captureId, userId);
  const body = await readJson(request);
  const requestedQueries = stringArray(body.queries);
  const maxQueries = typeof body.max_queries === "number" ? Math.max(1, Math.min(6, body.max_queries)) : undefined;

  const { rows } = await pool.query("select * from captures where id = $1 and user_id = $2", [captureId, userId]);
  const capture = asObject(rows[0]);

  await pool.query("update captures set status = 'investigating' where id = $1 and user_id = $2", [captureId, userId]);

  const recovery = await runSourceSearchRecovery({
    sourceUrl: stringValue(capture.source_url),
    rawText: stringValue(capture.raw_text),
    title: stringValue(capture.title),
    suggestedSearchQueries: requestedQueries,
    maxQueries,
  });

  const existingKeys = await existingCandidateKeys(captureId);
  const createdCandidates: JsonBody[] = [];

  for (const candidate of recovery.candidates) {
    const key = candidateKey(candidate.name, candidate.address);
    if (existingKeys.has(key)) continue;
    existingKeys.add(key);

    const body = sourceSearchCandidateBody(candidate, captureId);
    const insert = buildInsert("place_candidates", body, placeCandidateFields);
    const { rows: insertedRows } = await pool.query(`${insert.sql} returning *`, insert.values);
    createdCandidates.push(formatPlaceCandidate(insertedRows[0]));
  }

  await pool.query("update captures set status = 'review' where id = $1 and user_id = $2", [captureId, userId]);

  return sendJson(response, {
    capture_id: captureId,
    queries: recovery.queries,
    search_results: recovery.searchResults,
    created_candidates: createdCandidates,
    errors: recovery.errors,
    receipt: recovery.receipt,
  });
}

async function handleMemoryCaptures(
  request: IncomingMessage,
  response: ServerResponse,
  captureId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !captureId) {
    const { rows } = await pool.query(
      "select * from captures where user_id = $1 order by created_at desc",
      [userId],
    );
    return sendJson(response, rows.map(formatCapture));
  }

  if (request.method === "GET" && captureId) {
    const { rows } = await pool.query(
      "select * from captures where id = $1 and user_id = $2",
      [captureId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Capture not found" }, 404);
    return sendJson(response, formatCapture(rows[0]));
  }

  if (request.method === "POST" && !captureId) {
    const body = withOwner(await readJson(request), userId);
    const insert = buildInsert("captures", body, [...captureFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatCapture(rows[0]), 201);
  }

  if (request.method === "PATCH" && captureId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "created_at", "updated_at"]);
    const update = buildUpdate("captures", body, captureFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, captureId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Capture not found" }, 404);
    return sendJson(response, formatCapture(rows[0]));
  }

  return sendJson(response, { error: "Unsupported memory captures route" }, 405);
}

async function handleMemoryCandidates(
  request: IncomingMessage,
  response: ServerResponse,
  candidateId: string | undefined,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !candidateId) {
    const captureId = url.searchParams.get("capture_id");
    const where = captureId
      ? "where c.user_id = $1 and pc.capture_id = $2"
      : "where c.user_id = $1";
    const values = captureId ? [userId, captureId] : [userId];
    const { rows } = await pool.query(
      `select pc.*
       from place_candidates pc
       join captures c on c.id = pc.capture_id
       ${where}
       order by pc.created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatPlaceCandidate));
  }

  if (request.method === "POST" && !candidateId) {
    const body = await readJson(request);
    const captureId = typeof body.capture_id === "string" ? body.capture_id : undefined;
    if (!captureId) return sendJson(response, { error: "capture_id is required" }, 400);
    await ensureCaptureOwner(captureId, userId);
    await ensureOwnedPlaceReference(body.place_id, userId);

    const insert = buildInsert("place_candidates", body, placeCandidateFields);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatPlaceCandidate(rows[0]), 201);
  }

  if (request.method === "PATCH" && candidateId) {
    const body = writableFields(await readJson(request), ["id", "capture_id", "created_at", "updated_at"]);
    await ensureOwnedPlaceReference(body.place_id, userId);
    const update = buildUpdate("place_candidates", body, placeCandidateFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, candidateId, userId];
    const { rows } = await pool.query(
      `${update.sql}
       from captures c
       where place_candidates.capture_id = c.id
         and place_candidates.id = $${values.length - 1}
         and c.user_id = $${values.length}
       returning place_candidates.*`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Candidate not found" }, 404);
    return sendJson(response, formatPlaceCandidate(rows[0]));
  }

  return sendJson(response, { error: "Unsupported memory candidates route" }, 405);
}

async function handleMemoryDecisions(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const candidateId = url.searchParams.get("candidate_id");
    const where = candidateId
      ? "where c.user_id = $1 and ad.candidate_id = $2"
      : "where c.user_id = $1";
    const values = candidateId ? [userId, candidateId] : [userId];
    const { rows } = await pool.query(
      `select ad.*
       from agent_decisions ad
       join place_candidates pc on pc.id = ad.candidate_id
       join captures c on c.id = pc.capture_id
       ${where}
       order by ad.created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatAgentDecision));
  }

  if (request.method === "POST") {
    const body = await readJson(request);
    const candidateId = typeof body.candidate_id === "string" ? body.candidate_id : undefined;
    if (!candidateId) return sendJson(response, { error: "candidate_id is required" }, 400);
    await ensureCandidateOwner(candidateId, userId);

    const insert = buildInsert("agent_decisions", body, agentDecisionFields);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatAgentDecision(rows[0]), 201);
  }

  return sendJson(response, { error: "Unsupported memory decisions route" }, 405);
}

async function handleMemoryRecommendations(
  request: IncomingMessage,
  response: ServerResponse,
  recommendationSetId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !recommendationSetId) {
    const sets = await recommendationSetsForUser(userId);
    return sendJson(response, sets);
  }

  if (request.method === "GET" && recommendationSetId) {
    const sets = await recommendationSetsForUser(userId, recommendationSetId);
    if (!sets[0]) return sendJson(response, { error: "Recommendation not found" }, 404);
    return sendJson(response, sets[0]);
  }

  if (request.method === "POST" && !recommendationSetId) {
    const body = await readJson(request);
    const items = Array.isArray(body.items) ? body.items.map(asObject) : [];
    await ensureOwnedCaptureReference(body.capture_id, userId);
    for (const item of items) await ensureRecommendationItemReferences(item, userId);

    const client = await pool.connect();
    try {
      await client.query("begin");
      const setBody = withOwner(writableFields(body, ["items"]), userId);
      const setInsert = buildInsert("recommendation_sets", setBody, [...recommendationSetFields, "user_id"]);
      const { rows: setRows } = await client.query(`${setInsert.sql} returning *`, setInsert.values);
      const recommendationSet = setRows[0] as { id: string };

      const itemRows: JsonBody[] = [];
      for (const item of items) {
        const itemBody = { ...writableFields(item, ["recommendation_set_id", "created_at"]), recommendation_set_id: recommendationSet.id };
        const itemInsert = buildInsert("recommendation_items", itemBody, recommendationItemFields);
        const { rows } = await client.query(`${itemInsert.sql} returning *`, itemInsert.values);
        itemRows.push(asObject(rows[0]));
      }

      await client.query("commit");
      return sendJson(response, assembleRecommendationSets(setRows, itemRows)[0], 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (request.method === "PATCH" && recommendationSetId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "items", "created_at", "updated_at"]);
    await ensureOwnedCaptureReference(body.capture_id, userId);
    const update = buildUpdate("recommendation_sets", body, recommendationSetFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, recommendationSetId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Recommendation not found" }, 404);

    const sets = await recommendationSetsForUser(userId, recommendationSetId);
    return sendJson(response, sets[0]);
  }

  return sendJson(response, { error: "Unsupported memory recommendations route" }, 405);
}

async function handleAgents(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  url: URL,
  userId: string,
): Promise<void> {
  const [kind] = segments;

  if (kind === "capabilities") return await handleAgentCapabilities(request, response);
  if (kind === "tool-calls") return await handleAgentToolCalls(request, response, url, userId);

  return sendJson(response, { error: "Unsupported agents route" }, 405);
}

async function handleAgentCapabilities(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported agent capabilities route" }, 405);

  const { rows } = await pool.query(
    "select * from agent_capabilities where enabled = true order by agent_family, vertical, action",
  );
  return sendJson(response, rows.map(formatAgentCapability));
}

async function handleAgentToolCalls(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const capabilityId = url.searchParams.get("capability_id");
    const recommendationSetId = url.searchParams.get("recommendation_set_id");
    const filters = ["user_id = $1"];
    const values: QueryValue[] = [userId];

    if (capabilityId) {
      values.push(capabilityId);
      filters.push(`capability_id = $${values.length}`);
    }

    if (recommendationSetId) {
      values.push(recommendationSetId);
      filters.push(`recommendation_set_id = $${values.length}`);
    }

    const { rows } = await pool.query(
      `select * from agent_tool_calls where ${filters.join(" and ")} order by created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatAgentToolCall));
  }

  if (request.method === "POST") {
    const body = await readJson(request);
    const capabilityId = typeof body.capability_id === "string" ? body.capability_id : undefined;
    if (!capabilityId) return sendJson(response, { error: "capability_id is required" }, 400);
    await ensureCapabilityEnabled(capabilityId);
    await ensureOwnedCaptureReference(body.capture_id, userId);
    await ensureOwnedRecommendationSetReference(body.recommendation_set_id, userId);

    const callBody = withOwner(body, userId);
    const insert = buildInsert("agent_tool_calls", callBody, [...agentToolCallFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatAgentToolCall(rows[0]), 201);
  }

  return sendJson(response, { error: "Unsupported agent tool calls route" }, 405);
}

async function resolveFollowTarget(followRequest: ReturnType<typeof normalizeFollowRequest>): Promise<JsonBody> {
  if (followRequest.followingId) {
    const { rows } = await pool.query("select * from profiles where id = $1", [followRequest.followingId]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  if (followRequest.handle) {
    const { rows } = await pool.query("select * from profiles where lower(handle) = lower($1)", [followRequest.handle]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  if (followRequest.referralCode) {
    const { rows } = await pool.query("select * from profiles where referral_code = $1", [followRequest.referralCode]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  throw new ApiError(400, "following_id, handle, or referral_code is required");
}

async function referralProfile(code: string | undefined, handle: string | undefined): Promise<JsonBody> {
  if (!code && !handle) throw new ApiError(400, "code or handle is required");

  const filters: string[] = [];
  const values: QueryValue[] = [];
  if (code) {
    values.push(code);
    filters.push(`referral_code = $${values.length}`);
  }
  if (handle) {
    values.push(handle.replace(/^@+/, ""));
    filters.push(`lower(handle) = lower($${values.length})`);
  }

  const { rows } = await pool.query(`select * from profiles where ${filters.join(" or ")} limit 1`, values);
  if (!rows[0]) throw new ApiError(404, "Referral profile not found");
  return asObject(rows[0]);
}

async function friendSignalPlaces(userId: string, limit: number): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       f.lens as follow_lens,
       actor.id as actor_id,
       actor.display_name as actor_display_name,
       actor.handle as actor_handle,
       actor.referral_code as actor_referral_code
     from follows f
     join profiles actor on actor.id = f.following_id
     join places p on p.user_id = f.following_id
     join place_visibility pv on pv.place_id = p.id
     where f.follower_id = $1
       and p.user_id <> $1
       and pv.allow_friend_signal = true
       and pv.visibility in ('friends', 'public_link', 'public_guide')
     order by p.created_at desc
     limit $2`,
    [userId, limit],
  );

  return rows.map((row) => {
    const value = asObject(row);
    const actorName = displayName({
      display_name: value.actor_display_name,
      handle: value.actor_handle,
    });
    return formatSocialPlace(value, {
      kind: "friend_saved",
      lens: parseLens(value.follow_lens, "friends"),
      friendNames: actorName ? [actorName] : [],
      friendCount: 1,
      saveCount: 1,
      trendingRank: null,
      categoryRank: null,
      sourceLabel: actorName,
      referrerId: stringValue(value.actor_id) ?? null,
      referralCode: stringValue(value.actor_referral_code) ?? null,
    });
  });
}

async function trendingSignalPlaces(userId: string, limit: number): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       pss.lens as signal_lens,
       pss.friend_count,
       pss.save_count,
       pss.category_rank,
       pss.source_label,
       pss.referrer_id,
       pss.referral_code
     from place_social_signals pss
     join places p on p.id = pss.place_id
     join place_visibility pv on pv.place_id = p.id
     where (pss.viewer_user_id = $1 or pss.viewer_user_id is null)
       and pss.signal_type = 'trending'
       and p.user_id <> $1
       and pv.allow_trending_signal = true
       and pv.visibility in ('public_link', 'public_guide')
     order by pss.trending_score desc, pss.created_at desc
     limit $2`,
    [userId, limit],
  );

  return rows.map((row, index) => {
    const value = asObject(row);
    const categoryRank = numberValue(value.category_rank) ?? index + 1;
    return formatSocialPlace(value, {
      kind: "trending",
      lens: parseLens(value.signal_lens, "trending"),
      friendNames: [],
      friendCount: numberValue(value.friend_count) ?? 0,
      saveCount: numberValue(value.save_count) ?? 0,
      trendingRank: categoryRank,
      categoryRank,
      sourceLabel: stringValue(value.source_label) ?? "Trending in SAV-E",
      referrerId: stringValue(value.referrer_id) ?? null,
      referralCode: stringValue(value.referral_code) ?? null,
    });
  });
}

async function referralFeaturedPlaces(referrerId: string, referralCode: string): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       owner.display_name as owner_display_name,
       owner.handle as owner_handle
     from places p
     join place_visibility pv on pv.place_id = p.id
     join profiles owner on owner.id = p.user_id
     where p.user_id = $1
       and pv.allow_friend_signal = true
       and pv.visibility in ('public_link', 'public_guide')
     order by p.created_at desc
     limit 6`,
    [referrerId],
  );

  return rows.map((row) => {
    const value = asObject(row);
    const ownerName = displayName({
      display_name: value.owner_display_name,
      handle: value.owner_handle,
    });
    return formatSocialPlace(value, {
      kind: "referral_guide",
      lens: "friends",
      friendNames: [],
      friendCount: 0,
      saveCount: 0,
      trendingRank: null,
      categoryRank: null,
      sourceLabel: ownerName,
      referrerId,
      referralCode,
    });
  });
}

function formatSocialPlace(row: JsonBody, socialSignal: JsonBody): JsonBody {
  return {
    ...formatDates(pickFields(row, [...placeFields, "user_id"])),
    visibility: stringValue(row.social_visibility) ?? "private",
    social_signal: socialSignal,
  };
}

function formatFollow(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatPublicProfile(row: JsonBody): JsonBody {
  return {
    id: row.id,
    handle: row.handle ?? null,
    display_name: displayName(row),
    avatar_url: row.avatar_url ?? null,
    referral_code: row.referral_code ?? null,
  };
}

function displayName(row: JsonBody): string {
  return stringValue(row.display_name) ?? stringValue(row.handle) ?? "SAV-E User";
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return undefined;
}

function clampLimit(value: string | null): number {
  const parsed = value ? Number(value) : 40;
  if (!Number.isFinite(parsed)) return 40;
  return Math.max(1, Math.min(100, Math.trunc(parsed)));
}

function isMissingRelationError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as { code?: unknown; message?: unknown };
  return value.code === "42P01" ||
    (typeof value.message === "string" && value.message.includes("does not exist"));
}

async function existingCandidateKeys(captureId: string): Promise<Set<string>> {
  const { rows } = await pool.query("select name, address from place_candidates where capture_id = $1", [captureId]);
  return new Set(rows.map((row) => {
    const value = asObject(row);
    return candidateKey(stringValue(value.name) ?? "", stringValue(value.address) ?? "");
  }));
}

function sourceSearchCandidateBody(candidate: SourceSearchCandidate, captureId: string): JsonBody {
  return {
    capture_id: captureId,
    name: candidate.name,
    address: candidate.address,
    city: "",
    latitude: null,
    longitude: null,
    evidence: candidate.evidence.map((text) => ({ text })),
    confidence: candidate.confidence,
    missing_info: candidate.missingInfo,
    status: "review",
  };
}

function candidateKey(name: string, address: string): string {
  return `${canonicalCandidateValue(name)}|${canonicalCandidateValue(address)}`;
}

function canonicalCandidateValue(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, " ").trim();
}

function stringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

async function ensureCaptureOwner(captureId: string, userId: string): Promise<void> {
  const { rows } = await pool.query("select id from captures where id = $1 and user_id = $2", [captureId, userId]);
  if (!rows[0]) throw new ApiError(404, "Capture not found");
}

async function ensureCandidateOwner(candidateId: string, userId: string): Promise<void> {
  const { rows } = await pool.query(
    `select pc.id
     from place_candidates pc
     join captures c on c.id = pc.capture_id
     where pc.id = $1 and c.user_id = $2`,
    [candidateId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Candidate not found");
}

async function ensureOwnedPlaceReference(placeId: unknown, userId: string): Promise<void> {
  if (placeId === undefined || placeId === null) return;
  if (typeof placeId !== "string") throw new ApiError(400, "place_id must be a string");

  const { rows } = await pool.query("select id from places where id = $1 and user_id = $2", [placeId, userId]);
  if (!rows[0]) throw new ApiError(404, "Place not found");
}

async function ensureOwnedCaptureReference(captureId: unknown, userId: string): Promise<void> {
  if (captureId === undefined || captureId === null) return;
  if (typeof captureId !== "string") throw new ApiError(400, "capture_id must be a string");
  await ensureCaptureOwner(captureId, userId);
}

async function ensureOwnedCandidateReference(candidateId: unknown, userId: string): Promise<void> {
  if (candidateId === undefined || candidateId === null) return;
  if (typeof candidateId !== "string") throw new ApiError(400, "place_candidate_id must be a string");
  await ensureCandidateOwner(candidateId, userId);
}

async function ensureOwnedRecommendationSetReference(recommendationSetId: unknown, userId: string): Promise<void> {
  if (recommendationSetId === undefined || recommendationSetId === null) return;
  if (typeof recommendationSetId !== "string") throw new ApiError(400, "recommendation_set_id must be a string");

  const { rows } = await pool.query("select id from recommendation_sets where id = $1 and user_id = $2", [
    recommendationSetId,
    userId,
  ]);
  if (!rows[0]) throw new ApiError(404, "Recommendation not found");
}

async function ensureRecommendationItemReferences(item: JsonBody, userId: string): Promise<void> {
  await ensureOwnedCandidateReference(item.place_candidate_id, userId);
  await ensureOwnedPlaceReference(item.place_id, userId);
}

async function ensureCapabilityEnabled(capabilityId: string): Promise<void> {
  const { rows } = await pool.query("select id from agent_capabilities where id = $1 and enabled = true", [
    capabilityId,
  ]);
  if (!rows[0]) throw new ApiError(404, "Capability not found");
}

async function ensureProfile(userId: string): Promise<void> {
  await pool.query(
    `insert into profiles (id, display_name)
     values ($1, 'SAV-E User')
     on conflict (id) do nothing`,
    [userId],
  );
}

async function resolveUserId(request: IncomingMessage): Promise<string> {
  const header = request.headers.authorization ?? "";
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) return verifiedPrivySubject(token);

  const guestId = request.headers["x-save-guest-id"] ?? request.headers["x-wanderly-guest-id"];
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

  const values = columns.map((column) => queryValue(column, body[column]));
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

  const values = columns.map((column) => queryValue(column, body[column]));
  const assignments = columns.map((column, index) => `${column} = $${index + 1}`);
  return {
    sql: `update ${table} set ${assignments.join(", ")}`,
    values,
  };
}

function queryValue(column: string, value: unknown): QueryValue {
  if (jsonbFields.has(column) && value !== null && value !== undefined) {
    return JSON.stringify(value);
  }
  return value as QueryValue;
}

function tripsSelect(whereClause: string, orderClause = ""): string {
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
    ${orderClause}
  `;
}

async function recommendationSetsForUser(userId: string, recommendationSetId?: string): Promise<JsonBody[]> {
  const values = recommendationSetId ? [userId, recommendationSetId] : [userId];
  const where = recommendationSetId ? "where user_id = $1 and id = $2" : "where user_id = $1";
  const { rows: setRows } = await pool.query(
    `select * from recommendation_sets ${where} order by created_at desc`,
    values,
  );
  if (setRows.length === 0) return [];

  const setIds = setRows.map((row) => (row as { id: string }).id);
  const { rows: itemRows } = await pool.query(
    "select * from recommendation_items where recommendation_set_id = any($1::uuid[]) order by rank, created_at",
    [setIds],
  );

  return assembleRecommendationSets(setRows, itemRows);
}

function assembleRecommendationSets(setRows: JsonBody[], itemRows: JsonBody[]): JsonBody[] {
  const itemsBySetId = new Map<string, JsonBody[]>();
  for (const row of itemRows) {
    const item = formatRecommendationItem(row);
    const setId = String(item.recommendation_set_id);
    const items = itemsBySetId.get(setId) ?? [];
    items.push(item);
    itemsBySetId.set(setId, items);
  }

  return setRows.map((row) => {
    const set = formatRecommendationSet(row);
    return {
      ...set,
      items: itemsBySetId.get(String(set.id)) ?? [],
    };
  });
}

function sendJson(response: ServerResponse, body: unknown, status = 200): void {
  response.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, x-save-guest-id, x-wanderly-guest-id",
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

function formatCapture(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatPlaceCandidate(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentDecision(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentCapability(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentToolCall(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatRecommendationSet(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatRecommendationItem(row: JsonBody): JsonBody {
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
