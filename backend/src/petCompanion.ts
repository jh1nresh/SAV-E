export const petPresets = ["sprout", "spark", "cloud"] as const;

export type PetPreset = typeof petPresets[number];
export type PetStage = "hatchling" | "companion" | "guardian";

export class PetCompanionValidationError extends Error {}

type PetSelectionPatch = {
  pet_preset: PetPreset;
  pet_name: string;
  pet_selected_at: string;
};

export function normalizePetSelectionPatch(
  body: Record<string, unknown>,
  selectedAt = new Date(),
): PetSelectionPatch | null {
  const hasPreset = Object.hasOwn(body, "pet_preset");
  const hasName = Object.hasOwn(body, "pet_name");
  if (!hasPreset && !hasName) return null;
  if (!hasPreset || !hasName) {
    throw new PetCompanionValidationError("Pet preset and name must be selected together");
  }

  const preset = typeof body.pet_preset === "string" ? body.pet_preset.trim() : "";
  if (!petPresets.includes(preset as PetPreset)) {
    throw new PetCompanionValidationError("Unsupported pet preset");
  }

  const name = typeof body.pet_name === "string" ? body.pet_name.trim() : "";
  if (name.length < 1 || name.length > 24) {
    throw new PetCompanionValidationError("Pet name must be between 1 and 24 characters");
  }

  return {
    pet_preset: preset as PetPreset,
    pet_name: name,
    pet_selected_at: selectedAt.toISOString(),
  };
}

export function petXPForVerifiedReceipts(receiptCount: unknown): number {
  const count = Number(receiptCount ?? 0);
  if (!Number.isFinite(count) || count <= 0) return 0;
  return Math.floor(count) * 20;
}

export function petStageForXP(xp: number): PetStage {
  if (xp >= 60) return "guardian";
  if (xp >= 20) return "companion";
  return "hatchling";
}
