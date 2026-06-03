import assert from "node:assert/strict";
import test from "node:test";
import {
  buildTrustSummary,
  formatPlaceClaim,
  normalizePlaceClaimCreate,
  normalizeRecommendationRequest,
  recommendPlacesByClaims,
} from "./placeClaims.js";

test("normalizePlaceClaimCreate keeps raw evidence refs private by default", () => {
  const claim = normalizePlaceClaimCreate({
    claimType: "good_for_date",
    claim: "Good for casual date night, but avoid Friday peak hours.",
    agentUsableSummary: "適合 casual date；尖峰可能久等。",
    proofLevel: "visited_self_reported",
    evidenceRefs: ["source_123", "photo_456"],
    visibility: "public",
    confidence: 0.82,
    context: { occasionTags: ["date"], constraints: ["avoid_peak_wait"] },
    ratings: { dateFit: 5 },
    observedAt: "2026-05-20T00:00:00Z",
  }, "save_place_456", "user_123");

  assert.equal(claim.place_id, "save_place_456");
  assert.equal(claim.user_id, "user_123");
  assert.equal(claim.claim_type, "good_for_date");
  assert.equal(claim.proof_level, "visited_self_reported");
  assert.deepEqual(claim.evidence_refs, ["source_123", "photo_456"]);

  const publicShape = formatPlaceClaim({
    id: "claim_123",
    created_at: "2026-06-03T00:00:00Z",
    ...claim,
  });
  assert.deepEqual(publicShape.evidence_summary, ["saved source evidence", "photo evidence"]);
  assert.equal("evidence_refs" in publicShape, false);

  const privateShape = formatPlaceClaim({
    id: "claim_123",
    created_at: "2026-06-03T00:00:00Z",
    ...claim,
  }, true);
  assert.deepEqual(privateShape.evidence_refs, ["source_123", "photo_456"]);
});

test("buildTrustSummary weights proof level and exposes warnings without raw evidence", () => {
  const summary = buildTrustSummary("save_place_456", [
    {
      id: "claim_123",
      claim_type: "good_for_date",
      claim: "Good for casual date night, but avoid Friday peak hours.",
      agent_usable_summary: "適合 casual date；尖峰可能久等。",
      proof_level: "visited_self_reported",
      confidence: 0.82,
      observed_at: "2026-05-20T00:00:00Z",
      evidence_refs: ["source_123", "photo_456"],
    },
    {
      id: "claim_124",
      claim_type: "friend_verified",
      claim: "Friend went and liked it.",
      agent_usable_summary: "friend tried it",
      proof_level: "friend_verified",
      confidence: 0.74,
      observed_at: "2026-05-22T00:00:00Z",
      evidence_refs: ["source_789"],
    },
  ]);

  const trustSummary = summary.trust_summary as Record<string, unknown>;
  assert.equal(trustSummary.verified_claim_count, 2);
  assert.equal(trustSummary.friend_verified_count, 1);
  assert.equal(trustSummary.receipt_backed_count, 0);
  assert.equal(trustSummary.strongest_proof_level, "friend_verified");
  assert.deepEqual(trustSummary.warnings, ["long_wait_peak_hours"]);
  assert.equal(summary.agent_answer, "Trust level friend_verified, confidence 0.77. Warnings: long_wait_peak_hours.");
});

test("recommendPlacesByClaims filters low proof claims and returns a bounded retrieval receipt", () => {
  const request = normalizeRecommendationRequest({
    intent: "台北 casual date dinner spicy",
    constraints: ["date", "spicy"],
    proofLevelMin: "user_confirmed_place",
    limit: 2,
  });

  const output = recommendPlacesByClaims([
    {
      id: "claim_low",
      place_id: "place_low",
      place_name: "Unconfirmed Reel Place",
      claim_type: "good_for_date",
      claim: "Looks romantic from a reel.",
      agent_usable_summary: "unconfirmed",
      proof_level: "source_backed",
      confidence: 0.9,
      context: { occasionTags: ["date"] },
    },
    {
      id: "claim_123",
      place_id: "place_1",
      place_name: "Spicy Date Noodles",
      claim_type: "good_for_date",
      claim: "Good casual date dinner and spicy noodles.",
      agent_usable_summary: "date dinner spicy",
      proof_level: "visited_self_reported",
      confidence: 0.82,
      context: { occasionTags: ["date"], tasteTags: ["spicy"] },
    },
    {
      id: "claim_124",
      place_id: "place_2",
      place_name: "Quiet Cafe",
      claim_type: "work_friendly",
      claim: "Good cafe to work.",
      agent_usable_summary: "work cafe",
      proof_level: "user_confirmed_place",
      confidence: 0.7,
      context: { occasionTags: ["work"] },
    },
  ], request);

  const results = output.results as Array<Record<string, unknown>>;
  assert.equal(results.length, 2);
  assert.equal(results[0].place_id, "place_1");
  assert.equal(results[0].proof_level, "visited_self_reported");
  assert.deepEqual(results[0].supporting_claims, ["claim_123"]);

  const receipt = output.retrieval_receipt as Record<string, unknown>;
  assert.deepEqual(receipt.used, ["2 owner-scoped places", "2 verified claims"]);
  assert.deepEqual(receipt.skipped, ["1 claims below proof threshold"]);
  assert.equal(receipt.public_web_used, false);
});
