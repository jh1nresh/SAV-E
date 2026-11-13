import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPFunctionalTests: XCTestCase {
    func testExplicitFriendConfirmationPersistsLocallyOnceWithoutMergingSenderMemory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("friend-confirm-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = SaveLocalVaultService(overrideVaultURL: folder.appendingPathComponent("vault.json"))
        let senderVault = SaveLocalVaultService(overrideVaultURL: folder.appendingPathComponent("sender.json"))
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        var source = place(); source.status = .visited; source.note = "private sender memory"
        try senderVault.saveConfirmedPlace(source)
        let senderBefore = try Data(contentsOf: folder.appendingPathComponent("sender.json"))
        let package = try CityMVPFriendExchange.makeSnapshot(places: senderVault.confirmedPlaces(), selectedIDs: [source.id],
            senderLabel: "Declared sender", recommendationReason: "I recommend the coffee")
        let opened = try CityMVPFriendExchange.decode(CityMVPFriendExchange.encode(package))
        XCTAssertTrue(try vault.confirmedPlaces().isEmpty, "Opening a package never saves")
        let incoming = CityMVPFriendExchange.recipientPlace(for: try XCTUnwrap(opened.venues.first))
        let saved = try vm.confirmCityMVPFriendPlace(incoming)
        XCTAssertEqual(saved.status, .wantToGo); XCTAssertNil(saved.note); XCTAssertNil(saved.recommender)
        let second = CityMVPFriendExchange.recipientPlace(for: try XCTUnwrap(opened.venues.first))
        XCTAssertEqual(try vm.confirmCityMVPFriendPlace(second).id, saved.id)
        XCTAssertEqual(vm.places.count, 1)
        let reloaded = try vault.confirmedPlaces()
        XCTAssertEqual(reloaded.count, 1); XCTAssertEqual(reloaded[0].id, saved.id)
        XCTAssertNil(reloaded[0].note); XCTAssertEqual(reloaded[0].status, .wantToGo)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("sender.json")), senderBefore)
    }

    func testFriendConfirmationRejectsRemoteContextAndPrivateOrVisitedPayloads() throws {
        let remote = MapViewModel(usesRemotePersistence: true)
        XCTAssertThrowsError(try remote.confirmCityMVPFriendPlace(place()))
        let local = MapViewModel(usesRemotePersistence: false)
        for transform in [ { (p: inout Place) in p.status = .visited },
                           { (p: inout Place) in p.note = "private" },
                           { (p: inout Place) in p.recommender = "unverified author" },
                           { (p: inout Place) in p.latitude = .nan } ] {
            var invalid = place(); transform(&invalid)
            XCTAssertThrowsError(try local.confirmCityMVPFriendPlace(invalid))
        }
        XCTAssertTrue(local.places.isEmpty)
    }

    func testNewPreviewSourceStatementsAreNotWrittenIntoAPrivateNote() throws {
        let context = try XCTUnwrap(CityMVPPlaceBridge.context.first { $0.id == CityMVPPlaceBridge.cityHallID })
        let candidate = CityMVPPlaceBridge.candidate(for: context)
        let saved = try SaveSearchController().makeSavedPlace(from: SavePlaceDraft(
            title: candidate.title, address: candidate.subtitle, latitude: candidate.latitude,
            longitude: candidate.longitude, category: candidate.category, sourceURL: candidate.sourceURL,
            sourcePlatform: candidate.sourcePlatform, evidence: candidate.evidence))
        XCTAssertNil(saved.userFacingNote)
        XCTAssertEqual(saved.savedAdditionalSourceEvidence.count, 3)
        XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains { $0.contains("position and entrance unverified") })
        let outer = try XCTUnwrap(CityContextPlace.catalogue?.records.first)
        let outerCandidate = CityMVPPlaceBridge.candidate(for: outer)
        let outerSaved = try SaveSearchController().makeSavedPlace(from: SavePlaceDraft(
            title: outerCandidate.title, address: outerCandidate.subtitle, latitude: outerCandidate.latitude,
            longitude: outerCandidate.longitude, category: outerCandidate.category, sourceURL: outerCandidate.sourceURL,
            sourcePlatform: outerCandidate.sourcePlatform, evidence: outerCandidate.evidence))
        XCTAssertNil(outerSaved.userFacingNote)
        XCTAssertEqual(outerSaved.savedAdditionalSourceEvidence.count, 4)
    }

    func testLocalTakeoutImportPreservesCorruptVaultAndDoesNotPublishSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("takeout-corrupt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        let corrupt = Data("{invalid existing vault".utf8)
        try corrupt.write(to: url, options: .atomic)
        let draft = ImportedPlaceDraft(name: "Import failure fixture", address: "Taipei, Test Road 1",
                                       latitude: 25.034, longitude: 121.564,
                                       sourceFile: "fixture.csv", sourceFormat: "csv", reviewState: .readyToSave)
        XCTAssertTrue(vm.places.isEmpty)
        do {
            _ = try await vm.saveImportedPlaces([draft])
            XCTFail("A corrupt primary vault must fail the import, not return a successful summary")
        } catch {
            XCTAssertTrue(error is DecodingError, "Expected the existing vault decoding failure, got \(error)")
        }
        XCTAssertTrue(vm.places.isEmpty, "Failed persistence must not publish a Saved place")
        XCTAssertTrue(vm.reviewCandidates.isEmpty, "A storage failure must not silently park or confirm the import")
        XCTAssertEqual(try Data(contentsOf: url), corrupt, "Do not reset or overwrite the existing corrupt vault")
    }

    func testNormalMapLinkConfirmationKeepsParserProseOutOfPrivateNotes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("review-memory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        let source = "https://maps.apple.com/?q=Source%20Boundary%20Fixture&ll=25.0312,121.5708"
        let ids = try await vm.importSharedTextAsReviewCandidates(source)
        XCTAssertTrue(try vault.confirmedPlaces().isEmpty, "A parsed clue cannot save itself")
        let candidate = try XCTUnwrap(vm.reviewCandidates.first { ids.contains($0.id) })
        let originalSourceProse = try XCTUnwrap(Place.from(candidate).note)
        let saved = try await vm.saveReviewCandidateAsPlace(candidate)
        XCTAssertNil(saved.note)
        XCTAssertNil(saved.userFacingNote)
        XCTAssertEqual(saved.sourceUrl, source)
        XCTAssertEqual(saved.latitude, 25.0312, accuracy: 0.000001)
        XCTAssertEqual(saved.longitude, 121.5708, accuracy: 0.000001)
        for line in originalSourceProse.components(separatedBy: .newlines) {
            XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains(line), "Keep original source prose as evidence")
        }
        let reopened = SaveLocalVaultService(overrideVaultURL: url)
        let durable = try XCTUnwrap(reopened.confirmedPlaces().first)
        XCTAssertEqual(durable.id, saved.id)
        XCTAssertNil(durable.note)
        XCTAssertEqual(durable.savedAdditionalSourceEvidence, saved.savedAdditionalSourceEvidence)
        XCTAssertTrue(vm.reviewCandidates.isEmpty)
    }

    func testReviewSourceMergePreservesAnExistingUserNoteEvenWhenItLooksGenerated() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("review-note-merge-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = SaveLocalVaultService(overrideVaultURL: folder.appendingPathComponent("vault.json"))
        var existing = place()
        existing.name = "Source Boundary Fixture"
        existing.latitude = 25.0312; existing.longitude = 121.5708
        existing.note = "Structured Apple Maps place link: this is my own note\nMap provider: keep my text"
        try vault.saveConfirmedPlace(existing)
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        vm.places = [existing]
        let ids = try await vm.importSharedTextAsReviewCandidates(
            "https://maps.apple.com/?q=Source%20Boundary%20Fixture&ll=25.0312,121.5708")
        let candidate = try XCTUnwrap(vm.reviewCandidates.first { ids.contains($0.id) })
        let saved = try await vm.saveReviewCandidateAsPlace(candidate)
        XCTAssertEqual(saved.id, existing.id)
        XCTAssertEqual(saved.note, existing.note, "Existing private text is never reclassified by its contents")
        let durable = try vault.confirmedPlaces()
        XCTAssertEqual(durable.count, 1)
        XCTAssertEqual(durable.first?.id, existing.id)
        XCTAssertEqual(durable.first?.note, existing.note)
        XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains { $0.contains("Structured Apple Maps place link: Source Boundary Fixture") })
    }

    func testLocalTakeoutImportPublishesOnlyDurableIdentityAndReloadsOnce() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("takeout-durable-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let vm = MapViewModel(saveLocalVaultService: vault, usesRemotePersistence: false)
        let draft = ImportedPlaceDraft(name: "Import success fixture", address: "Taipei, Test Road 2",
                                       latitude: 25.034, longitude: 121.564,
                                       sourceFile: "fixture.csv", sourceFormat: "csv", reviewState: .readyToSave)
        let summary = try await vm.saveImportedPlaces([draft])
        XCTAssertEqual(summary.saved, 1)
        XCTAssertEqual(summary.skippedDuplicates, 0)
        XCTAssertEqual(summary.reviewDrafts, 0)
        XCTAssertEqual(vm.places.map(\.id), [draft.id])
        let reopened = SaveLocalVaultService(overrideVaultURL: url)
        let persisted = try reopened.confirmedPlaces()
        XCTAssertEqual(persisted.map(\.id), [draft.id])
        XCTAssertEqual(persisted.first?.name, draft.name)
        XCTAssertEqual(persisted.first?.address, draft.address)
        let replay = try await vm.saveImportedPlaces([draft])
        XCTAssertEqual(replay.saved, 0)
        XCTAssertEqual(replay.skippedDuplicates, 1)
        XCTAssertEqual(vm.places.map(\.id), [draft.id])
        XCTAssertEqual(try reopened.confirmedPlaces().map(\.id), [draft.id])
    }

    private func place() -> Place {
        Place(id: UUID(), name: "Fixture coffee", address: "Taipei, Test Road 1",
              latitude: 25.034, longitude: 121.564, category: .cafe, status: .wantToGo,
              sourcePlatform: .other, createdAt: Date())
    }
}
