// Bounded-LLM-action post-check (spec: sll-r bounded-llm-action-settlement-rail,
// agent-client half). SLL-R enforces the *action* invariants server-side; this is
// the *reply* invariant: an outgoing message must not claim a higher commercial
// state than the deterministic truth SLL-R returned. It defends against a future
// LLM-written reply (or a template drift) that says "paid" / "order placed" /
// "receipt" before that state actually exists.
//
// Pure + dependency-free so it's trivially testable and safe to wrap every
// SLL-R-derived reply.

// Ordered low → high. A reply may claim AT MOST the allowed level.
export const CLAIM_LEVELS = [
  "intent_only",
  "catalog_found",
  "quote_only",
  "consent_requested",
  "order_created",
  "payment_pending",
  "paid",
  "merchant_accepted",
  "ready",
  "fulfilled",
  "receipt_issued",
  "verified_review_eligible",
] as const;
export type ClaimLevel = (typeof CLAIM_LEVELS)[number];

const RANK: Record<ClaimLevel, number> = Object.fromEntries(
  CLAIM_LEVELS.map((l, i) => [l, i]),
) as Record<ClaimLevel, number>;

// Phrase → the minimum claim level it implies. Patterns are deliberately narrow
// (a bare "payment" or "receipt on the way" must NOT trip a higher level — only
// completed-state language does).
const CLAIM_PATTERNS: Array<{ level: ClaimLevel; re: RegExp }> = [
  { level: "verified_review_eligible", re: /\bverified review\b/i },
  { level: "receipt_issued", re: /\breceipt (issued|ready|available)\b|your receipt is\b/i },
  { level: "fulfilled", re: /\b(fulfilled|picked up|handed over)\b/i },
  { level: "ready", re: /\b(ready for pickup|is ready|order is ready)\b/i },
  { level: "merchant_accepted", re: /\bmerchant (accepted|confirmed)\b|accepted by .* (cafe|coffee|merchant)\b/i },
  { level: "paid", re: /\b(paid|payment received|payment confirmed|charged your card|successfully charged)\b/i },
  { level: "order_created", re: /\b(order placed|order created|ordered|placed your order)\b/i },
];

// The highest claim level any phrase in the text implies (intent_only if none).
export function detectClaimLevel(text: string): ClaimLevel {
  let level: ClaimLevel = "intent_only";
  for (const { level: l, re } of CLAIM_PATTERNS) {
    if (re.test(text) && RANK[l] > RANK[level]) level = l;
  }
  return level;
}

export type ClaimCheck = { ok: true } | { ok: false; claimed: ClaimLevel; allowed: ClaimLevel };

// True iff the reply claims no more than `allowed`.
export function checkClaim(text: string, allowed: ClaimLevel): ClaimCheck {
  const claimed = detectClaimLevel(text);
  return RANK[claimed] <= RANK[allowed] ? { ok: true } : { ok: false, claimed, allowed };
}

// Map an SLL-R order status to the max claim level its reply may assert.
export function claimLevelForOrderStatus(status: string): ClaimLevel {
  switch (status) {
    case "pending_payment": return "order_created";
    case "payment_backed": return "paid";
    case "accepted": return "merchant_accepted";
    case "ready": return "ready";
    case "claimed":
    case "fulfilled": return "fulfilled";
    case "receipt_issued": return "receipt_issued";
    default: return "order_created";
  }
}

// Guard a reply: if it overclaims, log and fall back to a safe message bounded by
// the true state, rather than send a false claim. Returns the safe reply.
export function guardReply(reply: string, allowed: ClaimLevel, fallback: string): string {
  const check = checkClaim(reply, allowed);
  if (check.ok) return reply;
  console.error(`[claimGuard] blocked overclaim: reply claims "${check.claimed}" but state allows "${check.allowed}"`);
  return fallback;
}
