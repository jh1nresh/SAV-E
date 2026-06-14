// SLL-R client — SAV-E's commerce / receipt / redemption rail.
//
// SAV-E owns consumer memory + recommendation. When a saved intent needs to
// become a real action (order / ticket / voucher) or be verified (receipt →
// proof), SAV-E calls SLL-R through this module. SLL-R is an external service;
// this is the only place SAV-E talks to it. Follows the repo's fetch+env pattern
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

// A buyer session binds SLL-R orders + receipts to a stable buyerId. SAV-E mints
// one per SAV-E user (persist the token on the user; reuse to keep history).
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
// Place an order bound to a SAV-E buyer. Pass the buyer session so the order +
// its receipt accrue to that buyerId (the cross-merchant taste/receipt graph).
export async function placeOrder(
  merchantId: string,
  userIntent: string,
  buyer: SllrBuyer,
  opts: { deadlineMinutes?: number; customerLabel?: string } = {},
): Promise<SllrOrder> {
  const r = await sllrFetch<{ order: SllrOrder }>(
    `/merchants/${encodeURIComponent(merchantId)}/orders`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${buyer.token}` },
      body: JSON.stringify({ userIntent, ...opts }),
    },
  );
  return r.order;
}

export type SllrPaymentOption = { rail: string; type?: string; url?: string; pickupCode?: string };
export async function paymentOptions(merchantId: string, orderId: string): Promise<SllrPaymentOption[]> {
  const r = await sllrFetch<{ paymentOptions?: SllrPaymentOption[] }>(
    `/merchants/${encodeURIComponent(merchantId)}/payment-options`,
    { method: "POST", body: JSON.stringify({ orderId }) },
  );
  return r.paymentOptions ?? [];
}

// The buyer's cross-merchant order history (SLL-R receipt/taste graph). SAV-E can
// fold this into its experience memory.
export async function myOrders(buyer: SllrBuyer): Promise<SllrOrder[]> {
  const r = await sllrFetch<{ orders?: SllrOrder[] }>("/buyer/orders", {
    method: "GET",
    headers: { authorization: `Bearer ${buyer.token}` },
  });
  return r.orders ?? [];
}
