// SLL-R client — Savvy's commerce / receipt / redemption rail.
//
// Savvy owns consumer memory + recommendation. When a saved intent needs to
// become a real action (order / ticket / voucher) or be verified (receipt →
// proof), Savvy calls SLL-R through this module. SLL-R is an external service;
// this is the only place Savvy talks to it. Follows the repo's fetch+env pattern
// (cf. maatPublicWebAnalysis.ts). No DB, no auth surface — pure outbound client.
//
// Env:
//   SLLR_API_BASE   default https://sll-r.vercel.app

const SLLR_API_BASE = (process.env.SLLR_API_BASE ?? "https://sll-r.vercel.app").replace(/\/$/, "");

export class SllrError extends Error {
  constructor(message: string, readonly status = 502) {
    super(message);
    this.name = "SllrError";
  }
}

async function sllrFetch<T>(path: string, init: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${SLLR_API_BASE}${path}`, {
      ...init,
      headers: { "content-type": "application/json", ...(init.headers ?? {}) },
    });
  } catch (error) {
    throw new SllrError(`SLL-R ${path} unreachable: ${error instanceof Error ? error.message : "network error"}`);
  }
  const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok || typeof json.error === "string") {
    throw new SllrError(`SLL-R ${path} failed (${res.status}): ${String(json.error ?? res.statusText)}`, res.status);
  }
  return json as T;
}

// A buyer session binds SLL-R orders + receipts to a stable buyerId. Savvy mints
// one per Savvy user (persist the token on the user; reuse to keep history).
export type SllrBuyer = { token: string; buyerId: string };
export async function issueBuyerSession(label: string): Promise<SllrBuyer> {
  return sllrFetch<SllrBuyer>("/buyer/session", { method: "POST", body: JSON.stringify({ label }) });
}

export type SllrQuote = {
  feasible: boolean;
  item?: { id: string; name: string; subtotalUsd: string };
  estimate?: { readyInMinutes?: number | null };
  merchant?: { id: string; name: string; paymentRails: string[] };
};
export async function quote(
  merchantId: string,
  userIntent: string,
  opts: { deadlineMinutes?: number; maxSpendUsd?: string } = {},
): Promise<SllrQuote> {
  const r = await sllrFetch<{ quote: SllrQuote }>(
    `/merchants/${encodeURIComponent(merchantId)}/quote`,
    { method: "POST", body: JSON.stringify({ userIntent, ...opts }) },
  );
  return r.quote;
}

export type SllrOrder = {
  id: string;
  status: string;
  item: { name: string; subtotalUsd: string };
  merchantId?: string;
  merchantName?: string;
};
// "SLL-R asks": the hint to offer the buyer a recurring version of this order.
export type SllrRecurringSuggestion = { eligible: boolean; prompt?: string };
// Place an order bound to a Savvy buyer. Pass the buyer session so the order +
// its receipt accrue to that buyerId (the cross-merchant taste/receipt graph).
export async function placeOrder(
  merchantId: string,
  userIntent: string,
  buyer: SllrBuyer,
  opts: { deadlineMinutes?: number; customerLabel?: string } = {},
): Promise<SllrOrder & { suggestRecurring?: SllrRecurringSuggestion }> {
  const r = await sllrFetch<{ order: SllrOrder; suggestRecurring?: SllrRecurringSuggestion }>(
    `/merchants/${encodeURIComponent(merchantId)}/orders`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${buyer.token}` },
      body: JSON.stringify({ userIntent, ...opts }),
    },
  );
  return { ...r.order, suggestRecurring: r.suggestRecurring };
}

export type SllrPaymentOption = { rail: string; type?: string; url?: string; pickupCode?: string };
export async function paymentOptions(merchantId: string, orderId: string): Promise<SllrPaymentOption[]> {
  const r = await sllrFetch<{ paymentOptions?: SllrPaymentOption[] }>(
    `/merchants/${encodeURIComponent(merchantId)}/payment-options`,
    { method: "POST", body: JSON.stringify({ orderId }) },
  );
  return r.paymentOptions ?? [];
}

export type SllrNearbyMerchant = { id: string; name: string; category: string; location: string; distanceKm: number };
// Merchants near a location, sorted by distance (SLL-R geo lookup). Used to pick
// the nearest merchant to order from for a given area.
export async function nearby(
  lat: number,
  lng: number,
  opts: { radiusKm?: number; category?: string; limit?: number } = {},
): Promise<SllrNearbyMerchant[]> {
  const params = new URLSearchParams({ lat: String(lat), lng: String(lng) });
  if (opts.radiusKm) params.set("radiusKm", String(opts.radiusKm));
  if (opts.category) params.set("category", opts.category);
  if (opts.limit) params.set("limit", String(opts.limit));
  const r = await sllrFetch<{ merchants?: SllrNearbyMerchant[] }>(`/merchants/nearby?${params.toString()}`, { method: "GET" });
  return r.merchants ?? [];
}

// The buyer's cross-merchant order history (SLL-R receipt/taste graph). Savvy can
// fold this into its experience memory.
export async function myOrders(buyer: SllrBuyer): Promise<SllrOrder[]> {
  const r = await sllrFetch<{ orders?: SllrOrder[] }>("/buyer/orders", {
    method: "GET",
    headers: { authorization: `Bearer ${buyer.token}` },
  });
  return r.orders ?? [];
}

// --- Recurring orders (confirm-each) ----------------------------------------
// SLL-R owns the schedule + the saved-card charge; Savvy sets up the "usual" and
// relays the per-run confirm. The buyer must have a saved card (first checkout)
// before a run can actually charge.

export type SllrSchedule = { daysOfWeek: number[]; hour: number; minute: number; tz: string };
export type SllrSubscription = { id: string; merchantId: string; merchantName?: string; nextRunAt?: string };
export type SllrRun = { id: string; subscriptionId: string; summary: string; dueAt?: string };

// Create a recurring subscription ("usual" + weekly schedule). maxPerRunUsd caps
// each charge — SLL-R refuses a run above it.
export async function createRecurring(
  buyer: SllrBuyer,
  merchantId: string,
  userIntent: string,
  schedule: SllrSchedule,
  maxPerRunUsd: string,
  opts: { deadlineMinutes?: number } = {},
): Promise<{ subscription: SllrSubscription; cardOnFile: boolean }> {
  return sllrFetch<{ subscription: SllrSubscription; cardOnFile: boolean }>("/buyer/recurring", {
    method: "POST",
    headers: { authorization: `Bearer ${buyer.token}` },
    body: JSON.stringify({ merchantId, template: { userIntent, ...opts }, schedule, maxPerRunUsd }),
  });
}

// Runs awaiting the buyer's confirmation (the "order your usual now?" prompts).
export async function pendingRuns(buyer: SllrBuyer): Promise<SllrRun[]> {
  const r = await sllrFetch<{ runs?: SllrRun[] }>("/buyer/recurring/runs", {
    method: "GET",
    headers: { authorization: `Bearer ${buyer.token}` },
  });
  return r.runs ?? [];
}

// Confirm a pending run → SLL-R creates the order + charges the saved card.
export type SllrConfirmResult = { status: string; order?: SllrOrder };
export async function confirmRecurringRun(buyer: SllrBuyer, runId: string): Promise<SllrConfirmResult> {
  return sllrFetch<SllrConfirmResult>("/buyer/recurring/confirm", {
    method: "POST",
    headers: { authorization: `Bearer ${buyer.token}` },
    body: JSON.stringify({ runId }),
  });
}
