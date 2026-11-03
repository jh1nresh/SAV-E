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
            includeSampleCatalog: true,
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
            includeSampleCatalog: true,
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
        let now = SaveInkClock.previewNow
        let privateAccount = friend("b1", "阿哲", count: 2, daysAgo: 3, verification: .verified, now: now)
            + friend("b2", "凱文", count: 2, daysAgo: 1, verification: .verified, now: now)
            + friend("a", "我", count: 5, daysAgo: 0, verification: .verified, visibility: .private, now: now)
        let hidden = SaveInkFriends.cards(from: privateAccount)
        XCTAssertEqual(hidden.map(\.authorName), ["凱文", "阿哲"])
        XCTAssertFalse(hidden.contains { $0.authorName == "我" })
        let publicAccount = friend("b1", "阿哲", count: 2, daysAgo: 3, verification: .verified, now: now)
            + friend("b2", "凱文", count: 2, daysAgo: 1, verification: .verified, now: now)
            + friend("a", "我", count: 5, daysAgo: 0, verification: .verified, visibility: .public, now: now)
        XCTAssertEqual(SaveInkFriends.cards(from: publicAccount).map(\.authorName).first, "我")
    }

    func testF7FriendsSortVerifiedCountThenRecencyAndDoNotUseDistance() {
        let now = SaveInkClock.previewNow
        let cards = SaveInkFriends.cards(from: [
            friend("near", "近但少", count: 1, daysAgo: 1, verification: .verified, now: now),
            friend("far", "遠但多", count: 4, daysAgo: 9, verification: .verified, now: now),
            friend("tieNew", "同次數新", count: 2, daysAgo: 1, verification: .verified, now: now),
            friend("tieOld", "同次數舊", count: 2, daysAgo: 5, verification: .verified, now: now),
            friend("new", "未驗證新", count: 1, daysAgo: 0, verification: .unverified, now: now),
            friend("old", "未驗證舊", count: 3, daysAgo: 6, verification: .unverified, now: now),
        ].flatMap { $0 })
        XCTAssertGreaterThanOrEqual(cards.filter { $0.segment == .verified }.count, 3)
        XCTAssertEqual(cards.map(\.authorName), ["遠但多", "同次數新", "同次數舊", "近但少", "未驗證新", "未驗證舊"])
        XCTAssertEqual(cards.map(\.segment), [.verified, .verified, .verified, .verified, .unverified, .unverified])
    }

    func testF8NonPlaceLinkIsRejected() async {
        let link = "https://notes.example/article/how-to-film"
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.f8.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() }
        )
        let ids = store.places.map(\.id)
        store.saveQuery = link
        store.commitSave()
        XCTAssertEqual(store.places.map(\.id), ids)
        XCTAssertEqual(store.saveNotice, SaveInkPlaceLink.notAPlaceMessage)
        XCTAssertFalse(store.places.contains { $0.name.contains("notes.example") })
        await store.checkIn(placeID: "saved-\(SaveInkSeed.of(link))")
        XCTAssertEqual(store.totalVisits(), 0)
        XCTAssertTrue(store.stampedPlaceIDs().isEmpty)
        XCTAssertFalse(
            SaveInkPlaceLink.hasPlaceEvidence(link, knownPlaces: store.places)
        )
    }

    func testF8ShareMenuReadsPlacesTheAppSaved() {
        let key = SavePlaceLinkGate.placesKey
        let shared = SavePlaceLinkGate.sharedPlacesDefaults()
        let legacy = UserDefaults.standard
        let previousShared = shared.data(forKey: key)
        let previousLegacy = legacy.data(forKey: key)
        defer {
            if let previousShared { shared.set(previousShared, forKey: key) } else { shared.removeObject(forKey: key) }
            if let previousLegacy { legacy.set(previousLegacy, forKey: key) } else { legacy.removeObject(forKey: key) }
        }
        shared.removeObject(forKey: key)
        legacy.removeObject(forKey: key)
        let store = SaveInkNotebookStore(
            defaults: .standard,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() }
        )
        store.saveQuery = "分享測試小店"
        store.commitSave()
        XCTAssertNil(legacy.data(forKey: key))
        XCTAssertNotNil(shared.data(forKey: key))
        let names = SavePlaceLinkGate.knownPlaceNames()
        XCTAssertTrue(names.contains("分享測試小店"))
        let video = "https://www.youtube.com/watch?v=shop-tour"
        XCTAssertFalse(SavePlaceLinkGate.rejects(
            urlString: video,
            evidence: "介紹分享測試小店",
            knownPlaceNames: names
        ))
        XCTAssertEqual(
            SavePlaceLinkGate.linkedPlaceName(in: "介紹分享測試小店\n\(video)", knownPlaceNames: names),
            "分享測試小店"
        )
        let article = "https://notes.example/article/how-to-film"
        XCTAssertTrue(SavePlaceLinkGate.rejects(urlString: article, evidence: "how to film", knownPlaceNames: names))
        XCTAssertNil(SavePlaceLinkGate.linkedPlaceName(in: article, knownPlaceNames: names))
    }

    func testF8ShopVideoStaysLinkedToThePlace() {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.f8.place.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            includeSampleCatalog: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        store.saveQuery = "https://www.youtube.com/watch?v=shop-tour 青田七六咖啡"
        store.commitSave()
        XCTAssertNil(store.saveNotice)
        XCTAssertEqual(store.recognizedPlaceID, SaveInkFixture.qingtian)
        XCTAssertEqual(store.place(SaveInkFixture.qingtian)?.badge, .saved)
        XCTAssertFalse(store.places.contains { $0.id.hasPrefix("saved-") })
        XCTAssertFalse(store.places.contains { $0.name.contains("youtube.com") })
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
        store.draftComment = "留下"
        store.draftVisibility = .private
        store.commitDraft()
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
        XCTAssertEqual(reloaded.latestVisit(for: SaveInkFixture.dingtai)?.visibility, .private)
        XCTAssertEqual(reloaded.latestVisit(for: SaveInkFixture.dingtai)?.comment, "留下")
    }

    func testF9MainSchemaSurvivesUpgradeAndReload() throws {
        let suite = "save.ink.f9.upgrade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let visitID = UUID()
        let visits = """
        [{
          "id": "\(visitID.uuidString)",
          "placeID": "dingtai",
          "visitedAt": "2026-10-28T04:00:00Z",
          "verification": "verified",
          "comment": "main 留下的"
        }]
        """
        defaults.set(Data(visits.utf8), forKey: "save.ink.visits.v1")
        let places = """
        [{
          "id": "saved-main-shop",
          "name": "主線小店",
          "stampName": "主線小店",
          "street": "主線街",
          "blurb": "升級前存的",
          "sourceLabel": "來自 main",
          "detailNote": "舊收藏沒有可見度欄位"
        }]
        """
        defaults.set(Data(places.utf8), forKey: "save.ink.places.v1")
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        let visit = try XCTUnwrap(store.latestVisit(for: "dingtai"))
        XCTAssertEqual(visit.id, visitID)
        XCTAssertEqual(visit.visibility, .public)
        XCTAssertEqual(visit.comment, "main 留下的")
        XCTAssertEqual(store.totalVisits(), 1)
        XCTAssertEqual(store.stampedPlaceIDs(), ["dingtai"])
        XCTAssertTrue(store.places.contains { $0.name == "主線小店" })
        let friends = store.friendCards().map(\.authorName)
        XCTAssertFalse(friends.isEmpty)
        let reloaded = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        XCTAssertEqual(reloaded.latestVisit(for: "dingtai")?.visibility, .public)
        XCTAssertEqual(reloaded.latestVisit(for: "dingtai")?.comment, "main 留下的")
        XCTAssertEqual(reloaded.totalVisits(), 1)
        XCTAssertEqual(reloaded.stampedPlaceIDs(), ["dingtai"])
        XCTAssertTrue(reloaded.places.contains { $0.name == "主線小店" })
        XCTAssertEqual(reloaded.friendCards().map(\.authorName), friends)
    }

    func testF9StandardPlacesMigrateIntoTheSharedStore() throws {
        let key = SavePlaceLinkGate.placesKey
        let shared = SavePlaceLinkGate.sharedPlacesDefaults()
        let legacy = UserDefaults.standard
        let previousShared = shared.data(forKey: key)
        let previousLegacy = legacy.data(forKey: key)
        defer {
            if let previousShared { shared.set(previousShared, forKey: key) } else { shared.removeObject(forKey: key) }
            if let previousLegacy { legacy.set(previousLegacy, forKey: key) } else { legacy.removeObject(forKey: key) }
        }
        shared.removeObject(forKey: key)
        let places = """
        [{
          "id": "saved-main-shop",
          "name": "主線小店",
          "stampName": "主線小店",
          "street": "主線街",
          "blurb": "升級前存的",
          "sourceLabel": "來自 main",
          "detailNote": "舊收藏在 App 容器"
        }]
        """
        legacy.set(Data(places.utf8), forKey: key)
        let store = SaveInkNotebookStore(
            defaults: .standard,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() }
        )
        XCTAssertTrue(store.places.contains { $0.name == "主線小店" })
        XCTAssertNotNil(shared.data(forKey: key))
        let reloaded = SaveInkNotebookStore(
            defaults: .standard,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() }
        )
        XCTAssertTrue(reloaded.places.contains { $0.name == "主線小店" })
        XCTAssertEqual(SavePlaceLinkGate.knownPlaceNames().contains("主線小店"), true)
    }

    func testF10InkControlsHaveLabelsHitTargetsAndAreNotColorOnly() throws {
        let chrome = try source("SAV-E/Views/InkNotebook/SaveInkNotebookChrome.swift")
        let screens = try source("SAV-E/Views/InkNotebook/SaveInkNotebookScreens.swift")
        XCTAssertTrue(chrome.contains(".accessibilityLabel(\"返回\")"))
        XCTAssertTrue(chrome.contains(".frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(chrome.contains("relativeTo:"))
        XCTAssertTrue(screens.contains("ink.friends.entry"))
        XCTAssertTrue(screens.contains(".frame(height: 50)"))
        XCTAssertTrue(chrome.contains("ink.arrived"))
        XCTAssertTrue(screens.contains("✓ 去過"))
        XCTAssertTrue(screens.contains("△ 未驗證") || chrome.contains("△ 未驗證"))
        XCTAssertTrue(screens.contains("○ 存了還沒去"))
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
        XCTAssertTrue(screens.contains("朋友還沒有分享造訪"))
        XCTAssertTrue(screens.contains("朋友把造訪設成公開後，就會出現在這裡"))
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

    func testNormalLaunchOmitsSampleShopsFriendsAndCheckIns() {
        let defaults = inkSuite("normal")
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow }
        )
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertTrue(store.friendCards().isEmpty)
        XCTAssertEqual(store.totalVisits(), 0)
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1"))
        XCTAssertTrue(defaults.bool(forKey: SaveInkNotebookStore.sampleCheckInMigrationKey))
        XCTAssertEqual(SaveInkFixture.samplePlaceIDs.count, 5)
    }

    func testFixtureLaunchStillSeedsSampleShopsFriendsAndCheckIns() throws {
        let defaults = inkSuite("fixture")
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: true
        )
        XCTAssertEqual(store.places.prefix(5).map(\.id), SaveInkFixture.places.map(\.id))
        XCTAssertEqual(
            store.homePlaces().prefix(3).map(\.id),
            [SaveInkFixture.dingtai, SaveInkFixture.qingtian, SaveInkFixture.chifeng]
        )
        XCTAssertEqual(store.friendCards().map(\.authorName), ["阿哲", "凱文", "茉茉", "小安"])
        let seeded = SaveInkFixture.visits()
        XCTAssertEqual(store.totalVisits(), seeded.count)
        // 青田七六 is a saved shop in the catalog. It has no seeded check-in.
        let seededPlaceIDs = Set(seeded.map(\.placeID))
        XCTAssertEqual(
            seededPlaceIDs,
            [
                SaveInkFixture.dingtai,
                SaveInkFixture.chifeng,
                SaveInkFixture.huashan,
                SaveInkFixture.dadaocheng,
            ]
        )
        XCTAssertFalse(seededPlaceIDs.contains(SaveInkFixture.qingtian))
        let stored = try XCTUnwrap(defaults.data(forKey: "save.ink.visits.v1"))
        let text = String(decoding: stored, as: UTF8.self)
        for placeID in seededPlaceIDs {
            XCTAssertTrue(text.contains(placeID), placeID)
        }
        XCTAssertFalse(text.contains(SaveInkFixture.qingtian))
        XCTAssertFalse(text.contains("saved-"))
        XCTAssertFalse(defaults.bool(forKey: SaveInkNotebookStore.sampleCheckInMigrationKey))
    }

    func testSampleCheckInMigrationRemovesOnlyUntouchedSeedVisits() throws {
        let defaults = inkSuite("migrate")
        let userVisit = inkVisit(placeID: "saved-mine", comment: "我的店，比鼎泰小館好")
        let otherVisit = inkVisit(placeID: "walk-note", comment: "自己走去的")
        var commentedSample = inkVisit(placeID: SaveInkFixture.dingtai, comment: "我真的去了")
        commentedSample.visibility = .private
        var ratedSample = inkVisit(placeID: SaveInkFixture.qingtian, comment: "")
        ratedSample.sentiment = .again
        let seed = try XCTUnwrap(SaveInkFixture.visits().first { $0.placeID == SaveInkFixture.dingtai })
        XCTAssertTrue(SaveInkFixture.isUntouchedSeedVisit(seed))
        XCTAssertFalse(SaveInkFixture.isUntouchedSeedVisit(commentedSample))
        XCTAssertFalse(SaveInkFixture.isUntouchedSeedVisit(ratedSample))
        let visitsBefore = try SaveInkNotebookStore.encoder.encode([
            seed, userVisit, commentedSample, ratedSample, otherVisit,
        ])
        defaults.set(visitsBefore, forKey: "save.ink.visits.v1")
        let placesBefore = Data("{\"id\":\"saved-mine\"}".utf8)
        defaults.set(placesBefore, forKey: "save.ink.places.v1")

        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false
        )
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.dingtai)?.id, commentedSample.id)
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.dingtai)?.comment, "我真的去了")
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.dingtai)?.visibility, .private)
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.qingtian)?.id, ratedSample.id)
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.qingtian)?.sentiment, .again)
        XCTAssertEqual(store.latestVisit(for: "saved-mine")?.comment, "我的店，比鼎泰小館好")
        XCTAssertEqual(store.latestVisit(for: "walk-note")?.comment, "自己走去的")
        XCTAssertEqual(store.totalVisits(), 4)
        XCTAssertEqual(defaults.data(forKey: "save.ink.places.v1"), placesBefore)
        let stored = try XCTUnwrap(defaults.data(forKey: "save.ink.visits.v1"))
        let text = String(decoding: stored, as: UTF8.self)
        XCTAssertFalse(text.contains(seed.id.uuidString))
        XCTAssertTrue(text.contains(commentedSample.id.uuidString))
        XCTAssertTrue(text.contains("我真的去了"))
        XCTAssertTrue(text.contains("saved-mine"))
        XCTAssertNotEqual(stored, visitsBefore)
    }

    func testSampleCheckInMigrationLeavesUntouchedVisitsByteForByte() throws {
        let defaults = inkSuite("migrate-user")
        let userVisit = inkVisit(placeID: "saved-mine", comment: "只有這則")
        let original = try SaveInkNotebookStore.encoder.encode([userVisit])
        defaults.set(original, forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow }
        )
        XCTAssertEqual(store.latestVisit(for: "saved-mine")?.id, userVisit.id)
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1"), original)
    }

    func testSampleCheckInMigrationRunsOnce() throws {
        let defaults = inkSuite("migrate-once")
        let seed = try XCTUnwrap(SaveInkFixture.visits().first { $0.placeID == SaveInkFixture.huashan })
        defaults.set(
            try SaveInkNotebookStore.encoder.encode([
                seed,
                inkVisit(placeID: "saved-mine", comment: "留下"),
            ]),
            forKey: "save.ink.visits.v1"
        )
        let first = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertNil(first.latestVisit(for: SaveInkFixture.huashan))
        XCTAssertEqual(first.latestVisit(for: "saved-mine")?.comment, "留下")

        let revived = try XCTUnwrap(SaveInkFixture.visits().first { $0.placeID == SaveInkFixture.dadaocheng })
        let kept = try XCTUnwrap(first.latestVisit(for: "saved-mine"))
        defaults.set(
            try SaveInkNotebookStore.encoder.encode([kept, revived]),
            forKey: "save.ink.visits.v1"
        )
        let second = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertEqual(second.latestVisit(for: SaveInkFixture.dadaocheng)?.id, revived.id)
        XCTAssertEqual(second.latestVisit(for: "saved-mine")?.comment, "留下")
        XCTAssertEqual(second.totalVisits(), 2)
    }

    func testFixtureModeDoesNotConsumeTheSampleCheckInMigration() throws {
        let defaults = inkSuite("fixture-keeps-samples")
        let seed = try XCTUnwrap(SaveInkFixture.visits().first { $0.placeID == SaveInkFixture.dingtai })
        defaults.set(
            try SaveInkNotebookStore.encoder.encode([
                seed,
                inkVisit(placeID: "saved-mine", comment: "我的"),
            ]),
            forKey: "save.ink.visits.v1"
        )
        let fixture = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: true
        )
        XCTAssertEqual(fixture.latestVisit(for: SaveInkFixture.dingtai)?.id, seed.id)
        XCTAssertFalse(defaults.bool(forKey: SaveInkNotebookStore.sampleCheckInMigrationKey))

        let production = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false
        )
        XCTAssertNil(production.latestVisit(for: SaveInkFixture.dingtai))
        XCTAssertEqual(production.latestVisit(for: "saved-mine")?.comment, "我的")
        XCTAssertTrue(production.friendCards().isEmpty)
        XCTAssertFalse(production.places.contains { SaveInkFixture.samplePlaceIDs.contains($0.id) })
    }

    func testUserConfirmedSamplePlaceVisitStaysByteForByte() throws {
        let defaults = inkSuite("user-sample")
        let visit = inkVisit(placeID: SaveInkFixture.dingtai, comment: "只有我寫的")
        let original = try SaveInkNotebookStore.encoder.encode([visit])
        defaults.set(original, forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.dingtai)?.id, visit.id)
        XCTAssertEqual(store.latestVisit(for: SaveInkFixture.dingtai)?.comment, "只有我寫的")
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1"), original)
        XCTAssertEqual(store.place(SaveInkFixture.dingtai)?.name, "鼎泰小館")
        XCTAssertEqual(store.place(SaveInkFixture.dingtai)?.stampName, "鼎泰小館")
        XCTAssertEqual(store.place(SaveInkFixture.dingtai)?.street, "永康街")
        XCTAssertEqual(store.place(SaveInkFixture.dingtai)?.friendUsualCount, 0)
        XCTAssertEqual(store.place(SaveInkFixture.dingtai)?.detailNote, "你保留的到訪紀錄。")
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.walkMinutes)
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.distanceMeters)
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.videoTitle)
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.videoSource)
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.shopLatitude)
        XCTAssertNil(store.place(SaveInkFixture.dingtai)?.shopLongitude)
        XCTAssertFalse(store.homePlaces().contains { $0.id == SaveInkFixture.dingtai })
        XCTAssertNil(store.place(SaveInkFixture.qingtian))
        XCTAssertEqual(defaults.data(forKey: "save.ink.places.v1"), nil)
    }

    func testArrivalRequiresAShopPosition() {
        let saved = SaveInkNotebookStore(
            defaults: inkSuite("arrival-saved"),
            now: { SaveInkClock.previewNow }
        )
        saved.saveQuery = "我的店"
        saved.commitSave()
        XCTAssertEqual(saved.homePlaces().first?.name, "我的店")
        XCTAssertNil(saved.homePlaces().first?.shopLatitude)
        XCTAssertNil(saved.arrivalPlaceID())

        let fixture = SaveInkNotebookStore(
            defaults: inkSuite("arrival-fixture"),
            now: { SaveInkClock.previewNow },
            seedFixture: true
        )
        XCTAssertEqual(fixture.arrivalPlaceID(), SaveInkFixture.dingtai)
    }

    func testUnlocatedVisitIsExplicitlyUnverifiedAndNeverRequestsLocation() throws {
        let defaults = inkSuite("unlocated-visit")
        let locator = SaveInkScriptedLocator(fix: .inRange())
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow }, makeLocator: { locator })
        store.saveQuery = "沒有座標的小店"
        store.commitSave()
        let id = try XCTUnwrap(store.homePlaces().first?.id)
        XCTAssertEqual(store.homeBadge(for: try XCTUnwrap(store.place(id))), .saved)
        store.recordUnverifiedVisit(placeID: id)
        XCTAssertEqual(store.homeBadge(for: try XCTUnwrap(store.place(id))), .unverified)
        XCTAssertEqual(locator.calls, 0)
        XCTAssertEqual(store.latestVisit(for: id)?.verification, .unverified)
        XCTAssertNil(store.latestVisit(for: id)?.anomaly)
        XCTAssertEqual(store.verifiedCount(for: id), 0)
        XCTAssertEqual(store.visitCount(for: id), 1)
        XCTAssertEqual(store.sheet, .checkIn(.downgradedUnverified, placeID: id))
        store.recordUnverifiedVisit(placeID: id)
        XCTAssertEqual(store.totalVisits(), 1)
        XCTAssertEqual(store.sheet, .checkIn(.duplicate, placeID: id))
        let reloaded = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertEqual(reloaded.latestVisit(for: id)?.verification, .unverified)
        XCTAssertEqual(reloaded.visitCount(for: id), 1)
        XCTAssertEqual(reloaded.verifiedCount(for: id), 0)
        XCTAssertEqual(reloaded.stampedPlaceIDs(), [id])
        XCTAssertEqual(reloaded.homeBadge(for: try XCTUnwrap(reloaded.place(id))), .unverified)
    }

    func testPasteExampleLinkStaysInsideTheFixtureCatalog() {
        let fixture = SaveInkNotebookStore(
            defaults: inkSuite("paste-fixture"),
            now: { SaveInkClock.previewNow },
            seedFixture: true
        )
        fixture.pasteExampleLink()
        XCTAssertEqual(fixture.saveLink, "https://短影音連結/v/8f2k…")
        XCTAssertEqual(fixture.recognizedPlaceID, SaveInkFixture.qingtian)

        let production = SaveInkNotebookStore(
            defaults: inkSuite("paste-production"),
            now: { SaveInkClock.previewNow }
        )
        production.pasteExampleLink()
        XCTAssertEqual(production.saveLink, "")
        XCTAssertNil(production.recognizedPlaceID)
    }

    func testUnlocatedVisitScreensRenderForQA() throws {
        let store = SaveInkNotebookStore(defaults: inkSuite("unlocated-render"), now: { SaveInkClock.previewNow })
        store.saveQuery = "沒有座標的長店名小店"
        store.commitSave()
        let id = try XCTUnwrap(store.homePlaces().first?.id)
        store.recordUnverifiedVisit(placeID: id)
        for width: CGFloat in [375, 390, 430] {
            for (name, image) in [
                ("home", try hostedInkImage(SaveInkHomeScreen(store: store), width: width)),
                ("place", try hostedInkImage(SaveInkPlaceScreen(store: store, placeID: id), width: width)),
            ] {
                let data = try XCTUnwrap(image.pngData())
                XCTAssertGreaterThan(data.count, 8_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "ink-unverified-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testRetainedSampleVisitDoesNotEnableFixturePaste() throws {
        let defaults = inkSuite("retained-sample-paste")
        let visit = inkVisit(placeID: SaveInkFixture.qingtian, comment: "自己寫的")
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertNotNil(store.place(SaveInkFixture.qingtian))
        store.pasteExampleLink()
        XCTAssertEqual(store.saveLink, "")
        XCTAssertNil(store.recognizedPlaceID)
    }

    func testCommitSaveIgnoresAnUnresolvedRecognizedPlace() {
        let store = SaveInkNotebookStore(
            defaults: inkSuite("dangling-place"),
            now: { SaveInkClock.previewNow }
        )
        store.recognizedPlaceID = SaveInkFixture.qingtian
        store.saveQuery = "我的店"
        store.commitSave()
        XCTAssertNil(store.sheet)
        let saved = store.places.first { $0.name == "我的店" }
        XCTAssertEqual(saved?.id.hasPrefix("saved-"), true)
        XCTAssertEqual(store.recognizedPlaceID, saved?.id)
        XCTAssertFalse(store.places.contains { $0.id == SaveInkFixture.qingtian })
    }

    func testExplicitSavePromotesARetainedPlaceAndKeepsItsVisit() throws {
        let defaults = inkSuite("retained-place-save")
        let visit = inkVisit(placeID: SaveInkFixture.qingtian, comment: "自己寫的到訪")
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertTrue(store.homePlaces().isEmpty)
        store.saveQuery = "青田七六咖啡"
        XCTAssertNil(store.recognizedPlaceID)
        store.commitSave()
        let saved = try XCTUnwrap(store.homePlaces().first)
        XCTAssertEqual(saved.name, "青田七六咖啡")
        XCTAssertTrue(saved.id.hasPrefix("saved-"))
        XCTAssertEqual(store.latestVisit(for: saved.id)?.id, visit.id)
        XCTAssertEqual(store.latestVisit(for: saved.id)?.comment, visit.comment)
        XCTAssertEqual(store.recognizedPlaceID, saved.id)
        XCTAssertNil(store.place(SaveInkFixture.qingtian))
        store.commitSave()
        XCTAssertEqual(store.homePlaces().count, 1)
        let reloaded = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertEqual(reloaded.homePlaces().map(\.id), [saved.id])
        XCTAssertEqual(reloaded.latestVisit(for: saved.id)?.id, visit.id)
        XCTAssertEqual(reloaded.latestVisit(for: saved.id)?.comment, visit.comment)
    }

    func testCorruptVisitPayloadIsNotDeleted() {
        let defaults = inkSuite("corrupt")
        let payload = Data("not-json".utf8)
        defaults.set(payload, forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow })
        XCTAssertEqual(store.totalVisits(), 0)
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1"), payload)
        XCTAssertFalse(defaults.bool(forKey: SaveInkNotebookStore.sampleCheckInMigrationKey))
    }

    func testInkLaunchArgsGateFixtureData() {
        XCTAssertFalse(SaveInkLaunch.usesFixtureData(arguments: []))
        XCTAssertFalse(SaveInkLaunch.usesFixtureData(arguments: ["--savvy-ink-skip-welcome"]))
        XCTAssertFalse(SaveInkLaunch.usesFixtureData(arguments: ["--uitest-complete-onboarding"]))
        XCTAssertTrue(SaveInkLaunch.usesFixtureData(arguments: ["--savvy-ink-suite=ink-nav"]))
        XCTAssertTrue(SaveInkLaunch.usesFixtureData(arguments: ["--savvy-ink-screen=01-main"]))
        XCTAssertEqual(SaveInkLaunch.friendInputs(arguments: [])?.count, Optional(0))
        XCTAssertEqual(
            SaveInkLaunch.friendInputs(arguments: ["--savvy-ink-suite=x", "--savvy-ink-empty-friends"])?.count,
            Optional(0)
        )
        XCTAssertNil(SaveInkLaunch.friendInputs(arguments: ["--savvy-ink-suite=x"]))
    }

    func testHomeEmptyStateUsesInkCopy() throws {
        let screens = try source("SAV-E/Views/InkNotebook/SaveInkNotebookScreens.swift")
        XCTAssertTrue(screens.contains("ink.home.empty"))
        XCTAssertTrue(screens.contains("還沒有地點"))
        XCTAssertTrue(screens.contains("存一個地點，到了再記"))
        XCTAssertTrue(screens.contains("輕點卡片，看地圖怎麼走"))
        XCTAssertFalse(screens.contains("?? SaveInkFixture.dingtai"))
        XCTAssertTrue(screens.contains("store.arrivalPlaceID()"))
        XCTAssertTrue(screens.contains("ink.friends.empty"))
        XCTAssertTrue(screens.contains("朋友還沒有分享造訪"))
    }

    func testApprovedInkBaselinesStayByteIdentical() throws {
        let expected = [
            "ink-01-main.png": "722549d8eaa490abe201e32b90d9ce0df4785df41c0773f7b4c0d4337ae4a0d2",
            "ink-02-save-place.png": "9c48fda0ef1d36d8ef3a4f68d0879b449a45ecb56e55ae795c86c0bc888280e0",
            "ink-03-passport.png": "d97d2478fe3c68ad16b3d686f591f8fa6e05672bfb2e43d6a0ad4e410c3cfb63",
            "ink-04-stamp-confirm.png": "6e92b8dcb3e24bfef7118038c0ad37b680962f30587b7331e46927463092a109",
            "ink-05-shop-detail.png": "c3f349fa26a479c6fc9f2b0d90395a7e1e6dc9412fdee5e2521824e13d6ba70e",
            "ink-06-welcome.png": "10f7662191fa12dfd91670428e9a3ef78390a5c7d67e987d9b171361f6fd27b1",
            "ink-07-checkin-success.png": "4748cade0d4bb218239f5adb71505aa0a5d0dfb0782fc04dd0fca8a1f40071c3",
            "ink-08-checkin-failed.png": "9a6dbdb255f6ee333515399bf9ede43c0c36283ef12d9fd73173bc24755c9140",
            "ink-09-checkin-no-permission.png": "a42cabd3796ef960c5e034941d3e5cd324f673234c288d7ae5c6ffdc271f38c7",
            "ink-10-checkin-approximate.png": "e1efe0c7a28ebbf19ca7648b0e63069954d9002eebedbdffd392fd35276e2105",
            "ink-11-checkin-too-far.png": "46cbb73ad807d86278720e41cf8486b0df12de01a34104f7cf58df21bb827f36",
            "ink-12-friends.png": "657a1fd868f9964fe99eb9cf89f558ac70835de6eeb07cc7ffec8c7ddf519bc7",
            "ink-13-review-visibility.png": "17130bdd98c22c354033425c041c91d371231bb6a8d8c61ec05ef1ac5ccd64da",
            "ink-14-friends-empty.png": "c389eba15e92a8536eb29adb7a42865402b81ba86bf19094ff2ca231c3b7aa8c",
        ]
        XCTAssertEqual(expected.count, SaveInkPreviewScreen.allCases.count)
        for (name, hash) in expected {
            let data = try Data(contentsOf: inkBaselineDirectory.appendingPathComponent(name))
            XCTAssertEqual(sha256(data), hash, name)
        }
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

    func testInkTextContrastMeetsWCAG() throws {
        let chrome = try source("SAV-E/Views/InkNotebook/SaveInkNotebookChrome.swift")
        func hex(named name: String) throws -> (Double, Double, Double) {
            let token = "static let \(name) = Color(hex: \""
            let range = try XCTUnwrap(chrome.range(of: token), name)
            let start = range.upperBound
            let end = chrome.index(start, offsetBy: 6)
            let value = try XCTUnwrap(UInt32(chrome[start..<end], radix: 16), name)
            return (
                Double((value >> 16) & 0xFF),
                Double((value >> 8) & 0xFF),
                Double(value & 0xFF)
            )
        }
        let ink = try hex(named: "ink")
        let inkSub = try hex(named: "inkSub")
        let paper = try hex(named: "paper")
        let card = try hex(named: "card")
        let fill = try hex(named: "unverifiedFill")
        let accent = try hex(named: "accent")
        let white = (255.0, 255.0, 255.0)
        let pairs: [(String, (Double, Double, Double), (Double, Double, Double))] = [
            ("ink on paper", ink, paper),
            ("ink on card", ink, card),
            ("ink on unverified fill", ink, fill),
            ("secondary text on paper", inkSub, paper),
            ("secondary text on card", inkSub, card),
            ("secondary text on unverified fill", inkSub, fill),
            ("white on accent", white, accent),
        ]
        var lowest = Double.greatestFiniteMagnitude
        var lowestName = ""
        for (name, text, background) in pairs {
            let ratio = wcagContrast(text, background)
            if ratio < lowest {
                lowest = ratio
                lowestName = name
            }
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) \(ratio)")
        }
        XCTAssertGreaterThanOrEqual(lowest, 4.5, "lowest \(lowestName) \(lowest)")
        XCTAssertEqual(paper.0, 250)
        XCTAssertEqual(paper.1, 249)
        XCTAssertEqual(paper.2, 244)
        XCTAssertEqual(accent.0, 184)
        XCTAssertEqual(accent.1, 72)
        XCTAssertEqual(accent.2, 31)
    }

    func testInkScreensRenderForTheSimulatorAttachment() throws {
        var rendered: [SaveInkPreviewScreen: Data] = [:]
        for screen in SaveInkPreviewScreen.allCases {
            let image = try hostedInkImage(screen)
            let data = try XCTUnwrap(image.pngData(), screen.rawValue)
            XCTAssertGreaterThan(data.count, 8_000, screen.rawValue)
            XCTAssertTrue(topBandIsPaper(image), "\(screen.rawValue) status-bar band must be paper, not the hosting view's white")
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

    private func wcagContrast(
        _ text: (Double, Double, Double),
        _ background: (Double, Double, Double)
    ) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = channel / 255
            if value <= 0.04045 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        func luminance(_ color: (Double, Double, Double)) -> Double {
            0.2126 * linear(color.0) + 0.7152 * linear(color.1) + 0.0722 * linear(color.2)
        }
        let lighter = max(luminance(text), luminance(background))
        let darker = min(luminance(text), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func topBandIsPaper(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return false }
        let width = cg.width
        let rows = min(72, cg.height)
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        var red = 0
        var green = 0
        var blue = 0
        var count = 0
        for y in 0..<rows {
            for x in stride(from: 0, to: width, by: 8) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                red += Int(pointer[offset])
                green += Int(pointer[offset + 1])
                blue += Int(pointer[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return false }
        let meanRed = red / count
        let meanGreen = green / count
        let meanBlue = blue / count
        let paperDistance = abs(meanRed - 250) + abs(meanGreen - 249) + abs(meanBlue - 244)
        let whiteDistance = abs(meanRed - 255) + abs(meanGreen - 255) + abs(meanBlue - 255)
        return paperDistance < whiteDistance
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `ImageRenderer` leaves `ScrollView` and `LazyVGrid` empty. A hosted
    /// window runs the real layout pass those screens need.
    @MainActor
    private func hostedInkImage(_ screen: SaveInkPreviewScreen) throws -> UIImage {
        try hostedInkImage(SaveInkScreenPreview(screen: screen))
    }

    @MainActor
    private func hostedInkImage<Content: View>(_ root: Content, width: CGFloat = 393) throws -> UIImage {
        let size = CGSize(width: width, height: 852)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .light
        let paper = UIColor(red: 250.0 / 255, green: 249.0 / 255, blue: 244.0 / 255, alpha: 1)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .light
        window.backgroundColor = paper
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.backgroundColor = paper
        host.view.isOpaque = true
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        format.preferredRange = .standard
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
                if abs(red - 250) > 14 || abs(green - 249) > 14 || abs(blue - 244) > 14 {
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

    private func inkSuite(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "save.ink.\(name).\(UUID().uuidString)")!
    }

    private func inkVisit(placeID: String, comment: String) -> SaveInkVisitRecord {
        SaveInkVisitRecord(
            id: UUID(),
            placeID: placeID,
            visitedAt: SaveInkClock.previewNow,
            verification: .verified,
            visibility: .public,
            comment: comment,
            sentiment: nil,
            anomaly: nil
        )
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
