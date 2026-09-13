import { createHash, randomUUID } from "node:crypto";
import type { Pool } from "pg";
import { AnalysisControlError } from "./analysisUsage.js";

const maxResultBytes = 1_000_000;
const maxLocalFlights = 256;
const flights = new WeakMap<Pool, Map<string, Promise<Record<string, unknown>>>>();

// Inputs are normalized by the caller. Preserve meaningful text, array order,
// and every supplied field; only object property insertion order is irrelevant.
function stableJSON(value: unknown): string {
  return JSON.stringify(value, (_key, item) => item && typeof item === "object" && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]]))
    : item);
}

function boundedResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw invalidResult();
  const json = JSON.stringify(value);
  if (Buffer.byteLength(json) > maxResultBytes) throw invalidResult();
  return JSON.parse(json) as Record<string, unknown>;
}

function invalidResult(): AnalysisControlError {
  return new AnalysisControlError(503, "analysis_recovery_invalid_result", "Analysis recovery result is unavailable");
}
function running(): AnalysisControlError {
  return new AnalysisControlError(409, "analysis_recovery_running", "Analysis recovery is already running");
}
function reusable(value: Record<string, unknown>): boolean {
  const receipt = value.receipt as { failureReason?: { kind?: string } } | undefined;
  return !(Array.isArray(value.errors) && value.errors.length > 0)
    && receipt?.failureReason?.kind !== "provider_failure";
}

export async function runAnalysisRecovery(
  pool: Pool,
  userId: string,
  captureId: string,
  normalizedInput: Record<string, unknown>,
  work: () => Promise<Record<string, unknown>>,
): Promise<Record<string, unknown>> {
  const key = createHash("sha256").update(stableJSON({ version: 1, userId, captureId: captureId.toLowerCase(), input: normalizedInput })).digest("hex");
  let local = flights.get(pool);
  if (!local) { local = new Map(); flights.set(pool, local); }
  const existing = local.get(key);
  if (existing) return { ...boundedResult(await existing), reused: true };

  const promise = runWithLease(pool, key, userId, captureId, work);
  // Overflow still uses the database lease; never evict an active promise and
  // never grow a process-lifetime result cache.
  const tracked = local.size < maxLocalFlights;
  if (tracked) local.set(key, promise);
  try { return boundedResult(await promise); }
  finally { if (tracked && local.get(key) === promise) local.delete(key); }
}

async function runWithLease(
  pool: Pool, key: string, userId: string, captureId: string,
  work: () => Promise<Record<string, unknown>>,
): Promise<Record<string, unknown>> {
  const token = randomUUID();
  const claim = await pool.query(`insert into analysis_recovery_runs
    (key,user_id,capture_id,state,lease_token,lease_expires_at,result,updated_at)
    values($1,$2,$3,'running',$4,clock_timestamp()+interval '10 minutes',null,clock_timestamp())
    on conflict(key) do update set state='running',lease_token=excluded.lease_token,
      lease_expires_at=excluded.lease_expires_at,result=null,updated_at=clock_timestamp()
    where analysis_recovery_runs.user_id=excluded.user_id
      and analysis_recovery_runs.capture_id=excluded.capture_id
      and (analysis_recovery_runs.state='failed' or analysis_recovery_runs.lease_expires_at<=clock_timestamp())
    returning lease_token`, [key, userId, captureId, token]);
  if (claim.rowCount === 0) {
    const cached = await pool.query(`select result from analysis_recovery_runs
      where key=$1 and user_id=$2 and capture_id=$3 and state='completed'
        and lease_expires_at>clock_timestamp()`, [key, userId, captureId]);
    if (cached.rows[0]) return { ...boundedResult(cached.rows[0].result), reused: true };
    throw running();
  }

  try {
    const result = boundedResult(await work());
    const response = boundedResult({ ...result, reused: false });
    const cacheable = reusable(result);
    const published = await pool.query(`update analysis_recovery_runs
      set state=$3,result=$4::jsonb,lease_expires_at=clock_timestamp()+interval '5 minutes',updated_at=clock_timestamp()
      where key=$1 and lease_token=$2 and state='running' and lease_expires_at>clock_timestamp()`,
    [key, token, cacheable ? "completed" : "failed", cacheable ? JSON.stringify(result) : null]);
    if (published.rowCount === 0) {
      throw new AnalysisControlError(409, "analysis_recovery_lease_lost", "Analysis recovery must be retried");
    }
    return response;
  } catch (error) {
    // A stale worker must not change a newer owner's lease or completed result.
    // Preserve the original failure if the database is also unavailable.
    await pool.query(`update analysis_recovery_runs set state='failed',result=null,updated_at=clock_timestamp()
      where key=$1 and lease_token=$2 and state='running' and lease_expires_at>clock_timestamp()`, [key, token]).catch(() => {});
    throw error;
  }
}
