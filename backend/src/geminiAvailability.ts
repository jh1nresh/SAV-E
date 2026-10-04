/** Passive, process-local HTTP availability. Never probes, reads bodies, or reports a credit balance. */
export type GeminiState = "available" | "billing_blocked" | "access_denied" | "rate_limited" | "unavailable";
type Observation = { state: GeminiState; observedAt: number; sequence: number };
export class GeminiAvailability {
  private observations = new Map<string, Observation>();
  private sequence = 0;
  constructor(private now = Date.now, private notify: (state: GeminiState) => void = state => {
    console.warn(JSON.stringify({ event: "gemini_availability_changed", state }));
  }) {}

  async observe<T extends { ok: boolean; status: number }>(model: string, request: () => Promise<T>): Promise<T> {
    const sequence = ++this.sequence;
    try {
      const response = await request();
      // A malformed caller request says nothing about the provider's availability.
      const state = response.ok ? "available" : response.status === 402 ? "billing_blocked"
        : [401, 403].includes(response.status) ? "access_denied" : response.status === 429 ? "rate_limited"
        : response.status >= 500 ? "unavailable" : undefined;
      if (state) this.record(model, state, sequence);
      return response;
    } catch (error) {
      this.record(model, "unavailable", sequence);
      throw error;
    }
  }

  private record(model: string, state: GeminiState, sequence: number) {
    const previous = this.observations.get(model);
    if (previous && previous.sequence > sequence) return;
    if (!previous && this.observations.size >= 32) this.observations.delete(this.observations.keys().next().value!);
    this.observations.set(model, { state, observedAt: this.now(), sequence });
    // Only bounded state labels enter logs; never model names, URLs, bodies, keys or user data.
    if (previous?.state !== state && (state !== "available" || previous)) {
      try { this.notify(state); } catch { /* diagnostics cannot fail user requests */ }
    }
  }

  snapshot() {
    const recent = [...this.observations.values()].filter(item => this.now() - item.observedAt < 10 * 60_000);
    const order: GeminiState[] = ["billing_blocked", "access_denied", "rate_limited", "unavailable", "available"];
    const state = order.find(value => recent.some(item => item.state === value)) ?? "unknown";
    return { state, scope: "process_local_recent_http_responses", window_seconds: 600,
      observed_at: recent.length ? new Date(Math.max(...recent.map(item => item.observedAt))).toISOString() : null,
      credit_balance: null, active_probe: false };
  }
}
export const geminiAvailability = new GeminiAvailability();
