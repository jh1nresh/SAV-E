import type {
  TrekMcpToolTransport,
  TrekPlanningToolName,
} from "./trekPlanningAdapter.js";

/**
 * In-memory stand-in for a live TREK MCP endpoint.
 *
 * The real connection needs OAuth 2.1 (`trips:write`, `places:write`) against a
 * separately deployed TREK instance — a founder decision that is deliberately
 * still open. Until then this transport answers the six tool calls with
 * well-formed, deterministic payloads so the whole projection path (route ->
 * adapter -> receipt -> app) can be exercised and its data shape verified
 * without a network dependency or a TREK account.
 *
 * It is NOT a mock in the test-double sense: it ships in the server so the
 * `--trek-stub` path is reachable in a running deployment, and it is what the
 * app talks to until `TREK_MCP_ENDPOINT` is configured.
 */
export class TrekStubTransport implements TrekMcpToolTransport {
  private nextId = 1000;
  private dayIdsByTrip = new Map<number, number[]>();
  /** Assignment ids per day id, so the closing summary can be verified. */
  private assignmentsByDayId = new Map<number, number[]>();

  /** Tool calls in the order they were received — the projection audit trail. */
  readonly callLog: TrekPlanningToolName[] = [];

  constructor(private readonly tripDayCount: number) {}

  async callTool(params: {
    name: TrekPlanningToolName;
    arguments: Record<string, unknown>;
  }): Promise<unknown> {
    this.callLog.push(params.name);
    return mcpResult(this.payload(params));
  }

  private payload(params: {
    name: TrekPlanningToolName;
    arguments: Record<string, unknown>;
  }): Record<string, unknown> {
    switch (params.name) {
      case "create_trip": {
        const tripId = this.allocate();
        const dayIds = Array.from({ length: this.tripDayCount }, () => this.allocate());
        this.dayIdsByTrip.set(tripId, dayIds);
        return { trip: { id: tripId } };
      }

      case "get_trip_summary": {
        const tripId = numberArgument(params.arguments, "tripId");
        const dayIds = this.dayIdsByTrip.get(tripId) ?? [];
        return {
          trip: { id: tripId },
          // TREK's wire shape is snake_case here, unlike the camelCase tool
          // arguments — the adapter reads `day_number`.
          days: dayIds.map((id, index) => ({
            id,
            day_number: index + 1,
            assignments: (this.assignmentsByDayId.get(id) ?? []).map((assignmentId) => ({
              id: assignmentId,
            })),
          })),
        };
      }

      case "create_and_assign_place": {
        const dayId = numberArgument(params.arguments, "dayId");
        const assignmentId = this.allocate();
        this.assignmentsByDayId.set(dayId, [
          ...(this.assignmentsByDayId.get(dayId) ?? []),
          assignmentId,
        ]);
        return {
          place: { id: this.allocate() },
          assignment: { id: assignmentId },
        };
      }

      case "update_assignment_time":
      case "reorder_day_assignments":
        return { ok: true };

      case "create_share_link":
        return { share: { url: `https://trek.invalid/s/${this.allocate()}` } };
    }
  }

  private allocate(): number {
    this.nextId += 1;
    return this.nextId;
  }
}

/**
 * Wraps a payload the way an MCP server does. The adapter decodes
 * `structuredContent` first and falls back to a JSON text block, so the stub
 * emits both — exercising the same decode path a live TREK response takes.
 */
function mcpResult(payload: Record<string, unknown>): Record<string, unknown> {
  return {
    structuredContent: payload,
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
}

function numberArgument(args: Record<string, unknown>, key: string): number {
  const value = args[key];
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`TREK stub expected an integer ${key}`);
  }
  return value;
}
