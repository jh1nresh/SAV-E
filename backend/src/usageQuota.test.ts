import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  betaUsageQuotaPolicy,
  buildGeminiUsageEvent,
  buildUsageQuotaPreview,
} from "./usageQuota.js";

test("successful Gemini responses consume one AI-assist unit and retain aggregate token counts only", () => {
  const event = buildGeminiUsageEvent({
    model: "gemini-3.5-flash",
    outcome: "success",
    upstreamStatus: 200,
    latencyMs: 412.8,
    responseBody: {
      candidates: [{ content: { parts: [{ text: "private generated answer" }] } }],
      usageMetadata: {
        promptTokenCount: 120,
        candidatesTokenCount: 30,
        totalTokenCount: 150,
      },
    },
  });

  assert.equal(event.units, 1);
  assert.equal(event.inputTokens, 120);
  assert.equal(event.outputTokens, 30);
  assert.equal(event.totalTokens, 150);
  assert.equal(event.latencyMs, 412);
  assert.equal(JSON.stringify(event).includes("private generated answer"), false);
});

test("technical failures consume zero units even when the provider returns an error", () => {
  const upstreamFailure = buildGeminiUsageEvent({
    model: "gemini-3.5-flash",
    outcome: "upstream_failure",
    upstreamStatus: 503,
    latencyMs: 90,
    responseBody: { usageMetadata: { totalTokenCount: 40 }, error: "private provider detail" },
  });
  const transportFailure = buildGeminiUsageEvent({
    model: "gemini-3.5-flash",
    outcome: "transport_failure",
    latencyMs: 20,
  });

  assert.equal(upstreamFailure.units, 0);
  assert.equal(transportFailure.units, 0);
  assert.equal(JSON.stringify(upstreamFailure).includes("private provider detail"), false);
});

test("monthly preview warns at 15, never enforces, and clamps remaining units", () => {
  const now = new Date("2026-08-13T18:00:00.000Z");
  const warning = buildUsageQuotaPreview({ usedUnits: "15", now, meteringAvailable: true });
  const reached = buildUsageQuotaPreview({ usedUnits: 24, now, meteringAvailable: true });

  assert.equal(betaUsageQuotaPolicy.monthlyLimitUnits, 20);
  assert.equal(warning.state, "warning");
  assert.equal(warning.remaining_units, 5);
  assert.equal(warning.period_start, "2026-08-01T00:00:00.000Z");
  assert.equal(warning.period_end, "2026-09-01T00:00:00.000Z");
  assert.equal(reached.state, "preview_limit_reached");
  assert.equal(reached.remaining_units, 0);
  assert.equal(reached.enforced, false);
  assert.equal(reached.beta_access_continues, true);
});

test("missing metering schema reports warming up instead of inventing usage", () => {
  const preview = buildUsageQuotaPreview({
    usedUnits: 9,
    now: new Date("2026-08-13T18:00:00.000Z"),
    meteringAvailable: false,
  });

  assert.equal(preview.state, "warming_up");
  assert.equal(preview.used_units, null);
  assert.equal(preview.remaining_units, null);
  assert.equal(preview.enforced, false);
  assert.equal(preview.beta_access_continues, true);
});

test("usage schema and route stay owner-scoped, server-authored, and payload-free", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const tableStart = schema.indexOf("create table if not exists ai_usage_events");
  const tableEnd = schema.indexOf("create index if not exists idx_ai_usage_events_user_created");
  const table = schema.slice(tableStart, tableEnd);
  const authStart = server.indexOf("const userId = await resolveUserId(request)");
  const quotaRoute = server.indexOf('resource === "usage" && id === "quota"');

  assert.notEqual(tableStart, -1);
  assert.match(table, /user_id text references profiles\(id\)/);
  assert.doesNotMatch(table, /prompt|payload|source_url|place_name|private_note/);
  assert.ok(quotaRoute > authStart, "quota preview must stay behind authenticated user resolution");
  assert.match(server, /where user_id = \$1[\s\S]*created_at >=/);
  assert.match(server, /AI usage telemetry unavailable; request remains fail-open/);
});

test("the preview defaults to the free tier for callers that predate entitlements", () => {
  const preview = buildUsageQuotaPreview({ usedUnits: 4, meteringAvailable: true });

  assert.equal(preview.tier, "free");
  assert.equal(preview.limit_units, betaUsageQuotaPolicy.monthlyLimitUnits);
  assert.equal(preview.warning_threshold_units, betaUsageQuotaPolicy.warningThresholdUnits);
});

test("a Pro caller gets the larger allowance and a proportional warning threshold", () => {
  const preview = buildUsageQuotaPreview({
    usedUnits: 30,
    meteringAvailable: true,
    tier: "pro",
    limitUnits: 500,
  });

  assert.equal(preview.tier, "pro");
  assert.equal(preview.limit_units, 500);
  assert.equal(preview.remaining_units, 470);
  // A Pro user must not be warned at the free threshold of 15.
  assert.equal(preview.warning_threshold_units, 375);
  assert.equal(preview.state, "available");
});

test("enforcement stays off regardless of tier or exhaustion", () => {
  const exhaustedFree = buildUsageQuotaPreview({ usedUnits: 999, meteringAvailable: true });
  const exhaustedPro = buildUsageQuotaPreview({
    usedUnits: 999, meteringAvailable: true, tier: "pro", limitUnits: 500,
  });

  assert.equal(exhaustedFree.enforced, false);
  assert.equal(exhaustedPro.enforced, false);
  assert.equal(exhaustedFree.beta_access_continues, true);
  assert.equal(exhaustedPro.beta_access_continues, true);
});

test("entitlement route is authenticated, server-authored, and stores no payment data", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");

  const tableStart = schema.indexOf("create table if not exists subscription_entitlements");
  assert.notEqual(tableStart, -1, "subscription_entitlements must exist");
  const table = schema.slice(tableStart, schema.indexOf("create index if not exists idx_subscription_entitlements_user"));

  assert.match(table, /user_id text references profiles\(id\)/);
  // Never store payment instruments, prices, receipts, or Apple account IDs.
  assert.doesNotMatch(table, /price|amount|currency|receipt_data|apple_account|payment/i);

  const authStart = server.indexOf("const userId = await resolveUserId(request)");
  const entitlementRoute = server.indexOf('resource === "entitlements" && id === "apple"');
  assert.ok(entitlementRoute > authStart, "entitlement route must stay behind authentication");

  // Tier must be derived from the verified transaction, never from the body.
  assert.match(server, /verifyAppleSignedTransaction\(signedTransaction\)/);
  assert.doesNotMatch(server, /body\.tier|body\.is_pro|body\.product_id/);
});
