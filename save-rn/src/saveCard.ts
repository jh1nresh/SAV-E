export const SAVE_CARD_SCHEMA = "save.card.v0" as const;

export type SaveCardType =
  | "place_card"
  | "recommendation_card"
  | "itinerary_card"
  | "review_card";

export type SaveCardVisibility =
  | "private"
  | "public_link"
  | "friends"
  | "agent_readable";

export type SaveCardSourceKind =
  | "instagram"
  | "luma"
  | "google_maps"
  | "apple_maps"
  | "manual"
  | "other";

export type SaveCardPlaceStatus =
  | "source_only"
  | "review_candidate"
  | "confirmed_place"
  | "visited";

export type SaveCardProofLevel =
  | "source_link"
  | "map_confirmed"
  | "visited"
  | "receipt_backed"
  | "payment_backed";

export type SaveCardAction = "save" | "open_maps" | "ask_agent" | "import";

export type SaveCardSource = {
  kind: SaveCardSourceKind;
  url?: string | null;
};

export type SaveCardGeo = {
  latitude: number;
  longitude: number;
};

export type SaveCardPlace = {
  name: string;
  address: string;
  geo: SaveCardGeo | null;
  status: SaveCardPlaceStatus;
  confidence?: number | null;
  proofLevel: SaveCardProofLevel;
  evidence: string[];
  missingInfo: string[];
};

export type SaveCardRedaction = {
  field: string;
  reason: string;
};

export type SaveCard = {
  schema: typeof SAVE_CARD_SCHEMA;
  cardType: SaveCardType;
  id: string;
  title: string;
  createdAt: string;
  createdBy: string;
  visibility: SaveCardVisibility;
  source: SaveCardSource;
  places: SaveCardPlace[];
  humanSummary: string;
  agentInstructions: string[];
  redactions: SaveCardRedaction[];
  actions: SaveCardAction[];
};

const cardTypes = new Set<SaveCardType>([
  "place_card",
  "recommendation_card",
  "itinerary_card",
  "review_card",
]);

const visibilities = new Set<SaveCardVisibility>([
  "private",
  "public_link",
  "friends",
  "agent_readable",
]);

const sourceKinds = new Set<SaveCardSourceKind>([
  "instagram",
  "luma",
  "google_maps",
  "apple_maps",
  "manual",
  "other",
]);

const placeStatuses = new Set<SaveCardPlaceStatus>([
  "source_only",
  "review_candidate",
  "confirmed_place",
  "visited",
]);

const proofLevels = new Set<SaveCardProofLevel>([
  "source_link",
  "map_confirmed",
  "visited",
  "receipt_backed",
  "payment_backed",
]);

const actions = new Set<SaveCardAction>([
  "save",
  "open_maps",
  "ask_agent",
  "import",
]);

export function validateSaveCard(value: unknown): SaveCard {
  const card = asRecord(value, "card");

  expect(card.schema === SAVE_CARD_SCHEMA, "schema must be save.card.v0");
  expect(isString(card.cardType) && cardTypes.has(card.cardType as SaveCardType), "cardType is invalid");
  expect(isString(card.id) && card.id.startsWith("save_"), "id must start with save_");
  expect(isNonEmptyString(card.title), "title is required");
  expect(isString(card.createdAt) && !Number.isNaN(Date.parse(card.createdAt)), "createdAt must be ISO-like date");
  expect(isNonEmptyString(card.createdBy), "createdBy is required");
  expect(isString(card.visibility) && visibilities.has(card.visibility as SaveCardVisibility), "visibility is invalid");

  const source = asRecord(card.source, "source");
  expect(isString(source.kind) && sourceKinds.has(source.kind as SaveCardSourceKind), "source.kind is invalid");
  expect(source.url === undefined || source.url === null || isString(source.url), "source.url must be a string or null");

  expect(Array.isArray(card.places), "places must be an array");
  for (const [index, placeValue] of card.places.entries()) {
    validatePlace(placeValue, index);
  }

  expect(isString(card.humanSummary), "humanSummary must be a string");
  expect(isStringArray(card.agentInstructions), "agentInstructions must be string[]");
  expect(Array.isArray(card.redactions), "redactions must be an array");
  for (const [index, redactionValue] of card.redactions.entries()) {
    const redaction = asRecord(redactionValue, `redactions[${index}]`);
    expect(isNonEmptyString(redaction.field), `redactions[${index}].field is required`);
    expect(isNonEmptyString(redaction.reason), `redactions[${index}].reason is required`);
  }
  expect(Array.isArray(card.actions), "actions must be an array");
  for (const action of card.actions) {
    expect(isString(action) && actions.has(action as SaveCardAction), `action is invalid: ${String(action)}`);
  }

  return card as SaveCard;
}

export function parseSaveCard(json: string): SaveCard {
  return validateSaveCard(JSON.parse(json));
}

function validatePlace(value: unknown, index: number): void {
  const place = asRecord(value, `places[${index}]`);
  expect(isNonEmptyString(place.name), `places[${index}].name is required`);
  expect(isString(place.address), `places[${index}].address must be a string`);
  expect(
    isString(place.status) && placeStatuses.has(place.status as SaveCardPlaceStatus),
    `places[${index}].status is invalid`
  );
  expect(
    place.confidence === undefined ||
      place.confidence === null ||
      (typeof place.confidence === "number" && place.confidence >= 0 && place.confidence <= 1),
    `places[${index}].confidence must be between 0 and 1`
  );
  expect(
    isString(place.proofLevel) && proofLevels.has(place.proofLevel as SaveCardProofLevel),
    `places[${index}].proofLevel is invalid`
  );
  expect(isStringArray(place.evidence), `places[${index}].evidence must be string[]`);
  expect(isStringArray(place.missingInfo), `places[${index}].missingInfo must be string[]`);

  if (place.geo !== null) {
    const geo = asRecord(place.geo, `places[${index}].geo`);
    expect(typeof geo.latitude === "number" && geo.latitude >= -90 && geo.latitude <= 90, `places[${index}].geo.latitude is invalid`);
    expect(typeof geo.longitude === "number" && geo.longitude >= -180 && geo.longitude <= 180, `places[${index}].geo.longitude is invalid`);
  }
}

function asRecord(value: unknown, label: string): Record<string, unknown> {
  expect(value !== null && typeof value === "object" && !Array.isArray(value), `${label} must be an object`);
  return value as Record<string, unknown>;
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isNonEmptyString(value: unknown): value is string {
  return isString(value) && value.trim().length > 0;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isString);
}

function expect(condition: boolean, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}
