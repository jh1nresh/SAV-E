import assert from "node:assert/strict";
import test from "node:test";
import { detectClaimLevel, checkClaim, claimLevelForOrderStatus, guardReply } from "./claimGuard.js";

test("detectClaimLevel picks the highest implied level", () => {
  assert.equal(detectClaimLevel("I think you want an iced latte; confirm?"), "intent_only");
  assert.equal(detectClaimLevel("Order placed with the merchant."), "order_created");
  assert.equal(detectClaimLevel("Payment received — order placed."), "paid");
  assert.equal(detectClaimLevel("Your receipt is ready."), "receipt_issued");
});

test("benign 'payment'/'receipt on the way' wording does NOT overclaim", () => {
  assert.equal(detectClaimLevel("Pay here: <link>. I'll confirm after payment clears."), "intent_only");
  assert.equal(detectClaimLevel("Ordered a latte. Receipt on the way."), "order_created");
});

test("checkClaim blocks a reply that exceeds the allowed state", () => {
  // Adversarial: reply claims paid, but state is only order_created.
  const bad = checkClaim("Payment received! You're all set.", "order_created");
  assert.equal(bad.ok, false);
  if (!bad.ok) {
    assert.equal(bad.claimed, "paid");
    assert.equal(bad.allowed, "order_created");
  }
  // Within bounds.
  assert.equal(checkClaim("Order placed.", "order_created").ok, true);
  assert.equal(checkClaim("Payment received.", "paid").ok, true);
});

test("claimLevelForOrderStatus maps SLL-R statuses", () => {
  assert.equal(claimLevelForOrderStatus("pending_payment"), "order_created");
  assert.equal(claimLevelForOrderStatus("payment_backed"), "paid");
  assert.equal(claimLevelForOrderStatus("receipt_issued"), "receipt_issued");
  assert.equal(claimLevelForOrderStatus("whatever"), "order_created");
});

test("guardReply falls back when the reply overclaims", () => {
  // A would-be LLM reply overclaiming 'paid' on an unpaid order → fallback.
  const safe = guardReply("Payment received, enjoy!", "order_created", "Order received.");
  assert.equal(safe, "Order received.");
  // A correct reply passes through untouched.
  const ok = guardReply("Order placed.", "order_created", "Order received.");
  assert.equal(ok, "Order placed.");
});
