export const betaUsageQuotaPolicy = {
  policyVersion: "ai-assists-beta-v0",
  monthlyLimitUnits: 20,
  warningThresholdUnits: 15,
  enforced: false,
} as const;

export type UsageEventOutcome =
  | "success"
  | "upstream_failure"
  | "transport_failure"
  | "invalid_response";

export type AIUsageEvent = {
  operation: "gemini_generate_content";
  provider: "google_gemini";
  model: string;
  outcome: UsageEventOutcome;
  units: 0 | 1;
  upstreamStatus: number | null;
  latencyMs: number;
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
};

export type UsageQuotaPreview = {
  policy_version: string;
  period_start: string;
  period_end: string;
  limit_units: number;
  warning_threshold_units: number;
  used_units: number | null;
  remaining_units: number | null;
  state: "available" | "warning" | "preview_limit_reached" | "warming_up";
  enforced: false;
  metering_available: boolean;
  beta_access_continues: true;
};

export function buildGeminiUsageEvent(input: {
  model: string;
  outcome: UsageEventOutcome;
  upstreamStatus?: number | null;
  latencyMs: number;
  responseBody?: unknown;
}): AIUsageEvent {
  const usage = usageMetadata(input.responseBody);
  return {
    operation: "gemini_generate_content",
    provider: "google_gemini",
    model: input.model,
    outcome: input.outcome,
    units: input.outcome === "success" ? 1 : 0,
    upstreamStatus: finiteInteger(input.upstreamStatus) ?? null,
    latencyMs: Math.max(0, Math.trunc(input.latencyMs)),
    inputTokens: usage.inputTokens,
    outputTokens: usage.outputTokens,
    totalTokens: usage.totalTokens,
  };
}

export function buildUsageQuotaPreview(input: {
  usedUnits?: unknown;
  now?: Date;
  meteringAvailable: boolean;
}): UsageQuotaPreview {
  const now = input.now ?? new Date();
  const periodStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const periodEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const usedUnits = input.meteringAvailable ? Math.max(0, finiteInteger(input.usedUnits) ?? 0) : null;
  const remainingUnits = usedUnits === null
    ? null
    : Math.max(0, betaUsageQuotaPolicy.monthlyLimitUnits - usedUnits);

  let state: UsageQuotaPreview["state"] = "warming_up";
  if (usedUnits !== null) {
    if (usedUnits >= betaUsageQuotaPolicy.monthlyLimitUnits) state = "preview_limit_reached";
    else if (usedUnits >= betaUsageQuotaPolicy.warningThresholdUnits) state = "warning";
    else state = "available";
  }

  return {
    policy_version: betaUsageQuotaPolicy.policyVersion,
    period_start: periodStart.toISOString(),
    period_end: periodEnd.toISOString(),
    limit_units: betaUsageQuotaPolicy.monthlyLimitUnits,
    warning_threshold_units: betaUsageQuotaPolicy.warningThresholdUnits,
    used_units: usedUnits,
    remaining_units: remainingUnits,
    state,
    enforced: false,
    metering_available: input.meteringAvailable,
    beta_access_continues: true,
  };
}

function usageMetadata(value: unknown): {
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
} {
  const body = objectValue(value);
  const metadata = objectValue(body?.usageMetadata);
  return {
    inputTokens: finiteInteger(metadata?.promptTokenCount) ?? null,
    outputTokens: finiteInteger(metadata?.candidatesTokenCount) ?? null,
    totalTokens: finiteInteger(metadata?.totalTokenCount) ?? null,
  };
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  return value as Record<string, unknown>;
}

function finiteInteger(value: unknown): number | undefined {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim() ? Number(value) : Number.NaN;
  if (!Number.isFinite(parsed)) return undefined;
  return Math.trunc(parsed);
}
