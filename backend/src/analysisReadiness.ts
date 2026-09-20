import { analysisLimits } from "./analysisUsage.js";

// Resolve every operational column without reading user rows or changing schema.
// A healthy adapter configuration alone does not prove analysis can start.
const schemaProbe = `select
 s.id, s.user_id, s.started_at, s.finished_at, s.events_truncated,
 s.client_events_expected, s.client_events_received, s.outcome,
 e.id, e.analysis_id, e.user_id, e.operation, e.model, e.origin, e.outcome,
 e.reserved_micros, e.estimated_micros, e.duration_ms, e.input_tokens, e.output_tokens,
 e.thinking_tokens, e.cached_tokens, e.total_tokens, e.price_version, e.created_at,
 c.analysis_id, c.capture_id, c.user_id,
 r.key, r.user_id, r.capture_id, r.state, r.lease_token, r.lease_expires_at, r.result, r.updated_at
 from analysis_sessions s
 left join analysis_usage_events e on false
 left join analysis_captures c on false
 left join analysis_recovery_runs r on false
 limit 0`;

export async function readAnalysisReadiness(
  query: (sql: string) => Promise<unknown>,
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ ready: boolean; failures: string[] }> {
  const failures: string[] = [];
  if (!(env.GEMINI_API_KEY?.trim() || env.GOOGLE_GEMINI_API_KEY?.trim())) failures.push("semantic_provider_unconfigured");
  if (!env.GOOGLE_PLACES_API_KEY?.trim()) failures.push("places_provider_unconfigured");
  try { analysisLimits(env); } catch { failures.push("analysis_limits_invalid"); }
  try { await query(schemaProbe); } catch { failures.push("analysis_schema_unavailable"); }
  return { ready: failures.length === 0, failures };
}
