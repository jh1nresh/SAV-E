import XCTest
@testable import SAVE

final class SaveLocalVaultServiceTests: XCTestCase {
    @MainActor
    func testConfirmedPlaceSaveUpsertsMatchingVenueInsteadOfAppendingDuplicate() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save-memory-records.json")
        let service = SaveLocalVaultService(overrideVaultURL: vaultURL)

        let first = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District",
            googlePlaceId: "ChIJ-sav-e-test"
        )
        let resaved = makePlace(
            id: UUID(),
            name: "隱室無名滷肉飯 中山店",
            address: "103, Taiwan, Taipei City, Datong District, Lane 33",
            googlePlaceId: "ChIJ-sav-e-test"
        )

        _ = try service.saveConfirmedPlace(first)
        _ = try service.saveConfirmedPlace(resaved)

        let places = try service.confirmedPlaces(limit: 10)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.address, resaved.address)
    }

    @MainActor
    func testRepeatedSavePreservesBothSourcesAndOldTripIDAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let service = SaveLocalVaultService(overrideVaultURL: url)
        var first = makePlace(id: UUID(), name: "Cafe", address: "Taipei", googlePlaceId: "venue")
        first.sourceUrl = "https://example.com/first"
        first.note = "From a friend"
        var second = makePlace(id: UUID(), name: "Cafe", address: "Taipei", googlePlaceId: "venue")
        second.sourceUrl = "https://example.com/second"
        second.note = "From a guide"
        _ = try service.saveConfirmedPlace(first)
        _ = try service.saveConfirmedPlace(second)
        let reloaded = try SaveLocalVaultService(overrideVaultURL: url).confirmedPlaces()
        XCTAssertEqual(reloaded.count, 1)
        let merged = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(merged.savedIDs, [first.id, second.id])
        XCTAssertTrue(merged.sourceEvidence.contains("Source URL: https://example.com/first"))
        XCTAssertTrue(merged.sourceEvidence.contains("Source URL: https://example.com/second"))
        XCTAssertTrue(merged.sourceEvidence.contains("From a friend"))
        XCTAssertTrue(merged.sourceEvidence.contains("From a guide"))
    }

    @MainActor
    func testSameRecordEditCanClearNotesAndVisitedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var original = makePlace(id: UUID(), name: "Cafe", address: "Taipei", googlePlaceId: "venue")
        original.note = "Old note"
        original.status = .visited
        _ = try service.saveConfirmedPlace(original)
        var edited = original
        edited.note = nil
        edited.status = .wantToGo
        _ = try service.saveConfirmedPlace(edited)
        let stored = try XCTUnwrap(service.confirmedPlaces().first)
        XCTAssertNil(stored.note)
        XCTAssertEqual(stored.status, .wantToGo)
    }

    @MainActor
    func testMissingVaultReadsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )

        XCTAssertTrue(try service.recentRecords().isEmpty)
    }

    @MainActor
    func testConfirmedPlaceKeepsCanonicalIdentityAndRemovalClearsProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )
        let place = makePlace(id: UUID(), name: "Memory Cafe", address: "1 Test Way", googlePlaceId: nil)

        _ = try service.saveConfirmedPlace(place)
        XCTAssertEqual(try service.confirmedPlaces().first?.id, place.id)

        try service.removeConfirmedPlace(place)
        XCTAssertTrue(try service.confirmedPlaces().isEmpty)
    }

    @MainActor
    func testDeleteAllRecordsClearsEveryLocalMemoryState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
        )

        _ = try service.saveSourceOnly(url: URL(string: "https://example.com/place")!)
        _ = try service.saveConfirmedPlace(
            makePlace(id: UUID(), name: "Memory Cafe", address: "1 Test Way", googlePlaceId: nil)
        )

        try service.deleteAllRecords()

        XCTAssertTrue(try service.recentRecords().isEmpty)
        XCTAssertTrue(try service.confirmedPlaces().isEmpty)
        XCTAssertTrue(try service.reviewCandidates().isEmpty)
    }

    @MainActor
    func testPendingRefinementUpdatesPreservedRecordWithoutMergingDistinctCandidates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let service = SaveLocalVaultService(overrideVaultURL: url)
        let id = UUID()
        let pending = makePendingCandidate(localID: id)
        let original = try service.saveReviewCandidate(pending, recordID: id, preservingExisting: true)
        XCTAssertEqual(original.state, .sourceOnly)

        var refined = pending
        refined.isSourceOnly = false
        refined.candidateName = "Resolved Cafe"
        refined.address = "1 Test Way"
        refined.latitude = 25.051
        refined.longitude = 121.519
        _ = try service.saveReviewCandidate(refined, recordID: id)

        let reloaded = SaveLocalVaultService(overrideVaultURL: url)
        let records = try reloaded.recentRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, original.id)
        XCTAssertEqual(records.first?.state, .reviewCandidate)
        XCTAssertEqual(records.first?.address, "1 Test Way")
        XCTAssertEqual(records.first?.sourceText, pending.sourceText)
        XCTAssertTrue(try reloaded.confirmedPlaces().isEmpty)

        let otherID = UUID()
        _ = try reloaded.saveReviewCandidate(makePendingCandidate(localID: otherID), recordID: otherID, preservingExisting: true)
        XCTAssertEqual(try reloaded.recentRecords().count, 2, "Distinct pending candidates from the same source must stay distinct")
    }

    @MainActor
    func testPendingQueueRetryKeepsOneRecordAndRetainsAlreadyRefinedEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let service = SaveLocalVaultService(overrideVaultURL: url)
        let pending = makePendingCandidate(localID: UUID())
        let id = try XCTUnwrap(pending.localVaultRecordID)
        _ = try service.saveReviewCandidate(pending, recordID: id, preservingExisting: true)

        // Analysis failed before refinement. Restoring/reloading the pending queue retains its local ID.
        let queue = try JSONEncoder().encode([pending])
        let retry = try XCTUnwrap(JSONDecoder().decode([PendingReviewCandidate].self, from: queue).first)
        XCTAssertEqual(retry.localVaultRecordID, id)
        let restarted = SaveLocalVaultService(overrideVaultURL: url)
        _ = try restarted.saveReviewCandidate(retry, recordID: id, preservingExisting: true)
        XCTAssertEqual(try restarted.recentRecords().count, 1)

        var refined = retry
        refined.candidateName = "Resolved Cafe"
        refined.evidence.append("Refined source evidence")
        refined.isSourceOnly = false
        _ = try restarted.saveReviewCandidate(refined, recordID: id)

        // Remote persistence failed after refinement; another retry must not discard the richer record.
        let next = SaveLocalVaultService(overrideVaultURL: url)
        let preserved = try next.saveReviewCandidate(retry, recordID: id, preservingExisting: true)
        XCTAssertEqual(preserved.title, "Resolved Cafe")
        XCTAssertTrue(preserved.evidence.contains("Refined source evidence"))
        _ = try next.saveReviewCandidate(refined, recordID: id)
        XCTAssertEqual(try next.recentRecords().count, 1)
        XCTAssertEqual(try next.recentRecords().first?.id, id)
        XCTAssertEqual(try next.reviewCandidates().count, 1)
    }

    @MainActor
    func testFailedRefinementAfterRemoteFailureCannotReplaceStrongerCandidate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let service = SaveLocalVaultService(overrideVaultURL: url)
        let id = UUID()
        let original = makePendingCandidate(localID: id)
        _ = try service.saveReviewCandidate(original, recordID: id, preservingExisting: true)
        var refined = original
        refined.isSourceOnly = false
        refined.candidateName = "Resolved North Branch"
        refined.address = "1 North Street"
        refined.latitude = 25.051
        refined.longitude = 121.519
        refined.evidence = ["North branch address and location evidence"]
        let stronger = try service.saveReviewCandidate(refined, recordID: id)

        // The remote write failed. Queue persistence must retain the refined payload and local ID.
        let failedQueue = try JSONEncoder().encode([refined])
        let retry = try XCTUnwrap(JSONDecoder().decode([PendingReviewCandidate].self, from: failedQueue).first)
        XCTAssertEqual(retry.localVaultRecordID, id)
        XCTAssertEqual(retry.latitude, refined.latitude)
        XCTAssertEqual(retry.evidence, refined.evidence)

        let restarted = SaveLocalVaultService(overrideVaultURL: url)
        _ = try restarted.saveReviewCandidate(retry, recordID: id, preservingExisting: true)
        // A provider failure returns only a thin clue; exercise the actual refinement upsert,
        // including a review-shaped result with no reliable coordinates.
        for sourceOnly in [true, false] {
            var failedRefinement = original
            failedRefinement.isSourceOnly = sourceOnly
            failedRefinement.candidateName = "Unresolved South Branch"
            failedRefinement.address = "South area"
            failedRefinement.evidence = ["Incomplete lookup"]
            let result = try restarted.saveReviewCandidate(failedRefinement, recordID: id)
            XCTAssertEqual(result, stronger)
        }
        let finalRecords = try SaveLocalVaultService(overrideVaultURL: url).recentRecords()
        XCTAssertEqual(finalRecords, [stronger])
        XCTAssertEqual(finalRecords.first?.latitude, refined.latitude)
        XCTAssertEqual(finalRecords.first?.longitude, refined.longitude)
        XCTAssertEqual(finalRecords.first?.evidence, refined.evidence)
        XCTAssertTrue(try restarted.confirmedPlaces().isEmpty)
    }

    @MainActor
    func testPendingRetryCannotDowngradeUserConfirmedMapStamp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let id = UUID()
        let pending = makePendingCandidate(localID: id)
        _ = try service.saveReviewCandidate(pending, recordID: id, preservingExisting: true)
        try service.removeReviewCandidate(id)
        _ = try service.saveConfirmedPlace(makePlace(id: id, name: "User confirmed Cafe", address: "2 Correct Way", googlePlaceId: nil))

        _ = try service.saveReviewCandidate(pending, recordID: id, preservingExisting: true)
        _ = try service.saveReviewCandidate(pending, recordID: id)
        let records = try service.recentRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.state, .confirmedPlace)
        XCTAssertEqual(records.first?.title, "User confirmed Cafe")
        XCTAssertEqual(records.first?.address, "2 Correct Way")
        XCTAssertTrue(try service.reviewCandidates().isEmpty)
    }

    @MainActor
    func testOlderPendingQueueWithoutLocalRecordIdentityStillDecodes() throws {
        let original = makePendingCandidate(localID: nil)
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["localVaultRecordID"])
        let decoded = try JSONDecoder().decode(PendingReviewCandidate.self, from: data)
        XCTAssertNil(decoded.localVaultRecordID)
        XCTAssertEqual(decoded.sourceURL, original.sourceURL)
    }

    @MainActor
    private func makePendingCandidate(localID: UUID?) -> PendingReviewCandidate {
        PendingReviewCandidate(candidateName: "Source clue", address: "", category: "food",
            sourceURL: "https://example.com/shared-post", sourceText: "Original caption",
            evidence: ["Original source clue"], confidence: 0, missingInfo: ["Exact place"],
            savedAt: Date(timeIntervalSince1970: 1_700_000_000), isSourceOnly: true,
            localVaultRecordID: localID)
    }

    @MainActor
    private func makePlace(
        id: UUID,
        name: String,
        address: String,
        googlePlaceId: String?
    ) -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: 25.051,
            longitude: 121.519,
            googlePlaceId: googlePlaceId,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: "https://instagram.com/p/save-test",
            sourcePlatform: .instagram,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}
