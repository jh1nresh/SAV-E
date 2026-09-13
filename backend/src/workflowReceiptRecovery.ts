import type { PoolClient } from "pg";
import { normalizePlaceRecoveryWorkerResult, type PlaceRecoveryWorkerResult } from "./workflowContracts.js";

type Row = Record<string, unknown>;

/** Called only while the requester-owned workflow run is locked in a transaction. */
export async function recoverMissingAnalysisReceipt<T>(
  db: Pick<PoolClient, "query">,
  run: Row,
  userId: string,
  candidateId: string | undefined,
  recordResult: (result: PlaceRecoveryWorkerResult) => Promise<T>,
): Promise<T | undefined> {
  // Candidates do not carry attempt identity. Only an untouched first attempt
  // can be reconstructed without attributing an older candidate to a retry.
  if (run.user_id !== userId
    || Number(run.current_attempt_no) !== 1
    || run.credit_settlement !== "pending"
    || !["queued", "running", "needs_review"].includes(String(run.status))
    || (run.result_type != null && !["review_candidate", "source_only_clue"].includes(String(run.result_type)))
  ) return undefined;

  const { rows: history } = await db.query(
    `select id from workflow_receipts where run_id = $1
     union all
     select id from user_decisions where run_id = $1
     limit 1`,
    [run.id],
  );
  if (history.length) return undefined;

  const { rows } = await db.query(
    `select pc.id, pc.workflow_run_id, c.user_id, pc.name, pc.status,
            pc.address, pc.latitude, pc.longitude,
            pc.confidence, pc.evidence, pc.missing_info
     from place_candidates pc
     join captures c on c.id = pc.capture_id
     where pc.workflow_run_id = $1 and c.user_id = $2
       and ($3::uuid is null or pc.id = $3::uuid)
     order by pc.id
     limit 2
     for share of pc, c`,
    [run.id, userId, candidateId ?? null],
  );
  // An omitted selection is safe only when the persisted result is unambiguous.
  if (rows.length !== 1) return undefined;
  const candidate = rows[0] as Row;
  if (candidate.workflow_run_id !== run.id || candidate.user_id !== userId
    || (candidateId !== undefined && String(candidate.id).toLowerCase() !== candidateId.toLowerCase())
    || !["review", "source_only", "needs_more_evidence"].includes(String(candidate.status))
    || typeof candidate.name !== "string" || !candidate.name.trim()
    || !hasPersistedEvidence(candidate.evidence)
  ) return undefined;

  const result = normalizePlaceRecoveryWorkerResult({
    // Older iOS imports persisted source-only drafts as status=review. Without
    // a persisted location, recovering a clue is safer than promoting its name.
    result_type: candidate.status === "source_only" || run.result_type === "source_only_clue"
      || !hasPersistedLocation(candidate)
      ? "source_only_clue" : "review_candidate",
    evidence_tier: "weak",
    confidence: candidate.confidence,
    // Reference the private evidence row; do not invent provider provenance or
    // expose its text in the public analysis receipt.
    evidence_refs: [candidate.id],
    candidate_refs: [candidate.id],
    missing_fields: candidate.missing_info,
    attempt_no: 1,
    result_revision: 1,
    idempotency_key: `persisted-candidate:${run.id}:${candidate.id}`,
  });
  result.operatorId = "save-backend";
  result.permissionSnapshot = { scopes: ["place_recovery.persisted_candidate.recover"] };
  return recordResult(result);
}

function hasPersistedEvidence(value: unknown): boolean {
  return Array.isArray(value) && value.some((item) => {
    const text = typeof item === "string" ? item
      : item && typeof item === "object" ? (item as Row).text : undefined;
    return typeof text === "string" && text.trim().length > 0;
  });
}

function hasPersistedLocation(candidate: Row): boolean {
  return (typeof candidate.address === "string" && candidate.address.trim().length > 0)
    || (typeof candidate.latitude === "number" && Number.isFinite(candidate.latitude)
      && Math.abs(candidate.latitude) <= 90
      && typeof candidate.longitude === "number" && Number.isFinite(candidate.longitude)
      && Math.abs(candidate.longitude) <= 180);
}
