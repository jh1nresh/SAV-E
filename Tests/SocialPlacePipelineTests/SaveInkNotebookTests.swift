import CoreLocation
import CryptoKit
import MapKit
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
        let size = CGSize(width: 393, height: 852)
        let root = SaveInkScreenPreview(screen: screen)
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

    func testLiveLaunchKeepsFixtureNotebookForInkArguments() {
        XCTAssertFalse(SaveInkLaunch.usesLivePlaces(arguments: ["--savvy-ink-screen=01-main"]))
        XCTAssertFalse(SaveInkLaunch.usesLivePlaces(arguments: ["--savvy-ink-skip-welcome"]))
        XCTAssertFalse(SaveInkLaunch.usesLivePlaces(arguments: ["--savvy-ink-suite=ink-nav"]))
        XCTAssertTrue(SaveInkLaunch.usesLivePlaces(arguments: ["--uitest-complete-onboarding"]))
        XCTAssertTrue(SaveInkLaunch.usesLivePlaces(arguments: []))
    }

    func testCatalogDedupesVaultPendingAndInkAndKeepsCoordinates() throws {
        let confirmed = Place.from(inkPending(
            name: "青田七六咖啡",
            address: "台北市大安區青田街",
            latitude: 25.0272,
            longitude: 121.5328,
            google: "google-qingtian"
        ))
        let duplicate = inkPending(
            name: "青田七六",
            address: "台北市大安區青田街",
            latitude: 25.0273,
            longitude: 121.5329,
            google: "google-qingtian"
        )
        let shared = inkPending(
            name: "赤峰街麵店",
            address: "台北市中山區赤峰街",
            latitude: 25.0562,
            longitude: 121.5264
        )
        let ink = inkRow(id: "saved-qingtian", name: "青田七六咖啡", street: "青田街")
        let rows = SaveInkPlaceCatalog.merge(
            ink: [ink],
            confirmed: [confirmed],
            pending: [duplicate, shared],
            userLocation: CLLocation(latitude: 25.0260, longitude: 121.5320)
        )
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.name)), Set(["青田七六咖啡", "赤峰街麵店"]))
        let inkQingtian = try XCTUnwrap(rows.first { $0.id == "saved-qingtian" })
        XCTAssertNil(inkQingtian.shopLatitude)
        let stamped = try XCTUnwrap(rows.first { $0.name == "青田七六咖啡" && $0.id != "saved-qingtian" })
        XCTAssertEqual(try XCTUnwrap(stamped.shopLatitude), 25.0272, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(stamped.shopLongitude), 121.5328, accuracy: 0.0001)
        XCTAssertEqual(rows.first { $0.name == "赤峰街麵店" }?.shopLatitude ?? 0, 25.0562, accuracy: 0.0001)
        XCTAssertLessThan(rows[0].distanceMeters ?? 0, rows[1].distanceMeters ?? 1)
    }

    func testWalkingMinutesRoundUpAndDetailCameraStaysLocal() {
        XCTAssertEqual(SaveInkPlaceCatalog.minutes(fromTravelTime: 20), 1)
        XCTAssertEqual(SaveInkPlaceCatalog.minutes(fromTravelTime: 90), 2)
        XCTAssertEqual(SaveInkPlaceCatalog.minutes(fromTravelTime: 0), 1)
        let shop = CLLocationCoordinate2D(latitude: 25.033, longitude: 121.543)
        let nearUser = CLLocationCoordinate2D(latitude: 25.053, longitude: 121.543)
        let farUser = CLLocationCoordinate2D(latitude: 25.40, longitude: 121.90)
        let near = SaveInkMapCamera.region(around: [], user: nearUser, focused: shop)
        let far = SaveInkMapCamera.region(around: [], user: farUser, focused: shop)
        XCTAssertLessThan(near?.span.latitudeDelta ?? 0, 0.05)
        XCTAssertLessThan(far?.span.latitudeDelta ?? 1, 0.05)
        XCTAssertGreaterThan(near?.span.latitudeDelta ?? 0, far?.span.latitudeDelta ?? 0)
        let wide = SaveInkMapCamera.region(
            around: [
                CLLocationCoordinate2D(latitude: -80, longitude: -170),
                CLLocationCoordinate2D(latitude: 80, longitude: 170),
            ],
            user: nil,
            focused: nil
        )
        XCTAssertLessThanOrEqual(wide?.span.latitudeDelta ?? 999, 180)
        XCTAssertLessThanOrEqual(wide?.span.longitudeDelta ?? 999, 360)
        let dateline = SaveInkMapCamera.region(
            around: [
                CLLocationCoordinate2D(latitude: -18, longitude: 179),
                CLLocationCoordinate2D(latitude: -18.2, longitude: -179),
            ],
            user: nil,
            focused: nil
        )
        XCTAssertLessThan(dateline?.span.longitudeDelta ?? 360, 20)
        XCTAssertGreaterThan(abs(dateline?.center.longitude ?? 0), 170)
    }

    func testSupabaseSyncKeepsLocalPlacesWhenTheServerFails() async {
        let local = Place.from(inkPending(name: "本地小店", address: "永康街", latitude: 25.03, longitude: 121.53))
        let remote = SaveInkRemoteFake()
        remote.fetchError = URLError(.notConnectedToInternet)
        let offline = await SaveInkPlaceSync.reconcile(local: [local], userId: "user-1", remote: remote)
        XCTAssertEqual(offline.map(\.id), [local.id])
        XCTAssertTrue(remote.saved.isEmpty)

        remote.fetchError = nil
        remote.configured = false
        let skipped = await SaveInkPlaceSync.reconcile(local: [local], userId: "user-1", remote: remote)
        XCTAssertEqual(skipped.map(\.id), [local.id])
        XCTAssertTrue(remote.saved.isEmpty)

        let signedOut = await SaveInkPlaceSync.reconcile(local: [local], userId: nil, remote: remote)
        XCTAssertEqual(signedOut.map(\.id), [local.id])
    }

    func testSupabaseSyncUploadsLocalOnlyPlacesAndKeepsRemoteOnes() async {
        let local = Place.from(inkPending(name: "只在手機", address: "永康街", latitude: 25.03, longitude: 121.53))
        let server = Place.from(inkPending(
            name: "另一台存的",
            address: "信義路",
            latitude: 25.04,
            longitude: 121.56,
            google: "google-server"
        ))
        let remote = SaveInkRemoteFake()
        remote.places = [server]
        let merged = await SaveInkPlaceSync.reconcile(local: [local], userId: "user-1", remote: remote)
        XCTAssertEqual(Set(merged.map(\.name)), Set(["只在手機", "另一台存的"]))
        XCTAssertEqual(remote.saved.map(\.id), [local.id])

        remote.saved = []
        remote.saveError = URLError(.networkConnectionLost)
        let kept = await SaveInkPlaceSync.reconcile(local: [local], userId: "user-1", remote: remote)
        XCTAssertTrue(kept.contains { $0.id == local.id })
        XCTAssertTrue(remote.saved.isEmpty)
    }

    func testLiveHomeReadsVaultPendingAndInkWithoutConsumingTheShareQueue() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = "did:privy:ink-live"
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let saved = Place.from(inkPending(
            name: "金庫小館",
            address: "台北市大安區永康街",
            latitude: 25.0331,
            longitude: 121.5298
        ))
        _ = try vault.saveConfirmedPlace(saved, ownerSubject: owner)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            inkPending(name: "分享麵店", address: "台北市中山區赤峰街", latitude: 25.056, longitude: 121.526, owner: owner),
            inkPending(name: "別人的店", address: "台北市信義區", latitude: 25.03, longitude: 121.57, owner: "someone-else"),
        ])
        let remote = SaveInkRemoteFake()
        remote.fetchError = URLError(.notConnectedToInternet)
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { owner },
            location: { CLLocation(latitude: 25.033, longitude: 121.530) },
            walkingMinutes: { _, _ in 11 },
            currentSession: { (owner, 1) },
            canConfirmAnother: { _ in true }
        )
        let loaded = await engine.load(ink: [
            inkRow(id: "saved-vault", name: "金庫小館", street: "永康街"),
            inkRow(id: "saved-plain", name: "沒座標小店", street: "新生南路"),
        ])
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: owner).map(\.name), ["分享麵店"])
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), [])
        let names = Set(loaded.places.map(\.name))
        XCTAssertEqual(names, Set(["金庫小館", "沒座標小店"]))
        XCTAssertFalse(names.contains("分享麵店"))
        XCTAssertFalse(names.contains("別人的店"))
        let vaultRow = try XCTUnwrap(loaded.places.first { $0.name == "金庫小館" && $0.shopLatitude != nil })
        XCTAssertEqual(vaultRow.shopLatitude ?? 0, 25.0331, accuracy: 0.0001)
        XCTAssertNotNil(vaultRow.distanceMeters)
        XCTAssertEqual(vaultRow.walkMinutes, 11)
        let unresolved = try XCTUnwrap(loaded.places.first { $0.id == "saved-plain" })
        XCTAssertNil(unresolved.shopLatitude)
        XCTAssertNil(unresolved.walkMinutes)
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: owner)
        XCTAssertFalse(stored.contains { $0.name == "分享麵店" })
        XCTAssertFalse(stored.contains { $0.name == "沒座標小店" })
        XCTAssertTrue(remote.saved.isEmpty)

        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.live.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: SaveInkLivePlaceLoader(
                localPlaces: { _ in [] },
                load: { _ in loaded }
            )
        )
        XCTAssertTrue(store.places.isEmpty)
        await store.refreshLivePlaces()
        XCTAssertEqual(Set(store.places.map(\.name)), names)
        XCTAssertEqual(store.userCoordinate?.latitude ?? 0, 25.033, accuracy: 0.0001)
    }

    func testShareQueueDoesNotConfirmPlacesPastTheFreeCap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = "did:privy:ink-cap"
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            inkPending(name: "排隊小店", address: "台北市大安區", latitude: 25.03, longitude: 121.53, owner: owner),
        ])
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: SaveInkRemoteFake(),
            userID: { owner },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (owner, 1) },
            canConfirmAnother: { _ in false }
        )
        let loaded = await engine.load(ink: [])
        XCTAssertTrue(loaded.places.isEmpty)
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: owner)
        XCTAssertFalse(stored.contains { $0.name == "排隊小店" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: owner).map(\.name), ["排隊小店"])
    }

    func testAccountChangeAbortsPlaceWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = "did:privy:ink-session"
        var generation = 1
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            inkPending(name: "換帳號小店", address: "台北市", latitude: 25.03, longitude: 121.53, owner: owner),
        ])
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: SaveInkRemoteFake(),
            userID: {
                generation = 2
                return owner
            },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (owner, generation) },
            canConfirmAnother: { _ in true }
        )
        let loaded = await engine.load(ink: [inkRow(id: "saved-keep", name: "原本的", street: "街")])
        XCTAssertEqual(loaded.places.map(\.name), ["原本的"])
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: owner)
        XCTAssertTrue(stored.isEmpty)
    }

    func testInkSavesStayWithTheAccountThatWroteThem() {
        let defaults = UserDefaults(suiteName: "save.ink.owner.\(UUID().uuidString)")!
        let places = """
        [
          {
            "id": "saved-a",
            "name": "甲店",
            "stampName": "甲店",
            "street": "甲街",
            "blurb": "甲",
            "sourceLabel": "來自 甲",
            "detailNote": "甲",
            "ownerSubject": "account-a"
          },
          {
            "id": "saved-b",
            "name": "乙店",
            "stampName": "乙店",
            "street": "乙街",
            "blurb": "乙",
            "sourceLabel": "來自 乙",
            "detailNote": "乙",
            "ownerSubject": "account-b"
          }
        ]
        """
        defaults.set(Data(places.utf8), forKey: SavePlaceLinkGate.placesKey)
        let accountA = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" }
        )
        XCTAssertEqual(accountA.places.map(\.name), ["甲店"])
        accountA.saveQuery = "丙店"
        accountA.commitSave()
        let accountB = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-b" }
        )
        XCTAssertEqual(accountB.places.map(\.name), ["乙店"])
        XCTAssertFalse(accountB.places.contains { $0.name == "丙店" })
    }

    func testVisitsStayWithTheAccountThatRecordedThem() async {
        let defaults = UserDefaults(suiteName: "save.ink.visits.owner.\(UUID().uuidString)")!
        let places = """
        [{
          "id": "saved-a",
          "name": "甲店",
          "stampName": "甲店",
          "street": "甲街",
          "blurb": "甲",
          "sourceLabel": "來自 甲",
          "detailNote": "甲",
          "ownerSubject": "account-a"
        }]
        """
        defaults.set(Data(places.utf8), forKey: SavePlaceLinkGate.placesKey)
        let accountA = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator(fix: .inRange(meters: 18)) },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" }
        )
        await accountA.checkIn(placeID: "saved-a")
        XCTAssertEqual(accountA.verifiedCount(for: "saved-a"), 1)
        let accountB = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-b" }
        )
        XCTAssertEqual(accountB.totalVisits(), 0)
        let reloaded = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" }
        )
        XCTAssertEqual(reloaded.verifiedCount(for: "saved-a"), 1)
    }

    func testSignedOutLiveVisitsIgnoreTheFixtureKey() throws {
        let defaults = UserDefaults(suiteName: "save.ink.signed-out.\(UUID().uuidString)")!
        let visit = SaveInkVisitRecord(
            id: UUID(),
            placeID: "dingtai",
            visitedAt: SaveInkClock.previewNow,
            verification: .verified,
            visibility: .public,
            comment: "fixture",
            sentiment: nil,
            anomaly: nil
        )
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1")
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { nil }
        )
        XCTAssertEqual(store.totalVisits(), 0)
    }

    func testCheckInDoesNotWriteVisitsAfterTheAccountChanges() async {
        let defaults = UserDefaults(suiteName: "save.ink.checkin.owner.\(UUID().uuidString)")!
        let places = """
        [{
          "id": "saved-a",
          "name": "甲店",
          "stampName": "甲店",
          "street": "甲街",
          "blurb": "甲",
          "sourceLabel": "來自 甲",
          "detailNote": "甲",
          "ownerSubject": "account-a"
        }]
        """
        defaults.set(Data(places.utf8), forKey: SavePlaceLinkGate.placesKey)
        var owner: String? = "account-a"
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: {
                SaveInkOwnerSwitchLocator { owner = "account-b" }
            },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { owner }
        )
        await store.checkIn(placeID: "saved-a")
        XCTAssertEqual(store.totalVisits(), 0)
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-a"))
    }

    func testRemoteStampsStayInTheCapCount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-remote-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = "did:privy:remote-cap"
        let remote = SaveInkRemoteFake()
        remote.places = [
            Place.from(inkPending(name: "遠端一", address: "甲路", latitude: 25.01, longitude: 121.51)),
            Place.from(inkPending(name: "遠端二", address: "乙路", latitude: 25.02, longitude: 121.52)),
        ]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            inkPending(name: "排隊一", address: "丙路", latitude: 25.03, longitude: 121.53, owner: owner),
            inkPending(name: "排隊二", address: "丁路", latitude: 25.04, longitude: 121.54, owner: owner),
        ])
        var counts: [Int] = []
        let engine = SaveInkLivePlaceEngine(
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            pending: queue,
            remote: remote,
            userID: { owner },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (owner, 1) },
            canConfirmAnother: { count in
                counts.append(count)
                return count < 3
            }
        )
        let loaded = await engine.load(ink: [])
        XCTAssertEqual(counts, [2, 3])
        XCTAssertTrue(loaded.places.contains { $0.name == "排隊一" })
        XCTAssertFalse(loaded.places.contains { $0.name == "排隊二" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: owner).map(\.name), ["排隊二"])
    }

    func testClaimedOwnerlessShareDoesNotImportForTheNextAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-claim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            inkPending(name: "無主小店", address: "戊路", latitude: 25.05, longitude: 121.55, owner: nil),
        ])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.configured = false
        let first = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { "account-a" },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { ("account-a", 1) },
            canConfirmAnother: { _ in true }
        )
        _ = await first.load(ink: [])
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        let second = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { "account-b" },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { ("account-b", 2) },
            canConfirmAnother: { _ in true }
        )
        let loaded = await second.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "無主小店" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-b")
        XCTAssertFalse(stored.contains { $0.name == "無主小店" })
    }

    private func inkPending(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        google: String? = nil,
        owner: String? = nil
    ) -> PendingSharedPlace {
        PendingSharedPlace(
            ownerSubject: owner,
            googlePlaceId: google,
            name: name,
            address: address,
            category: "food",
            latitude: latitude,
            longitude: longitude,
            dishes: [],
            savedAt: SaveInkClock.previewNow
        )
    }

    private func inkRow(id: String, name: String, street: String) -> SaveInkPlace {
        SaveInkPlace(
            id: id,
            name: name,
            stampName: name,
            street: street,
            distanceMeters: nil,
            blurb: "剛存的",
            sourceLabel: "來自 你貼上的店名",
            badge: .saved,
            detailNote: "剛存下來",
            friendUsualCount: 0,
            walkMinutes: nil,
            addressLine: nil,
            videoTitle: nil,
            videoSource: nil,
            shopLatitude: nil,
            shopLongitude: nil
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

private final class SaveInkOwnerSwitchLocator: SaveInkLocating {
    var onRequest: () -> Void

    init(onRequest: @escaping () -> Void) {
        self.onRequest = onRequest
    }

    func requestFix(for place: SaveInkPlace) async -> SaveInkFix {
        onRequest()
        return .inRange()
    }
}

private final class SaveInkRemoteFake: SaveInkPlaceRemote {
    var configured = true
    var isConfigured: Bool { configured }
    var places: [Place] = []
    var saved: [Place] = []
    var fetchError: Error?
    var saveError: Error?

    func fetchPlaces(for userId: String) async throws -> [Place] {
        if let fetchError { throw fetchError }
        return places
    }

    func savePlace(_ place: Place, userId: String) async throws {
        if let saveError { throw saveError }
        saved.append(place)
    }
}
