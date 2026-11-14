#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import MapKit
import XCTest
@testable import SAVE

@MainActor
final class LivePlaceInformationTests: XCTestCase {
    func testWrongBranchAndAmbiguousExactMatchesAreRejected() async throws {
        let pin = try savedPin()
        let scenarios: [([MKMapItem], LivePlaceInformationError)] = [
            ([mapItem("Different venue")], .notFound),
            ([mapItem("Exact Cafe", latitude: 25.0311)], .notFound),
            ([mapItem("Exact Cafe"), mapItem("Exact Cafe", latitude: 25.0301)], .ambiguous),
        ]
        for (results, expected) in scenarios {
            let reader = InformationReader(results: results)
            let model = LivePlaceInformationModel(reader: reader) { _, _ in true }
            await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7)
            XCTAssertNil(model.item)
            XCTAssertEqual(model.error, expected)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testSingleExactNormalizedNearbyMatchRetainsActualAppleMetadata() async throws {
        let accepted = mapItem("  EXACT　Cafe  ", latitude: 25.0310)
        accepted.phoneNumber = "+1 555 0100"
        accepted.url = URL(string: "https://example.invalid/venue")
        let reader = InformationReader(results: [mapItem("Unrelated cafe"), accepted])
        let model = LivePlaceInformationModel(reader: reader) { _, _ in true }
        let pin = try savedPin()
        await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertTrue(model.item === accepted)
        XCTAssertEqual(model.item?.phoneNumber, accepted.phoneNumber)
        XCTAssertEqual(model.item?.url, accepted.url)
        XCTAssertNil(model.error)
        XCTAssertEqual(pin.place.note, "Original private note")
        XCTAssertEqual(reader.queries.first?.0, pin.place.name)
        XCTAssertEqual(reader.queries.first?.1, pin.place.address)
    }

    func testProvidedNativeItemSkipsLookupButStillRequiresMatchingIdentity() async throws {
        let actual = mapItem("Exact Cafe")
        let pin = try XCTUnwrap(LiveMapPlace.search(actual))
        let reader = InformationReader(results: [])
        let model = LivePlaceInformationModel(reader: reader) { _, _ in true }
        await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertTrue(model.item === actual)
        XCTAssertTrue(reader.queries.isEmpty)
        XCTAssertTrue(reader.appleIDs.isEmpty)
        // The retained object is not permission to attach another branch later.
        actual.name = "A different branch"
        await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertNil(model.item)
        XCTAssertEqual(model.error, .notFound)
        XCTAssertEqual(reader.queries.count, 1)
    }

    func testGoogleIdentityNeverBecomesAnAppleIdentifierRequest() async throws {
        let reader = InformationReader(results: [mapItem("Exact Cafe")])
        let model = LivePlaceInformationModel(reader: reader) { _, _ in true }
        let pin = try savedPin(provider: .googlePlaces, identifier: "ChIJ-redacted-google-id")
        await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertTrue(reader.appleIDs.isEmpty)
        XCTAssertEqual(reader.queries.count, 1)
        XCTAssertNotNil(model.item)
        var googleOnly = pin.place
        googleOnly.locationProvider = .appleMaps
        googleOnly.providerPlaceId = nil
        await model.load(pin: try XCTUnwrap(LiveMapPlace.saved(googleOnly)), ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertTrue(reader.appleIDs.isEmpty, "A Google ID is never an Apple identifier fallback")
        XCTAssertEqual(reader.queries.count, 2)
    }

    func testTypedAppleIdentityUsesIdentifierReaderOnSupportedOS() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Typed Apple identifiers require iOS 18") }
        let reader = InformationReader(results: [mapItem("Exact Cafe")])
        let model = LivePlaceInformationModel(reader: reader) { _, _ in true }
        await model.load(pin: try savedPin(provider: .appleMaps, identifier: "redacted-apple-id"),
                         ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertEqual(reader.appleIDs, ["redacted-apple-id"])
        XCTAssertTrue(reader.queries.isEmpty)
        XCTAssertNotNil(model.item)
    }

    func testDelayedLookupRejectsOwnerGenerationExplicitCancelAndTaskCancellation() async throws {
        for mode in 0..<4 {
            let session = InformationSession()
            let gate = InformationGate()
            let reader = InformationReader(results: [mapItem("Exact Cafe")])
            reader.gate = gate
            let model = LivePlaceInformationModel(reader: reader) { owner, generation in
                session.owner == owner && session.generation == generation
            }
            let pin = try savedPin()
            let task = Task { await model.load(pin: pin, ownerSubject: "fixture-owner", sessionGeneration: 7) }
            await fulfillment(of: [gate.entered], timeout: 2)
            guard gate.isPaused else { task.cancel(); gate.release(); return }
            switch mode {
            case 0: session.owner = "other-owner"
            case 1: session.generation = 8
            case 2: model.cancel()
            default: task.cancel()
            }
            gate.release()
            await task.value
            XCTAssertNil(model.item)
            XCTAssertNil(model.error)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testOldPinResponseCannotReplaceNewPinAndInvalidPreflightNeverReads() async throws {
        let session = InformationSession()
        let gate = InformationGate()
        let reader = InformationReader(results: [mapItem("Exact Cafe")])
        reader.gate = gate
        let model = LivePlaceInformationModel(reader: reader) { owner, generation in
            session.owner == owner && session.generation == generation
        }
        let first = try savedPin()
        let task = Task { await model.load(pin: first, ownerSubject: "fixture-owner", sessionGeneration: 7) }
        await fulfillment(of: [gate.entered], timeout: 2)
        guard gate.isPaused else { task.cancel(); gate.release(); return }
        let secondItem = mapItem("Other Cafe")
        reader.results = [secondItem]
        await model.load(pin: try savedPin(name: "Other Cafe"), ownerSubject: "fixture-owner", sessionGeneration: 7)
        gate.release()
        await task.value
        XCTAssertTrue(model.item === secondItem)
        let reads = reader.queries.count
        session.owner = "other-owner"
        await model.load(pin: first, ownerSubject: "fixture-owner", sessionGeneration: 7)
        XCTAssertNil(model.item)
        XCTAssertNil(model.error)
        XCTAssertEqual(reader.queries.count, reads)
    }

    private func savedPin(name: String = "Exact Cafe", provider: PlaceMatchProvider? = nil,
                          identifier: String? = nil) throws -> LiveMapPlace {
        let place = Place(id: UUID(), name: name, address: "Redacted venue address", latitude: 25.03, longitude: 121.54,
                          googlePlaceId: provider == .googlePlaces ? identifier : nil, category: .cafe, status: .wantToGo,
                          note: "Original private note", sourcePlatform: .other, coordinateSystem: .wgs84,
                          locationProvider: provider, providerPlaceId: identifier, createdAt: Date(timeIntervalSince1970: 0))
        return try XCTUnwrap(LiveMapPlace.saved(place))
    }

    private func mapItem(_ name: String, latitude: Double = 25.03) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 121.54)))
        item.name = name
        return item
    }
}

@MainActor
private final class InformationSession {
    var owner = "fixture-owner"
    var generation = 7
}

@MainActor
private final class InformationReader: LivePlaceInformationReading {
    var results: [MKMapItem]
    var queries: [(String, String)] = []
    var appleIDs: [String] = []
    var gate: InformationGate?
    init(results: [MKMapItem]) { self.results = results }
    func appleItem(identifier: String) async throws -> MKMapItem? { appleIDs.append(identifier); return results.first }
    func search(name: String, address: String, coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
        queries.append((name, address))
        let response = results
        if let pending = gate { gate = nil; await pending.pause() }
        return response
    }
    // Deliberately permits a late callback so model guards, not this fake, protect UI.
    func cancel() {}
}

@MainActor
private final class InformationGate {
    let entered = XCTestExpectation(description: "Apple reader suspended")
    private var continuation: CheckedContinuation<Void, Never>?
    var isPaused: Bool { continuation != nil }
    private var released = false
    func pause() async {
        if released { return }
        await withCheckedContinuation { continuation = $0; entered.fulfill() }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
#endif
