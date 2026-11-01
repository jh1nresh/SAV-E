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
            "comment", "id", "placeID", "verification", "visibility", "visitedAt",
        ])
        XCTAssertNil(object["sentiment"])
        XCTAssertNil(object["anomaly"])
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

    func testF5SoftCheckInUsesAScriptedFix() async {
        let verified = await checkInStore(fix: .inRange(meters: 18))
        XCTAssertEqual(verified.sheet, .checkIn(.verified, placeID: SaveInkFixture.dingtai))
        let far = await checkInStore(fix: .inRange(meters: 320))
        XCTAssertEqual(far.sheet, .checkIn(.tooFar(meters: 320), placeID: SaveInkFixture.dingtai))
        var denied = SaveInkFix.inRange()
        denied.authorization = .denied
        let blocked = await checkInStore(fix: denied)
        XCTAssertEqual(blocked.sheet, .checkIn(.permissionDenied, placeID: SaveInkFixture.dingtai))
        var approximate = SaveInkFix.inRange()
        approximate.precise = false
        let coarse = await checkInStore(fix: approximate)
        XCTAssertEqual(coarse.sheet, .checkIn(.approximateOnly, placeID: SaveInkFixture.dingtai))
    }

    func testF6VisibilityIsSharedByTheVisitAndItsComment() async {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.f6.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator(fix: .inRange(meters: 18)) }
        )
        await store.checkIn(placeID: SaveInkFixture.dingtai)
        let created = store.latestVisit(for: SaveInkFixture.dingtai)
        XCTAssertEqual(created?.visibility, .public)
        XCTAssertEqual(created?.comment, "")
        store.draftComment = "只有我"
        store.draftVisibility = .private
        store.commitDraft()
        let saved = store.latestVisit(for: SaveInkFixture.dingtai)
        XCTAssertEqual(saved?.visibility, .private)
        XCTAssertEqual(saved?.comment, "只有我")
        let cards = SaveInkFriends.cards(from: [
            SaveInkFriendVisitInput(
                authorID: "a",
                authorName: "我",
                placeID: SaveInkFixture.dingtai,
                placeName: "店",
                street: "街",
                comment: saved?.comment ?? "",
                visitedAt: saved?.visitedAt ?? SaveInkClock.previewNow,
                verification: .verified,
                visibility: saved?.visibility ?? .public
            ),
        ])
        XCTAssertTrue(cards.isEmpty)
        XCTAssertEqual(SaveInkProvisional.defaultVisibility, .public)
    }

    func testF7FriendsSortVerifiedCountThenRecencyAndDoNotUseDistance() {
        let now = SaveInkClock.previewNow
        let cards = SaveInkFriends.cards(from: [
            friend("near", "近但少", count: 1, daysAgo: 1, verification: .verified, now: now),
            friend("far", "遠但多", count: 4, daysAgo: 9, verification: .verified, now: now),
            friend("new", "未驗證新", count: 1, daysAgo: 0, verification: .unverified, now: now),
            friend("old", "未驗證舊", count: 3, daysAgo: 6, verification: .unverified, now: now),
        ].flatMap { $0 })
        XCTAssertEqual(cards.map(\.authorName), ["遠但多", "近但少", "未驗證新", "未驗證舊"])
        XCTAssertEqual(cards.map(\.segment), [.verified, .verified, .unverified, .unverified])
    }

    func testF8PlaceRelatedCheckIsNotImplemented() throws {
        let model = try source("SAV-E/Views/InkNotebook/SaveInkNotebookModel.swift")
        XCTAssertFalse(model.contains("classifyPlace"))
        XCTAssertFalse(model.contains("placeRelated"))
        let suite = "save.ink.f8.\(UUID().uuidString)"
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: suite)!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() }
        )
        store.saveQuery = "https://www.youtube.com/watch?v=not-a-place"
        store.commitSave()
        XCTAssertTrue(store.places.contains { $0.name.contains("youtube.com") })
    }

    func testF9SavesVisitsStampsAndBundledFriendsSurviveReload() async {
        let suite = "save.ink.f9.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let now = SaveInkClock.previewNow
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { now },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator(fix: .inRange(meters: 18)) }
        )
        let seededVisits = store.totalVisits()
        await store.checkIn(placeID: SaveInkFixture.dingtai)
        store.saveQuery = "測試小店"
        store.commitSave()
        XCTAssertGreaterThan(store.totalVisits(), seededVisits)
        let visits = store.totalVisits()
        let stamps = store.stampedPlaceIDs()
        let friends = store.friendCards().map(\.authorName)
        XCTAssertFalse(friends.isEmpty)
        let reloaded = SaveInkNotebookStore(
            defaults: defaults,
            now: { now },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        XCTAssertEqual(reloaded.totalVisits(), visits)
        XCTAssertEqual(reloaded.stampedPlaceIDs(), stamps)
        XCTAssertTrue(reloaded.places.contains { $0.name == "測試小店" })
        XCTAssertEqual(reloaded.friendCards().map(\.authorName), friends)
        XCTAssertEqual(
            reloaded.latestVisit(for: SaveInkFixture.dingtai)?.visitedAt,
            store.latestVisit(for: SaveInkFixture.dingtai)?.visitedAt
        )
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
        XCTAssertFalse(app.contains("--uitest-legacy-root"))
        XCTAssertFalse(app.contains("--savvy-ink-notebook"))
        XCTAssertFalse(launch.contains("--savvy-ink-notebook"))
        XCTAssertTrue(launch.contains("--savvy-ink-screen="))
        XCTAssertTrue(launch.contains("--savvy-ink-empty-friends"))
        XCTAssertTrue(app.contains("SaveInkLaunch.previewScreen"))
    }

    func testSuiteParityReferencesStayOnDisk() {
        let names = [
            "home.png", "home-dark.png",
            "map-light.png", "map-dark.png", "map-mask.png",
            "friends.png", "friends-dark.png",
            "passport.png", "passport-dark.png",
            "saves.png", "plan.png", "capture.png", "paywall.png",
        ]
        let directory = repositoryRoot
            .appendingPathComponent("Prototypes/AtlasPostcard/Reference/ProductionTargets")
        for name in names {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                name
            )
        }
    }

    func testApprovedMapBaselineRemainsTheVisualReference() throws {
        let map = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png"
        )
        let data = try Data(contentsOf: map)
        XCTAssertEqual(
            md5(data),
            "711c9b3c54367281dab91b5fd094f047",
            "map.png stays the a5d62df8 approved visual reference"
        )
    }

    func testInkScreensRenderForTheSimulatorAttachment() throws {
        var rendered: [SaveInkPreviewScreen: Data] = [:]
        for screen in SaveInkPreviewScreen.allCases {
            let image = try hostedInkImage(screen)
            let data = try XCTUnwrap(image.pngData(), screen.rawValue)
            XCTAssertGreaterThan(data.count, 8_000, screen.rawValue)
            rendered[screen] = data
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ink-\(screen.rawValue).png")
            try data.write(to: url)
            let attachment = XCTAttachment(contentsOfFile: url)
            attachment.name = "ink-\(screen.rawValue).png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let main = try XCTUnwrap(rendered[.main])
        let passport = try XCTUnwrap(rendered[.passport])
        let review = try XCTUnwrap(rendered[.reviewVisibility])
        XCTAssertNotEqual(md5(passport), md5(review), "passport and review must not be the same blank paper")
        XCTAssertGreaterThan(
            nonPaperRatio(try XCTUnwrap(UIImage(data: main)), in: CGRect(x: 24, y: 150, width: 345, height: 460)),
            0.04,
            "home must draw the place cards, not only the header and button"
        )
        XCTAssertGreaterThan(
            nonPaperRatio(try XCTUnwrap(UIImage(data: passport)), in: CGRect(x: 16, y: 40, width: 360, height: 640)),
            0.04,
            "passport must draw stamps and the visit list"
        )
        XCTAssertGreaterThan(
            nonPaperRatio(try XCTUnwrap(UIImage(data: review)), in: CGRect(x: 16, y: 40, width: 360, height: 640)),
            0.04,
            "review must draw the stamp and the comment field"
        )
        let hashes = Set(rendered.values.map(sha256))
        XCTAssertEqual(hashes.count, SaveInkPreviewScreen.allCases.count, "every ink still must be a different image")
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `ImageRenderer` leaves `ScrollView` and `LazyVGrid` empty. A hosted
    /// window runs the real layout pass those screens need.
    @MainActor
    private func hostedInkImage(_ screen: SaveInkPreviewScreen) throws -> UIImage {
        let size = CGSize(width: 393, height: 852)
        let root = SaveInkScreenPreview(screen: screen)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    private func nonPaperRatio(_ image: UIImage, in rect: CGRect) -> Double {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { _ in
            image.draw(in: CGRect(
                x: -rect.minX * 48 / rect.width,
                y: -rect.minY * 48 / rect.height,
                width: image.size.width * 48 / rect.width,
                height: image.size.height * 48 / rect.height
            ))
        }
        guard let cg = sample.cgImage,
              let data = cg.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return 0 }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        var nonPaper = 0
        var samples = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pointer[offset])
                let green = Int(pointer[offset + 1])
                let blue = Int(pointer[offset + 2])
                samples += 1
                if abs(red - 250) > 14 || abs(green - 248) > 14 || abs(blue - 243) > 14 {
                    nonPaper += 1
                }
            }
        }
        return samples == 0 ? 0 : Double(nonPaper) / Double(samples)
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
            XCTAssertTrue(FileManager.default.fileExists(atPath: baseline.path), name)
            let data = try Data(contentsOf: baseline)
            XCTAssertEqual([UInt8](data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10], name)
            XCTAssertGreaterThan(data.count, 8_000, name)
        }
    }

    private func checkInStore(fix: SaveInkFix) async -> SaveInkNotebookStore {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.f5.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator(fix: fix) }
        )
        await store.checkIn(placeID: SaveInkFixture.dingtai)
        return store
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
