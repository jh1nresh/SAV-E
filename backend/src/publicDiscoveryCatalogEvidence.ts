import type { PublicDiscoveryPlace } from "./publicDiscovery.js";
import { publicPostEvidenceFingerprint, readPublicPostForVenueReview } from "./publicPostReverification.js";

type Platform = "instagram" | "threads";
const cities = new Set(["www.travel.taipei", "travel.taipei"]);
const authorityHosts = new Set([...cities, "www.gov.taipei", "www.post.gov.tw", "heo.gov.taipei"]);
const featureKey = /^Attraction_379000000A_([0-9]{6})$/u;
const featurePath = /^\/zh-tw\/attraction\/details\/([1-9][0-9]{0,5})\/?$/u;
const transientContext = /跨年|多元舞台|觀音祭|集章|踩街|限時|快閃|報名|抽獎|開幕記者會|搬遷|舊址|停業/u;
const neighbour = /^(?:附近|旁邊|旁的|邊的|對面|周邊)/u;
const visibleURL = /https:\/\/[^\s<>"'。。，、！？；）】]+/gu;

type FeatureProof = { catalogNumber: number; names: string[]; urls: Set<string> };

function normalize(value: string): string {
  return value.normalize("NFKC").replace(/臺/gu, "台").replace(/\s+/gu, "").toLowerCase();
}

function authorityLink(value: string): { url: string; catalogNumber?: number } | undefined {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.port || !authorityHosts.has(url.hostname)) return;
    const feature = cities.has(url.hostname) ? url.pathname.match(featurePath) : null;
    if (cities.has(url.hostname) && !feature) return;
    if (feature) {
      url.hostname = "www.travel.taipei";
      url.pathname = `/zh-tw/attraction/details/${feature[1]}`;
    }
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) if (/^utm_[a-z0-9_]+$/u.test(key)) url.searchParams.delete(key);
    url.searchParams.sort();
    return { url: url.href, catalogNumber: feature ? Number(feature[1]) : undefined };
  } catch {
    return;
  }
}

export function readTaipeiFeatureProof(raw: unknown, place: PublicDiscoveryPlace): FeatureProof {
  if (!raw || typeof raw !== "object") throw Error("Invalid official feature");
  const row = raw as Record<string, unknown>;
  const id = typeof row.catalogID === "string" ? row.catalogID.match(featureKey) : null;
  if (row.provider !== place.provider || row.providerPlaceID !== place.providerPlaceID || row.expectedName !== place.name) {
    throw Error("Stale official feature");
  }
  if (!id || !["attractions", "route", "area"].includes(place.category)
    || (place.provider === "taipei_catalog" && place.providerPlaceID !== row.catalogID)
    || !Array.isArray(row.names) || row.names.length < 1 || row.names.length > 4
    || !Array.isArray(row.authorityURLs) || row.authorityURLs.length < 1 || row.authorityURLs.length > 4) {
    throw Error("Invalid official feature");
  }
  const catalogNumber = Number(id[1]);
  const canonicalName = normalize(place.name);
  const names = row.names.map(value => {
    if (typeof value !== "string" || value.length > 80 || !/^[\p{Script=Han}0-9]+$/u.test(normalize(value))
      || normalize(value).length < 4) throw Error("Invalid official feature name");
    return normalize(value);
  });
  if (!names.some(name => canonicalName.includes(name))) throw Error("Invalid official feature name");
  const urls = new Set<string>();
  let sameCatalog = false;
  for (const value of row.authorityURLs) {
    const link = typeof value === "string" && value.length <= 500 ? authorityLink(value) : undefined;
    if (!link || (link.catalogNumber !== undefined && link.catalogNumber !== catalogNumber)) {
      throw Error("Invalid official feature URL");
    }
    sameCatalog ||= link.catalogNumber === catalogNumber;
    urls.add(link.url);
  }
  if (!sameCatalog) throw Error("Missing municipal feature URL");
  return { catalogNumber, names, urls };
}

function directlyNamesFeature(body: string, names: string[]): boolean {
  const compact = normalize(body);
  return names.some(name => compact.split(name).slice(1).some(after => !neighbour.test(after)));
}

export function verifyPublicTaipeiCatalogCandidate(input: {
  html: string; platform: Platform; sourceURL: string; author?: string; place: PublicDiscoveryPlace; proof: FeatureProof;
}) {
  const { html, platform, sourceURL, author, place, proof } = input;
  const original = readPublicPostForVenueReview(html, platform, sourceURL, author);
  if (!original) return { status: "original_unavailable" as const };
  if (transientContext.test(original.body)) return { status: "time_or_relocation" as const };
  if (!directlyNamesFeature(original.body, proof.names)) return { status: "feature_name_unconfirmed" as const };
  let hasProof = false;
  const links = [...original.bodyLinks, ...original.body.matchAll(visibleURL)].map(value =>
    authorityLink(typeof value === "string" ? value : value[0]));
  for (const link of links) {
    if (!link) continue;
    if (link.catalogNumber !== undefined && link.catalogNumber !== proof.catalogNumber) {
      return { status: "multiple_catalog_features" as const };
    }
    hasProof ||= proof.urls.has(link.url);
  }
  if (!hasProof) return { status: "no_catalog_link" as const };
  const contentFingerprint = publicPostEvidenceFingerprint(html, platform, sourceURL, original.author, place);
  if (!contentFingerprint) return { status: "original_unavailable" as const };
  return { status: "exact_catalog_feature" as const, authorHandle: original.author, contentFingerprint };
}
