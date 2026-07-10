import XCTest
@testable import SAVE

final class SavePlaceCorrectionEventTests: XCTestCase {
    func testCorrectionActionsMapToExistingWorkflowDecisionContract() {
        XCTAssertEqual(SavePlaceCorrectionEventType.confirmCandidate.workflowAction, "confirm")
        XCTAssertEqual(SavePlaceCorrectionEventType.wrongBranch.workflowAction, "needs_more_evidence")
        XCTAssertEqual(SavePlaceCorrectionEventType.saveSourceOnly.workflowAction, "source_only")
        XCTAssertEqual(SavePlaceCorrectionEventType.mergeExisting.workflowAction, "merge_existing")
        XCTAssertEqual(SavePlaceCorrectionEventType.rejectCandidate.workflowAction, "reject")
        XCTAssertEqual(SavePlaceCorrectionEventType.investigateMore.workflowAction, "investigate_more")
    }

    @MainActor
    func testLegacyCandidateStatusFallbackMirrorsBackendDecisionState() {
        XCTAssertEqual(MapViewModel.legacyCandidateStatus(for: .rejectCandidate, finalPlaceId: nil), "rejected")
        XCTAssertEqual(MapViewModel.legacyCandidateStatus(for: .saveSourceOnly, finalPlaceId: nil), "source_only")
        XCTAssertEqual(MapViewModel.legacyCandidateStatus(for: .investigateMore, finalPlaceId: nil), "needs_more_evidence")
        XCTAssertEqual(MapViewModel.legacyCandidateStatus(for: .confirmCandidate, finalPlaceId: UUID()), "saved")
    }

    func testCorrectionPayloadKeepsBeforeAfterAndLearningLabels() throws {
        let candidate = makeCandidate(status: "review")
        var corrected = candidate
        corrected.address = "456 Correct Branch Ave"
        corrected.city = "Irvine"

        let event = SavePlaceCorrectionEvent(
            userId: "user-1",
            candidate: candidate,
            eventType: .wrongBranch,
            afterSnapshot: SavePlaceCorrectionSnapshot(candidate: corrected),
            userReasonText: "Wrong branch"
        )
        let payload = event.workflowPayload

        XCTAssertEqual(payload["event_type"] as? String, "wrong_branch")
        XCTAssertEqual(payload["source_evidence_tier_before"] as? String, "likely")
        XCTAssertEqual((payload["before_snapshot"] as? [String: Any])?["address"] as? String, candidate.address)
        XCTAssertEqual((payload["after_snapshot"] as? [String: Any])?["address"] as? String, "456 Correct Branch Ave")
        XCTAssertEqual(payload["user_reason_text"] as? String, "Wrong branch")
    }

    func testCorrectionStorePersistsEventsNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json"))
        let candidate = makeCandidate(status: "review")
        let first = SavePlaceCorrectionEvent(
            userId: "user-1",
            candidate: candidate,
            eventType: .investigateMore,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = SavePlaceCorrectionEvent(
            userId: "user-1",
            candidate: candidate,
            eventType: .saveSourceOnly,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try store.append(first)
        try store.append(second)

        XCTAssertEqual(try store.recentEvents().map(\.eventType), [.saveSourceOnly, .investigateMore])
    }

    func testCorrectionStoreDoesNotLoseConcurrentAppends() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavePlaceCorrectionEventStore(overrideURL: directory.appendingPathComponent("corrections.json"))
        let candidate = makeCandidate(status: "review")
        let events = (0..<50).map { index in
            SavePlaceCorrectionEvent(
                userId: "user-\(index)",
                candidate: candidate,
                eventType: .investigateMore
            )
        }
        let errorLock = NSLock()
        var appendErrors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: events.count) { index in
            do {
                try store.append(events[index])
            } catch {
                errorLock.lock()
                appendErrors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(appendErrors.isEmpty)
        XCTAssertEqual(Set(try store.recentEvents(limit: events.count).map(\.id)), Set(events.map(\.id)))
    }

    @MainActor
    func testMapNeverReturnsReviewCandidatesAsDefaultPins() {
        let map = MapViewModel()
        map.reviewCandidates = [makeCandidate(status: "review")]

        XCTAssertTrue(map.reviewCandidatesOnMap.isEmpty)
    }

    private func makeCandidate(status: String) -> PlaceReviewCandidate {
        PlaceReviewCandidate(
            id: UUID(),
            captureId: UUID(),
            workflowRunId: UUID(),
            name: "Candidate Cafe",
            address: "123 Maybe St",
            city: "Tustin",
            latitude: 33.74,
            longitude: -117.82,
            evidence: ["Caption: Candidate Cafe", "Google Places match"],
            confidence: 0.72,
            missingInfo: ["Confirm exact branch"],
            status: status,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
