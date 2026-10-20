import XCTest
@testable import SAVE

@MainActor
final class SaveDoodlePassportTests: XCTestCase {
    func testVisitRanksFollowOneThreeFive() {
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 0), .none)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 1), .single)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 2), .single)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 3), .double)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 4), .double)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 5), .gold)
        XCTAssertEqual(SavePassportStampRank.from(visitCount: 9), .gold)
    }

    func testCitySlotsPadToTwelveAndColorVisited() {
        let suite = "save.doodle.passport.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SavePassportVisitStore(defaults: defaults)
        let duck = place("Duck", "Beijing, China", .food, status: .visited)
        let cafe = place("Grey Cafe", "Beijing, China", .cafe)
        let park = place("Tiantan", "Beijing, China", .attraction)
        let tokyo = place("Ichiran", "1-22-7 Jinnan, Shibuya City, Tokyo, Japan", .food)
        let slots = SaveDoodlePassportCatalog.slots(
            from: [duck, cafe, park, tokyo],
            selection: .city("beijing"),
            locationDenied: true,
            visitStore: store
        )
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.compactMap(\.place?.name), ["Duck", "Grey Cafe", "Tiantan"])
        XCTAssertTrue(slots[0].isVisited)
        XCTAssertFalse(slots[1].isVisited)
        XCTAssertEqual(SaveDoodlePassportCatalog.visitedCount(in: [duck, cafe, park]), 1)
        XCTAssertEqual(SaveDoodlePassportCatalog.stickerKind(for: duck), .duck)
        XCTAssertEqual(SaveDoodlePassportCatalog.stickerKind(for: cafe), .coffee)
    }

    func testRecordingAVisitClimbsTheStampRank() {
        let suite = "save.doodle.passport.visit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SavePassportVisitStore(defaults: defaults)
        let id = UUID()
        XCTAssertEqual(store.rank(for: id, visited: false), .none)
        XCTAssertEqual(store.recordVisit(for: id), 1)
        XCTAssertEqual(store.rank(for: id, visited: true), .single)
        store.recordVisit(for: id)
        store.recordVisit(for: id)
        XCTAssertEqual(store.rank(for: id, visited: true), .double)
        store.recordVisit(for: id)
        store.recordVisit(for: id)
        XCTAssertEqual(store.rank(for: id, visited: true), .gold)
    }

    func testRootIsDoodleGridAndFlagsOffTileTownMissions() throws {
        let passport = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        let page = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportView.swift")
        XCTAssertTrue(passport.contains("SaveDoodlePassportPage("))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showTodayMissions"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showFieldStreak"))
        XCTAssertTrue(passport.contains("SaveDoodlePassportFlags.showStampLedger"))
        XCTAssertFalse(SaveDoodlePassportFlags.showTodayMissions)
        XCTAssertFalse(SaveDoodlePassportFlags.showFieldStreak)
        XCTAssertFalse(SaveDoodlePassportFlags.showStampLedger)
        XCTAssertFalse(passport.contains("PassportTileTownCollection"))
        XCTAssertFalse(passport.contains("SaveKraftStamp("))
        XCTAssertTrue(page.contains("profile.stampGrid"))
        XCTAssertTrue(page.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(page.contains("SaveDisplayTitle("))
        XCTAssertTrue(page.contains("traditionalChinese: \"護照\""))
        XCTAssertTrue(page.contains("onOpenCollected"))
        XCTAssertTrue(passport.contains("opensCollected"))
        XCTAssertTrue(passport.contains("profile.collected.root"))
        XCTAssertTrue(passport.contains("SharedPostsGrid"))
        XCTAssertTrue(page.contains("SaveHaptics.stamp()"))
    }

    func testPassportParityTargetIsTheDoodleMockAtExactly90() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(script.contains("five-tab-passport*)"))
        XCTAssertTrue(script.contains("screen=\"passport\""))
        XCTAssertTrue(script.contains("for screen in home saves plan map passport; do"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Prototypes/AtlasPostcard/Reference/ProductionTargets/passport.png"
            ).path
        ))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-passport\")"))
        XCTAssertTrue(rail.contains("ProductionTargets/passport.png"))
        XCTAssertTrue(rail.contains("at exactly 0.90"))
    }

    private func place(
        _ name: String,
        _ address: String,
        _ category: PlaceCategory,
        status: PlaceStatus = .wantToGo
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 39.88,
            longitude: 116.40,
            category: category,
            status: status,
            sourcePlatform: .other,
            createdAt: Date()
        )
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
