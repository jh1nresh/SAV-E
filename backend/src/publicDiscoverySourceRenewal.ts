import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { canonicalSource, readPublicDiscoveryFile, timestamp, validatePublicDiscoveryManifest, validatePublicDiscoveryPlace,
  type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { activateReviewGeneration, record, resumeReviewGeneration } from "./publicDiscoveryGenerationTransition.js";
import { approvedSourceState, readActiveApprovedGeneration } from "./publicDiscoveryPublishGeneration.js";
import { compileApprovedPublicBatch } from "./publicDiscoveryReviewedBatch.js";
import { writePublicSourceJSON } from "./publicDiscoverySaveQueue.js";
import { publicPostEvidenceFingerprint, publicReviewEmbedURL, threadsParentFingerprintPrefix } from "./publicPostReverification.js";

const journal = "pending-renewal.json";
const day = 86_400_000;
const minute = 60_000;
const lead = 360 * minute;
const budget = 4;
const originalID = (url: string) => createHash("sha256").update(url).digest("hex");
type Candidate = {
  key: string; venue: string; place: PublicDiscoveryPlace; platform: "instagram" | "threads";
  sourceURL: string; author: string; fingerprint: string; review: Record<string, unknown>; expiry: number; end: number;
};
type Original = { url: string; rows: Candidate[]; due: boolean; expiry: number; liveExpiry: number };
type Receipt = {
  checkedAt: string; baseIndexSHA256: string; renewed: number; quarantined: number; unavailable: number; selected: number;
};

function readReceipt(value: unknown, baseIndexSHA256: string, checkedAt: string): Receipt {
  const row = record(value);
  if (row.baseIndexSHA256 !== baseIndexSHA256 || row.checkedAt !== checkedAt || Object.keys(row).length !== 6
    || [row.renewed, row.quarantined, row.unavailable, row.selected].some(count =>
      typeof count !== "number" || !Number.isSafeInteger(count) || count < 0)) throw new Error("Invalid source renewal receipt");
  return row as Receipt;
}

async function readRetries(path: string, now: number) {
  const raw = await readPublicDiscoveryFile(path).catch((error: NodeJS.ErrnoException) => {
    if (error.code !== "ENOENT") throw error;
    return undefined;
  });
  const retries = new Map<string, number>();
  if (raw === undefined) return retries;
  for (const [id, deadline] of Object.entries(record(raw))) {
    if (!/^[a-f0-9]{64}$/.test(id) || typeof deadline !== "number" || !Number.isSafeInteger(deadline) || deadline < 0) {
      throw new Error("Invalid source renewal retry");
    }
    if (deadline > now) retries.set(id, deadline);
  }
  return retries;
}

function selectOriginals(raw: unknown, held: ReadonlySet<string>, now: number, retries: ReadonlyMap<string, number>) {
  const archive = record(raw);
  if (!Array.isArray(archive.venues)) throw new Error("Invalid public source archive");
  const originals = new Map<string, Original>();
  const lastsUntil = new Map<string, number>();
  for (const value of archive.venues) {
    const row = record(value);
    const place = validatePublicDiscoveryPlace(row.place);
    const venue = `${place.provider}:${place.providerPlaceID}`;
    if (!Array.isArray(row.candidates)) throw new Error("Invalid source candidates");
    for (const value of row.candidates) {
      const candidate = record(value);
      if (candidate.review === null) continue;
      const review = record(candidate.review);
      const end = review.visibleUntil === undefined ? Infinity : Date.parse(timestamp(review.visibleUntil));
      if (end <= now) continue;
      const platform = candidate.platform;
      if (platform !== "instagram" && platform !== "threads") throw new Error("Invalid reviewed source platform");
      const { postID, url: sourceURL } = canonicalSource(candidate.sourceURL, platform);
      const key = `${venue}:${platform}:${postID}`;
      const expiry = Date.parse(timestamp(review.checkedAt)) + day;
      const current = expiry > now && !held.has(key);
      if (current) lastsUntil.set(venue, Math.max(lastsUntil.get(venue) ?? 0, Math.min(end, expiry)));
      if (typeof review.contentFingerprint !== "string" || typeof candidate.authorHandle !== "string") continue;
      const url = publicReviewEmbedURL(platform, sourceURL);
      const group = originals.get(url) ?? { url, rows: [], due: false, expiry: Infinity, liveExpiry: Infinity };
      group.rows.push({ key, venue, place, platform, sourceURL, author: candidate.authorHandle,
        fingerprint: review.contentFingerprint, review, expiry, end });
      group.due ||= expiry <= now + lead || held.has(key);
      group.expiry = Math.min(group.expiry, expiry);
      if (current) group.liveExpiry = Math.min(group.liveExpiry, expiry);
      originals.set(url, group);
    }
  }
  const due = [...originals.values()].filter(group => group.due && !retries.has(originalID(group.url))).sort((a, b) =>
    (a.liveExpiry === b.liveExpiry ? a.expiry - b.expiry : a.liveExpiry - b.liveExpiry) || a.url.localeCompare(b.url, "en"));
  const selected = new Set<Original>();
  const protectedVenues = new Set<string>();
  for (const group of due) {
    if (selected.size === budget) break;
    const atRisk = group.rows.filter(row => row.expiry > now && row.expiry <= now + lead && !held.has(row.key)
      && row.end > now + lead && (lastsUntil.get(row.venue) ?? 0) <= now + lead);
    if (!atRisk.some(row => !protectedVenues.has(row.venue))) continue;
    selected.add(group);
    for (const row of atRisk) protectedVenues.add(row.venue);
  }
  for (const group of due) {
    if (selected.size === budget) break;
    selected.add(group);
  }
  return [...selected];
}

export async function resumePendingSourceRenewal(root: string, descriptor: number, clock = () => new Date()) {
  const state = approvedSourceState(root, descriptor);
  const active = await readActiveApprovedGeneration(state);
  return resumeReviewGeneration(state, journal, active.indexSHA256, { clock, readReceipt });
}

/** Recheck previously approved originals only. The caller shares its provider hold with draft reads. */
export async function renewApprovedSources(root: string, descriptor: number, options: {
  clock: () => Date;
  fetchEmbed: (url: string) => Promise<string>;
  providerPaused: () => boolean;
}) {
  const state = approvedSourceState(root, descriptor);
  const { clock, fetchEmbed, providerPaused } = options;
  const now = clock();
  const active = await readActiveApprovedGeneration(state);
  const transition = { clock, readReceipt };
  const recovered = await resumeReviewGeneration(state, journal, active.indexSHA256, transition);
  if (recovered) return recovered;
  const { indexSHA256: baseIndexSHA256, raw, projectedAt, envelope } = active;
  const approved = validatePublicDiscoveryManifest(raw, projectedAt);
  assert.deepEqual(validatePublicDiscoveryManifest(compileApprovedPublicBatch(envelope.archive, envelope.held, projectedAt), projectedAt),
    approved, "Active review snapshot does not match its archive");
  const archive: unknown = structuredClone(envelope.archive);
  const retryPath = join(state, "source-renewal-retries.json");
  const retries = await readRetries(retryPath, +now);
  const selected = selectOriginals(archive, envelope.held, +now, retries);
  const quarantine = new Map(envelope.quarantine.map(value => {
    const row = record(value);
    return [String(row.key), row];
  }));
  const receipt: Receipt = { checkedAt: now.toISOString(), baseIndexSHA256, renewed: 0, quarantined: 0,
    unavailable: 0, selected: selected.length };
  const withhold = (key: string, reason: string) => {
    if (quarantine.get(key)?.reason !== reason) receipt.quarantined++;
    quarantine.set(key, { key, reason });
  };
  const retry = (url: string, minutes: number) => retries.set(originalID(url), +clock() + minutes * minute);
  let attempted = false;
  for (const original of selected) {
    if (providerPaused()) break;
    attempted = true;
    let html;
    try {
      html = await fetchEmbed(original.url);
    } catch (error) {
      if (error instanceof Error && /^(?:Provider )?HTTP (?:404|410)$/.test(error.message)) {
        for (const row of original.rows) withhold(row.key, "not_found");
        retry(original.url, 60);
      } else {
        receipt.unavailable++;
        retry(original.url, 5);
      }
      continue;
    }
    const checkedAt = clock();
    for (const row of original.rows) {
      if (row.end <= +checkedAt) continue;
      const fingerprint = publicPostEvidenceFingerprint(html, row.platform, row.sourceURL, row.author, row.place,
        row.fingerprint.startsWith(threadsParentFingerprintPrefix));
      if (fingerprint === row.fingerprint) {
        row.review.checkedAt = checkedAt.toISOString();
        quarantine.delete(row.key);
        receipt.renewed++;
      } else if (fingerprint) {
        withhold(row.key, "fingerprint_changed");
        retry(original.url, 60);
      } else {
        receipt.unavailable++;
        // Other associations may already have recorded the longer delay.
        if (!retries.has(originalID(original.url))) retry(original.url, 5);
      }
    }
  }
  if (attempted) await writePublicSourceJSON(retryPath, Object.fromEntries(retries));
  const snapshotAt = clock();
  receipt.checkedAt = snapshotAt.toISOString();
  const visible = compileApprovedPublicBatch(archive, new Set(quarantine.keys()), snapshotAt);
  if (Date.parse(approved.expiresAt) > +snapshotAt && !receipt.renewed && !receipt.quarantined
    && isDeepStrictEqual(visible.posts, approved.posts)) {
    return { activated: false, indexSHA256: baseIndexSHA256, ...receipt };
  }
  return activateReviewGeneration(state, journal, { archive, quarantine: [...quarantine.values()], manifest: visible, receipt }, transition);
}
