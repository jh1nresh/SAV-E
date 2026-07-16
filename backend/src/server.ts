import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomBytes, createHash, createHmac, timingSafeEqual } from "node:crypto";
import { importSPKI, jwtVerify, type JWTPayload, type KeyLike } from "jose";
import pg, { type PoolClient } from "pg";
import {
  evaluateAccountConfirmationRequest,
  evaluateAccountStatusRequest,
  resolveProfileSubject,
  stableAccountRefSecret,
} from "./accountStatus.js";
import { createGuestSession, userIdFromGuestSessionToken } from "./guestSessions.js";
import {
  buildMaatPlaceAnalysis,
  buildPublicPlaceCard,
  buildTrustSummary,
  experienceReviewClaimType,
  experienceReviewMutationScope,
  formatPlaceClaim,
  normalizeExperienceReviewPatch,
  normalizePlaceClaimCreate,
  normalizeRecommendationRequest,
  normalizeUsageReceiptCreate,
  parseProofLevel,
  proofLevelsAtLeast,
  recommendPlacesByClaims,
} from "./placeClaims.js";
import { enrichMaatPlaceAnalysisWithPublicWeb } from "./maatPublicWebAnalysis.js";
import { runSourceSearchRecovery, type SourceSearchCandidate } from "./sourceSearchWorker.js";
import {
  defaultGeminiText,
  defaultPlacesSearch,
  defaultPlacesReviews,
  processSendblueInbound,
  PgBackedConversationStore,
  conversationStateTableSql,
  SendblueClient,
} from "./sendblueBot.js";
import { issueBuyerSession, placeOrder, nearby, createRecurring, pendingRuns, confirmRecurringRun, type SllrBuyer } from "./sllrCommerce.js";
import { defaultGeocode, parseRecurringSchedule, recurringQuery } from "./sendblueBot.js";
import type { StoredLocation } from "./sendbluePlaceStore.js";
import { SllrBuyerStore, sllrBuyerTableSql, type NumberBuyer } from "./sllrBuyerStore.js";
import { guardReply, claimLevelForOrderStatus } from "./claimGuard.js";
import {
  PgSendbluePlaceStore,
  sendblueSavedPlacesTableSql,
} from "./sendbluePlaceStore.js";
import {
  PgVerifiedVisitStore,
  verifiedVisitsTableSql,
} from "./sendblueReceiptStore.js";
import { PgReviewStore, reviewsTableSql } from "./sendblueReviewStore.js";
import { renderMySavesPage, type MySavesPayload } from "./mySavesPage.js";
import { buildClearingBlockDraft } from "./clearingBlocks.js";
import {
  formatPublicSharedPlaceLink,
  formatSharedPlaceLink,
  normalizeSharedPlaceLinkCreate,
  normalizeSharedSenderSnapshot,
  isSharedPlaceLinkExpired,
  publicSharedPlaceLinkSelectSQL,
  sharedPlaceLinkBodyMaxBytes,
} from "./shareLinks.js";
import {
  friendShareEventExpiryDisposition,
  friendShareCodeFromPlaceCreate,
  friendShareExclusiveOpenFailurePredicate,
  friendSharePlaceOriginConflictClause,
  friendShareRecipientMetrics,
  friendShareShareMetrics,
  friendShareVerifiedCohortPredicate,
  isSelfFriendShareRecipient,
  normalizeFriendShareClientEvent,
  recipientPlaceMatchesSharedPayload,
  type FriendShareClientEvent,
  type FriendShareRecipientMetricsRow,
  type FriendShareShareMetricsRow,
} from "./friendShareEvents.js";
import {
  normalizeFollowRequest,
  normalizeVisibilityRequest,
  parseLens,
} from "./socialContracts.js";
import {
  FollowListInputError,
  listFollowedFriends,
  listFollowedFriendsPage,
  normalizeFollowListOptions,
  unfollowByRelationshipId,
} from "./followList.js";
import {
  WorkflowContractError,
  normalizePlaceRecoveryWorkOrderCreate,
  normalizePlaceRecoveryRunCreate,
  normalizePlaceRecoveryWorkerResult,
  normalizeUserDecision,
  placeRecoveryWorkflowId,
  placeRecoveryWorkflowVersion,
  receiptForResult,
  analysisReceiptForResult,
  type PlaceRecoveryWorkerResult,
  type UserDecisionInput,
} from "./workflowContracts.js";
import {
  WorkflowConflictError,
  planDecisionTransition,
  planResultTransition,
  reconcileReputation,
  safeOpaqueRefs,
} from "./workflowLifecycle.js";
import {
  buildRecommendationAnalysisReceiptDraft,
  envelopeForRecommendationAnalysisReceipt,
  normalizeRecommendationAnalysisReceiptPayload,
  RecommendationAnalysisReceiptPayloadError,
  recommendationAnalysisReceiptPayloadMaxBytes,
  sha256CanonicalJson,
  sha256ImmutableWorkflowReceipt,
} from "./receiptEnvelope.js";
import { readSourceRecoveryConfigStatus } from "./sourceRecoveryConfig.js";
import { createPrivyUserProvisioner } from "./privyUsers.js";
import {
  MemoryContractError,
  normalizePreferenceCreate,
  normalizePreferencePatch,
  normalizeRecommendationOutcome,
} from "./memoryContracts.js";
import {
  R8AgentMetricsQueryError,
  aggregateR8PilotMetrics,
  authorizeR8AgentMetrics,
  normalizeR8AgentMetricsQuery,
  r8AgentMetricsFailureLabels,
  r8AgentMetricsSql,
  type R8AgentMetricsRow,
} from "./r8AgentMetrics.js";
import {
  TrekKmlExportError,
  buildTrekKml,
  normalizeTrekKmlExportRequest,
  trekKmlPlacesSql,
  trekKmlResponseHeaders,
  type TrekKmlPlaceRow,
} from "./trekKmlExport.js";

type JsonBody = Record<string, unknown>;
type QueryValue = string | number | boolean | Date | string[] | JsonBody | JsonBody[] | null;

const { Pool } = pg;

const databaseUrl = requireEnv("DATABASE_URL");
const privyAppId = requireEnv("PRIVY_APP_ID");
const privyVerificationKey = requireEnv("PRIVY_VERIFICATION_KEY");
const privyAppSecret = process.env.PRIVY_APP_SECRET?.trim();
const guestSessionSecret = process.env.SAVE_GUEST_SESSION_SECRET?.trim() || randomBytes(32).toString("hex");
const defaultJsonBodyMaxBytes = 256 * 1024;
const geminiProxyRequestMaxBytes = 64 * 1024;
const geminiProxyResponseMaxBytes = 512 * 1024;

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: databaseSSLConfig(databaseUrl),
});

let verificationKeyPromise: Promise<KeyLike> | undefined;
const privyUserProvisioner = createPrivyUserProvisioner({
  appId: privyAppId,
  appSecret: privyAppSecret,
});

// Per-number place memory for the Sendblue bot. Backed by pool.query (injected,
// not the pool itself, to avoid a circular import in the bot module).
const sendbluePlaceStore = new PgSendbluePlaceStore({
  query: (sql, values) => pool.query(sql, values as QueryValue[]),
});

// Per-number verified-visit memory: forwarded receipts → proof-of-visit.
const sendblueReceiptStore = new PgVerifiedVisitStore({
  query: (sql, values) => pool.query(sql, values as QueryValue[]),
});

// Per-number receipt-gated reviews.
const sendblueReviewStore = new PgReviewStore({
  query: (sql, values) => pool.query(sql, values as QueryValue[]),
});

// Durable conversation memory: in-memory speed, write-through to Postgres, and
// hydrated at boot so multi-turn state survives deploys/restarts.
const sendblueConversationStore = new PgBackedConversationStore({
  query: (sql, values) => pool.query(sql, values as QueryValue[]),
});

export const userChannelsTableSql = `
alter table profiles add column if not exists privy_user_id text;
create unique index if not exists idx_profiles_privy_user_id
  on profiles (privy_user_id) where privy_user_id is not null;

create table if not exists user_channels (
  id uuid primary key default gen_random_uuid(),
  profile_id text references profiles(id) on delete cascade not null,
  channel text not null,
  channel_user_id text not null,
  phone_e164 text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_channels_channel_check check (channel in ('imessage', 'sms', 'line', 'whatsapp', 'sendblue'))
);
create unique index if not exists user_channels_channel_user_unique
  on user_channels (channel, channel_user_id);
create index if not exists user_channels_profile_idx
  on user_channels (profile_id, channel);
`;

// One SLL-R buyer session per phone number, so orders/receipts accrue to a stable
// buyer (the cross-merchant receipt graph). Persisted so a phone keeps the same
// buyerId (and saved card / recurring) across restarts.
const sllrBuyers = new SllrBuyerStore(pool);
// Serialize buyer creation per fromNumber so two concurrent requests can't both
// miss get(), both issueBuyerSession(), and split buyer identity via overwriting set().
const sllrBuyerCreations = new Map<string, Promise<SllrBuyer>>();
async function getOrCreateSllrBuyer(fromNumber: string): Promise<SllrBuyer> {
  const existing = await sllrBuyers.get(fromNumber);
  if (existing) return existing;
  const inFlight = sllrBuyerCreations.get(fromNumber);
  if (inFlight) return inFlight;
  const creation = (async () => {
    const buyer = await issueBuyerSession(`SAV-E ${fromNumber}`);
    await sllrBuyers.set(fromNumber, buyer);
    return buyer;
  })();
  sllrBuyerCreations.set(fromNumber, creation);
  try {
    return await creation;
  } finally {
    sllrBuyerCreations.delete(fromNumber);
  }
}
// Place an SLL-R order for an inbound number. Returned to the bot as deps.order.
async function placeSllrOrder(query: string, fromNumber: string, location?: StoredLocation): Promise<string> {
  const buyer = await getOrCreateSllrBuyer(fromNumber);
  // Pick the nearest merchant to the user's area; fall back to the default.
  let merchantId = process.env.SLLR_DEFAULT_MERCHANT?.trim() || "raposa-coffee";
  if (location) {
    try {
      const near = await nearby(location.lat, location.lng, { limit: 1 });
      if (near[0]) merchantId = near[0].id;
    } catch (error) {
      console.error(`[sendblue] nearby lookup failed, using default merchant kind=${safeErrorKind(error)}`);
    }
  }
  try {
    const order = await placeOrder(merchantId, query, buyer, { customerLabel: "SAV-E" });
    // Post-check: the reply may not claim more than the order's real state.
    let reply = guardReply(
      `✅ Ordered ${order.item.name} ($${order.item.subtotalUsd}) at ${order.merchantName ?? "the merchant"}. I'll text you when it's confirmed.`,
      claimLevelForOrderStatus(order.status),
      `✅ Order received at ${order.merchantName ?? "the merchant"}. I'll text you when it's confirmed.`,
    );
    // "SLL-R asks": offer to make this a recurring order.
    if (order.suggestRecurring?.eligible) {
      reply += `\n\n🔁 Want this regularly? Text e.g. "每天早上 8點 ${order.item.name}" and I'll ask before each one.`;
    }
    return reply;
  } catch (error) {
    console.error(`[sendblue] SLL-R order failed kind=${safeErrorKind(error)}`);
    return "Sorry — I couldn't place that order right now. Try again in a moment.";
  }
}

const SLLR_TZ = process.env.SLLR_DEFAULT_TZ?.trim() || "America/Los_Angeles";
const SLLR_RECURRING_MAX_USD = process.env.SLLR_RECURRING_MAX_USD?.trim() || "20.00";

// Set up a recurring order from a phrase like "每天早上 8點 cold brew". deps.setRecurring.
async function setSllrRecurring(text: string, fromNumber: string, location?: StoredLocation): Promise<string> {
  const buyer = await getOrCreateSllrBuyer(fromNumber);
  let merchantId = process.env.SLLR_DEFAULT_MERCHANT?.trim() || "raposa-coffee";
  if (location) {
    try {
      const near = await nearby(location.lat, location.lng, { limit: 1 });
      if (near[0]) merchantId = near[0].id;
    } catch (error) {
      console.error(`[sendblue] nearby lookup failed for recurring, using default kind=${safeErrorKind(error)}`);
    }
  }
  const schedule = parseRecurringSchedule(text, SLLR_TZ);
  const usual = recurringQuery(text);
  try {
    const { subscription, cardOnFile } = await createRecurring(buyer, merchantId, usual, schedule, SLLR_RECURRING_MAX_USD);
    void subscription;
    const days = schedule.daysOfWeek.length === 7 ? "every day" : schedule.daysOfWeek.length === 5 ? "weekdays" : `${schedule.daysOfWeek.length} days/week`;
    const time = `${String(schedule.hour).padStart(2, "0")}:${String(schedule.minute).padStart(2, "0")}`;
    let reply = `🔁 Set! I'll ask before ordering "${usual}" ${days} at ${time}. Reply "confirm my usual" when I check in.`;
    if (!cardOnFile) reply += `\n\n💳 Heads up: no saved card yet — pay your next order with the Stripe link once and it'll be remembered for recurring.`;
    return reply;
  } catch (error) {
    console.error(`[sendblue] SLL-R recurring setup failed kind=${safeErrorKind(error)}`);
    return "Sorry — I couldn't set that up right now. Try again in a moment.";
  }
}

// Confirm the buyer's pending recurring run → SLL-R charges the saved card. deps.confirmRecurring.
async function confirmSllrRecurring(fromNumber: string): Promise<string> {
  const buyer = await sllrBuyers.get(fromNumber);
  if (!buyer) return "I don't have a recurring order set up for you yet.";
  try {
    const runs = await pendingRuns(buyer);
    if (!runs.length) return "Nothing to confirm right now — no recurring order is pending.";
    const result = await confirmRecurringRun(buyer, runs[0].id);
    if (result.status === "charged" && result.order) {
      return guardReply(
        `✅ Done — ordered ${result.order.item.name} ($${result.order.item.subtotalUsd}). Receipt on the way.`,
        claimLevelForOrderStatus(result.order.status),
        `✅ Recurring order placed.`,
      );
    }
    if (result.status === "no_card") return "I don't have a saved card yet — pay an order with the Stripe link once and I'll remember it.";
    if (result.status === "over_cap") return "That order is over your per-run limit, so I didn't charge it.";
    if (result.status === "declined") return "Your card was declined — please update it and try again.";
    if (result.status === "requires_action") return "Your bank needs an extra confirmation — I'll send a payment link instead.";
    return `Couldn't complete that (${result.status}).`;
  } catch (error) {
    console.error(`[sendblue] SLL-R recurring confirm failed kind=${safeErrorKind(error)}`);
    return "Sorry — I couldn't confirm that right now. Try again in a moment.";
  }
}

// Recurring notifier: SLL-R's cron opens confirm prompts (pending runs); SAV-E
// polls each known buyer and iMessages the prompt once per run (atomic dedup via
// markNotified). The buyer replies "confirm my usual" → confirmSllrRecurring.
const SLLR_NOTIFY_INTERVAL_MS = Number(process.env.SLLR_NOTIFY_INTERVAL_MS ?? 300_000);
// Guard so a slow sweep doesn't overlap with the next interval tick.
let sllrNotifySweepInFlight = false;
async function sllrNotifySweep(): Promise<number> {
  let buyers: NumberBuyer[];
  try {
    buyers = await sllrBuyers.all();
  } catch (error) {
    console.error(`[sendblue] sllr notify: list buyers failed kind=${safeErrorKind(error)}`);
    return 0;
  }
  if (!buyers.length) return 0;
  const client = new SendblueClient();
  let sent = 0;
  for (const { number, buyer } of buyers) {
    let runs;
    try {
      runs = await pendingRuns(buyer);
    } catch (error) {
      console.error(`[sendblue] sllr notify: pendingRuns failed kind=${safeErrorKind(error)}`);
      continue;
    }
    for (const run of runs) {
      try {
        await client.sendMessage(number, `🔁 ${run.summary} — order now? Reply "confirm my usual".`);
      } catch (error) {
        console.error(`[sendblue] sllr notify: send failed kind=${safeErrorKind(error)}`);
        continue; // don't mark notified — let the next sweep retry
      }
      try {
        const fresh = await sllrBuyers.markNotified(run.id);
        if (fresh) sent++; // freshly prompted this run
      } catch (error) {
        console.error(`[sendblue] sllr notify: markNotified failed kind=${safeErrorKind(error)}`);
      }
    }
  }
  if (sent) console.log(`[sendblue] sllr notify: sent ${sent} recurring prompt(s)`);
  return sent;
}

// Idempotent create-if-not-exists; awaited at startup. Failure is logged, not
// fatal — the webhook still 200s and the save path degrades gracefully.
async function ensureSendblueTable(): Promise<void> {
  try {
    await pool.query(sendblueSavedPlacesTableSql);
    await pool.query(sllrBuyerTableSql);
    await pool.query(verifiedVisitsTableSql);
    await pool.query(reviewsTableSql);
    await pool.query(userChannelsTableSql);
    await pool.query(conversationStateTableSql);
    // Hydrate durable conversation memory into the in-memory layer.
    await sendblueConversationStore.hydrate();
  } catch (error) {
    console.error(`[sendblue] ensureSendblueTable failed kind=${safeErrorKind(error)}`);
  }
}

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
  "business_photo_urls",
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
  "workflow_run_id",
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

const placeClaimFields = [
  "id",
  "place_id",
  "claim_type",
  "claim",
  "idempotency_key",
  "agent_usable_summary",
  "author_type",
  "author_public_handle",
  "author_relationship",
  "proof_level",
  "evidence_refs",
  "visibility",
  "confidence",
  "context",
  "ratings",
  "observed_at",
  "expires_or_stale_after",
  "created_at",
] as const;

const experienceReviewPatchFields = [
  "claim",
  "agent_usable_summary",
  "context",
  "ratings",
  "observed_at",
  "expires_or_stale_after",
] as const;

const claimUsageReceiptFields = [
  "id",
  "claim_id",
  "place_id",
  "consumer_agent_id",
  "consumer_user_id",
  "action",
  "outcome",
  "created_at",
] as const;

const recommendationAnalysisReceiptFields = [
  "id",
  "user_id",
  "product",
  "receipt_type",
  "agent_id",
  "capability",
  "input_hash",
  "output_hash",
  "private_payload_ref",
  "private_payload",
  "public_summary",
  "preference_signals",
  "evaluator_verdict",
  "settlement_state",
  "created_at",
] as const;

const memoryPreferenceFields = [
  "user_id",
  "preference_type",
  "normalized_value",
  "context",
  "polarity",
  "source",
  "evidence_refs",
  "evidence_count",
  "confidence",
  "status",
  "corrected_from_id",
] as const;

const recommendationOutcomeFields = [
  "user_id",
  "recommendation_id",
  "labels",
  "label_source",
  "candidate_ids",
  "place_ids",
  "memory_refs",
  "evidence_refs",
  "correction_class",
  "receipt_ref",
  "model_version",
  "retrieval_version",
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

const sharedPlaceLinkFields = [
  "code",
  "user_id",
  "source_place_id",
  "sender_display_name",
  "sender_handle",
  "source_verified_at",
  "note_consent_version",
  "payload",
  "expires_at",
] as const;

const workflowRunFields = [
  "work_order_id",
  "workflow_id",
  "listing_id",
  "user_id",
  "source_url",
  "source_type",
  "status",
  "result_type",
  "confidence",
  "evidence_tier",
  "result_evidence_refs",
  "result_candidate_refs",
  "current_attempt_no",
  "credit_reserved",
  "credit_settlement",
  "receipt_id",
  "completed_at",
] as const;

const workOrderFields = [
  "workflow_id",
  "listing_id",
  "user_id",
  "intent",
  "input_type",
  "input_ref",
  "source_url",
  "evaluator_policy_id",
  "settlement_mode",
  "budget_policy",
  "status",
] as const;

const userDecisionFields = [
  "id",
  "run_id",
  "user_id",
  "attempt_no",
  "candidate_id",
  "final_place_id",
  "action",
  "edited_payload",
  "reason",
  "reason_code",
  "idempotency_key",
  "before_hash",
  "after_hash",
] as const;

const workflowReceiptFields = [
  "run_id",
  "workflow_id",
  "workflow_version",
  "operator_id",
  "requester_id",
  "receipt_type",
  "attempt_no",
  "result_revision",
  "idempotency_key",
  "supersedes_receipt_id",
  "is_current",
  "failure_code",
  "failed_step",
  "retryable",
  "decision_id",
  "job_id",
  "agent_id",
  "model_provenance",
  "model_provenance_bucket",
  "input_hash",
  "output_hash",
  "permission_snapshot",
  "tool_trace_refs",
  "latency_ms",
  "cost_estimate",
  "failure_reason",
  "user_feedback_action",
  "quality_delta",
  "reputation_delta",
  "verdict",
  "settlement",
  "evaluator_summary",
  "evidence_refs",
  "candidate_refs",
  "receipt_hash",
  "anchor_status",
  "private_url",
  "privacy_validated",
] as const;

const clearingBlockFields = [
  "chain_namespace",
  "user_id",
  "block_number",
  "previous_block_hash",
  "merkle_root",
  "receipt_count",
  "block_hash",
  "signer_agent_id",
  "anchor_status",
  "anchor_chain",
  "anchor_tx_hash",
] as const;

const clearingBlockItemFields = [
  "block_id",
  "receipt_id",
  "receipt_hash",
  "merkle_proof",
  "position",
] as const;

const creditLedgerFields = [
  "run_id",
  "user_id",
  "attempt_no",
  "decision_id",
  "settlement_key",
  "delta",
  "reason",
  "settlement",
] as const;

const workflowReputationSnapshotFields = [
  "requester_id",
  "listing_id",
  "workflow_id",
  "workflow_version",
  "source_type",
  "operator_id",
  "model_provenance_bucket",
  "policy_version",
  "is_current",
  "run_count",
  "operational_success_count",
  "technical_failure_count",
  "confirmed_count",
  "edited_count",
  "rejected_count",
  "source_only_count",
  "refund_count",
  "median_latency_ms",
  "user_decision_coverage",
  "operational_success_rate",
  "confirmation_rate",
  "edit_rate",
  "rejection_rate",
  "technical_failure_rate",
  "pass_count",
  "partial_count",
  "fail_count",
  "confirmed_save_count",
  "user_rejection_count",
  "hallucination_report_count",
] as const;

const jsonbFields = new Set([
  "model_provenance",
  "permission_snapshot",
  "cost_estimate",
  "context",
  "evidence",
  "edited_payload",
  "input",
  "input_schema",
  "budget_policy",
  "output",
  "output_schema",
  "payload",
  "private_payload",
  "public_summary",
  "ratings",
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
    if (request.method === "GET" && url.pathname === "/health/source-recovery") {
      const status = await readSourceRecoveryConfigStatus();
      return sendJson(response, status, status.ready ? 200 : 503);
    }

    const rawSegments = url.pathname.split("/").filter(Boolean);
    if (rawSegments.join("/") === "internal/r8/pilot-metrics") {
      return await handleR8AgentPilotMetrics(request, response, url);
    }
    if (rawSegments.join("/") === "internal/friend-share/events") {
      return await handleInternalFriendShareEvents(request, response, url);
    }
    const isPublicV0 = rawSegments[0] === "public" && rawSegments[1] === "v0";
    if (isPublicV0) {
      return await handlePublicV0(request, response, rawSegments.slice(2));
    }

    const isV0 = rawSegments[0] === "v0";
    const segments = isV0 ? rawSegments.slice(1) : rawSegments;
    const [resource, id] = segments;

    if (!isV0 && request.method === "GET" && resource === "my" && id) {
      return await handleMySavesPage(response, id);
    }

    if (request.method === "GET" && resource === "referrals") {
      return await handleReferrals(request, response, id, url);
    }
    if (
      isV0
      && request.method === "POST"
      && resource === "shared-place-links"
      && id
      && segments[2] === "events"
    ) {
      return await handlePublicFriendShareEvent(request, response, id);
    }
    if (isV0 && request.method === "GET" && resource === "shared-place-links" && id && segments.length === 2) {
      return await handleSharedPlaceLinkPublic(response, id);
    }
    if (isV0 && request.method === "POST" && resource === "guest-sessions" && !id) {
      return sendJson(response, createGuestSession(guestSessionSecret), 201);
    }

    // Sendblue iMessage bot webhook (unauthenticated — no Privy). Must be
    // registered before resolveUserId(). Always returns 200 quickly.
    if (isV0 && request.method === "POST" && resource === "sendblue" && id === "webhook") {
      return await handleSendblueWebhook(request, response);
    }

    // Tokenized "my SAV-E" read: a signed link lets a phone see ITS OWN saved
    // places / verified visits / reviews — no Privy login (the number IS the
    // account, see auto-account). The data layer a web view / app consumes.
    if (isV0 && request.method === "GET" && resource === "my" && id) {
      return await handleMySaves(response, id);
    }

    if (isV0 && resource === "account-status") {
      if (segments.length > 2 || (segments.length === 2 && segments[1] !== "confirm")) {
        return sendJson(response, { error: "Not found" }, 404);
      }
      response.setHeader("Cache-Control", "private, no-store");
      response.setHeader("Vary", "Authorization");
      response.setHeader("Referrer-Policy", "no-referrer");
      if (segments[1] === "confirm") {
        if (request.method !== "POST") {
          return sendJson(response, { error: "Method not allowed" }, 405);
        }
        const body = await readJson(request, 2_048);
        const client = await pool.connect();
        try {
          const result = await evaluateAccountConfirmationRequest({
            method: request.method,
            authorizationHeader: request.headers.authorization,
            accountRefSecret: stableAccountRefSecret(process.env),
            expectedAccountRef: body.account_ref,
            verifySubject: verifiedPrivySubject,
            beginTransaction: async () => { await client.query("begin"); },
            lockSubject: (subject) => lockProfileSubject(client, subject),
            query: (sql, values) => client.query(sql, [...values] as QueryValue[]),
            createProfile: async (subject) => {
              await client.query(
                `insert into profiles (id, display_name)
                 select $1, 'SAV-E User'
                 where not exists (
                   select 1 from profiles where privy_user_id = $1
                 )
                 on conflict (id) do nothing`,
                [subject],
              );
            },
            commitTransaction: async () => { await client.query("commit"); },
            rollbackTransaction: async () => { await client.query("rollback"); },
          });
          return sendJson(response, result.body, result.statusCode);
        } finally {
          client.release();
        }
      }
      const result = await evaluateAccountStatusRequest({
        method: request.method,
        authorizationHeader: request.headers.authorization,
        accountRefSecret: stableAccountRefSecret(process.env),
        verifySubject: verifiedPrivySubject,
        query: (sql, values) => pool.query(sql, [...values] as QueryValue[]),
      });
      return sendJson(response, result.body, result.statusCode);
    }

    const userId = await resolveUserId(request);
    await ensureProfile(userId);

    if (isV0 && resource === "user-channels") {
      return await handleUserChannels(request, response, id, userId);
    }

    if (isV0 && resource === "places" && id === "recommend-by-claims") {
      return await handleRecommendByClaims(request, response, userId);
    }
    if (isV0 && resource === "recommendation-analysis-receipts") {
      return await handleRecommendationAnalysisReceipts(request, response, userId);
    }
    if (isV0 && resource === "memory-preferences") {
      return await handleMemoryPreferences(request, response, id, segments[2], userId);
    }
    if (isV0 && resource === "recommendation-outcomes") {
      return await handleRecommendationOutcomes(request, response, userId);
    }
    if (isV0 && resource === "friend-share-events") {
      return await handleFriendShareEvents(request, response, url, userId);
    }
    if (isV0 && resource === "claims" && id === "usage-receipts") {
      return await handleAuthenticatedClaimUsageReceipts(request, response, userId);
    }
    if (isV0 && resource === "exports" && id === "trek-kml") {
      return await handleTrekKmlExport(request, response, userId);
    }
    if (isV0 && resource === "llm") {
      return await handleLLMProxy(request, response, segments.slice(1));
    }
    if (isV0 && resource === "places" && id && segments[2] === "verified-claims") {
      return await handlePlaceVerifiedClaims(request, response, id, segments[3], url, userId);
    }
    if (isV0 && resource === "places" && id && segments[2] === "maat-analysis") {
      return await handlePlaceMaatAnalysis(request, response, id, url, userId);
    }
    if (isV0 && resource === "places" && id && segments[2] === "trust-summary") {
      return await handlePlaceTrustSummary(request, response, id, userId);
    }
    if (resource === "places" && id && segments[2] === "visibility") {
      return await handlePlaceVisibility(request, response, id, userId);
    }
    if (resource === "places") return await handlePlaces(request, response, id, userId);
    if (resource === "trips") return await handleTrips(request, response, id, userId);
    if (resource === "profile") return await handleProfile(request, response, userId);
    if (resource === "follows") {
      return await handleFollows(request, response, id, url, userId, isV0);
    }
    if (isV0 && resource === "shared-place-links") return await handleSharedPlaceLinks(request, response, id, userId);
    if (isV0 && resource === "workflows") return await handleWorkflows(request, response, segments.slice(1), userId);
    if (resource === "social" && id === "signals") return await handleSocialSignals(request, response, url, userId);
    if (resource === "memory") {
      return await handleMemory(request, response, segments.slice(1), url, userId);
    }
    if (resource === "agents") {
      return await handleAgents(request, response, segments.slice(1), url, userId);
    }

    return sendJson(response, { error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof ApiError
      ? error.status
      : error instanceof WorkflowContractError
        ? 400
        : error instanceof WorkflowConflictError
          ? 409
          : error instanceof SyntaxError
            ? 400
            : 500;
    const message = error instanceof SyntaxError
      ? "Invalid JSON body"
      : status < 500 && error instanceof Error
        ? error.message
        : "Internal server error";
    return sendJson(response, { error: message }, status);
  }
}).listen(Number(process.env.PORT ?? 3000), () => {
  console.log(`SAV-E backend listening on ${process.env.PORT ?? 3000}`);
  void ensureSendblueTable();
  // Recurring confirm-prompt notifier (in-process v0). Set SLLR_NOTIFY_INTERVAL_MS=0
  // to disable (e.g. when an external cron drives it instead).
  if (SLLR_NOTIFY_INTERVAL_MS > 0) {
    const timer = setInterval(() => {
      if (sllrNotifySweepInFlight) return; // previous sweep still running
      sllrNotifySweepInFlight = true;
      void sllrNotifySweep().finally(() => {
        sllrNotifySweepInFlight = false;
      });
    }, SLLR_NOTIFY_INTERVAL_MS);
    timer.unref();
    console.log(`[sendblue] sllr recurring notifier every ${Math.round(SLLR_NOTIFY_INTERVAL_MS / 1000)}s`);
  }
});

async function resolveSendblueMemoryKey(fromNumber: string): Promise<string> {
  const normalized = normalizeChannelUserId(fromNumber);
  if (!normalized) return fromNumber;
  // 1. Already bound to a SAV-E profile? Use it.
  const { rows } = await pool.query(
    `select uc.profile_id, p.privy_user_id
     from user_channels uc
     join profiles p on p.id = uc.profile_id
     where uc.channel in ('sendblue', 'imessage', 'sms')
       and uc.verified_at is not null
       and (uc.channel_user_id = $1 or uc.phone_e164 = $1)
     order by case uc.channel when 'sendblue' then 0 when 'imessage' then 1 else 2 end
     limit 1`,
    [normalized],
  );
  if (typeof rows[0]?.profile_id === "string") {
    await ensurePrivyPhoneProfile(normalized, rows[0].profile_id, rows[0].privy_user_id);
    return rows[0].profile_id;
  }

  // 2. First time this number texts us → texting IS registration. Auto-create a
  //    SAV-E profile + a VERIFIED iMessage binding (the message was delivered
  //    FROM this number via Sendblue, so the channel is verified by possession).
  //    The profile id is the normalized phone, so the memory key is UNCHANGED
  //    (no re-keying of existing sendblue_* data) — we just give the number a
  //    real account it previously lacked. Zero login. Merging into a pre-existing
  //    app (Privy) account is a separate, opt-in step.
  try {
    await ensureProfile(normalized);
    await pool.query(
      `insert into user_channels (profile_id, channel, channel_user_id, phone_e164, verified_at, updated_at)
       values ($1, 'imessage', $1, $1, now(), now())
       on conflict (channel, channel_user_id)
       do update set verified_at = coalesce(user_channels.verified_at, now()), updated_at = now()`,
      [normalized],
    );
    await ensurePrivyPhoneProfile(normalized, normalized, null);
    console.log(`[sendblue] auto-created SAV-E account for inbound number`);
  } catch (error) {
    console.error(`[sendblue] auto-create account failed kind=${safeErrorKind(error)}`);
  }
  // Memory key is the phone either way (profile id == phone), so existing memory
  // is preserved even if the insert above raced or failed.
  return normalized;
}

function normalizeChannelUserId(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

// Signed private link for a phone's own SAV-E data. A stable secret keeps the
// link valid across deploys (set SAVE_MY_SAVES_SECRET on Railway).
const mySavesSecret = process.env.SAVE_MY_SAVES_SECRET?.trim() || guestSessionSecret;

export function signMyToken(phone: string): string {
  const mac = createHmac("sha256", mySavesSecret).update(phone).digest("base64url");
  return `${Buffer.from(phone).toString("base64url")}.${mac}`;
}

function verifyMyToken(token: string): string | null {
  const [b64, mac] = token.split(".");
  if (!b64 || !mac) return null;
  let phone: string;
  try {
    phone = Buffer.from(b64, "base64url").toString("utf8");
  } catch {
    return null;
  }
  const expected = createHmac("sha256", mySavesSecret).update(phone).digest("base64url");
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  return phone;
}

/**
 * Read-only "my SAV-E" payload for a tokenized phone link: the account's saved
 * places + verified visits + reviews. This is the unified data layer a web view
 * or the app reads (step 3) — everything is keyed by the phone (= the account).
 */
async function handleMySaves(response: ServerResponse, token: string): Promise<void> {
  const phone = verifyMyToken(token);
  if (!phone) return sendJson(response, { error: "Invalid or expired link" }, 403);
  return sendJson(response, await readMySavesPayload(phone), 200);
}

async function readMySavesPayload(phone: string): Promise<MySavesPayload> {
  const [places, visits, reviews] = await Promise.all([
    sendbluePlaceStore.list(phone, 100).catch(() => []),
    sendblueReceiptStore.list(phone, 100).catch(() => []),
    sendblueReviewStore.list(phone, 100).catch(() => []),
  ]);
  return {
    places,
    visits,
    reviews,
    counts: { places: places.length, visits: visits.length, reviews: reviews.length },
  };
}

async function handleMySavesPage(response: ServerResponse, token: string): Promise<void> {
  const phone = verifyMyToken(token);
  if (!phone) {
    return sendHtml(response, "<!doctype html><title>Invalid SAV-E link</title><p>Invalid or expired SAV-E link.</p>", 403);
  }
  return sendHtml(response, renderMySavesPage(await readMySavesPayload(phone)), 200);
}

function mySavesLink(phone: string): string {
  const configuredBase =
    process.env.SAVE_MY_SAVES_BASE_URL?.trim() ||
    "https://sav-e-app.vercel.app";
  return `${configuredBase.replace(/\/+$/, "")}/my/${signMyToken(phone)}`;
}

async function handleUserChannels(
  request: IncomingMessage,
  response: ServerResponse,
  channelId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !channelId) {
    const { rows } = await pool.query(
      `select id, channel, channel_user_id, phone_e164, verified_at, created_at, updated_at
       from user_channels
       where profile_id = $1
       order by created_at desc`,
      [userId],
    );
    return sendJson(response, rows.map(formatDates));
  }

  if (request.method === "POST" && !channelId) {
    const body = await readJson(request);
    const channelRaw = typeof body.channel === "string" ? body.channel.trim().toLowerCase() : "sendblue";
    const supportedChannels = new Set(["imessage", "sms", "line", "whatsapp", "sendblue"]);
    if (!supportedChannels.has(channelRaw)) {
      return sendJson(response, { error: "Unsupported channel" }, 400);
    }
    const channel = channelRaw;
    const channelUserId = normalizeChannelUserId(body.channel_user_id ?? body.phone ?? body.phone_e164);
    if (!channelUserId) return sendJson(response, { error: "channel_user_id or phone is required" }, 400);
    const phone = normalizeChannelUserId(body.phone_e164 ?? body.phone) || null;
    const { rows } = await pool.query(
      `insert into user_channels (profile_id, channel, channel_user_id, phone_e164, verified_at, updated_at)
       values ($1, $2, $3, $4, null, now())
       on conflict (channel, channel_user_id) do update
         set phone_e164 = coalesce(excluded.phone_e164, user_channels.phone_e164),
             updated_at = now()
       where user_channels.profile_id = excluded.profile_id
       returning id, profile_id, channel, channel_user_id, phone_e164, verified_at, created_at, updated_at`,
      [userId, channel, channelUserId, phone],
    );
    if (!rows[0]) return sendJson(response, { error: "Channel is already linked to another profile" }, 409);
    return sendJson(response, formatDates(rows[0]), 201);
  }

  if (request.method === "DELETE" && channelId) {
    const { rows } = await pool.query(
      `delete from user_channels where id = $1 and profile_id = $2 returning id`,
      [channelId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "User channel not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported user-channels route" }, 405);
}

// Sendblue inbound webhook. Spike: synchronous fetch -> caption -> venue ->
// reply, always returns 200 to Sendblue (even on internal errors) so the
// webhook is never retried/disabled. No Privy auth on this route.
async function handleSendblueWebhook(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  let body: Record<string, unknown>;
  try {
    body = await readJson(request);
  } catch (error) {
    console.error(`[sendblue] readJson failed kind=${safeErrorKind(error)}`);
    return sendJson(response, { ok: true }, 200);
  }

  // Keep operational diagnostics metadata-only. Inbound bodies can contain
  // phone numbers, private messages, media URLs, and location payloads.
  console.log(`[sendblue] inbound keys=${Object.keys(body).sort().join(",")} message_type=${stringValue(body.message_type) ?? "unknown"}`);

  // Respond 200 IMMEDIATELY so Sendblue's webhook never times out on a slow
  // link fetch / Gemini call; process + reply in the background (fire-and-forget).
  sendJson(response, { ok: true }, 200);

  void (async () => {
    try {
      const client = new SendblueClient();
      // Inject the LLM so no-URL messages get an agentic, grounded answer over
      // the user's saved places (not just keyword-matched intents).
      const result = await processSendblueInbound(body, {
        client,
        store: sendbluePlaceStore,
        receiptStore: sendblueReceiptStore,
        reviewStore: sendblueReviewStore,
        conversation: sendblueConversationStore,
        gemini: defaultGeminiText,
        placesSearch: defaultPlacesSearch,
        placesReviews: defaultPlacesReviews,
        order: placeSllrOrder,
        setRecurring: setSllrRecurring,
        confirmRecurring: confirmSllrRecurring,
        geocode: defaultGeocode,
        resolveMemoryKey: resolveSendblueMemoryKey,
        mySavesUrl: mySavesLink,
      });
      console.log(`[sendblue] done replied=${result.replied}`);
    } catch (error) {
      console.error(`[sendblue] background processing error kind=${safeErrorKind(error)}`);
    }
  })();
}

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
    const rawBody = await readJson(request);
    let friendShareCode: string | undefined;
    try {
      friendShareCode = friendShareCodeFromPlaceCreate(rawBody);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid friend share code";
      return sendJson(response, { error: message }, 400);
    }

    const body = withOwner(rawBody, userId);
    if (friendShareCode) {
      const link = await friendShareLinkForEvent(friendShareCode);
      if (friendShareLinkIsExpired(link)) {
        return sendJson(response, { error: "Shared place link expired" }, 410);
      }
      if (isSelfFriendShareRecipient(link.user_id, userId)) {
        return sendJson(response, { error: "Sender cannot save their own friend share receipt" }, 409);
      }
      if (!recipientPlaceMatchesSharedPayload(body, link.payload)) {
        return sendJson(response, { error: "Place does not match the shared place" }, 409);
      }

      const receiptBody: JsonBody = {
        ...body,
        origin_shared_place_link_id: link.id,
      };
      const insert = buildInsert(
        "places",
        receiptBody,
        [...placeFields, "user_id", "origin_shared_place_link_id"],
      );
      const client = await pool.connect();
      try {
        await client.query("begin");
        const { rows } = await client.query(
          `${insert.sql}
           ${friendSharePlaceOriginConflictClause}
           returning *, (xmax = 0) as friend_share_receipt_created`,
          insert.values,
        );
        const result = asObject(rows[0]);
        const { friend_share_receipt_created: created, ...canonicalPlace } = result;
        const terminalEvent = created === true
          ? "friend_share_saved"
          : "friend_share_duplicate_blocked";
        await client.query(
          `insert into friend_share_events (
             shared_place_link_id,
             sender_user_id,
             recipient_user_id,
             recipient_place_id,
             event_type,
             surface
           )
           values ($1, $2, $3, $4, $5, 'server')
           on conflict do nothing`,
          [link.id, link.user_id, userId, canonicalPlace.id, terminalEvent],
        );
        await client.query("commit");
        return sendJson(response, {
          place: formatPlace(canonicalPlace),
          outcome: created === true ? "saved" : "already_saved",
        }, 201);
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }
    }

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

async function handlePublicV0(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
): Promise<void> {
  const [resource, id] = segments;

  if (resource === "cards" && id) {
    return await handlePublicPlaceCard(request, response, id);
  }
  if (resource === "claim-usage-receipts") {
    return await handlePublicClaimUsageReceipts(request, response);
  }

  return sendJson(response, { error: "Unsupported public v0 route" }, 404);
}

async function handlePublicPlaceCard(
  request: IncomingMessage,
  response: ServerResponse,
  cardId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported public card route" }, 405);

  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as public_visibility,
       owner.handle as owner_handle
     from places p
     join place_visibility pv on pv.place_id = p.id
     join profiles owner on owner.id = p.user_id
     where p.id = $1
       and pv.visibility in ('public_link', 'public_guide')
     limit 1`,
    [cardId],
  );
  if (!rows[0]) return sendJson(response, { error: "Public card not found" }, 404);

  const { rows: claims } = await pool.query(
    `select
       pc.*,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where pc.place_id = $1
       and pc.visibility in ('public', 'link_shared')
       and (pc.expires_or_stale_after is null or pc.expires_or_stale_after >= now())
     order by pc.created_at desc`,
    [cardId],
  );

  return sendJson(response, buildPublicPlaceCard(formatDates(rows[0]), claims.map((claim) => formatDates(claim))));
}

async function handlePublicClaimUsageReceipts(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported usage receipt route" }, 405);

  let body: JsonBody;
  try {
    body = normalizeUsageReceiptCreate(await readJson(request));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid usage receipt";
    return sendJson(response, { error: message }, 400);
  }

  const claim = await publicClaimForReceipt(String(body.claim_id));
  body.place_id = claim.place_id;
  const insert = buildInsert("claim_usage_receipts", body, claimUsageReceiptFields);
  const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
  return sendJson(response, formatDates(rows[0]), 201);
}

async function handleAuthenticatedClaimUsageReceipts(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported usage receipt route" }, 405);

  let body: JsonBody;
  try {
    body = normalizeUsageReceiptCreate(await readJson(request));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid usage receipt";
    return sendJson(response, { error: message }, 400);
  }

  const claim = await ownedClaimForReceipt(String(body.claim_id), userId);
  body.place_id = claim.place_id;
  body.consumer_user_id = userId;
  const insert = buildInsert("claim_usage_receipts", body, claimUsageReceiptFields);
  const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
  return sendJson(response, formatDates(rows[0]), 201);
}

async function handlePlaceVerifiedClaims(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  claimId: string | undefined,
  url: URL,
  userId: string,
): Promise<void> {
  await ensureOwnedPlaceReference(placeId, userId);

  if (request.method === "GET" && !claimId) {
    const includePrivateEvidence = url.searchParams.get("includePrivateEvidence") === "true" ||
      url.searchParams.get("include_private_evidence") === "true";
    const claims = await placeClaimsForPlace(placeId, userId, {
      proofLevelMin: url.searchParams.get("proofLevelMin") ?? url.searchParams.get("proof_level_min"),
      claimType: url.searchParams.get("claimType") ?? url.searchParams.get("claim_type"),
      visibility: url.searchParams.get("visibility"),
      relationship: url.searchParams.get("relationship"),
      freshness: url.searchParams.get("freshness"),
    });

    return sendJson(response, {
      place_id: placeId,
      claims: claims.map((claim) => formatPlaceClaim(formatDates(claim), includePrivateEvidence)),
    });
  }

  if (request.method === "POST" && !claimId) {
    let body: JsonBody;
    try {
      body = normalizePlaceClaimCreate(await readJson(request), placeId, userId);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid claim";
      return sendJson(response, { error: message }, 400);
    }

    const insert = buildInsert("place_claims", body, [...placeClaimFields, "user_id"]);
    if (body.claim_type !== experienceReviewClaimType) {
      const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
      return sendJson(response, formatPlaceClaim(formatDates(rows[0]), true), 201);
    }

    const { rows } = await pool.query(
      `${insert.sql}
       on conflict (user_id, place_id, idempotency_key)
       where claim_type = 'experience_review' and idempotency_key is not null
       do nothing
       returning *`,
      insert.values,
    );
    if (rows[0]) return sendJson(response, formatPlaceClaim(formatDates(rows[0]), true), 201);

    const { rows: replayRows } = await pool.query(
      `select * from place_claims
       where user_id = $1 and place_id = $2 and claim_type = 'experience_review' and idempotency_key = $3
       limit 1`,
      [userId, placeId, String(body.idempotency_key)],
    );
    if (!replayRows[0]) throw new Error("Experience review idempotency replay was not found");
    return sendJson(response, formatPlaceClaim(formatDates(replayRows[0]), true), 200);
  }

  if (request.method === "PATCH" && claimId) {
    const scope = experienceReviewMutationScope(placeId, claimId, userId);
    const { rows: existingRows } = await pool.query(
      `select * from place_claims where ${scope.clause} limit 1`,
      scope.values,
    );
    if (!existingRows[0]) return sendJson(response, { error: "Experience review not found" }, 404);

    let patch: JsonBody;
    try {
      patch = normalizeExperienceReviewPatch(await readJson(request), asObject(existingRows[0]));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid experience review";
      return sendJson(response, { error: message }, 400);
    }
    const update = buildUpdate("place_claims", patch, experienceReviewPatchFields);
    if (!update) return sendJson(response, { error: "No writable experience fields" }, 400);
    const updateScope = experienceReviewMutationScope(placeId, claimId, userId, update.values.length);
    const { rows } = await pool.query(
      `${update.sql}, updated_at = now() where ${updateScope.clause} returning *`,
      [...update.values, ...updateScope.values],
    );
    if (!rows[0]) return sendJson(response, { error: "Experience review not found" }, 404);
    return sendJson(response, formatPlaceClaim(formatDates(rows[0]), true));
  }

  if (request.method === "DELETE" && claimId) {
    const scope = experienceReviewMutationScope(placeId, claimId, userId);
    const { rows } = await pool.query(
      `delete from place_claims where ${scope.clause} returning id`,
      scope.values,
    );
    if (!rows[0]) return sendJson(response, { error: "Experience review not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported verified claims route" }, 405);
}

async function handlePlaceMaatAnalysis(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported maat analysis route" }, 405);

  const place = await ownedPlaceForAnalysis(placeId, userId);
  const claims = await placeClaimsForPlace(placeId, userId);
  const includePrivateEvidence = url.searchParams.get("includePrivateEvidence") === "true" ||
    url.searchParams.get("include_private_evidence") === "true";
  const includePublicWeb = url.searchParams.get("includePublicWeb") === "true" ||
    url.searchParams.get("include_public_web") === "true";
  const maxCitedClaims = Number(url.searchParams.get("maxCitedClaims") ?? url.searchParams.get("max_cited_claims") ?? 3);
  const formattedClaims = claims.map((claim) => formatDates(claim));
  const analysis = buildMaatPlaceAnalysis(place, formattedClaims, {
    includePrivateEvidence,
    maxCitedClaims,
  });
  const enrichedAnalysis = includePublicWeb
    ? await enrichMaatPlaceAnalysisWithPublicWeb({
      place,
      claims: formattedClaims,
      analysis,
      includePrivateEvidence,
    })
    : analysis;
  return sendJson(response, enrichedAnalysis);
}

async function handlePlaceTrustSummary(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported trust summary route" }, 405);

  await ensureOwnedPlaceReference(placeId, userId);
  const claims = await placeClaimsForPlace(placeId, userId);
  return sendJson(response, buildTrustSummary(placeId, claims.map((claim) => formatDates(claim))));
}

async function handleRecommendByClaims(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported recommend-by-claims route" }, 405);

  const recommendationRequest = normalizeRecommendationRequest(await readJson(request));
  const proofLevels = proofLevelsAtLeast(recommendationRequest.proofLevelMin ?? "user_confirmed_place");
  const { rows } = await pool.query(
    `select
       pc.*,
       p.name as place_name,
       p.address as place_address,
       p.category as place_category,
       p.status as place_status,
       p.rating as place_rating,
       p.google_rating as place_google_rating,
       p.price_range as place_price_range,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     join places p on p.id = pc.place_id
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where pc.user_id = $1
       and p.user_id = $1
       and pc.proof_level = any($2::text[])
     order by pc.created_at desc
     limit 200`,
    [userId, proofLevels],
  );

  const recommendationOutput = recommendPlacesByClaims(rows.map((row) => formatDates(row)), recommendationRequest);
  const receiptDraft = buildRecommendationAnalysisReceiptDraft({
    userId,
    request: recommendationRequest as JsonBody,
    output: recommendationOutput,
  });
  const receiptInsert = buildInsert(
    "recommendation_analysis_receipts",
    receiptDraft,
    recommendationAnalysisReceiptFields,
  );
  const { rows: receiptRows } = await pool.query(`${receiptInsert.sql} returning *`, receiptInsert.values);

  return sendJson(response, {
    ...recommendationOutput,
    agent_shack_receipt_envelope: envelopeForRecommendationAnalysisReceipt(formatDates(receiptRows[0])),
  });
}

async function handleRecommendationAnalysisReceipts(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported recommendation analysis receipt route" }, 405);
  }

  const body = await readJson(request, recommendationAnalysisReceiptPayloadMaxBytes);
  let payload;
  try {
    payload = normalizeRecommendationAnalysisReceiptPayload(body);
  } catch (error) {
    if (error instanceof RecommendationAnalysisReceiptPayloadError) {
      const status = error.message.includes("too large") ? 413 : 400;
      return sendJson(response, { error: error.message }, status);
    }
    throw error;
  }
  const receiptDraft = buildRecommendationAnalysisReceiptDraft({
    userId,
    agentId: payload.agentId,
    request: payload.request,
    output: payload.output,
  });
  const receiptInsert = buildInsert(
    "recommendation_analysis_receipts",
    receiptDraft,
    recommendationAnalysisReceiptFields,
  );
  const { rows } = await pool.query(`${receiptInsert.sql} returning *`, receiptInsert.values);
  const row = formatDates(rows[0]);

  return sendJson(response, {
    id: row.id,
    envelope: envelopeForRecommendationAnalysisReceipt(row),
    full_payload_json: JSON.stringify(row.private_payload),
  }, 201);
}

async function handleR8AgentPilotMetrics(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
): Promise<void> {
  response.setHeader("Cache-Control", "private, no-store");
  if (request.method !== "GET") {
    return sendJson(response, { error: "Unsupported R8 pilot metrics route" }, 405);
  }

  const configuredToken = process.env.SAVE_INTERNAL_AGENT_TOKEN?.trim();
  const authorization = authorizeR8AgentMetrics(configuredToken, request.headers.authorization);
  if (authorization === "unavailable") {
    return sendJson(response, { error: "Internal agent metrics are not configured" }, 503);
  }
  if (authorization === "unauthorized") {
    return sendJson(response, { error: "Unauthorized" }, 401);
  }

  let query;
  try {
    query = normalizeR8AgentMetricsQuery(url.searchParams);
  } catch (error) {
    if (error instanceof R8AgentMetricsQueryError) {
      return sendJson(response, { error: error.message }, 400);
    }
    throw error;
  }

  const generatedAt = new Date();
  const since = new Date(generatedAt.getTime() - query.days * 24 * 60 * 60 * 1000);
  const { rows } = await pool.query<R8AgentMetricsRow>(r8AgentMetricsSql, [
    since,
    generatedAt,
    r8AgentMetricsFailureLabels,
  ]);
  const metrics = aggregateR8PilotMetrics({
    rows,
    token: configuredToken as string,
    days: query.days,
    limit: query.limit,
    generatedAt: generatedAt.toISOString(),
  });
  console.info(
    `[r8-pilot-metrics] access days=${query.days} limit=${query.limit} cohort_users=${metrics.cohort.users_total} returned_users=${metrics.cohort.users_returned} starts_at=${metrics.window.starts_at} generated_at=${metrics.window.generated_at}`,
  );
  return sendJson(response, metrics);
}

async function handleInternalFriendShareEvents(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
): Promise<void> {
  response.setHeader("Cache-Control", "private, no-store");
  if (request.method !== "GET") {
    return sendJson(response, { error: "Unsupported friend share event metrics route" }, 405);
  }

  const configuredToken = process.env.SAVE_INTERNAL_AGENT_TOKEN?.trim();
  const authorization = authorizeR8AgentMetrics(configuredToken, request.headers.authorization);
  if (authorization === "unavailable") {
    return sendJson(response, { error: "Internal agent metrics are not configured" }, 503);
  }
  if (authorization === "unauthorized") {
    return sendJson(response, { error: "Unauthorized" }, 401);
  }

  let query;
  try {
    query = normalizeR8AgentMetricsQuery(url.searchParams);
  } catch (error) {
    if (error instanceof R8AgentMetricsQueryError) {
      return sendJson(response, { error: error.message }, 400);
    }
    throw error;
  }

  const code = url.searchParams.get("code")?.trim();
  if (code && !/^[A-Za-z0-9_-]{6,32}$/.test(code)) {
    return sendJson(response, { error: "code is invalid" }, 400);
  }

  const generatedAt = new Date();
  const since = new Date(generatedAt.getTime() - query.days * 24 * 60 * 60 * 1000);
  const filters = [
    "event.created_at >= $1",
    "event.created_at <= $2",
    friendShareVerifiedCohortPredicate,
  ];
  const values: QueryValue[] = [since, generatedAt];
  if (code) {
    values.push(code);
    filters.push(`link.code = $${values.length}`);
  }
  values.push(query.limit);
  const limitPlaceholder = `$${values.length}`;
  const exclusiveOpenFailure = friendShareExclusiveOpenFailurePredicate(
    "event",
    "terminal_event",
    { startsAt: "$1", endsAt: "$2" },
  );

  const { rows: shareRows } = await pool.query<FriendShareShareMetricsRow>(
    `select
       link.id as link_id,
       event.sender_user_id,
       count(*)::int as events_total,
       (count(*) filter (where event.event_type = 'friend_share_receipt_opened'))::int as receipt_opened,
       (count(*) filter (where event.event_type = 'friend_share_save_tapped'))::int as save_tapped,
       (count(*) filter (where event.event_type = 'friend_share_saved'))::int as saved,
       (count(*) filter (where event.event_type = 'friend_share_duplicate_blocked'))::int as duplicate_blocked,
       (count(*) filter (where ${exclusiveOpenFailure}))::int as open_failed,
       (count(distinct event.recipient_user_id))::int as identified_recipient_sessions,
       (count(distinct event.recipient_user_id) filter (
         where left(event.recipient_user_id, 6) <> 'guest_'
       ))::int as account_recipient_users,
       (count(distinct event.recipient_user_id) filter (
         where left(event.recipient_user_id, 6) = 'guest_'
       ))::int as guest_recipient_sessions,
       (count(distinct event.recipient_user_id) filter (
         where event.event_type in ('friend_share_saved', 'friend_share_duplicate_blocked')
           and left(event.recipient_user_id, 6) <> 'guest_'
       ))::int as account_recipient_users_succeeded,
       (count(distinct event.recipient_user_id) filter (
         where event.event_type in ('friend_share_saved', 'friend_share_duplicate_blocked')
           and left(event.recipient_user_id, 6) = 'guest_'
       ))::int as guest_recipient_sessions_succeeded,
       (count(distinct event.recipient_user_id) filter (
         where ${exclusiveOpenFailure}
           and left(event.recipient_user_id, 6) <> 'guest_'
       ))::int as account_recipient_users_open_failed,
       (count(distinct event.recipient_user_id) filter (
         where ${exclusiveOpenFailure}
           and left(event.recipient_user_id, 6) = 'guest_'
       ))::int as guest_recipient_sessions_open_failed,
       (count(*) filter (where event.recipient_user_id is null))::int as anonymous_events,
       max(event.created_at) as last_activity_at
     from friend_share_events event
     join shared_place_links link on link.id = event.shared_place_link_id
     where ${filters.join(" and ")}
     group by link.id, event.sender_user_id
     order by last_activity_at desc, link.id
     limit ${limitPlaceholder}`,
    values,
  );

  const recipientValues = values.slice(0, -1);
  recipientValues.push(query.limit);
  const recipientLimitPlaceholder = `$${recipientValues.length}`;
  const { rows: recipientRows } = await pool.query<FriendShareRecipientMetricsRow>(
    `select
       link.id as link_id,
       event.recipient_user_id,
       (count(*) filter (where event.event_type = 'friend_share_receipt_opened'))::int as receipt_opened,
       (count(*) filter (where event.event_type = 'friend_share_save_tapped'))::int as save_tapped,
       (count(*) filter (where event.event_type = 'friend_share_saved'))::int as saved,
       (count(*) filter (where event.event_type = 'friend_share_duplicate_blocked'))::int as duplicate_blocked,
       (count(*) filter (where ${exclusiveOpenFailure}))::int as open_failed,
       max(event.created_at) as last_activity_at
     from friend_share_events event
     join shared_place_links link on link.id = event.shared_place_link_id
     where ${filters.join(" and ")}
       and event.recipient_user_id is not null
     group by link.id, event.recipient_user_id
     order by last_activity_at desc, link.id, event.recipient_user_id
     limit ${recipientLimitPlaceholder}`,
    recipientValues,
  );

  return sendJson(response, {
    window: {
      days: query.days,
      starts_at: since.toISOString(),
      generated_at: generatedAt.toISOString(),
    },
    shares: friendShareShareMetrics(shareRows, configuredToken as string),
    recipients: friendShareRecipientMetrics(recipientRows, configuredToken as string),
    definitions: {
      success: "An identified account or guest session saved the place or confirmed it was already saved.",
      failure: "An identified account or guest session recorded an open failure and no save or duplicate receipt in this window.",
      unresolved: "The recipient opened or tapped save without a saved, duplicate, or failure receipt in this window.",
      demand_proof: "Use account_recipient_users and account_recipient_users_succeeded for the account-user conversion threshold; guest sessions are reported separately.",
      privacy: "Share and user references are token-scoped pseudonyms; raw link codes, display names, note text, and precise coordinates are not returned.",
    },
  });
}

async function handleMemoryPreferences(
  request: IncomingMessage,
  response: ServerResponse,
  preferenceId: string | undefined,
  action: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !preferenceId) {
    const { rows } = await pool.query(
      "select * from memory_preferences where user_id = $1 order by updated_at desc",
      [userId],
    );
    return sendJson(response, rows.map((row) => formatDates(asObject(row))));
  }

  try {
    if (request.method === "POST" && !preferenceId) {
      const normalized = normalizePreferenceCreate(await readJson(request));
      const insert = buildInsert(
        "memory_preferences",
        { ...normalized, user_id: userId },
        memoryPreferenceFields,
      );
      const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
      return sendJson(response, formatDates(asObject(rows[0])), 201);
    }

    if (request.method === "PATCH" && preferenceId && !action) {
      const patch = normalizePreferencePatch(await readJson(request));
      const update = buildUpdate("memory_preferences", patch, memoryPreferenceFields);
      if (!update) return sendJson(response, { error: "No writable fields" }, 400);
      const { rows } = await pool.query(
        `${update.sql}, updated_at = now() where id = $${update.values.length + 1} and user_id = $${update.values.length + 2} returning *`,
        [...update.values, preferenceId, userId],
      );
      if (!rows[0]) return sendJson(response, { error: "Preference not found" }, 404);
      return sendJson(response, formatDates(asObject(rows[0])));
    }

    if (request.method === "POST" && preferenceId && action === "corrections") {
      const normalized = normalizePreferenceCreate({ ...await readJson(request), source: "explicit", status: "active" });
      const client = await pool.connect();
      try {
        await client.query("begin");
        const { rows: previousRows } = await client.query(
          "update memory_preferences set status = 'corrected', updated_at = now() where id = $1 and user_id = $2 and status <> 'removed' returning id",
          [preferenceId, userId],
        );
        if (!previousRows[0]) {
          await client.query("rollback");
          return sendJson(response, { error: "Preference not found" }, 404);
        }
        const insert = buildInsert(
          "memory_preferences",
          { ...normalized, user_id: userId, corrected_from_id: preferenceId },
          memoryPreferenceFields,
        );
        const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
        await client.query("commit");
        return sendJson(response, formatDates(asObject(rows[0])), 201);
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }
    }
  } catch (error) {
    if (error instanceof MemoryContractError) return sendJson(response, { error: error.message }, 400);
    throw error;
  }

  return sendJson(response, { error: "Unsupported memory preference route" }, 405);
}

async function handleRecommendationOutcomes(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const { rows } = await pool.query(
      "select * from recommendation_outcomes where user_id = $1 order by created_at desc limit 200",
      [userId],
    );
    return sendJson(response, rows.map((row) => formatDates(asObject(row))));
  }
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported recommendation outcome route" }, 405);
  }

  try {
    const normalized = normalizeRecommendationOutcome(await readJson(request));
    for (const placeId of normalized.place_ids as string[]) await ensureOwnedPlaceReference(placeId, userId);
    for (const candidateId of normalized.candidate_ids as string[]) await ensureOwnedCandidateReference(candidateId, userId);
    const insert = buildInsert(
      "recommendation_outcomes",
      { ...normalized, user_id: userId },
      recommendationOutcomeFields,
    );
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatDates(asObject(rows[0])), 201);
  } catch (error) {
    if (error instanceof MemoryContractError) return sendJson(response, { error: error.message }, 400);
    throw error;
  }
}

async function handleLLMProxy(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
): Promise<void> {
  const [providerAction] = segments;
  if (providerAction !== "gemini-generate-content") {
    return sendJson(response, { error: "Unsupported LLM route" }, 404);
  }
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported LLM route" }, 405);
  }

  const apiKey = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_GEMINI_API_KEY;
  if (!apiKey) throw new ApiError(503, "Gemini proxy is not configured");

  const body = await readJson(request, geminiProxyRequestMaxBytes);
  const model = geminiProxyModel(body.model);
  const geminiBody = geminiProxyBody(body);
  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": "SAV-E backend Gemini proxy/1.0",
      },
      body: JSON.stringify(geminiBody),
      redirect: "manual",
      signal: AbortSignal.timeout(20_000),
    },
  );

  if (upstream.status >= 300 && upstream.status < 400) {
    throw new ApiError(502, "Gemini proxy blocked redirect response");
  }
  const raw = await boundedResponseBuffer(upstream, geminiProxyResponseMaxBytes);
  if (!upstream.ok) {
    return sendJson(response, { error: "Gemini upstream request failed", status: upstream.status }, 502);
  }
  const parsed = JSON.parse(new TextDecoder().decode(raw));
  return sendJson(response, parsed);
}

function geminiProxyModel(value: unknown): string {
  const model = typeof value === "string" && value.trim() ? value.trim() : "gemini-3.5-flash";
  const allowed = new Set((process.env.SAVE_GEMINI_PROXY_MODELS ?? "gemini-3.5-flash")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean));
  if (!allowed.has(model)) throw new ApiError(400, "Unsupported Gemini model");
  return model;
}

function geminiProxyBody(body: JsonBody): JsonBody {
  const contents = body.contents;
  if (!Array.isArray(contents) || contents.length === 0) throw new ApiError(400, "contents is required");
  const result: JsonBody = { contents };
  if (body.generationConfig && typeof body.generationConfig === "object" && !Array.isArray(body.generationConfig)) {
    result.generationConfig = body.generationConfig as JsonBody;
  }
  if (body.systemInstruction && typeof body.systemInstruction === "object" && !Array.isArray(body.systemInstruction)) {
    result.systemInstruction = body.systemInstruction as JsonBody;
  }
  return result;
}

async function placeClaimsForPlace(
  placeId: string,
  userId: string,
  filters: {
    proofLevelMin?: string | null;
    claimType?: string | null;
    visibility?: string | null;
    relationship?: string | null;
    freshness?: string | null;
  } = {},
): Promise<JsonBody[]> {
  const values: QueryValue[] = [placeId, userId];
  const where = ["pc.place_id = $1", "pc.user_id = $2"];

  if (filters.proofLevelMin) {
    values.push(proofLevelsAtLeast(parseProofLevel(filters.proofLevelMin, "source_backed")));
    where.push(`pc.proof_level = any($${values.length}::text[])`);
  }
  if (filters.claimType) {
    values.push(filters.claimType);
    where.push(`pc.claim_type = $${values.length}`);
  }
  if (filters.visibility) {
    values.push(filters.visibility);
    where.push(`pc.visibility = $${values.length}`);
  }
  if (filters.relationship) {
    values.push(filters.relationship);
    where.push(`pc.author_relationship = $${values.length}`);
  }
  if (filters.freshness === "active") {
    where.push("(pc.expires_or_stale_after is null or pc.expires_or_stale_after >= now())");
  } else if (filters.freshness === "stale") {
    where.push("pc.expires_or_stale_after < now()");
  }

  const { rows } = await pool.query(
    `select
       pc.*,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where ${where.join(" and ")}
     order by pc.created_at desc`,
    values,
  );
  return rows;
}

async function publicClaimForReceipt(claimId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    `select pc.id, pc.place_id
     from place_claims pc
     join place_visibility pv on pv.place_id = pc.place_id
     where pc.id = $1
       and pc.visibility in ('public', 'link_shared')
       and pv.visibility in ('public_link', 'public_guide')
     limit 1`,
    [claimId],
  );
  if (!rows[0]) throw new ApiError(404, "Public claim not found");
  return asObject(rows[0]);
}

async function ownedClaimForReceipt(claimId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    "select id, place_id from place_claims where id = $1 and user_id = $2 limit 1",
    [claimId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Claim not found");
  return asObject(rows[0]);
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

async function handleTrekKmlExport(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported TREK KML export route" }, 405);
  }

  let placeIds: string[];
  try {
    placeIds = normalizeTrekKmlExportRequest(await readJson(request));
  } catch (error) {
    if (error instanceof TrekKmlExportError) {
      return sendJson(response, { error: error.message }, 400);
    }
    throw error;
  }

  const { rows } = await pool.query<TrekKmlPlaceRow>(trekKmlPlacesSql, [userId, placeIds]);
  if (rows.length !== placeIds.length) {
    return sendJson(response, { error: "One or more places were not found" }, 404);
  }

  let kml: string;
  try {
    kml = buildTrekKml(rows);
  } catch (error) {
    if (error instanceof TrekKmlExportError) {
      return sendJson(response, { error: error.message }, 422);
    }
    throw error;
  }

  response.writeHead(200, trekKmlResponseHeaders());
  response.end(kml);
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
  followId: string | undefined,
  url: URL,
  userId: string,
  isVersioned: boolean,
): Promise<void> {
  response.setHeader("Cache-Control", "private, no-store");
  response.setHeader("Vary", "Authorization");

  if (request.method === "GET") {
    if (followId) return sendJson(response, { error: "Not found" }, 404);
    if (isVersioned) {
      try {
        const page = await listFollowedFriendsPage(
          userId,
          normalizeFollowListOptions({
            search: url.searchParams.get("q"),
            limit: url.searchParams.get("limit"),
            cursor: url.searchParams.get("cursor"),
          }),
          (sql, values) => pool.query(sql, [...values] as QueryValue[]),
        );
        return sendJson(response, page);
      } catch (error) {
        if (error instanceof FollowListInputError) {
          return sendJson(response, { error: error.message }, 400);
        }
        throw error;
      }
    }
    const friends = await listFollowedFriends(
      userId,
      (sql, values) => pool.query(sql, [...values] as QueryValue[]),
    );
    return sendJson(response, friends);
  }

  if (request.method === "DELETE") {
    if (!isVersioned || !followId) {
      return sendJson(response, { error: "Follow id is required" }, 400);
    }
    try {
      await unfollowByRelationshipId(
        userId,
        followId,
        (sql, values) => pool.query(sql, [...values] as QueryValue[]),
      );
    } catch (error) {
      if (error instanceof FollowListInputError) {
        return sendJson(response, { error: error.message }, 400);
      }
      throw error;
    }
    return sendJson(response, null, 204);
  }

  if (request.method !== "POST" || followId) {
    return sendJson(response, { error: "Unsupported follows route" }, 405);
  }

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

async function handleSharedPlaceLinkPublic(
  response: ServerResponse,
  code: string,
): Promise<void> {
  response.setHeader("Cache-Control", "private, no-store");
  response.setHeader("Referrer-Policy", "no-referrer");
  const { rows } = await pool.query(publicSharedPlaceLinkSelectSQL, [code]);
  if (!rows[0]) return sendJson(response, { error: "Shared place link not found" }, 404);
  if (isSharedPlaceLinkExpired(rows[0].expires_at)) {
    return sendJson(response, { error: "Shared place link expired" }, 410);
  }
  return sendJson(response, formatPublicSharedPlaceLink(formatDates(rows[0])));
}

async function handlePublicFriendShareEvent(
  request: IncomingMessage,
  response: ServerResponse,
  code: string,
): Promise<void> {
  let event: FriendShareClientEvent;
  try {
    event = normalizeFriendShareClientEvent(await readJson(request), "public");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid friend share event";
    return sendJson(response, { error: message }, 400);
  }

  const link = await friendShareLinkForEvent(code);
  const expiryDisposition = friendShareEventExpiryDisposition(event, friendShareLinkIsExpired(link));
  if (expiryDisposition === "link_expired") {
    return sendJson(response, { error: "Shared place link expired" }, 410);
  }
  if (expiryDisposition === "reason_mismatch") {
    return sendJson(response, { error: "Shared place link is not expired" }, 400);
  }

  const created = await insertFriendShareEvent(link, event, null);
  return sendJson(response, created, 201);
}

async function handleFriendShareEvents(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "POST") {
    const body = await readJson(request);
    const code = stringValue(body.code);
    if (!code) return sendJson(response, { error: "code is required" }, 400);

    let event: FriendShareClientEvent;
    try {
      event = normalizeFriendShareClientEvent(body, "authenticated");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid friend share event";
      return sendJson(response, { error: message }, 400);
    }

    const link = await friendShareLinkForEvent(code);
    if (isSelfFriendShareRecipient(link.user_id, userId)) {
      return sendJson(response, { error: "Share owners cannot record recipient events on their own links" }, 409);
    }
    const expiryDisposition = friendShareEventExpiryDisposition(event, friendShareLinkIsExpired(link));
    if (expiryDisposition === "link_expired") {
      return sendJson(response, { error: "Shared place link expired" }, 410);
    }
    if (expiryDisposition === "reason_mismatch") {
      return sendJson(response, { error: "Shared place link is not expired" }, 400);
    }
    const created = await insertFriendShareEvent(link, event, userId);
    return sendJson(response, created, 201);
  }

  if (request.method === "GET") {
    const code = url.searchParams.get("code")?.trim();
    if (!code) return sendJson(response, { error: "code is required" }, 400);
    const { rows: links } = await pool.query(
      "select id from shared_place_links where code = $1 and user_id = $2 limit 1",
      [code, userId],
    );
    if (!links[0]) return sendJson(response, { error: "Shared place link not found" }, 404);

    const exclusiveOpenFailure = friendShareExclusiveOpenFailurePredicate(
      "event",
      "terminal_event",
    );
    const { rows: summaryRows } = await pool.query(
      `select
         count(*)::int as events_total,
         (count(*) filter (where event_type = 'friend_share_link_created'))::int as link_created,
         (count(*) filter (where event_type = 'friend_share_receipt_opened'))::int as receipt_opened,
         (count(*) filter (where event_type = 'friend_share_save_tapped'))::int as save_tapped,
         (count(*) filter (where event_type = 'friend_share_saved'))::int as saved,
         (count(*) filter (where event_type = 'friend_share_duplicate_blocked'))::int as duplicate_blocked,
         (count(*) filter (where ${exclusiveOpenFailure}))::int as open_failed,
         (count(distinct recipient_user_id))::int as identified_recipient_sessions,
         (count(distinct recipient_user_id) filter (
           where left(recipient_user_id, 6) <> 'guest_'
         ))::int as account_recipient_users,
         (count(distinct recipient_user_id) filter (
           where left(recipient_user_id, 6) = 'guest_'
         ))::int as guest_recipient_sessions,
         (count(distinct recipient_user_id) filter (
           where event_type in ('friend_share_saved', 'friend_share_duplicate_blocked')
             and left(recipient_user_id, 6) <> 'guest_'
         ))::int as account_recipient_users_succeeded,
         (count(distinct recipient_user_id) filter (
           where event_type in ('friend_share_saved', 'friend_share_duplicate_blocked')
             and left(recipient_user_id, 6) = 'guest_'
         ))::int as guest_recipient_sessions_succeeded,
         (count(distinct recipient_user_id) filter (
           where ${exclusiveOpenFailure}
             and left(recipient_user_id, 6) <> 'guest_'
         ))::int as account_recipient_users_open_failed,
         (count(distinct recipient_user_id) filter (
           where ${exclusiveOpenFailure}
             and left(recipient_user_id, 6) = 'guest_'
         ))::int as guest_recipient_sessions_open_failed,
         (count(*) filter (where recipient_user_id is null))::int as anonymous_events
       from friend_share_events event
       where event.shared_place_link_id = $1`,
      [links[0].id],
    );
    const { rows } = await pool.query(
      `select event_type, surface, reason_code, created_at
       from friend_share_events
       where shared_place_link_id = $1
       order by created_at desc
       limit 100`,
      [links[0].id],
    );
    return sendJson(response, {
      code,
      summary: asObject(summaryRows[0]),
      events: rows.map((row) => {
        const event = asObject(row);
        return formatDates({
          event_type: event.event_type,
          surface: event.surface,
          reason_code: event.reason_code ?? null,
          created_at: event.created_at,
        });
      }),
    });
  }

  return sendJson(response, { error: "Unsupported friend share events route" }, 405);
}

async function friendShareLinkForEvent(code: string): Promise<JsonBody> {
  if (!/^[A-Za-z0-9_-]{6,32}$/.test(code)) throw new ApiError(404, "Shared place link not found");
  const { rows } = await pool.query(
    `select id, user_id, payload, expires_at
     from shared_place_links
     where code = $1
     limit 1`,
    [code],
  );
  if (!rows[0]) throw new ApiError(404, "Shared place link not found");
  return asObject(rows[0]);
}

function friendShareLinkIsExpired(link: JsonBody): boolean {
  if (!link.expires_at) return false;
  const expiresAt = link.expires_at instanceof Date
    ? link.expires_at.getTime()
    : Date.parse(String(link.expires_at));
  return !Number.isFinite(expiresAt) || expiresAt <= Date.now();
}

async function insertFriendShareEvent(
  link: JsonBody,
  event: FriendShareClientEvent,
  recipientUserId: string | null,
): Promise<JsonBody> {
  const { rows } = await pool.query(
    `insert into friend_share_events (
       shared_place_link_id,
       sender_user_id,
       recipient_user_id,
       recipient_place_id,
       event_type,
       surface,
       reason_code
     )
     values ($1, $2, $3, $4, $5, $6, $7)
     on conflict do nothing
     returning event_type, surface, reason_code, created_at`,
    [
      link.id,
      link.user_id,
      recipientUserId,
      event.recipientPlaceId,
      event.eventType,
      event.surface,
      event.reasonCode,
    ],
  );
  if (rows[0]) return formatDates(asObject(rows[0]));

  const { rows: existingRows } = await pool.query(
    `select event_type, surface, reason_code, created_at
     from friend_share_events
     where shared_place_link_id = $1
       and recipient_user_id is not distinct from $2
       and event_type = $3
       and surface = $4
       and reason_code is not distinct from $5
     limit 1`,
    [link.id, recipientUserId, event.eventType, event.surface, event.reasonCode],
  );
  if (existingRows[0]) return formatDates(asObject(existingRows[0]));

  throw new Error("Friend share event receipt could not be persisted");
}

async function handleSharedPlaceLinks(
  request: IncomingMessage,
  response: ServerResponse,
  code: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !code) {
    const { rows } = await pool.query(
      `select *
       from shared_place_links
       where user_id = $1
       order by created_at desc
       limit 100`,
      [userId],
    );
    return sendJson(response, rows.map((row) => formatSharedPlaceLink(formatDates(row))));
  }

  if (request.method === "POST" && !code) {
    let create;
    try {
      create = normalizeSharedPlaceLinkCreate(await readJson(request, sharedPlaceLinkBodyMaxBytes));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid shared place payload";
      return sendJson(response, { error: message }, 400);
    }

    const code = await uniqueShareCode();
    const client = await pool.connect();
    try {
      await client.query("begin");
      let senderDisplayName: string | null = null;
      let senderHandle: string | null = null;
      let sourceVerifiedAt: Date | null = null;
      if (create.sourcePlaceId) {
        const { rows: senderRows } = await client.query(
          `select
             place.name,
             place.address,
             place.latitude,
             place.longitude,
             place.source_url,
             profile.display_name,
             profile.handle,
             now() as source_verified_at
           from places place
           join profiles profile on profile.id = place.user_id
           where place.id = $1 and place.user_id = $2
           limit 1`,
          [create.sourcePlaceId, userId],
        );
        if (!senderRows[0]) throw new ApiError(404, "Place not found");
        if (!recipientPlaceMatchesSharedPayload(asObject(senderRows[0]), create.payload)) {
          throw new ApiError(409, "Shared payload does not match the verified source place");
        }
        const senderSnapshot = normalizeSharedSenderSnapshot(
          senderRows[0].display_name,
          senderRows[0].handle,
        );
        senderDisplayName = senderSnapshot.displayName;
        senderHandle = senderSnapshot.handle;
        sourceVerifiedAt = senderRows[0].source_verified_at as Date;
      }
      const body: JsonBody = {
        code,
        user_id: userId,
        source_place_id: create.sourcePlaceId ?? null,
        sender_display_name: senderDisplayName,
        sender_handle: senderHandle,
        source_verified_at: sourceVerifiedAt,
        note_consent_version: create.noteConsentVersion,
        payload: create.payload,
        expires_at: create.expiresAt,
      };
      const insert = buildInsert("shared_place_links", body, sharedPlaceLinkFields);
      const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
      await client.query(
        `insert into friend_share_events (
           shared_place_link_id,
           sender_user_id,
           event_type,
           surface
         )
         values ($1, $2, 'friend_share_link_created', 'server')`,
        [rows[0].id, userId],
      );
      await client.query("commit");
      return sendJson(response, formatSharedPlaceLink(formatDates(rows[0])), 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  return sendJson(response, { error: "Unsupported shared place links route" }, 405);
}

async function handleWorkflows(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  userId: string,
): Promise<void> {
  if (segments[0] !== "place-recovery") {
    return sendJson(response, { error: "Unsupported workflows route" }, 405);
  }

  const kind = segments[1];
  const id = segments[2];
  const action = segments[3];

  if (kind === "work-orders") {
    if (request.method === "GET" && !id) {
      const { rows } = await pool.query(
        `select *
         from work_orders
         where user_id = $1 and workflow_id = $2
         order by created_at desc
         limit 100`,
        [userId, placeRecoveryWorkflowId],
      );
      return sendJson(response, rows.map((row) => formatDates(row)));
    }

    if (request.method === "POST" && !id) {
      const workOrder = normalizePlaceRecoveryWorkOrderCreate(await readJson(request));
      const client = await pool.connect();
      try {
        const row = await createPlaceRecoveryWorkOrder(client, userId, workOrder);
        return sendJson(response, formatDates(row), 201);
      } finally {
        client.release();
      }
    }

    return sendJson(response, { error: "Unsupported work order route" }, 405);
  }

  if (kind === "clearing-blocks") {
    if (request.method === "GET" && id) {
      const block = await clearingBlockForUser(id, userId);
      const { rows: items } = await pool.query(
        `select receipt_id, receipt_hash, merkle_proof, position, created_at
         from clearing_block_items
         where block_id = $1
         order by position asc`,
        [id],
      );
      return sendJson(response, {
        block: formatDates(block),
        items: items.map((row) => formatDates(row)),
      });
    }

    if (request.method === "GET" && !id) {
      const { rows } = await pool.query(
        `select *
         from clearing_blocks
         where user_id = $1 and chain_namespace = $2
         order by block_number desc
         limit 100`,
        [userId, placeRecoveryWorkflowId],
      );
      return sendJson(response, rows.map((row) => formatDates(row)));
    }

    if (request.method === "POST" && !id) {
      const created = await createClearingBlockForPendingReceipts(userId, await readJson(request));
      return sendJson(response, created, created.created ? 201 : 200);
    }

    return sendJson(response, { error: "Unsupported clearing block route" }, 405);
  }

  if (kind === "reputation") {
    if (request.method === "GET" && id === "summary") {
      const { rows } = await pool.query(
        `select
           workflow_version,
           source_type,
           operator_id,
           model_provenance_bucket,
           policy_version,
           run_count,
           operational_success_count,
           technical_failure_count,
           confirmed_count,
           edited_count,
           rejected_count,
           source_only_count,
           refund_count,
           median_latency_ms,
           user_decision_coverage,
           operational_success_rate,
           confirmation_rate,
           edit_rate,
           rejection_rate,
           technical_failure_rate,
           created_at
         from workflow_reputation_snapshots
         where requester_id = $1 and workflow_id = $2 and is_current = true
         order by source_type, operator_id, model_provenance_bucket`,
        [userId, placeRecoveryWorkflowId],
      );
      return sendJson(response, rows.map((row) => formatDates(asObject(row))));
    }
    return sendJson(response, { error: "Unsupported reputation route" }, 405);
  }

  if (kind !== "runs") {
    return sendJson(response, { error: "Unsupported workflows route" }, 405);
  }

  const runId = id;

  if (request.method === "GET" && runId === "summary") {
    const { rows } = await pool.query(
      `select
         count(*)::int as total_runs,
         count(*) filter (where source_url ilike '%instagram.com/reel%')::int as instagram_reels,
         count(*) filter (where source_url is not null)::int as source_url_runs,
         count(*) filter (where exists (
           select 1 from workflow_receipts wr
           where wr.run_id = workflow_runs.id and wr.receipt_type = 'analysis' and wr.is_current = true
         ))::int as runs_with_current_analysis_receipt,
         count(*) filter (where exists (
           select 1 from workflow_receipts wr
           where wr.run_id = workflow_runs.id and wr.receipt_type = 'decision'
         ))::int as runs_with_decision_receipt,
         count(*) filter (where result_type = 'technical_failure')::int as technical_failure_runs,
         count(*) filter (where credit_settlement = 'pending')::int as unsettled_runs,
         count(*) filter (where status = 'completed')::int as completed_runs,
         count(*) filter (where status = 'failed')::int as failed_runs,
         count(*) filter (where status = 'needs_review')::int as needs_review_runs
       from workflow_runs
       where user_id = $1 and workflow_id = $2`,
      [userId, placeRecoveryWorkflowId],
    );
    const { rows: receiptRows } = await pool.query(
      `with receipt_counts as (
         select
           count(*)::int as total_receipts,
           count(*) filter (where receipt_type = 'analysis')::int as analysis_receipts,
           count(*) filter (where receipt_type = 'decision')::int as decision_receipts,
           count(*) filter (where user_feedback_action is not null)::int as user_feedback_receipts
         from workflow_receipts wr
         join workflow_runs r on r.id = wr.run_id
         where r.user_id = $1 and wr.workflow_id = $2
       ), conflicts as (
         select count(*)::int as analysis_receipt_duplicates_or_conflicts
         from (
           select wr.run_id, wr.attempt_no
           from workflow_receipts wr
           join workflow_runs r on r.id = wr.run_id
           where r.user_id = $1 and wr.workflow_id = $2 and wr.receipt_type = 'analysis'
           group by wr.run_id, wr.attempt_no
           having count(*) filter (where wr.is_current) > 1 or count(distinct wr.output_hash) > 1
         ) grouped
       ), coverage as (
         select coalesce(
           count(*) filter (where r.result_type <> 'technical_failure' and exists (
             select 1 from workflow_receipts wr
             where wr.run_id = r.id
               and wr.receipt_type = 'decision'
               and wr.is_current = true
               and wr.attempt_no = r.current_attempt_no
           ))::double precision
           / nullif(count(*) filter (where r.result_type <> 'technical_failure'), 0),
           0
         ) as user_decision_coverage
         from workflow_runs r
         where r.user_id = $1 and r.workflow_id = $2
       )
       select * from receipt_counts cross join conflicts cross join coverage`,
      [userId, placeRecoveryWorkflowId],
    );
    return sendJson(response, {
      runs: asObject(rows[0]),
      receipts: asObject(receiptRows[0]),
    });
  }

  if (request.method === "GET" && !runId) {
    const { rows } = await pool.query(
      `select *
       from workflow_runs
       where user_id = $1 and workflow_id = $2
       order by created_at desc
       limit 100`,
      [userId, placeRecoveryWorkflowId],
    );
    return sendJson(response, rows.map((row) => formatDates(row)));
  }

  if (request.method === "POST" && !runId) {
    const body = await readJson(request);
    const run = normalizePlaceRecoveryRunCreate(body);
    const workOrder = normalizePlaceRecoveryWorkOrderCreate({
      ...body,
      source_url: run.sourceUrl,
      source_type: run.sourceType,
      credit_reserved: run.creditReserved,
    });
    const client = await pool.connect();
    try {
      await client.query("begin");
      const workOrderId = run.workOrderId
        ? await ensureWorkOrderOwner(run.workOrderId, userId, client)
        : String((await createPlaceRecoveryWorkOrder(client, userId, workOrder)).id);
      const insert = buildInsert("workflow_runs", {
        work_order_id: workOrderId,
        workflow_id: run.workflowId,
        listing_id: run.listingId,
        user_id: userId,
        source_url: run.sourceUrl ?? null,
        source_type: run.sourceType,
        status: "queued",
        current_attempt_no: 1,
        credit_reserved: run.creditReserved,
        credit_settlement: "pending",
      }, workflowRunFields);
      const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
      const created = asObject(rows[0]);
      await client.query("update work_orders set status = 'running' where id = $1 and user_id = $2", [workOrderId, userId]);
      await insertCreditLedger(client, {
        run_id: String(created.id),
        user_id: userId,
        attempt_no: 1,
        settlement_key: "reserve",
        delta: -run.creditReserved,
        reason: "reserve",
        settlement: "pending",
      });
      await client.query("commit");
      return sendJson(response, formatDates(created), 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (!runId) return sendJson(response, { error: "Workflow run is required" }, 400);
  if (!isUuid(runId)) return sendJson(response, { error: "Workflow run id must be a UUID" }, 400);
  await ensureWorkflowRunOwner(runId, userId);

  if (request.method === "GET" && action === "receipts") {
    const { rows } = await pool.query(
      `select
         wr.id,
         wr.run_id,
         wr.workflow_id,
         wr.workflow_version,
         wr.receipt_type,
         wr.attempt_no,
         wr.result_revision,
         wr.supersedes_receipt_id,
         wr.is_current,
         wr.failure_code,
         wr.failed_step,
         wr.retryable,
         wr.job_id,
         wr.agent_id,
         wr.operator_id,
         wr.model_provenance_bucket,
         wr.input_hash,
         wr.output_hash,
         wr.latency_ms,
         wr.user_feedback_action,
         wr.verdict,
         wr.settlement,
         wr.evaluator_summary,
         wr.evidence_refs,
         wr.candidate_refs,
         wr.receipt_hash,
         wr.anchor_status,
         wr.created_at
       from workflow_receipts wr
       join workflow_runs r on r.id = wr.run_id
       where wr.run_id = $1
         and r.user_id = $2
         and wr.workflow_id = $3
       order by wr.attempt_no asc, wr.created_at asc, wr.id asc`,
      [runId, userId, placeRecoveryWorkflowId],
    );
    return sendJson(response, rows.map(workflowReceiptResponse));
  }

  if (request.method === "POST" && action === "result") {
    const result = normalizePlaceRecoveryWorkerResult(await readJson(request));
    const recorded = await recordPlaceRecoveryResult(runId, userId, result);
    return sendJson(response, recorded, recorded.created ? 201 : 200);
  }

  if (request.method === "POST" && action === "decision") {
    const decision = normalizeUserDecision(await readJson(request), runId);
    const recorded = await recordPlaceRecoveryDecision(runId, userId, decision);
    return sendJson(response, recorded, recorded.created ? 201 : 200);
  }

  return sendJson(response, { error: "Unsupported workflow run route" }, 405);
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
  if (body.workflow_run_id !== undefined && typeof body.workflow_run_id !== "string") {
    return sendJson(response, { error: "workflow_run_id must be a string" }, 400);
  }
  const workflowRunId = stringValue(body.workflow_run_id);
  if (workflowRunId) await ensureWorkflowRunOwner(workflowRunId, userId);

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

    const body = sourceSearchCandidateBody(candidate, captureId, workflowRunId);
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
    media_evidence: recovery.mediaEvidence,
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
    if (body.workflow_run_id !== undefined && typeof body.workflow_run_id !== "string") {
      return sendJson(response, { error: "workflow_run_id must be a string" }, 400);
    }
    if (body.workflow_run_id) await ensureWorkflowRunOwner(body.workflow_run_id, userId);
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

function sourceSearchCandidateBody(candidate: SourceSearchCandidate, captureId: string, workflowRunId?: string): JsonBody {
  return {
    capture_id: captureId,
    workflow_run_id: workflowRunId,
    name: candidate.name,
    address: candidate.address,
    city: "",
    latitude: candidate.latitude ?? null,
    longitude: candidate.longitude ?? null,
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

function safeErrorKind(error: unknown): string {
  return error instanceof Error ? error.name : typeof error;
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

async function ownedPlaceForAnalysis(placeId: unknown, userId: string): Promise<JsonBody> {
  if (typeof placeId !== "string") throw new ApiError(400, "place_id must be a string");

  const { rows } = await pool.query(
    "select * from places where id = $1 and user_id = $2 limit 1",
    [placeId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Place not found");
  return asObject(rows[0]);
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

async function createPlaceRecoveryWorkOrder(
  client: PoolClient,
  userId: string,
  workOrder: ReturnType<typeof normalizePlaceRecoveryWorkOrderCreate>,
): Promise<JsonBody> {
  const insert = buildInsert("work_orders", {
    workflow_id: workOrder.workflowId,
    listing_id: workOrder.listingId,
    user_id: userId,
    intent: workOrder.intent,
    input_type: workOrder.inputType,
    input_ref: workOrder.inputRef ?? null,
    source_url: workOrder.sourceUrl ?? null,
    evaluator_policy_id: workOrder.evaluatorPolicyId,
    settlement_mode: workOrder.settlementMode,
    budget_policy: workOrder.budgetPolicy,
    status: "queued",
  }, workOrderFields);
  const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
  return asObject(rows[0]);
}

async function ensureWorkOrderOwner(workOrderId: string, userId: string, client?: PoolClient): Promise<string> {
  const db = client ?? pool;
  const { rows } = await db.query("select id from work_orders where id = $1 and user_id = $2", [workOrderId, userId]);
  if (!rows[0]) throw new ApiError(404, "Work order not found");
  return workOrderId;
}

async function ensureWorkflowRunOwner(runId: string, userId: string): Promise<void> {
  const { rows } = await pool.query("select id from workflow_runs where id = $1 and user_id = $2", [runId, userId]);
  if (!rows[0]) throw new ApiError(404, "Workflow run not found");
}

async function workflowRunForUser(runId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query("select * from workflow_runs where id = $1 and user_id = $2", [runId, userId]);
  if (!rows[0]) throw new ApiError(404, "Workflow run not found");
  return asObject(rows[0]);
}

async function recordPlaceRecoveryResult(
  runId: string,
  userId: string,
  result: PlaceRecoveryWorkerResult,
): Promise<JsonBody & { created: boolean }> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const run = await lockedWorkflowRun(client, runId, userId);
    const currentAttemptNo = Number(run.current_attempt_no ?? 1);
    const attemptNo = result.attemptNo ?? currentAttemptNo;
    const safeResult: PlaceRecoveryWorkerResult = {
      ...result,
      evidenceRefs: safeOpaqueRefs(result.evidenceRefs),
      candidateRefs: safeOpaqueRefs(result.candidateRefs),
      toolTraceRefs: safeOpaqueRefs(result.toolTraceRefs),
      modelProvenance: safeModelProvenance(result.modelProvenance),
      jobId: result.jobId ?? `run:${runId}:attempt:${attemptNo}`,
    };
    await validateResultCandidateRefs(client, runId, userId, safeResult);

    const output = safeResultProjection(safeResult);
    const outputHash = sha256CanonicalJson(output);
    const idempotencyKey = result.idempotencyKey
      ?? `result:${sha256CanonicalJson({ runId, attemptNo, resultRevision: result.resultRevision, outputHash })}`;

    const { rows: replayRows } = await client.query(
      `select *
       from workflow_receipts
       where run_id = $1 and receipt_type = 'analysis' and idempotency_key = $2
       limit 1`,
      [runId, idempotencyKey],
    );
    if (replayRows[0]) {
      const replay = asObject(replayRows[0]);
      const replayAttemptNo = result.attemptNo ?? Number(replay.attempt_no);
      if (stringValue(replay.output_hash) !== outputHash
        || Number(replay.attempt_no) !== replayAttemptNo
        || Number(replay.result_revision) !== result.resultRevision
      ) {
        throw new WorkflowConflictError("Result idempotency key was already used with different identity or output");
      }
      await client.query("commit");
      return {
        created: false,
        run: formatDates(run),
        receipt: workflowReceiptResponse(replay),
      };
    }

    const currentReceipt = await currentAnalysisReceipt(client, runId);
    const plan = planResultTransition({
      currentAttemptNo,
      currentCreditSettlement: parseCreditSettlement(run.credit_settlement),
      requestedAttemptNo: result.attemptNo,
      resultRevision: result.resultRevision,
      idempotencyKey,
      outputHash,
      explicitRetry: result.explicitRetry,
      currentReceipt: currentReceipt ? {
        id: String(currentReceipt.id),
        attemptNo: Number(currentReceipt.attempt_no),
        resultRevision: Number(currentReceipt.result_revision),
        idempotencyKey: String(currentReceipt.idempotency_key),
        outputHash: String(currentReceipt.output_hash),
      } : undefined,
    });
    if (plan.kind === "idempotent") {
      const { rows } = await client.query("select * from workflow_receipts where id = $1", [plan.receiptId]);
      await client.query("commit");
      return { created: false, run: formatDates(run), receipt: workflowReceiptResponse(rows[0]) };
    }

    if (plan.supersedeCurrent && plan.supersedesReceiptId) {
      await client.query(
        "update workflow_receipts set is_current = false where id = $1 and run_id = $2 and receipt_type = 'analysis'",
        [plan.supersedesReceiptId, runId],
      );
    }

    const status = safeResult.technicalFailure ? "failed" : "needs_review";
    await persistWorkflowResultSteps(client, runId, plan.attemptNo, safeResult, outputHash);
    const { rows: updatedRows } = await client.query(
      `update workflow_runs
       set status = $1,
           current_attempt_no = $2,
           result_type = $3,
           confidence = $4,
           evidence_tier = $5,
           result_evidence_refs = $6,
           result_candidate_refs = $7,
           credit_settlement = $8,
           completed_at = case when $1 = 'failed' then now() else null end
       where id = $9 and user_id = $10
       returning *`,
      [
        status,
        plan.attemptNo,
        safeResult.resultType,
        safeResult.confidence,
        safeResult.evidenceTier,
        safeResult.evidenceRefs,
        safeResult.candidateRefs,
        safeResult.technicalFailure ? "refunded" : "pending",
        runId,
        userId,
      ],
    );
    let updatedRun = asObject(updatedRows[0]);
    const receiptDraft = analysisReceiptForResult(safeResult);
    const receiptBody = workflowReceiptBody(runId, receiptDraft, {
      run: updatedRun,
      userId,
      output,
      attemptNo: plan.attemptNo,
      resultRevision: plan.resultRevision,
      idempotencyKey,
      supersedesReceiptId: plan.supersedesReceiptId,
      isCurrent: true,
      outputHash,
      decisionId: undefined,
    });
    const receiptInsert = buildInsert("workflow_receipts", receiptBody, workflowReceiptFields);
    const { rows: receiptRows } = await client.query(`${receiptInsert.sql} returning *`, receiptInsert.values);
    const receipt = asObject(receiptRows[0]);

    if (safeResult.technicalFailure) {
      await insertCreditLedger(client, {
        run_id: runId,
        user_id: userId,
        attempt_no: plan.attemptNo,
        settlement_key: `technical_failure:${plan.attemptNo}`,
        delta: Number(updatedRun.credit_reserved ?? 1),
        reason: "technical_failure",
        settlement: "refunded",
      });
    }

    const { rows: finalRows } = await client.query(
      `update workflow_runs
       set receipt_id = $1
       where id = $2 and user_id = $3
       returning *`,
      [receipt.id, runId, userId],
    );
    updatedRun = asObject(finalRows[0] ?? updatedRun);
    if (updatedRun.work_order_id) {
      await client.query(
        "update work_orders set status = $1 where id = $2 and user_id = $3",
        [status, updatedRun.work_order_id, userId],
      );
    }
    await upsertWorkflowStep(client, {
      runId,
      attemptNo: plan.attemptNo,
      stepKey: "write_analysis_receipt",
      status: "succeeded",
      inputHash: String(receipt.input_hash),
      outputHash: String(receipt.output_hash),
    });
    await refreshWorkflowReputationSnapshot(client, userId, updatedRun, receipt);

    await client.query("commit");
    return {
      created: true,
      run: formatDates(updatedRun),
      receipt: workflowReceiptResponse(receipt),
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function lockedWorkflowRun(client: PoolClient, runId: string, userId: string): Promise<JsonBody> {
  const { rows } = await client.query(
    "select * from workflow_runs where id = $1 and user_id = $2 for update",
    [runId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Workflow run not found");
  return asObject(rows[0]);
}

async function currentAnalysisReceipt(client: PoolClient, runId: string): Promise<JsonBody | undefined> {
  const { rows } = await client.query(
    `select *
     from workflow_receipts
     where run_id = $1 and receipt_type = 'analysis' and is_current = true
     order by attempt_no desc, created_at desc, id desc
     limit 1
     for update`,
    [runId],
  );
  return rows[0] ? asObject(rows[0]) : undefined;
}

async function validateResultCandidateRefs(
  client: PoolClient,
  runId: string,
  userId: string,
  result: PlaceRecoveryWorkerResult,
): Promise<void> {
  if (result.resultType === "review_candidate" && result.candidateRefs.length === 0) {
    throw new WorkflowContractError("review_candidate requires an owned candidate reference");
  }
  if (!result.candidateRefs.length) return;
  if (result.candidateRefs.some((ref) => !isUuid(ref))) {
    throw new WorkflowContractError("candidate_refs must contain UUIDs owned by this run");
  }
  const { rows } = await client.query(
    `select pc.id
     from place_candidates pc
     join captures c on c.id = pc.capture_id
     where pc.id = any($1::uuid[])
       and pc.workflow_run_id = $2
       and c.user_id = $3`,
    [result.candidateRefs, runId, userId],
  );
  if (rows.length !== new Set(result.candidateRefs).size) {
    throw new ApiError(404, "Workflow candidate not found");
  }
}

function safeResultProjection(result: PlaceRecoveryWorkerResult): JsonBody {
  return {
    resultType: result.resultType,
    evidenceTier: result.evidenceTier,
    confidence: result.confidence,
    missingFields: result.missingFields,
    evidenceRefs: result.evidenceRefs,
    candidateRefs: result.candidateRefs,
    technicalFailure: result.technicalFailure,
    failureCode: result.failureCode ?? null,
    failedStep: result.failedStep ?? null,
    retryable: result.retryable ?? null,
    jobId: result.jobId ?? null,
    agentId: result.agentId,
    operatorId: result.operatorId ?? "save-client",
    permissionSnapshot: result.permissionSnapshot,
    toolTraceRefs: result.toolTraceRefs,
    latencyMs: result.latencyMs ?? null,
    costEstimate: result.costEstimate ?? null,
    modelProvenance: result.modelProvenance,
  };
}

function workflowReceiptResponse(value: unknown): JsonBody {
  const receipt = asObject(value);
  return formatDates({
    id: receipt.id,
    run_id: receipt.run_id,
    workflow_id: receipt.workflow_id,
    workflow_version: receipt.workflow_version,
    receipt_type: receipt.receipt_type,
    attempt_no: receipt.attempt_no,
    result_revision: receipt.result_revision,
    supersedes_receipt_id: receipt.supersedes_receipt_id,
    is_current: receipt.is_current,
    failure_code: receipt.failure_code,
    failed_step: receipt.failed_step,
    retryable: receipt.retryable,
    decision_id: receipt.decision_id,
    job_id: safeOpaqueRefs([receipt.job_id], 1)[0] ?? null,
    agent_id: receipt.agent_id,
    operator_id: receipt.operator_id,
    model_provenance_bucket: receipt.model_provenance_bucket,
    input_hash: receipt.input_hash,
    output_hash: receipt.output_hash,
    latency_ms: receipt.latency_ms,
    user_feedback_action: receipt.user_feedback_action,
    verdict: receipt.verdict,
    settlement: receipt.settlement,
    evaluator_summary: receipt.evaluator_summary,
    evidence_refs: safeOpaqueRefs(receipt.evidence_refs),
    candidate_refs: safeOpaqueRefs(receipt.candidate_refs),
    receipt_hash: receipt.receipt_hash,
    anchor_status: receipt.anchor_status,
    created_at: receipt.created_at,
  });
}

function safeModelProvenance(value: JsonBody): JsonBody {
  return {
    claimedProvider: boundedSafeDimension(value.claimedProvider, 80),
    claimedModel: boundedSafeDimension(value.claimedModel, 120),
    observedProvider: null,
    observedModel: null,
    attestationLevel: "self_claim",
    fallbackUsed: typeof value.fallbackUsed === "boolean" ? value.fallbackUsed : "unknown",
    usage: asOptionalObject(value.usage),
    evidenceRefs: safeOpaqueRefs(value.evidenceRefs, 16),
  };
}

function modelProvenanceBucket(value: JsonBody): string {
  const provider = boundedSafeDimension(value.claimedProvider, 40);
  const providerBucket = ["openai", "google", "anthropic", "xai", "apple", "none", "unknown"].includes(provider)
    ? provider
    : "other";
  const model = boundedSafeDimension(value.claimedModel, 80);
  const modelBucket = model === "none" || model === "no-model"
    ? "no-model"
    : model.includes("gemini")
      ? "gemini"
      : model.includes("claude")
        ? "claude"
        : model.includes("gpt") || /^o[1-9]/.test(model)
          ? "openai-model"
          : model.includes("grok")
            ? "grok"
            : model === "unknown"
              ? "unknown"
              : "other";
  return `self-claim-${providerBucket}-${modelBucket}`;
}

function boundedSafeDimension(value: unknown, maxLength: number): string {
  if (typeof value !== "string") return "unknown";
  const safe = value.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return safe.slice(0, maxLength) || "unknown";
}

function asOptionalObject(value: unknown): JsonBody | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonBody : null;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function recordPlaceRecoveryDecision(
  runId: string,
  userId: string,
  decisionInput: UserDecisionInput,
): Promise<JsonBody & { created: boolean }> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const run = await lockedWorkflowRun(client, runId, userId);
    const currentReceipt = await currentAnalysisReceipt(client, runId);
    if (!currentReceipt) throw new WorkflowConflictError("A current analysis receipt is required before a decision");
    if (run.result_type === "technical_failure") {
      throw new WorkflowConflictError("Technical failures are refunded automatically and do not accept user decisions");
    }

    const currentAttemptNo = Number(run.current_attempt_no ?? 1);
    const receiptAttemptNo = Number(currentReceipt.attempt_no ?? 1);
    const attemptNo = decisionInput.attemptNo ?? currentAttemptNo;
    const inferredCandidateId = (stringArray(run.result_candidate_refs) ?? []).find(isUuid);
    const candidateId = decisionInput.candidateId ?? inferredCandidateId;
    const editedPlaceId = stringValue(decisionInput.editedPayload.place_id);
    const finalPlaceId = decisionInput.finalPlaceId ?? (editedPlaceId && isUuid(editedPlaceId) ? editedPlaceId : undefined);
    const decision: UserDecisionInput = { ...decisionInput, attemptNo, candidateId, finalPlaceId };

    const finalPlaceHash = sha256CanonicalJson(decision.finalPlace ?? null);
    const fingerprint = sha256CanonicalJson({
      runId,
      attemptNo,
      action: decision.action,
      candidateId: candidateId ?? null,
      finalPlaceId: finalPlaceId ?? null,
      reasonCode: decision.reasonCode ?? null,
      editedPayloadHash: sha256CanonicalJson(decision.editedPayload),
      finalPlaceHash,
    });
    const idempotencyKey = decision.idempotencyKey ?? `decision:${fingerprint}`;

    const { rows: existingRows } = await client.query(
      `select ud.*, wr.id as receipt_id
       from user_decisions ud
       left join workflow_receipts wr on wr.decision_id = ud.id
       where ud.run_id = $1
         and ud.user_id = $2
         and (ud.idempotency_key = $3 or ($4::uuid is not null and ud.id = $4::uuid))`,
      [runId, userId, idempotencyKey, decision.decisionId ?? null],
    );
    if (existingRows.length > 1) {
      throw new WorkflowConflictError("Decision id and idempotency key refer to different decisions");
    }
    const existing = existingRows[0] ? asObject(existingRows[0]) : undefined;
    const plan = planDecisionTransition({
      currentAttemptNo,
      currentCreditSettlement: parseCreditSettlement(run.credit_settlement),
      action: decision.action,
      creditReserved: Number(run.credit_reserved ?? 1),
      idempotencyKey,
      fingerprint,
      existingDecision: existing ? {
        id: String(existing.id),
        receiptId: String(existing.receipt_id),
        idempotencyKey: String(existing.idempotency_key),
        fingerprint: String(existing.after_hash),
      } : undefined,
    });
    if (plan.kind === "idempotent") {
      const { rows: receiptRows } = await client.query("select * from workflow_receipts where id = $1", [plan.receiptId]);
      await client.query("commit");
      return {
        created: false,
        run: formatDates(run),
        receipt: workflowReceiptResponse(receiptRows[0]),
      };
    }

    await insertFinalPlaceForDecision(client, userId, decision);
    await validateDecisionReferences(client, runId, userId, stringValue(run.result_type), decision);
    if (attemptNo !== currentAttemptNo || receiptAttemptNo !== currentAttemptNo) {
      throw new WorkflowConflictError("A retry is already pending or the decision targets a stale attempt");
    }

    const result = normalizePlaceRecoveryWorkerResult({
      result_type: run.result_type ?? "source_only_clue",
      evidence_tier: run.evidence_tier ?? "none",
      confidence: run.confidence ?? 0,
      evidence_refs: run.result_evidence_refs ?? [],
      candidate_refs: run.result_candidate_refs ?? [],
      job_id: currentReceipt.job_id ?? undefined,
      model_provenance: currentReceipt.model_provenance ?? {},
    });
    const receiptDraft = receiptForResult(result, decision);
    const beforeHash = String(currentReceipt.output_hash);
    const decisionBody: JsonBody = {
      id: decision.decisionId,
      run_id: runId,
      user_id: userId,
      attempt_no: attemptNo,
      candidate_id: candidateId ?? null,
      final_place_id: finalPlaceId ?? null,
      action: decision.action,
      edited_payload: decision.editedPayload,
      reason: decision.reason ?? null,
      reason_code: decision.reasonCode ?? null,
      idempotency_key: idempotencyKey,
      before_hash: beforeHash,
      after_hash: fingerprint,
    };
    const decisionInsert = buildInsert("user_decisions", decisionBody, userDecisionFields);
    const { rows: decisionRows } = await client.query(`${decisionInsert.sql} returning *`, decisionInsert.values);
    const decisionRow = asObject(decisionRows[0]);

    await client.query(
      "update workflow_receipts set is_current = false where run_id = $1 and receipt_type = 'decision' and is_current = true",
      [runId],
    );
    const output = {
      action: decision.action,
      candidateId: candidateId ?? null,
      finalPlaceId: finalPlaceId ?? null,
      reasonCode: decision.reasonCode ?? null,
      editedPayloadHash: sha256CanonicalJson(decision.editedPayload),
      finalPlaceHash,
    };
    const outputHash = sha256CanonicalJson(output);
    const receiptBody = workflowReceiptBody(runId, receiptDraft, {
      run,
      userId,
      output,
      attemptNo,
      resultRevision: Number(currentReceipt.result_revision ?? 1),
      idempotencyKey,
      isCurrent: true,
      outputHash,
      decisionId: String(decisionRow.id),
    });
    const receiptInsert = buildInsert("workflow_receipts", receiptBody, workflowReceiptFields);
    const { rows: receiptRows } = await client.query(`${receiptInsert.sql} returning *`, receiptInsert.values);
    const receipt = asObject(receiptRows[0]);

    if (plan.terminal) {
      await insertCreditLedger(client, {
        run_id: runId,
        user_id: userId,
        attempt_no: attemptNo,
        decision_id: decisionRow.id,
        settlement_key: `decision:${decisionRow.id}`,
        delta: plan.refundDelta,
        reason: plan.creditSettlement,
        settlement: plan.creditSettlement,
      });
    }
    await updateDecisionCandidateState(client, userId, decision);
    const { rows: updatedRows } = await client.query(
      `update workflow_runs
       set status = $1,
           current_attempt_no = $2,
           credit_settlement = $3,
           receipt_id = $4,
           completed_at = case when $5 then coalesce(completed_at, now()) else null end
       where id = $6 and user_id = $7
       returning *`,
      [
        plan.nextStatus,
        plan.nextAttemptNo,
        plan.creditSettlement,
        receipt.id,
        plan.terminal,
        runId,
        userId,
      ],
    );
    const updatedRun = asObject(updatedRows[0]);
    if (updatedRun.work_order_id) {
      await client.query(
        "update work_orders set status = $1 where id = $2 and user_id = $3",
        [plan.nextStatus, updatedRun.work_order_id, userId],
      );
    }
    await refreshWorkflowReputationSnapshot(client, userId, updatedRun, currentReceipt);

    await client.query("commit");
    return {
      created: true,
      run: formatDates(updatedRun),
      receipt: workflowReceiptResponse(receipt),
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function insertFinalPlaceForDecision(
  client: PoolClient,
  userId: string,
  decision: UserDecisionInput,
): Promise<void> {
  if (!decision.finalPlace) return;
  if (!decision.finalPlaceId || stringValue(decision.finalPlace.id) !== decision.finalPlaceId) {
    throw new WorkflowContractError("final_place.id must match final_place_id");
  }
  if (!["confirm", "edit", "wrong_place", "wrong_city", "wrong_branch"].includes(decision.action)) {
    throw new WorkflowContractError("final_place is only accepted for a newly saved or corrected place");
  }
  if (!stringValue(decision.finalPlace.name)
    || typeof decision.finalPlace.address !== "string"
    || numberValue(decision.finalPlace.latitude) === undefined
    || numberValue(decision.finalPlace.longitude) === undefined
  ) {
    throw new WorkflowContractError("final_place requires name, address, latitude, and longitude");
  }

  const body = withOwner(pickFields(decision.finalPlace, placeFields), userId);
  const insert = buildInsert("places", body, [...placeFields, "user_id"]);
  const { rows } = await client.query(`${insert.sql} on conflict (id) do nothing returning id`, insert.values);
  if (!rows[0]) throw new WorkflowConflictError("final_place.id already exists; use an existing-place decision without final_place");
}

async function validateDecisionReferences(
  client: PoolClient,
  runId: string,
  userId: string,
  resultType: string | undefined,
  decision: UserDecisionInput,
): Promise<void> {
  if (decision.candidateId) {
    const { rows } = await client.query(
      `select pc.id
       from place_candidates pc
       join captures c on c.id = pc.capture_id
       where pc.id = $1 and pc.workflow_run_id = $2 and c.user_id = $3`,
      [decision.candidateId, runId, userId],
    );
    if (!rows[0]) throw new ApiError(404, "Workflow candidate not found");
  }
  if (decision.finalPlaceId) {
    const { rows } = await client.query("select id from places where id = $1 and user_id = $2", [decision.finalPlaceId, userId]);
    if (!rows[0]) throw new ApiError(404, "Final place not found");
  }
  if (["edit", "wrong_place", "wrong_city", "wrong_branch", "merge_existing"].includes(decision.action)
    && !decision.finalPlaceId
  ) {
    throw new WorkflowContractError(`${decision.action} requires a final_place_id owned by the requester`);
  }
  if (decision.action === "confirm" && !decision.candidateId && !decision.finalPlaceId) {
    throw new WorkflowContractError("confirm requires an owned candidate or final_place_id");
  }
  if (resultType === "source_only_clue" && decision.action === "confirm" && !decision.finalPlaceId) {
    throw new WorkflowContractError("source-only results require source_only or a resolved final_place_id");
  }
}

async function updateDecisionCandidateState(
  client: PoolClient,
  userId: string,
  decision: UserDecisionInput,
): Promise<void> {
  if (!decision.candidateId) return;
  const status = decision.action === "reject"
    ? "rejected"
    : decision.action === "source_only"
      ? "source_only"
      : decision.action === "needs_more_evidence" || decision.action === "investigate_more"
      ? "needs_more_evidence"
      : decision.finalPlaceId
        ? "saved"
        : "confirmed";
  await client.query(
    `update place_candidates pc
     set status = $1,
         place_id = coalesce($2, pc.place_id),
         updated_at = now()
     from captures c
     where pc.capture_id = c.id and pc.id = $3 and c.user_id = $4`,
    [status, decision.finalPlaceId ?? null, decision.candidateId, userId],
  );
}

async function persistWorkflowResultSteps(
  client: PoolClient,
  runId: string,
  attemptNo: number,
  result: PlaceRecoveryWorkerResult,
  outputHash: string,
): Promise<void> {
  const requiredSteps = [
    "validate_input",
    "fetch_or_resolve_source",
    "extract_or_recover_candidate",
    "resolve_place_identity",
    "persist_result",
  ] as const;
  const failedStepKey = result.failedStep ? workflowStepKeyForFailure(result.failedStep) : undefined;
  const failedIndex = failedStepKey ? requiredSteps.indexOf(failedStepKey as typeof requiredSteps[number]) : -1;

  for (const [index, stepKey] of requiredSteps.entries()) {
    const status = result.technicalFailure
      ? failedIndex === -1 || index < failedIndex
        ? "succeeded"
        : index === failedIndex
          ? "failed"
          : "skipped"
      : result.resultType === "source_only_clue" && stepKey === "resolve_place_identity"
        ? "skipped"
        : "succeeded";
    await upsertWorkflowStep(client, {
      runId,
      attemptNo,
      stepKey,
      status,
      errorCode: status === "failed" ? result.failureCode : undefined,
      outputHash,
      metadata: status === "failed" ? { retryable: result.retryable === true } : undefined,
    });
  }
  if (result.technicalFailure && result.failureCode && failedStepKey && failedIndex === -1) {
    await upsertWorkflowStep(client, {
      runId,
      attemptNo,
      stepKey: failedStepKey,
      status: "failed",
      errorCode: result.failureCode,
      outputHash,
      metadata: { retryable: result.retryable === true },
    });
  }
}

function workflowStepKeyForFailure(failedStep: string): string {
  if (failedStep === "validate_input") return "validate_input";
  if (failedStep === "fetch_source") return "fetch_or_resolve_source";
  if (["extract_source", "classify_source", "recover_candidate"].includes(failedStep)) {
    return "extract_or_recover_candidate";
  }
  if (failedStep === "resolve_map_identity") return "resolve_place_identity";
  if (failedStep === "persist_candidate") return "persist_result";
  return failedStep === "settle_credit" ? "settle_credit" : "write_receipt";
}

async function upsertWorkflowStep(client: PoolClient, input: {
  runId: string;
  attemptNo: number;
  stepKey: string;
  status: "succeeded" | "failed" | "skipped";
  inputHash?: string;
  outputHash?: string;
  errorCode?: string;
  metadata?: JsonBody;
}): Promise<void> {
  await client.query(
    `insert into workflow_steps (
       run_id, attempt_no, step_key, status, input, output, error,
       error_code, input_hash, output_hash, metadata, completed_at
     )
     values ($1, $2, $3, $4, '{}'::jsonb, '{}'::jsonb, null, $5, $6, $7, $8::jsonb, now())
     on conflict (run_id, attempt_no, step_key) do update set
       status = excluded.status,
       error_code = excluded.error_code,
       input_hash = excluded.input_hash,
       output_hash = excluded.output_hash,
       metadata = excluded.metadata,
       completed_at = excluded.completed_at`,
    [
      input.runId,
      input.attemptNo,
      input.stepKey,
      input.status,
      input.errorCode ?? null,
      input.inputHash ?? null,
      input.outputHash ?? null,
      JSON.stringify(input.metadata ?? {}),
    ],
  );
}

async function refreshWorkflowReputationSnapshot(
  client: PoolClient,
  userId: string,
  run: JsonBody,
  analysisReceipt: JsonBody,
): Promise<void> {
  const sourceType = boundedSafeDimension(run.source_type, 80);
  const operatorId = boundedSafeDimension(analysisReceipt.operator_id, 80);
  const provenanceBucket = boundedSafeDimension(analysisReceipt.model_provenance_bucket, 120);
  const subjectKey = [
    userId,
    placeRecoveryWorkflowId,
    placeRecoveryWorkflowVersion,
    sourceType,
    operatorId,
    provenanceBucket,
  ].join("|");
  await client.query("select pg_advisory_xact_lock(hashtext($1))", [subjectKey]);

  const { rows } = await client.query(
    `select
       r.id as run_id,
       r.result_type = 'technical_failure' as technical_failure,
       r.credit_settlement,
       ar.latency_ms,
       dr.user_feedback_action as decision_action
     from workflow_runs r
     join lateral (
       select wr.*
       from workflow_receipts wr
       where wr.run_id = r.id and wr.receipt_type = 'analysis' and wr.is_current = true
       order by wr.attempt_no desc, wr.created_at desc
       limit 1
     ) ar on true
     left join lateral (
       select wr.user_feedback_action
       from workflow_receipts wr
       where wr.run_id = r.id
         and wr.receipt_type = 'decision'
         and wr.is_current = true
         and wr.attempt_no = ar.attempt_no
       order by wr.created_at desc
       limit 1
     ) dr on true
     where r.user_id = $1
       and r.workflow_id = $2
       and ar.workflow_version = $3
       and r.source_type = $4
       and ar.operator_id = $5
       and ar.model_provenance_bucket = $6`,
    [
      userId,
      placeRecoveryWorkflowId,
      placeRecoveryWorkflowVersion,
      sourceType,
      operatorId,
      provenanceBucket,
    ],
  );
  const outcomes = rows.map((row) => {
    const value = asObject(row);
    const action = stringValue(value.decision_action);
    return {
      runId: String(value.run_id),
      isCurrent: true,
      settled: parseCreditSettlement(value.credit_settlement) !== "pending",
      technicalFailure: value.technical_failure === true,
      decisionAction: action && isUserDecisionAction(action) ? action : undefined,
      creditSettlement: parseCreditSettlement(value.credit_settlement),
      latencyMs: value.latency_ms === null || value.latency_ms === undefined ? undefined : Number(value.latency_ms),
    };
  });
  const counters = reconcileReputation(outcomes);

  await client.query(
    `update workflow_reputation_snapshots
     set is_current = false
     where requester_id = $1
       and workflow_id = $2
       and workflow_version = $3
       and source_type = $4
       and operator_id = $5
       and model_provenance_bucket = $6
       and policy_version = 'v0'
       and is_current = true`,
    [userId, placeRecoveryWorkflowId, placeRecoveryWorkflowVersion, sourceType, operatorId, provenanceBucket],
  );
  const snapshotInsert = buildInsert("workflow_reputation_snapshots", {
    requester_id: userId,
    listing_id: String(run.listing_id),
    workflow_id: placeRecoveryWorkflowId,
    workflow_version: placeRecoveryWorkflowVersion,
    source_type: sourceType,
    operator_id: operatorId,
    model_provenance_bucket: provenanceBucket,
    policy_version: "v0",
    is_current: true,
    run_count: counters.runCount,
    operational_success_count: counters.operationalSuccessCount,
    technical_failure_count: counters.technicalFailureCount,
    confirmed_count: counters.confirmedCount,
    edited_count: counters.editedCount,
    rejected_count: counters.rejectedCount,
    source_only_count: counters.sourceOnlyCount,
    refund_count: counters.refundCount,
    median_latency_ms: counters.medianLatencyMs,
    user_decision_coverage: counters.userDecisionCoverage,
    operational_success_rate: counters.operationalSuccessRate,
    confirmation_rate: counters.confirmationRate,
    edit_rate: counters.editRate,
    rejection_rate: counters.rejectionRate,
    technical_failure_rate: counters.technicalFailureRate,
    pass_count: counters.confirmedCount,
    partial_count: counters.editedCount + counters.sourceOnlyCount,
    fail_count: counters.technicalFailureCount + counters.rejectedCount,
    confirmed_save_count: counters.confirmedCount,
    user_rejection_count: counters.rejectedCount,
    hallucination_report_count: 0,
  }, workflowReputationSnapshotFields);
  await client.query(snapshotInsert.sql, snapshotInsert.values);
}

function parseCreditSettlement(value: unknown): "pending" | "consumed" | "refunded" | "partial" {
  return value === "consumed" || value === "refunded" || value === "partial" ? value : "pending";
}

function isUserDecisionAction(value: string): value is UserDecisionInput["action"] {
  return [
    "confirm", "edit", "reject", "source_only", "wrong_place", "wrong_city",
    "wrong_branch", "merge_existing", "needs_more_evidence", "investigate_more",
  ].includes(value);
}

async function clearingBlockForUser(blockId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    "select * from clearing_blocks where id = $1 and user_id = $2",
    [blockId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Clearing block not found");
  return asObject(rows[0]);
}

async function createClearingBlockForPendingReceipts(userId: string, body: JsonBody): Promise<JsonBody> {
  const limit = boundedClearingBlockLimit(body.limit);
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("select pg_advisory_xact_lock(hashtext($1))", [`${placeRecoveryWorkflowId}:${userId}:clearing`]);
    const { rows: receiptRows } = await client.query(
      `select wr.id, wr.receipt_hash
       from workflow_receipts wr
       join workflow_runs r on r.id = wr.run_id
       where r.user_id = $1
         and wr.workflow_id = $2
         and wr.requester_id = $1
         and wr.is_current = true
         and wr.attempt_no = r.current_attempt_no
         and wr.receipt_hash is not null
         and wr.privacy_validated = true
         and wr.anchor_status = 'offchain'
         and (
           wr.settlement in ('credit_consumed', 'credit_refunded', 'partial')
           or (wr.receipt_type = 'analysis' and wr.settlement = 'manual_review')
         )
         and not exists (
           select 1
           from workflow_receipts superseding
           where superseding.supersedes_receipt_id = wr.id
             and superseding.is_current = true
         )
         and not exists (
           select 1 from clearing_block_items cbi where cbi.receipt_id = wr.id
         )
       order by wr.created_at asc, wr.id asc
       limit $3
       for update of wr skip locked`,
      [userId, placeRecoveryWorkflowId, limit],
    );

    if (!receiptRows.length) {
      await client.query("commit");
      return { created: false, pending_receipt_count: 0 };
    }

    const { rows: previousRows } = await client.query(
      `select block_number, block_hash
       from clearing_blocks
       where user_id = $1 and chain_namespace = $2
       order by block_number desc
       limit 1
       for update`,
      [userId, placeRecoveryWorkflowId],
    );
    const previous = previousRows[0] ? asObject(previousRows[0]) : {};
    const blockNumber = Number(previous.block_number ?? 0) + 1;
    const previousBlockHash = stringValue(previous.block_hash);
    const receipts = receiptRows.map((row) => {
      const receipt = asObject(row);
      return {
        id: String(receipt.id),
        receiptHash: String(receipt.receipt_hash),
      };
    });
    const draft = buildClearingBlockDraft({
      chainNamespace: placeRecoveryWorkflowId,
      blockNumber,
      previousBlockHash,
      receipts,
    });

    const blockInsert = buildInsert("clearing_blocks", {
      chain_namespace: draft.chainNamespace,
      user_id: userId,
      block_number: draft.blockNumber,
      previous_block_hash: draft.previousBlockHash ?? null,
      merkle_root: draft.merkleRoot,
      receipt_count: draft.receiptCount,
      block_hash: draft.blockHash,
      signer_agent_id: "save-backend",
      anchor_status: "offchain",
      anchor_chain: null,
      anchor_tx_hash: null,
    }, clearingBlockFields);
    const { rows: blockRows } = await client.query(`${blockInsert.sql} returning *`, blockInsert.values);
    const block = asObject(blockRows[0]);

    const items: JsonBody[] = [];
    for (const [position, receipt] of receipts.entries()) {
      const itemInsert = buildInsert("clearing_block_items", {
        block_id: block.id,
        receipt_id: receipt.id,
        receipt_hash: receipt.receiptHash,
        merkle_proof: [],
        position,
      }, clearingBlockItemFields);
      const { rows } = await client.query(`${itemInsert.sql} returning *`, itemInsert.values);
      items.push(asObject(rows[0]));
    }

    await client.query(
      "update workflow_receipts set anchor_status = 'batch_anchored' where id = any($1::uuid[])",
      [receipts.map((receipt) => receipt.id)],
    );
    await client.query("commit");
    return {
      created: true,
      block: formatDates(block),
      items: items.map((item) => formatDates(item)),
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function syncWorkOrderStatusForRun(run: JsonBody, status: string): Promise<void> {
  const workOrderId = stringValue(run.work_order_id);
  const userId = stringValue(run.user_id);
  if (!workOrderId || !userId) return;
  await pool.query("update work_orders set status = $1 where id = $2 and user_id = $3", [status, workOrderId, userId]);
}

function boundedClearingBlockLimit(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value)) return 50;
  return Math.max(1, Math.min(100, value));
}

async function uniqueShareCode(): Promise<string> {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const code = randomBytes(6).toString("base64url");
    const { rows } = await pool.query("select code from shared_place_links where code = $1", [code]);
    if (!rows[0]) return code;
  }
  throw new ApiError(500, "Could not allocate share code");
}

async function insertCreditLedger(client: PoolClient, body: JsonBody): Promise<void> {
  const insert = buildInsert("credit_ledger", body, creditLedgerFields);
  await client.query(insert.sql, insert.values);
}

function workflowReceiptBody(runId: string, receipt: {
  receiptType: string;
  workflowVersion: string;
  jobId?: string;
  agentId: string;
  operatorId?: string;
  permissionSnapshot: JsonBody;
  toolTraceRefs: string[];
  latencyMs?: number;
  costEstimate?: JsonBody;
  failureReason?: string;
  failureCode?: string;
  failedStep?: string;
  retryable?: boolean;
  userFeedbackAction?: string;
  qualityDelta: number;
  reputationDelta: number;
  modelProvenance: JsonBody;
  verdict: string;
  settlement: string;
  evaluatorSummary: string;
  evidenceRefs: string[];
  candidateRefs: string[];
}, context: {
  run: JsonBody;
  userId: string;
  output: unknown;
  attemptNo: number;
  resultRevision: number;
  idempotencyKey: string;
  supersedesReceiptId?: string;
  isCurrent: boolean;
  outputHash: string;
  decisionId?: string;
}): JsonBody {
  const inputHash = sha256CanonicalJson({
    sourceUrl: context.run?.source_url ?? null,
    sourceType: context.run?.source_type ?? null,
    workOrderId: context.run?.work_order_id ?? null,
  });
  const modelProvenance = safeModelProvenance(receipt.modelProvenance);
  const envelope: JsonBody = {
    run_id: runId,
    workflow_id: placeRecoveryWorkflowId,
    workflow_version: receipt.workflowVersion,
    operator_id: receipt.operatorId ?? receipt.agentId,
    requester_id: context.userId,
    receipt_type: receipt.receiptType,
    attempt_no: context.attemptNo,
    result_revision: context.resultRevision,
    idempotency_key: context.idempotencyKey,
    supersedes_receipt_id: context.supersedesReceiptId ?? null,
    is_current: context.isCurrent,
    failure_code: receipt.failureCode ?? null,
    failed_step: receipt.failedStep ?? null,
    retryable: receipt.retryable ?? null,
    decision_id: context.decisionId ?? null,
    job_id: receipt.jobId ?? null,
    agent_id: receipt.agentId,
    model_provenance: modelProvenance,
    model_provenance_bucket: modelProvenanceBucket(modelProvenance),
    input_hash: inputHash,
    output_hash: context.outputHash,
    permission_snapshot: receipt.permissionSnapshot,
    tool_trace_refs: safeOpaqueRefs(receipt.toolTraceRefs),
    latency_ms: receipt.latencyMs ?? null,
    cost_estimate: receipt.costEstimate ?? null,
    failure_reason: receipt.failureCode ?? null,
    user_feedback_action: receipt.userFeedbackAction ?? null,
    quality_delta: receipt.qualityDelta,
    reputation_delta: receipt.reputationDelta,
    verdict: receipt.verdict,
    settlement: receipt.settlement,
    evaluator_summary: receipt.evaluatorSummary,
    evidence_refs: safeOpaqueRefs(receipt.evidenceRefs),
    candidate_refs: safeOpaqueRefs(receipt.candidateRefs),
    anchor_status: "offchain",
    private_url: null,
    privacy_validated: true,
  };
  return {
    ...envelope,
    receipt_hash: sha256ImmutableWorkflowReceipt(envelope),
  };
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

async function lockProfileSubject(client: PoolClient, privySubject: string): Promise<void> {
  await client.query(
    "select pg_advisory_xact_lock(hashtext($1))",
    [`save-profile-subject:v0:${privySubject}`],
  );
}

async function linkPrivyUserToProfile(profileId: string, privyUserId: string): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await lockProfileSubject(client, privyUserId);
    const { rows: existingRows } = await client.query(
      `select id, privy_user_id
       from profiles
       where id = $1 or privy_user_id = $1
       for update`,
      [privyUserId],
    );
    const hasConflict = existingRows.some((row) => {
      const existingId = typeof row.id === "string" ? row.id : "";
      const existingBinding = typeof row.privy_user_id === "string" ? row.privy_user_id : "";
      return existingId !== profileId
        || (existingBinding.length > 0 && existingBinding !== privyUserId);
    });
    if (hasConflict) throw new Error("Privy profile link conflict");

    const { rows } = await client.query(
      `update profiles
       set privy_user_id = $2, updated_at = now()
       where id = $1 and (privy_user_id is null or privy_user_id = $2)
       returning id`,
      [profileId, privyUserId],
    );
    if (!rows[0]) throw new Error("Privy profile link target unavailable");
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function ensurePrivyPhoneProfile(
  phoneE164: string,
  profileId: string,
  existingPrivyUserId: unknown,
): Promise<void> {
  if (typeof existingPrivyUserId === "string" && existingPrivyUserId.trim()) return;
  if (!privyUserProvisioner) return;
  try {
    const privyUser = await privyUserProvisioner.ensureUserForPhone(phoneE164);
    if (privyUser?.id) {
      await linkPrivyUserToProfile(profileId, privyUser.id);
    }
  } catch (error) {
    console.error(`[sendblue] privy phone provisioning failed kind=${safeErrorKind(error)}`);
  }
}

async function resolveUserId(request: IncomingMessage): Promise<string> {
  const header = request.headers.authorization ?? "";
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) {
    const privySubject = await verifiedPrivySubject(token);
    return await profileIdForPrivySubject(privySubject);
  }

  const guestToken = request.headers["x-save-guest-token"] ?? request.headers["x-wanderly-guest-token"];
  const normalizedGuestToken = Array.isArray(guestToken) ? guestToken[0] : guestToken;
  if (typeof normalizedGuestToken === "string") {
    const guestUserId = userIdFromGuestSessionToken(normalizedGuestToken, guestSessionSecret);
    if (guestUserId) return guestUserId;
  }

  throw new ApiError(401, "Missing bearer token or guest session");
}

async function profileIdForPrivySubject(privySubject: string): Promise<string> {
  const client = await pool.connect();
  let transactionStarted = false;
  let transactionFinished = false;
  try {
    await client.query("begin");
    transactionStarted = true;
    await lockProfileSubject(client, privySubject);

    const resolution = await resolveProfileSubject(
      privySubject,
      (sql, values) => client.query(sql, [...values] as QueryValue[]),
    );
    if (resolution.conflictingRawBinding) {
      throw new ApiError(409, "Account profile binding conflict");
    }

    await client.query(
      `insert into profiles (id, display_name)
       values ($1, 'SAV-E User')
       on conflict (id) do nothing`,
      [resolution.profileId],
    );
    await client.query("commit");
    transactionFinished = true;
    return resolution.profileId;
  } catch (error) {
    if (transactionStarted && !transactionFinished) {
      try {
        await client.query("rollback");
      } catch {
        // Preserve the original failure; this client is released below.
      }
    }
    throw error;
  } finally {
    client.release();
  }
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

async function readJson(request: IncomingMessage, maxBytes = defaultJsonBodyMaxBytes): Promise<JsonBody> {
  const chunks: Buffer[] = [];
  let byteLength = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteLength += buffer.byteLength;
    if (byteLength > maxBytes) throw new ApiError(413, "JSON payload is too large");
    chunks.push(buffer);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  return asObject(JSON.parse(raw));
}

async function boundedResponseBuffer(response: Response, maxBytes: number): Promise<Uint8Array> {
  const length = Number(response.headers.get("content-length") ?? "0");
  if (length > maxBytes) throw new ApiError(502, "Upstream response is too large");
  if (!response.body) return new Uint8Array();

  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  const reader = response.body.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteLength += value.byteLength;
    if (byteLength > maxBytes) {
      await reader.cancel();
      throw new ApiError(502, "Upstream response is too large");
    }
    chunks.push(value);
  }

  const data = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return data;
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
    "Access-Control-Allow-Headers": "authorization, content-type, x-save-guest-token, x-wanderly-guest-token",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Content-Type": "application/json",
  });
  response.end(status === 204 ? undefined : JSON.stringify(body));
}

function sendHtml(response: ServerResponse, body: string, status = 200): void {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "private, no-store",
    "X-Robots-Tag": "noindex, nofollow",
  });
  response.end(body);
}

function formatPlace(row: JsonBody): JsonBody {
  const { origin_shared_place_link_id: _originSharedPlaceLinkId, ...publicPlace } = row;
  return formatDates(publicPlace);
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

function databaseSSLConfig(url: string): undefined | { rejectUnauthorized: boolean; ca?: string } {
  const sslMode = process.env.PGSSLMODE?.trim().toLowerCase();
  if (sslMode === "disable") return undefined;
  let hostname = "";
  try {
    hostname = new URL(url).hostname.toLowerCase();
  } catch {
    hostname = "";
  }
  if (hostname === "localhost" || hostname === "127.0.0.1" || hostname.endsWith(".railway.internal")) {
    return undefined;
  }
  if (sslMode === "no-verify") return { rejectUnauthorized: false };
  const ca = process.env.DATABASE_CA_CERT?.replace(/\\n/g, "\n");
  return ca ? { rejectUnauthorized: true, ca } : { rejectUnauthorized: true };
}

class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
