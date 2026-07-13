import assert from "node:assert/strict";
import test from "node:test";
import {
  MemoryContractError,
  normalizePreferenceCreate,
  normalizePreferencePatch,
  normalizeRecommendationOutcome,
  recommendationOutcomeLabels,
} from "./memoryContracts.js";

test("explicit preferences activate while inferred preferences stay proposed", () => {
  assert.equal(normalizePreferenceCreate({
    preference_type: "cuisine",
    normalized_value: "  Thai   Food ",
    polarity: "like",
    source: "explicit",
  }).status, "active");
  assert.equal(normalizePreferenceCreate({
    preference_type: "vibe",
    normalized_value: "quiet",
    polarity: "like",
    source: "inferred",
  }).status, "proposed");
  assert.throws(() => normalizePreferenceCreate({
    preference_type: "vibe",
    normalized_value: "quiet",
    polarity: "like",
    source: "inferred",
    status: "active",
  }), MemoryContractError);
});

test("preference patch exposes only user-control fields", () => {
  assert.deepEqual(normalizePreferencePatch({ status: "removed" }), { status: "removed" });
  assert.throws(() => normalizePreferencePatch({ source: "explicit" }), /no supported/);
});

test("outcomes accept the full taxonomy without private payloads", () => {
  for (const label of recommendationOutcomeLabels) {
    const outcome = normalizeRecommendationOutcome({
      recommendation_id: "run_opaque_123",
      labels: [label],
      label_source: "evaluator",
      evidence_refs: ["claim:abc123"],
      retrieval_version: "structured-v1",
    });
    assert.deepEqual(outcome.labels, [label]);
  }
  assert.throws(() => normalizeRecommendationOutcome({
    recommendation_id: "run_opaque_123",
    labels: ["wrong_place"],
    label_source: "explicit_user",
    evidence_refs: ["https://private.example/note"],
  }), /opaque identifier/);
  assert.throws(() => normalizeRecommendationOutcome({
    recommendation_id: "run_opaque_123",
    labels: ["unknown"],
    label_source: "evaluator",
  }), /labels is invalid/);
});
