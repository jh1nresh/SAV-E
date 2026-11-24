import { hasDirectPublicPlaceMention } from "./publicDiscoveryMentionEvidence.js";
import type { PublicDiscoveryPlace } from "./publicDiscovery.js";
import { publicPostEvidenceFingerprint, readPublicPostForVenueReview } from "./publicPostReverification.js";

type Platform = "instagram" | "threads";
const district = "(?:松山|信義|大安|中山|中正|大同|萬華|文山|南港|內湖|士林|北投)區";
const street = "[\\p{Script=Han}]{1,16}?(?:大道|街|路)(?:[東西南北])?(?:[一二三四五六七八九十0-9]{1,2}段)?(?:[0-9]{1,5}巷)?(?:[0-9]{1,5}弄)?";
const digits = "[0-9]{1,5}";
const door = `${digits}(?:[-之]${digits})?號(?:之${digits})?`;
const floor = "(?:[bB]?[0-9]{1,3}(?:樓|[fF])(?:之[0-9]{1,3})?)?";
const address = `台北市(${district})(${street})(${door})(${floor})`;
const conflictingContext = /舊址|舊店|搬遷|搬家|遷址|搬到|搬去|原址|新址|快閃|限定活動|美食節|營業異動|歇業|停業/u;
const unitOrProximityHint = /^(?:之|正?對面|正?对面|旁|隔壁|前|後|樓|室|戶|棟|櫃|攤|[0-9]|附近|鄰近|近旁|周邊|週邊|周边|周圍|周围|一帶|nearby|opposite|nextto|acrossfrom)/u;
const proximityBeforeAddress = /(?:靠近|鄰近|临近|接近|距離|距离|距|離|离|近|near|nearby|opposite|nextto|acrossfrom|around)[「『“"'（(【]*$/u;
const addressSuffixPunctuation = /^[「」『』“”"'【】()[\]的]*/u;
const abbreviatedAddress = new RegExp(`${street}${door}`, "u");
const supportedCategories = new Set(["food", "cafe", "restaurant"]);

function normalize(value: string): string {
  return value.normalize("NFKC").replace(/臺/gu, "台").replace(/\s+/gu, "").toLowerCase();
}

function matchedKey(match: RegExpMatchArray): string {
  const parts = match[3]!.replace(/^(\d+)號之(\d+)$/u, "$1-$2號").replace(/之(?=\d+號$)/u, "-");
  return ["台北市", match[1], match[2], parts, match[4]].join("");
}

export function publicStreetKey(place: PublicDiscoveryPlace): string | undefined {
  const evidence = normalize(place.address).match(new RegExp(`^(?:[0-9]{3,6})?(?:台灣)?${address}$`, "u"));
  if (evidence) return matchedKey(evidence);
}

/** Narrow address evidence. Ambiguous results still need a branch reviewer. */
export function preflightTaipeiStreet(place: PublicDiscoveryPlace, placesAtAddress: ReadonlySet<string>) {
  if (!publicStreetKey(place) || !supportedCategories.has(place.category)) return "unsupported_address";
  if (placesAtAddress.size !== 1 || !placesAtAddress.has(`${place.provider}:${place.providerPlaceID}`)) return "shared_address";
}

export function classifyTaipeiStreetCaption(
  body: string, place: PublicDiscoveryPlace, placesAtAddress: ReadonlySet<string>,
) {
  const ineligible = preflightTaipeiStreet(place, placesAtAddress);
  if (ineligible) return ineligible;
  const target = publicStreetKey(place)!;
  const text = normalize(body);
  if (conflictingContext.test(text)) return "time_or_relocation";
  const matches = [...text.matchAll(new RegExp(address, "gu"))];
  if (matches.some(match => {
    const index = match.index!;
    const after = text.slice(index + match[0].length).replace(addressSuffixPunctuation, "");
    return unitOrProximityHint.test(after) || proximityBeforeAddress.test(text.slice(0, index));
  })) return "ambiguous_address";
  const paths = new Set(matches.map(matchedKey));
  if (!paths.size) return "no_exact_address";
  if (paths.size !== 1 || abbreviatedAddress.test(text.replace(new RegExp(address, "gu"), "|"))) return "ambiguous_address";
  if (!paths.has(target)) return "different_branch";
  const name = normalize(place.name);
  if (Array.from(name).length < 4 || !hasDirectPublicPlaceMention(text, [name])) return "name_unconfirmed";
  return "exact_street_match";
}

function streetNumberKey(target: string | undefined) {
  return target?.replace(/(?:b?[0-9]{1,3}(?:樓|f)(?:之[0-9]{1,3})?)$/u, "");
}

export function publicTaipeiStreetInventory(places: PublicDiscoveryPlace[]) {
  const map = new Map<string, Set<string>>();
  for (const place of places) {
    // Suites and floors are kept distinct for a direct match. For ambiguity,
    // count every known storefront at the same street number.
    const door = streetNumberKey(publicStreetKey(place));
    if (!door) continue;
    const identities = map.get(door) ?? new Set<string>();
    identities.add(`${place.provider}:${place.providerPlaceID}`);
    map.set(door, identities);
  }
  return (place: PublicDiscoveryPlace): ReadonlySet<string> => {
    const door = streetNumberKey(publicStreetKey(place));
    return door ? map.get(door) ?? new Set() : new Set();
  };
}

export function verifyPublicTaipeiStreetCandidate(input: {
  html: string; platform: Platform; sourceURL: string; author?: string;
  place: PublicDiscoveryPlace; placesAtAddress: ReadonlySet<string>; evidenceAddress?: string;
}) {
  const { html, platform, sourceURL, author, place, placesAtAddress, evidenceAddress } = input;
  const original = readPublicPostForVenueReview(html, platform, sourceURL, author);
  if (!original) return { status: "original_unavailable" as const };
  const evidencePlace = evidenceAddress ? { ...place, address: evidenceAddress } : place;
  const status = classifyTaipeiStreetCaption(original.body, evidencePlace, placesAtAddress);
  if (status !== "exact_street_match") return { status };
  const contentFingerprint = publicPostEvidenceFingerprint(html, platform, sourceURL, original.author, place);
  if (!contentFingerprint) return { status: "original_unavailable" as const };
  return { status, authorHandle: original.author, contentFingerprint };
}
