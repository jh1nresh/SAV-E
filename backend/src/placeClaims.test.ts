import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMaatPlaceAnalysis,
  buildPublicPlaceCard,
  buildTrustSummary,
  experienceReviewMutationScope,
  formatPlaceClaim,
  normalizeExperienceReviewPatch,
  normalizePlaceClaimCreate,
  normalizeRecommendationRequest,
  normalizeUsageReceiptCreate,
  recommendPlacesByClaims,
} from "./placeClaims.js";
import {
  enrichMaatPlaceAnalysisWithPublicWeb,
  enrichMaatPlaceAnalysisWithStructuredSources,
  mergePublicWebDetails,
  publicWebConfigFromEnv,
} from "./maatPublicWebAnalysis.js";

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

test("experience reviews are private structured self reports with note-free summaries", () => {
  const claim = normalizePlaceClaimCreate({
    claimType: "experience_review",
    note: "Private companion detail that must not reach ranking copy.",
    proofLevel: "visited_self_reported",
    visibility: "private",
    observedAt: "2026-07-13T12:00:00Z",
    context: {
      occasion: "date",
      time_of_day: "evening",
      price_band: "$$",
    },
    ratings: {
      would_return: "yes",
      strengths: ["vibe", "taste", "taste"],
      misses: ["wait"],
    },
    agentUsableSummary: "Client text must be ignored.",
  }, "place_1", "user_1");

  assert.deepEqual(claim, {
    user_id: "user_1",
    place_id: "place_1",
    claim_type: "experience_review",
    claim: "Private companion detail that must not reach ranking copy.",
    agent_usable_summary: "Would return: yes; occasion: date; time: evening; price: $$; strengths: taste, vibe; misses: wait",
    author_type: "self",
    author_public_handle: undefined,
    author_relationship: "self",
    proof_level: "visited_self_reported",
    evidence_refs: [],
    visibility: "private",
    confidence: 1,
    context: { occasion: "date", time_of_day: "evening", price_band: "$$" },
    ratings: { would_return: "yes", strengths: ["taste", "vibe"], misses: ["wait"] },
    observed_at: "2026-07-13T12:00:00Z",
    expires_or_stale_after: undefined,
    idempotency_key: claim.idempotency_key,
  });
  assert.match(String(claim.idempotency_key), /^experience:[a-f0-9]{64}$/);
  assert.doesNotMatch(String(claim.agent_usable_summary), /companion|Client text/);

  const analysis = buildMaatPlaceAnalysis(
    { id: "place_1", name: "Private Date Place" },
    [{ id: "claim_1", ...claim }],
    { includePrivateEvidence: true },
  );
  assert.doesNotMatch(JSON.stringify(analysis), /Private companion detail/);
});

test("experience reviews reject incomplete, public, and out-of-vocabulary input", () => {
  const valid = {
    claim_type: "experience_review",
    observed_at: "2026-07-13T12:00:00Z",
    context: { occasion: "general" },
    ratings: { would_return: "unsure" },
  };

  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, observed_at: undefined }, "place_1", "user_1"),
    /observed_at is required/,
  );
  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, visibility: "public" }, "place_1", "user_1"),
    /visibility must be private/,
  );
  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, proof_level: "receipt_backed" }, "place_1", "user_1"),
    /proof_level must be visited_self_reported/,
  );
  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, context: { occasion: "business" } }, "place_1", "user_1"),
    /context.occasion/,
  );
  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, ratings: { would_return: "maybe" } }, "place_1", "user_1"),
    /ratings.would_return/,
  );
  assert.throws(
    () => normalizePlaceClaimCreate({ ...valid, ratings: { would_return: "yes", strengths: ["parking"] } }, "place_1", "user_1"),
    /ratings.strengths/,
  );
});

test("experience create dedupes retries but preserves separate observed visits", () => {
  const first = normalizePlaceClaimCreate({
    claim_type: "experience_review",
    observed_at: "2026-07-13T12:00:00Z",
    context: { occasion: "date" },
    ratings: { would_return: "yes", strengths: ["vibe", "taste"] },
  }, "place_1", "user_1");
  const retry = normalizePlaceClaimCreate({
    claim_type: "experience_review",
    observed_at: "2026-07-13T12:00:00Z",
    context: { occasion: "date" },
    ratings: { would_return: "yes", strengths: ["taste", "vibe"] },
  }, "place_1", "user_1");
  const laterVisit = normalizePlaceClaimCreate({
    claim_type: "experience_review",
    observed_at: "2026-07-14T12:00:00Z",
    context: { occasion: "date" },
    ratings: { would_return: "yes", strengths: ["taste", "vibe"] },
  }, "place_1", "user_1");

  assert.equal(first.idempotency_key, retry.idempotency_key);
  assert.notEqual(first.idempotency_key, laterVisit.idempotency_key);
});

test("experience patches preserve ownership invariants and can clear a private note", () => {
  const existing = normalizePlaceClaimCreate({
    claim_type: "experience_review",
    note: "Original private note",
    observed_at: "2026-07-13T12:00:00Z",
    context: { occasion: "date" },
    ratings: { would_return: "yes", strengths: ["vibe"] },
  }, "place_1", "user_1");

  const patch = normalizeExperienceReviewPatch({
    note: "",
    ratings: { would_return: "no", misses: ["wait", "service"] },
    expires_or_stale_after: null,
  }, existing);

  assert.deepEqual(patch, {
    claim: "",
    agent_usable_summary: "Would return: no; occasion: date; misses: service, wait",
    context: { occasion: "date" },
    ratings: { would_return: "no", strengths: [], misses: ["service", "wait"] },
    observed_at: "2026-07-13T12:00:00Z",
    expires_or_stale_after: null,
  });
  assert.throws(
    () => normalizeExperienceReviewPatch({ visibility: "public" }, existing),
    /visibility must be private/,
  );
  assert.throws(
    () => normalizeExperienceReviewPatch({ visibility: "private" }, existing),
    /No writable experience fields/,
  );
});

test("experience mutation scope fails closed on place, claim, owner, type, and visibility", () => {
  assert.deepEqual(experienceReviewMutationScope("place_1", "claim_1", "user_1"), {
    clause: "id = $1 and place_id = $2 and user_id = $3 and claim_type = 'experience_review' and author_type = 'self' and author_relationship = 'self' and visibility = 'private'",
    values: ["claim_1", "place_1", "user_1"],
  });
  assert.equal(
    experienceReviewMutationScope("place_1", "claim_1", "user_1", 6).clause,
    "id = $7 and place_id = $8 and user_id = $9 and claim_type = 'experience_review' and author_type = 'self' and author_relationship = 'self' and visibility = 'private'",
  );
});

test("deleting an experience removes its next-request ranking influence", () => {
  const request = normalizeRecommendationRequest({ intent: "date", limit: 3 });
  const experience = {
    id: "claim_1",
    place_id: "place_1",
    place_name: "Date Place",
    claim_type: "experience_review",
    claim: "",
    agent_usable_summary: "Would return: yes; occasion: date",
    proof_level: "visited_self_reported",
    confidence: 1,
    context: { occasion: "date" },
    ratings: { would_return: "yes" },
  };

  assert.equal((recommendPlacesByClaims([experience], request).results as unknown[]).length, 1);
  assert.deepEqual(recommendPlacesByClaims([], request).results, []);
});

test("experience reviews without positive return evidence are not ranked as likes", () => {
  const request = normalizeRecommendationRequest({ intent: "date", limit: 3 });
  const rows = ["no", "unsure"].map((wouldReturn, index) => ({
    id: `claim_${index}`,
    place_id: `place_${index}`,
    place_name: `Place ${index}`,
    claim_type: "experience_review",
    claim: "",
    agent_usable_summary: `Would return: ${wouldReturn}; occasion: date`,
    proof_level: "visited_self_reported",
    confidence: 1,
    context: { occasion: "date" },
    ratings: { would_return: wouldReturn },
  }));

  const output = recommendPlacesByClaims(rows, request);
  assert.deepEqual(output.results, []);
  assert.deepEqual((output.retrieval_receipt as Record<string, unknown>).skipped, [
    "2 experiences without positive return evidence",
  ]);
});

test("private experience notes do not influence recommendation ranking or warnings", () => {
  const request = normalizeRecommendationRequest({ intent: "secret spicy", limit: 2 });
  const output = recommendPlacesByClaims([
    {
      id: "claim_neutral",
      place_id: "place_neutral",
      place_name: "Neutral Place",
      claim_type: "saved_place",
      claim: "Saved place",
      agent_usable_summary: "Saved place",
      proof_level: "visited_self_reported",
      confidence: 1,
    },
    {
      id: "claim_private",
      place_id: "place_private",
      place_name: "Private Note Place",
      claim_type: "experience_review",
      claim: "secret spicy long wait",
      agent_usable_summary: "Would return: yes; occasion: general",
      proof_level: "visited_self_reported",
      confidence: 1,
      context: { occasion: "general" },
      ratings: { would_return: "yes" },
    },
  ], request);

  const results = output.results as Array<Record<string, unknown>>;
  assert.equal(results[0].place_id, "place_neutral");
  assert.deepEqual(results[1].warnings, []);
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

test("buildPublicPlaceCard projects public claims without private evidence refs", () => {
  const card = buildPublicPlaceCard(
    {
      id: "place_1",
      name: "Spicy Date Noodles",
      address: "100 Taipei Rd",
      category: "food",
      google_place_id: "google_123",
      owner_handle: "memo",
    },
    [
      {
        id: "claim_123",
        place_id: "place_1",
        claim_type: "good_for_date",
        claim: "Good casual date dinner.",
        agent_usable_summary: "date dinner",
        proof_level: "visited_self_reported",
        confidence: 0.82,
        visibility: "public",
        evidence_refs: ["source_123"],
        usage_count: 3,
        accepted_count: 2,
      },
      {
        id: "claim_private",
        place_id: "place_1",
        claim_type: "private_note",
        claim: "Private note.",
        agent_usable_summary: "private",
        proof_level: "visited_self_reported",
        confidence: 0.9,
        visibility: "private",
        evidence_refs: ["source_private"],
      },
    ],
  );

  const claims = card.public_claims as Array<Record<string, unknown>>;
  assert.equal(card.card_id, "place_1");
  assert.equal(claims.length, 1);
  assert.equal(claims[0].claim_id, "claim_123");
  assert.equal("evidence_refs" in claims[0], false);
  assert.deepEqual(claims[0].evidence_summary, ["saved source evidence"]);

  const trustSummary = card.trust_summary as Record<string, unknown>;
  assert.deepEqual(trustSummary.reputation, {
    usage_count: 3,
    accepted_count: 2,
    score: 0.67,
  });
});

test("normalizeUsageReceiptCreate bounds action and outcome", () => {
  assert.deepEqual(
    normalizeUsageReceiptCreate({
      claimId: "claim_123",
      consumerAgentId: "agent_456",
      action: "recommended_to_user",
      outcome: "accepted",
    }),
    {
      claim_id: "claim_123",
      consumer_agent_id: "agent_456",
      action: "recommended_to_user",
      outcome: "accepted",
    },
  );

  assert.deepEqual(
    normalizeUsageReceiptCreate({
      claim_id: "claim_123",
      action: "post_to_social",
      outcome: "paid",
    }),
    {
      claim_id: "claim_123",
      consumer_agent_id: "unknown_agent",
      action: "cited",
      outcome: "unknown",
    },
  );
});

test("buildMaatPlaceAnalysis scopes analysis to selected place evidence and excludes private claims by default", () => {
  const output = buildMaatPlaceAnalysis(
    {
      id: "place_1",
      name: "Spicy Date Noodles",
      address: "100 Taipei Rd",
      note: "Saved for casual dates; try the spicy noodles $16. Parking garage nearby.",
      source_url: "https://www.instagram.com/reel/example/",
      google_rating: 4.6,
      extracted_dishes: ["spicy noodles"],
      price_range: "$$",
    },
    [
      {
        id: "claim_public",
        claim_type: "good_for_date",
        claim: "Great casual date dinner with spicy noodles. Expect a line at peak dinner.",
        agent_usable_summary: "date dinner spicy noodles; average cost $25 per person; reservation recommended",
        proof_level: "visited_self_reported",
        confidence: 0.82,
        visibility: "public",
        evidence_refs: ["source_123"],
      },
      {
        id: "claim_private",
        claim_type: "private_note",
        claim: "Private exact companion note.",
        agent_usable_summary: "private companion detail",
        proof_level: "receipt_backed",
        confidence: 0.95,
        visibility: "private",
        evidence_refs: ["receipt_private"],
      },
    ],
  );

  assert.equal(output.capability, "maat_place_analysis_v0");
  assert.equal(output.status, "ready");
  assert.equal(output.verdict, "usable_with_caveats");
  assert.deepEqual(output.cited_claim_ids, ["claim_public"]);
  assert.match(String(output.summary), /date dinner spicy noodles/);
  assert.deepEqual(output.warnings, ["long_wait_peak_hours", "private_claims_excluded"]);
  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.price_range, "$$");
  assert.deepEqual(details.avg_cost, "$25");
  assert.deepEqual(details.parking, "Saved for casual dates; try the spicy noodles $16. Parking garage nearby.");
  assert.deepEqual(details.reservation_tips, "date dinner spicy noodles; average cost $25 per person; reservation recommended");
  assert.deepEqual(details.best_for, ["date night"]);
  assert.deepEqual(details.evidence_gaps, []);
  assert.deepEqual(details.platform_scores, [{
    platform: "Google",
    score: 4.6,
    source: "google_place_metadata",
  }]);
  assert.deepEqual(details.must_try, [{
    name: "spicy noodles",
    price: "$16",
    evidence: "saved place dish",
  }]);
  assert.deepEqual(details.critical_reviews, [{
    issue: "Great casual date dinner with spicy noodles. Expect a line at peak dinner.",
    source: "SAV-E evidence",
    frequency: "mentioned",
  }]);
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.input_scope, "selected_place_only");
  assert.equal(receipt.whole_map_used, false);
  assert.equal(receipt.raw_private_evidence_included, false);
  assert.equal(receipt.model_used, false);
});

test("buildMaatPlaceAnalysis refuses to invent analysis for thin source-only places", () => {
  const output = buildMaatPlaceAnalysis({ id: "place_thin", name: "Mystery Reel Spot" }, []);

  assert.equal(output.status, "not_enough_evidence");
  assert.equal(output.verdict, "insufficient_evidence");
  assert.deepEqual(output.cited_claim_ids, []);
  assert.deepEqual(output.next_actions, ["add_note", "confirm_place", "attach_source_or_receipt"]);
  assert.deepEqual(output.warnings, ["thin_place_evidence", "no_verified_claims_cited"]);
});

test("mergePublicWebDetails fills Ma'at restaurant detail gaps without replacing local scores", () => {
  const base = buildMaatPlaceAnalysis(
    {
      id: "place_1",
      name: "Spicy Date Noodles",
      google_rating: 4.6,
      price_range: "$$",
      extracted_dishes: ["紅燒牛肉麵"],
    },
    [],
  );
  const output = mergePublicWebDetails(base, {
    platform_scores: [{ platform: "Google", score: 4.9, source: "public web" }, { platform: "Yelp", score: 4.2, source: "Yelp" }],
    must_try: [{ name: "紅燒牛肉麵", description: "湯頭濃郁", price: "$18", evidence: "public web" }],
    parking: "附近有收費停車場。",
    avg_cost: "$25-35/人",
    critical_reviews: [{ issue: "尖峰時段等候較久", source: "Yelp", frequency: "常見" }],
  }, [{ title: "Yelp", url: "https://example.com/restaurant" }], "gemini-test");

  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.platform_scores, [
    { platform: "Google", score: 4.6, source: "google_place_metadata" },
    { platform: "Yelp", score: 4.2, source: "Yelp" },
  ]);
  assert.deepEqual(details.must_try, [{ name: "紅燒牛肉麵", description: "湯頭濃郁", price: "$18", evidence: "saved place dish" }]);
  assert.equal(details.avg_cost, "$25-35/人");
  assert.equal(details.parking, "附近有收費停車場。");
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.input_scope, "selected_place_plus_public_web");
  assert.equal(receipt.public_web_used, true);
  assert.equal(receipt.model_used, true);
  assert.equal(receipt.public_web_status, "used");
  assert.equal(receipt.model_name, "gemini-test");
  assert.deepEqual(output.public_web_sources, [{ title: "Yelp", url: "https://example.com/restaurant" }]);
});

test("enrichMaatPlaceAnalysisWithPublicWeb is env-gated and keeps deterministic output when disabled", async () => {
  const base = buildMaatPlaceAnalysis({ id: "place_1", name: "Spicy Date Noodles" }, []);
  const output = await enrichMaatPlaceAnalysisWithPublicWeb({
    place: { id: "place_1", name: "Spicy Date Noodles" },
    claims: [],
    analysis: base,
  }, { enabled: false, model: "gemini-test" });

  assert.equal(output.restaurant_details, base.restaurant_details);
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.public_web_used, false);
  assert.equal(receipt.model_used, false);
  assert.equal(receipt.public_web_status, "disabled");
});

test("publicWebConfigFromEnv enables requested Ma'at web analysis unless explicitly disabled", () => {
  const config = publicWebConfigFromEnv({ GEMINI_API_KEY: "test-key", GOOGLE_PLACES_API_KEY: "places-key", YELP_API_KEY: "yelp-key" });
  assert.equal(config.enabled, true);
  assert.equal(config.model, "gemini-2.5-flash");
  assert.equal(config.googlePlacesApiKey, "places-key");
  assert.equal(config.yelpApiKey, "yelp-key");
  assert.equal(publicWebConfigFromEnv({ GEMINI_API_KEY: "test-key", SAVE_ENABLE_MAAT_PUBLIC_WEB: "false" }).enabled, false);
});

test("enrichMaatPlaceAnalysisWithStructuredSources fills details from Google Places", async () => {
  const googleUrls: string[] = [];
  const base = buildMaatPlaceAnalysis({ id: "place_1", name: "一號地鍋雞", address: "Irvine, CA" }, []);
  const output = await enrichMaatPlaceAnalysisWithStructuredSources({
    place: { id: "place_1", name: "一號地鍋雞", address: "Irvine, CA", latitude: 33.6846, longitude: -117.8265 },
    claims: [],
    analysis: base,
  }, {
    enabled: true,
    model: "gemini-test",
    googlePlacesApiKey: "places-key",
    fetcher: async (url, init) => {
      googleUrls.push(url);
      if (url === "https://places.googleapis.com/v1/places:searchText") {
        assert.match(init.body ?? "", /一號地鍋雞/);
        assert.match(init.body ?? "", /locationBias/);
        return {
          ok: true,
          status: 200,
          json: async () => ({
            places: [{
              id: "google_1",
              displayName: { text: "一號地鍋雞" },
              rating: 4.3,
            }],
          }),
        };
      }
      assert.equal(url, "https://places.googleapis.com/v1/places/google_1");
      return {
        ok: true,
        status: 200,
        json: async () => ({
            id: "google_1",
            displayName: { text: "一號地鍋雞" },
            formattedAddress: "1 Test Rd, Irvine, CA",
            googleMapsUri: "https://maps.google.com/?cid=1",
            rating: 4.3,
            userRatingCount: 218,
            priceLevel: "PRICE_LEVEL_MODERATE",
            primaryType: "chinese_restaurant",
            parkingOptions: { freeParkingLot: true, paidStreetParking: true },
            reservable: true,
            dineIn: true,
            takeout: true,
            servesDinner: true,
            editorialSummary: { text: "熱鬧的地鍋雞餐廳。" },
        }),
      };
    },
  });

  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.platform_scores, [{ platform: "Google", score: 4.3, source: "google_places_api" }]);
  assert.equal(details.price_range, "$$");
  assert.equal(details.cuisine, "chinese restaurant");
  assert.equal(details.ambiance, "熱鬧的地鍋雞餐廳。");
  assert.equal(details.reservation_tips, "Google Places 顯示可訂位；尖峰時段建議先預約。");
  assert.equal(details.parking, "Google Places 顯示：免費停車場、路邊付費停車。");
  assert.deepEqual(details.best_for, ["內用", "外帶", "晚餐"]);
  assert.deepEqual(details.evidence_gaps, ["recommended_dishes"]);
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.structured_source_used, true);
  assert.equal(receipt.google_places_status, "used");
  assert.equal(receipt.yelp_status, "missing_api_key");
  assert.deepEqual(output.structured_source_sources, [{ title: "Google Places", url: "https://maps.google.com/?cid=1" }]);
  assert.deepEqual(googleUrls, [
    "https://places.googleapis.com/v1/places:searchText",
    "https://places.googleapis.com/v1/places/google_1",
  ]);
});

test("enrichMaatPlaceAnalysisWithPublicWeb keeps structured details when Gemini key is missing", async () => {
  const base = buildMaatPlaceAnalysis({ id: "place_1", name: "Utopia Euro Caffe", address: "Los Angeles, CA" }, []);
  const output = await enrichMaatPlaceAnalysisWithPublicWeb({
    place: { id: "place_1", name: "Utopia Euro Caffe", address: "Los Angeles, CA" },
    claims: [],
    analysis: base,
  }, {
    enabled: true,
    model: "gemini-test",
    googlePlacesApiKey: "places-key",
    fetcher: async (url) => {
      if (url === "https://places.googleapis.com/v1/places:searchText") {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            places: [{ id: "google_1" }],
          }),
        };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({
          id: "google_1",
          googleMapsUri: "https://maps.google.com/?cid=2",
          rating: 4.6,
          priceLevel: "PRICE_LEVEL_MODERATE",
          reservable: true,
        }),
      };
    },
  });

  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.platform_scores, [{ platform: "Google", score: 4.6, source: "google_places_api" }]);
  assert.equal(details.price_range, "$$");
  assert.equal(details.reservation_tips, "Google Places 顯示可訂位；尖峰時段建議先預約。");
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.structured_source_used, true);
  assert.equal(receipt.public_web_used, false);
  assert.equal(receipt.model_used, false);
  assert.equal(receipt.public_web_status, "missing_api_key");
});

test("enrichMaatPlaceAnalysisWithStructuredSources can add Yelp score and review excerpts", async () => {
  const base = buildMaatPlaceAnalysis({ id: "place_1", name: "Corner Bakery Cafe", address: "Irvine, CA" }, []);
  const output = await enrichMaatPlaceAnalysisWithStructuredSources({
    place: { id: "place_1", name: "Corner Bakery Cafe", address: "Irvine, CA" },
    claims: [],
    analysis: base,
  }, {
    enabled: true,
    model: "gemini-test",
    yelpApiKey: "yelp-key",
    fetcher: async (url) => {
      if (url.startsWith("https://api.yelp.com/v3/businesses/search")) {
        return {
          ok: true,
          status: 200,
          json: async () => ({ businesses: [{ id: "corner-bakery", url: "https://www.yelp.com/biz/corner-bakery" }] }),
        };
      }
      if (url.endsWith("/corner-bakery")) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            id: "corner-bakery",
            url: "https://www.yelp.com/biz/corner-bakery",
            rating: 3.8,
            price: "$$",
            categories: [{ title: "Cafes" }, { title: "Breakfast & Brunch" }],
          }),
        };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({
          reviews: [{ rating: 2, text: "Service can be slow during lunch." }],
        }),
      };
    },
  });

  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.platform_scores, [{ platform: "Yelp", score: 3.8, source: "yelp_api" }]);
  assert.equal(details.price_range, "$$");
  assert.equal(details.cuisine, "Cafes / Breakfast & Brunch");
  assert.deepEqual(details.critical_reviews, [{ issue: "Service can be slow during lunch.", source: "Yelp", frequency: "review excerpt" }]);
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.google_places_status, "missing_api_key");
  assert.equal(receipt.yelp_status, "used");
});

test("enrichMaatPlaceAnalysisWithPublicWeb sends public claim summaries only", async () => {
  let requestBody = "";
  const base = buildMaatPlaceAnalysis({ id: "place_1", name: "A Cheng Goose" }, []);
  const output = await enrichMaatPlaceAnalysisWithPublicWeb({
    place: {
      id: "place_1",
      name: "A Cheng Goose",
      address: "No. 105, Jilin Rd",
      google_rating: 4.5,
    },
    claims: [
      {
        id: "public_claim",
        claim: "public summary",
        agent_usable_summary: "燒鵝是招牌",
        visibility: "public",
        proof_level: "source_backed",
      },
      {
        id: "private_claim",
        claim: "private companion note",
        agent_usable_summary: "do not leak private note",
        visibility: "private",
        proof_level: "receipt_backed",
      },
    ],
    analysis: base,
  }, {
    enabled: true,
    apiKey: "test-key",
    model: "gemini-test",
    fetcher: async (_url, init) => {
      requestBody = init.body ?? "";
      return {
        ok: true,
        status: 200,
        json: async () => ({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify({
                  must_try: [{ name: "燒鵝飯", description: "外皮酥脆", evidence: "public web" }],
                  parking: "附近路邊停車有限。",
                }),
              }],
            },
            groundingMetadata: {
              groundingChunks: [{ web: { title: "Review", uri: "https://example.com/review" } }],
            },
          }],
        }),
      };
    },
  });

  assert.match(requestBody, /燒鵝是招牌/);
  assert.doesNotMatch(requestBody, /do not leak private note/);
  const details = output.restaurant_details as Record<string, unknown>;
  assert.deepEqual(details.must_try, [{ name: "燒鵝飯", description: "外皮酥脆", price: undefined, evidence: "public web" }]);
  assert.equal(details.parking, "附近路邊停車有限。");
  const receipt = output.analysis_receipt as Record<string, unknown>;
  assert.equal(receipt.public_web_used, true);
  assert.equal(receipt.model_used, true);
});

test("recommendPlacesByClaims uses usage receipts as a small reputation boost", () => {
  const request = normalizeRecommendationRequest({
    intent: "date",
    constraints: ["date"],
    proofLevelMin: "user_confirmed_place",
    limit: 1,
  });

  const output = recommendPlacesByClaims([
    {
      id: "claim_low_reputation",
      place_id: "place_low",
      place_name: "Quiet Date Spot",
      claim_type: "good_for_date",
      claim: "date",
      agent_usable_summary: "date",
      proof_level: "user_confirmed_place",
      confidence: 0.8,
      usage_count: 0,
      accepted_count: 0,
    },
    {
      id: "claim_reputation",
      place_id: "place_high",
      place_name: "Trusted Date Spot",
      claim_type: "good_for_date",
      claim: "date",
      agent_usable_summary: "date",
      proof_level: "user_confirmed_place",
      confidence: 0.8,
      usage_count: 20,
      accepted_count: 18,
    },
  ], request);

  const results = output.results as Array<Record<string, unknown>>;
  assert.equal(results[0].place_id, "place_high");
});
