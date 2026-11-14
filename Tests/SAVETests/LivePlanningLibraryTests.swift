#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LivePlanningLibraryTests: XCTestCase {
    func testOnlyCurrentPendingCandidatesAppearAndResolvedRowsCannotReopen() {
        let review = candidate(status: "review")
        let needsEvidence = candidate(status: "needs_more_evidence")
        let source = candidate(status: "source_only")
        let terminal = ["saved", "confirmed", "rejected", "superseded", "unknown"].map { candidate(status: $0) }
        var replaced = candidate(status: "review")
        replaced.supersededByCandidateID = review.id
        var replacedByMany = candidate(status: "source_only")
        replacedByMany.supersededByCandidateIDs = [review.id, source.id]
        let pending = [review, needsEvidence, source]
        let projection = LiveLibraryReviewProjection(candidates: pending + terminal + [replaced, replacedByMany],
                                                      batchIDs: nil, query: "")
        XCTAssertEqual(Set(projection.matches.map(\.id)), Set(pending.map(\.id)))
        for resolved in terminal + [replaced, replacedByMany] {
            XCTAssertFalse(LiveLibraryReviewProjection.isPending(resolved))
        }
    }

    func testBatchOnlyFiltersPendingAndShowAllRestoresOlderClues() {
        let older = candidate(name: "Earlier clue", age: 20)
        let first = candidate(name: "First new clue", age: 2)
        let second = candidate(name: "Second new clue", age: 1)
        let all = [older, first, second]
        let batch = LiveLibraryReviewProjection(candidates: all, batchIDs: [first.id, second.id], query: "")
        XCTAssertEqual(batch.eligible.count, 3, "Batch is a presentation filter, never removal of retained clues")
        XCTAssertEqual(batch.matches.map(\.id), [second.id, first.id])
        XCTAssertNil(batch.emptyState)
        let cleared = LiveLibraryReviewProjection(candidates: all, batchIDs: nil, query: "")
        XCTAssertEqual(cleared.matches.map(\.id), [second.id, first.id, older.id])
        let emptySelection = LiveLibraryReviewProjection(candidates: all, batchIDs: [], query: "")
        XCTAssertTrue(emptySelection.matches.isEmpty)
        XCTAssertEqual(emptySelection.emptyState, .batchReviewed)
        XCTAssertEqual(emptySelection.eligible.count, 3)
    }

    func testSearchUsesOnlyNameAndAddressAndDoesNotSurfaceCaptionOrSourceHandleMatches() {
        let named = candidate(name: "Fixture Coffee", address: "Harbor Street")
        let addressed = candidate(name: "Fixture Bakery", address: "Coffee Road")
        var proseOnly = candidate(name: "Different clue", address: "Another street")
        proseOnly.evidence = ["Coffee is mentioned only inside a long imported caption."]
        proseOnly.sourceHandle = "coffee_publisher"
        let projection = LiveLibraryReviewProjection(candidates: [named, addressed, proseOnly], batchIDs: nil,
                                                      query: "  coffee\n")
        XCTAssertEqual(Set(projection.matches.map(\.id)), Set([named.id, addressed.id]))
        let batch = LiveLibraryReviewProjection(candidates: [named, addressed], batchIDs: [named.id], query: "road")
        XCTAssertTrue(batch.matches.isEmpty)
        XCTAssertEqual(batch.emptyState, .noSearchMatches)
        XCTAssertEqual(LiveLibraryReviewProjection(candidates: [named, addressed], batchIDs: [named.id], query: "").matches.map(\.id), [named.id])
    }

    func testStaleAndResolvedBatchHasHonestEmptyStateWhileOtherPendingCluesRemainRecoverable() {
        var resolved = candidate(name: "Now confirmed")
        resolved.status = "confirmed"
        let older = candidate(name: "Still waiting")
        let stale = LiveLibraryReviewProjection(candidates: [resolved, older], batchIDs: [resolved.id, UUID()], query: "")
        XCTAssertEqual(stale.emptyState, .batchReviewed)
        XCTAssertTrue(stale.matches.isEmpty)
        XCTAssertEqual(stale.eligible.map(\.id), [older.id])
        let cleared = LiveLibraryReviewProjection(candidates: [resolved, older], batchIDs: nil, query: "")
        XCTAssertEqual(cleared.matches.map(\.id), [older.id])
        XCTAssertNil(cleared.emptyState)
        XCTAssertEqual(LiveLibraryReviewProjection(candidates: [resolved], batchIDs: nil, query: "").emptyState, .nonePending)
    }

    func testCanonicalNewestFirstOrderingUsesStableIDForEqualDates() {
        let a = candidate(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, age: 1)
        let b = candidate(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, age: 1)
        let latest = candidate(age: 0)
        let projection = LiveLibraryReviewProjection(candidates: [b, latest, a], batchIDs: nil, query: "")
        XCTAssertEqual(projection.matches.map(\.id), [latest.id, a.id, b.id])
    }

    func testStateSeparatesAnalysisSourcePossiblePlaceAndUnplacedWithoutConfirmingAnything() {
        let located = candidate()
        var source = candidate(status: "source_only")
        source.latitude = nil; source.longitude = nil
        var pending = source
        pending.missingInfo = ["Analysis pending"]
        var unplaced = located
        unplaced.missingInfo = [PlaceReviewCandidate.unplacedInboxMarker]
        var unlocatedReview = candidate(status: "needs_more_evidence")
        unlocatedReview.latitude = nil; unlocatedReview.longitude = nil

        XCTAssertEqual(LiveLibraryReviewState(located), .possiblePlace)
        XCTAssertEqual(LiveLibraryReviewState(source), .sourceClue)
        XCTAssertEqual(LiveLibraryReviewState(pending), .analysisPending)
        XCTAssertEqual(LiveLibraryReviewState(unplaced), .unplaced)
        XCTAssertEqual(LiveLibraryReviewState(unlocatedReview), .sourceClue)
        XCTAssertTrue(LiveLibraryReviewProjection.isPending(unplaced), "Located Unplaced is retained until explicit recovery")
        XCTAssertEqual(unplaced.status, "review")
        XCTAssertEqual(located.status, "review")
    }

    private func candidate(id: UUID = UUID(), name: String = "Fixture clue", address: String = "1 Fixture Street",
                           status: String = "review", age: TimeInterval = 0) -> PlaceReviewCandidate {
        PlaceReviewCandidate(id: id, captureId: nil, name: name, address: address, city: nil,
            latitude: 25.03, longitude: 121.54, evidence: [], confidence: 0.7, missingInfo: [],
            status: status, createdAt: Date(timeIntervalSince1970: 1_800_000_000 - age))
    }
}
#endif
