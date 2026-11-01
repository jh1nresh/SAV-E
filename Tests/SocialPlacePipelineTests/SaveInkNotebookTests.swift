import CryptoKit
import SwiftUI
import UIKit
import XCTest
@testable import SAVE

@MainActor
final class SaveInkNotebookTests: XCTestCase {
    func testProvisionalThresholdsMatchHoPSuggestions() {
        XCTAssertEqual(SaveInkProvisional.radiusMeters, 150)
        XCTAssertEqual(SaveInkProvisional.maxAccuracyMeters, 100)
        XCTAssertEqual(SaveInkProvisional.timeoutSeconds, 10)
        XCTAssertEqual(SaveInkProvisional.samePlaceWindow, 6 * 60 * 60)
        XCTAssertEqual(SaveInkProvisional.upgradeWindow, 24 * 60 * 60)
        XCTAssertEqual(SaveInkProvisional.dailyVerifiedCap, 20)
        XCTAssertEqual(SaveInkProvisional.maxSpeedKmh, 300)
        XCTAssertEqual(SaveInkProvisional.maxFixAge, 60)
        XCTAssertEqual(SaveInkProvisional.defaultVisibility, .public)
    }

    func testDistanceBoundaryAndUnusableFixes() {
        XCTAssertEqual(decision(.inRange(meters: 150)).situation, .verified)
        XCTAssertEqual(decision(.inRange(meters: 150.4)).situation, .tooFar(meters: 150))
        var coarse = SaveInkFix.inRange()
        coarse.horizontalAccuracyMeters = 100
        XCTAssertEqual(decision(coarse).situation, .verified)
        coarse.horizontalAccuracyMeters = 100.1
        XCTAssertEqual(decision(coarse).situation, .locationFailed)
        var stale = SaveInkFix.inRange()
        stale.ageSeconds = 60
        XCTAssertEqual(decision(stale).situation, .verified)
        stale.ageSeconds = 60.1
        XCTAssertEqual(decision(stale).situation, .locationFailed)
        var timedOut = SaveInkFix.inRange()
        timedOut.timedOut = true
        XCTAssertEqual(decision(timedOut).situation, .locationFailed)
        var denied = SaveInkFix.inRange()
        denied.authorization = .denied
        XCTAssertEqual(decision(denied).situation, .permissionDenied)
        var reduced = SaveInkFix.inRange()
        reduced.precise = false
        XCTAssertEqual(decision(reduced).situation, .approximateOnly)
    }

    func testAntiFraudDowngradesWithoutStoringCoordinates() {
        var simulated = SaveInkFix.inRange()
        simulated.isSimulated = true
        let simulatedDecision = decision(simulated)
        XCTAssertEqual(simulatedDecision.situation, .downgradedUnverified)
        XCTAssertEqual(simulatedDecision.anomaly, .simulatedLocation)
        XCTAssertEqual(simulatedDecision.verification, .unverified)

        let fast = SaveInkCheckIn.decide(fix: .inRange(), verifiedToday: 0, impliedSpeedKmh: 301)
        XCTAssertEqual(fast.anomaly, .implausibleSpeed)
        let capped = SaveInkCheckIn.decide(fix: .inRange(), verifiedToday: 20, impliedSpeedKmh: nil)
        XCTAssertEqual(capped.anomaly, .dailyCap)
        XCTAssertEqual(capped.verification, .unverified)
    }

    func testTooFarWaitsForSaveAnywayAndRetryCanUpgrade() {
        let now = SaveInkClock.previewNow
        var visits: [SaveInkVisitRecord] = []
        let far = decision(.inRange(meters: 320))
        XCTAssertEqual(
            SaveInkVisitBook.apply(decision: far, placeID: "dingtai", now: now, visits: &visits),
            .ignored
        )
        XCTAssertTrue(visits.isEmpty)
        let saved = SaveInkVisitBook.apply(
            decision: far,
            placeID: "dingtai",
            now: now,
            visits: &visits,
            recordTooFar: true
        )
        guard case .inserted(let id) = saved else {
            return XCTFail("expected an unverified visit")
        }
        XCTAssertEqual(visits.first?.verification, .unverified)
        XCTAssertEqual(visits.first?.visibility, .public)

        let upgrade = SaveInkVisitBook.apply(
            decision: decision(.inRange()),
            placeID: "dingtai",
            now: now.addingTimeInterval(60),
            visits: &visits
        )
        XCTAssertEqual(upgrade, .upgraded(id))
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits[0].verification, .verified)
    }

    func testSamePlaceWindowDoesNotAddASecondVisit() {
        let now = SaveInkClock.previewNow
        var visits = [sampleVisit(placeID: "dingtai", at: now.addingTimeInterval(-3600), verification: .verified)]
        let result = SaveInkVisitBook.apply(
            decision: decision(.inRange()),
            placeID: "dingtai",
            now: now,
            visits: &visits
        )
        XCTAssertEqual(result, .suppressed)
        XCTAssertEqual(visits.count, 1)
    }

    func testVisitRecordCannotEncodeCoordinates() throws {
        let record = sampleVisit(placeID: "dingtai", at: SaveInkClock.previewNow, verification: .verified)
        let data = try SaveInkNotebookStore.encoder.encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let forbidden = [
            "latitude", "longitude", "lat", "lng", "coordinate", "coordinates",
            "horizontalaccuracy", "altitude", "course", "speed",
        ]
        for key in object.keys {
            XCTAssertFalse(forbidden.contains(key.lowercased()), key)
        }
        XCTAssertEqual(object["visibility"] as? String, "public")
        XCTAssertEqual(object["verification"] as? String, "verified")
        XCTAssertEqual(Set(object.keys), [
            "anomaly", "comment", "id", "placeID", "sentiment", "verification", "visibility", "visitedAt",
        ])
    }

    func testCheckInPersistsVerdictWithoutCoordinates() async throws {
        let suite = "save.ink.checkin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let locator = SaveInkScriptedLocator(fix: .inRange(meters: 18))
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { locator }
        )
        await store.checkIn(placeID: SaveInkFixture.dingtai)
        XCTAssertEqual(locator.calls, 1)
        XCTAssertEqual(store.verifiedCount(for: SaveInkFixture.dingtai), 1)
        let stored = try XCTUnwrap(defaults.data(forKey: "save.ink.visits.v1"))
        let text = String(decoding: stored, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("latitude"))
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertFalse(text.contains("25.0327"))
    }

    func testOpeningFriendsDoesNotRequestLocation() {
        var made = 0
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.friends.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: {
                made += 1
                return SaveInkScriptedLocator()
            }
        )
        store.openFriends()
        XCTAssertEqual(store.path, [.friends])
        XCTAssertEqual(made, 0)
    }

    func testFriendRankingVerifiedCountThenRecencyAndUnverifiedLast() {
        let now = SaveInkClock.previewNow
        let cards = SaveInkFriends.cards(from: [
            friend("a", "同次數舊", count: 2, daysAgo: 4, verification: .verified, now: now),
            friend("b", "同次數新", count: 2, daysAgo: 1, verification: .verified, now: now),
            friend("c", "次數多", count: 5, daysAgo: 6, verification: .verified, now: now),
            friend("d", "未驗證較新", count: 1, daysAgo: 0, verification: .unverified, now: now),
            friend("e", "私密", count: 9, daysAgo: 0, verification: .verified, visibility: .private, now: now),
        ].flatMap { $0 })
        XCTAssertEqual(cards.map(\.authorName), ["次數多", "同次數新", "同次數舊", "未驗證較新"])
        XCTAssertEqual(cards[0].verifiedCount, 5)
        XCTAssertEqual(cards[1].subtitle(now: now), "去過 2 次・1 天前")
        XCTAssertEqual(cards[3].segment, .unverified)
        XCTAssertEqual(cards[3].verifiedCount, 0)
        XCTAssertEqual(cards[3].subtitle(now: now), "今天")
        XCTAssertFalse(cards.contains { $0.authorName == "私密" })
    }

    func testPrivateVisitsDoNotAddToAPublicVerifiedCount() {
        let now = SaveInkClock.previewNow
        var inputs = friend("a", "阿哲", count: 1, daysAgo: 2, verification: .verified, now: now)
        inputs += friend("a", "阿哲", count: 4, daysAgo: 1, verification: .verified, visibility: .private, now: now)
        let cards = SaveInkFriends.cards(from: inputs)
        XCTAssertEqual(cards.map(\.verifiedCount), [1])
    }

    func testFixtureFriendsMatchTheDesignedOrder() {
        let now = SaveInkClock.previewNow
        let cards = SaveInkFriends.cards(from: SaveInkFixture.friendInputs(now: now))
        XCTAssertEqual(cards.map(\.authorName), ["阿哲", "凱文", "茉茉", "小安"])
        XCTAssertEqual(cards.map(\.verifiedCount), [5, 3, 2, 0])
        XCTAssertEqual(cards.map(\.segment), [.verified, .verified, .verified, .unverified])
        XCTAssertEqual(cards[0].subtitle(now: now), "去過 5 次・2 天前")
        XCTAssertEqual(cards[1].subtitle(now: now), "去過 3 次・1 週前")
        XCTAssertEqual(cards[3].subtitle(now: now), "3 天前")
    }

    func testInkSurfaceHasOneFriendsEntryAndNoTabsOrFilter() throws {
        let screens = try source("SAV-E/Views/InkNotebook/SaveInkNotebookScreens.swift")
        let root = try source("SAV-E/Views/InkNotebook/SaveInkNotebookRoot.swift")
        let chrome = try source("SAV-E/Views/InkNotebook/SaveInkNotebookChrome.swift")
        let model = try source("SAV-E/Views/InkNotebook/SaveInkNotebookModel.swift")
        for file in [screens, root, chrome, model] {
            XCTAssertFalse(file.contains("TabView"))
        }
        XCTAssertEqual(screens.components(separatedBy: "ink.friends.entry").count - 1, 1)
        XCTAssertTrue(screens.contains("ink.friends.back"))
        XCTAssertFalse(screens.contains("只看已驗證"))
        XCTAssertFalse(screens.contains("ink.friends.filter"))
        XCTAssertTrue(screens.contains("朋友去過的地方"))
        XCTAssertTrue(screens.contains("ink.friends.empty"))
        XCTAssertTrue(screens.contains("還沒有朋友的造訪"))
        XCTAssertFalse(screens.contains("ink.friends.error"))
        XCTAssertTrue(chrome.contains("B8481F"))
        XCTAssertEqual(chrome.components(separatedBy: "SaveInkPalette.accent").count - 1, 1)
        XCTAssertTrue(model.contains("SaveInkCheckIn"))
        XCTAssertFalse(model.contains("var latitude"))
        XCTAssertFalse(model.contains("var longitude"))
    }

    func testEmptyFriendsIsAStateAndDoesNotRequestLocation() {
        var made = 0
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.empty.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            friendInputs: [],
            makeLocator: {
                made += 1
                return SaveInkScriptedLocator()
            }
        )
        store.openFriends()
        XCTAssertTrue(store.friendCards().isEmpty)
        XCTAssertEqual(made, 0)
        XCTAssertEqual(SaveInkPreviewScreen.friendsEmpty.rawValue, "14-friends-empty")
    }

    func testShippingRootIsTheInkNotebookWithoutAFlag() throws {
        let app = try source("SAV-E/App/SaveApp.swift")
        let launch = try source("SAV-E/Views/InkNotebook/SaveInkNotebookRoot.swift")
        XCTAssertTrue(app.contains("SaveInkNotebookRoot()"))
        XCTAssertFalse(app.contains("ContentView("))
        XCTAssertFalse(app.contains("--savvy-ink-notebook"))
        XCTAssertFalse(launch.contains("--savvy-ink-notebook"))
        XCTAssertTrue(launch.contains("--savvy-ink-screen="))
        XCTAssertTrue(app.contains("SaveInkLaunch.previewScreen"))
    }

    func testFiveTabScreenshotBaselinesAreWithdrawn() {
        let names = [
            "home.png", "home-dark.png",
            "map.png", "map-light.png", "map-dark.png", "map-mask.png",
            "friends.png", "friends-dark.png",
            "passport.png", "passport-dark.png",
        ]
        let directory = repositoryRoot
            .appendingPathComponent("Prototypes/AtlasPostcard/Reference/ProductionTargets")
        for name in names {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                name
            )
        }
    }

    func testInkScreensRenderForTheSimulatorAttachment() throws {
        for screen in SaveInkPreviewScreen.allCases {
            let renderer = ImageRenderer(content: SaveInkScreenPreview(screen: screen))
            renderer.scale = 3
            renderer.proposedSize = ProposedViewSize(width: 393, height: 852)
            let image = try XCTUnwrap(renderer.uiImage, screen.rawValue)
            let data = try XCTUnwrap(image.pngData(), screen.rawValue)
            XCTAssertGreaterThan(data.count, 8_000, screen.rawValue)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ink-\(screen.rawValue).png")
            try data.write(to: url)
            let attachment = XCTAttachment(contentsOfFile: url)
            attachment.name = "ink-\(screen.rawValue).png"
            attachment.lifetime = .keepAlways
            add(attachment)
            let baseline = inkBaselineDirectory.appendingPathComponent("ink-\(screen.rawValue).png")
            if FileManager.default.fileExists(atPath: baseline.path) {
                let committed = try Data(contentsOf: baseline)
                XCTAssertEqual(md5(committed), md5(data), screen.rawValue)
            }
        }
    }

    func testInkNotebookBaselinesAwaitFounderApproval() throws {
        let names = SaveInkPreviewScreen.allCases.map { "ink-\($0.rawValue).png" }
        XCTAssertTrue(names.contains("ink-01-main.png"))
        XCTAssertTrue(names.contains("ink-03-passport.png"))
        XCTAssertTrue(names.contains("ink-12-friends.png"))
        XCTAssertTrue(names.contains("ink-14-friends-empty.png"))
        let design = try source("DESIGN.md")
        XCTAssertTrue(design.contains("pending founder approval"))
        XCTAssertTrue(design.contains("Reference/InkNotebook"))
        for name in names {
            let baseline = inkBaselineDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: baseline.path) else { continue }
            let data = try Data(contentsOf: baseline)
            XCTAssertEqual([UInt8](data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10], name)
            XCTAssertGreaterThan(data.count, 8_000, name)
        }
    }

    private func decision(_ fix: SaveInkFix) -> SaveInkCheckInDecision {
        SaveInkCheckIn.decide(fix: fix, verifiedToday: 0, impliedSpeedKmh: nil)
    }

    private func sampleVisit(
        placeID: String,
        at date: Date,
        verification: SaveInkVerification
    ) -> SaveInkVisitRecord {
        SaveInkVisitRecord(
            id: UUID(),
            placeID: placeID,
            visitedAt: date,
            verification: verification,
            visibility: .public,
            comment: "",
            sentiment: nil,
            anomaly: nil
        )
    }

    private func friend(
        _ author: String,
        _ name: String,
        count: Int,
        daysAgo: Int,
        verification: SaveInkVerification,
        visibility: SaveInkVisibility = .public,
        now: Date
    ) -> [SaveInkFriendVisitInput] {
        (0..<count).map { index in
            SaveInkFriendVisitInput(
                authorID: author,
                authorName: name,
                placeID: "place",
                placeName: "店",
                street: "街",
                comment: index == 0 ? "一句" : "",
                visitedAt: now.addingTimeInterval(TimeInterval(-(daysAgo + index) * 86_400)),
                verification: verification,
                visibility: visibility
            )
        }
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var inkBaselineDirectory: URL {
        repositoryRoot.appendingPathComponent("Prototypes/AtlasPostcard/Reference/InkNotebook")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
