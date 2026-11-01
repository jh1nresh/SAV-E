import assert from "node:assert/strict";
import test from "node:test";
import {
  InkVisitContractError,
  normalizeInkVisit,
  rankInkFriendVisits,
} from "./inkVisitContract.js";

test("ink visit rejects coordinates and defaults to public", () => {
  const visit = normalizeInkVisit({
    placeId: "dingtai",
    visitedAt: "2026-11-01T04:00:00.000Z",
    verification: "verified",
    comment: "  小籠包  ",
  });
  assert.deepEqual(visit, {
    placeId: "dingtai",
    visitedAt: "2026-11-01T04:00:00.000Z",
    verification: "verified",
    visibility: "public",
    comment: "小籠包",
  });
  assert.throws(
    () =>
      normalizeInkVisit({
        placeId: "dingtai",
        visitedAt: "2026-11-01T04:00:00.000Z",
        verification: "verified",
        latitude: 25.03,
      }),
    InkVisitContractError,
  );
});

test("friend ranking counts only public verified visits", () => {
  const cards = rankInkFriendVisits([
    visit("old", "place", "2026-10-28T00:00:00.000Z", "verified", "public"),
    visit("old", "place", "2026-10-29T00:00:00.000Z", "verified", "public"),
    visit("new", "place", "2026-10-30T00:00:00.000Z", "verified", "public"),
    visit("new", "place", "2026-10-31T00:00:00.000Z", "verified", "public"),
    visit("many", "place", "2026-10-01T00:00:00.000Z", "verified", "public"),
    visit("many", "place", "2026-10-02T00:00:00.000Z", "verified", "public"),
    visit("many", "place", "2026-10-03T00:00:00.000Z", "verified", "public"),
    visit("hidden", "place", "2026-11-01T00:00:00.000Z", "verified", "private"),
    visit("gray", "place", "2026-11-01T00:00:00.000Z", "unverified", "public"),
  ]);
  assert.deepEqual(
    cards.map((card) => [card.authorId, card.verifiedCount, card.segment]),
    [
      ["many", 3, "verified"],
      ["new", 2, "verified"],
      ["old", 2, "verified"],
      ["gray", 0, "unverified"],
    ],
  );
});

function visit(
  authorId: string,
  placeId: string,
  visitedAt: string,
  verification: "verified" | "unverified",
  visibility: "public" | "private",
) {
  return { authorId, placeId, visitedAt, verification, visibility };
}
