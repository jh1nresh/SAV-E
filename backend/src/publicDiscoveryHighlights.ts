import type { PublicDiscoveryPost } from "./publicDiscovery.js";

const day = 86_400_000;
const highlightLimit = 3;

export type PublicLikesObservation = { count: number; observedAt: string };

function publicationTime(post: PublicDiscoveryPost): number {
  const published = post.publishedAt ?? post.publishedOn;
  return published === undefined ? Number.NEGATIVE_INFINITY : Date.parse(published);
}

/** Reviewed inputs only. Likes compare recent posts from the same platform. */
export function addVenueHighlights(posts: PublicDiscoveryPost[], likes: Map<string, PublicLikesObservation>, now: Date) {
  const byVenue = new Map<string, PublicDiscoveryPost[]>();
  for (const post of posts) {
    const key = JSON.stringify([post.place.provider, post.place.providerPlaceID]);
    const group = byVenue.get(key);
    if (group) group.push(post);
    else byVenue.set(key, [post]);
  }
  const ranks = new Map<PublicDiscoveryPost, number>();
  const recent = now.getTime() - 90 * day;
  const currentMetrics = now.getTime() - 30 * day;
  for (const group of byVenue.values()) {
    // Stable ties keep the verified index order.
    const ordered = group.sort((a, b) => {
      const left = publicationTime(a), right = publicationTime(b);
      return left === right ? 0 : right - left;
    });
    for (const platform of ["instagram", "threads"] as const) {
      const comparable = ordered.map((post, index) => ({ post, index, observation: likes.get(post.id) }))
        .filter(({ post, observation }) => post.platform === platform && publicationTime(post) >= recent
          && observation !== undefined && Date.parse(observation.observedAt) >= currentMetrics);
      const ranked = [...comparable].sort((a, b) => b.observation!.count - a.observation!.count);
      for (const [index, entry] of comparable.entries()) {
        ordered[entry.index] = ranked[index]!.post;
      }
    }
    const selected = ordered.slice(0, highlightLimit);
    if (selected.length === highlightLimit && selected.every(post => post.platform === selected[0]!.platform)) {
      const other = ordered.find(post => post.platform !== selected[0]!.platform);
      if (other) selected[highlightLimit - 1] = other;
    }
    for (const [index, post] of selected.entries()) ranks.set(post, index + 1);
  }
  return posts.map(post => {
    const highlightRank = ranks.get(post);
    return highlightRank === undefined ? post : { ...post, highlightRank };
  });
}
