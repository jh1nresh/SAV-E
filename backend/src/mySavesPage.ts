import type { SavedPlace } from "./sendbluePlaceStore.js";
import type { VerifiedVisit } from "./sendblueReceiptStore.js";
import type { StoredReview } from "./sendblueReviewStore.js";

export type MySavesPayload = {
  places: SavedPlace[];
  visits: VerifiedVisit[];
  reviews: StoredReview[];
  counts: { places: number; visits: number; reviews: number };
};

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatDate(date: Date | undefined): string {
  if (!date) return "";
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(date);
}

function mapsUrl(place: SavedPlace): string {
  const query = [place.name, place.area].filter(Boolean).join(" ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

function safeHttpUrl(value: string | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function placeCard(place: SavedPlace): string {
  const category = place.category ? `<span>${escapeHtml(place.category)}</span>` : "";
  const area = place.area ? `<p>${escapeHtml(place.area)}</p>` : "";
  const sourceUrl = safeHttpUrl(place.sourceUrl);
  const source = sourceUrl ? `<a href="${escapeHtml(sourceUrl)}" rel="noreferrer">source</a>` : "";
  return `<article class="card">
    <div>
      <h2>${escapeHtml(place.name)}</h2>
      ${area}
      <div class="chips">${category}<span>saved ${escapeHtml(formatDate(place.createdAt))}</span></div>
    </div>
    <div class="actions">
      <a href="${escapeHtml(mapsUrl(place))}" rel="noreferrer">map</a>
      ${source}
    </div>
  </article>`;
}

function visitCard(visit: VerifiedVisit): string {
  const total = visit.total ? `<span>${escapeHtml(visit.total)}</span>` : "";
  const date = visit.visitDate || formatDate(visit.createdAt);
  return `<article class="card compact">
    <div>
      <h2>${escapeHtml(visit.merchant)}</h2>
      <div class="chips"><span>verified visit</span>${total}${date ? `<span>${escapeHtml(date)}</span>` : ""}</div>
    </div>
  </article>`;
}

function reviewCard(review: StoredReview): string {
  const rating = review.rating ? `<span>${escapeHtml(review.rating)}★</span>` : "";
  return `<article class="card compact">
    <div>
      <h2>${escapeHtml(review.merchant)}</h2>
      ${review.text ? `<p>${escapeHtml(review.text)}</p>` : ""}
      <div class="chips">${rating}<span>receipt-gated review</span></div>
    </div>
  </article>`;
}

function section(title: string, empty: string, body: string): string {
  return `<section>
    <h1>${escapeHtml(title)}</h1>
    ${body || `<p class="empty">${escapeHtml(empty)}</p>`}
  </section>`;
}

function countLabel(count: number, singular: string, plural: string): string {
  return `${count} ${count === 1 ? singular : plural}`;
}

export function renderMySavesPage(payload: MySavesPayload): string {
  const places = payload.places.map(placeCard).join("");
  const visits = payload.visits.map(visitCard).join("");
  const reviews = payload.reviews.map(reviewCard).join("");
  const metaTitle = `My SAV-E: ${countLabel(payload.counts.places, "place", "places")}, ${countLabel(payload.counts.visits, "visit", "visits")}, ${countLabel(payload.counts.reviews, "review", "reviews")}`;
  const metaDescription = "Open your private SAV-E cards, map links, verified visits, and receipt-gated reviews.";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="robots" content="noindex,nofollow" />
  <meta name="description" content="${escapeHtml(metaDescription)}" />
  <meta property="og:title" content="${escapeHtml(metaTitle)}" />
  <meta property="og:description" content="${escapeHtml(metaDescription)}" />
  <meta name="twitter:card" content="summary" />
  <title>My SAV-E</title>
  <style>
    :root { color-scheme: light dark; --bg:#f7f2e8; --ink:#35271d; --muted:#7b6b5f; --card:#fffaf1; --line:#d8c8b4; --green:#456f55; --gold:#a16f1e; }
    @media (prefers-color-scheme: dark) {
      :root { --bg:#15191d; --ink:#f8efe3; --muted:#c7b9aa; --card:#202327; --line:#615445; --green:#6fa17e; --gold:#c28a2c; }
    }
    * { box-sizing:border-box; }
    body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",Inter,sans-serif; background:var(--bg); color:var(--ink); }
    main { width:min(760px,100%); margin:0 auto; padding:28px 18px 44px; }
    header { padding:18px 0 22px; }
    .eyebrow { color:var(--green); font-weight:800; letter-spacing:0; text-transform:uppercase; font-size:13px; }
    h1 { font-size:24px; line-height:1.15; margin:0 0 12px; }
    header h1 { font-size:40px; margin:8px 0; }
    p { color:var(--muted); font-size:16px; line-height:1.45; margin:4px 0; }
    .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin-top:18px; }
    .stat { border:1px solid var(--line); border-radius:14px; padding:12px; background:rgba(255,255,255,.22); }
    .stat strong { display:block; font-size:24px; }
    section { margin-top:28px; }
    .card { display:flex; justify-content:space-between; gap:16px; padding:16px; border:1px solid var(--line); border-radius:18px; background:var(--card); margin:10px 0; box-shadow:0 8px 20px rgba(0,0,0,.04); }
    .card.compact { display:block; }
    h2 { font-size:20px; line-height:1.2; margin:0 0 6px; }
    .chips { display:flex; flex-wrap:wrap; gap:7px; margin-top:10px; }
    .chips span { border:1px solid var(--line); border-radius:999px; color:var(--ink); padding:5px 9px; font-weight:650; font-size:13px; }
    .actions { display:flex; flex-direction:column; gap:8px; align-items:flex-end; white-space:nowrap; }
    a { color:var(--gold); font-weight:800; text-decoration:none; }
    .empty { border:1px dashed var(--line); border-radius:18px; padding:18px; }
  </style>
</head>
<body>
  <main>
    <header>
      <div class="eyebrow">Private SAV-E link</div>
      <h1>My SAV-E</h1>
      <p>Your texted places, verified visits, and receipt-gated reviews. This link is private to your phone account.</p>
      <div class="stats">
        <div class="stat"><strong>${payload.counts.places}</strong><span>places</span></div>
        <div class="stat"><strong>${payload.counts.visits}</strong><span>visits</span></div>
        <div class="stat"><strong>${payload.counts.reviews}</strong><span>reviews</span></div>
      </div>
    </header>
    ${section("Saved Places", "No saved places yet. Text SAV-E a place link to start.", places)}
    ${section("Verified Visits", "No receipt-backed visits yet.", visits)}
    ${section("Reviews", "No receipt-gated reviews yet.", reviews)}
  </main>
</body>
</html>`;
}
