import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";
import type { Pool, PoolClient } from "pg";

export class AnalysisControlError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}
export type AnalysisOperation = "google_places" | "gemini" | "metadata" | "public_search" | "media_download" | "rubric" | "local_ocr" | "local_asr" | "apple_maps" | "china_places";
export type AnalysisOutcome = "success" | "failure" | "cancelled";
export type AnalysisPrice = { requestMicros?: number; inputMicrosPerMillion?: number; outputMicrosPerMillion?: number; cachedInputMicrosPerMillion?: number };
// Gross published retail estimates, before free allowances, tax or infrastructure.
export const analysisPrices: Record<string, AnalysisPrice> = {
  google_places: { requestMicros: 32_000 },
  "gemini:gemini-3.5-flash": { inputMicrosPerMillion: 1_500_000, outputMicrosPerMillion: 9_000_000, cachedInputMicrosPerMillion: 150_000 },
  "gemini:gemini-2.5-flash": { inputMicrosPerMillion: 300_000, outputMicrosPerMillion: 2_500_000, cachedInputMicrosPerMillion: 30_000 },
  metadata: { requestMicros: 0 }, public_search: { requestMicros: 0 }, media_download: { requestMicros: 0 },
  local_ocr: { requestMicros: 0 }, local_asr: { requestMicros: 0 }, apple_maps: { requestMicros: 0 },
};
export const analysisPriceVersion = "retail-usd-2026-09-13";
export type AnalysisLimits = { enabled: boolean; accountDailyAnalyses?: number; analysisRequests?: number; accountDailyMicros?: number; globalDailyMicros?: number; analysisMicros?: number };
export function analysisLimits(env: NodeJS.ProcessEnv = process.env): AnalysisLimits {
  const enabled = env.SAVE_ANALYSIS_LIMITS_ENABLED === "true";
  const values = {
    accountDailyAnalyses: limitNumber(env.SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT),
    analysisRequests: limitNumber(env.SAVE_ANALYSIS_REQUEST_LIMIT),
    accountDailyMicros: limitNumber(env.SAVE_ANALYSIS_ACCOUNT_DAILY_BUDGET_MICROS),
    globalDailyMicros: limitNumber(env.SAVE_ANALYSIS_GLOBAL_DAILY_BUDGET_MICROS),
    analysisMicros: limitNumber(env.SAVE_ANALYSIS_BUDGET_MICROS),
  };
  if (enabled && Object.values(values).some(value => value === undefined)) throw unavailable();
  return { enabled, ...values };
}
function limitNumber(value: string | undefined): number | undefined {
  if (value === undefined || !/^\d+$/.test(value)) return undefined;
  const number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 ? number : undefined;
}
export function analysisID(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new AnalysisControlError(400, "analysis_invalid_id", "Invalid analysis identifier");
  }
  return value.toLowerCase();
}
export function unavailable(): AnalysisControlError {
  return new AnalysisControlError(503, "analysis_controls_unavailable", "Analysis controls are temporarily unavailable");
}
export type TokenUsage = { input: number | null; output: number | null; thinking: number | null; cached: number | null; total: number | null };
const integer = (value: unknown): number | null => typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
export function geminiTokens(body: unknown): TokenUsage {
  const usage = body && typeof body === "object" ? (body as Record<string, any>).usageMetadata : undefined;
  return { input: integer(usage?.promptTokenCount), output: integer(usage?.candidatesTokenCount), thinking: integer(usage?.thoughtsTokenCount), cached: integer(usage?.cachedContentTokenCount), total: integer(usage?.totalTokenCount) };
}
export function estimatedMicros(price: AnalysisPrice | undefined, tokens?: TokenUsage): number | null {
  if (!price) return null;
  if (price.requestMicros !== undefined) return price.requestMicros;
  if (!tokens || tokens.input === null || tokens.output === null || price.inputMicrosPerMillion === undefined || price.outputMicrosPerMillion === undefined) return null;
  // Missing thinking counts may be inferred only from a complete token total.
  const thinking = tokens.thinking ?? (tokens.total === null ? null : tokens.total - tokens.input - tokens.output);
  if (thinking === null || thinking < 0 || (tokens.total !== null && tokens.total < tokens.input + tokens.output + thinking) || (tokens.cached !== null && tokens.cached > tokens.input)) return null;
  const cached = Math.min(tokens.input, tokens.cached ?? 0);
  return Math.ceil(((tokens.input - cached) * price.inputMicrosPerMillion + cached * (price.cachedInputMicrosPerMillion ?? price.inputMicrosPerMillion) + (tokens.output + thinking) * price.outputMicrosPerMillion) / 1_000_000);
}
export type OperationInput = { operation: AnalysisOperation; model?: string; reserveMicros?: number; tokens?: TokenUsage };
export class AnalysisUsageStore {
  constructor(readonly pool: Pool, readonly limits: () => AnalysisLimits = analysisLimits) {}
  private async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try { await client.query("begin"); await client.query("set local statement_timeout = '10s'"); await client.query("select pg_advisory_xact_lock(1935764581)"); const value = await work(client); await client.query("commit"); return value; }
    catch (error) { await client.query("rollback"); throw error; }
    finally { client.release(); }
  }
  async start(userId: string, id: string, clientEventsExpected = true): Promise<string> {
    id = analysisID(id);
    return this.transaction(async client => {
      const existing = await client.query("select user_id, finished_at from analysis_sessions where id=$1", [id]);
      if (existing.rows[0]) {
        if (existing.rows[0].user_id !== userId) throw new AnalysisControlError(404,"analysis_not_found","Analysis not found");
        if (existing.rows[0].finished_at) throw new AnalysisControlError(409,"analysis_closed","Analysis is already complete");
        return id;
      }
      const limits = this.limits();
      if (limits.enabled) {
        const count = await client.query("select count(*)::int as n from analysis_sessions where user_id=$1 and started_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'",[userId]);
        if (count.rows[0].n >= limits.accountDailyAnalyses!) throw new AnalysisControlError(429,"analysis_limit_exceeded","Daily analysis limit reached");
      }
      await client.query("insert into analysis_sessions(id,user_id,client_events_expected) values($1,$2,$3)",[id,userId,clientEventsExpected]);
      return id;
    });
  }
  async owner(userId: string,id: string, client: Pool | PoolClient = this.pool, allowFinished = false): Promise<void> {
    const result = await client.query("select finished_at from analysis_sessions where id=$1 and user_id=$2",[analysisID(id),userId]);
    if (!result.rows[0]) throw new AnalysisControlError(404,"analysis_not_found","Analysis not found");
    if (!allowFinished && result.rows[0].finished_at) throw new AnalysisControlError(409,"analysis_closed","Analysis is already complete");
  }
  async reserve(userId: string,id: string,input: OperationInput): Promise<string> {
    return this.transaction(async client => {
      await this.owner(userId,id,client);
      const price = analysisPrices[input.operation === "gemini" ? `gemini:${input.model}` : input.operation];
      const reserve = input.reserveMicros ?? price?.requestMicros ?? null;
      const limits = this.limits();
      if (limits.enabled) {
        if (reserve === null || !Number.isSafeInteger(reserve) || reserve < 0) throw unavailable();
        const usage = await client.query(`select
          coalesce(sum(greatest(reserved_micros,coalesce(estimated_micros,reserved_micros))) filter(where analysis_id=$1),0)::bigint as analysis_cost,
          count(*) filter(where analysis_id=$1)::int as analysis_requests,
          coalesce(sum(greatest(reserved_micros,coalesce(estimated_micros,reserved_micros))) filter(where user_id=$2 and created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),0)::bigint as account_cost,
          coalesce(sum(greatest(reserved_micros,coalesce(estimated_micros,reserved_micros))) filter(where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),0)::bigint as global_cost,
          count(*) filter(where reserved_micros is null and (analysis_id=$1 or created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))::int as unknown
          from analysis_usage_events where origin='server' and (analysis_id=$1 or created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')`,[id,userId]);
        const used = usage.rows[0];
        if (used.unknown > 0) throw unavailable();
        if (used.analysis_requests >= limits.analysisRequests! || Number(used.analysis_cost)+reserve > limits.analysisMicros! || Number(used.account_cost)+reserve > limits.accountDailyMicros! || Number(used.global_cost)+reserve > limits.globalDailyMicros!) {
          throw new AnalysisControlError(429,"analysis_limit_exceeded","Analysis usage limit reached");
        }
      }
      const eventId = randomUUID();
      await client.query(`insert into analysis_usage_events(id,analysis_id,user_id,operation,model,origin,outcome,reserved_micros,price_version) values($1,$2,$3,$4,$5,'server','pending',$6,$7)`,[eventId,id,userId,input.operation,input.model ?? null,reserve,analysisPriceVersion]);
      return eventId;
    });
  }
  async settle(userId: string,id: string,eventId: string,input: OperationInput,outcome: AnalysisOutcome,duration: number): Promise<void> {
    const price = analysisPrices[input.operation === "gemini" ? `gemini:${input.model}` : input.operation];
    const cost = outcome === "success" ? estimatedMicros(price,input.tokens) : null;
    await this.pool.query(`update analysis_usage_events set outcome=$4,duration_ms=$5,estimated_micros=$6,input_tokens=$7,output_tokens=$8,thinking_tokens=$9,cached_tokens=$10,total_tokens=$11 where id=$1 and analysis_id=$2 and user_id=$3 and origin='server' and outcome='pending'`,[eventId,id,userId,outcome,Math.max(0,Math.trunc(duration)),cost,input.tokens?.input ?? null,input.tokens?.output ?? null,input.tokens?.thinking ?? null,input.tokens?.cached ?? null,input.tokens?.total ?? null]);
  }
  async clientEvents(userId: string,id: string,events: unknown,truncated:unknown=false): Promise<void> {
    if (typeof truncated !== "boolean" || !Array.isArray(events) || events.length > 256) throw new AnalysisControlError(400,"analysis_invalid_events","Invalid analysis events");
    const allowed = new Set(["metadata","public_search","apple_maps","china_places","local_ocr"]);
    const clean = events.map(event => {
      if (!event || typeof event !== "object" || !allowed.has(event.operation) || !["success","failure","cancelled"].includes(event.outcome) || integer(event.duration_ms) === null || event.duration_ms > 86_400_000) throw new AnalysisControlError(400,"analysis_invalid_events","Invalid analysis events");
      return { id: analysisID(event.event_id),operation:event.operation,outcome:event.outcome,duration:event.duration_ms };
    });
    await this.transaction(async client => {
      await this.owner(userId,id,client,true);
      const existing=await client.query("select id from analysis_usage_events where analysis_id=$1 and user_id=$2 and origin='client'",[id,userId]);
      const seen=new Set(existing.rows.map(row=>row.id));
      let overflow=truncated;
      for (const event of clean) {
        if(seen.has(event.id)) continue;
        if(seen.size>=256) { overflow=true; continue; }
        await client.query(`insert into analysis_usage_events(id,analysis_id,user_id,operation,origin,outcome,duration_ms,estimated_micros) values($1,$2,$3,$4,'client',$5,$6,$7) on conflict(id) do nothing`,[event.id,id,userId,event.operation,event.outcome,event.duration,analysisPrices[event.operation]?.requestMicros ?? null]);
        seen.add(event.id);
      }
      await client.query("update analysis_sessions set events_truncated=events_truncated or $3,client_events_received=true where id=$1 and user_id=$2",[id,userId,overflow]);
    });
  }
  async finish(userId: string,id: string,outcome: unknown,captureIds: unknown): Promise<void> {
    if (!["review_candidate","source_only","failed","cancelled"].includes(String(outcome)) || !Array.isArray(captureIds) || captureIds.length > 100) throw new AnalysisControlError(400,"analysis_invalid_result","Invalid analysis result");
    const ids = [...new Set(captureIds.map(analysisID))];
    await this.transaction(async client => {
      await this.owner(userId,id,client,true);
      for (const captureId of ids) {
        const capture = await client.query("select id from captures where id=$1 and user_id=$2",[captureId,userId]);
        if (!capture.rows[0]) throw new AnalysisControlError(404,"analysis_not_found","Capture not found");
        await client.query("insert into analysis_captures(analysis_id,capture_id,user_id) values($1,$2,$3) on conflict do nothing",[id,captureId,userId]);
      }
      await client.query("update analysis_sessions set finished_at=coalesce(finished_at,now()),outcome=coalesce(outcome,$3) where id=$1 and user_id=$2",[id,userId,outcome]);
    });
  }
  async summary(userId: string,id: string): Promise<Record<string, unknown>> {
    await this.owner(userId,id,this.pool,true);
    const {rows} = await this.pool.query(`select operation,model,origin,count(*)::int as attempts,count(*) filter(where outcome='success')::int as successes,count(*) filter(where outcome='failure')::int as failures,count(*) filter(where outcome='pending')::int as pending,sum(input_tokens)::bigint as input_tokens,sum(output_tokens)::bigint as output_tokens,sum(thinking_tokens)::bigint as thinking_tokens,sum(estimated_micros)::bigint as known_estimated_micros,count(*) filter(where estimated_micros is null)::int as unknown_cost_events from analysis_usage_events where analysis_id=$1 and user_id=$2 group by operation,model,origin order by operation,model,origin`,[id,userId]);
    const confirmed = await this.pool.query(`select count(distinct c.id)::int as n from analysis_captures a join place_candidates c on c.capture_id=a.capture_id where a.analysis_id=$1 and a.user_id=$2 and c.status in ('confirmed','saved')`,[id,userId]);
    const session=await this.pool.query("select events_truncated,client_events_expected,client_events_received,finished_at from analysis_sessions where id=$1 and user_id=$2",[id,userId]);
    return { analysis_id:id,events_truncated:session.rows[0].events_truncated,client_events_are_unverified:true,price_version:analysisPriceVersion,currency:"USD",cost_basis:"gross_provider_estimate_excludes_free_allowances_tax_infrastructure",operations:rows,confirmed_candidates:confirmed.rows[0].n,client_events_received:session.rows[0].client_events_received,cost_complete:Boolean(session.rows[0].finished_at) && (!session.rows[0].client_events_expected || session.rows[0].client_events_received) && !session.rows[0].events_truncated && rows.every(row=>row.unknown_cost_events===0),enforced:this.limits().enabled };
  }
}
const context = new AsyncLocalStorage<{store:AnalysisUsageStore;userId:string;id:string}>();
export function withAnalysisUsage<T>(store:AnalysisUsageStore,userId:string,id:string,work:()=>Promise<T>):Promise<T> { return context.run({store,userId,id},work); }
export async function trackAnalysisOperation<T>(input:OperationInput,work:()=>Promise<T>,tokens?:(value:T)=>TokenUsage):Promise<T> {
  const current = context.getStore();
  if (!current) return work();
  const eventId = await current.store.reserve(current.userId,current.id,input);
  const started = Date.now();
  try {
    const result = await work();
    await current.store.settle(current.userId,current.id,eventId,{...input,tokens:tokens?.(result)},"success",Date.now()-started);
    return result;
  } catch (error) {
    await current.store.settle(current.userId,current.id,eventId,input,error instanceof Error && error.name === "AbortError" ? "cancelled" : "failure",Date.now()-started);
    throw error;
  }
}
