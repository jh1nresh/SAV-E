import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";
import {
  canonicalSource, isPublicDiscoveryVenueID, readPublicDiscoveryFile, validatePublicDiscoveryPlace,
} from "./publicDiscovery.js";
import { staticPublicProfileMarkup } from "./publicPostReverification.js";
import { boundedResponseText, sourceMetadataFromHTML } from "./sourceSearchWorker.js";

const maxProfiles = 30;
const maxVenues = 20;
export const publicProfileCandidateLimit = 20;
const maxResponseBytes = 3 * 1_024 * 1_024;
const maxJSONNodes = 80_000;
const handlePattern = /^(?=.*[a-z0-9_])[a-z0-9._]{1,30}$/i;
const postPattern = /^[a-z0-9_-]{1,100}$/i;
type Platform = "instagram" | "threads";
type Profile = { platform: Platform; handle: string };
type ProfileQuery = Profile & { terms: string[]; branchTerms: string[] };
type ProfilePost = { id: string; sourceURL: string; caption: string };
type ProfileStatus = "read" | "no_readable_posts" | "access_required" | "rate_limited"
  | "unavailable" | "not_attempted";
type ProfileResult = { status: ProfileStatus; posts: ProfilePost[] };
type DraftCandidate = {
  platform: Platform; sourceURL: string; authorHandle: string; observedIn: string; title: string; review: null;
};
type JSONObject = Record<string, unknown>;

function object(value: unknown): JSONObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JSONObject : undefined;
}

function records(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function fields(value: unknown, expected: string[], optional: string[] = []): JSONObject {
  const row = object(value);
  if (!row || !expected.every(key => Object.hasOwn(row, key))
    || Object.keys(row).some(key => !expected.includes(key) && !optional.includes(key))) {
    throw new Error("Invalid profile batch input");
  }
  return row;
}

function normalizedText(value: string): string {
  return value.normalize("NFKC").toLowerCase().trim().replace(/\s+/gu, " ");
}

function profileKey({ platform, handle }: Profile): string {
  return `${platform}:${handle}`;
}

function profileURL({ platform, handle }: Profile): string {
  return platform === "threads" ? `https://www.threads.com/@${handle}` : `https://www.instagram.com/${handle}/`;
}

function matchTerms(terms: unknown): string[] {
  if (!Array.isArray(terms) || terms.length < 1 || terms.length > 8) throw new Error("Invalid match terms");
  const normalized = Array.from(terms, (term: unknown) => {
    if (typeof term !== "string" || term.length > 160 || /[\p{Cc}]/u.test(term)) throw new Error("Invalid match term");
    const text = normalizedText(term);
    if (Array.from(text).length < 2) throw new Error("Invalid match term");
    return text;
  });
  return [...new Set(normalized)];
}

function profileQuery(value: unknown): ProfileQuery {
  const row = fields(value, ["platform", "handle", "terms"], ["branchTerms"]);
  const { platform, handle, terms, branchTerms } = row;
  if ((platform !== "instagram" && platform !== "threads") || typeof handle !== "string"
    || !handlePattern.test(handle)) throw new Error("Invalid profile query");
  return {
    platform, handle: handle.toLowerCase(), terms: matchTerms(terms),
    branchTerms: Object.hasOwn(row, "branchTerms") ? matchTerms(branchTerms) : [],
  };
}

function authorPrivacy(profile: Profile, owner: JSONObject | undefined): boolean | undefined {
  const privacyKey = profile.platform === "threads" ? "text_post_app_is_private" : "is_private";
  if (typeof owner?.username !== "string" || owner.username.toLowerCase() !== profile.handle) return;
  if (owner[privacyKey] === true || owner.is_private === true) return true;
  return owner[privacyKey] === false ? false : undefined;
}

function matchingAuthorPost(profile: Profile, row: JSONObject | undefined): ProfilePost | undefined {
  if (!row) return;
  const owner = object(row.user) ?? object(row.owner);
  const code = row.code ?? row.shortcode;
  const text = object(row.caption)?.text;
  if (!owner || typeof owner.username !== "string" || owner.username.toLowerCase() !== profile.handle
    || authorPrivacy(profile, owner) === true || typeof code !== "string" || !postPattern.test(code)
    || typeof text !== "string" || !text.trim() || text.length > 8_000) return;
  let rawURL: string;
  if (profile.platform === "threads") {
    rawURL = `${profileURL(profile)}/post/${code}`;
  } else {
    if (row.media_type !== 1 && row.media_type !== 2 && row.media_type !== 8) return;
    rawURL = `https://www.instagram.com/${row.product_type === "clips" ? "reel" : "p"}/${code}/`;
  }
  const { url, postID } = canonicalSource(rawURL, profile.platform);
  return { id: postID, sourceURL: url, caption: normalizedText(text) };
}

function providerData(scripts: string[]): JSONObject[] {
  const payloads: JSONObject[] = [];
  let visited = 0;
  for (const script of scripts) {
    let root: unknown;
    try { root = JSON.parse(script); } catch { continue; }
    const stack = [root];
    while (stack.length) {
      if (++visited > maxJSONNodes) throw new Error("Profile data is too complex");
      const item = stack.pop();
      if (Array.isArray(item)) {
        for (const value of item) stack.push(value);
      } else {
        const row = object(item);
        if (!row) continue;
        const data = object(object(object(row.__bbox)?.result)?.data);
        if (data) payloads.push(data);
        for (const value of Object.values(row)) stack.push(value);
      }
    }
  }
  return payloads;
}

/** Inspect the provider timeline only after a matching public profile is present. */
function profilePosts(scripts: string[], profile: Profile): ProfileResult {
  const payloads = providerData(scripts);
  const owners = payloads.map(data => object(profile.platform === "instagram" ? data.xig_user_by_username : data.user));
  const access = owners.map(owner => authorPrivacy(profile, owner));
  if (access.includes(true)) return { status: "access_required", posts: [] };
  if (!access.includes(false)) return { status: "no_readable_posts", posts: [] };
  const rows: unknown[] = [];
  if (profile.platform === "instagram") {
    // The header carries privacy; a separate timeline fragment carries only the same provider account ID.
    const ids = new Set(owners.flatMap((owner, i) => access[i] === false && typeof owner?.id === "string"
      && /^\d{1,30}$/.test(owner.id) ? [owner.id] : []));
    if (ids.size === 1) {
      for (const owner of owners) {
        if (typeof owner?.id !== "string" || !ids.has(owner.id)) continue;
        if (owner.is_private === true) return { status: "access_required", posts: [] };
        if (owner.username !== undefined
            && (typeof owner.username !== "string" || owner.username.toLowerCase() !== profile.handle)) {
          return { status: "unavailable", posts: [] };
        }
        for (const edge of records(object(owner.polaris_ordered_timeline_connection)?.edges)) {
          rows.push(object(edge)?.node);
        }
      }
    }
  } else {
    for (const data of payloads) {
      for (const edge of records(object(data.mediaData)?.edges)) {
        for (const item of records(object(object(edge)?.node)?.thread_items)) {
          rows.push(object(item)?.post);
        }
      }
    }
  }

  const posts = new Map<string, ProfilePost | null>();
  for (const row of rows) {
    const post = matchingAuthorPost(profile, object(row));
    if (!post) continue;
    const prior = posts.get(post.id);
    if (prior === undefined) posts.set(post.id, post);
    else if (prior && (prior.caption !== post.caption || prior.sourceURL !== post.sourceURL)) posts.set(post.id, null);
  }
  const readable = [...posts.values()].filter((post): post is ProfilePost => post !== null);
  return { status: readable.length ? "read" : "no_readable_posts", posts: readable };
}

function isLoginRedirect(response: Response, url: URL): boolean {
  const location = response.headers.get("location");
  if (response.status < 300 || response.status >= 400 || !location) return false;
  try {
    const target = new URL(location, url);
    return target.origin === url.origin && !target.username && !target.password
      && /^\/(?:login|accounts\/login|challenge|checkpoint)(?:\/|$)/i.test(target.pathname);
  } catch { return false; }
}

async function readProfile(profile: Profile, fetchImpl: typeof fetch): Promise<ProfileResult> {
  try {
    const url = new URL(profileURL(profile));
    const response = await fetchImpl(url, {
      headers: { Accept: "text/html", "User-Agent": "Mozilla/5.0" },
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok || !/^text\/html(?:\s*;|$)/i.test(response.headers.get("content-type") ?? "")) {
      void response.body?.cancel().catch(() => {});
      const status = response.status === 429 ? "rate_limited"
        : [401, 403].includes(response.status) || isLoginRedirect(response, url) ? "access_required" : "unavailable";
      return { status, posts: [] };
    }
    const html = await boundedResponseText(response, maxResponseBytes);
    const page = staticPublicProfileMarkup(html);
    const title = (sourceMetadataFromHTML(page.markup.slice(0, 32_768)).title ?? page.title ?? "").toLowerCase();
    if (!title.includes(`(@${profile.handle})`)) {
      return { status: /\b(?:log in|login)\b/.test(title) ? "access_required" : "unavailable", posts: [] };
    }
    return profilePosts(page.scripts, profile);
  } catch {
    return { status: "unavailable", posts: [] };
  }
}

/**
 * Find drafts with a business term and, if supplied, a separate branch term in the caption.
 * These matches are leads for review and do not establish a venue association.
 */
export async function collectPublicProfileDiscoveryDrafts(raw: unknown, fetchImpl: typeof fetch = fetch) {
  const { venues } = fields(raw, ["venues"]);
  if (!Array.isArray(venues) || venues.length < 1 || venues.length > maxVenues) throw new Error("Invalid venue batch");
  const venueKeys = new Set<string>();
  const input = venues.map((value: unknown) => {
    const row = fields(value, ["place", "profiles"]);
    const place = validatePublicDiscoveryPlace(row.place);
    const key = `${place.provider}:${place.providerPlaceID}`;
    if (!isPublicDiscoveryVenueID(place.providerPlaceID) || venueKeys.has(key)
      || !Array.isArray(row.profiles) || row.profiles.length < 1 || row.profiles.length > maxProfiles) {
      throw new Error("Invalid public venue or profile count");
    }
    venueKeys.add(key);
    return { place, profiles: row.profiles.map(profileQuery) };
  });
  const uniqueProfiles = new Map(input.flatMap(row => row.profiles.map(profile => [profileKey(profile), profile] as const)));
  if (uniqueProfiles.size > maxProfiles) throw new Error("Profile budget exceeded");

  const halted = new Set<Platform>();
  const results = new Map<string, ProfileResult>();
  const profiles = [];
  for (const [key, { platform, handle }] of uniqueProfiles) {
    const result: ProfileResult = halted.has(platform) ? { status: "not_attempted", posts: [] }
      : await readProfile({ platform, handle }, fetchImpl);
    if (result.status === "rate_limited") halted.add(platform);
    results.set(key, result);
    profiles.push({ platform, handle, status: result.status, readablePosts: result.posts.length });
  }

  const draft = input.flatMap(({ place, profiles: queries }) => {
    const matches = new Map<string, DraftCandidate>();
    for (const profile of queries) {
      for (const post of results.get(profileKey(profile))!.posts) {
        if (!profile.terms.some(term => post.caption.includes(term))) continue;
        if (profile.branchTerms.length && !profile.branchTerms.some(term => post.caption.includes(term))) continue;
        matches.set(`${profile.platform}:${post.id}`, {
          platform: profile.platform, sourceURL: post.sourceURL, authorHandle: profile.handle,
          observedIn: profileURL(profile), title: "", review: null,
        });
      }
    }
    const candidates = [...matches.values()].slice(0, publicProfileCandidateLimit);
    return candidates.length ? [{ place, candidates }] : [];
  });
  return { draft: { venues: draft }, profiles };
}

function runningAsCommand(entry: string | undefined): boolean {
  if (typeof import.meta.main === "boolean") return import.meta.main;
  // Node 20 does not expose import.meta.main. Evaluation arguments are not script paths.
  if (!entry || entry === "-" || process.execArgv.some(arg => /^(?:-[ep]|--(?:eval|print)(?:=|$))/.test(arg))) return false;
  if (pathToFileURL(entry).href === import.meta.url) return true;
  // Node resolves symlinks for the module URL but preserves the invocation path in argv.
  try { return pathToFileURL(realpathSync(entry)).href === import.meta.url; }
  catch { return false; }
}

if (runningAsCommand(process.argv[1])) {
  void (async () => {
    const [input] = process.argv.slice(2);
    if (!input || process.argv.length !== 3) throw new Error("Expected one public profile batch file");
    const result = await collectPublicProfileDiscoveryDrafts(await readPublicDiscoveryFile(input));
    process.stdout.write(`${JSON.stringify(result)}\n`);
  })().catch(() => {
    process.stderr.write("Public profile drafts could not be generated. Check the batch file.\n");
    process.exitCode = 1;
  });
}
