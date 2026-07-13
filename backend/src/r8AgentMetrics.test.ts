import assert from "node:assert/strict";
import test from "node:test";
import {
  R8AgentMetricsQueryError,
  aggregateR8PilotMetrics,
  authorizeR8AgentMetrics,
  normalizeR8AgentMetricsQuery,
  r8AgentMetricsFailureLabels,
  r8AgentMetricsSql,
} from "./r8AgentMetrics.js";

const token = "test-internal-agent-token-at-least-32-characters";

test("internal agent authorization fails closed and accepts only the configured bearer token", () => {
  assert.equal(authorizeR8AgentMetrics(undefined, undefined), "unavailable");
  assert.equal(authorizeR8AgentMetrics(undefined, "Bearer wrong"), "unavailable");
  assert.equal(authorizeR8AgentMetrics(undefined, `Bearer ${token}`), "unavailable");
  assert.equal(authorizeR8AgentMetrics("", `Bearer ${token}`), "unavailable");
  assert.equal(authorizeR8AgentMetrics("too-short", "Bearer too-short"), "unavailable");
  assert.equal(authorizeR8AgentMetrics(token, undefined), "unauthorized");
  assert.equal(authorizeR8AgentMetrics(token, token), "unauthorized");
  assert.equal(authorizeR8AgentMetrics(token, "Bearer wrong"), "unauthorized");
  assert.equal(authorizeR8AgentMetrics(token, `Bearer ${token}`), "authorized");
});

test("pilot metric query defaults and bounds are deterministic", () => {
  assert.deepEqual(normalizeR8AgentMetricsQuery(new URLSearchParams()), { days: 30, limit: 100 });
  assert.deepEqual(normalizeR8AgentMetricsQuery(new URLSearchParams("days=7&limit=5")), { days: 7, limit: 5 });

  for (const query of ["days=0", "days=366", "days=1.5", "limit=0", "limit=101", "limit=nope"]) {
    assert.throws(
      () => normalizeR8AgentMetricsQuery(new URLSearchParams(query)),
      R8AgentMetricsQueryError,
    );
  }
});

test("pilot metrics keep technical verdicts separate from latest product outcomes", () => {
  const response = aggregateR8PilotMetrics({
    rows: [
      {
        user_id: "private-user-a",
        analysis_total: 4,
        technical_pass: 2,
        technical_partial: 1,
        technical_fail: 1,
        technical_manual_review: 0,
        linked_outcomes: 3,
        product_success: 1,
        product_failure: 1,
        product_unresolved: 1,
        last_activity_at: "2026-07-13T16:42:01.000Z",
      },
      {
        user_id: "private-user-b",
        analysis_total: 1,
        technical_pass: 1,
        technical_partial: 0,
        technical_fail: 0,
        technical_manual_review: 0,
        linked_outcomes: 0,
        product_success: 0,
        product_failure: 0,
        product_unresolved: 0,
        last_activity_at: "2026-07-12T04:12:00.000Z",
      },
    ],
    token,
    days: 30,
    limit: 1,
    generatedAt: "2026-07-13T17:00:00.000Z",
  });

  assert.equal(response.cohort.users_total, 2);
  assert.equal(response.cohort.users_returned, 1);
  assert.equal(response.cohort.analysis_total, 5);
  assert.equal(response.cohort.technical.pass, 3);
  assert.equal(response.cohort.product.success, 1);
  assert.equal(response.cohort.product.failure, 1);
  assert.equal(response.cohort.product.unresolved, 1);
  assert.equal(response.cohort.product.pending, 2);
  assert.equal(response.cohort.feedback_coverage_rate, 0.6);
  assert.equal(response.window.starts_at, "2026-06-13T17:00:00.000Z");

  const user = response.users[0];
  assert.equal(user.analysis_total, 4);
  assert.deepEqual(user.technical, { pass: 2, partial: 1, fail: 1, manual_review: 0 });
  assert.deepEqual(user.product, { success: 1, failure: 1, unresolved: 1, pending: 1 });
  assert.equal(user.feedback_coverage_rate, 0.75);
  assert.equal(user.repeat_usage, true);
  assert.equal(user.last_activity_date, "2026-07-13");
  assert.match(user.user_ref, /^save_user_[A-Za-z0-9_-]{22}$/);

  const serialized = JSON.stringify(response);
  assert.doesNotMatch(serialized, /private-user-a|private-user-b/);
  assert.match(serialized, /technical evaluator verdicts do not establish user success/i);
});

test("user pseudonyms are stable for one token and change when the token rotates", () => {
  const input = {
    rows: [{
      user_id: "private-user-a",
      analysis_total: 1,
      technical_pass: 1,
      technical_partial: 0,
      technical_fail: 0,
      technical_manual_review: 0,
      linked_outcomes: 0,
      product_success: 0,
      product_failure: 0,
      product_unresolved: 0,
      last_activity_at: "2026-07-13T16:42:01.000Z",
    }],
    days: 30,
    limit: 100,
    generatedAt: "2026-07-13T17:00:00.000Z",
  };
  const first = aggregateR8PilotMetrics({ ...input, token }).users[0].user_ref;
  const second = aggregateR8PilotMetrics({ ...input, token }).users[0].user_ref;
  const rotated = aggregateR8PilotMetrics({ ...input, token: `${token}-rotated` }).users[0].user_ref;

  assert.equal(first, second);
  assert.notEqual(first, rotated);
});

test("empty cohorts use zero coverage and tied activity is ordered by pseudonymous user ref", () => {
  const empty = aggregateR8PilotMetrics({
    rows: [],
    token,
    days: 30,
    limit: 100,
    generatedAt: "2026-07-13T17:00:00.000Z",
  });
  assert.equal(empty.cohort.feedback_coverage_rate, 0);
  assert.equal(empty.cohort.users_total, 0);
  assert.deepEqual(empty.users, []);

  const tiedRows = ["private-user-z", "private-user-a"].map((userId) => ({
    user_id: userId,
    analysis_total: 1,
    technical_pass: 1,
    technical_partial: 0,
    technical_fail: 0,
    technical_manual_review: 0,
    linked_outcomes: 0,
    product_success: 0,
    product_failure: 0,
    product_unresolved: 0,
    last_activity_at: "2026-07-13T16:42:01.000Z",
  }));
  const tied = aggregateR8PilotMetrics({
    rows: tiedRows,
    token,
    days: 30,
    limit: 2,
    generatedAt: "2026-07-13T17:00:00.000Z",
  });
  const refs = tied.users.map((user) => user.user_ref);
  assert.deepEqual(refs, [...refs].sort());
});

test("aggregate SQL deduplicates latest outcomes, enforces same-owner links, and excludes private fields", () => {
  const normalized = r8AgentMetricsSql.toLowerCase().replace(/\s+/g, " ");
  assert.match(normalized, /distinct on \(user_id, recommendation_id\)/);
  assert.match(normalized, /from recommendation_outcomes where created_at <= \$2 and label_source = 'explicit_user'/);
  assert.match(normalized, /outcome\.user_id = receipt\.user_id/);
  assert.match(normalized, /outcome\.recommendation_id = receipt\.id::text/);
  assert.match(normalized, /useful_recommendation/);
  assert.match(normalized, /created_at <= \$2/);
  assert.match(normalized, /\$3::text\[\]/);
  assert.ok(r8AgentMetricsFailureLabels.includes("wrong_place"));
  assert.ok(r8AgentMetricsFailureLabels.includes("preference_mismatch"));
  assert.doesNotMatch(normalized, /private_payload|public_summary|preference_signals|evidence_refs|memory_refs|candidate_ids|place_ids/);
});
