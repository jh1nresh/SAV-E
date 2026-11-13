import Foundation
import XCTest
@testable import SAVE

@MainActor
final class SavvyPlaceHistoryTests: XCTestCase {
    func testOwnerFilteringAndNoUnownedVisitFallback() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        try put([place("a", owner: "A"), place("b", owner: "B"), place("old", owner: nil)],
                key: SavePlaceLinkGate.placesKey, into: stores.shared)
        try put([visit(placeID: "a")], key: "save.ink.visits.v1", into: stores.visits)
        try put([visit(placeID: "b")], key: "save.ink.visits.v1.B", into: stores.visits)

        let a = try load("A", stores)
        XCTAssertEqual(a.ownerSubject, "A")
        XCTAssertEqual(a.savedPlaces.map(\.id), ["a"])
        XCTAssertTrue(a.visits.isEmpty)
        let b = try load("B", stores)
        XCTAssertEqual(b.savedPlaces.map(\.id), ["b"])
        XCTAssertEqual(b.visits.map(\.placeID), ["b"])
    }

    func testSharedKeyWinsAndAbsentKeyFallsBackWithoutCopying() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        try put([place("legacy", owner: "A")], key: SavePlaceLinkGate.placesKey, into: stores.legacy)
        XCTAssertEqual(try load("A", stores).savedPlaces.map(\.id), ["legacy"])
        XCTAssertNil(stores.shared.object(forKey: SavePlaceLinkGate.placesKey))
        try put([place("shared", owner: "A")], key: SavePlaceLinkGate.placesKey, into: stores.shared)
        XCTAssertEqual(try load("A", stores).savedPlaces.map(\.id), ["shared"])
        try put([SaveInkSavedPlaceRecord](), key: SavePlaceLinkGate.placesKey, into: stores.shared)
        XCTAssertTrue(try load("A", stores).savedPlaces.isEmpty)
    }

    func testCorruptSharedDataFailsWithoutFallbackOrMutation() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        let corrupt = Data("not JSON".utf8)
        stores.shared.set(corrupt, forKey: SavePlaceLinkGate.placesKey)
        try put([place("legacy", owner: "A")], key: SavePlaceLinkGate.placesKey, into: stores.legacy)
        let legacyBefore = stores.legacy.data(forKey: SavePlaceLinkGate.placesKey)
        XCTAssertThrowsError(try load("A", stores)) {
            XCTAssertEqual($0 as? SavvyPlaceHistory.Failure, .unreadablePlaces)
        }
        XCTAssertEqual(stores.shared.data(forKey: SavePlaceLinkGate.placesKey), corrupt)
        XCTAssertEqual(stores.legacy.data(forKey: SavePlaceLinkGate.placesKey), legacyBefore)
    }

    func testWrongTypeAndCorruptVisitsAreExplicitFailures() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        stores.shared.set("unexpected type", forKey: SavePlaceLinkGate.placesKey)
        XCTAssertThrowsError(try load("A", stores)) {
            XCTAssertEqual($0 as? SavvyPlaceHistory.Failure, .unreadablePlaces)
        }
        stores.shared.removeObject(forKey: SavePlaceLinkGate.placesKey)
        let corrupt = Data("[]broken".utf8)
        stores.visits.set(corrupt, forKey: "save.ink.visits.v1.A")
        XCTAssertThrowsError(try load("A", stores)) {
            XCTAssertEqual($0 as? SavvyPlaceHistory.Failure, .unreadableVisits)
        }
        XCTAssertEqual(stores.visits.data(forKey: "save.ink.visits.v1.A"), corrupt)
    }

    func testFullNotesAndAllVisitMetadataRoundTripUnchanged() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        let note = String(repeating: "私人原文：位置尚未確定。\n", count: 80)
        var saved = place("saved--123456789", owner: "A")
        saved.detailNote = note
        saved.sourceLabel = "原始來源，保留原文"
        var first = visit(placeID: saved.id)
        first.comment = note
        first.verification = .unverified
        first.visibility = .private
        first.sentiment = .worthQueue
        first.anomaly = .implausibleSpeed
        var second = visit(placeID: saved.id)
        second.visitedAt = first.visitedAt.addingTimeInterval(86_400)
        second.verification = .verified
        second.visibility = .public
        try put([saved], key: SavePlaceLinkGate.placesKey, into: stores.shared)
        try put([first, second], key: "save.ink.visits.v1.A", into: stores.visits)
        let placesBefore = stores.shared.data(forKey: SavePlaceLinkGate.placesKey)
        let visitsBefore = stores.visits.data(forKey: "save.ink.visits.v1.A")

        let snapshot = try load("A", stores)
        XCTAssertEqual(snapshot.savedPlaces, [saved])
        XCTAssertEqual(snapshot.visits, [first, second])
        XCTAssertEqual(stores.shared.data(forKey: SavePlaceLinkGate.placesKey), placesBefore)
        XCTAssertEqual(stores.visits.data(forKey: "save.ink.visits.v1.A"), visitsBefore)
    }

    func testMissingOwnerDoesNotExposeOwnerlessRecords() throws {
        let stores = isolatedStores()
        defer { stores.cleanUp() }
        try put([place("ownerless", owner: nil)], key: SavePlaceLinkGate.placesKey, into: stores.shared)
        for owner in ["", " \n"] {
            XCTAssertThrowsError(try load(owner, stores)) {
                XCTAssertEqual($0 as? SavvyPlaceHistory.Failure, .missingOwner)
            }
        }
    }

    private func load(_ owner: String, _ stores: Stores) throws -> SavvyPlaceHistorySnapshot {
        try SavvyPlaceHistory.load(ownerSubject: owner, placesDefaults: stores.shared,
                                  legacyDefaults: stores.legacy, visitsDefaults: stores.visits)
    }

    private func put<Value: Encodable>(_ value: Value, key: String, into defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }

    private func place(_ id: String, owner: String?) -> SaveInkSavedPlaceRecord {
        SaveInkSavedPlaceRecord(id: id, name: "Name", stampName: "Stamp", street: "Street",
                                blurb: "Saved", sourceLabel: "Source", detailNote: "Note", ownerSubject: owner)
    }

    private func visit(placeID: String) -> SaveInkVisitRecord {
        SaveInkVisitRecord(id: UUID(), placeID: placeID, visitedAt: Date(timeIntervalSince1970: 1_700_000_000),
                           verification: .unverified, visibility: .private, comment: "",
                           sentiment: nil, anomaly: nil)
    }

    private struct Stores {
        let names: [String]
        let shared: UserDefaults
        let legacy: UserDefaults
        let visits: UserDefaults

        func cleanUp() {
            for (name, defaults) in zip(names, [shared, legacy, visits]) {
                defaults.removePersistentDomain(forName: name)
            }
        }
    }

    private func isolatedStores() -> Stores {
        let names = (0..<3).map { "savvy.history.tests.\(UUID().uuidString).\($0)" }
        return Stores(names: names, shared: UserDefaults(suiteName: names[0])!,
                      legacy: UserDefaults(suiteName: names[1])!, visits: UserDefaults(suiteName: names[2])!)
    }
}
