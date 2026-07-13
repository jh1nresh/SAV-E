import { createHash, createHmac, timingSafeEqual } from "node:crypto";

export type R8AgentMetricsAuthorization = "authorized" | "unauthorized" | "unavailable";

export class R8AgentMetricsQueryError extends Error {}

export interface R8AgentMetricsQuery {
  days: number;
  limit: number;
}

export interface R8AgentMetricsRow {
  user_id: string;
  analysis_total: number | string;
  technical_pass: number | string;
  technical_partial: number | string;
  technical_fail: number | string;
  technical_manual_review: number | string;
  linked_outcomes: number | string;
  product_success: number | string;
  product_failure: number | string;
  product_unresolved: number | string;
  last_activity_at: Date | string;
}

interface MetricCounts {
  success: number;
  failure: number;
  unresolved: number;
  pending: number;
}

interface TechnicalCounts {
  pass: number;
  partial: number;
  fail: number;
  manual_review: number;
}

export interface R8PilotMetricsResponse {
  window: {
    days: number;
    starts_at: string;
    generated_at: string;
  };
  cohort: {
    users_total: number;
    users_returned: number;
    analysis_total: number;
    linked_outcomes: number;
    feedback_coverage_rate: number;
    technical: TechnicalCounts;
    product: MetricCounts;
  };
  users: Array<{
    user_ref: string;
    analysis_total: number;
    linked_outcomes: number;
    feedback_coverage_rate: number;
    repeat_usage: boolean;
    technical: TechnicalCounts;
    product: MetricCounts;
    last_activity_date: string;
  }>;
  definitions: {
    technical: string;
    feedback_coverage: string;
    repeat_usage: string;
    product_success: string;
    product_failure: string;
    product_unresolved: string;
    product_pending: string;
  };
}

export const r8AgentMetricsFailureLabels = [
  "wrong_place",
  "irrelevant_recommendation",
  "missing_evidence",
  "hallucinated_fact",
  "preference_mismatch",
  "stale_place_or_menu",
  "action_overclaim",
] as const;

export const r8AgentMetricsSql = `
with latest_outcomes as (
  select distinct on (user_id, recommendation_id)
    user_id,
    recommendation_id,
    labels,
    created_at
  from recommendation_outcomes
  where created_at <= $2 and label_source = 'explicit_user'
  order by user_id, recommendation_id, created_at desc, id desc
),
windowed_receipts as (
  select id, user_id, evaluator_verdict, created_at
  from recommendation_analysis_receipts
  where created_at >= $1 and created_at <= $2
)
select
  receipt.user_id,
  count(*)::int as analysis_total,
  count(*) filter (where receipt.evaluator_verdict = 'pass')::int as technical_pass,
  count(*) filter (where receipt.evaluator_verdict = 'partial')::int as technical_partial,
  count(*) filter (where receipt.evaluator_verdict = 'fail')::int as technical_fail,
  count(*) filter (where receipt.evaluator_verdict = 'manual_review')::int as technical_manual_review,
  count(outcome.recommendation_id)::int as linked_outcomes,
  count(*) filter (
    where 'useful_recommendation' = any(coalesce(outcome.labels, '{}'::text[]))
  )::int as product_success,
  count(*) filter (
    where not ('useful_recommendation' = any(coalesce(outcome.labels, '{}'::text[])))
      and coalesce(outcome.labels, '{}'::text[]) && $3::text[]
  )::int as product_failure,
  count(*) filter (
    where outcome.recommendation_id is not null
      and not ('useful_recommendation' = any(coalesce(outcome.labels, '{}'::text[])))
      and not (coalesce(outcome.labels, '{}'::text[]) && $3::text[])
  )::int as product_unresolved,
  greatest(max(receipt.created_at), max(outcome.created_at)) as last_activity_at
from windowed_receipts receipt
left join latest_outcomes outcome
  on outcome.user_id = receipt.user_id
 and outcome.recommendation_id = receipt.id::text
group by receipt.user_id
order by last_activity_at desc, receipt.user_id
`;

export function authorizeR8AgentMetrics(
  configuredToken: string | undefined,
  authorizationHeader: string | undefined,
): R8AgentMetricsAuthorization {
  const expected = configuredToken?.trim();
  if (!expected || expected.length < 32) return "unavailable";

  const match = authorizationHeader?.match(/^Bearer ([^\s]+)$/);
  if (!match) return "unauthorized";

  const expectedDigest = createHash("sha256").update(expected).digest();
  const presentedDigest = createHash("sha256").update(match[1]).digest();
  return timingSafeEqual(expectedDigest, presentedDigest) ? "authorized" : "unauthorized";
}

export function normalizeR8AgentMetricsQuery(searchParams: URLSearchParams): R8AgentMetricsQuery {
  return {
    days: boundedInteger(searchParams.get("days"), "days", 1, 365, 30),
    limit: boundedInteger(searchParams.get("limit"), "limit", 1, 100, 100),
  };
}

export function aggregateR8PilotMetrics(input: {
  rows: R8AgentMetricsRow[];
  token: string;
  days: number;
  limit: number;
  generatedAt?: string;
}): R8PilotMetricsResponse {
  const generatedAt = input.generatedAt ?? new Date().toISOString();
  const startsAt = new Date(new Date(generatedAt).getTime() - input.days * 24 * 60 * 60 * 1000).toISOString();
  const users = input.rows
    .map((row) => ({
      metrics: userMetrics(row, input.token),
      lastActivityTime: new Date(row.last_activity_at).getTime(),
    }))
    .sort((left, right) =>
      right.lastActivityTime - left.lastActivityTime
        || compareOpaqueRefs(left.metrics.user_ref, right.metrics.user_ref))
    .map(({ metrics }) => metrics);
  const returnedUsers = users.slice(0, input.limit);
  const cohort = users.reduce(
    (summary, user) => {
      summary.analysis_total += user.analysis_total;
      summary.linked_outcomes += user.linked_outcomes;
      addTechnical(summary.technical, user.technical);
      addProduct(summary.product, user.product);
      return summary;
    },
    {
      users_total: users.length,
      users_returned: returnedUsers.length,
      analysis_total: 0,
      linked_outcomes: 0,
      feedback_coverage_rate: 0,
      technical: emptyTechnical(),
      product: emptyProduct(),
    },
  );
  cohort.feedback_coverage_rate = rate(cohort.linked_outcomes, cohort.analysis_total);

  return {
    window: {
      days: input.days,
      starts_at: startsAt,
      generated_at: generatedAt,
    },
    cohort,
    users: returnedUsers,
    definitions: {
      technical: "Technical evaluator verdicts do not establish user success.",
      feedback_coverage: "Latest linked explicit user outcomes divided by analysis receipts in the observation window.",
      repeat_usage: "Two or more analysis receipts for the same pseudonymous user in the observation window.",
      product_success: "Latest linked explicit user outcome contains useful_recommendation.",
      product_failure: "Latest linked explicit user outcome contains a failure label and no useful_recommendation.",
      product_unresolved: "Latest linked explicit user outcome contains neither a useful nor failure label.",
      product_pending: "Analysis receipt has no linked explicit user outcome.",
    },
  };
}

function userMetrics(row: R8AgentMetricsRow, token: string): R8PilotMetricsResponse["users"][number] {
  const analysisTotal = count(row.analysis_total);
  const linkedOutcomes = count(row.linked_outcomes);
  const success = count(row.product_success);
  const failure = count(row.product_failure);
  const unresolved = count(row.product_unresolved);

  return {
    user_ref: `save_user_${createHmac("sha256", token)
      .update("r8-pilot-user-ref:v0\0")
      .update(row.user_id)
      .digest("base64url")
      .slice(0, 22)}`,
    analysis_total: analysisTotal,
    linked_outcomes: linkedOutcomes,
    feedback_coverage_rate: rate(linkedOutcomes, analysisTotal),
    repeat_usage: analysisTotal >= 2,
    technical: {
      pass: count(row.technical_pass),
      partial: count(row.technical_partial),
      fail: count(row.technical_fail),
      manual_review: count(row.technical_manual_review),
    },
    product: {
      success,
      failure,
      unresolved,
      pending: Math.max(0, analysisTotal - linkedOutcomes),
    },
    last_activity_date: new Date(row.last_activity_at).toISOString().slice(0, 10),
  };
}

function boundedInteger(
  value: string | null,
  field: string,
  min: number,
  max: number,
  fallback: number,
): number {
  if (value === null) return fallback;
  if (!/^\d+$/.test(value)) throw new R8AgentMetricsQueryError(`${field} must be an integer`);
  const parsed = Number(value);
  if (parsed < min || parsed > max) {
    throw new R8AgentMetricsQueryError(`${field} must be between ${min} and ${max}`);
  }
  return parsed;
}

function count(value: number | string): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.trunc(parsed) : 0;
}

function rate(numerator: number, denominator: number): number {
  if (denominator === 0) return 0;
  return Math.round((numerator / denominator) * 10_000) / 10_000;
}

function compareOpaqueRefs(left: string, right: string): number {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

function emptyTechnical(): TechnicalCounts {
  return { pass: 0, partial: 0, fail: 0, manual_review: 0 };
}

function emptyProduct(): MetricCounts {
  return { success: 0, failure: 0, unresolved: 0, pending: 0 };
}

function addTechnical(target: TechnicalCounts, source: TechnicalCounts): void {
  target.pass += source.pass;
  target.partial += source.partial;
  target.fail += source.fail;
  target.manual_review += source.manual_review;
}

function addProduct(target: MetricCounts, source: MetricCounts): void {
  target.success += source.success;
  target.failure += source.failure;
  target.unresolved += source.unresolved;
  target.pending += source.pending;
}
