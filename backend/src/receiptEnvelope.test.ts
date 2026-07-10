import assert from "node:assert/strict";
import test from "node:test";
import {
  buildRecommendationAnalysisReceiptDraft,
  envelopeForRecommendationAnalysisReceipt,
  normalizeRecommendationAnalysisReceiptPayload,
  RecommendationAnalysisReceiptPayloadError,
  sha256CanonicalJson,
  sha256ImmutableWorkflowReceipt,
} from "./receiptEnvelope.js";

test("recommendation analysis receipt stores full payload and projects AgentShack-safe envelope", () => {
  const output = {
    results: [
      {
        place_id: "place_private_1",
        name: "Utopia Euro Caffe",
        why: "Private saved evidence matched coffee.",
        supporting_claims: ["claim_private_1"],
      },
    ],
    retrieval_receipt: {
      used: ["1 owner-scoped places", "1 verified claims"],
      skipped: [],
      public_web_used: false,
    },
  };
  const receipt = buildRecommendationAnalysisReceiptDraft({
    userId: "user_123",
    agentId: "save-ios-test",
    request: {
      intent: "推薦我附近咖啡廳 private birthday note",
      constraints: ["nearby", "coffee", "saved"],
      proof_level_min: "user_confirmed_place",
    },
    output,
    createdAt: "2026-06-06T12:00:00.000Z",
  });

  assert.equal(receipt.product, "save");
  assert.equal(receipt.receipt_type, "recommendation_analysis");
  assert.equal(receipt.capability, "place_claim_recommendation");
  assert.equal(receipt.private_payload.output, output);
  assert.equal(receipt.public_summary.result_count, 1);
  assert.deepEqual(receipt.preference_signals, [
    "coffee",
    "saved_memory",
    "nearby",
    "proof_level:user_confirmed_place",
  ]);

  const envelope = envelopeForRecommendationAnalysisReceipt(receipt);
  const envelopeJson = JSON.stringify(envelope);
  assert.equal(envelope.receipt_type, "recommendation_analysis");
  assert.equal(envelope.private_payload_ref, receipt.private_payload_ref);
  assert.equal("private_payload" in envelope, false);
  assert.equal(envelopeJson.includes("Utopia Euro Caffe"), false);
  assert.equal(envelopeJson.includes("private birthday note"), false);
  assert.equal(envelopeJson.includes("claim_private_1"), false);
});

test("recommendation analysis hashes use canonical JSON key ordering", () => {
  assert.equal(
    sha256CanonicalJson({ b: 2, a: { d: 4, c: 3 } }),
    sha256CanonicalJson({ a: { c: 3, d: 4 }, b: 2 }),
  );
});

test("workflow receipt hash excludes mutable lifecycle projection", () => {
  const receipt = {
    run_id: "run-1",
    output_hash: "output-1",
    settlement: "manual_review",
    quality_delta: 0.5,
    reputation_delta: 1,
    is_current: true,
    anchor_status: "offchain",
    privacy_validated: true,
    private_url: null,
  };
  const hash = sha256ImmutableWorkflowReceipt(receipt);

  assert.equal(sha256ImmutableWorkflowReceipt({
    ...receipt,
    is_current: false,
    anchor_status: "batch_anchored",
    privacy_validated: false,
    private_url: "save://private/receipt-1",
  }), hash);
  assert.equal(sha256ImmutableWorkflowReceipt({
    ...receipt,
    id: "database-generated-id",
    created_at: "2026-07-10T00:00:00.000Z",
    quality_delta: "0.5",
    reputation_delta: "1",
  }), hash);
  assert.notEqual(sha256ImmutableWorkflowReceipt({ ...receipt, output_hash: "output-2" }), hash);
});

test("client recommendation output projects mixed saved and public counts safely", () => {
  const receipt = buildRecommendationAnalysisReceiptDraft({
    userId: "user_123",
    agentId: "save-ios",
    request: {
      intent: "推薦我附近咖啡 private birthday note",
      constraints: ["nearby"],
      proof_level_min: "user_confirmed_place",
      shown_at: "2026-06-06T11:59:00Z",
    },
    output: {
      answer_source: "deterministic",
      answer_message: "I will start from your saved coffee memory.",
      public_fallback_used: true,
      preference_signals: [
        "category:cafe",
        "source:saved_memory",
        "Bright Coffee Bar",
        "bright_coffee_bar",
        "private_note:anniversary",
        "source:saved_memory:anniversary",
        "source:public_quality",
      ],
      results: [
        {
          result_id: "place_private_1",
          title: "Bright Coffee Bar",
          object_type: "saved_place",
          reasons: ["private quiet table note"],
        },
        {
          result_id: "map_public_1",
          title: "Public Coffee",
          object_type: "map_visible_unsaved_place",
          reasons: ["public map quality"],
        },
      ],
    },
    createdAt: "2026-06-06T12:00:00.000Z",
  });

  const envelope = envelopeForRecommendationAnalysisReceipt(receipt);
  const envelopeJson = JSON.stringify(envelope);

  assert.equal(envelope.public_summary.result_count, 2);
  assert.equal(envelope.public_summary.saved_result_count, 1);
  assert.equal(envelope.public_summary.public_result_count, 1);
  assert.equal(envelope.public_summary.public_web_used, true);
  assert.ok(envelope.preference_signals.includes("category:cafe"));
  assert.ok(envelope.preference_signals.includes("source:saved_memory"));
  assert.ok(envelope.preference_signals.includes("source:public_quality"));
  assert.equal(envelope.preference_signals.includes("bright coffee bar"), false);
  assert.equal(envelope.preference_signals.includes("bright_coffee_bar"), false);
  assert.equal(envelope.preference_signals.includes("private_note:anniversary"), false);
  assert.equal(envelope.preference_signals.includes("source:saved_memory:anniversary"), false);
  assert.equal(envelopeJson.includes("Bright Coffee Bar"), false);
  assert.equal(envelopeJson.includes("private quiet table note"), false);
  assert.equal(envelopeJson.includes("anniversary"), false);
});

test("recommendation analysis preference signals reserve proof level under truncation", () => {
  const receipt = buildRecommendationAnalysisReceiptDraft({
    userId: "user_123",
    request: {
      intent: "nearby saved coffee milk tea restaurant brunch dessert bar",
      constraints: ["nearby", "saved"],
      proof_level_min: "receipt_backed",
    },
    output: {
      preference_signals: [
        "category:food",
        "category:cafe",
        "category:bar",
        "category:attraction",
        "category:stay",
        "category:shopping",
        "source:saved_memory",
        "source:visited_memory",
        "source:review_candidate",
        "source:public_quality",
        "rating:high",
        "rating:positive",
        "visited_memory",
      ],
      results: [],
    },
  });

  assert.equal(receipt.preference_signals.length, 12);
  assert.ok(receipt.preference_signals.includes("proof_level:receipt_backed"));
});

test("recommendation analysis receipt payload normalization rejects oversized client payloads", () => {
  assert.throws(
    () => normalizeRecommendationAnalysisReceiptPayload({
      request: {},
      output: { results: Array.from({ length: 51 }, () => ({})) },
    }),
    RecommendationAnalysisReceiptPayloadError,
  );

  assert.throws(
    () => normalizeRecommendationAnalysisReceiptPayload({
      request: {},
      output: { preference_signals: Array.from({ length: 65 }, (_, index) => `signal_${index}`) },
    }),
    RecommendationAnalysisReceiptPayloadError,
  );

  assert.throws(
    () => normalizeRecommendationAnalysisReceiptPayload({
      request: { intent: "x".repeat(2049) },
      output: {},
    }),
    RecommendationAnalysisReceiptPayloadError,
  );
});
