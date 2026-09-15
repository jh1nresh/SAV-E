import type { PoolClient } from "pg";

type Row = Record<string, any>;
const pending = new Set(["review", "needs_more_evidence", "source_only"]);
const terminal = new Set(["saved", "confirmed", "rejected"]);

// Keep identity-bearing query parameters and opaque fragments. Invalid URLs are
// never evidence that two captures are the same source.
export function normalizedCaptureURL(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value.trim());
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return undefined;
    for (const key of [...url.searchParams.keys()]) {
      if (/^utm_/i.test(key) || /^(fbclid|gclid|igshid|igsh|mc_cid|mc_eid)$/i.test(key)) url.searchParams.delete(key);
    }
    url.searchParams.sort();
    return url.href;
  } catch { return undefined; }
}

function identityText(value: unknown): string {
  return typeof value === "string" ? value.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase() : "";
}

export function sameCandidateIdentity(left: Row, right: Row): boolean {
  if ((left.status === "source_only" || right.status === "source_only")
    && left.capture_id === right.capture_id && left.capture_id
    && [left, right].every(row => !row.place_id && !identityText(row.address) && row.latitude == null && row.longitude == null)
    && (left.status === right.status || (identityText(left.name) && identityText(left.name) === identityText(right.name)))) return true;
  if (left.place_id && right.place_id) return left.place_id === right.place_id;
  const name = identityText(left.name), address = identityText(left.address);
  if (!name || !address || name !== identityText(right.name) || address !== identityText(right.address)) return false;
  if ([left.latitude, left.longitude, right.latitude, right.longitude].every(value => typeof value === "number" && Number.isFinite(value))) {
    // Conflicting coordinates can identify different branches despite matching labels.
    if (Math.abs(left.latitude - right.latitude) > 0.001 || Math.abs(left.longitude - right.longitude) > 0.001) return false;
  }
  return true;
}

export function mergedEvidence(left: unknown, right: unknown): unknown[] {
  const values = [...(Array.isArray(left) ? left : []), ...(Array.isArray(right) ? right : [])];
  const seen = new Set<string>();
  return values.filter(value => { const key = JSON.stringify(value); if (seen.has(key)) return false; seen.add(key); return true; });
}

export function mergedCaptureText(existing: Row, incoming: Row): string | null {
  let text = typeof existing.raw_text === "string" ? existing.raw_text : "";
  for (const value of [incoming.raw_text, incoming.title !== existing.title ? incoming.title : null]) {
    if (typeof value === "string" && value.trim() && !text.includes(value.trim())) text += `${text ? "\n\n" : ""}${value.trim()}`;
  }
  return text || null;
}

export async function reuseCapture(client: PoolClient, userId: string, body: Row): Promise<Row | undefined> {
  const key = normalizedCaptureURL(body.source_url);
  if (!key) return undefined;
  await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [`capture:${userId}:${key}`]);
  const { rows } = await client.query("select * from captures where user_id=$1 and source_url is not null order by created_at, id for update", [userId]);
  const existing = rows.find(row => normalizedCaptureURL(row.source_url) === key);
  if (!existing) return undefined;
  const updated = await client.query("update captures set raw_text=$3, title=coalesce(title,$4), created_at=coalesce($5::timestamptz,created_at), updated_at=now() where id=$1 and user_id=$2 returning *", [existing.id, userId, mergedCaptureText(existing, body), body.title ?? null, earliestKnownDate([existing.created_at, body.created_at]) ?? null]);
  const capture = updated.rows[0];
  // Capture-only repeat imports may return saved successor IDs without posting
  // candidates again. Keep their collection dates aligned without new decisions.
  await client.query("update place_candidates set created_at=$2 where capture_id=$1 and created_at>$2::timestamptz", [capture.id, capture.created_at]);
  await client.query("update places p set created_at=$3 where p.user_id=$2 and p.created_at>$3::timestamptz and exists (select 1 from place_candidates pc where pc.capture_id=$1 and pc.place_id=p.id and pc.status in ('saved','confirmed'))", [capture.id, userId, capture.created_at]);
  return capture;
}

export function earliestKnownDate(values: unknown[]): string | Date | undefined {
  let earliest: string | Date | undefined;
  let earliestTime = Infinity;
  for (const value of values) {
    if (typeof value !== "string" && !(value instanceof Date)) continue;
    const time = value instanceof Date ? value.getTime() : Date.parse(value);
    if (Number.isFinite(time) && time < earliestTime) {
      earliest = value;
      earliestTime = time;
    }
  }
  return earliest;
}

export async function prepareCandidate(client: PoolClient, body: Row): Promise<{ existing?: Row; body: Row }> {
  body = { ...body, evidence: externalCandidateEvidence(body.evidence) };
  const capture = await client.query("select created_at from captures where id=$1 for update", [body.capture_id]);
  const { rows } = await client.query("select * from place_candidates where capture_id=$1 order by created_at, id for update", [body.capture_id]);
  const matches = rows.filter(row => sameCandidateIdentity(row, body));
  const createdAt = earliestKnownDate([capture.rows[0]?.created_at, ...matches.map(row => row.created_at), body.created_at]);
  const existing = matches.find(row => (row.workflow_run_id ?? null) === (body.workflow_run_id ?? null));
  if (existing) {
    const updated = await client.query("update place_candidates set evidence=$2::jsonb, created_at=coalesce($3::timestamptz,created_at), updated_at=now() where id=$1 returning *", [existing.id, JSON.stringify(mergedEvidence(existing.evidence, body.evidence)), createdAt ?? null]);
    if (["saved", "confirmed"].includes(existing.status) && existing.place_id && createdAt !== undefined) {
      // An already confirmed source can refine collection time without a new
      // decision, candidate reconciliation, or changes to workflow receipts.
      await client.query("update places p set created_at=$3 from captures c where c.id=$2 and p.id=$1 and p.user_id=c.user_id and p.created_at>$3::timestamptz", [existing.place_id, body.capture_id, createdAt]);
    }
    return { existing: updated.rows[0], body };
  }
  // Never transfer a candidate between workflows: old analysis receipts refer to it.
  let completed = matches.find(row => terminal.has(row.status));
  if (completed && body.workflow_run_id) {
    const target = await client.query("select credit_settlement from workflow_runs where id=$1", [body.workflow_run_id]);
    // This separate reservation needs an actionable result and its own decision.
    if (target.rows[0]?.credit_settlement === "pending") completed = undefined;
  }
  return { body: {
    ...body,
    created_at: createdAt,
    ...(completed ? { status: completed.status, place_id: completed.place_id, evidence: mergedEvidence(completed.evidence, body.evidence) }
      : matches[0] ? { evidence: mergedEvidence(matches[0].evidence, body.evidence) } : {}),
  } };
}

export async function reconcileSavedCandidates(client: PoolClient, userId: string, candidateId: string): Promise<string[]> {
  const { rows } = await client.query("select pc.*, c.created_at as capture_created_at, wr.credit_settlement as run_settlement from place_candidates pc join captures c on c.id=pc.capture_id left join workflow_runs wr on wr.id=pc.workflow_run_id where c.user_id=$1 order by pc.id for update of pc", [userId]);
  const saved = rows.find(row => row.id === candidateId);
  if (!saved || !["saved", "confirmed"].includes(saved.status)) return [];
  let confirmedIdentity = saved;
  if (saved.place_id) {
    const places = await client.query("select id, name, address, latitude, longitude, created_at from places where id=$1 and user_id=$2 for update", [saved.place_id, userId]);
    if (!places.rows[0]) return [];
    // A correction confirms the final owned place, not the old candidate label.
    confirmedIdentity = { ...places.rows[0], place_id: saved.place_id };
  }
  // A separate pending run still needs its own user decision and settlement.
  // Keep its review actionable instead of hiding a reserved workflow.
  const duplicates = rows.filter(row => row.id !== candidateId && pending.has(row.status)
    && !(row.workflow_run_id && row.workflow_run_id !== saved.workflow_run_id && row.run_settlement === "pending")
    && sameCandidateIdentity(confirmedIdentity, row));
  if (saved.place_id) {
    // The user just confirmed these source records into the owned place. Persist
    // chronology here so every client observes it without arbitrary date PATCHes.
    const earliest = earliestKnownDate([confirmedIdentity.created_at,
      ...[saved, ...duplicates].flatMap(row => [row.created_at, row.capture_created_at])]);
    if (earliest !== undefined) await client.query("update places set created_at=$3 where id=$1 and user_id=$2 and created_at>$3::timestamptz", [saved.place_id, userId, earliest]);
  }
  if (!duplicates.length) return [];
  // Preserve every row and its workflow/evidence. Confirmation finishes only an
  // exact venue identity; source URLs alone cannot complete a multi-venue post.
  await client.query("update place_candidates set status=$2, place_id=coalesce($3,place_id), evidence=evidence || $4::jsonb, updated_at=now() where id=any($1::uuid[])", [duplicates.map(row => row.id), saved.status, saved.place_id ?? null, JSON.stringify([{ completed_by_candidate_id: candidateId }])]);
  return duplicates.map(row => row.id);
}

export function isGenericSourceOnlyCandidate(row: Row): boolean {
  return row.status === "source_only" && !identityText(row.address) && !row.place_id
    && row.latitude == null && row.longitude == null
    && ["saved link", "saved source", "social link", "instagram reel", "instagram link", "xiaohongshu link",
      "douyin link", "dianping link", "meituan link", "taobao instant commerce link", "taobao product link",
      "tiktok link", "google maps link", "apple maps link"].includes(identityText(row.name));
}

export async function supersedeSourceOnlyCandidates(client: PoolClient, captureId: string, successorIds?: string[]): Promise<string[]> {
  const { rows } = await client.query("select pc.*, wr.credit_settlement as run_settlement from place_candidates pc left join workflow_runs wr on wr.id=pc.workflow_run_id where pc.capture_id=$1 for update of pc", [captureId]);
  const named = rows.filter(row => row.status !== "source_only" && row.status !== "rejected");
  let successors = named.length ? [named[0]] : [];
  if (successorIds) {
    const ids = [...new Set(successorIds)];
    successors = ids.map(id => rows.find(row => row.id === id)).filter(Boolean);
    // Accept only a fully persisted batch; existing settled successors remain
    // part of the source history even when a later retry discovers another venue.
    if (!ids.length || successors.length !== ids.length || successors.some(row => !["review", "needs_more_evidence", "saved", "confirmed"].includes(row.status))) return [];
  } else if (!named.length || named.some(row => !sameCandidateIdentity(named[0], row))) return [];
  const changed: string[] = [];
  for (const source of rows.filter(isGenericSourceOnlyCandidate)) {
    const previous = supersededCandidateIDs(source);
    const replacements = [...new Set([...previous, ...successors.map(row => String(row.id))])];
    const represented = rows.filter(row => replacements.includes(row.id));
    if (named.some(row => !represented.some(successor => sameCandidateIdentity(successor, row)))) continue;
    if (!previous.length && source.workflow_run_id && source.run_settlement === "pending"
      && !successors.some(successor => successor.workflow_run_id === source.workflow_run_id)) continue;
    if (replacements.length === previous.length) continue;
    // Append a cumulative event rather than altering prior evidence/provenance.
    await client.query("update place_candidates set evidence=evidence || $2::jsonb, updated_at=now() where id=$1", [source.id, JSON.stringify([{ superseded_by_candidate_id: replacements[0], superseded_by_candidate_ids: replacements }])]);
    changed.push(source.id);
  }
  return changed;
}

export function duplicateCandidateGroups(rows: Row[], places: Row[] = []): Row[] {
  const groups: Row[][] = [];
  for (const original of rows.filter(row => !supersededCandidateID(row))) {
    let row = original;
    if (["saved", "confirmed"].includes(row.status) && row.place_id) {
      const place = places.find(place => place.id === row.place_id);
      // Historical extraction labels may precede a user correction. Audit the
      // final owned identity; an unavailable place cannot support a saved link.
      if (!place) continue;
      row = { ...row, name: place.name, address: place.address, latitude: place.latitude, longitude: place.longitude };
    }
    const group = groups.find(group => group.every(other => sameCandidateIdentity(other, row)
      || (other.status === "source_only" && row.status === "source_only"
        && normalizedCaptureURL(row.source_url) !== undefined
        && normalizedCaptureURL(row.source_url) === normalizedCaptureURL(other.source_url)
        && !identityText(row.address) && !identityText(other.address)
        && !row.place_id && !other.place_id && row.latitude == null && row.longitude == null
        && other.latitude == null && other.longitude == null)));
    if (group) group.push(row); else groups.push([row]);
  }
  const matchedPlaces = (group: Row[]) => places.filter(place => group.every(row => sameCandidateIdentity(row, { ...place, place_id: place.id })));
  return groups.filter(group => group.some(row => pending.has(row.status)) && (group.length > 1 || matchedPlaces(group).length === 1)).map(group => ({
    candidate_ids: group.map(row => row.id),
    pending_candidate_ids: group.filter(row => pending.has(row.status)).map(row => row.id),
    saved_place_ids: [...new Set([...group.filter(row => row.status === "saved" && row.place_id).map(row => row.place_id), ...matchedPlaces(group).map(place => place.id)])],
    reason: group.some(row => row.status === "source_only") ? "same_source_clue" : "same_place_identity",
  }));
}

export function supersededCandidateID(row: Row): string | undefined {
  if (!Array.isArray(row.evidence)) return undefined;
  return row.evidence.find(item => item && typeof item === "object"
    && typeof item.superseded_by_candidate_id === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(item.superseded_by_candidate_id))?.superseded_by_candidate_id;
}

export function supersededCandidateIDs(row: Row): string[] {
  if (!Array.isArray(row.evidence)) return [];
  const validID = (id: unknown): id is string => typeof id === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  const ids: string[] = [];
  for (const item of row.evidence) {
    if (!item || typeof item !== "object") continue;
    if (validID(item.superseded_by_candidate_id)) ids.push(item.superseded_by_candidate_id);
    if (Array.isArray(item.superseded_by_candidate_ids) && item.superseded_by_candidate_ids.every(validID)) ids.push(...item.superseded_by_candidate_ids);
  }
  return [...new Set(ids)];
}

// Reconciliation provenance is authored by the service, not imported evidence.
export function externalCandidateEvidence(value: unknown): unknown[] {
  if (!Array.isArray(value)) return [];
  return value.map(item => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return item;
    const { superseded_by_candidate_id, superseded_by_candidate_ids, completed_by_candidate_id, ...evidence } = item;
    return evidence;
  }).filter(item => !item || typeof item !== "object" || Object.keys(item).length > 0);
}
