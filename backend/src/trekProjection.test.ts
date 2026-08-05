import assert from "node:assert/strict";
import test from "node:test";

import { TrekPlanningAdapter } from "./trekPlanningAdapter.js";
import { TrekStubTransport } from "./trekStubTransport.js";
import {
  TrekProjectionError,
  buildTrekPlanningRequest,
  normalizeTrekProjectionRequestBody,
  projectedDayCount,
  type TrekProjectionStopRow,
  type TrekProjectionTripRow,
} from "./trekProjection.js";

const requestId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const tripId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const firstPlaceId = "11111111-1111-4111-8111-111111111111";
const secondPlaceId = "22222222-2222-4222-8222-222222222222";

const trip: TrekProjectionTripRow = {
  id: tripId,
  name: "Tokyo Weekend",
  start_date: "2026-10-12",
  end_date: "2026-10-14",
};

function stop(overrides: Partial<TrekProjectionStopRow> = {}): TrekProjectionStopRow {
  return {
    place_id: firstPlaceId,
    place_name: "Koffee Mameya",
    day: 1,
    order_index: 0,
    start_time: "09:00",
    duration: 60,
    address: "4-15-3 Jingumae, Shibuya",
    latitude: 35.6684,
    longitude: 139.7101,
    status: "confirmed",
    ...overrides,
  };
}

test("normalizes a projection body and defaults to the private share mode", () => {
  const result = normalizeTrekProjectionRequestBody({ requestId });
  assert.equal(result.requestId, requestId);
  assert.equal(result.shareMode, "private");
});

test("rejects a projection body without a requestId", () => {
  assert.throws(() => normalizeTrekProjectionRequestBody({}), TrekProjectionError);
});

test("rejects an unknown share mode", () => {
  assert.throws(
    () => normalizeTrekProjectionRequestBody({ requestId, shareMode: "public" }),
    TrekProjectionError,
  );
});

test("builds an adapter request from confirmed stops", () => {
  const { request, skippedStopCount } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [stop(), stop({ place_id: secondPlaceId, place_name: "Tsukiji", day: 2, order_index: 1 })],
  });

  assert.equal(skippedStopCount, 0);
  assert.equal(request.localTripId, tripId);
  assert.equal(request.title, "Tokyo Weekend");
  assert.equal(request.startDate, "2026-10-12");
  assert.equal(request.mapStamps.length, 2);
  assert.equal(request.mapStamps[0]?.confirmationState, "confirmed_map_stamp");
  assert.equal(request.mapStamps[0]?.localPlaceId, firstPlaceId);
  assert.equal(request.mapStamps[0]?.startTime, "09:00");
  assert.equal(request.mapStamps[1]?.day, 2);
});

test("skips stops that are not projectable and reports the count", () => {
  const { request, skippedStopCount } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [
      stop(),
      stop({ place_id: secondPlaceId, status: "pending" }),
      stop({ place_id: secondPlaceId, latitude: 0, longitude: 0 }),
      stop({ place_id: secondPlaceId, latitude: null, longitude: null }),
    ],
  });

  assert.equal(request.mapStamps.length, 1);
  assert.equal(skippedStopCount, 3);
});

test("refuses to project a trip with no confirmed Map Stamps", () => {
  assert.throws(
    () =>
      buildTrekPlanningRequest({
        requestId,
        shareMode: "private",
        trip,
        stops: [stop({ status: "pending" })],
      }),
    TrekProjectionError,
  );
});

test("normalizes a timestamp start_time down to a clock time", () => {
  const { request } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [stop({ start_time: "14:30:00+09" })],
  });
  assert.equal(request.mapStamps[0]?.startTime, "14:30");
});

test("day count covers the highest day in the projection", () => {
  const { request } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [stop({ day: 1 }), stop({ place_id: secondPlaceId, day: 3, order_index: 1 })],
  });
  assert.equal(projectedDayCount(request), 3);
});

test("end to end: stored rows project through the adapter into a completed receipt", async () => {
  const { request } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [
      stop(),
      stop({ place_id: secondPlaceId, place_name: "Tsukiji", order_index: 1, start_time: "11:30" }),
    ],
  });

  const transport = new TrekStubTransport(projectedDayCount(request));
  const receipt = await new TrekPlanningAdapter(transport).execute(request);

  assert.equal(receipt.status, "completed");
  assert.equal(receipt.importedMapStampCount, 2);
  assert.equal(receipt.localTripId, tripId);
  assert.ok(receipt.remoteTripId && receipt.remoteTripId > 0);
  assert.equal(receipt.mapStampMappings.length, 2);
  assert.equal(receipt.mapStampMappings[0]?.localPlaceId, firstPlaceId);
  assert.ok(receipt.mapStampMappings[0]!.remotePlaceId > 0);
  assert.ok(receipt.mapStampMappings[0]!.remoteAssignmentId > 0);

  // Both stamps sit on day 1: the adapter reorders that day once, then
  // re-reads the summary to verify every assignment landed.
  assert.deepEqual(transport.callLog, [
    "create_trip",
    "get_trip_summary",
    "create_and_assign_place",
    "update_assignment_time",
    "create_and_assign_place",
    "update_assignment_time",
    "reorder_day_assignments",
    "get_trip_summary",
  ]);
});

test("end to end: private share mode never creates a share link", async () => {
  const { request } = buildTrekPlanningRequest({
    requestId,
    shareMode: "private",
    trip,
    stops: [stop()],
  });

  const transport = new TrekStubTransport(projectedDayCount(request));
  const receipt = await new TrekPlanningAdapter(transport).execute(request);

  assert.equal(receipt.shareCreated, false);
  assert.ok(!transport.callLog.includes("create_share_link"));
});
