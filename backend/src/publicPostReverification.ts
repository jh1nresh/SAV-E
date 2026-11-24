import { createHash } from "node:crypto";
import { canonicalSource, type PublicDiscoveryPlace } from "./publicDiscovery.js";
import { decodeHTML } from "./sourceSearchWorker.js";

type Platform = "instagram" | "threads";
export const threadsParentFingerprintPrefix = "threads-parent-v1:";

export function publicReviewEmbedURL(platform: Platform, sourceURL: string): string {
  const url = canonicalSource(sourceURL, platform).url;
  return platform === "instagram" ? `${url}embed/captioned/` : `${url}/embed`;
}

function staticMarkupAttributes(markup: string): Map<string, string> {
  const values = new Map<string, string>();
  for (const match of markup.matchAll(/\s+([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+)))?/g)) {
    const key = match[1]!.toLowerCase();
    if (!values.has(key)) values.set(key, decodeHTML(match[2] ?? match[3] ?? match[4] ?? ""));
  }
  return values;
}

type Element = { attributes: Map<string, string>; end: number; body: string };

function staticMarkupTagPattern(): RegExp {
  return /<!--[\s\S]*?(?:-->|$)|<(\/?)([A-Za-z][\w:-]*)(?=[\s/>])(?:[^<>"']|"[^"]*"|'[^']*')*>/g;
}

function isHiddenStaticTag(tag: string, markup: string): boolean {
  const attrs = staticMarkupAttributes(markup);
  const style = (attrs.get("style") ?? "").replace(/\/\*[\s\S]*?\*\//g, "").replace(/\s+/g, "");
  return tag === "template" || (tag === "details" && !attrs.has("open")) || attrs.has("hidden")
    || attrs.get("aria-hidden")?.trim().toLowerCase() === "true"
    || /(?:^|;)(?:display:none|visibility:(?:hidden|collapse)|opacity:[+-]?(?:0+(?:\.0*)?|\.0+)%?)(?:!important)?(?:;|$)/i.test(style);
}

function visibleStaticPostMarkup(
  html: string, readInertTag?: (tag: string, markup: string, body: string) => void,
): string {
  const tags = staticMarkupTagPattern();
  const inert = new Set(["script", "style", "noscript", "iframe", "textarea", "title", "xmp", "noembed", "noframes"]);
  const voidTags = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
  const parts: string[] = [];
  let start = 0;
  let hidden: { tag: string; depth: number } | undefined;
  for (let match = tags.exec(html); match; match = tags.exec(html)) {
    const tag = match[2]?.toLowerCase();
    const closing = match[1] === "/";
    if (!tag || (!closing && (inert.has(tag) || tag === "plaintext"))) {
      if (!hidden) parts.push(html.slice(start, match.index));
      if (tag === "plaintext") return parts.join("");
      if (tag) {
        const end = new RegExp(`</${tag}(?=[\\s/>])[^>]*>`, "ig");
        end.lastIndex = tags.lastIndex;
        const closingTag = end.exec(html);
        if (closingTag && readInertTag && !hidden && !isHiddenStaticTag(tag, match[0])) {
          readInertTag(tag, match[0], html.slice(tags.lastIndex, closingTag.index));
        }
        tags.lastIndex = closingTag ? end.lastIndex : html.length;
      }
      start = tags.lastIndex;
      continue;
    }
    if (hidden) {
      if (tag === hidden.tag && (hidden.depth += closing ? -1 : 1) === 0) {
        hidden = undefined;
        start = tags.lastIndex;
      }
      continue;
    }
    if (closing) continue;
    if (isHiddenStaticTag(tag, match[0])) {
      parts.push(html.slice(start, match.index));
      start = tags.lastIndex;
      if (!voidTags.has(tag)) hidden = { tag, depth: 1 };
    }
  }
  if (!hidden) parts.push(html.slice(start));
  return parts.join("");
}

export function staticPublicProfileMarkup(html: string) {
  const scripts: string[] = [];
  let title: string | undefined;
  const markup = visibleStaticPostMarkup(html, (tag, opening, body) => {
    if (tag === "title" && title === undefined) title = decodeHTML(body);
    if (tag === "script" && staticMarkupAttributes(opening).get("type")?.toLowerCase() === "application/json") {
      scripts.push(body);
    }
  });
  return { markup, title, scripts };
}

// Read the provider's named, static embed elements. Missing or changed layouts are inconclusive.
function elements(html: string, tag: "a" | "div" | "span", className?: string): Element[] {
  const stack: Array<{ attributes: Map<string, string>; end: number }> = [];
  const found: Element[] = [];
  for (const tagMatch of html.matchAll(staticMarkupTagPattern())) {
    if (tagMatch[2]?.toLowerCase() !== tag) continue;
    const index = tagMatch.index!;
    if (tagMatch[1]) {
      const open = stack.pop();
      if (open && (!className || open.attributes.get("class")?.split(/\s+/).includes(className))) {
        found.push({ ...open, body: html.slice(open.end, index) });
      }
    } else {
      stack.push({ attributes: staticMarkupAttributes(tagMatch[0]), end: index + tagMatch[0].length });
    }
  }
  return found;
}

function visibleText(markup: string): string {
  return decodeHTML(markup.replace(/<br\b[^>]*>/gi, "\n")
    .replace(/<(?:\/?[A-Za-z][\w:-]*)(?=[\s/>])(?:[^<>"']|"[^"]*"|'[^']*')*>/g, ""))
    .normalize("NFC").replace(/\s+/gu, " ").trim();
}

function instagramCaptionBody(markup: string): string {
  for (const tag of markup.matchAll(staticMarkupTagPattern())) {
    if (tag[2] && !tag[1]
      && staticMarkupAttributes(tag[0]).get("class")?.split(/\s+/).includes("CaptionComments")) {
      return markup.slice(0, tag.index);
    }
  }
  return markup;
}

function exactPostLink(anchor: Element, platform: Platform, sourceURL: string): boolean {
  try { return canonicalSource(anchor.attributes.get("href"), platform).url === sourceURL; }
  catch { return false; }
}

function evidenceLink(anchor: Element, base: string): string {
  const raw = anchor.attributes.get("href") ?? "";
  if (!raw) return "";
  try {
    const url = new URL(raw, base);
    // Strip only observed provider parameters that rotate per embed request.
    if (url.origin === "https://www.instagram.com") url.searchParams.delete("ig_rid");
    if (url.origin === "https://www.threads.com") url.searchParams.delete("xmt");
    if (url.origin === "https://l.facebook.com" && url.pathname === "/l.php" && url.searchParams.has("u")) {
      url.searchParams.delete("h");
    }
    return url.href;
  } catch { return raw; }
}

function inspectPublicPostEmbed(
  html: string, platform: Platform, sourceURL: string, expectedAuthor?: string,
  includeThreadParent = false,
) {
  if (html.length > 768_000) return;
  const canonical = canonicalSource(sourceURL, platform).url;
  for (const tag of html.matchAll(staticMarkupTagPattern())) {
    if (tag[2]?.toLowerCase() === "base" && staticMarkupAttributes(tag[0]).has("href")) return;
  }
  const embed = elements(visibleStaticPostMarkup(html), "div", "Embed");
  if (embed.length !== 1) return;
  const visible = embed[0]!.body;
  let reviewedMarkup = visible;
  let threadLinkMarkup: string | undefined;
  let parentEvidence: [string, string, string[]] | undefined;
  if (platform === "threads" && elements(visible, "span", "BodyTextContainer").length > 1) {
    // A public reply embed can include its parent before the selected reply.
    const containers = elements(visible, "div", "OuterContainer").sort((a, b) => a.end - b.end);
    const [parent, reply] = containers;
    const parentBody = parent ? elements(parent.body, "div", "BodyContainerParent") : [];
    const replyBody = reply ? elements(reply.body, "div", "BodyContainerNoThreadLine") : [];
    if (containers.length !== 2 || !parent || !reply
      || parent.attributes.get("class")?.split(/\s+/).includes("OuterContainerFull")
      || !reply.attributes.get("class")?.split(/\s+/).includes("OuterContainerFull")
      || parentBody.length !== 1 || replyBody.length !== 1
      || elements(parentBody[0]!.body, "span", "BodyTextContainer").length !== 1
      || elements(replyBody[0]!.body, "span", "BodyTextContainer").length !== 1
      || elements(parent.body, "span", "BodyTextContainer").length !== 1
      || elements(visible, "div", "LinkContainer").length !== 1) return;
    reviewedMarkup = reply.body;
    threadLinkMarkup = visible.slice(0, parent.end);
    if (includeThreadParent) {
      const identities = elements(parent.body, "div", "AuthorIdentity");
      const profiles = identities.length === 1 ? elements(identities[0]!.body, "a", "HeaderLink") : [];
      const [parentCaption] = elements(parentBody[0]!.body, "span", "BodyTextContainer");
      const parentText = visibleText(parentCaption!.body);
      if (profiles.length !== 1 || Array.from(parentText).length < 12) return;
      const embedURL = publicReviewEmbedURL(platform, canonical);
      const profile = evidenceLink(profiles[0]!, embedURL);
      if (!/^https:\/\/www\.threads\.com\/@[a-z0-9._]{1,30}$/i.test(profile)) return;
      parentEvidence = [profile.toLowerCase(), parentText,
        elements(parentCaption!.body, "a").map(anchor => evidenceLink(anchor, embedURL))];
    }
  }
  if (includeThreadParent && !parentEvidence) return;
  const caption = platform === "instagram"
    ? elements(reviewedMarkup, "div", "Caption") : elements(reviewedMarkup, "span", "BodyTextContainer");
  if (caption.length !== 1) return;
  const content = platform === "instagram" ? instagramCaptionBody(caption[0]!.body) : caption[0]!.body;
  const headers = reviewedMarkup.slice(0, caption[0]!.end);
  const threadAuthor = platform === "threads" ? elements(headers, "div", "AuthorIdentity") : [];
  if (platform === "threads" && threadAuthor.length !== 1) return;
  const profile = elements(platform === "instagram" ? content : threadAuthor[0]!.body, "a",
    platform === "instagram" ? "CaptionUsername" : "HeaderLink");
  const base = platform === "instagram" ? "https://www.instagram.com" : "https://www.threads.com";
  if (profile.length !== 1) return;
  let author: string | undefined;
  try {
    const url = new URL(profile[0]!.attributes.get("href") ?? "", base);
    if (url.origin !== base) return;
    if (platform === "threads" && new URL(canonical).pathname.split("/")[1]?.toLowerCase() !== url.pathname.slice(1).toLowerCase()) return;
    if (expectedAuthor !== undefined) {
      const profilePath = platform === "instagram" ? `/${expectedAuthor}/` : `/@${expectedAuthor}`;
      if (url.pathname.toLowerCase() !== profilePath.toLowerCase()) return;
      author = expectedAuthor;
    } else {
      const pattern = platform === "instagram" ? /^\/([a-z0-9._]{1,30})\/$/i : /^\/@([a-z0-9._]{1,30})$/i;
      author = url.pathname.match(pattern)?.[1];
    }
  } catch { return; }
  const threadLinks = platform === "threads" ? elements(threadLinkMarkup ?? headers, "div", "LinkContainer") : [];
  if (platform === "threads" && threadLinks.length !== 1) return;
  const permalink = platform === "instagram" ? elements(headers, "a", "EmbeddedMedia")
    : elements(threadLinks[0]!.body, "a");
  if (!author || permalink.length !== 1 || !exactPostLink(permalink[0]!, platform, canonical)) return;
  const body = visibleText(content);
  if (Array.from(body).length < 12) return;
  const locations = elements(headers, "a", "Location");
  const embedURL = publicReviewEmbedURL(platform, canonical);
  const location = locations.map(anchor => [visibleText(anchor.body), evidenceLink(anchor, embedURL)]);
  const bodyLinks = elements(content, "a").map(anchor => evidenceLink(anchor, embedURL));
  return { canonical, author, body, bodyLinks, location, parentEvidence };
}

/** Fingerprint an already-reviewed original. No caption, location URL or HTML is returned. */
export function publicPostEvidenceFingerprint(
  html: string, platform: Platform, sourceURL: string, author: string, place: PublicDiscoveryPlace,
  includeThreadParent = false,
): string | undefined {
  const evidence = inspectPublicPostEmbed(html, platform, sourceURL, author, includeThreadParent);
  if (!evidence) return;
  const { canonical, body, bodyLinks, location, parentEvidence } = evidence;
  const digest = createHash("sha256").update(JSON.stringify([
    "public-embed-evidence-v1", canonical, author.toLowerCase(), place.provider, place.providerPlaceID, place.name, place.address,
    place.latitude, place.longitude, place.coordinateSystem,
    body, bodyLinks, location, ...(parentEvidence ? [parentEvidence] : []),
  ])).digest("hex");
  return parentEvidence ? threadsParentFingerprintPrefix + digest : digest;
}

/** Read author and caption from the canonical public embed for local venue review. */
export function readPublicPostForVenueReview(html: string, platform: Platform, sourceURL: string, author?: string) {
  const evidence = inspectPublicPostEmbed(html, platform, sourceURL, author);
  if (!evidence) return;
  return { author: evidence.author, body: evidence.body, bodyLinks: evidence.bodyLinks };
}
