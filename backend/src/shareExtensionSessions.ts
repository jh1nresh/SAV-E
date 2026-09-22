import { createHash, randomBytes } from "node:crypto";
import type { SourceSearchOutput } from "./sourceSearchWorker.js";

type QueryResult = { rows: Array<Record<string, unknown>>; rowCount?: number | null };
type Queryable = { query(sql: string, values?: unknown[]): Promise<QueryResult> };
type TransactionClient = Queryable & { release(): void };
type TransactionPool = Queryable & { connect(): Promise<TransactionClient> };

export const shareExtensionSessionTTLMillis = 30 * 24 * 60 * 60 * 1_000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedBodyKeys = new Set(["source_url", "caption", "analysis_id"]);
const socialDomains = [
  "instagram.com", "threads.net", "threads.com", "x.com", "twitter.com",
  "tiktok.com", "youtube.com", "youtu.be", "xiaohongshu.com", "xhslink.com", "douyin.com",
];

export class ShareExtensionSessionError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

export type ShareExtensionSession = {
  id: string;
  ownerId: string;
  ownerSubject: string;
  installationId: string;
  expiresAt: Date;
};

export type ShareExtensionAnalyzeInput = {
  sourceUrl: string;
  caption?: string;
  analysisId: string;
};

export type ShareExtensionAnalysisClaim =
  | { kind: "new" }
  | { kind: "replay"; response: unknown };

export function shareExtensionAnalysisResponse(ownerSubject: string, recovery: SourceSearchOutput): Record<string, unknown> {
  if (recovery.receipt.failureReason?.kind === "provider_failure") {
    throw new ShareExtensionSessionError(502, "Share analysis provider unavailable");
  }
  return {
    owner_subject: ownerSubject,
    candidates: recovery.candidates,
    receipt: recovery.receipt,
    ...(recovery.semanticStatus === undefined ? {} : { semanticStatus: recovery.semanticStatus }),
  };
}

export function shareTokenHash(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function shareAnalysisInputHash(input: ShareExtensionAnalyzeInput): string {
  return createHash("sha256").update(JSON.stringify({
    source_url: input.sourceUrl,
    caption: input.caption ?? null,
  }), "utf8").digest("hex");
}

export function normalizeShareInstallationId(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new ShareExtensionSessionError(400, "Invalid installation_id");
  }
  return value.toLowerCase();
}

export function normalizeShareAnalyzeInput(body: Record<string, unknown>): ShareExtensionAnalyzeInput {
  if (Object.keys(body).some(key => !allowedBodyKeys.has(key))) {
    throw new ShareExtensionSessionError(400, "Unsupported share analysis field");
  }
  if (typeof body.source_url !== "string" || Buffer.byteLength(body.source_url, "utf8") > 4_096) {
    throw new ShareExtensionSessionError(400, "Invalid source_url");
  }
  let url: URL;
  try { url = new URL(body.source_url); }
  catch { throw new ShareExtensionSessionError(400, "Invalid source_url"); }
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const supportedHost = socialDomains.some(domain => host === domain || host.endsWith(`.${domain}`));
  if (url.protocol !== "https:" || url.username || url.password || url.port || !supportedHost) {
    throw new ShareExtensionSessionError(400, "Unsupported social source_url");
  }
  url.hostname = host === "twitter.com" ? "x.com" : host;
  const caption = body.caption;
  if (caption !== undefined && (typeof caption !== "string" || caption.length > 20_000 || Buffer.byteLength(caption, "utf8") > 64_000)) {
    throw new ShareExtensionSessionError(400, "Invalid caption");
  }
  if (typeof body.analysis_id !== "string" || !uuidPattern.test(body.analysis_id)) {
    throw new ShareExtensionSessionError(400, "Invalid analysis_id");
  }
  return {
    sourceUrl: url.href,
    ...(caption === undefined ? {} : { caption }),
    analysisId: body.analysis_id.toLowerCase(),
  };
}

export class ShareExtensionSessionStore {
  constructor(private readonly pool: TransactionPool) {}

  async issue(ownerId: string, ownerSubject: string, installationId: string, now = new Date()): Promise<{ token: string; session: ShareExtensionSession }> {
    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(now.getTime() + shareExtensionSessionTTLMillis);
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock(hashtext($1))", [`share-extension:${ownerId}:${installationId}`]);
      await client.query(
        `/* share-extension:issue-revoke */
         update share_extension_sessions set revoked_at=$3
         where owner_id=$1 and installation_id=$2 and revoked_at is null`,
        [ownerId, installationId, now],
      );
      const result = await client.query(
        `/* share-extension:issue-insert */
         insert into share_extension_sessions(owner_id,owner_subject,installation_id,token_hash,expires_at,created_at)
         values($1,$2,$3,$4,$5,$6)
         returning id,owner_id,owner_subject,installation_id,expires_at`,
        [ownerId, ownerSubject, installationId, shareTokenHash(token), expiresAt, now],
      );
      await client.query("commit");
      const row = result.rows[0];
      return { token, session: sessionFromRow(row) };
    } catch (error) {
      await client.query("rollback").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async authorize(token: string, now = new Date()): Promise<ShareExtensionSession> {
    const result = await this.pool.query(
      `/* share-extension:authorize */
       select id,owner_id,owner_subject,installation_id,expires_at
       from share_extension_sessions
       where token_hash=$1 and revoked_at is null and expires_at>$2`,
      [shareTokenHash(token), now],
    );
    if (!result.rows[0]) throw new ShareExtensionSessionError(401, "Invalid or expired share session");
    return sessionFromRow(result.rows[0]);
  }

  async revoke(token: string, now = new Date()): Promise<void> {
    await this.pool.query(
      `/* share-extension:revoke */
       update share_extension_sessions set revoked_at=coalesce(revoked_at,$2)
       where token_hash=$1`,
      [shareTokenHash(token), now],
    );
  }

  async claimAnalysis(sessionId: string, analysisId: string, requestHash: string): Promise<ShareExtensionAnalysisClaim> {
    const inserted = await this.pool.query(
      `/* share-extension:analysis-claim */
       insert into share_extension_analyses(session_id,analysis_id,request_hash,status)
       values($1,$2,$3,'pending') on conflict(analysis_id) do nothing
       returning analysis_id`,
      [sessionId, analysisId, requestHash],
    );
    if (inserted.rows[0]) return { kind: "new" };
    const existing = await this.pool.query(
      `/* share-extension:analysis-existing */
       select session_id,request_hash,status,response from share_extension_analyses where analysis_id=$1`,
      [analysisId],
    );
    const row = existing.rows[0];
    if (!row || row.session_id !== sessionId || row.request_hash !== requestHash) {
      throw new ShareExtensionSessionError(409, "analysis_id was already used for different input");
    }
    if (row.status === "completed") return { kind: "replay", response: row.response };
    if (row.status === "failed") throw new ShareExtensionSessionError(409, "Analysis already failed; use a new analysis_id");
    throw new ShareExtensionSessionError(409, "Analysis is already in progress");
  }

  async completeAnalysis(sessionId: string, analysisId: string, requestHash: string, response: unknown): Promise<void> {
    const serialized = JSON.stringify(response);
    if (!serialized || Buffer.byteLength(serialized, "utf8") > 256_000) {
      throw new ShareExtensionSessionError(502, "Analysis response is too large");
    }
    const result = await this.pool.query(
      `/* share-extension:analysis-complete */
       update share_extension_analyses set status='completed',response=$4::jsonb,finished_at=now()
       where session_id=$1 and analysis_id=$2 and request_hash=$3 and status='pending'`,
      [sessionId, analysisId, requestHash, serialized],
    );
    if (result.rowCount !== 1) throw new ShareExtensionSessionError(409, "Analysis claim is no longer active");
  }

  async failAnalysis(sessionId: string, analysisId: string, requestHash: string): Promise<void> {
    await this.pool.query(
      `/* share-extension:analysis-fail */
       update share_extension_analyses set status='failed',finished_at=now()
       where session_id=$1 and analysis_id=$2 and request_hash=$3 and status='pending'`,
      [sessionId, analysisId, requestHash],
    );
  }
}

function sessionFromRow(row: Record<string, unknown> | undefined): ShareExtensionSession {
  if (!row || typeof row.id !== "string" || typeof row.owner_id !== "string" || typeof row.owner_subject !== "string"
    || typeof row.installation_id !== "string" || !(row.expires_at instanceof Date)) {
    throw new Error("Invalid share extension session row");
  }
  return { id: row.id, ownerId: row.owner_id, ownerSubject: row.owner_subject,
    installationId: row.installation_id, expiresAt: row.expires_at };
}
