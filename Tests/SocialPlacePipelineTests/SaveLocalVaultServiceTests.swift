import XCTest
@testable import SAVE

final class SaveLocalVaultServiceTests: XCTestCase {
    @MainActor
    func testRepeatedThinNamedCandidateKeepsVerifiedLocationAndAddedEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var pending = makePendingCandidate(localID: UUID())
        pending.isSourceOnly = false
        pending.candidateName = "Cafe"
        pending.address = "1 Test Way"
        pending.latitude = 25.05
        pending.longitude = 121.51
        let original = try vault.saveReviewCandidate(pending)
        pending.latitude = nil
        pending.longitude = nil
        pending.evidence += ["Second caption"]
        let repeated = try vault.saveReviewCandidate(pending)
        XCTAssertEqual(repeated.id, original.id)
        XCTAssertEqual(repeated.latitude, original.latitude)
        XCTAssertEqual(repeated.longitude, original.longitude)
        XCTAssertTrue(repeated.evidence.contains("Second caption"))
        XCTAssertEqual(try vault.reviewCandidates().first?.latitude, original.latitude)
    }

    @MainActor
    func testRepeatedSourceSurvivesReloadAsOneClueWithBothNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let first = try vault.saveSourceOnly(url: URL(string: "https://example.com/post?id=1")!, note: "First clue")
        let second = try vault.saveSourceOnly(url: URL(string: "https://example.com/post?utm_source=ig&id=1")!, note: "More context")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.createdAt.timeIntervalSince1970, second.createdAt.timeIntervalSince1970, accuracy: 1)
        let reloaded = SaveLocalVaultService(overrideVaultURL: url)
        XCTAssertEqual(try reloaded.recentRecords().count, 1)
        XCTAssertEqual(try reloaded.reviewCandidates().count, 1)
        XCTAssertTrue(try XCTUnwrap(reloaded.recentRecords().first?.sourceText).contains("First clue"))
        XCTAssertTrue(try XCTUnwrap(reloaded.recentRecords().first?.sourceText).contains("More context"))
    }

    @MainActor
    func testNamedCandidateRepeatUpsertsButAnotherVenueInPostRemainsSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var pending = makePendingCandidate(localID: UUID())
        pending.isSourceOnly = false
        pending.candidateName = "Cafe"
        pending.address = "1 Test Way"
        let original = try vault.saveReviewCandidate(pending)
        pending.savedAt = original.createdAt.addingTimeInterval(100)
        pending.evidence += ["Additional source evidence"]
        let repeated = try vault.saveReviewCandidate(pending)
        XCTAssertEqual(repeated.id, original.id)
        XCTAssertEqual(repeated.createdAt, original.createdAt)
        XCTAssertTrue(repeated.evidence.contains("Additional source evidence"))
        pending.candidateName = "Museum"
        _ = try vault.saveReviewCandidate(pending)
        XCTAssertEqual(try vault.reviewCandidates().count, 2)
    }

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

    /// D3 / P1 4345427432: deleting A's stamp must not erase B's matching venue.
    @MainActor
    func testRemoveConfirmedPlaceKeepsAnotherAccountMatchingVenue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let ownerA = makePlace(
            id: UUID(),
            name: "Harbor Cafe",
            address: "1 Harbor Way",
            googlePlaceId: "ChIJ-shared-harbor"
        )
        let ownerB = makePlace(
            id: UUID(),
            name: "Harbor Cafe",
            address: "1 Harbor Way",
            googlePlaceId: "ChIJ-shared-harbor"
        )
        _ = try vault.saveConfirmedPlace(ownerA, ownerSubject: "did:privy:a")
        _ = try vault.saveConfirmedPlace(ownerB, ownerSubject: "did:privy:b")
        XCTAssertEqual(try vault.confirmedPlaces(belongingTo: "did:privy:a").count, 1)
        XCTAssertEqual(try vault.confirmedPlaces(belongingTo: "did:privy:b").count, 1)

        try vault.removeConfirmedPlace(ownerA, belongingTo: "did:privy:a")

        XCTAssertTrue(try vault.confirmedPlaces(belongingTo: "did:privy:a").isEmpty)
        let remaining = try vault.confirmedPlaces(belongingTo: "did:privy:b")
        XCTAssertEqual(remaining.count, 1, "account B must keep the shared-venue stamp after A deletes")
        XCTAssertEqual(remaining.first?.id, ownerB.id)
        XCTAssertEqual(remaining.first?.googlePlaceId, "ChIJ-shared-harbor")
    }

    /// P1 4366239481: replacing a signed-in confirmed row must not delete an
    /// ownerless pre-upgrade mirror that shares the same ID.
    @MainActor
    func testSaveConfirmedPlaceDoesNotReplaceOwnerlessConfirmedMirror() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let sharedID = UUID()
        var ownerless = makePlace(
            id: sharedID,
            name: "Harbor Cafe",
            address: "1 Harbor Way",
            googlePlaceId: "ChIJ-ownerless-harbor"
        )
        ownerless.note = "Legacy private note"
        _ = try vault.saveConfirmedPlace(ownerless)
        var signedIn = makePlace(
            id: sharedID,
            name: "Harbor Cafe",
            address: "1 Harbor Way",
            googlePlaceId: "ChIJ-ownerless-harbor"
        )
        signedIn.note = "Signed-in edit"
        _ = try vault.saveConfirmedPlace(signedIn, ownerSubject: "did:privy:a")

        let records = try vault.confirmedPlaceRecords()
        let legacy = try XCTUnwrap(records.first { $0.ownerSubject == nil })
        XCTAssertEqual(legacy.id, sharedID)
        XCTAssertEqual(legacy.sourceText, "Legacy private note")
        XCTAssertTrue(legacy.evidence.contains("Legacy private note"))
        let owned = try XCTUnwrap(records.first { $0.ownerSubject == "did:privy:a" })
        XCTAssertEqual(owned.id, sharedID)
        XCTAssertEqual(owned.sourceText, "Signed-in edit")
        XCTAssertEqual(records.count, 2, "ownerless and signed-in confirmed rows must both remain")
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
        XCTAssertEqual(finalRecords.first?.evidence, stronger.evidence)
        XCTAssertTrue(stronger.evidence.contains("Original source clue"))
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
        // Confirmation requires a review candidate with a reliable location, not a source-only clue.
        var refined = pending
        refined.isSourceOnly = false
        refined.latitude = 25.051
        refined.longitude = 121.519
        _ = try service.saveReviewCandidate(refined, recordID: id)
        XCTAssertEqual(try service.reviewCandidates().count, 1)

        // Match the local confirmation flow: save the Map Stamp, then retire its review candidate.
        _ = try service.saveConfirmedPlace(makePlace(id: id, name: "User confirmed Cafe", address: "2 Correct Way", googlePlaceId: nil))
        try service.removeReviewCandidate(id)
        XCTAssertEqual(try service.recentRecords().count, 1, "Confirmation must finish before exercising the retry")

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
    func testReviewMergeKeepsExistingSourceHandleWhenIncomingOmitsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var seeded = makePendingCandidate(localID: UUID())
        seeded.isSourceOnly = false
        seeded.candidateName = "Harbor Oven Pizza"
        seeded.address = "Berth 73, San Pedro, Los Angeles, CA 90731"
        seeded.latitude = 33.7405
        seeded.longitude = -118.2807
        seeded.sourceURL = "https://www.instagram.com/p/harborovenpizza/"
        seeded.sourceHandle = "la.harbor.eats"
        seeded.evidence += ["Creator handle: @la.harbor.eats"]
        let original = try vault.saveReviewCandidate(seeded)

        var incoming = seeded
        incoming.sourceHandle = nil
        incoming.evidence += [
            "Source URL: https://www.google.com/maps/place/Harbor+Oven+Pizza/@33.7405,-118.2807,17z/data=!3m1"
        ]
        let merged = try vault.saveReviewCandidate(incoming)
        XCTAssertEqual(merged.id, original.id)
        XCTAssertEqual(merged.sourceHandle, "la.harbor.eats")
        XCTAssertEqual(try vault.reviewCandidates().first?.sourceHandle, "la.harbor.eats")
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
    func testReviewCandidatesKeepOwnerSubjectAndDoNotMergeAcrossAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var ownerA = makePendingCandidate(localID: UUID())
        ownerA.ownerSubject = "did:privy:owner-a"
        ownerA.isSourceOnly = false
        ownerA.candidateName = "Harbor Cafe"
        ownerA.address = "1 Harbor Way"
        ownerA.latitude = 25.05
        ownerA.longitude = 121.51
        let savedA = try vault.saveReviewCandidate(ownerA)

        var ownerB = ownerA
        ownerB.ownerSubject = "did:privy:owner-b"
        ownerB.evidence += ["Account B caption"]
        let savedB = try vault.saveReviewCandidate(ownerB)

        XCTAssertNotEqual(savedA.id, savedB.id)
        let stored = try vault.reviewCandidates()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.ownerSubject == "did:privy:owner-a" }?.name, "Harbor Cafe")
        XCTAssertEqual(stored.first { $0.ownerSubject == "did:privy:owner-b" }?.name, "Harbor Cafe")
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.ownerSubject == "did:privy:owner-a" }).evidence.contains("Account B caption"))
    }

    @MainActor
    func testExactIDUpsertsAndRemovalStayWithinTheOwningAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let sharedID = UUID()
        var a = makePendingCandidate(localID: sharedID)
        a.ownerSubject = "owner-a"
        a.isSourceOnly = false
        a.candidateName = "Cafe A"
        a.latitude = 25
        a.longitude = 121
        let savedA = try vault.saveReviewCandidate(a, recordID: sharedID)
        var b = a
        b.ownerSubject = "owner-b"
        b.candidateName = "Cafe B"
        b.evidence = ["B private clue"]
        let savedB = try vault.saveReviewCandidate(b, recordID: sharedID, preservingExisting: true)
        XCTAssertEqual(savedA.ownerSubject, "owner-a")
        XCTAssertEqual(savedB.ownerSubject, "owner-b")
        XCTAssertEqual(savedB.title, "Cafe B")
        var bReview = try XCTUnwrap(vault.reviewCandidates(belongingTo: "owner-b").first)
        XCTAssertEqual(bReview.id, savedB.id)
        bReview.name = "B refined"
        _ = try vault.saveReviewCandidate(bReview)
        let stored = try vault.reviewCandidates()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.ownerSubject == "owner-a" }?.name, "Cafe A")
        XCTAssertEqual(stored.first { $0.ownerSubject == "owner-b" }?.name, "B refined")
        try vault.removeReviewCandidate(sharedID, ownerSubject: "owner-b")
        XCTAssertEqual(try vault.reviewCandidates().map(\.ownerSubject), ["owner-a"])
    }

    /// D3 / P1 4343590029: AskSaveMemoryIntent must not speak another account's
    /// recent titles. Filter by owner before applying the limit.
    @MainActor
    func testRecentRecordsBelongingToActiveAccountHideOtherOwnersBeforeLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "B older clue", ownerSubject: "did:privy:b"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A newer clue 2", ownerSubject: "did:privy:a"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A newest clue 1", ownerSubject: "did:privy:a"))

        XCTAssertEqual(try vault.recentRecords(limit: 2).map(\.title), ["A newest clue 1", "A newer clue 2"])
        XCTAssertEqual(
            try vault.recentRecords(limit: 2, belongingTo: "did:privy:b").map(\.title),
            ["B older clue"],
            "owner filter must run before prefix so B is not truncated by A's newer rows"
        )
        XCTAssertTrue(try vault.recentRecords(limit: 5, belongingTo: "did:privy:a").allSatisfy { $0.ownerSubject == "did:privy:a" })
        XCTAssertTrue(try vault.recentRecords(limit: 5, belongingTo: "did:privy:missing").isEmpty)
        XCTAssertTrue(try vault.recentRecords(limit: 5, belongingTo: nil).isEmpty, "signed-in scope with nil owner hides stamped rows")
    }

    /// D3 / P1 4347594673: Memory & Preferences must hide the previous owner.
    @MainActor
    func testMemoryInspectorShowsOnlyTheCurrentOwnerRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(
            state: .confirmedPlace,
            title: "A Harbor Cafe",
            address: "1 Harbor Way",
            evidence: ["Source URL: https://example.com/a"],
            ownerSubject: "did:privy:a"
        ))
        try vault.append(SaveMemoryRecord(
            state: .sourceOnly,
            title: "B secret clue",
            address: "9 Private Road",
            evidence: ["Source URL: https://example.com/b"],
            ownerSubject: "did:privy:b"
        ))

        let visibleToB = try SaveMemoryInspector.records(in: vault, belongingTo: "did:privy:b")
        XCTAssertEqual(visibleToB.map(\.title), ["B secret clue"])
        XCTAssertEqual(visibleToB.first?.address, "9 Private Road")
        XCTAssertFalse(visibleToB.contains { $0.ownerSubject == "did:privy:a" })
        XCTAssertEqual(
            try SaveMemoryInspector.records(in: vault, belongingTo: "did:privy:a").map(\.title),
            ["A Harbor Cafe"]
        )
        XCTAssertTrue(
            try SaveMemoryInspector.records(in: vault, belongingTo: nil).isEmpty,
            "signed-in inspector with no owner must not dump the shared vault"
        )
    }

    /// D3 / P1 4347594680: deleting B must not erase A's shared-device rows.
    @MainActor
    func testDeleteRecordsBelongingToOwnerLeavesOtherAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "did:privy:a"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "did:privy:b"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Ownerless clue"))

        try vault.deleteRecords(belongingTo: "did:privy:b")

        let remaining = try vault.recentRecords(limit: 10)
        XCTAssertEqual(Set(remaining.compactMap(\.title)), ["A clue", "Ownerless clue"])
        XCTAssertFalse(remaining.contains { $0.ownerSubject == "did:privy:b" })
    }

    @MainActor
    func testExplicitLocalDecisionCannotMintOrMutateStaleForeignConfirmedOrQuarantinedRows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        var candidate = PlaceReviewCandidate(id: UUID(), captureId: nil, name: "Local clue", address: "1 Road", city: "Taipei",
            latitude: 25, longitude: 121, evidence: ["Original source clue"], confidence: 0.6,
            missingInfo: ["Analysis pending"], status: "source_only", createdAt: Date(), ownerSubject: "account-a")
        try vault.append(SaveMemoryRecord(id: candidate.id, state: .reviewCandidate, sourceText: "Original private input",
            title: candidate.name, ownerSubject: "account-a"))
        let before = try Data(contentsOf: url)
        let original = candidate
        for failure in ["absent", "foreign", "remote", "invalid-status"] {
            candidate = original
            if failure == "absent" { candidate.id = UUID() }
            if failure == "foreign" { candidate.ownerSubject = "account-b" }
            if failure == "remote" { candidate.captureId = UUID() }
            if failure == "invalid-status" { candidate.status = "saved" }
            XCTAssertThrowsError(try vault.saveLocalReviewDecision(candidate))
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
        candidate = original
        _ = try vault.prepareAccountDeletion(belongingTo: "account-a")
        XCTAssertThrowsError(try vault.saveLocalReviewDecision(candidate))
        XCTAssertEqual(try Data(contentsOf: url), before)
        let intent = try XCTUnwrap(vault.pendingAccountDeletionIntent())
        try vault.completeAccountDeletionCleanup(intentID: intent.id)
        try vault.append(SaveMemoryRecord(id: candidate.id, state: .confirmedPlace, title: "Confirmed stamp", ownerSubject: "account-a"))
        let confirmed = try Data(contentsOf: url)
        XCTAssertThrowsError(try vault.saveLocalReviewDecision(candidate))
        XCTAssertEqual(try Data(contentsOf: url), confirmed)
        XCTAssertTrue(try vault.reviewCandidates().isEmpty)
    }

    @MainActor
    func testDurableDeletionIntentQuarantinesExactScopeAcrossReloadAndPreservesNewRows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let old = SaveMemoryRecord(state: .confirmedPlace, sourceText: "Private note", title: "Legacy name", latitude: 25, longitude: 121)
        let a = SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a")
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        for row in [old, a, b] { try vault.append(row) }
        let rawBefore = try Data(contentsOf: url)
        let intent = try vault.prepareAccountDeletion(belongingTo: "account-a")
        XCTAssertEqual(try Data(contentsOf: url), rawBefore, "Intent must not discard recoverable payload")
        XCTAssertEqual(intent.initialOwnerlessRecordIDs, [old.id])
        let later = SaveMemoryRecord(state: .sourceOnly, title: "Later ownerless")
        try vault.append(later)
        let reloaded = SaveLocalVaultService(overrideVaultURL: url)
        XCTAssertEqual(try reloaded.pendingAccountDeletionIntent(), intent)
        XCTAssertEqual(Set(try reloaded.recentRecords().map(\.id)), [b.id, later.id])
        XCTAssertEqual(try reloaded.recentRecords(belongingTo: nil).map(\.id), [later.id])
        XCTAssertTrue(try reloaded.confirmedPlaces(belongingTo: nil).isEmpty)
        XCTAssertTrue(try reloaded.confirmedPlaceRecords().isEmpty)
        XCTAssertTrue(try reloaded.reviewCandidates(belongingTo: "account-a").isEmpty)
        XCTAssertThrowsError(try reloaded.prepareAccountDeletion(belongingTo: "account-b"))
        try reloaded.purgeAccountDeletionRecords(intentID: intent.id)
        XCTAssertNotNil(try reloaded.pendingAccountDeletionIntent(), "Purge alone must not clear avatar cleanup intent")
        // Cross-process append between purge and completion is included for A only.
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Late A", ownerSubject: "account-a"))
        try reloaded.completeAccountDeletionCleanup(intentID: intent.id)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertEqual(Set(try vault.recentRecords().map(\.id)), [b.id, later.id])
    }

    @MainActor
    func testCorruptDeletionReceiptFailsClosedAndOldIDsCannotModifyNewIntent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Private legacy clue"))
        let first = try vault.prepareAccountDeletion(belongingTo: "account-a")
        let receiptURL = url.appendingPathExtension("account-deletion.json")
        let receipt = try Data(contentsOf: receiptURL)
        try Data("corrupt".utf8).write(to: receiptURL, options: .atomic)
        let fresh = SaveLocalVaultService(overrideVaultURL: url)
        XCTAssertThrowsError(try fresh.recentRecords())
        XCTAssertThrowsError(try fresh.reviewCandidates())
        XCTAssertThrowsError(try fresh.confirmedPlaces())
        XCTAssertThrowsError(try fresh.confirmedPlaceRecords())
        XCTAssertThrowsError(try fresh.purgeAccountDeletionRecords(intentID: first.id))
        try receipt.write(to: receiptURL, options: .atomic)
        try fresh.purgeAccountDeletionRecords(intentID: first.id)
        try fresh.completeAccountDeletionCleanup(intentID: first.id)
        let second = try fresh.prepareAccountDeletion(belongingTo: "account-b")
        XCTAssertThrowsError(try vault.recordRemoteAccountDeletionSuccess(intentID: first.id))
        XCTAssertThrowsError(try vault.purgeAccountDeletionRecords(intentID: first.id))
        XCTAssertThrowsError(try vault.completeAccountDeletionCleanup(intentID: first.id))
        XCTAssertEqual(try fresh.pendingAccountDeletionIntent(), second)
    }

    @MainActor
    func testAccountDeletionPurgesLegacySnapshotWithoutClaimingOrDeletingOtherOwners() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("vault.json")
        // The old on-disk schema has no ownerSubject key, not an assigned account.
        let legacyIDs = (0..<30).map { _ in UUID() }
        let legacyRows: [[String: Any]] = legacyIDs.enumerated().map { index, id in
            ["id": id.uuidString, "state": index == 0 ? "confirmed_place" : "source_only",
             "title": "Legacy private name \(index)", "sourceText": "Legacy private note \(index)",
             "evidence": ["Legacy private clue \(index)"], "createdAt": "2026-01-01T00:00:00Z"]
        }
        try JSONSerialization.data(withJSONObject: legacyRows).write(to: url)
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let a = SaveMemoryRecord(state: .sourceOnly, title: "A private clue", ownerSubject: "account-a")
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B private clue", ownerSubject: "account-b")
        try vault.append(a)
        try vault.append(b)
        let snapshot = try vault.ownerlessRecordIDsForAccountDeletion()
        XCTAssertEqual(snapshot, Set(legacyIDs), "Snapshot must not use the 25-row UI limit")
        XCTAssertEqual(try vault.recentRecords(limit: 100, belongingTo: nil).count, 30)
        XCTAssertEqual(try vault.recentRecords(belongingTo: "account-a").map(\.id), [a.id])

        // Simulate an independently proven stamp arriving after the snapshot.
        // Deletion must recheck the current row, not delete IDs indiscriminately.
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let stampedIndex = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == legacyIDs[0].uuidString })
        rows[stampedIndex]["ownerSubject"] = "account-b"
        try JSONSerialization.data(withJSONObject: rows).write(to: url, options: .atomic)
        let later = SaveMemoryRecord(state: .sourceOnly, sourceText: "Later note", title: "Later ownerless clue")
        try vault.append(later)

        try vault.deleteAccountRecords(belongingTo: "account-a", initialOwnerlessRecordIDs: snapshot)

        let reloaded = SaveLocalVaultService(overrideVaultURL: url)
        XCTAssertEqual(Set(try reloaded.recentRecords(limit: 100).map(\.id)), [b.id, legacyIDs[0], later.id])
        XCTAssertEqual(try reloaded.recentRecords(belongingTo: nil).map(\.id), [later.id])
        XCTAssertEqual(Set(try reloaded.recentRecords(belongingTo: "account-b").map(\.id)), [b.id, legacyIDs[0]])
        XCTAssertTrue(try reloaded.recentRecords(belongingTo: "account-a").isEmpty)
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let signedOutMessageRows = persisted.filter {
            SaveVaultOwnerScope.belongsToActiveAccount($0["ownerSubject"] as? String, currentUserId: nil)
        }
        XCTAssertEqual(signedOutMessageRows.compactMap { $0["id"] as? String }, [later.id.uuidString])
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("Legacy private note 1\""))
        // The operation is locally idempotent; retry preserves later ownerless data.
        try reloaded.deleteAccountRecords(belongingTo: "account-a", initialOwnerlessRecordIDs: snapshot)
        XCTAssertEqual(try reloaded.recentRecords(belongingTo: nil).map(\.id), [later.id])
    }

    /// D3 / P2 4343590036: Review 500-row cap is per account, not the shared file.
    @MainActor
    func testReviewCandidatesBelongingToActiveAccountFilterBeforeLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        try vault.append(SaveMemoryRecord(
            state: .reviewCandidate,
            title: "B older review",
            createdAt: older,
            ownerSubject: "did:privy:b"
        ))
        try vault.append(SaveMemoryRecord(
            state: .reviewCandidate,
            title: "A newer review",
            createdAt: newer,
            ownerSubject: "did:privy:a"
        ))
        try vault.append(SaveMemoryRecord(
            state: .reviewCandidate,
            title: "A newest review",
            createdAt: newer.addingTimeInterval(10),
            ownerSubject: "did:privy:a"
        ))

        XCTAssertEqual(
            try vault.reviewCandidates(limit: 2, belongingTo: "did:privy:b").map(\.name),
            ["B older review"],
            "owner filter must run before the Review limit so B survives A's newer rows"
        )
        XCTAssertEqual(
            try vault.reviewCandidates(limit: 2, belongingTo: "did:privy:a").map(\.name),
            ["A newest review", "A newer review"]
        )
    }

    /// D3 / P1 4344606407: iMessage decodes this JSON; ownerSubject must be present
    /// so `MessagesVaultReader` can apply `SaveVaultOwnerScope`.
    @MainActor
    func testPersistedVaultJSONIncludesOwnerSubjectForIMessageReads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(
            state: .confirmedPlace,
            title: "A Cafe",
            placeName: "A Cafe",
            latitude: 25.03,
            longitude: 121.56,
            ownerSubject: "did:privy:a"
        ))
        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        )
        XCTAssertEqual(rows.first?["ownerSubject"] as? String, "did:privy:a")
        XCTAssertEqual(rows.first?["state"] as? String, "confirmed_place")
        XCTAssertFalse(
            SaveVaultOwnerScope.belongsToActiveAccount(
                rows.first?["ownerSubject"] as? String,
                currentUserId: "did:privy:b"
            ),
            "signed-in B must not see A's iMessage vault row"
        )
        XCTAssertTrue(
            SaveVaultOwnerScope.belongsToActiveAccount(
                rows.first?["ownerSubject"] as? String,
                currentUserId: "did:privy:a"
            )
        )
    }

    @MainActor
    func testConfirmedPlaceRoundTripPreservesAmapIdentityForCapProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        var stamp = makePlace(id: UUID(), name: "Harbor Cafe", address: "1 Harbor", googlePlaceId: nil)
        stamp.coordinateSystem = .gcj02
        stamp.locationProvider = .amap
        stamp.providerPlaceId = "amap-harbor"
        stamp.providerMapUrl = "https://uri.amap.com/marker?position=121.519,25.051"
        _ = try vault.saveConfirmedPlace(stamp, ownerSubject: "did:privy:a")
        let restored = try XCTUnwrap(
            SaveLocalVaultService(overrideVaultURL: url).confirmedPlaces(belongingTo: "did:privy:a").first
        )
        XCTAssertEqual(restored.coordinateSystem, .gcj02)
        XCTAssertEqual(restored.locationProvider, .amap)
        XCTAssertEqual(restored.providerPlaceId, "amap-harbor")
        XCTAssertEqual(restored.providerMapUrl, stamp.providerMapUrl)
        var incoming = makePlace(id: UUID(), name: "Harbor Cafe", address: "1 Harbor", googlePlaceId: nil)
        incoming.coordinateSystem = .gcj02
        incoming.locationProvider = .amap
        incoming.providerPlaceId = "amap-harbor"
        incoming.latitude = stamp.latitude
        incoming.longitude = stamp.longitude
        XCTAssertTrue(restored.matches(incoming))
        XCTAssertEqual(Place.consolidated([restored, incoming]).count, 1)
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
