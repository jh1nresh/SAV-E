import Foundation
import XCTest
@testable import SAVE

@MainActor
final class ImportedLinkNoteTests: XCTestCase {
    private let source = "https://example.com/post?id=42#venue"
    private let body = "Imported caption: quiet tables and a long analysis of the menu."

    func testLinkedSaveDraftStoresOnlyURLInActualPlaceWirePayload() async throws {
        let draft = SavePlaceDraft(title: "Fixture Cafe", address: "Fixture address", latitude: 25.03,
                                  longitude: 121.54, category: .cafe, sourceURL: "  HTTPS://EXAMPLE.COM/post?id=42#venue\n",
                                  sourcePlatform: .other, evidence: [body])
        let place = try SaveSearchController().makeSavedPlace(from: draft)
        XCTAssertEqual(place.note, source)
        XCTAssertEqual(place.userFacingNote, source)
        XCTAssertEqual(place.wireNoteForPersistence(), source)
        XCTAssertTrue(place.savedAdditionalSourceEvidence.contains(body))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImportedNoteRequestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ImportedNoteRequestURLProtocol.reset() }
        let service = SupabaseService(apiBaseURL: "https://imported-note.test", session: session,
                                      accessTokenProvider: { "fixture-test-token" })
        try await service.savePlace(place, userId: "fixture-owner")
        let data = try XCTUnwrap(ImportedNoteRequestURLProtocol.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["note"] as? String, source)
        XCTAssertFalse((payload["note"] as? String ?? "").contains(body))
    }

    func testPendingSharedLinkUsesURLInsteadOfSourceText() {
        let place = Place.from(pending(sourceURL: source))
        XCTAssertEqual(place.note, source)
        XCTAssertEqual(place.sourceUrl, source)
        XCTAssertEqual(place.wireNoteForPersistence(), source)
        XCTAssertFalse(place.savedAdditionalSourceEvidence.contains(body))
    }

    func testFreshReviewWithExplicitSourceMarkerDoesNotCopyBodyIntoSavedMemory() {
        for marker in ["Source URL:", "Source:"] {
            let candidate = review(evidence: [body, "\(marker) \(source)", "Caption mentions https://example.com/unrelated"])
            let place = Place.from(candidate)
            XCTAssertEqual(place.note, source)
            XCTAssertEqual(place.sourceUrl, source)
            XCTAssertTrue(place.savedAdditionalSourceEvidence.contains(body))
            XCTAssertFalse((place.wireNoteForPersistence() ?? "").contains("Caption"))
        }
    }

    func testExplicitSourceOutranksCaptionURLsAndInvalidSourceDoesNotPromoteThem() {
        let caption = "Caption mentions https://example.com/unrelated"
        let explicit = Place.from(review(evidence: [caption, "Source URL: \(source)", body]))
        XCTAssertEqual(explicit.note, source)
        XCTAssertEqual(explicit.sourceUrl, source)
        let invalid = Place.from(review(evidence: [caption, "Source URL: javascript:alert(1)", body]))
        XCTAssertNil(invalid.note)
        XCTAssertNil(invalid.sourceUrl)
        XCTAssertTrue(invalid.savedAdditionalSourceEvidence.contains(caption))
    }

    func testVaultCanonicalSourceOutranksMarkersQuotedInsideCaptionOrEarlierEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imported-link-note-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let caption = "Caption body\nSource: https://example.com/menu\nMore source prose"
        let pending = PendingReviewCandidate(candidateName: "Fixture Cafe", address: "Fixture address", category: "cafe",
            sourceURL: source, sourceText: caption, evidence: ["Source URL: https://example.com/quoted"], confidence: 1,
            missingInfo: [], savedAt: Date(timeIntervalSince1970: 0), isSourceOnly: false)
        _ = try vault.saveReviewCandidate(pending)
        let restored = try XCTUnwrap(vault.reviewCandidates().first)
        XCTAssertEqual(restored.evidence.first, "Source URL: \(source)")
        XCTAssertEqual(Place.from(restored).note, source)
        XCTAssertEqual(Place.from(restored).sourceUrl, source)
        let legacyOrder = Place.from(review(evidence: [caption, "Source URL: \(source)"]))
        XCTAssertEqual(legacyOrder.note, source)
        XCTAssertEqual(legacyOrder.sourceUrl, source)
        XCTAssertNil(ImportedLinkNote.explicitURL(in: ["Source URL: javascript:alert(1)", "Source: https://example.com/menu"]))
    }

    func testNoExplicitSourceKeepsExistingManualAndUnclassifiedBehavior() throws {
        let manual = "Keep this personal note exactly."
        let draft = SavePlaceDraft(title: "Fixture Cafe", address: "Fixture address", latitude: 25.03,
                                  longitude: 121.54, category: .cafe, sourceURL: nil, sourcePlatform: nil, evidence: [manual])
        XCTAssertEqual(try SaveSearchController().makeSavedPlace(from: draft).note, manual)
        XCTAssertEqual(Place.from(review(evidence: [manual])).note, manual)
        XCTAssertEqual(Place.from(pending(sourceURL: nil)).note, body)
        let quoted = "A personal note that mentions https://example.com/menu"
        XCTAssertEqual(Place.from(review(evidence: [quoted])).note, quoted,
                       "A URL embedded in prose is not explicit import provenance")
    }

    func testUnplacedRecoveryAndMergePreserveExistingManualNoteDespiteSourceURL() {
        let manualNote = "Must try the bun\nAsk for the quiet table"
        var original = Place.from(review(evidence: [body, "Source URL: \(source)"]))
        original.note = manualNote
        let parked = PlaceReviewCandidate.unplacedInboxItem(from: original, ownerSubject: "fixture-owner")
        XCTAssertTrue(parked.isUnplacedInbox)
        let restored = Place.from(parked)
        XCTAssertEqual(restored.note, manualNote)
        XCTAssertEqual(restored.sourceUrl, source)
        XCTAssertTrue(restored.savedAdditionalSourceEvidence.contains(body))
        let secondRecovery = Place.from(PlaceReviewCandidate.unplacedInboxItem(from: restored, ownerSubject: "fixture-owner"))
        XCTAssertEqual(secondRecovery.note, manualNote)
        XCTAssertTrue(secondRecovery.savedAdditionalSourceEvidence.contains(body))
        let incoming = Place.from(review(evidence: ["Source URL: \(source)", body]))
        let merged = original.mergingSources(from: incoming)
        XCTAssertEqual(merged.note, manualNote)
        XCTAssertEqual(merged.wireNoteForPersistence(), manualNote)
        XCTAssertTrue(merged.savedAdditionalSourceEvidence.contains(body))
    }

    func testMultilineSourceMetadataNeverBecomesManualNoteAcrossTwoRecoveryCycles() {
        let manual = "Must try the bun\nAsk for quiet table"
        var saved = Place.from(pending(sourceURL: source))
        saved.note = manual
        saved.additionalSourceEvidence = ["Imported caption line1\nImported caption line2", "Evidence: existing context\nAnother context"]
        for _ in 0..<2 {
            saved = Place.from(PlaceReviewCandidate.unplacedInboxItem(from: saved, ownerSubject: "fixture-owner"))
            XCTAssertEqual(saved.note, manual)
            XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains("Imported caption line1"))
            XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains("Imported caption line2"))
            XCTAssertTrue(saved.savedAdditionalSourceEvidence.contains("Another context"))
        }
    }

    func testMalformedAndCredentialedSourcesDoNotGuessANewNoteURL() {
        for invalid in ["example.com/post", "ftp://example.com/post", "https://user:secret@example.com/post",
                        "https://example.com/post\nUnrelated caption"] {
            XCTAssertNil(ImportedLinkNote.normalizedURL(invalid))
            let place = Place.from(pending(sourceURL: invalid))
            XCTAssertNil(place.note, "Rejected source URLs must not fall back to imported post text")
            XCTAssertFalse(place.savedAdditionalSourceEvidence.contains(body))
        }
        XCTAssertEqual(ImportedLinkNote.normalizedURL("https://maps.google.com/?q=Exact+Venue&place_id=ChIJFixture#map"),
                       "https://maps.google.com/?q=Exact+Venue&place_id=ChIJFixture#map",
                       "Google venue query/fragment must not be stripped by a share-only sanitizer")
    }

    private func pending(sourceURL: String?) -> PendingSharedPlace {
        PendingSharedPlace(name: "Fixture Cafe", address: "Fixture address", category: "cafe",
                           latitude: 25.03, longitude: 121.54, dishes: [], priceRange: nil,
                           sourceURL: sourceURL, sourceText: body, savedAt: Date(timeIntervalSince1970: 0))
    }

    private func review(evidence: [String]) -> PlaceReviewCandidate {
        PlaceReviewCandidate(id: UUID(), captureId: nil, name: "Fixture Cafe", address: "Fixture address", city: nil,
                             latitude: 25.03, longitude: 121.54, evidence: evidence, confidence: 1,
                             missingInfo: [], status: "review", createdAt: Date(timeIntervalSince1970: 0))
    }
}

/// Captures the real client encoder without contacting a server or an account.
private final class ImportedNoteRequestURLProtocol: URLProtocol {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var body: Data?
    }
    private static let state = State()
    static var body: Data? { state.lock.withLock { state.body } }
    static func reset() { state.lock.withLock { state.body = nil } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            body = data
        }
        Self.state.lock.withLock { Self.state.body = body }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
