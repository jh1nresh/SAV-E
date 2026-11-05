import CoreLocation
import CryptoKit
import MapKit
import Network
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import SAVE

@MainActor
final class SaveInkNotebookTests: XCTestCase {
    func testSavedOnlyPassportPlaceDoesNotCreateAVisitOrStamp() {
        let place = inkRow(id: "saved-only", name: "Old saved place", street: "Real street")
        let store = livePlaceStore(places: [place])
        XCTAssertEqual(store.homePlaces().map(\.id), ["saved-only"])
        XCTAssertEqual(store.homeBadge(for: place), .saved)
        store.openPassport()
        store.openPlace(place.id)
        XCTAssertEqual(store.path, [.passport, .place("saved-only")])
        XCTAssertTrue(store.stampedPlaceIDs().isEmpty)
        XCTAssertEqual(store.totalVisits(), 0)
    }

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
        XCTAssertTrue(chrome.contains(".accessibilityLabel(languageSettings.localized(english: \"Back\", traditionalChinese: \"返回\"))"))
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

    func testNormalUnlocatedCopyDoesNotClaimFixtureCityOrVerifiedAction() throws {
        let defaults = inkSuite("unlocated-copy")
        let store = SaveInkNotebookStore(defaults: defaults)
        store.saveQuery = "沒有座標的小店"
        store.commitSave()
        let row = try XCTUnwrap(store.homePlaces().first)
        XCTAssertEqual(store.homeSummary(count: 0), "還沒有地點")
        XCTAssertEqual(store.homeSummary(count: 1), "挑了 1 個給你")
        XCTAssertEqual(store.detailNote(for: row), "剛存下來。可以記錄到訪（未驗證）。")
        let reloaded = SaveInkNotebookStore(defaults: defaults)
        XCTAssertEqual(reloaded.detailNote(for: try XCTUnwrap(reloaded.place(row.id))), store.detailNote(for: row))
        var custom = row
        custom.detailNote = "自己留下的店家筆記"
        XCTAssertEqual(store.detailNote(for: custom), custom.detailNote)
        var located = row
        located.shopLatitude = 25.03
        located.shopLongitude = 121.53
        XCTAssertEqual(store.detailNote(for: located), located.detailNote)
        let fixture = SaveInkNotebookStore(defaults: inkSuite("fixture-copy"), seedFixture: true)
        XCTAssertEqual(fixture.homeSummary(count: 3), "今天在大安區，挑了 3 個給你")
        XCTAssertEqual(fixture.detailNote(for: row), row.detailNote)
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
        let store = SaveInkNotebookStore(defaults: inkSuite("empty-home-copy"))
        XCTAssertEqual(store.homeSummary(count: store.homePlaces().count), "還沒有地點")
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

    func testShippingInkLanguageDoesNotReuseArchivedDesigns() throws {
        let screens = try source("SAV-E/Views/InkNotebook/SaveInkNotebookScreens.swift")
        XCTAssertFalse(screens.contains("LanguageSettingsSheet()"))
        let start = try XCTUnwrap(screens.range(of: "struct SaveInkLanguageSheet: View"))
        let end = try XCTUnwrap(screens.range(of: "struct SaveInkWelcomeScreen: View"))
        let sheet = String(screens[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(sheet.contains("SaveInkType."))
        XCTAssertTrue(sheet.contains("SaveInkPalette."))
        XCTAssertTrue(sheet.contains("SaveInkRoughRoundedRect"))
        for legacyStyle in ["SaveTheme.", "SaveAtlasPalette.", "SaveDottedBackground", "saveSuccess"] {
            XCTAssertFalse(sheet.contains(legacyStyle), "Current language UI must not borrow archived styles: \(legacyStyle)")
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

    /// MapKit and its SwiftUI tasks need an asynchronous layout window. The
    /// synchronous still helper is intentionally unchanged for the 14 baselines.
    private func hostedInkMapImage<Content: View>(_ root: Content, width: CGFloat) async throws -> UIImage {
        let size = CGSize(width: width, height: 852)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .light
        window.backgroundColor = UIColor(SaveInkPalette.paper)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.backgroundColor = window.backgroundColor
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(3))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
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
        XCTAssertTrue(SaveInkLaunch.usesLivePlaces(arguments: ["--savvy-ink-skip-welcome"]))
        XCTAssertFalse(SaveInkLaunch.usesLivePlaces(arguments: ["--savvy-ink-suite=ink-nav"]))
        XCTAssertTrue(SaveInkLaunch.usesLivePlaces(arguments: ["--uitest-complete-onboarding"]))
        XCTAssertTrue(SaveInkLaunch.usesLivePlaces(arguments: []))
    }

    func testLiveUnverifiedVisitKeepsAccountScopeAndDraftOwnership() throws {
        let defaults = inkSuite("live-unverified-owner")
        let row = inkRow(id: "saved-unlocated", name: "沒有座標的小店", street: "小店")
        let locator = SaveInkScriptedLocator(fix: .inRange())
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [row] },
            load: { _ in SaveInkLivePlaceLoad(places: [row], userCoordinate: nil) }
        )
        let store = SaveInkNotebookStore(
            defaults: defaults, now: { SaveInkClock.previewNow }, makeLocator: { locator },
            usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-a" }
        )
        store.recordUnverifiedVisit(placeID: row.id)
        XCTAssertEqual(locator.calls, 0)
        XCTAssertEqual(store.visitCount(for: row.id), 1)
        XCTAssertEqual(store.verifiedCount(for: row.id), 0)
        XCTAssertEqual(store.homeBadge(for: try XCTUnwrap(store.place(row.id))), .unverified)
        store.draftComment = "自己寫的"
        store.commitDraft()
        let reloaded = SaveInkNotebookStore(
            defaults: defaults, now: { SaveInkClock.previewNow }, usesLivePlaces: true,
            liveLoader: loader, liveOwner: { "account-a" }
        )
        XCTAssertEqual(reloaded.latestVisit(for: row.id)?.verification, .unverified)
        XCTAssertEqual(reloaded.latestVisit(for: row.id)?.comment, "自己寫的")
        XCTAssertEqual(reloaded.homeBadge(for: try XCTUnwrap(reloaded.place(row.id))), .unverified)
        let other = SaveInkNotebookStore(
            defaults: defaults, usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-b" }
        )
        XCTAssertEqual(other.totalVisits(), 0)
    }

    func testLiveUnverifiedVisitRefusesStaleCatalogAndCrossAccountDraft() throws {
        let defaults = inkSuite("live-unverified-switch")
        let row = inkRow(id: "saved-unlocated", name: "沒有座標的小店", street: "小店")
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [row] },
            load: { _ in SaveInkLivePlaceLoad(places: [row], userCoordinate: nil) }
        )
        var owner = "account-a"
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow },
                                         usesLivePlaces: true, liveLoader: loader, liveOwner: { owner })
        owner = "account-b"
        store.recordUnverifiedVisit(placeID: row.id)
        XCTAssertEqual(store.totalVisits(), 0)
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
        owner = "account-a"
        store.recordUnverifiedVisit(placeID: row.id)
        owner = "account-b"
        store.draftComment = "不能改寫另一個帳號"
        store.commitDraft()
        let original = SaveInkNotebookStore(
            defaults: defaults, now: { SaveInkClock.previewNow }, usesLivePlaces: true,
            liveLoader: loader, liveOwner: { "account-a" }
        )
        XCTAssertEqual(original.latestVisit(for: row.id)?.verification, .unverified)
        XCTAssertEqual(original.latestVisit(for: row.id)?.comment, "")
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
    }

    func testLiveCatalogScreensRenderForQA() throws {
        let unlocated = inkRow(id: "saved-long-name", name: "這是一間有很長店名而且沒有座標的小店", street: "店名待補地址")
        var located = inkRow(id: "saved-located", name: "已存的地點", street: "測試街")
        located.shopLatitude = 25.0327
        located.shopLongitude = 121.5294
        let rows = [unlocated, located, inkRow(id: "saved-third", name: "另一個已存地點", street: "測試街二段")]
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in rows },
            load: { _ in SaveInkLivePlaceLoad(places: rows, userCoordinate: nil) }
        )
        let store = SaveInkNotebookStore(defaults: inkSuite("live-catalog-render"), now: { SaveInkClock.previewNow },
                                         usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-a" })
        store.recordUnverifiedVisit(placeID: unlocated.id)
        store.commitDraft()
        let empty = SaveInkNotebookStore(defaults: inkSuite("live-empty-render"), now: { SaveInkClock.previewNow },
                                         usesLivePlaces: true, liveLoader: .inactive, liveOwner: { "account-a" })
        for width: CGFloat in [375, 390, 430] {
            for (name, image) in [
                ("home", try hostedInkImage(SaveInkHomeScreen(store: store), width: width)),
                ("empty", try hostedInkImage(SaveInkHomeScreen(store: empty), width: width)),
                ("place-unverified", try hostedInkImage(SaveInkPlaceScreen(store: store, placeID: unlocated.id), width: width)),
            ] {
                XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 8_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "ink-live-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testLiveMapKitScreensRenderForDesign() async throws {
        var saved = inkRow(id: "map-saved", name: "只存未去的測試店", street: "測試街")
        saved.shopLatitude = 25.0327
        saved.shopLongitude = 121.5294
        saved.distanceMeters = 200
        saved.walkMinutes = 4
        var visited = inkRow(id: "map-visited", name: "已到訪的測試店", street: "測試街二段")
        visited.shopLatitude = 25.0338
        visited.shopLongitude = 121.5320
        visited.badge = .visited
        visited.distanceMeters = 400
        visited.walkMinutes = 7
        let rows = [saved, visited]
        let defaults = inkSuite("live-mapkit-render")
        let visit = inkVisit(placeID: visited.id, comment: "測試用到訪紀錄")
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1.account-a")
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in rows },
            load: { _ in SaveInkLivePlaceLoad(
                places: rows,
                userCoordinate: CLLocationCoordinate2D(latitude: 25.0315, longitude: 121.5300)
            ) }
        )
        let store = SaveInkNotebookStore(
            defaults: defaults, now: { SaveInkClock.previewNow }, usesLivePlaces: true,
            liveLoader: loader, liveOwner: { "account-a" }
        )
        await store.refreshLivePlaces()
        XCTAssertFalse(store.includesSampleCatalog)
        XCTAssertEqual(store.verifiedCount(for: visited.id), 1)
        for width: CGFloat in [375, 390, 430] {
            for (name, image) in [
                ("home", try await hostedInkMapImage(SaveInkHomeScreen(store: store), width: width)),
                ("place-saved", try await hostedInkMapImage(SaveInkPlaceScreen(store: store, placeID: saved.id), width: width)),
                ("place-visited", try await hostedInkMapImage(SaveInkPlaceScreen(store: store, placeID: visited.id), width: width)),
            ] {
                XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 8_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "ink-mapkit-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
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
        let homeNear = SaveInkMapCamera.region(around: [shop], user: nearUser, focused: nil)
        let homeFar = SaveInkMapCamera.region(around: [shop], user: farUser, focused: nil)
        XCTAssertGreaterThan(homeNear?.span.latitudeDelta ?? 0, 0.01)
        XCTAssertLessThan(homeFar?.span.latitudeDelta ?? 1, 0.05)
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

    func testDestinationAdministrativeMetadataDisambiguatesAggregateCN() {
        func region(_ iso: String? = "CN", _ area: String?, _ city: String? = nil, _ district: String? = nil) -> String? {
            SaveInkMapPolicy.routingRegionCode(isoCountryCode: iso, administrativeArea: area,
                                              locality: city, subLocality: district)
        }
        // Observed public Apple en_US fixtures; all reported Asia/Shanghai, so
        // time zone cannot resolve the user's mainland-only provider boundary.
        XCTAssertEqual(region("CN", "Taiwan", "Taibei"), "TW")
        XCTAssertEqual(region("CN", nil, "Hong Kong SAR", "Central & Western District"), "HK")
        XCTAssertEqual(region("CN", nil, "Macau SAR", "St. Anthony Parish"), "MO")
        XCTAssertNil(region("CN", "Fujian", "Quanzhou", "Jinmen"))
        XCTAssertNil(region("CN", "Fujian", "Fuzhou", "Lianjiang"))
        XCTAssertEqual(region("CN", "Beijing", "Beijing"), "CN")
        for city in ["Beijing", "Shanghai", "Tianjin", "Chongqing"] {
            XCTAssertEqual(region("CN", nil, city, "Chaoyang"), "CN")
        }
        XCTAssertNil(region("CN", nil, "Beijing extra"))
        XCTAssertNil(region("CN", nil, "Fuzhou"))
        XCTAssertEqual(region("CN", "Shanghai", "Shanghai"), "CN")
        XCTAssertEqual(region("CN", "Fujian", "Xiamen", "Siming"), "CN")
        for area in ["Taiwan Province", "臺灣省", "台灣", "台湾省"] {
            XCTAssertEqual(region("CN", area), "TW")
        }
        XCTAssertEqual(region("CN", "Hong Kong"), "HK")
        XCTAssertEqual(region("CN", "Macao SAR China"), "MO")
        for area in [nil, "", "Unknown", "Not Taiwan", "Beijing extra"] {
            XCTAssertNil(region("CN", area))
        }
        XCTAssertNil(region("CN", nil, "Hong Kong SAR extra"))
        XCTAssertEqual(region("US", "Taiwan", "Hong Kong SAR"), "US", "Destination ISO outside CN is not rewritten by unrelated labels")
        XCTAssertEqual(region("TW", nil), "TW")
        XCTAssertNil(region(nil, "Beijing"))
    }

    func testWGS84OfficialRedirectAdapterIsTransientAndFailsClosed() throws {
        var place = inkRow(id: "wgs-adapter", name: "Original destination & name", street: "Beijing")
        place.shopLatitude = 39.9087
        place.shopLongitude = 116.3975
        let original = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        let response = "https://m.amap.com/share/index/lnglat=116.403742675782,39.910102539063&name=Provider%20name&src=savvy&callnative=0&innersrc=u"
        let embed = try XCTUnwrap(SaveInkMapPolicy.amapEmbedFromWGS84Redirect(try XCTUnwrap(URL(string: response)), original: original))
        XCTAssertTrue(SaveInkMapPolicy.isAmapEmbed(embed))
        let query = try XCTUnwrap(URLComponents(url: embed, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "lng" }?.value, "116.403742675782")
        XCTAssertEqual(query.first { $0.name == "lat" }?.value, "39.910102539063")
        XCTAssertEqual(query.first { $0.name == "name" }?.value, place.name)
        XCTAssertEqual(query.first { $0.name == "platform" }?.value, "pc")
        XCTAssertEqual(place.shopLatitude, 39.9087, "Provider conversion must not rewrite saved WGS84 coordinates")
        XCTAssertNil(place.mapReference)
        for bad in [
            response.replacingOccurrences(of: "https:", with: "http:"),
            response.replacingOccurrences(of: "m.amap.com", with: "m.amap.com.evil.example"),
            response.replacingOccurrences(of: "m.amap.com", with: "user:password@m.amap.com"),
            response.replacingOccurrences(of: "m.amap.com", with: "m.amap.com:8443"),
            response + "?unexpected=1", response + "#fragment",
            response.replacingOccurrences(of: "/share/index/", with: "/other/"),
            response.replacingOccurrences(of: "116.403742675782", with: "nan"),
            response.replacingOccurrences(of: "39.910102539063", with: "inf"),
            response.replacingOccurrences(of: "116.403742675782", with: "181"),
            response.replacingOccurrences(of: "116.403742675782", with: "121.5"),
            response + "&src=savvy", response + "&unknown=1",
            response.replacingOccurrences(of: "callnative=0", with: "callnative=1")
        ] {
            XCTAssertNil(SaveInkMapPolicy.amapEmbedFromWGS84Redirect(try XCTUnwrap(URL(string: bad)), original: original))
        }
        let gaode = try XCTUnwrap(URL(string: original.absoluteString.replacingOccurrences(of: "coordinate=wgs84", with: "coordinate=gaode")))
        XCTAssertNil(SaveInkMapPolicy.amapEmbedFromWGS84Redirect(try XCTUnwrap(URL(string: response)), original: gaode))
        let duplicate = try XCTUnwrap(URL(string: original.absoluteString + "&coordinate=wgs84"))
        XCTAssertNil(SaveInkMapPolicy.amapWGS84Reference(in: duplicate))
    }

    func testAmapWebKitPolicyAndPermissionDelegatesAreObjectiveCProtocolWitnesses() throws {
        let coordinator = SaveInkAmapWebView.Coordinator(failed: .constant(false),
            originalURL: try XCTUnwrap(URL(string: "https://www.amap.com/ssr/embed/place?lng=116.4&lat=39.9")))
        for selector in [
            "webView:decidePolicyForNavigationAction:decisionHandler:",
            "webView:decidePolicyForNavigationResponse:decisionHandler:",
            "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:",
            "webView:requestDeviceOrientationAndMotionPermissionForOrigin:initiatedByFrame:decisionHandler:",
            "webView:didReceiveServerRedirectForProvisionalNavigation:",
            "webView:didFinishNavigation:"
        ] {
            XCTAssertTrue(coordinator.responds(to: NSSelectorFromString(selector)), selector)
        }
        let observer = SaveInkHTTP200MapObserver { _, _ in }
        XCTAssertTrue(observer.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:")))
    }

    func testAmapCountryHardDeadlineFinishesWhenBackendNeverCallsBack() async throws {
        var completed = false
        var stopped = 0
        var callback: SaveInkMapCountryRequest.Completion?
        let request = SaveInkMapCountryRequest(timeout: .milliseconds(30), start: { _, _, completion in
            callback = completion
        }, stop: { stopped += 1 })
        let reference = SaveInkMapReference(latitude: 39.9, longitude: 116.4, coordinateSystem: .wgs84,
                                            provider: nil, providerPlaceID: nil)
        let work = Task { @MainActor in
            let result = await request.matches(reference: reference, address: "Public fixture")
            completed = true
            return result
        }
        defer { request.cancel(); work.cancel() }
        for _ in 0..<100 {
            if completed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(completed, "The hard deadline must resume without any backend callback")
        if !completed { request.cancel() }
        let result = await work.value
        XCTAssertNil(result)
        XCTAssertEqual(stopped, 1)
        let late = try XCTUnwrap(callback)
        late([MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4))])
        late(nil) // Neither callback may resume the continuation a second time.
        request.cancel()
        XCTAssertEqual(stopped, 1)
        let reused = await request.matches(reference: reference, address: "Public fixture")
        XCTAssertNil(reused, "A finished country request is single-use")
    }

    func testAmapCountryCancellationFinishesBeforeLateBackendCallback() async throws {
        var completed = false
        var stopped = 0
        var callback: SaveInkMapCountryRequest.Completion?
        let request = SaveInkMapCountryRequest(timeout: .seconds(30), start: { _, _, completion in
            callback = completion
        }, stop: { stopped += 1 })
        let reference = SaveInkMapReference(latitude: 39.9, longitude: 116.4, coordinateSystem: .wgs84,
                                            provider: nil, providerPlaceID: nil)
        let work = Task { @MainActor in
            let result = await request.matches(reference: reference, address: "Public fixture")
            completed = true
            return result
        }
        defer { request.cancel(); work.cancel() }
        for _ in 0..<100 {
            if callback != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let late = try XCTUnwrap(callback, "Observe a pending backend request before cancellation")
        work.cancel()
        for _ in 0..<100 {
            if completed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(completed, "Task cancellation must finish without waiting for the backend")
        if !completed { request.cancel() }
        let result = await work.value
        XCTAssertNil(result)
        late([MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4))])
        XCTAssertEqual(stopped, 1)
    }

    func testAmapCountrySuccessfulCallbackCancelsHardDeadline() async throws {
        var stopped = 0
        let match = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4))
        let request = SaveInkMapCountryRequest(timeout: .milliseconds(30), start: { _, _, completion in
            completion([match])
        }, stop: { stopped += 1 })
        defer { request.cancel() }
        let reference = SaveInkMapReference(latitude: 39.9, longitude: 116.4, coordinateSystem: .wgs84,
                                            provider: nil, providerPlaceID: nil)
        let result = await request.matches(reference: reference, address: "Public fixture")
        XCTAssertEqual(result?.count, 1)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(stopped, 0, "A completed request must not retain a deadline that cancels a later result")
    }

    func testAmapRedirectProvenanceRequiresOriginalHTTPNavigation() throws {
        let original = try XCTUnwrap(URL(string: "https://uri.amap.com/marker?position=116.3975,39.9087&coordinate=wgs84&callnative=0&name=Public&src=savvy"))
        let web = SaveInkAmapNavigationStub()
        let coordinator = SaveInkAmapWebView.Coordinator(failed: .constant(false), originalURL: original)
        defer { coordinator.invalidate() }
        coordinator.start(in: web)
        let initial = web.navigation
        coordinator.webView(web, didStartProvisionalNavigation: initial)
        XCTAssertFalse(coordinator.hasOriginalServerRedirect)
        let other = WKNavigation()
        coordinator.webView(web, didReceiveServerRedirectForProvisionalNavigation: other)
        XCTAssertFalse(coordinator.hasOriginalServerRedirect, "A different navigation cannot supply provider conversion provenance")
        coordinator.webView(web, didReceiveServerRedirectForProvisionalNavigation: initial)
        XCTAssertTrue(coordinator.hasOriginalServerRedirect)
        coordinator.webView(web, didStartProvisionalNavigation: other)
        XCTAssertFalse(coordinator.hasOriginalServerRedirect, "A script/form/new navigation must clear the original HTTP redirect proof")
        coordinator.webView(web, didReceiveServerRedirectForProvisionalNavigation: other)
        coordinator.webView(web, didReceiveServerRedirectForProvisionalNavigation: initial)
        XCTAssertFalse(coordinator.hasOriginalServerRedirect)
        coordinator.invalidate()
        coordinator.webView(web, didReceiveServerRedirectForProvisionalNavigation: initial)
        XCTAssertFalse(coordinator.hasOriginalServerRedirect)
    }

    func testAmapActualHTTP200ShellStillNeedsSemanticMap() async throws {
        let fixture = try SaveInkHTTP200MapFixture()
        defer { fixture.stop() }
        for _ in 0..<100 {
            if fixture.port != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let port = try XCTUnwrap(fixture.port, "Loopback HTTP fixture must become ready")
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/map-shell"))
        var failed = false
        let web = WKWebView()
        let coordinator = SaveInkAmapWebView.Coordinator(
            failed: Binding(get: { failed }, set: { failed = $0 }),
            originalURL: try XCTUnwrap(URL(string: "https://www.amap.com/ssr/embed/place?lng=116.4&lat=39.9")),
            timeout: .milliseconds(100))
        defer { coordinator.invalidate(); web.stopLoading(); web.navigationDelegate = nil }
        // Only this test delegate admits loopback. Production origin policy is
        // unchanged; the real HTTP 200 completion forwards into render monitoring.
        let observer = SaveInkHTTP200MapObserver(expectedURL: url) { web, navigation in
            coordinator.beginMonitoring(in: web)
            coordinator.webView(web, didFinish: navigation)
        }
        web.navigationDelegate = observer
        web.load(URLRequest(url: url))
        for _ in 0..<250 {
            if observer.finished && failed { break }
            if observer.error != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let body = (try? await web.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String
        let diagnostics = "successfulServer200Sends=\(fixture.responseSentCount) expected=\(url.absoluteString) bodySentinel=\(body?.contains(SaveInkHTTP200MapFixture.bodySentinel) == true)\n" + observer.trace.joined(separator: "\n")
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "ink-amap-http200-fixture-diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        try diagnostics.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("ink-amap-http200-fixture-diagnostics.txt"), atomically: true, encoding: .utf8)
        XCTAssertNil(observer.error)
        XCTAssertEqual(observer.statusCode, 200, diagnostics)
        XCTAssertTrue(body?.contains(SaveInkHTTP200MapFixture.bodySentinel) == true, "The intended loopback HTML must actually be loaded")
        XCTAssertTrue(observer.finished, "An actual HTTP 200 HTML document must finish before testing render semantics")
        XCTAssertTrue(failed, "HTTP 200 without map tiles must still hit the semantic render deadline")
        XCTAssertFalse(coordinator.hasRenderedMap)
    }

    func testAmapInFlightReadinessCannotPublishAfterTeardown() async throws {
        var failed = false
        var pending: CheckedContinuation<Bool, Never>?
        let web = WKWebView()
        let coordinator = SaveInkAmapWebView.Coordinator(
            failed: Binding(get: { failed }, set: { failed = $0 }),
            originalURL: try XCTUnwrap(URL(string: "https://www.amap.com/ssr/embed/place?lng=116.4&lat=39.9")),
            timeout: .seconds(2), readinessProbe: { _ in
                await withCheckedContinuation { pending = $0 }
            })
        defer { coordinator.invalidate(); pending?.resume(returning: false) }
        coordinator.beginMonitoring(in: web)
        coordinator.webView(web, didFinish: nil)
        for _ in 0..<100 {
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let callback = try XCTUnwrap(pending, "Observe readiness probe entry before teardown")
        pending = nil
        coordinator.invalidate()
        callback.resume(returning: true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(coordinator.hasRenderedMap, "A successful in-flight script result cannot revive a dismantled map")
        XCTAssertFalse(failed)
    }

    func testAmapEmptyHTMLShellHitsOverallRenderDeadline() async throws {
        var failed = false
        let web = WKWebView()
        web.loadHTMLString("<html><body>Successful document shell without map tiles</body></html>", baseURL: nil)
        defer { web.stopLoading() }
        let coordinator = SaveInkAmapWebView.Coordinator(
            failed: Binding(get: { failed }, set: { failed = $0 }),
            originalURL: try XCTUnwrap(URL(string: "https://www.amap.com/ssr/embed/place?lng=116.4&lat=39.9")),
            timeout: .milliseconds(100))
        defer { coordinator.invalidate() }
        coordinator.beginMonitoring(in: web)
        coordinator.webView(web, didFinish: nil)
        try await Task.sleep(for: .milliseconds(60))
        coordinator.webView(web, didFinish: nil) // HTTP/document completion cannot reset the deadline.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(failed, "A finished document without a semantic map must become unavailable")
    }

    func testAmapTeardownCancelsDeadlineAndIgnoresLateCallbacks() async throws {
        var failed = false
        let web = WKWebView()
        let coordinator = SaveInkAmapWebView.Coordinator(
            failed: Binding(get: { failed }, set: { failed = $0 }),
            originalURL: try XCTUnwrap(URL(string: "https://www.amap.com/ssr/embed/place?lng=116.4&lat=39.9")),
            timeout: .milliseconds(100))
        coordinator.beginMonitoring(in: web)
        coordinator.webView(web, didFinish: nil)
        coordinator.invalidate()
        coordinator.webView(web, didFinish: nil)
        coordinator.webViewWebContentProcessDidTerminate(web)
        coordinator.webView(web, didFailProvisionalNavigation: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(failed, "Removed/replaced maps must not publish old timeout, script or navigation failures")
    }

    func testAmapDestinationCountryLookupForOptionalNetworkCapture() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_AMAP_CAPTURE"] == "1" else {
            throw XCTSkip("Set SAVE_AMAP_CAPTURE=1 for the explicit live destination-country gate")
        }
        var hq = inkRow(id: "public-cn-country", name: "高德地图总部", street: "中国北京市朝阳区望京东园四区4号楼")
        hq.addressLine = hq.street
        hq.mapReference = SaveInkMapReference(latitude: 40.002539, longitude: 116.489729,
            coordinateSystem: .gcj02, provider: .amap, providerPlaceID: "B0K3C7EM0G")
        let mainland = await SaveInkMapPolicy.destinationCountryCode(for: hq)
        var taipei = inkRow(id: "public-tw-country", name: "Taipei public coordinate", street: "Taipei")
        taipei.shopLatitude = 25.033964
        taipei.shopLongitude = 121.564468
        let outside = await SaveInkMapPolicy.destinationCountryCode(for: taipei)
        let hqMetadata = await SaveInkMapPolicy.destinationPlacemark(for: hq)
        let taipeiMetadata = await SaveInkMapPolicy.destinationPlacemark(for: taipei)
        func metadata(_ match: CLPlacemark?) -> String {
            "iso=\(match?.isoCountryCode ?? "nil") admin=\(match?.administrativeArea ?? "nil") locality=\(match?.locality ?? "nil") sublocality=\(match?.subLocality ?? "nil") zone=\(match?.timeZone?.identifier ?? "nil")"
        }
        let diagnosticText = "Public HQ GCJ/address region=\(mainland ?? "unresolved") \(metadata(hqMetadata))\nPublic Taipei WGS84 region=\(outside ?? "unresolved") \(metadata(taipeiMetadata))"
        try diagnosticText.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("ink-map-live-country-results.txt"), atomically: true, encoding: .utf8)
        let result = XCTAttachment(string: diagnosticText)
        result.name = "ink-map-live-country-results"
        result.lifetime = .keepAlways
        add(result)
        XCTAssertEqual(mainland, "CN", "Do not infer mainland success when the live country lookup is unavailable")
        XCTAssertEqual(outside, "TW", "Taipei must route by the destination, not the viewer's region")
        if mainland == "CN" {
            guard case .amap = SaveInkMapPolicy.display(for: hq, countryCode: mainland) else {
                return XCTFail("Live mainland result must select Amap")
            }
        }
        if outside == "TW" { XCTAssertEqual(SaveInkMapPolicy.display(for: taipei, countryCode: outside), .apple) }
    }

    /// Explicit local verification only: normal CI stays deterministic and does
    /// not depend on an external map's network. The attachment is the actual
    /// WKWebView snapshot, not a drawn map fixture or a URL-success assertion.
    func testAmapOfficialEmbedRendersForOptionalNetworkCapture() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_AMAP_CAPTURE"] == "1" else {
            throw XCTSkip("Set SAVE_AMAP_CAPTURE=1 for the explicit live Amap capture gate")
        }
        var place = inkRow(id: "public-amap-hq", name: "高德地图总部", street: "Official documentation example")
        place.mapReference = SaveInkMapReference(latitude: 40.002539, longitude: 116.489729,
            coordinateSystem: .gcj02, provider: .amap, providerPlaceID: "B0K3C7EM0G")
        try await captureOfficialAmap(place, prefix: "ink-amap-gcj-poi")
    }

    func testAmapRawGCJEmbedRendersForOptionalNetworkCapture() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_AMAP_CAPTURE"] == "1" else {
            throw XCTSkip("Set SAVE_AMAP_CAPTURE=1 for the explicit live Amap capture gate")
        }
        var place = inkRow(id: "public-amap-raw-gcj", name: "Public GCJ02 map point", street: "Beijing")
        place.mapReference = SaveInkMapReference(latitude: 40.002539, longitude: 116.489729,
            coordinateSystem: .gcj02, provider: .amap, providerPlaceID: nil)
        let url = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        XCTAssertEqual(url.path, "/ssr/embed/place")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(query.first { $0.name == "id" })
        XCTAssertEqual(query.first { $0.name == "lng" }?.value, "116.489729")
        try await captureOfficialAmap(place, prefix: "ink-amap-raw-gcj")
    }

    func testAmapWGS84MarkerRendersForOptionalNetworkCapture() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_AMAP_CAPTURE"] == "1" else {
            throw XCTSkip("Set SAVE_AMAP_CAPTURE=1 for the explicit live Amap capture gate")
        }
        // Public approximate central-Beijing WGS84 point, not an asserted POI.
        var place = inkRow(id: "public-amap-wgs84", name: "Public WGS84 map point", street: "Beijing")
        place.shopLatitude = 39.9087
        place.shopLongitude = 116.3975
        let url = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        XCTAssertEqual(url.host, "uri.amap.com")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "coordinate" }?.value, "wgs84")
        XCTAssertNil(query.first { $0.name == "poiid" })
        try await captureOfficialAmap(place, prefix: "ink-amap-wgs84-marker")
    }

    private func captureOfficialAmap(_ place: SaveInkPlace, prefix: String) async throws {
        let url = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        var failed = false
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive }, "Real WebKit rendering needs a foreground UIWindowScene")
        let originalKeyWindow = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            Text("Public Amap render verification").font(.caption)
            SaveInkAmapWebView(url: url, failed: Binding(get: { failed }, set: { failed = $0 }))
                .frame(height: 190)
            Spacer()
        }.background(Color.white).preferredColorScheme(.light))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.overrideUserInterfaceStyle = .light
        host.view.backgroundColor = .white
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        let web = try XCTUnwrap(findAmapWebView(in: host.view))
        defer { web.stopLoading() }
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        var ready = false
        for _ in 0..<40 {
            try Task.checkCancellation()
            if failed { break }
            let result = try? await web.evaluateJavaScript(SaveInkAmapWebView.renderReadinessScript)
            if result as? Bool == true { ready = true; break }
            try await Task.sleep(for: .seconds(1))
        }
        let diagnostics = try? await web.evaluateJavaScript("""
            JSON.stringify((() => {
              const locationOnly = raw => { try { const u = new URL(raw); return /^https?:$/.test(u.protocol) ? u.host + u.pathname.slice(0,120) : u.protocol; } catch { return 'invalid'; } };
              return {location:locationOnly(location.href), title:document.title.slice(0,80),
                body:document.body.innerText.slice(0,240), visibility:document.visibilityState,
                viewport:[innerWidth,innerHeight,devicePixelRatio], readyState:document.readyState,
                canvases:[...document.querySelectorAll('canvas')].slice(0,8).map(x => [x.width,x.height,x.clientWidth,x.clientHeight]),
                images:[...document.images].slice(0,16).map(x => ({location:locationOnly(x.src), complete:x.complete,width:x.naturalWidth,height:x.naturalHeight})),
                frames:[...document.querySelectorAll('iframe')].slice(0,8).map(x => locationOnly(x.src)),
                resources:performance.getEntriesByType('resource').slice(-30).map(x => ({location:locationOnly(x.name), completed:x.responseEnd > 0}))};
            })())
            """)
        let blocked = (web.navigationDelegate as? SaveInkAmapWebView.Coordinator)?.blockedNavigationLocations ?? []
        let diagnosticText = "scene=\(scene.activationState.rawValue) app=\(UIApplication.shared.applicationState.rawValue) attached=\(web.window != nil) frame=\(web.frame) blocked=\(blocked)\n\(diagnostics as? String ?? "DOM unavailable")"
        let diagnosticAttachment = XCTAttachment(string: diagnosticText)
        diagnosticAttachment.name = "\(prefix)-public-dom-diagnostics"
        diagnosticAttachment.lifetime = .keepAlways
        add(diagnosticAttachment)
        try diagnosticText.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-diagnostics.txt"), atomically: true, encoding: .utf8)
        let hostImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let hostAttachment = XCTAttachment(image: hostImage)
        hostAttachment.name = "\(prefix)-foreground-native-window"
        hostAttachment.lifetime = .keepAlways
        add(hostAttachment)
        try XCTUnwrap(hostImage.pngData()).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-native-window.png"))
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            web.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? NSError(domain: "SavvyAmapSnapshot", code: 1)) }
            }
        }
        let data = try XCTUnwrap(snapshot.pngData())
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "\(prefix)-real-web-map"
        attachment.lifetime = .keepAlways
        add(attachment)
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-real-web-map.png"))
        XCTAssertTrue(SaveInkMapPolicy.isAmapEmbed(web.url), "Every route must end in the compact official embed, never the mobile POI card")
        XCTAssertFalse(failed, "The official map failed to navigate or load")
        XCTAssertTrue(ready, "Require a rendered canvas/tile plus a completed map tile/vector resource; inspect the real WebKit attachment")
        XCTAssertGreaterThan(data.count, 20_000, "A blank WebKit surface is not a visible map")
        let geolocation = try await web.callAsyncJavaScript("""
            return await Promise.race([
              new Promise(resolve => navigator.geolocation.getCurrentPosition(
                () => resolve('allowed'), () => resolve('blocked'))),
              new Promise(resolve => setTimeout(() => resolve('timeout'), 3000))
            ]);
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(geolocation as? String, "blocked", "The embedded destination map must not request the viewer's GPS")
    }

    private func findAmapWebView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews {
            if let web = findAmapWebView(in: child) { return web }
        }
        return nil
    }

    func testMapProviderFollowsDestinationCountryIncludingSeparateHKMOTWRegions() throws {
        var place = inkRow(id: "destination", name: "Destination", street: "Saved address")
        place.shopLatitude = 31.23
        place.shopLongitude = 121.47
        guard case .amap(let url) = SaveInkMapPolicy.display(for: place, countryCode: " cn ") else {
            return XCTFail("Mainland destination must use Amap")
        }
        XCTAssertEqual(url.host, "uri.amap.com")
        for code in ["HK", "MO", "TW", "KR", "US"] {
            XCTAssertEqual(SaveInkMapPolicy.display(for: place, countryCode: code), .apple)
        }
        for code in [nil, "", "CN-HK", "not-a-country", "ZZ"] {
            XCTAssertEqual(SaveInkMapPolicy.display(for: place, countryCode: code), .unavailable)
        }
    }

    func testProviderReferencePreservesGCJWithoutMakingItAnArrivalOrAppleCoordinate() throws {
        var original = Place.from(inkPending(name: "上海測試店", address: "上海市徐匯區永福路235號", latitude: 31.23, longitude: 121.47))
        original.coordinateSystem = .gcj02
        original.locationProvider = .amap
        original.providerPlaceId = "B000TEST"
        let row = SaveInkPlaceCatalog.row(place: original, ink: nil)
        XCTAssertNil(row.shopLatitude)
        XCTAssertNil(row.shopLongitude)
        XCTAssertEqual(row.mapReference?.coordinateSystem, .gcj02)
        XCTAssertEqual(row.mapReference?.latitude, original.latitude)
        XCTAssertFalse(SaveInkAppleMaps.canOpen(row))
        XCTAssertEqual(SaveInkMapPolicy.display(for: row, countryCode: "HK"), .unavailable)
        let url = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: row))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "www.amap.com")
        XCTAssertEqual(query.first { $0.name == "id" }?.value, "B000TEST")
        XCTAssertNil(query.first { $0.name == "lng" }, "Amap resolves its POI id instead of reinterpreting coordinates")
        let store = livePlaceStore(places: [row])
        store.openPlace(row.id)
        XCTAssertEqual(store.totalVisits(), 0)
    }

    func testAmapURLsKeepCoordinateSystemsAndOnlyDestinationFields() throws {
        var place = inkRow(id: "url", name: "Cafe & tea? name=other", street: "Shanghai")
        place.shopLatitude = 31.23
        place.shopLongitude = 121.47
        place.detailNote = "PRIVATE NOTE MUST NOT LEAVE"
        let wgs = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        let wgsQuery = try XCTUnwrap(URLComponents(url: wgs, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(wgs.host, "uri.amap.com")
        XCTAssertEqual(wgsQuery.first { $0.name == "coordinate" }?.value, "wgs84")
        XCTAssertEqual(wgsQuery.first { $0.name == "name" }?.value, place.name)
        XCTAssertEqual(wgsQuery.first { $0.name == "callnative" }?.value, "0")
        XCTAssertFalse(wgs.absoluteString.contains("PRIVATE"))

        place.mapReference = SaveInkMapReference(latitude: 31.231, longitude: 121.471,
            coordinateSystem: .gcj02, provider: .amap, providerPlaceID: nil)
        let gcj = try XCTUnwrap(SaveInkMapPolicy.amapEmbedURL(for: place))
        let gcjQuery = try XCTUnwrap(URLComponents(url: gcj, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(gcj.path, "/ssr/embed/place")
        XCTAssertEqual(gcjQuery.first { $0.name == "lng" }?.value, "121.471")
        XCTAssertEqual(gcjQuery.first { $0.name == "platform" }?.value, "pc")
        XCTAssertNil(gcjQuery.first { $0.name == "coordinate" }, "Embed coordinates are already GCJ-02")
        place.mapReference?.coordinateSystem = .bd09
        XCTAssertNil(SaveInkMapPolicy.amapEmbedURL(for: place))
        place.mapReference?.coordinateSystem = .gcj02
        place.mapReference?.provider = .appleMaps
        XCTAssertNil(SaveInkMapPolicy.amapEmbedURL(for: place))
        place.mapReference?.latitude = .nan
        XCTAssertNil(SaveInkMapPolicy.amapMarkerURL(for: place, opensApp: true))
    }

    func testMapTargetsFeaturedDestinationAndRejectsUnsafeWebNavigation() {
        let first = inkRow(id: "first", name: "First", street: "A")
        let second = inkRow(id: "second", name: "Second", street: "B")
        XCTAssertEqual(SaveInkMapPolicy.target(in: [first, second], focusedID: nil)?.id, "first")
        XCTAssertEqual(SaveInkMapPolicy.target(in: [first, second], focusedID: "second")?.id, "second")
        XCTAssertNil(SaveInkMapPolicy.target(in: [first, second], focusedID: "gone"))
        XCTAssertNil(SaveInkMapPolicy.target(in: [], focusedID: nil))
        for raw in ["https://www.amap.com/ssr/embed/place?id=B1", "https://m.amap.com/", "https://uri.amap.com/marker"] {
            XCTAssertTrue(SaveInkMapPolicy.permitsWebNavigation(URL(string: raw), userInitiated: false))
            XCTAssertFalse(SaveInkMapPolicy.permitsWebNavigation(URL(string: raw), userInitiated: true))
        }
        for raw in ["http://www.amap.com/", "https://www.amap.com.attacker.example/", "https://user:secret@www.amap.com/",
                    "https://www.amap.com:444/", "javascript:alert(1)", "file:///private/file", "https://example.com/"] {
            XCTAssertFalse(SaveInkMapPolicy.permitsWebNavigation(URL(string: raw), userInitiated: false))
        }
    }

    func testCountryAddressMatchMustStayNearItsTypedProviderReference() {
        let reference = SaveInkMapReference(latitude: 31.23, longitude: 121.47,
            coordinateSystem: .gcj02, provider: .amap, providerPlaceID: nil)
        XCTAssertTrue(SaveInkMapPolicy.countryMatchIsNearby(reference, latitude: 31.232, longitude: 121.475))
        XCTAssertFalse(SaveInkMapPolicy.countryMatchIsNearby(reference, latitude: 25.03, longitude: 121.53))
        XCTAssertFalse(SaveInkMapPolicy.countryMatchIsNearby(reference, latitude: .nan, longitude: 121.47))
    }

    func testLateCountryLookupCannotReplaceNewDestinationAndMissingInputClearsIt() async {
        let state = SaveInkMapDestinationState()
        let pending = SaveInkSuspendedCountryLookup()
        var place = inkRow(id: "old", name: "Old", street: "Shanghai")
        place.shopLatitude = 31.23
        place.shopLongitude = 121.47
        let oldPlace = place
        let oldTask = Task { await state.refresh(place: oldPlace) { _ in await pending.load() } }
        await pending.waitUntilStarted()
        place.id = "new"
        await state.refresh(place: place) { _ in "TW" }
        pending.finish("CN")
        await oldTask.value
        XCTAssertEqual(state.display, .apple)
        XCTAssertEqual(state.targetToken, SaveInkMapPolicy.token(for: place))
        await state.refresh(place: nil) { _ in XCTFail("No target must not geocode"); return "CN" }
        XCTAssertEqual(state.display, .unavailable)
    }

    func testCancelledCountryLookupCannotPublishALateProvider() async {
        let state = SaveInkMapDestinationState()
        let pending = SaveInkSuspendedCountryLookup()
        var place = inkRow(id: "cancel", name: "Cancel", street: "Shanghai")
        place.shopLatitude = 31.23
        place.shopLongitude = 121.47
        let target = place
        let task = Task { await state.refresh(place: target) { _ in await pending.load() } }
        await pending.waitUntilStarted()
        task.cancel()
        pending.finish("CN")
        await task.value
        XCTAssertEqual(state.display, .loading)
    }

    func testLateWalkingRouteCannotReplaceANewerRoute() async {
        let state = SaveInkMapRouteState()
        let pending = SaveInkSuspendedRouteLookup()
        let oldTask = Task { await state.refresh { await pending.load() } }
        await pending.waitUntilStarted()

        let current = inkRoute(seconds: 120, meters: 100)
        await state.refresh { current }
        pending.finish(inkRoute(seconds: 900, meters: 800))
        await oldTask.value

        XCTAssertEqual(state.route?.seconds, 120)
        XCTAssertEqual(state.route?.meters, 100)
        XCTAssertEqual(state.route?.points.last?.latitude, current.points.last?.latitude)
    }

    func testRemovingWalkingRouteInputsClearsAndInvalidatesPendingResult() async {
        let state = SaveInkMapRouteState()
        await state.refresh { inkRoute(seconds: 120, meters: 100) }
        XCTAssertNotNil(state.route)

        let pending = SaveInkSuspendedRouteLookup()
        let oldTask = Task { await state.refresh { await pending.load() } }
        await pending.waitUntilStarted()
        XCTAssertNil(state.route, "A new request must clear the old label and polyline immediately")

        // The view returns nil when the user coordinate or focused shop disappears.
        await state.refresh { nil }
        pending.finish(inkRoute(seconds: 900, meters: 800))
        await oldTask.value
        XCTAssertNil(state.route)
    }

    func testCancelledWalkingRouteCannotPublishALateResult() async {
        let state = SaveInkMapRouteState()
        let pending = SaveInkSuspendedRouteLookup()
        let task = Task { await state.refresh { await pending.load() } }
        await pending.waitUntilStarted()
        task.cancel()
        pending.finish(inkRoute(seconds: 900, meters: 800))
        await task.value
        XCTAssertNil(state.route)
    }

    private func inkRoute(seconds: TimeInterval, meters: CLLocationDistance) -> SaveInkMapRoute {
        SaveInkMapRoute(
            points: [
                CLLocationCoordinate2D(latitude: 25.03, longitude: 121.53),
                CLLocationCoordinate2D(latitude: 25.03 + seconds / 1_000_000, longitude: 121.53 + meters / 1_000_000),
            ],
            seconds: seconds,
            meters: meters
        )
    }

    func testLiveMapStaysOffTheFixtureNotebook() throws {
        let chrome = try source("SAV-E/Views/InkNotebook/SaveInkNotebookChrome.swift")
        let screens = try source("SAV-E/Views/InkNotebook/SaveInkNotebookScreens.swift")
        XCTAssertTrue(chrome.contains("struct SaveInkWalkMap"))
        XCTAssertTrue(chrome.contains("struct SaveInkLiveMap"))
        XCTAssertTrue(chrome.contains("emphasis: .muted"))
        XCTAssertTrue(chrome.contains("pointsOfInterest: .excludingAll"))
        XCTAssertTrue(chrome.contains("UserAnnotation()"))
        XCTAssertTrue(chrome.contains("SaveInkMapPin()"))
        XCTAssertTrue(chrome.contains("SaveInkMapPin(visited: pin.visited)"))
        XCTAssertTrue(chrome.contains("head.fill(SaveInkPalette.ink)"))
        XCTAssertTrue(chrome.contains("PaperTexture"))
        XCTAssertTrue(chrome.contains("openInMaps"))
        XCTAssertFalse(chrome.contains("ink.home.map"))
        XCTAssertTrue(chrome.contains("ink.place.map"))
        XCTAssertTrue(screens.contains("showsLiveMap"))
        let homeEnd = try XCTUnwrap(screens.range(of: "struct SaveInkSaveSheet"))
        XCTAssertFalse(screens[..<homeEnd.lowerBound].contains("SaveInkLiveMap("), "Home is the list, not a map")
        XCTAssertTrue(screens.contains("SaveInkWalkMap(label:"))
        XCTAssertTrue(chrome.contains("ink.place.openMaps"))
        XCTAssertTrue(chrome.contains("用 Apple 地圖打開"))
        let plist = try source("SAV-E/Info.plist")
        XCTAssertTrue(plist.contains("NSLocationWhenInUseUsageDescription"))
        XCTAssertFalse(plist.contains("NSLocationAlwaysAndWhenInUseUsageDescription"))
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

    func testLiveCheckInShowsVisitedInsteadOfWantToGo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-badge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: "save.ink.badge.\(UUID().uuidString)")!
        let owner = "account-a"
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let saved = Place.from(inkPending(name: "甲店", address: "甲街", latitude: 25.03, longitude: 121.53, owner: owner))
        _ = try vault.saveConfirmedPlace(saved, ownerSubject: owner)
        let remote = SaveInkRemoteFake()
        remote.places = [saved] // This fixture represents a place that still exists remotely.
        let loader = liveLoader(owner: owner, directory: directory, vault: vault, queue: [], remote: remote)
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator(fix: .inRange(meters: 64)) },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { owner }
        )
        let placeID = try XCTUnwrap(store.places.first { $0.name == "甲店" }?.id)
        XCTAssertEqual(store.places.first { $0.id == placeID }?.badge, .saved)
        await store.checkIn(placeID: placeID)
        XCTAssertEqual(store.places.first { $0.id == placeID }?.badge, .visited)
        let image = try hostedInkImage(SaveInkArrivalScreen(store: store, placeID: placeID), width: 375)
        let attachment = XCTAttachment(image: image)
        attachment.name = "ink-verified-arrival-measured64-375"
        attachment.lifetime = .keepAlways
        add(attachment)
        await store.refreshLivePlaces()
        XCTAssertEqual(store.places.first { $0.id == placeID }?.badge, .visited)
        let reloaded = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { owner }
        )
        XCTAssertEqual(reloaded.places.first { $0.id == placeID }?.badge, .visited)
    }

    func testOwnerlessQueueIDsDifferByAccount() async throws {
        let item = inkPending(name: "無主小店", address: "戊路", latitude: 25.05, longitude: 121.55, owner: nil)
        let key = item.deduplicationKey
        let first = try await uploadedOwnerlessID(owner: "account-a", item: item)
        let second = try await uploadedOwnerlessID(owner: "account-b", item: item)
        XCTAssertEqual(first, SaveInkPlaceCatalog.stablePlaceID(for: "account-a|\(key)"))
        XCTAssertEqual(second, SaveInkPlaceCatalog.stablePlaceID(for: "account-b|\(key)"))
        XCTAssertNotEqual(first, second)
    }

    func testFailedUploadStaysQueuedForTheSameAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "還沒傳上去", address: "己路", latitude: 25.06, longitude: 121.56, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.saveError = URLError(.networkConnectionLost)
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["還沒傳上去"])
        let kept = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        let keptID = try XCTUnwrap(kept.first { $0.name == "還沒傳上去" }?.id)
        remote.saveError = nil
        _ = await engine.load(ink: [])
        XCTAssertEqual(remote.saved.map(\.id), [keptID])
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
        let other = liveEngine(
            owner: "account-b",
            vault: vault,
            queue: queue,
            remote: SaveInkRemoteFake()
        )
        let loaded = await other.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "還沒傳上去" })
    }

    func testMatchingShareKeepsTheStampWhenTheUploadHitsTheCap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-match-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "已存小店", address: "庚路", latitude: 25.07, longitude: 121.57, owner: nil)
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        _ = try vault.saveConfirmedPlace(Place.from(item), ownerSubject: "account-a")
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let remote = SaveInkRemoteFake()
        remote.saveError = SavePlaceLimitError.parkedInUnplacedInbox
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        let kept = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertTrue(kept.contains { $0.name == "已存小店" })
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["已存小店"])
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: SaveInkRemoteFake())
        let loaded = await other.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "已存小店" })
    }

    func testCapRejectionBindsTheOwnerlessQueueAndDropsTheNewStamp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-new-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "超額小店", address: "辛路", latitude: 25.08, longitude: 121.58, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.saveError = SavePlaceLimitError.parkedInUnplacedInbox
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "超額小店" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "超額小店" })
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["超額小店"])
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: SaveInkRemoteFake())
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "超額小店" })
    }

    func testLaterCapRejectionRemovesTheUnsentQueueStamp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-retry-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "稍後超額", address: "壬路", latitude: 25.09, longitude: 121.59, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.saveError = URLError(.networkConnectionLost)
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        let kept = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertTrue(kept.contains { $0.name == "稍後超額" })
        remote.saveError = SavePlaceLimitError.parkedInUnplacedInbox
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "稍後超額" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "稍後超額" })
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["稍後超額"])
    }

    func testLocalCapBindsAnOwnerlessShare() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-local-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "名額滿了", address: "癸路", latitude: 25.10, longitude: 121.60, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.configured = false
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { "account-a" },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { ("account-a", 1) },
            canConfirmAnother: { _ in false }
        )
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "名額滿了" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "名額滿了" })
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["名額滿了"])
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: SaveInkRemoteFake())
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "名額滿了" })
    }

    func testLocalCapHoldsAnOwnerlessRowWhenTheQueueCannotBeRewritten() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-local-cap-unwritable-\(UUID().uuidString)")
        let queueDirectory = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let item = inkPending(name: "名額寫不進", address: "卯路", latitude: 25.27, longitude: 121.77, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: queueDirectory)
        queue.restorePendingPlaces([item])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let remote = SaveInkRemoteFake()
        remote.configured = false
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { "account-a" },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { ("account-a", 1) },
            canConfirmAnother: { _ in false }
        )
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "名額寫不進" })
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "名額寫不進" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
    }

    func testFailedFetchDoesNotRestoreVaultAfterTheAccountChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-fetch-abort-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let saved = Place.from(inkPending(name: "刪除前的店", address: "子路", latitude: 25.11, longitude: 121.61, owner: "account-a"))
        _ = try vault.saveConfirmedPlace(saved, ownerSubject: "account-a")
        var sessionOwner: String? = "account-a"
        var generation = 1
        let remote = SaveInkRemoteFake()
        remote.fetchError = URLError(.cancelled)
        remote.beforeFetch = {
            try? vault.removeConfirmedPlace(saved, belongingTo: "account-a")
            sessionOwner = nil
            generation = 2
        }
        let engine = SaveInkLivePlaceEngine(
            vault: vault,
            pending: PendingPlaceImportService(overrideContainerURL: directory),
            remote: remote,
            userID: { sessionOwner },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (sessionOwner, generation) },
            canConfirmAnother: { _ in true }
        )
        _ = await engine.load(ink: [])
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "刪除前的店" })
    }

    func testSignedOutLoadLeavesTheShareQueueUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-signed-out-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "登入前的分享", address: "寅路", latitude: 25.12, longitude: 121.62, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let signedOut = SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: SaveInkRemoteFake(),
            userID: { nil },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (nil, 1) },
            canConfirmAnother: { _ in true }
        )
        let hidden = await signedOut.load(ink: [])
        XCTAssertFalse(hidden.places.contains { $0.name == "登入前的分享" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["登入前的分享"])
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: nil)
        XCTAssertFalse(stored.contains { $0.name == "登入前的分享" })
        let signedIn = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: SaveInkRemoteFake())
        let loaded = await signedIn.load(ink: [])
        XCTAssertTrue(loaded.places.contains { $0.name == "登入前的分享" })
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
    }

    func testFetchedStampUpdatesTheMatchingVaultRow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-mirror-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var local = Place.from(inkPending(name: "同步店", address: "卯路", latitude: 25.13, longitude: 121.63))
        local.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try vault.saveConfirmedPlace(local, ownerSubject: "account-a")
        var server = Place.from(inkPending(
            name: "同步店",
            address: "卯路",
            latitude: 25.13,
            longitude: 121.63,
            google: "google-sync"
        ))
        server.createdAt = Date(timeIntervalSince1970: 1_600_000_000)
        server.note = "伺服器備註"
        let remote = SaveInkRemoteFake()
        remote.places = [server]
        let engine = liveEngine(
            owner: "account-a",
            vault: vault,
            queue: PendingPlaceImportService(overrideContainerURL: directory),
            remote: remote
        )
        _ = await engine.load(ink: [])
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        let row = try XCTUnwrap(stored.first { $0.name == "同步店" })
        XCTAssertEqual(row.googlePlaceId, "google-sync")
        XCTAssertTrue(row.savedIDs.contains(local.id))
        remote.fetchError = URLError(.notConnectedToInternet)
        remote.places = []
        _ = await engine.load(ink: [])
        let offline = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertEqual(offline.first { $0.name == "同步店" }?.googlePlaceId, "google-sync")
    }

    func testFetchedStampPersistsAddressCategoryAndProvider() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-mirror-fields-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var local = Place.from(inkPending(name: "欄位店", address: "舊路", latitude: 25.14, longitude: 121.64))
        local.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        local.category = .food
        _ = try vault.saveConfirmedPlace(local, ownerSubject: "account-a")
        var server = local
        server.createdAt = Date(timeIntervalSince1970: 1_600_000_000)
        server.address = "新路"
        server.category = .cafe
        server.latitude = 25.1404
        server.locationProvider = .appleMaps
        server.providerPlaceId = "poi-1"
        server.recommendedItems = [RecommendedItem(name: "奶油麵包", price: nil)]
        let remote = SaveInkRemoteFake()
        remote.places = [server]
        let engine = liveEngine(
            owner: "account-a",
            vault: vault,
            queue: PendingPlaceImportService(overrideContainerURL: directory),
            remote: remote
        )
        _ = await engine.load(ink: [])
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        let row = try XCTUnwrap(stored.first { $0.name == "欄位店" })
        XCTAssertEqual(row.address, "新路")
        XCTAssertEqual(row.category, .cafe)
        XCTAssertEqual(row.latitude, 25.1404, accuracy: 0.00001)
        XCTAssertEqual(row.locationProvider, .appleMaps)
        XCTAssertEqual(row.providerPlaceId, "poi-1")
        XCTAssertEqual(row.savedRecommendedItems.map(\.name), ["奶油麵包"])
    }

    func testLiveHomeArrivalIgnoresAnUnlocatedList() {
        var alpha = inkRow(id: "alpha", name: "甲店", street: "甲")
        var beta = inkRow(id: "beta", name: "乙店", street: "乙")
        alpha.distanceMeters = nil
        beta.distanceMeters = nil
        let unlocated = livePlaceStore(places: [alpha, beta])
        XCTAssertNil(unlocated.liveArrivalPlaceID())
        var near = inkRow(id: "near", name: "近店", street: "近")
        var far = inkRow(id: "far", name: "遠店", street: "遠")
        near.distanceMeters = 40
        far.distanceMeters = 900
        let located = livePlaceStore(places: [near, far])
        XCTAssertEqual(located.liveArrivalPlaceID(), "near")
    }

    func testLiveSaveStopsAtThePlaceCap() async {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.cap-save.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            canSaveAnotherLivePlace: { _ in false },
            liveSavedPlaceTierIsAuthoritative: { true },
            parkCappedLiveSave: { _ in true }
        )
        await store.refreshLivePlaces()
        store.saveQuery = "超額新店"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "超額新店" })
        XCTAssertEqual(store.saveNotice, "已存 50 個地點，所以暫放，還沒放上地圖。")
    }

    func testCappedSaveStaysOpenWhenParkingFails() async {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.park-fail.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            canSaveAnotherLivePlace: { _ in false },
            liveSavedPlaceTierIsAuthoritative: { true },
            parkCappedLiveSave: { _ in false }
        )
        await store.refreshLivePlaces()
        store.saveQuery = "沒停好"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "沒停好" })
        XCTAssertEqual(store.saveNotice, "已存 50 個地點，這次沒有存下來。請稍後再試。")
        XCTAssertEqual(store.saveQuery, "沒停好")
    }

    func testOfflineLoadKeepsMoreThanFiveHundredStamps() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-many-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        for index in 0..<501 {
            let place = Place.from(inkPending(
                name: "店\(index)",
                address: "路\(index)",
                latitude: 1 + Double(index) * 0.02,
                longitude: 1
            ))
            _ = try vault.saveConfirmedPlace(place, ownerSubject: "account-a")
        }
        let remote = SaveInkRemoteFake()
        remote.fetchError = URLError(.notConnectedToInternet)
        let engine = liveEngine(
            owner: "account-a",
            vault: vault,
            queue: PendingPlaceImportService(overrideContainerURL: directory),
            remote: remote
        )
        let loaded = await engine.load(ink: [])
        XCTAssertEqual(loaded.places.count, 501)
    }

    func testLiveSaveWaitsForTheAuthoritativePlaceCount() async {
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [] },
            load: { ink in
                SaveInkLivePlaceLoad(places: ink, userCoordinate: nil, countIsAuthoritative: false)
            }
        )
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.wait-count.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { "account-a" },
            canSaveAnotherLivePlace: { _ in true }
        )
        store.saveQuery = "還沒核對"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "還沒核對" })
        XCTAssertEqual(store.saveNotice, "還在核對已存的地點，請稍後再存。")
        await store.refreshLivePlaces()
        store.saveNotice = nil
        store.saveQuery = "還沒核對"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "還沒核對" })
    }

    func testLiveHomeDoesNotShowFixtureFriends() {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.no-friends.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { nil }
        )
        XCTAssertTrue(store.friendCards().isEmpty)
        let fixture = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.fixture-friends.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        XCTAssertFalse(fixture.friendCards().isEmpty)
    }

    func testLivePasteReadsTheClipboardAndDoesNotSelectTheFixturePlace() async {
        let defaults = UserDefaults(suiteName: "save.ink.paste.\(UUID().uuidString)")!
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            liveSavedPlaceTierIsAuthoritative: { true }
        )
        await store.refreshLivePlaces()
        store.sheet = .save
        store.paste(liveText: "   ")
        XCTAssertTrue(store.saveLink.isEmpty)
        XCTAssertNil(store.recognizedPlaceID)
        store.paste(liveText: "https://notes.example/article/how-to-film")
        XCTAssertEqual(store.saveLink, "https://notes.example/article/how-to-film")
        XCTAssertNil(store.recognizedPlaceID)
        store.commitSave()
        XCTAssertEqual(store.saveNotice, SaveInkPlaceLink.notAPlaceMessage)
        XCTAssertEqual(store.sheet, .save)
        XCTAssertFalse(store.places.contains { $0.id == SaveInkFixture.qingtian })
        let fixture = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.paste-fixture.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        fixture.pasteExampleLink()
        XCTAssertEqual(fixture.recognizedPlaceID, SaveInkFixture.qingtian)
    }

    func testLivePasteKeepsAMapLinkOpenUntilItHasAName() async {
        let defaults = UserDefaults(suiteName: "save.ink.map-paste.\(UUID().uuidString)")!
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            liveSavedPlaceTierIsAuthoritative: { true }
        )
        await store.refreshLivePlaces()
        store.sheet = .save
        store.paste(liveText: "https://maps.apple.com/?ll=25.03,121.52")
        store.commitSave()
        XCTAssertEqual(store.saveNotice, "這則地圖連結還沒有店名。在下面寫下店名再存。")
        XCTAssertEqual(store.sheet, .save)
        XCTAssertFalse(store.places.contains { $0.name.contains("maps.apple") })
        store.saveNotice = nil
        store.paste(liveText: "https://maps.apple.com/?q=青田麵店")
        store.commitSave()
        XCTAssertTrue(store.places.contains { $0.name == "青田麵店" })
        XCTAssertEqual(
            SaveInkPlaceLink.mapPlaceName(in: "Check out Grand Central Market https://maps.apple.com/place?address=317%20S%20Broadway,%20Los%20Angeles,%20CA%2090013&coordinate=34.050536,-118.248981&name=Grand%20Central%20Market"),
            "Grand Central Market"
        )
        XCTAssertNil(store.sheet)
        let saved = try? String(decoding: XCTUnwrap(defaults.data(forKey: SavePlaceLinkGate.placesKey)), as: UTF8.self)
        XCTAssertTrue(saved?.contains("青田麵店") == true)
    }

    func testLiveSaveWaitsUntilTheSavedPlaceTierIsKnown() async {
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.wait-tier.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            canSaveAnotherLivePlace: { _ in true },
            liveSavedPlaceTierIsAuthoritative: { false }
        )
        await store.refreshLivePlaces()
        store.sheet = .save
        store.saveQuery = "方案還沒核對"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "方案還沒核對" })
        XCTAssertEqual(store.saveNotice, "還在核對可以存幾個地點，請稍後再存。")
        XCTAssertEqual(store.sheet, .save)
    }

    func testFailedRefreshPausesLiveSavesAgain() async {
        var authoritative = true
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [] },
            load: { ink in
                let allowed = authoritative
                authoritative = false
                return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil, countIsAuthoritative: allowed)
            }
        )
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.recount.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { "account-a" },
            canSaveAnotherLivePlace: { _ in true },
            liveSavedPlaceTierIsAuthoritative: { true }
        )
        await store.refreshLivePlaces()
        store.saveQuery = "核對過"
        store.commitSave()
        XCTAssertTrue(store.places.contains { $0.name == "核對過" })
        await store.refreshLivePlaces()
        store.saveNotice = nil
        store.saveQuery = "又失敗"
        store.commitSave()
        XCTAssertFalse(store.places.contains { $0.name == "又失敗" })
        XCTAssertEqual(store.saveNotice, "還在核對已存的地點，請稍後再存。")
    }

    func testAccountDeletionRemovesThatAccountsInkMemory() throws {
        let defaults = UserDefaults(suiteName: "save.ink.purge.\(UUID().uuidString)")!
        let places = """
        [
          {"id":"saved-a","name":"甲的店","stampName":"甲的店","street":"甲","blurb":"甲","sourceLabel":"來自 甲","detailNote":"甲","ownerSubject":"account-a"},
          {"id":"saved-b","name":"乙的店","stampName":"乙的店","street":"乙","blurb":"乙","sourceLabel":"來自 乙","detailNote":"乙","ownerSubject":"account-b"}
        ]
        """
        defaults.set(Data(places.utf8), forKey: SavePlaceLinkGate.placesKey)
        let visit = SaveInkVisitRecord(
            id: UUID(),
            placeID: "saved-a",
            visitedAt: SaveInkClock.previewNow,
            verification: .verified,
            visibility: .public,
            comment: "要刪的",
            sentiment: nil,
            anomaly: nil
        )
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1.account-a")
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1.account-b")
        try SaveInkNotebookStore.purgeAccount("account-a", defaults: defaults)
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" }
        )
        XCTAssertFalse(store.places.contains { $0.name == "甲的店" })
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-a"))
        let other = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-b" }
        )
        XCTAssertTrue(other.places.contains { $0.name == "乙的店" })
        XCTAssertNotNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
    }

    func testAccountDeletionFailsWhenInkPlacesCannotBeRead() {
        let defaults = UserDefaults(suiteName: "save.ink.purge-bad.\(UUID().uuidString)")!
        defaults.set(Data("not-json".utf8), forKey: SavePlaceLinkGate.placesKey)
        XCTAssertThrowsError(try SaveInkNotebookStore.purgeAccount("account-a", defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: SavePlaceLinkGate.placesKey), Data("not-json".utf8))
    }

    func testUnreadableInkFileIsNotReplacedByANewSave() async {
        let defaults = UserDefaults(suiteName: "save.ink.opaque.\(UUID().uuidString)")!
        let opaque = Data("not-json".utf8)
        defaults.set(opaque, forKey: SavePlaceLinkGate.placesKey)
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" },
            liveSavedPlaceTierIsAuthoritative: { true }
        )
        await store.refreshLivePlaces()
        store.sheet = .save
        store.saveQuery = "不該蓋掉"
        store.commitSave()
        XCTAssertEqual(defaults.data(forKey: SavePlaceLinkGate.placesKey), opaque)
        XCTAssertFalse(store.places.contains { $0.name == "不該蓋掉" })
        XCTAssertNil(store.recognizedPlaceID)
        XCTAssertEqual(store.saveNotice, "這次沒有存下來。請稍後再試。")
        XCTAssertEqual(store.sheet, .save)
    }

    func testResolvedLiveOwnerUsesTheCachedAccountWhileAuthIsUnknown() {
        XCTAssertEqual(
            SaveInkNotebookStore.resolvedLiveOwner(
                authUnknown: true,
                currentUserId: nil,
                cachedOwner: "account-a"
            ),
            "account-a"
        )
        XCTAssertEqual(
            SaveInkNotebookStore.resolvedLiveOwner(
                authUnknown: false,
                currentUserId: "account-b",
                cachedOwner: "account-a"
            ),
            "account-b"
        )
        XCTAssertNil(
            SaveInkNotebookStore.resolvedLiveOwner(
                authUnknown: false,
                currentUserId: nil,
                cachedOwner: "account-a"
            )
        )
    }

    func testLegacyInkSaveStaysHiddenUntilAnOwnerIsKnown() {
        let defaults = UserDefaults(suiteName: "save.ink.legacy.\(UUID().uuidString)")!
        let legacy = """
        [{
          "id": "saved-legacy",
          "name": "升級前的店",
          "stampName": "升級前的店",
          "street": "舊街",
          "blurb": "舊",
          "sourceLabel": "來自 你貼上的店名",
          "detailNote": "舊"
        }]
        """
        defaults.set(Data(legacy.utf8), forKey: SavePlaceLinkGate.placesKey)
        let accountA = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { "account-a" }
        )
        XCTAssertFalse(accountA.places.contains { $0.name == "升級前的店" })
        let signedOut = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { nil }
        )
        XCTAssertTrue(signedOut.places.contains { $0.name == "升級前的店" })
    }

    func testChangingSaveInputInvalidatesThePreviousRecognition() throws {
        let store = SaveInkNotebookStore(defaults: inkSuite("recognition-input"))
        store.saveQuery = "第一間小店"
        store.commitSave()
        let first = try XCTUnwrap(store.recognizedPlaceID)
        store.saveQuery = "第二間小店"
        XCTAssertNil(store.recognizedPlaceID)
        store.commitSave()
        XCTAssertNotEqual(store.recognizedPlaceID, first)
        XCTAssertEqual(Set(store.places.map(\.name)), ["第一間小店", "第二間小店"])
        store.saveLink = "https://maps.apple.com/?q=第三間小店"
        XCTAssertNil(store.recognizedPlaceID)
    }

    func testStaleLiveCatalogCannotStartAnotherAccountsCheckIn() async {
        var row = inkRow(id: "owner-a-place", name: "甲店", street: "甲街")
        row.shopLatitude = 25.03
        row.shopLongitude = 121.53
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [row] },
            load: { _ in SaveInkLivePlaceLoad(places: [row], userCoordinate: nil) }
        )
        let defaults = inkSuite("stale-checkin")
        let locator = SaveInkScriptedLocator()
        var owner = "account-a"
        let store = SaveInkNotebookStore(
            defaults: defaults, makeLocator: { locator }, usesLivePlaces: true,
            liveLoader: loader, liveOwner: { owner }
        )
        owner = "account-b"
        await store.checkIn(placeID: row.id)
        XCTAssertEqual(locator.calls, 0)
        XCTAssertTrue(store.visits.isEmpty)
        XCTAssertNil(store.sheet)
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-a"))
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
    }

    func testCheckInResolvesCanonicalIdentityAfterAwaitingLocation() async throws {
        var original = inkRow(id: "local-place", name: "甲店", street: "甲街")
        original.shopLatitude = 25.03
        original.shopLongitude = 121.53
        var catalog = [original]
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in catalog },
            load: { _ in SaveInkLivePlaceLoad(places: catalog, userCoordinate: nil) }
        )
        let locator = SaveInkSuspendedLocator()
        let defaults = inkSuite("checkin-adoption")
        let store = SaveInkNotebookStore(
            defaults: defaults, now: { SaveInkClock.previewNow }, makeLocator: { locator },
            usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-a" }
        )
        store.path = [.place(original.id)]
        let pending = Task { await store.checkIn(placeID: original.id) }
        await locator.waitUntilRequested()
        var adopted = original
        adopted.id = "remote-place"
        adopted.aliasIDs = [original.id]
        catalog = [adopted]
        await store.refreshLivePlaces()
        locator.finish(.inRange(meters: 18))
        await pending.value

        XCTAssertEqual(store.visits.first?.placeID, adopted.id)
        XCTAssertEqual(store.verifiedCount(for: adopted.id), 1)
        XCTAssertEqual(store.place(original.id)?.badge, .visited)
        XCTAssertEqual(store.activePlaceID, adopted.id)
        XCTAssertEqual(store.path, [.place(adopted.id)])
        XCTAssertEqual(store.sheet, .checkIn(.verified, placeID: adopted.id))
        store.draftComment = "刷新時仍保留這次到訪"
        store.commitDraft()
        let reloaded = SaveInkNotebookStore(
            defaults: defaults, usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-a" }
        )
        XCTAssertEqual(reloaded.latestVisit(for: adopted.id)?.comment, "刷新時仍保留這次到訪")
        XCTAssertEqual(reloaded.homeBadge(for: try XCTUnwrap(reloaded.place(original.id))), .visited)
    }

    func testCheckInRejectsAFixMeasuredBeforeShopCoordinatesChanged() async throws {
        var original = inkRow(id: "corrected-place", name: "甲店", street: "甲街")
        original.shopLatitude = 25.03
        original.shopLongitude = 121.53
        var catalog = [original]
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in catalog },
            load: { _ in SaveInkLivePlaceLoad(places: catalog, userCoordinate: nil) }
        )
        let locator = SaveInkSuspendedLocator()
        let defaults = inkSuite("checkin-coordinate-correction")
        let prior = inkVisit(placeID: original.id, comment: "既有到訪筆記")
        let priorBytes = try SaveInkNotebookStore.encoder.encode([prior])
        defaults.set(priorBytes, forKey: "save.ink.visits.v1.account-a")
        let store = SaveInkNotebookStore(
            defaults: defaults, makeLocator: { locator }, usesLivePlaces: true,
            liveLoader: loader, liveOwner: { "account-a" }
        )
        store.draftComment = "不能覆寫既有紀錄的殘留草稿"
        let pending = Task { await store.checkIn(placeID: original.id) }
        await locator.waitUntilRequested()
        catalog[0].shopLatitude = 26.03
        await store.refreshLivePlaces()
        locator.finish(.inRange(meters: 18))
        await pending.value
        XCTAssertEqual(store.visits.count, 1)
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1.account-a"), priorBytes)
        XCTAssertEqual(store.sheet, .checkIn(.placeChanged, placeID: original.id))
        let image = try hostedInkImage(SaveInkCheckInSheet(
            store: store, place: try XCTUnwrap(store.place(original.id)), situation: .placeChanged
        ), width: 375)
        let attachment = XCTAttachment(image: image)
        attachment.name = "ink-place-changed-375"
        attachment.lifetime = .keepAlways
        add(attachment)
        store.commitDraft()
        XCTAssertNil(store.sheet)
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1.account-a"), priorBytes)
        XCTAssertEqual(store.latestVisit(for: original.id)?.comment, "既有到訪筆記")
    }

    func testIgnoredCheckInPreservesUnreadableStoredVisitBytes() async {
        var row = inkRow(id: "located-place", name: "甲店", street: "甲街")
        row.shopLatitude = 25.03
        row.shopLongitude = 121.53
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in [row] },
            load: { _ in SaveInkLivePlaceLoad(places: [row], userCoordinate: nil) }
        )
        let defaults = inkSuite("ignored-checkin-bytes")
        let raw = Data("unreadable visits retained for recovery".utf8)
        defaults.set(raw, forKey: "save.ink.visits.v1.account-a")
        var far = SaveInkFix.inRange()
        far.distanceMeters = 400
        let store = SaveInkNotebookStore(
            defaults: defaults, makeLocator: { SaveInkScriptedLocator(fix: far) },
            usesLivePlaces: true, liveLoader: loader, liveOwner: { "account-a" }
        )
        await store.checkIn(placeID: row.id)
        XCTAssertTrue(store.visits.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "save.ink.visits.v1.account-a"), raw)
        XCTAssertEqual(store.sheet, .checkIn(.tooFar(meters: 400), placeID: row.id))
    }

    func testSaveAnywayRefusesAfterTheAccountChanges() async {
        let defaults = UserDefaults(suiteName: "save.ink.anyway.\(UUID().uuidString)")!
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
        var far = SaveInkFix.inRange()
        far.distanceMeters = 400
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator(fix: far) },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { owner }
        )
        await store.checkIn(placeID: "saved-a")
        owner = "account-b"
        store.saveAnyway()
        XCTAssertNil(store.sheet)
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-a"))
    }

    func testCommitSaveRefusesAfterTheAccountChanges() throws {
        let defaults = UserDefaults(suiteName: "save.ink.save-owner.\(UUID().uuidString)")!
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
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { owner }
        )
        owner = "account-b"
        store.saveQuery = "乙的新店"
        store.commitSave()
        let saved = try XCTUnwrap(defaults.data(forKey: SavePlaceLinkGate.placesKey))
        let text = String(decoding: saved, as: UTF8.self)
        XCTAssertFalse(text.contains("account-b"))
        XCTAssertFalse(text.contains("乙的新店"))
        XCTAssertTrue(text.contains("account-a"))
    }

    func testCommitDraftRefusesAfterTheAccountChanges() async throws {
        let defaults = UserDefaults(suiteName: "save.ink.draft-owner.\(UUID().uuidString)")!
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
            makeLocator: { SaveInkScriptedLocator(fix: .inRange(meters: 18)) },
            usesLivePlaces: true,
            liveLoader: .inactive,
            liveOwner: { owner }
        )
        await store.checkIn(placeID: "saved-a")
        store.draftComment = "不該過去"
        owner = "account-b"
        store.commitDraft()
        XCTAssertNil(defaults.data(forKey: "save.ink.visits.v1.account-b"))
        let kept = try XCTUnwrap(defaults.data(forKey: "save.ink.visits.v1.account-a"))
        XCTAssertFalse(String(decoding: kept, as: UTF8.self).contains("不該過去"))
    }

    func testInkSavesCountTowardTheShareCap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-cap-ink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "排隊店", address: "巳路", latitude: 25.16, longitude: 121.66, owner: "account-a")
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        var counts: [Int] = []
        let engine = SaveInkLivePlaceEngine(
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            pending: queue,
            remote: SaveInkRemoteFake(),
            userID: { "account-a" },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { ("account-a", 1) },
            canConfirmAnother: { count in
                counts.append(count)
                return count < 1
            }
        )
        let loaded = await engine.load(ink: [inkRow(id: "saved-ink", name: "手寫店", street: "手寫")])
        XCTAssertEqual(counts, [1])
        XCTAssertFalse(loaded.places.contains { $0.name == "排隊店" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["排隊店"])
    }

    func testNewerShareWithTheSameKeyStaysQueued() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-newer-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = inkPending(name: "同鍵店", address: "午路", latitude: 25.17, longitude: 121.67, owner: "account-a")
        first.sourceURL = "https://example.com/post/same"
        first.dishes = ["舊菜"]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([first])
        let remote = SaveInkRemoteFake()
        remote.beforeFetch = {
            var newer = first
            newer.dishes = ["新菜"]
            newer.savedAt = first.savedAt.addingTimeInterval(60)
            queue.restorePendingPlaces([newer])
        }
        let engine = liveEngine(
            owner: "account-a",
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            queue: queue,
            remote: remote
        )
        _ = await engine.load(ink: [])
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.dishes), [["新菜"]])
    }

    func testFailedDuplicateShareStaysQueued() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-dup-key-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = inkPending(name: "同鍵店", address: "申路", latitude: 25.19, longitude: 121.69, owner: "account-a")
        first.sourceURL = "https://example.com/post/dup"
        first.dishes = ["舊菜"]
        var second = first
        second.dishes = ["新菜"]
        second.savedAt = first.savedAt.addingTimeInterval(30)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([first, second])
        let remote = SaveInkRemoteFake()
        remote.afterSave = { remote.saveError = URLError(.networkConnectionLost) }
        let engine = liveEngine(
            owner: "account-a",
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            queue: queue,
            remote: remote
        )
        _ = await engine.load(ink: [])
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.dishes), [["新菜"]])
    }

    func testSuccessfulFetchDropsAStampDeletedElsewhere() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-deleted-elsewhere-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let deleted = Place.from(inkPending(name: "別台刪了", address: "戌路", latitude: 25.21, longitude: 121.71))
        let waiting = Place.from(inkPending(name: "還在排隊", address: "亥路", latitude: 25.22, longitude: 121.72))
        _ = try vault.saveConfirmedPlace(deleted, ownerSubject: "account-a")
        _ = try vault.saveConfirmedPlace(waiting, ownerSubject: "account-a")
        var queued = inkPending(name: "還在排隊", address: "亥路", latitude: 25.22, longitude: 121.72, owner: "account-a")
        queued.dishes = ["待傳"]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([queued])
        let remote = SaveInkRemoteFake()
        remote.saveError = URLError(.networkConnectionLost)
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "別台刪了" })
        XCTAssertTrue(loaded.places.contains { $0.name == "還在排隊" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "別台刪了" })
        XCTAssertTrue(stored.contains { $0.name == "還在排隊" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["還在排隊"])
    }

    func testVaultRereadDoesNotRestoreASuppressedDeletedStamp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-suppression-reread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let removed = Place.from(inkPending(name: "已在遠端刪掉", address: "甲路", latitude: 25.1, longitude: 121.5))
        _ = try vault.saveConfirmedPlace(removed, ownerSubject: "account-a")
        vault.removeConfirmedPlaceError = SaveLocalVaultError.storageUnavailable
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([inkPending(name: "新分享", address: "乙路", latitude: 25.2, longitude: 121.6, owner: "account-a")])
        let remote = SaveInkRemoteFake()
        let loaded = await liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote).load(ink: [])
        XCTAssertEqual(remote.saved.map(\.name), ["新分享"])
        XCTAssertEqual(loaded.places.map(\.name), ["新分享"])
        XCTAssertTrue(loaded.countIsAuthoritative)
        XCTAssertEqual(vault.capRejectedStampIDs(owner: "account-a"), [removed.id])
    }

    func testRemoteAdoptionPreservesLocalAliasesAndVisitRoutes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-remote-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var local = Place.from(inkPending(name: "同一家", address: "甲路", latitude: 25.1, longitude: 121.5))
        let oldAlias = UUID()
        local.mergedPlaceIDs = [oldAlias]
        _ = try vault.saveConfirmedPlace(local, ownerSubject: "account-a")
        var server = local.rekeyed(to: UUID())
        server.mergedPlaceIDs = nil
        server.note = "遠端編輯"
        let remote = SaveInkRemoteFake()
        remote.places = [server]
        let engine = liveEngine(owner: "account-a", vault: vault, queue: PendingPlaceImportService(overrideContainerURL: directory), remote: remote)
        let defaults = UserDefaults(suiteName: "save.ink.remote-alias.\(UUID().uuidString)")!
        let visit = SaveInkVisitRecord(id: UUID(), placeID: oldAlias.uuidString, visitedAt: SaveInkClock.previewNow,
                                       verification: .unverified, visibility: .private, comment: "真實紀錄", sentiment: nil, anomaly: nil)
        defaults.set(try SaveInkNotebookStore.encoder.encode([visit]), forKey: "save.ink.visits.v1.account-a")
        let loader = SaveInkLivePlaceLoader(localPlaces: { engine.localPlaces(ink: $0) }, load: { await engine.load(ink: $0) })
        let store = SaveInkNotebookStore(defaults: defaults, now: { SaveInkClock.previewNow }, usesLivePlaces: true,
                                         liveLoader: loader, liveOwner: { "account-a" })
        store.openPlace(local.id.uuidString)
        await store.refreshLivePlaces()
        XCTAssertEqual(store.place(local.id.uuidString)?.id, server.id.uuidString)
        XCTAssertEqual(store.place(oldAlias.uuidString)?.id, server.id.uuidString)
        XCTAssertEqual(store.latestVisit(for: server.id.uuidString)?.id, visit.id)
        XCTAssertEqual(store.path, [.place(server.id.uuidString)])
        XCTAssertEqual(store.place(server.id.uuidString)?.detailNote, "遠端編輯")
        let persisted = try XCTUnwrap(try vault.confirmedPlaces(limit: 20, belongingTo: "account-a").first)
        XCTAssertTrue(persisted.savedIDs.isSuperset(of: [local.id, oldAlias, server.id]))
    }

    func testUnwritableQueueDoesNotKeepAnOwnerlessStamp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-unwritable-\(UUID().uuidString)")
        let queueDirectory = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let item = inkPending(name: "寫不進去", address: "酉路", latitude: 25.20, longitude: 121.70, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: queueDirectory)
        queue.restorePendingPlaces([item])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        let remote = SaveInkRemoteFake()
        remote.saveError = URLError(.networkConnectionLost)
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "寫不進去" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "寫不進去" })
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["寫不進去"])
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "寫不進去" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        XCTAssertFalse(queue.bindPendingPlaces(keys: [item.deduplicationKey], to: "account-a"))
    }

    func testCapStopDropsTheStampWhenTheOwnerlessQueueCannotBeRewritten() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-stop-unwritable-\(UUID().uuidString)")
        let queueDirectory = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let item = inkPending(name: "超額寫不進", address: "亥路", latitude: 25.23, longitude: 121.73, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: queueDirectory)
        queue.restorePendingPlaces([item])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        let remote = SaveInkRemoteFake()
        remote.saveError = SavePlaceLimitError.parkedInUnplacedInbox
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "超額寫不進" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        XCTAssertFalse(stored.contains { $0.name == "超額寫不進" })
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["超額寫不進"])
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "超額寫不進" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
        let storedForB = try vault.confirmedPlaces(limit: 20, belongingTo: "account-b")
        XCTAssertFalse(storedForB.contains { $0.name == "超額寫不進" })
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
        _ = await engine.load(ink: [])
        XCTAssertNil(vault.unboundShareOwner(for: item.deduplicationKey))
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: nil).isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["超額寫不進"])
    }

    func testOpaqueCapRejectionMarkersHideTheCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-bad-rejected-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let place = Place.from(inkPending(name: "不該露出", address: "未路", latitude: 25.31, longitude: 121.81))
        _ = try vault.saveConfirmedPlace(place, ownerSubject: "account-a")
        vault.testingStoreOpaqueCapRejectedMarkers(Data("not-json".utf8), owner: "account-a")
        XCTAssertNil(vault.capRejectedStampIDs(owner: "account-a"))
        XCTAssertFalse(vault.rememberCapRejectedStamp(UUID(), owner: "account-a"))
        XCTAssertNil(vault.capRejectedStampIDs(owner: "account-a"))
        let engine = liveEngine(
            owner: "account-a",
            vault: vault,
            queue: PendingPlaceImportService(overrideContainerURL: directory),
            remote: SaveInkRemoteFake()
        )
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "不該露出" })
        XCTAssertFalse(loaded.countIsAuthoritative)
        XCTAssertFalse(engine.localPlaces(ink: []).contains { $0.name == "不該露出" })
    }

    func testSuccessfulUploadKeepsTheHoldUntilQueueBindingRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-upload-hold-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "傳完再清", address: "申路", latitude: 25.32, longitude: 121.82, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertTrue(vault.claimUnboundShare(key: item.deduplicationKey, owner: "account-a"))
        queue.forceBindFailure = true
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        XCTAssertEqual(remote.saved.count, 1)
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).count, 1)
        let otherRemote = SaveInkRemoteFake()
        _ = await liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote).load(ink: [])
        XCTAssertTrue(otherRemote.saved.isEmpty)
        queue.forceBindFailure = false
        remote.places = remote.saved
        _ = await engine.load(ink: [])
        XCTAssertNil(vault.unboundShareOwner(for: item.deduplicationKey))
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
        queue.restorePendingPlaces([item])
        _ = await liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote).load(ink: [])
        XCTAssertEqual(otherRemote.saved.count, 1)
    }

    func testSessionChangeCannotReimportEarlierUploadedShares() async throws {
        try await assertProcessedSharesStayOwnedAcrossSessionChange(bindingFails: false)
    }

    func testSessionChangeKeepsFallbackOwnershipForEarlierUploads() async throws {
        try await assertProcessedSharesStayOwnedAcrossSessionChange(bindingFails: true)
    }

    private func assertProcessedSharesStayOwnedAcrossSessionChange(bindingFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-upload-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = [
            inkPending(name: "第一分享店", address: "甲路", latitude: 25.30, longitude: 121.80),
            inkPending(name: "第二分享店", address: "乙路", latitude: 26.30, longitude: 122.80),
        ]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces(items)
        queue.forceBindFailure = bindingFails
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        var owner = "account-a"
        var generation = 1
        let remote = SaveInkRemoteFake()
        defer { remote.afterSave = nil }
        remote.afterSave = {
            remote.places = remote.saved
            if remote.saved.count == 2 {
                owner = "account-b"
                generation = 2
            }
        }
        let engine = SaveInkLivePlaceEngine(
            vault: vault, pending: queue, remote: remote, userID: { owner },
            location: { nil }, walkingMinutes: { _, _ in nil },
            currentSession: { (owner, generation) }, canConfirmAnother: { _ in true }
        )
        _ = await engine.load(ink: [])
        XCTAssertEqual(remote.saved.count, 2)
        let kept = queue.peekPendingPlaces(ownerSubject: "account-a")
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(kept.allSatisfy { $0.ownerSubject == (bindingFails ? nil : "account-a") })
        if bindingFails {
            for item in items {
                XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
            }
        }
        let otherRemote = SaveInkRemoteFake()
        let other = await liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote).load(ink: [])
        XCTAssertTrue(other.places.isEmpty)
        XCTAssertTrue(otherRemote.saved.isEmpty)
        XCTAssertTrue(otherRemote.updated.isEmpty)
        XCTAssertTrue(try vault.confirmedPlaces(limit: 20, belongingTo: "account-b").isEmpty)

        queue.forceBindFailure = false
        owner = "account-a"
        generation = 3
        _ = await engine.load(ink: [])
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
        for item in items { XCTAssertNil(vault.unboundShareOwner(for: item.deduplicationKey)) }
    }

    func testFailedHoldReleaseKeepsAQueueRowForRetry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-release-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "清理再試", address: "申路", latitude: 25.32, longitude: 121.82, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertTrue(vault.claimUnboundShare(key: item.deduplicationKey, owner: "account-a"))
        vault.releaseUnboundShareError = SaveLocalVaultError.storageUnavailable
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").count, 1)
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        vault.releaseUnboundShareError = nil
        _ = await engine.load(ink: [])
        XCTAssertEqual(remote.saved.count, 1)
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
        XCTAssertNil(vault.unboundShareOwner(for: item.deduplicationKey))
    }

    func testRetryHoldDoesNotDeleteTheShareWhenBindingFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-retry-hold-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "稍後再傳", address: "申路", latitude: 25.32, longitude: 121.82, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertTrue(vault.claimUnboundShare(key: item.deduplicationKey, owner: "account-a"))
        queue.forceBindFailure = true
        let remote = SaveInkRemoteFake()
        remote.saveError = URLError(.networkConnectionLost)
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["稍後再傳"])
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "稍後再傳" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
    }

    func testOpaqueShareFallbackBlocksTheQueue() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-bad-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "備援壞了", address: "午路", latitude: 25.30, longitude: 121.80, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        vault.testingStoreOpaqueUnboundShareFallback(Data("not-json".utf8))
        XCTAssertFalse(vault.unboundShareLedgerIsReadable())
        XCTAssertFalse(vault.claimUnboundShare(key: item.deduplicationKey, owner: "account-b"))
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "備援壞了" })
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["備援壞了"])
    }

    func testAccountDeletionRemovesCapRejectionMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-purge-rejected-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertTrue(vault.rememberCapRejectedStamp(UUID(), owner: "account-a"))
        XCTAssertTrue(vault.rememberCapRejectedStamp(UUID(), owner: "account-b"))
        try vault.purgeUnboundShares(belongingTo: "account-a")
        XCTAssertEqual(vault.capRejectedStampIDs(owner: "account-a"), [])
        XCTAssertEqual(vault.capRejectedStampIDs(owner: "account-b")?.count, 1)
    }

    func testLedgerFileFailureStillHoldsTheShare() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-ledger-fallback-\(UUID().uuidString)")
        let queueDirectory = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let item = inkPending(name: "帳本改記", address: "辰路", latitude: 25.28, longitude: 121.78, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: queueDirectory)
        queue.restorePendingPlaces([item])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        let remote = SaveInkRemoteFake()
        remote.afterSave = {
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        }
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertTrue(loaded.places.contains { $0.name == "帳本改記" })
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "帳本改記" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
    }

    func testCapRejectionStaysHiddenWhenTheStampCannotBeRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-drop-fails-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "刪不掉", address: "巳路", latitude: 25.29, longitude: 121.79, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        vault.removeConfirmedPlaceError = SaveLocalVaultError.storageUnavailable
        let remote = SaveInkRemoteFake()
        remote.saveError = SavePlaceLimitError.parkedInUnplacedInbox
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "刪不掉" })
        XCTAssertEqual(vault.capRejectedStampIDs(owner: "account-a")?.isEmpty, false)
        XCTAssertTrue(try vault.confirmedPlaces(limit: 20, belongingTo: "account-a").contains { $0.name == "刪不掉" })
        XCTAssertFalse(engine.localPlaces(ink: []).contains { $0.name == "刪不掉" })
        let again = await engine.load(ink: [])
        XCTAssertFalse(again.places.contains { $0.name == "刪不掉" })
        vault.removeConfirmedPlaceError = nil
        _ = await engine.load(ink: [])
        XCTAssertFalse(try vault.confirmedPlaces(limit: 20, belongingTo: "account-a").contains { $0.name == "刪不掉" })
        XCTAssertEqual(vault.capRejectedStampIDs(owner: "account-a"), [])
    }

    func testCoordinationFailureDoesNotClaimTheQueueRow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-coordinate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "協調失敗", address: "寅路", latitude: 25.26, longitude: 121.76, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let file = directory.appendingPathComponent(SAVEProductionConfig.pendingPlacesFileName)
        let before = try Data(contentsOf: file)
        queue.forceCoordinationFailure = true
        XCTAssertFalse(queue.bindPendingPlaces(keys: [item.deduplicationKey], to: "account-a"))
        XCTAssertFalse(queue.removeProcessedPendingPlaces([item]))
        XCTAssertEqual(try Data(contentsOf: file), before)
        queue.forceCoordinationFailure = false
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["協調失敗"])
        let eligible = queue.peekPendingPlaces(ownerSubject: "account-a")
        XCTAssertEqual(eligible.count, 1)
        XCTAssertNil(eligible.first?.ownerSubject, "A failed bind leaves the row eligible, not owned by account-a")
    }

    func testSuccessfulUploadHoldsAnOwnerlessRowWhenTheQueueCannotBeRewritten() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-uploaded-unwritable-\(UUID().uuidString)")
        let queueDirectory = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: queueDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let item = inkPending(name: "傳了寫不進", address: "丑路", latitude: 25.25, longitude: 121.75, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: queueDirectory)
        queue.restorePendingPlaces([item])
        queue.forceBindFailure = true // Exercise fallback ownership before and after upload.
        let remote = SaveInkRemoteFake()
        remote.afterSave = {
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: queueDirectory.path)
        }
        let vault = SaveLocalVaultService(overrideVaultURL: root.appendingPathComponent("vault.json"))
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertTrue(loaded.places.contains { $0.name == "傳了寫不進" })
        XCTAssertEqual(vault.unboundShareOwner(for: item.deduplicationKey), "account-a")
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["傳了寫不進"])
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "傳了寫不進" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
    }

    func testUnreadableUnboundShareLedgerBlocksEveryAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-bad-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = inkPending(name: "帳本壞了", address: "子路", latitude: 25.24, longitude: 121.74, owner: nil)
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let ledger = directory.appendingPathComponent("save.ink.unbound-shares.json")
        let opaque = Data("not-json".utf8)
        try opaque.write(to: ledger)
        XCTAssertFalse(vault.unboundShareLedgerIsReadable())
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        let loaded = await engine.load(ink: [])
        XCTAssertFalse(loaded.places.contains { $0.name == "帳本壞了" })
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertEqual(try Data(contentsOf: ledger), opaque)
        XCTAssertFalse(vault.claimUnboundShare(key: item.deduplicationKey, owner: "account-a"))
        XCTAssertEqual(try Data(contentsOf: ledger), opaque)
        let otherRemote = SaveInkRemoteFake()
        let other = liveEngine(owner: "account-b", vault: vault, queue: queue, remote: otherRemote)
        let second = await other.load(ink: [])
        XCTAssertFalse(second.places.contains { $0.name == "帳本壞了" })
        XCTAssertTrue(otherRemote.saved.isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: nil).map(\.name), ["帳本壞了"])
    }

    func testAccountDeletionRemovesOnlyThatAccountsUnboundShare() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-purge-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        XCTAssertTrue(vault.claimUnboundShare(key: "share-a", owner: "account-a"))
        XCTAssertTrue(vault.claimUnboundShare(key: "share-b", owner: "account-b"))
        try vault.purgeUnboundShares(belongingTo: "account-a")
        XCTAssertNil(vault.unboundShareOwner(for: "share-a"))
        XCTAssertEqual(vault.unboundShareOwner(for: "share-b"), "account-b")
        let ledger = directory.appendingPathComponent("save.ink.unbound-shares.json")
        let opaque = Data("not-json".utf8)
        try opaque.write(to: ledger)
        XCTAssertThrowsError(try vault.purgeUnboundShares(belongingTo: "account-a"))
        XCTAssertEqual(try Data(contentsOf: ledger), opaque)
    }

    func testMatchingShareUpdatesTheServerStampBeforeClaiming() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-remote-evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let local = Place.from(inkPending(name: "遠端證據", address: "未路", latitude: 25.18, longitude: 121.68))
        _ = try vault.saveConfirmedPlace(local, ownerSubject: "account-a")
        var item = inkPending(name: "遠端證據", address: "未路", latitude: 25.18, longitude: 121.68, owner: "account-a")
        item.sourceURL = "https://example.com/post/remote-evidence"
        item.dishes = ["豆花"]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let remote = SaveInkRemoteFake()
        remote.places = [local]
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        let updated = try XCTUnwrap(remote.updated.first { $0.name == "遠端證據" })
        XCTAssertEqual(updated.sourceUrl, "https://example.com/post/remote-evidence")
        XCTAssertTrue(updated.savedRecommendedItems.contains { $0.name == "豆花" })
        XCTAssertTrue(remote.saved.isEmpty)
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
        remote.updated = []
        remote.saveError = URLError(.networkConnectionLost)
        queue.restorePendingPlaces([item])
        _ = await engine.load(ink: [])
        XCTAssertTrue(remote.updated.isEmpty)
        XCTAssertEqual(queue.peekPendingPlaces(ownerSubject: "account-a").map(\.name), ["遠端證據"])
    }

    func testMatchingShareKeepsTheNewSourceOnTheStamp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let local = Place.from(inkPending(name: "證據店", address: "辰路", latitude: 25.15, longitude: 121.65))
        _ = try vault.saveConfirmedPlace(local, ownerSubject: "account-a")
        var item = inkPending(name: "證據店", address: "辰路", latitude: 25.15, longitude: 121.65, owner: "account-a")
        item.sourceURL = "https://example.com/post/evidence"
        item.dishes = ["紅燒肉"]
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(owner: "account-a", vault: vault, queue: queue, remote: remote)
        _ = await engine.load(ink: [])
        let uploaded = try XCTUnwrap(remote.saved.first { $0.name == "證據店" })
        XCTAssertEqual(uploaded.sourceUrl, "https://example.com/post/evidence")
        XCTAssertTrue(uploaded.savedRecommendedItems.contains { $0.name == "紅燒肉" })
        let stored = try vault.confirmedPlaces(limit: 20, belongingTo: "account-a")
        let row = try XCTUnwrap(stored.first { $0.name == "證據店" })
        XCTAssertEqual(row.sourceUrl, "https://example.com/post/evidence")
        XCTAssertTrue(queue.peekPendingPlaces(ownerSubject: "account-a").isEmpty)
    }

    func testOpenDetailFollowsTheConsolidatedPlaceID() async {
        let local = inkRow(id: "local-id", name: "合併店", street: "街")
        var remote = inkRow(id: "remote-id", name: "合併店", street: "街")
        remote.aliasIDs = ["local-id"]
        var showedLocal = true
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in showedLocal ? [local] : [remote] },
            load: { _ in
                showedLocal = false
                return SaveInkLivePlaceLoad(places: [remote], userCoordinate: nil)
            }
        )
        let store = SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.alias.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { "account-a" }
        )
        store.openPlace("local-id")
        XCTAssertEqual(store.path, [.place("local-id")])
        await store.refreshLivePlaces()
        XCTAssertEqual(store.place("local-id")?.id, "remote-id")
        XCTAssertEqual(store.path, [.place("remote-id")])
        XCTAssertEqual(store.activePlaceID, "remote-id")
    }

    private func livePlaceStore(places: [SaveInkPlace]) -> SaveInkNotebookStore {
        let loader = SaveInkLivePlaceLoader(
            localPlaces: { _ in places },
            load: { _ in SaveInkLivePlaceLoad(places: places, userCoordinate: nil) }
        )
        return SaveInkNotebookStore(
            defaults: UserDefaults(suiteName: "save.ink.arrival.\(UUID().uuidString)")!,
            now: { SaveInkClock.previewNow },
            seedFixture: false,
            makeLocator: { SaveInkScriptedLocator() },
            usesLivePlaces: true,
            liveLoader: loader,
            liveOwner: { "account-a" }
        )
    }

    private func uploadedOwnerlessID(owner: String, item: PendingSharedPlace) async throws -> UUID {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ink-id-\(owner)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([item])
        let remote = SaveInkRemoteFake()
        let engine = liveEngine(
            owner: owner,
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            queue: queue,
            remote: remote
        )
        _ = await engine.load(ink: [])
        return try XCTUnwrap(remote.saved.first?.id)
    }

    private func liveLoader(
        owner: String,
        directory: URL,
        vault: SaveLocalVaultService,
        queue: [PendingSharedPlace],
        remote: SaveInkRemoteFake
    ) -> SaveInkLivePlaceLoader {
        let pending = PendingPlaceImportService(overrideContainerURL: directory)
        pending.restorePendingPlaces(queue)
        let engine = liveEngine(owner: owner, vault: vault, queue: pending, remote: remote)
        return SaveInkLivePlaceLoader(
            localPlaces: { engine.localPlaces(ink: $0) },
            load: { await engine.load(ink: $0) }
        )
    }

    private func liveEngine(
        owner: String,
        vault: SaveLocalVaultService,
        queue: PendingPlaceImportService,
        remote: SaveInkRemoteFake
    ) -> SaveInkLivePlaceEngine {
        SaveInkLivePlaceEngine(
            vault: vault,
            pending: queue,
            remote: remote,
            userID: { owner },
            location: { nil },
            walkingMinutes: { _, _ in nil },
            currentSession: { (owner, 1) },
            canConfirmAnother: { _ in true }
        )
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

@MainActor
private final class SaveInkAmapNavigationStub: WKWebView {
    let navigation = WKNavigation()
    override func load(_ request: URLRequest) -> WKNavigation? { navigation }
}

/// Loopback-only, deterministic HTTP fixture. It never forwards requests outside
/// the test process and closes all accepted sockets during teardown.
private final class SaveInkHTTP200MapFixture: @unchecked Sendable {
    static let bodySentinel = "Successful HTTP 200 shell without a map"
    private let listener: NWListener
    private let queue = DispatchQueue(label: "savvy.map.http200-fixture")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var stopped = false
    private var successfulSends = 0
    var port: UInt16? { listener.port?.rawValue }
    var responseSentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return successfulSends
    }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let body = Data("<html><body>\(Self.bodySentinel)</body></html>".utf8)
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.lock()
            guard !self.stopped else { self.lock.unlock(); connection.cancel(); return }
            self.connections.append(connection)
            self.lock.unlock()
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                connection.send(content: response, completion: .contentProcessed { [weak self] error in
                    if error == nil, let self {
                        self.lock.lock()
                        self.successfulSends += 1
                        self.lock.unlock()
                    }
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        lock.lock()
        stopped = true
        let pending = connections
        connections = []
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}

@MainActor
private final class SaveInkHTTP200MapObserver: NSObject, WKNavigationDelegate {
    var statusCode: Int?
    var finished = false
    var error: Error?
    private(set) var trace: [String] = []
    private let expectedURL: URL?
    private let onFinish: @MainActor (WKWebView, WKNavigation?) -> Void
    init(expectedURL: URL? = nil, onFinish: @escaping @MainActor (WKWebView, WKNavigation?) -> Void) {
        self.expectedURL = expectedURL
        self.onFinish = onFinish
    }
    private func matchesExpected(_ url: URL?) -> Bool {
        guard let expectedURL, let url else { return false }
        return url == expectedURL
    }
    private func location(_ url: URL?) -> String {
        guard let url else { return "nil" }
        // Public loopback fixture only; never retain query values/credentials.
        return "\(url.scheme ?? "nil")://\(url.host ?? "nil"):\(url.port.map(String.init) ?? "default")\(url.path.prefix(100))"
    }
    private func record(_ message: String) {
        if trace.count < 16 { trace.append(String(message.prefix(400))) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let code = (response as? HTTPURLResponse)?.statusCode
        let expected = matchesExpected(response.url)
        record("response class=\(String(reflecting: type(of: response))) status=\(code.map(String.init) ?? "nil") main=\(navigationResponse.isForMainFrame) expected=\(expected) url=\(location(response.url))")
        if navigationResponse.isForMainFrame, expected { statusCode = code }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let expected = matchesExpected(webView.url)
        record("finish expected=\(expected) url=\(location(webView.url))")
        guard expected else { return }
        finished = true
        onFinish(webView, navigation)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        record("provisionalFailure domain=\((error as NSError).domain) code=\((error as NSError).code) url=\(location(webView.url))")
        self.error = error
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record("failure domain=\((error as NSError).domain) code=\((error as NSError).code) url=\(location(webView.url))")
        self.error = error
    }
}

@MainActor
private final class SaveInkSuspendedCountryLookup {
    private var result: CheckedContinuation<String?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async -> String? {
        await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard result == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ country: String?) {
        let continuation = result
        result = nil
        continuation?.resume(returning: country)
    }
}

@MainActor
private final class SaveInkSuspendedRouteLookup {
    private var result: CheckedContinuation<SaveInkMapRoute?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async -> SaveInkMapRoute? {
        await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard result == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ route: SaveInkMapRoute?) {
        let continuation = result
        result = nil
        continuation?.resume(returning: route)
    }
}

@MainActor
private final class SaveInkSuspendedLocator: SaveInkLocating {
    private var result: CheckedContinuation<SaveInkFix, Never>?
    private var requested: CheckedContinuation<Void, Never>?

    func requestFix(for place: SaveInkPlace) async -> SaveInkFix {
        await withCheckedContinuation { continuation in
            result = continuation
            requested?.resume()
            requested = nil
        }
    }

    func waitUntilRequested() async {
        guard result == nil else { return }
        await withCheckedContinuation { requested = $0 }
    }

    func finish(_ fix: SaveInkFix) {
        let continuation = result
        result = nil
        continuation?.resume(returning: fix)
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
    var updated: [Place] = []
    var fetchError: Error?
    var saveError: Error?
    var beforeFetch: (() -> Void)?
    var afterSave: (() -> Void)?

    func fetchPlaces(for userId: String) async throws -> [Place] {
        beforeFetch?()
        if let fetchError { throw fetchError }
        return places
    }

    func savePlace(_ place: Place, userId: String) async throws {
        if let saveError { throw saveError }
        saved.append(place)
        afterSave?()
    }

    func updatePlace(_ place: Place, userId: String) async throws {
        if let saveError { throw saveError }
        updated.append(place)
    }
}
