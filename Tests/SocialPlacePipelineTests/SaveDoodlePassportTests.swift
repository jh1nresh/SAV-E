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
        let now = Date()
        let duck = place("Duck", "Beijing, China", .food, status: .visited, createdAt: now)
        let cafe = place("Grey Cafe", "Beijing, China", .cafe, createdAt: now.addingTimeInterval(-1))
        let park = place("Tiantan", "Beijing, China", .attraction, createdAt: now.addingTimeInterval(-2))
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            createdAt: now.addingTimeInterval(-3)
        )
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

    func testDoodleFaceSlotsMatchThePassportMockGrid() {
        let slots = SaveDoodlePassportCatalog.doodleFaceSlots()
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.filter(\.isVisited).count, 4)
        XCTAssertEqual(
            slots.compactMap { slot -> SaveDoodleStickerKind? in
                if case let .place(_, kind, _) = slot.content { return kind }
                return nil
            },
            [
                .duck, .noodles, .temple, .lantern,
                .coffee, .hill, .bridge, .baozi,
                .tea, .bookstore, .bicycle, .ferris,
            ]
        )
        XCTAssertFalse(SaveDoodlePassportCatalog.usesDoodleFace)
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
        XCTAssertTrue(page.contains("locksPointSize: true"))
        XCTAssertTrue(page.contains("traditionalChinese: \"護照\""))
        XCTAssertFalse(page.contains("profile.settings"))
        XCTAssertTrue(page.contains("onOpenCollected"))
        XCTAssertTrue(passport.contains("opensCollected"))
        XCTAssertTrue(passport.contains("profile.collected.root"))
        XCTAssertTrue(passport.contains("SharedPostsGrid"))
        XCTAssertTrue(page.contains("SaveHaptics.stamp()"))
        let stickers = try source(at: "SAV-E/Views/Profile/SaveDoodlePassportStickers.swift")
        XCTAssertTrue(stickers.contains("dieCut"))
        XCTAssertTrue(stickers.contains("249 / 255"))
        XCTAssertTrue(page.contains(".frame(width: 8, height: 8)"))
    }

    func testPassportParityTargetIsTheDoodleMockAtExactly90() throws {
        let script = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(script.contains("five-tab-passport*)"))
        XCTAssertTrue(script.contains("screen=\"passport\""))
        XCTAssertTrue(script.contains("for screen in home saves plan map passport; do"))
        let target = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/passport.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let png = try Data(contentsOf: target)
        XCTAssertEqual([UInt8](png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(png, at: 16), 402)
        XCTAssertEqual(pngDimension(png, at: 20), 874)
        XCTAssertEqual(png[25], 2, "Passport target must stay RGB 8-bit, not a generated screenshot.")
        XCTAssertTrue(script.contains("THRESHOLD=\"0.90\""))
        let readme = try source(at: "Prototypes/AtlasPostcard/README.md")
        XCTAssertTrue(readme.contains("uniform"))
        XCTAssertTrue(readme.contains("paper"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-passport\")"))
        XCTAssertTrue(rail.contains("ProductionTargets/passport.png"))
        XCTAssertTrue(rail.contains("at exactly 0.90"))
        XCTAssertTrue(rail.contains("--uitest-doodle-passport-face"))
        XCTAssertTrue(rail.contains("doodle-passport-light"))
        XCTAssertTrue(rail.contains("doodle-passport-dark"))
    }

    private func place(
        _ name: String,
        _ address: String,
        _ category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        createdAt: Date = Date()
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
            createdAt: createdAt
        )
    }

    private func pngDimension(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
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
