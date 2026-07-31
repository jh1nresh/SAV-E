import assert from "node:assert/strict";
import test from "node:test";

import {
  TrekPlanningAdapter,
  TrekPlanningTransportError,
  decodeTrekMcpToolResult,
  type TrekConfirmedMapStampInput,
  type TrekMcpToolTransport,
  type TrekPlanningRequest,
  type TrekPlanningToolName,
} from "./trekPlanningAdapter.js";

const requestId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const localTripId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const firstPlaceId = "11111111-1111-4111-8111-111111111111";
const secondPlaceId = "22222222-2222-4222-8222-222222222222";
const thirdPlaceId = "33333333-3333-4333-8333-333333333333";

interface RecordedCall {
  name: TrekPlanningToolName;
  arguments: Record<string, unknown>;
}

class FakeTrekTransport implements TrekMcpToolTransport {
  readonly calls: RecordedCall[] = [];

  constructor(
    private readonly handler: (call: RecordedCall, index: number) => unknown | Promise<unknown>,
  ) {}

  async callTool(call: RecordedCall): Promise<unknown> {
    this.calls.push(call);
    return this.handler(call, this.calls.length - 1);
  }
}

test("copies confirmed Map Stamps into TREK in deterministic day order and shares only the map", async () => {
  let nextPlaceId = 501;
  let nextAssignmentId = 701;
  let summaryCalls = 0;
  const assignmentIdsByDay = new Map<number, number[]>();
  const transport = new FakeTrekTransport((call) => {
    switch (call.name) {
    case "create_trip":
      return ok({ trip: { id: 41, title: "Tokyo Weekend" } });
    case "get_trip_summary": {
      summaryCalls += 1;
      return ok({
        trip: { id: 41, title: "Tokyo Weekend" },
        days: [
          { id: 101, day_number: 1, assignments: summaryCalls === 1 ? [] : assignmentsForDay(101) },
          { id: 102, day_number: 2, assignments: summaryCalls === 1 ? [] : assignmentsForDay(102) },
        ],
      });
    }
    case "create_and_assign_place": {
      const dayId = call.arguments.dayId as number;
      const assignmentId = nextAssignmentId++;
      assignmentIdsByDay.set(dayId, [...(assignmentIdsByDay.get(dayId) ?? []), assignmentId]);
      return ok({ place: { id: nextPlaceId++ }, assignment: { id: assignmentId } });
    }
    case "update_assignment_time":
      return ok({ assignment: { id: call.arguments.assignmentId } });
    case "reorder_day_assignments":
      return ok({ success: true, dayId: call.arguments.dayId, order: call.arguments.assignmentIds });
    case "create_share_link":
      return ok({ token: "private-test-token-not-recorded", created: true });
    }
  });

  function assignmentsForDay(dayId: number): { id: number }[] {
    return (assignmentIdsByDay.get(dayId) ?? []).map((id) => ({ id }));
  }

  const adapter = new TrekPlanningAdapter(transport);
  const receipt = await adapter.execute(request({
    shareMode: "map_only",
    mapStamps: [
      mapStamp(thirdPlaceId, "Shibuya Sky", 2, 0, 35.6585, 139.7020),
      mapStamp(secondPlaceId, "Koffee Mameya", 1, 1, 35.6654, 139.7119),
      {
        ...mapStamp(firstPlaceId, "Tsukiji Outer Market", 1, 0, 35.6655, 139.7707),
        address: "4 Chome-16-2 Tsukiji, Chuo City, Tokyo",
        startTime: "09:00",
        endTime: "10:30",
      },
    ],
  }));

  assert.deepEqual(receipt, {
    requestId,
    localTripId,
    status: "completed",
    remoteTripId: 41,
    importedMapStampCount: 3,
    shareCreated: true,
    mapStampMappings: [
      { localPlaceId: firstPlaceId, remotePlaceId: 501, remoteAssignmentId: 701, remoteDayId: 101 },
      { localPlaceId: secondPlaceId, remotePlaceId: 502, remoteAssignmentId: 702, remoteDayId: 101 },
      { localPlaceId: thirdPlaceId, remotePlaceId: 503, remoteAssignmentId: 703, remoteDayId: 102 },
    ],
    completedTools: [
      "create_trip",
      "get_trip_summary",
      "create_and_assign_place",
      "update_assignment_time",
      "create_and_assign_place",
      "create_and_assign_place",
      "reorder_day_assignments",
      "create_share_link",
      "get_trip_summary",
    ],
    retryPolicy: "manual_only",
  });

  assert.deepEqual(transport.calls[0], {
    name: "create_trip",
    arguments: {
      title: "Tokyo Weekend",
      start_date: "2026-10-13",
      end_date: "2026-10-14",
      currency: "JPY",
    },
  });
  assert.deepEqual(
    transport.calls.filter((call) => call.name === "create_and_assign_place").map((call) => call.arguments),
    [
      {
        tripId: 41,
        dayId: 101,
        name: "Tsukiji Outer Market",
        lat: 35.6655,
        lng: 139.7707,
        address: "4 Chome-16-2 Tsukiji, Chuo City, Tokyo",
      },
      { tripId: 41, dayId: 101, name: "Koffee Mameya", lat: 35.6654, lng: 139.7119 },
      { tripId: 41, dayId: 102, name: "Shibuya Sky", lat: 35.6585, lng: 139.702 },
    ],
  );
  assert.deepEqual(
    transport.calls.find((call) => call.name === "update_assignment_time")?.arguments,
    { tripId: 41, assignmentId: 701, place_time: "09:00", end_time: "10:30" },
  );
  assert.deepEqual(
    transport.calls.find((call) => call.name === "reorder_day_assignments")?.arguments,
    { tripId: 41, dayId: 101, assignmentIds: [701, 702] },
  );
  assert.deepEqual(
    transport.calls.find((call) => call.name === "create_share_link")?.arguments,
    {
      tripId: 41,
      share_map: true,
      share_bookings: false,
      share_packing: false,
      share_budget: false,
      share_collab: false,
    },
  );
  assert.equal(JSON.stringify(receipt).includes("private-test-token"), false);
});

test("keeps a TREK trip private unless map-only sharing is explicit", async () => {
  let summaryCalls = 0;
  const transport = new FakeTrekTransport((call) => {
    if (call.name === "create_trip") return ok({ trip: { id: 42 } });
    if (call.name === "get_trip_summary") {
      summaryCalls += 1;
      return ok({
        trip: { id: 42 },
        days: [{ id: 201, day_number: 1, assignments: summaryCalls === 1 ? [] : [{ id: 801 }] }],
      });
    }
    if (call.name === "create_and_assign_place") {
      return ok({ place: { id: 601 }, assignment: { id: 801 } });
    }
    throw new Error(`Unexpected tool ${call.name}`);
  });

  const receipt = await new TrekPlanningAdapter(transport).execute(request({
    shareMode: "private",
    mapStamps: [mapStamp(firstPlaceId, "Tsukiji Outer Market", 1, 0, 35.6655, 139.7707)],
  }));

  assert.equal(receipt.status, "completed");
  assert.equal(receipt.shareCreated, false);
  assert.equal(transport.calls.some((call) => call.name === "create_share_link"), false);
});

test("fails closed before TREK when a clue is unconfirmed or carries private source fields", async () => {
  const transport = new FakeTrekTransport(() => {
    throw new Error("TREK must not be called");
  });
  const adapter = new TrekPlanningAdapter(transport);

  const unconfirmed = await adapter.execute(request({
    mapStamps: [{
      ...mapStamp(firstPlaceId, "Possible place", 1, 0, 35.6655, 139.7707),
      confirmationState: "review_candidate",
    } as unknown as TrekConfirmedMapStampInput],
  }));
  const leakedSource = await adapter.execute(request({
    mapStamps: [{
      ...mapStamp(firstPlaceId, "Tsukiji Outer Market", 1, 0, 35.6655, 139.7707),
      sourceUrl: "https://social.example/private",
      note: "private memory",
    } as TrekConfirmedMapStampInput],
  }));

  for (const receipt of [unconfirmed, leakedSource]) {
    assert.equal(receipt.status, "failed");
    assert.equal(receipt.failedAt, "validate");
    assert.equal(receipt.errorCode, "INVALID_REQUEST");
    assert.equal(receipt.remoteTripId, null);
    assert.deepEqual(receipt.mapStampMappings, []);
  }
  assert.equal(transport.calls.length, 0);
});

test("stops after a partial TREK failure and never retries a non-idempotent tool", async () => {
  let createdPlaces = 0;
  const transport = new FakeTrekTransport((call) => {
    if (call.name === "create_trip") return ok({ trip: { id: 43 } });
    if (call.name === "get_trip_summary") {
      return ok({ trip: { id: 43 }, days: [{ id: 301, day_number: 1, assignments: [] }] });
    }
    if (call.name === "create_and_assign_place") {
      createdPlaces += 1;
      if (createdPlaces === 2) throw new TrekPlanningTransportError("TREK_UNAVAILABLE");
      return ok({ place: { id: 701 }, assignment: { id: 901 } });
    }
    throw new Error(`Unexpected tool ${call.name}`);
  });

  const receipt = await new TrekPlanningAdapter(transport).execute(request({
    mapStamps: [
      mapStamp(firstPlaceId, "First", 1, 0, 35.6655, 139.7707),
      mapStamp(secondPlaceId, "Second", 1, 1, 35.6654, 139.7119),
    ],
  }));

  assert.equal(receipt.status, "failed");
  assert.equal(receipt.remoteTripId, 43);
  assert.equal(receipt.importedMapStampCount, 1);
  assert.deepEqual(receipt.mapStampMappings, [
    { localPlaceId: firstPlaceId, remotePlaceId: 701, remoteAssignmentId: 901, remoteDayId: 301 },
  ]);
  assert.equal(receipt.failedAt, "create_and_assign_place");
  assert.equal(receipt.errorCode, "TREK_UNAVAILABLE");
  assert.equal(receipt.retryPolicy, "manual_only");
  assert.equal(transport.calls.filter((call) => call.name === "create_and_assign_place").length, 2);
});

test("returns a recovery receipt when TREK creates a trip but omits its day mapping", async () => {
  const transport = new FakeTrekTransport((call) => {
    if (call.name === "create_trip") return ok({ trip: { id: 44 } });
    if (call.name === "get_trip_summary") return ok({ trip: { id: 44 } });
    throw new Error(`Unexpected tool ${call.name}`);
  });

  const receipt = await new TrekPlanningAdapter(transport).execute(request({
    mapStamps: [mapStamp(firstPlaceId, "Tsukiji Outer Market", 1, 0, 35.6655, 139.7707)],
  }));

  assert.equal(receipt.status, "failed");
  assert.equal(receipt.remoteTripId, 44);
  assert.equal(receipt.failedAt, "get_trip_summary");
  assert.equal(receipt.errorCode, "TREK_RESPONSE_INVALID");
  assert.equal(receipt.retryPolicy, "manual_only");
  assert.equal(transport.calls.length, 2);
});

test("decodes the TREK text payload and rejects MCP tool errors", () => {
  assert.deepEqual(decodeTrekMcpToolResult(ok({ trip: { id: 9 } })), { trip: { id: 9 } });
  assert.throws(
    () => decodeTrekMcpToolResult({ content: [{ type: "text", text: "Denied" }], isError: true }),
    (error: unknown) => error instanceof TrekPlanningTransportError && error.code === "TREK_TOOL_REJECTED",
  );
});

function request(overrides: Partial<TrekPlanningRequest> = {}): TrekPlanningRequest {
  return {
    requestId,
    localTripId,
    title: "Tokyo Weekend",
    startDate: "2026-10-13",
    endDate: "2026-10-14",
    currency: "jpy",
    shareMode: "private",
    mapStamps: [mapStamp(firstPlaceId, "Tsukiji Outer Market", 1, 0, 35.6655, 139.7707)],
    ...overrides,
  };
}

function mapStamp(
  localPlaceId: string,
  name: string,
  day: number,
  orderIndex: number,
  latitude: number,
  longitude: number,
): TrekConfirmedMapStampInput {
  return {
    localPlaceId,
    confirmationState: "confirmed_map_stamp",
    name,
    latitude,
    longitude,
    day,
    orderIndex,
  };
}

function ok(data: unknown): unknown {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
