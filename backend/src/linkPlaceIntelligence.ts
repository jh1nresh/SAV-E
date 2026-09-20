import { createHash } from "node:crypto";
import type { Pool } from "pg";
import type { SemanticAnalysisResult } from "./socialSemanticExtraction.js";

type DB = Pick<Pool, "query">;
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const hexKey = /^[a-f0-9]{64}$/;

// Remove known attribution only; unknown query parameters can change content.
export function canonicalSourceURL(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length > 4096) return undefined;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.port) return undefined;
    const host = url.hostname.toLowerCase().replace(/^www\./, "");
    if (!["instagram.com", "threads.net", "threads.com", "x.com", "twitter.com", "tiktok.com", "youtube.com", "youtu.be", "xiaohongshu.com", "xhslink.com", "douyin.com", "maps.app.goo.gl", "maps.google.com", "google.com"].includes(host)) return undefined;
    url.hostname = host === "twitter.com" ? "x.com" : host;
    for (const key of [...url.searchParams.keys()]) {
      if (/^utm_/i.test(key) || ["igsh", "igshid", "fbclid", "gclid", "si"].includes(key)) url.searchParams.delete(key);
    }
    url.searchParams.sort();
    // Fragments can identify a section of a source; preserve them.
    url.pathname = url.pathname.replace(/\/$/, "") || "/";
    return url.href;
  } catch { return undefined; }
}

export type IdentityFeedback = { rejected_id: string | null; selected_id: string };
export function applyIdentityFeedback(result: SemanticAnalysisResult, feedback: IdentityFeedback[]): { result: SemanticAnalysisResult; applied: number } {
  const copy: SemanticAnalysisResult = structuredClone(result);
  let applied = 0;
  for (const venue of copy.venues) {
    if (!venue.address || !["matched", "ambiguous"].includes(venue.mapStatus)) continue;
    const ids = new Set(venue.matches.map(place => place.id));
    const relevant = feedback.filter(row => row.rejected_id && ids.has(row.rejected_id));
    const selected = new Set(relevant.map(row => row.selected_id));
    // Contradictory histories never vote themselves into truth.
    if (selected.size !== 1) continue;
    const id = [...selected][0];
    if (ids.size === 1 && ids.has(id)) continue;
    venue.matches = venue.matches.filter(place => place.id === id);
    venue.mapStatus = venue.matches.length === 1 ? "matched" : "unverified";
    applied += 1;
  }
  return { result: copy, applied };
}

export class LinkPlaceIntelligence {
  constructor(private readonly pool: Pool) {}

  ownerCache(userId: string) {
    let epoch: string | undefined;
    const readEpoch = async () => {
      await this.pool.query("insert into extraction_cache_epochs(user_id) select id from profiles where id=$1 on conflict do nothing", [userId]);
      const {rows} = await this.pool.query("select epoch::text from extraction_cache_epochs where user_id=$1", [userId]);
      epoch = rows[0]?.epoch;
    };
    return {
      load: async (key: string): Promise<unknown | undefined> => {
        if (!userId || !hexKey.test(key)) return undefined;
        await readEpoch();
        const { rows } = await this.pool.query(`select extracted from semantic_extraction_cache
          where user_id=$1 and input_key=$2 and expires_at>clock_timestamp()`, [userId,key]);
        return rows[0]?.extracted;
      },
      save: async (key: string, raw: unknown) => {
        if (!userId || !hexKey.test(key)) return;
        const serialized = JSON.stringify(raw);
        if (!serialized || Buffer.byteLength(serialized)>64000) return;
        if (epoch === undefined) await readEpoch();
        const client = await this.pool.connect();
        try {
          await client.query("begin");
          const current = await client.query("select epoch::text from extraction_cache_epochs where user_id=$1 for update", [userId]);
          if (!epoch || current.rows[0]?.epoch !== epoch) { await client.query("rollback"); return; }
          await client.query(`insert into semantic_extraction_cache(user_id,input_key,extracted,expires_at)
            values($1,$2,$3::jsonb,clock_timestamp()+interval '24 hours')
            on conflict(user_id,input_key) do update set extracted=excluded.extracted,
              expires_at=excluded.expires_at,created_at=clock_timestamp()`, [userId,key,serialized]);
          await client.query(`delete from semantic_extraction_cache where user_id=$1 and
            (expires_at<=clock_timestamp() or input_key in (select input_key from semantic_extraction_cache
              where user_id=$1 order by created_at desc,input_key offset 100))`, [userId]);
          await client.query("commit");
        } catch (error) { await client.query("rollback"); throw error; }
        finally { client.release(); }
      },
    };
  }

  extractionCache(userId: string, captureId: string, sourceURL: unknown, contentStamp: string) {
    const source = canonicalSourceURL(sourceURL);
    const sourceKey = source ? hash(source) : undefined;
    let inputKey: string | undefined;
    const ownerCache = this.ownerCache(userId);
    let canBind = false;
    const valid = (key: string) => !!userId && !!sourceKey && hexKey.test(key);
    return {
      cache: {
        load: async (key: string) => {
          inputKey = valid(key) ? key : undefined;
          const available = await this.pool.query(`select to_regclass('candidate_extraction_inputs') is not null as available,
            exists(select 1 from captures where id=$1 and user_id=$2
              and md5(jsonb_build_array(source_url,raw_text,source_resolution->'captured_text_v1')::text)=$3) as owned`, [captureId,userId,contentStamp]);
          canBind = available.rows[0]?.available === true && available.rows[0]?.owned === true;
          if (!available.rows[0]?.owned) inputKey = undefined;
          return inputKey ? ownerCache.load(key) : undefined;
        },
        save: async (key: string, raw: unknown) => { if (inputKey && valid(key)) await ownerCache.save(key,raw); },
      },
      key: () => inputKey,
      bindCandidate: async (db: DB, candidateId: string, acceptedKey: string | undefined) => {
        if (!canBind || !acceptedKey || !valid(acceptedKey) || !contentStamp) return;
        await db.query(`insert into candidate_extraction_inputs(candidate_id,capture_id,user_id,source_key,input_key,content_stamp)
          select pc.id,c.id,c.user_id,$4,$5,$6 from place_candidates pc
          join captures c on c.id=pc.capture_id and c.user_id=$2
          where pc.id=$1 and c.id=$3 and md5(jsonb_build_array(c.source_url,c.raw_text,c.source_resolution->'captured_text_v1')::text)=$6
          on conflict(candidate_id) do nothing`, [candidateId,userId,captureId,sourceKey,acceptedKey,contentStamp]);
      },
      feedback: async (result: SemanticAnalysisResult) => {
        if (!inputKey || !sourceKey || !contentStamp || result.status !== "ready") return { result, applied: 0 };
        // Current ownership, candidate state and final saved identity are read on
        // every use. Deleted/rejected/reassigned evidence cannot be resurrected.
        const { rows } = await this.pool.query(`select distinct f.rejected_id,f.selected_id
          from place_identity_feedback f
          join captures c on c.id=f.capture_id and c.user_id=f.user_id
          join place_candidates pc on pc.id=f.candidate_id and pc.capture_id=c.id
            and pc.status in ('saved','confirmed') and pc.place_id=f.final_place_id
          join places p on p.id=f.final_place_id and p.user_id=f.user_id and p.google_place_id=f.selected_id
          join user_decisions ud on ud.id=f.decision_id and ud.user_id=f.user_id
          where f.user_id=$1 and f.source_key=$2 and f.input_key=$3
            and p.status in ('wantToGo','visited')
            and not exists(select 1 from user_decisions newer where newer.user_id=f.user_id
              and newer.candidate_id=f.candidate_id and newer.created_at>ud.created_at)
            and exists(select 1 from captures current_source where current_source.id=$4 and current_source.user_id=$1
              and md5(jsonb_build_array(current_source.source_url,current_source.raw_text,current_source.source_resolution->'captured_text_v1')::text)=$5)`, [userId,sourceKey,inputKey,captureId,contentStamp]);
        return applyIdentityFeedback(result, rows as IdentityFeedback[]);
      },
    };
  }

  async sources(userId: string, placeId: string) {
    const owned = await this.pool.query("select id,source_url from places where id=$1 and user_id=$2", [placeId,userId]);
    if (!owned.rows[0]) return undefined;
    const { rows } = await this.pool.query(`select c.id as capture_id,c.source_url,pc.status,
        exists(select 1 from user_decisions ud where ud.user_id=$1 and ud.candidate_id=pc.id
          and ud.final_place_id=pc.place_id and ud.action in ('edit','wrong_place','wrong_city','wrong_branch')) as corrected
      from place_candidates pc join captures c on c.id=pc.capture_id
      where pc.place_id=$2 and c.user_id=$1 and pc.status in ('saved','confirmed')
      order by c.created_at,c.id`, [userId,placeId]);
    const sources = new Map<string, { url: string; capture_ids: string[]; corrected: boolean }>();
    for (const row of [...rows,{source_url:owned.rows[0].source_url}]) {
      const url = canonicalSourceURL(row.source_url);
      if (!url) continue;
      const item = sources.get(url) ?? { url,capture_ids:[],corrected:false };
      if (row.capture_id && !item.capture_ids.includes(row.capture_id)) item.capture_ids.push(row.capture_id);
      item.corrected ||= row.corrected === true;
      sources.set(url,item);
    }
    return { place_id:placeId,privacy:"owner_private",sources:[...sources.values()] };
  }
}

// No user IDs, private notes, raw source URLs, or arbitrary slicing are exposed.
// Current eligibility is applied before grouping, so withdrawal/deletion is live.
export async function placePopularity(db: DB, now = new Date()) {
  const { rows } = await db.query(`with eligible as (
      select p.id,p.user_id,p.google_place_id,p.status,s.saved_at,s.first_visited_at
      from places p join place_visibility pv on pv.place_id=p.id and pv.user_id=p.user_id
      left join place_signal_state s on s.place_id=p.id and s.user_id=p.user_id and s.google_place_id=p.google_place_id
      where pv.visibility in ('public_link','public_guide') and pv.allow_trending_signal=true
        and left(p.user_id,6)<>'guest_' and p.status in ('wantToGo','visited') and nullif(btrim(p.google_place_id),'') is not null
    ), people as (
      select google_place_id,user_id,
        case when bool_and(saved_at is not null) then min(saved_at) end as saved_at,
        min(first_visited_at) filter(where status='visited') as visited_at
      from eligible group by google_place_id,user_id
    ), counts as (
      select google_place_id,
        count(*) filter(where saved_at>$1::timestamptz-interval '30 days' and saved_at<=$1)::int as save_count,
        count(*) filter(where visited_at>$1::timestamptz-interval '30 days' and visited_at<=$1)::int as visit_count
      from people group by google_place_id
    ) select google_place_id,case when save_count>=5 then save_count end as save_count,
      case when visit_count>=5 then visit_count end as self_reported_visit_count
    from counts where save_count>=5 or visit_count>=5
    order by coalesce(case when visit_count>=5 then visit_count end,0) desc,
      coalesce(case when save_count>=5 then save_count end,0) desc,google_place_id limit 40`, [now.toISOString()]);
  const sources = await db.query(`select p.google_place_id,p.source_url from places p
      join place_visibility pv on pv.place_id=p.id and pv.user_id=p.user_id
      where p.google_place_id=any($1::text[]) and left(p.user_id,6)<>'guest_' and p.status in ('wantToGo','visited')
        and pv.visibility in ('public_link','public_guide') and pv.allow_trending_signal=true
      union all
      select p.google_place_id,c.source_url from places p
      join place_visibility pv on pv.place_id=p.id and pv.user_id=p.user_id
      join place_candidates pc on pc.place_id=p.id and pc.status in ('saved','confirmed')
      join captures c on c.id=pc.capture_id and c.user_id=p.user_id
      where p.google_place_id=any($1::text[]) and left(p.user_id,6)<>'guest_' and p.status in ('wantToGo','visited')
        and pv.visibility in ('public_link','public_guide') and pv.allow_trending_signal=true`, [rows.map(row => row.google_place_id)]);
  const sourceCounts = new Map<string,Set<string>>();
  for (const source of sources.rows) {
    const canonical = canonicalSourceURL(source.source_url);
    if (!canonical) continue;
    const set = sourceCounts.get(source.google_place_id) ?? new Set<string>();
    set.add(canonical); sourceCounts.set(source.google_place_id,set);
  }
  return { window_days:30,as_of:now.toISOString(),population:"explicitly_public_opted_in_savvy_users",
    visit_evidence:"self_reported",minimum_people:5,source_count_window:"current_eligible_associations",
    places:rows.map(row => ({...row,linked_source_count:sourceCounts.get(row.google_place_id)?.size ?? 0})) };
}
