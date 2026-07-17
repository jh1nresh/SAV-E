import assert from "node:assert/strict";
import test from "node:test";
import {
  PetCompanionValidationError,
  normalizePetSelectionPatch,
  petStageForXP,
  petXPForVerifiedReceipts,
} from "./petCompanion.js";

test("pet selection trims a supported preset and name", () => {
  const selectedAt = new Date("2026-07-16T00:00:00.000Z");
  assert.deepEqual(
    normalizePetSelectionPatch({ pet_preset: " sprout ", pet_name: " 芽芽 " }, selectedAt),
    {
      pet_preset: "sprout",
      pet_name: "芽芽",
      pet_selected_at: "2026-07-16T00:00:00.000Z",
    },
  );
});

test("profile patches without pet fields remain unchanged", () => {
  assert.equal(normalizePetSelectionPatch({ display_name: "Mina" }), null);
});

test("pet selection rejects partial or unsupported input", () => {
  assert.throws(
    () => normalizePetSelectionPatch({ pet_preset: "sprout" }),
    PetCompanionValidationError,
  );
  assert.throws(
    () => normalizePetSelectionPatch({ pet_preset: "dragon", pet_name: "Nova" }),
    /Unsupported pet preset/,
  );
  assert.throws(
    () => normalizePetSelectionPatch({ pet_preset: "cloud", pet_name: " ".repeat(4) }),
    /Pet name must be between 1 and 24 characters/,
  );
});

test("verified receipt count maps to idempotent XP and Toma stages", () => {
  assert.equal(petXPForVerifiedReceipts(0), 0);
  assert.equal(petXPForVerifiedReceipts(3), 60);
  assert.equal(petXPForVerifiedReceipts(-1), 0);
  assert.equal(petStageForXP(19), "hatchling");
  assert.equal(petStageForXP(20), "companion");
  assert.equal(petStageForXP(60), "guardian");
});
