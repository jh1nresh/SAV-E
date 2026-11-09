import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  communityRecommendationSignal,
  normalizeFollowRequest,
  normalizeVisibilityRequest,
  parseLens,
  publicRecommendationRow,
  socialSignalKindForLens,
} from "./socialContracts.js";

test("normalizeFollowRequest resolves referral defaults without trusting invalid lens", () => {
  const request = normalizeFollowRequest({
    handle: "@MemoGuide",
    referral_code: "SAVE-123",
    lens: "anything",
  });

  assert.deepEqual(request, {
    followingId: undefined,
    handle: "memoguide",
    referralCode: "SAVE-123",
    lens: "friends",
    source: "referral",
  });
});

test("normalizeVisibilityRequest never allows private places to emit social signals", () => {
  assert.deepEqual(
    normalizeVisibilityRequest({
      visibility: "private",
      allow_friend_signal: true,
      allow_trending_signal: true,
    }),
    {
      visibility: "private",
      allowFriendSignal: false,
      allowTrendingSignal: false,
    },
  );
});

test("normalizeVisibilityRequest preserves explicit opt-in for public guide places", () => {
  assert.deepEqual(
    normalizeVisibilityRequest({
      visibility: "public_guide",
      allow_friend_signal: true,
      allow_trending_signal: true,
    }),
    {
      visibility: "public_guide",
      allowFriendSignal: true,
      allowTrendingSignal: true,
    },
  );
});

test("social lens parsing keeps invalid values bounded", () => {
  assert.equal(parseLens("trending"), "trending");
  assert.equal(parseLens("forYou"), "forYou");
  assert.equal(parseLens("public"), "friends");
  assert.equal(socialSignalKindForLens("trending"), "trending");
  assert.equal(socialSignalKindForLens("friends"), "friend_saved");
});

test("community recommendation cards strip private notes and do not invent popularity", () => {
  assert.deepEqual(
    publicRecommendationRow({
      id: "place-1",
      note: "private travel plan",
      memory_meta: { v: 1, evidence: ["Creator handle: @private"] },
      source_image_url: "https://cdn.instagram.com/private-post.jpg",
      source_url: "https://instagram.com/p/abc?utm_source=private#caption",
    }),
    {
      id: "place-1",
      note: null,
      memory_meta: null,
      source_image_url: null,
      source_url: "https://instagram.com/p/abc",
    },
  );
  assert.deepEqual(communityRecommendationSignal("Mina", "user-2"), {
    kind: "community_recommendation",
    lens: "forYou",
    friendNames: [],
    friendCount: 0,
    saveCount: 0,
    trendingRank: null,
    categoryRank: null,
    sourceLabel: "Mina",
    referrerId: "user-2",
    referralCode: null,
  });
});

test("community feed only selects explicitly published places owned by other users", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  assert.match(serverSource, /async function communityRecommendationPlaces/);
  assert.match(serverSource, /pv\.visibility = 'public_guide'/);
  assert.match(serverSource, /pv\.allow_trending_signal = true/);
  assert.match(serverSource, /p\.user_id <> \$1/);
  assert.match(serverSource, /publicRecommendationRow\(value\)/);
});

test("places.memory_meta is a private jsonb field omitted from social cards", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
  const supabaseSchema = readFileSync(new URL("../../supabase/schema.sql", import.meta.url), "utf8");
  const migration = readFileSync(new URL("../sql/places-memory-meta.sql", import.meta.url), "utf8");
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  assert.match(schema, /memory_meta jsonb/);
  assert.match(schema, /places_memory_meta_object/);
  assert.match(supabaseSchema, /memory_meta jsonb/);
  assert.match(supabaseSchema, /places_memory_meta_object/);
  assert.match(migration, /alter table places add column if not exists memory_meta jsonb/);
  assert.match(serverSource, /"memory_meta"/);
  assert.match(serverSource, /jsonbFields = new Set\(\[[\s\S]*"memory_meta"/);
  const socialCard = serverSource.slice(serverSource.indexOf("function formatSocialPlace"));
  assert.match(socialCard, /pickFields\(row, \[/);
  assert.doesNotMatch(socialCard.slice(0, 600), /memory_meta|extracted_dishes|\bnote\b/);
});
