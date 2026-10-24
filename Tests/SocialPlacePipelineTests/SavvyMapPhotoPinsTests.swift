import CoreLocation
import MapKit
import SwiftUI
import XCTest
@testable import SAVE

@MainActor
final class SavvyMapPhotoPinsTests: XCTestCase {
    func testQ1bOwnThenCoralNeverUsesGoogleOrOG() {
        let google = samplePlace(
            sourceImageUrl: "https://example.invalid/og.jpg",
            businessPhotoUrls: ["https://maps.googleapis.com/photo/1"],
            note: nil
        )
        XCTAssertFalse(google.businessPhotoURLStrings.isEmpty)
        XCTAssertTrue(SavvyMapPhotoPolicy.userAlbumPhotoURLs(for: google).isEmpty)
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: google, isConfirmedSaved: true),
            .coral
        )
        XCTAssertNil(SavvyMapPhotoPolicy.licensedPhotoURL(for: google, isConfirmedSaved: true))
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: google, isConfirmedSaved: false),
            .coral
        )

        let ogOnly = samplePlace(sourceImageUrl: "https://example.invalid/og.jpg", note: nil)
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: ogOnly, isConfirmedSaved: true),
            .coral
        )
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: samplePlace(note: nil), isConfirmedSaved: true),
            .coral
        )
    }

    func testP1PinMetricsStayFixedAndHittable() {
        XCTAssertEqual(SavvyMapPinMetrics.smallPinOuter, 40)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinPaperStroke, 4)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinNoPhotoOuter, 20)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinVisitedOuter, 45)
        XCTAssertEqual(SavvyMapPinMetrics.visitedRing, 2.5)
        XCTAssertGreaterThanOrEqual(SavvyMapPinMetrics.hitTarget, 44)
        XCTAssertGreaterThanOrEqual(SavvyMapPinMetrics.badgeWidth, 44)
        XCTAssertGreaterThanOrEqual(SavvyMapPinMetrics.badgeHeight, 44)
        XCTAssertEqual(SavvyMapPinMetrics.badgeWidth, 89)
        XCTAssertEqual(SavvyMapPinMetrics.badgeHeight, 104)
        XCTAssertEqual(SavvyMapPinMetrics.badgePhoto, 59)
        XCTAssertEqual(SavvyMapPinMetrics.badgeScaleFromPin, 40 / 89, accuracy: 0.0001)
        XCTAssertTrue(SavvyMapPinMetrics.badgeBaseIsCircle)
        XCTAssertEqual(SavvyMapPinMetrics.badgeStickerWidth, SavvyMapPinMetrics.badgeStickerHeight)
        XCTAssertEqual(SavvyMapPinMetrics.cardCoralIcon, 64)
        XCTAssertEqual(SavvyMapPinMetrics.badgeArcLabelOffsetY, 18)
        XCTAssertEqual(SavvyMapPinMetrics.badgeWordLabelExtraLift, 8)
    }

    func testP1HostedPinHitFrameIsAtLeastFortyFourPoints() {
        let place = samplePlace()
        for showsBadge in [false, true] {
            let pin = SavvyMapPhotoPinView(
                place: place,
                showsBadge: showsBadge,
                isVisited: false,
                isSelected: false,
                reduceMotion: true,
                onTap: {}
            )
            let size = hostedFittingSize(pin)
            XCTAssertGreaterThanOrEqual(
                size.width,
                44,
                "hosted pin width must be ≥44pt (badge=\(showsBadge), got \(size.width))"
            )
            XCTAssertGreaterThanOrEqual(
                size.height,
                44,
                "hosted pin height must be ≥44pt (badge=\(showsBadge), got \(size.height))"
            )
        }
    }

    func testP2ZoomHysteresisDoesNotFlickerBetweenThresholds() {
        XCTAssertFalse(SavvyMapZoomHysteresis.showsBadge(latitudeDelta: 0.03, currentlyBadge: false))
        XCTAssertTrue(SavvyMapZoomHysteresis.showsBadge(latitudeDelta: 0.015, currentlyBadge: false))
        XCTAssertTrue(SavvyMapZoomHysteresis.showsBadge(latitudeDelta: 0.022, currentlyBadge: true))
        XCTAssertFalse(SavvyMapZoomHysteresis.showsBadge(latitudeDelta: 0.022, currentlyBadge: false))
        XCTAssertFalse(SavvyMapZoomHysteresis.showsBadge(latitudeDelta: 0.026, currentlyBadge: true))
        XCTAssertEqual(SavvyMapZoomHysteresis.staggerDelay(distanceFromCenter: 50), 0.02, accuracy: 0.0001)
        XCTAssertEqual(SavvyMapZoomHysteresis.staggerDelay(distanceFromCenter: 400), 0.12, accuracy: 0.0001)
    }

    func testP2ZoomScanDoesNotFlickerBetweenBand() {
        var badge = false
        var path: [Bool] = []
        var inboundBand: [Bool] = []
        var outboundBand: [Bool] = []

        for milli in stride(from: 300, through: 150, by: -5) {
            let delta = CLLocationDegrees(milli) / 10_000
            badge = SavvyMapZoomHysteresis.showsBadge(latitudeDelta: delta, currentlyBadge: badge)
            path.append(badge)
            if (200...250).contains(milli) { inboundBand.append(badge) }
        }
        XCTAssertTrue(badge)

        for milli in stride(from: 150, through: 300, by: 5) {
            let delta = CLLocationDegrees(milli) / 10_000
            badge = SavvyMapZoomHysteresis.showsBadge(latitudeDelta: delta, currentlyBadge: badge)
            path.append(badge)
            if (200...250).contains(milli) { outboundBand.append(badge) }
        }
        XCTAssertFalse(badge)

        XCTAssertFalse(inboundBand.isEmpty)
        XCTAssertFalse(outboundBand.isEmpty)
        XCTAssertTrue(
            inboundBand.dropLast().allSatisfy { !$0 },
            "0.03→0.015 stays pin through the open band until 0.02"
        )
        XCTAssertTrue(
            outboundBand.allSatisfy { $0 },
            "0.015→0.03 stays badge through 0.02–0.025"
        )
        let flips = zip(path, path.dropFirst()).filter { $0 != $1 }.count
        XCTAssertEqual(flips, 2, "one grow and one shrink; no flicker in the band")
    }

    func testP3CardMetricsAndFrontCopy() {
        XCTAssertEqual(SavvyMapPinMetrics.cardWidth, 332)
        XCTAssertEqual(SavvyMapPinMetrics.cardWidthFraction, 0.845, accuracy: 0.0001)
        XCTAssertEqual(SavvyMapPinMetrics.cardHeight, 400)
        XCTAssertEqual(SavvyMapPinMetrics.cardCorner, 26)
        XCTAssertEqual(SavvyMapPinMetrics.cardPhotoHeight, 236)
        XCTAssertEqual(SavvyMapPinMetrics.cardPhotoCorner, 18)
        XCTAssertEqual(SavvyMapPinMetrics.cardScaleFromBadge, 89 / 332, accuracy: 0.0001)
        XCTAssertEqual(PlaceCategory.attraction.savvyEatGo, .go)
        XCTAssertEqual(PlaceCategory.food.savvyEatGo, .eat)
        XCTAssertEqual(PlaceCategory.cafe.savvyEatGo, .eat)
        XCTAssertEqual(SavvyMapEatGo.go.label(language: .english), "Go")
        XCTAssertEqual(SavvyMapEatGo.eat.label(language: .english), "Eat")
        XCTAssertEqual(SavvyMapEatGo.go.label(language: .traditionalChinese), "去")
        XCTAssertEqual(SavvyMapEatGo.eat.label(language: .traditionalChinese), "吃")
        XCTAssertEqual(
            "\(PlaceCategory.attraction.displayName(language: .traditionalChinese)) · \(SavvyMapEatGo.go.label(language: .traditionalChinese)) · 279m",
            "景點 · 去 · 279m"
        )
    }

    func testP4CameraPansNorthWithoutChangingLongitude() {
        let pin = CLLocationCoordinate2D(latitude: 39.8822, longitude: 116.4066)
        let center = SavvyMapCameraFocus.center(for: pin, latitudeDelta: 0.02)
        XCTAssertEqual(center.latitude, pin.latitude + 0.225 * 0.02, accuracy: 0.0000001)
        XCTAssertEqual(center.longitude, pin.longitude, accuracy: 0.0000001)
        XCTAssertEqual(SavvyMapPinMetrics.cameraDelay, 0.05, accuracy: 0.0001)
        XCTAssertEqual(SavvyMapPinMetrics.pinScreenYFraction, 0.725, accuracy: 0.0001)
        XCTAssertFalse(SavvyMapCameraFocus.usesEqualLatLonSpan)
        XCTAssertEqual(SavvyMapCameraFocus.cameraPitch, 0, accuracy: 0.0001)
        let current = MapCamera(
            centerCoordinate: pin,
            distance: 2_500,
            heading: 12,
            pitch: 18
        )
        let next = SavvyMapCameraFocus.camera(pin: pin, latitudeDelta: 0.02, current: current)
        XCTAssertEqual(next.distance, 2_500, accuracy: 0.001)
        XCTAssertEqual(next.heading, 12, accuracy: 0.001)
        XCTAssertEqual(next.pitch, 0, accuracy: 0.001)
        XCTAssertEqual(next.centerCoordinate.longitude, pin.longitude, accuracy: 0.0000001)
    }

    func testP4CameraFollowsCardByFiftyMilliseconds() throws {
        var scheduledDelay: TimeInterval?
        var moved = false
        let scheduler = SavvyMapScheduler { delay, work in
            scheduledDelay = delay
            work()
        }
        SavvyMapCameraFollow.scheduleOpenMove(
            reduceMotion: false,
            scheduler: scheduler
        ) {
            moved = true
        }
        XCTAssertEqual(scheduledDelay ?? -1, 0.05, accuracy: 0.03)
        XCTAssertTrue(moved)

        var immediate = false
        var delayedWhileReduced = false
        SavvyMapCameraFollow.scheduleOpenMove(
            reduceMotion: true,
            scheduler: SavvyMapScheduler { _, _ in delayedWhileReduced = true }
        ) {
            immediate = true
        }
        XCTAssertTrue(immediate)
        XCTAssertFalse(delayedWhileReduced)

        XCTAssertEqual(SavvyMapCameraFocus.cameraPitch, 0, accuracy: 0.0001)
        let pin = CLLocationCoordinate2D(latitude: 39.8822, longitude: 116.4066)
        let next = SavvyMapCameraFocus.camera(
            pin: pin,
            latitudeDelta: 0.02,
            current: MapCamera(centerCoordinate: pin, distance: 2_500, heading: 12, pitch: 18)
        )
        XCTAssertEqual(next.pitch, 0, accuracy: 0.001)

        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("SavvyMapMotion.cardOpen"))
        XCTAssertTrue(root.contains("moveCamera(to:"))
        XCTAssertTrue(root.contains("SavvyMapCameraFollow.scheduleOpenMove"))
        XCTAssertTrue(
            root.range(of: "session.select(id)")!.lowerBound
                < root.range(of: "moveCamera(to:")!.lowerBound
        )
        XCTAssertTrue(
            root.range(of: "func openCard")!.lowerBound
                < root.range(of: "func moveCamera")!.lowerBound
        )
    }

    func testP5CardBackHidesEmptyAlbumAndHours() {
        let empty = SavvyMapCardBackModel(
            note: nil,
            albumURLs: [],
            visitCount: 0,
            lastVisit: nil,
            address: "Tiantan, Beijing",
            openingHours: "  "
        )
        XCTAssertTrue(empty.showsNotePrompt)
        XCTAssertFalse(empty.showsAlbum)
        XCTAssertFalse(empty.showsHours)
        XCTAssertFalse(empty.hasVisited)
        XCTAssertEqual(empty.albumOverflow, 0)

        let filled = SavvyMapCardBackModel(
            note: "Loved the halls",
            albumURLs: [
                URL(string: "https://example.invalid/1.jpg")!,
                URL(string: "https://example.invalid/2.jpg")!,
                URL(string: "https://example.invalid/3.jpg")!,
                URL(string: "https://example.invalid/4.jpg")!,
            ],
            visitCount: 2,
            lastVisit: Date(timeIntervalSince1970: 1_700_000_000),
            address: "Tiantan, Beijing",
            openingHours: "09:00–17:00"
        )
        XCTAssertFalse(filled.showsNotePrompt)
        XCTAssertTrue(filled.showsAlbum)
        XCTAssertTrue(filled.showsHours)
        XCTAssertEqual(filled.albumOverflow, 1)
        XCTAssertEqual(filled.visibleAlbumURLs.count, 3)
    }

    func testP5BlankCardFlipsToBackThenFront() {
        var session = SavvyMapCardSession()
        session.select(UUID())
        XCTAssertTrue(session.isOpen)
        XCTAssertFalse(session.isFlipped)
        session.toggleFlip()
        XCTAssertTrue(session.isFlipped)
        session.toggleFlip()
        XCTAssertFalse(session.isFlipped)
        XCTAssertTrue(session.isOpen)
    }

    func testP6CollapseFlipsBackBeforeClosingAndIgnoresSmallDrags() {
        var session = SavvyMapCardSession()
        session.select(UUID())
        session.toggleFlip()
        XCTAssertTrue(session.isFlipped)
        XCTAssertEqual(session.requestCollapse(), .flipThenClose)
        XCTAssertTrue(session.isOpen)

        session.applyDrag(30)
        XCTAssertEqual(session.endDrag(), .idle)
        XCTAssertTrue(session.isOpen)

        session.applyDrag(61)
        XCTAssertEqual(session.endDrag(), .flipThenClose)
        session.isFlipped = false
        XCTAssertEqual(session.requestCollapse(), .close)
        session.finishCollapseAfterFlip()
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.placeID)
    }

    func testP6EmptyMapTapCollapsesWithoutMovingCamera() throws {
        var session = SavvyMapCardSession()
        session.select(UUID())
        XCTAssertEqual(session.requestCollapse(), .close)

        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("onTapGesture"))
        XCTAssertTrue(root.contains("collapseSelection(clearPlace: true)"))
        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(
            pins.contains("SavvyMapPinMetrics.collapseDrag"),
            "swipe-down collapse lives on the card, not the map root"
        )
        XCTAssertFalse(SavvyMapCardDrag.shouldCollapse(translationHeight: 12))
        XCTAssertFalse(SavvyMapCardDrag.shouldCollapse(translationHeight: 60))
        XCTAssertTrue(SavvyMapCardDrag.shouldCollapse(translationHeight: 61))
        XCTAssertEqual(SavvyMapCardDrag.minimumDistance, 12)
        let dragRange = try XCTUnwrap(pins.range(of: "DragGesture(minimumDistance: SavvyMapCardDrag.minimumDistance)"))
        let gestureWindow = String(pins[dragRange.lowerBound...].prefix(420))
        XCTAssertTrue(
            gestureWindow.contains("SavvyMapCardDrag.shouldCollapse(translationHeight:"),
            "60pt collapse must live on the DragGesture itself"
        )
        XCTAssertTrue(
            gestureWindow.contains("onCollapse()"),
            "deleting the DragGesture must fail this lock"
        )
        let collapseRange = try XCTUnwrap(root.range(of: "private func collapseSelection"))
        let finishRange = try XCTUnwrap(root.range(of: "private func finishClearingPlace"))
        XCTAssertLessThan(collapseRange.lowerBound, finishRange.lowerBound)
        let collapseBody = String(root[collapseRange.lowerBound..<finishRange.lowerBound])
        XCTAssertFalse(collapseBody.contains("moveCamera"))
        XCTAssertFalse(collapseBody.contains("cameraPosition"))
        XCTAssertFalse(collapseBody.contains("SavvyMapMotion.camera"))
    }

    func testP7BeenHereIncrementsAndSurvivesReread() {
        let suite = "savvy.map.visits.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavvyMapVisitStore(defaults: defaults, key: "test.visits")
        let id = UUID()
        XCTAssertEqual(store.visitCount(for: id, fallbackVisited: false), 0)
        XCTAssertEqual(store.recordVisit(placeID: id, at: Date(timeIntervalSince1970: 10)), 1)
        XCTAssertEqual(store.recordVisit(placeID: id, at: Date(timeIntervalSince1970: 20)), 2)
        let reread = SavvyMapVisitStore(defaults: defaults, key: "test.visits")
        XCTAssertEqual(reread.visitCount(for: id, fallbackVisited: false), 2)
        XCTAssertEqual(reread.lastVisit(for: id, fallback: nil)?.timeIntervalSince1970, 20)
        XCTAssertEqual(reread.visitCount(for: UUID(), fallbackVisited: true), 1)
    }

    func testP7BeenHereUsesVisitedPinStyle() throws {
        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("smallPinVisitedOuter"))
        XCTAssertTrue(pins.contains("SavvyMapPinMetrics.visitedRing"))
        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("place.status == .visited || visits.visitCount"))
        XCTAssertTrue(root.contains("visits.recordVisit(placeID:"))
        XCTAssertTrue(root.contains("updated.status = .visited"))
    }

    func testP8MapMotionTokensAreIsolatedFromThemeSprings() throws {
        XCTAssertEqual(SavvyMapPinMetrics.pinShadowOpacity, 0.45, accuracy: 0.0001)
        XCTAssertEqual(SavvyMapPinMetrics.cardShadowOpacity, 0.35, accuracy: 0.0001)
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        XCTAssertFalse(home.contains("SavvyMapMotion"))
        XCTAssertFalse(home.contains("SavvyMapPinMetrics.cardShadow"))
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        XCTAssertFalse(paywall.contains("SavvyMapMotion"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertFalse(profile.contains("SavvyMapMotion"))
    }

    func testP9ReduceMotionIsOnlyAQuarterSecondFade() throws {
        XCTAssertTrue(SavvyMapMotion.usesQuarterSecondFade(true))
        XCTAssertFalse(SavvyMapMotion.usesQuarterSecondFade(false))
        let reduced = SavvyMapMotion.cardOpen(reduceMotion: true)
        let full = SavvyMapMotion.cardOpen(reduceMotion: false)
        XCTAssertEqual(String(describing: reduced), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertEqual(String(describing: SavvyMapMotion.badge(reduceMotion: true)), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertEqual(String(describing: SavvyMapMotion.camera(reduceMotion: true)), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertNotEqual(String(describing: reduced), String(describing: full))
        XCTAssertEqual(
            String(describing: SavvyMapMotion.reduceMotion),
            String(describing: Animation.easeInOut(duration: 0.25))
        )
        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("reduceMotion ? 1 : (showsBadge ? 1 : SavvyMapPinMetrics.badgeScaleFromPin)"))
        XCTAssertTrue(pins.contains("reduceMotion ? 1 : (isOpen ? 1 : SavvyMapPinMetrics.cardScaleFromBadge)"))
        XCTAssertTrue(pins.contains("reduceMotion ? (isOpen ? 1 : 0)"))
        XCTAssertTrue(pins.contains("if reduceMotion {\n                    if isFlipped"))
        XCTAssertTrue(pins.contains("usesQuarterSecondFade(reduceMotion)"))
        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("SavvyMapCameraFollow.scheduleOpenMove"))
        XCTAssertTrue(root.contains("if reduceMotion"))
    }

    func testP10VoiceOverCopyNamesVisitState() throws {
        let pin = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pin.contains("accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(pin.contains("traditionalChinese: \"去過\""))
        XCTAssertTrue(pin.contains("traditionalChinese: \"沒去過\""))
        XCTAssertTrue(pin.contains("accessibilityAction(.escape"))
        XCTAssertTrue(pin.contains("traditionalChinese: \"看細節\""))
        XCTAssertTrue(pin.contains("map.peek.name"))
        XCTAssertTrue(pin.contains("traditionalChinese: \"我來過了\""))
        XCTAssertTrue(
            pin.contains("accessibilityIdentifier(\"map.card.beenHere\")"),
            "HoP: 我來過了 on the map place card must use map.card.beenHere"
        )
        XCTAssertTrue(
            pin.range(of: "traditionalChinese: \"我來過了\"")!.lowerBound
                < pin.range(of: "accessibilityIdentifier(\"map.card.beenHere\")")!.lowerBound
        )
        XCTAssertTrue(pin.contains("SavvyMapCardCopy.pinAccessibilityLabel"))
        XCTAssertTrue(pin.contains("accessibilityFocused($nameFocused)"))
        XCTAssertTrue(pin.contains("nameFocused = true"))
        XCTAssertTrue(pin.contains("english: \"See details\""))
        XCTAssertEqual(
            SavvyMapCardCopy.pinAccessibilityLabel(
                name: "Temple of Heaven",
                category: "Attraction",
                visit: "not visited",
                language: .english
            ),
            "Temple of Heaven, Attraction, not visited"
        )
        XCTAssertEqual(
            SavvyMapCardCopy.pinAccessibilityLabel(
                name: "天壇",
                category: "景點",
                visit: "沒去過",
                language: .traditionalChinese
            ),
            "天壇、景點、沒去過"
        )
        XCTAssertEqual(
            SavvyMapCardCopy.pinAccessibilityLabel(
                name: "天壇",
                category: "景點",
                visit: "去過",
                language: .traditionalChinese
            ),
            "天壇、景點、去過"
        )
    }

    func testZhHantCardCopyUsesDesignWordsAndKeepsEnglish() throws {
        XCTAssertEqual(SavvyMapCardCopy.directionsTitle(language: .english), "Directions")
        XCTAssertEqual(SavvyMapCardCopy.directionsTitle(language: .traditionalChinese), "怎麼去")
        XCTAssertEqual(
            SavvyMapCardCopy.pinAccessibilityLabel(
                name: "Temple of Heaven",
                category: "Attraction",
                visit: "not visited",
                language: .english
            ),
            "Temple of Heaven, Attraction, not visited"
        )
        XCTAssertEqual(
            SavvyMapCardCopy.pinAccessibilityLabel(
                name: "天壇",
                category: "景點",
                visit: "沒去過",
                language: .traditionalChinese
            ),
            "天壇、景點、沒去過"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))
        )
        let englishDate = SavvyMapCardCopy.visitDateText(date, language: .english)
        let chineseDate = SavvyMapCardCopy.visitDateText(date, language: .traditionalChinese)
        XCTAssertTrue(englishDate.contains("Oct"))
        XCTAssertFalse(chineseDate.contains("Oct"))
        XCTAssertFalse(chineseDate.contains("October"))
        XCTAssertTrue(chineseDate.contains("10") && chineseDate.contains("24"))

        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("SavvyMapCardCopy.directionsTitle"))
        XCTAssertFalse(pins.contains("Text(\"Directions\")"))
        XCTAssertTrue(pins.contains("traditionalChinese: \"怎麼去\""))
        XCTAssertTrue(pins.contains("traditionalChinese: \"吃\""))
        XCTAssertTrue(pins.contains("traditionalChinese: \"去\""))
        XCTAssertTrue(pins.contains("traditionalChinese: \"我來過了\""))
        XCTAssertFalse(pins.contains("SaveDoodleLens"))
        XCTAssertEqual(pins.components(separatedBy: "SavvyMapCardCopy.directionsTitle").count - 1, 2)

        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("SavvyMapDirectionsLaunch.open"))
        XCTAssertFalse(root.contains("UIApplication.shared.open(url)"))
    }

    func testP11ThirtyPinsStayIndividualAnnotations() throws {
        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("ForEach(savvyPinPlaces)"))
        XCTAssertTrue(root.contains("Annotation("))
        XCTAssertFalse(root.contains("MKClusterAnnotation"))
        XCTAssertFalse(root.contains("clusteringIdentifier"))
    }

    func testP11HitchOrScrollDecelerationMetricProbe() throws {
        var notes: [String] = []
        if #available(iOS 26.0, *) {
            let hitchType = NSClassFromString("XCTHitchMetric")
            notes.append(
                hitchType == nil
                    ? "iOS 26+ but XCTHitchMetric class was not found"
                    : "XCTHitchMetric is present; init(application:) needs XCUIApplication (UI test)"
            )
        } else {
            notes.append("XCTHitchMetric requires iOS 26+; this process is below that.")
        }

        let scrollMetricExists: Bool
        if #available(iOS 12.2, *) {
            _ = XCTOSSignpostMetric.scrollDecelerationMetric
            scrollMetricExists = true
            notes.append("XCTOSSignpostMetric.scrollDecelerationMetric is present")
        } else {
            scrollMetricExists = false
            notes.append("XCTOSSignpostMetric.scrollDecelerationMetric requires iOS 12.2+")
        }

        let reason = """
        模擬器無法判定：SAVETests cannot scroll 30 live Map annotations. \
        \(notes.joined(separator: ". ")). \
        XCTHitchMetric(application:) is a UI-test API. \
        No hitch / 60fps number is recorded. This is not a P11 pass. \
        HoP 2026-10-24: gate5-motion-60fps.mp4 is not P11 evidence. \
        scrollDecelerationMetricPresent=\(scrollMetricExists)
        """
        let attachment = XCTAttachment(string: reason)
        attachment.name = "p11-hitch-unmeasurable"
        attachment.lifetime = .keepAlways
        add(attachment)
        throw XCTSkip(reason)
    }

    func testDirectionsLaunchUsesDefaultModeAndFallsBackWithoutCoordinates() throws {
        let mapped = SavvyMapDirectionsLaunch.plan(for: samplePlace())
        XCTAssertEqual(mapped.kind, .directions)
        XCTAssertEqual(
            mapped.launchOptions[MKLaunchOptionsDirectionsModeKey],
            MKLaunchOptionsDirectionsModeDefault
        )

        var openedName: String?
        var openedOptions: [String: Any] = [:]
        var openedURL: URL?
        SavvyMapDirectionsLaunch.open(
            samplePlace(),
            openMapItem: { item, options in
                openedName = item.name
                openedOptions = options
            },
            openURL: { openedURL = $0 }
        )
        XCTAssertEqual(openedName, "Temple of Heaven")
        XCTAssertEqual(
            openedOptions[MKLaunchOptionsDirectionsModeKey] as? String,
            MKLaunchOptionsDirectionsModeDefault
        )
        XCTAssertNil(openedURL)

        let nowhere = samplePlace(latitude: 0, longitude: 0)
        XCTAssertFalse(nowhere.hasValidCoordinate)
        XCTAssertNil(nowhere.appleMapsURL)
        let fallback = SavvyMapDirectionsLaunch.plan(for: nowhere)
        XCTAssertEqual(fallback.kind, .placePage)
        XCTAssertTrue(fallback.launchOptions.isEmpty)

        openedName = nil
        openedURL = nil
        SavvyMapDirectionsLaunch.open(
            nowhere,
            openMapItem: { _, _ in openedName = "item" },
            openURL: { openedURL = $0 }
        )
        XCTAssertNil(openedName)
        let url = try XCTUnwrap(openedURL)
        XCTAssertTrue(url.absoluteString.contains("maps.apple.com"))
        XCTAssertTrue(url.absoluteString.contains("q=Temple"))
        XCTAssertFalse(url.absoluteString.contains("ll="))

        XCTAssertEqual(SavvyMapCardCopy.directionsTitle(language: .traditionalChinese), "怎麼去")
        XCTAssertEqual(SavvyMapCardCopy.directionsTitle(language: .english), "Directions")
    }

    func testP12SpringValuesMatchSpecSection6() throws {
        let source = try self.source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(source.contains("response: 0.46, dampingFraction: 0.61"))
        XCTAssertTrue(source.contains("response: 0.46, dampingFraction: 0.74"))
        XCTAssertTrue(source.contains("response: 0.51, dampingFraction: 0.86"))
        XCTAssertTrue(source.contains("response: 0.54, dampingFraction: 1.0"))
        XCTAssertTrue(source.contains("response: 0.57, dampingFraction: 0.76"))
        XCTAssertTrue(source.contains("response: 1.05, dampingFraction: 0.76"))
        XCTAssertTrue(source.contains("easeInOut(duration: 0.25)"))
        XCTAssertTrue(source.contains("5_000_000_000"))
        XCTAssertTrue(source.contains("showsBadge = true"))
        XCTAssertTrue(
            source.range(of: "5_000_000_000")!.lowerBound
                < source.range(of: "showsBadge = true")!.lowerBound
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.badge),
            String(describing: Animation.spring(response: 0.46, dampingFraction: 0.61))
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.cardOpen),
            String(describing: Animation.spring(response: 0.46, dampingFraction: 0.74))
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.cardClose),
            String(describing: Animation.spring(response: 0.51, dampingFraction: 0.86))
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.flipBack),
            String(describing: Animation.spring(response: 0.54, dampingFraction: 1.0))
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.flipFront),
            String(describing: Animation.spring(response: 0.57, dampingFraction: 0.76))
        )
        XCTAssertEqual(
            String(describing: SavvyMapMotion.camera),
            String(describing: Animation.spring(response: 1.05, dampingFraction: 0.76))
        )
    }

    func testP13HomeCapAndUnplacedStayOutOfThisDiff() throws {
        let home = try source(at: "SAV-E/Views/TileTown/SaveTileTownHomeView.swift")
        XCTAssertTrue(home.contains("home.savedPlaces"))
        XCTAssertTrue(home.contains("SaveTileTownCanvas"))
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("SaveTileTownHomeView()"))
        XCTAssertTrue(root.contains("SaveMapPhotoPinsRoot("))
        XCTAssertFalse(root.contains("SaveAtlasInteractiveRootMap("))

        let map = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertFalse(map.contains("maxFree"))
        XCTAssertFalse(map.contains("Unplaced"))
        XCTAssertFalse(map.contains("freeSaved"))

        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertFalse(pins.contains("maxFree"))
        XCTAssertFalse(pins.contains("Unplaced"))

        let mask = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(mask.contains("atlas-map"))
    }

    func testP14OnlyConfirmedSavedPlacesGetSavvyPins() throws {
        let saved = samplePlace(status: .wantToGo)
        let visited = samplePlace(
            name: "Summer Palace",
            latitude: 39.9997,
            longitude: 116.2755,
            status: .visited
        )
        let unsavedSocial = samplePlace(
            name: "Friend Cafe",
            latitude: 40.012,
            longitude: 116.401,
            sourceImageUrl: "https://example.invalid/friend.jpg",
            businessPhotoUrls: ["https://maps.googleapis.com/photo/unsaved"]
        )
        XCTAssertEqual(
            SavvyMapStampPolicy.pinKind(isConfirmedSaved: true, hasPhotoURL: false),
            .savvyPin
        )
        XCTAssertEqual(
            SavvyMapStampPolicy.pinKind(isConfirmedSaved: true, hasPhotoURL: true),
            .savvyPin
        )
        XCTAssertEqual(
            SavvyMapStampPolicy.pinKind(isConfirmedSaved: false, hasPhotoURL: true),
            .nativeApplePOI
        )
        XCTAssertTrue(SavvyMapStampPolicy.qualifiesForSavvyPin(saved, confirmedPlaces: [saved, visited]))
        XCTAssertTrue(SavvyMapStampPolicy.qualifiesForSavvyPin(visited, confirmedPlaces: [saved, visited]))
        XCTAssertFalse(
            SavvyMapStampPolicy.qualifiesForSavvyPin(unsavedSocial, confirmedPlaces: [saved, visited])
        )

        let friendMatch = Place(
            id: UUID(),
            name: saved.name,
            address: saved.address,
            latitude: saved.latitude,
            longitude: saved.longitude,
            googlePlaceId: saved.googlePlaceId,
            category: saved.category,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: "https://example.invalid/og.jpg",
            businessPhotoUrls: ["https://example.invalid/biz.jpg"],
            extractedDishes: nil,
            priceRange: nil,
            recommender: "Ada",
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
        let friends = SavvyMapStampPolicy.friendLensPins(
            confirmedPlaces: [saved, visited],
            socialPlaces: [friendMatch, unsavedSocial]
        )
        XCTAssertEqual(friends.map(\.id), [saved.id])

        let afterSave = SavvyMapStampPolicy.includingSelectedSavedPin(
            [],
            selected: saved,
            confirmedPlaces: [saved]
        )
        XCTAssertEqual(afterSave.map(\.id), [saved.id])

        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("savvyPinPlaces"))
        XCTAssertTrue(root.contains("SavvyMapStampPolicy.friendLensPins"))
        XCTAssertTrue(root.contains("selectMapFeature"))
        XCTAssertTrue(root.contains("pointsOfInterest: .all"))
        XCTAssertFalse(root.contains("UnsavedMapCandidatePin"))
        XCTAssertFalse(root.contains("SocialPlaceMapPin"))
        XCTAssertFalse(root.contains("ReviewCandidateMapPin"))
        XCTAssertTrue(root.contains("visibleSocialPlaces"))
        XCTAssertFalse(root.contains("return social.isEmpty ? mapViewModel.socialPlaces : social"))
    }

    func testP15LoadFailureStaysCoralWithoutBrokenImage() throws {
        XCTAssertEqual(SavvyMapPhotoDisplay.surface(for: .loaded), .photo)
        XCTAssertEqual(SavvyMapPhotoDisplay.surface(for: .failed), .coral)
        XCTAssertEqual(SavvyMapPhotoDisplay.surface(for: .loading), .coral)
        XCTAssertEqual(SavvyMapPhotoDisplay.surface(for: .missing), .coral)
        XCTAssertTrue(SavvyMapPhotoDisplay.hidesBrokenImageOnFailure)

        let own = SavvyMapResolvedPhoto(
            origin: .own,
            url: URL(string: "https://example.invalid/me.jpg"),
            shared: nil
        )
        XCTAssertEqual(own.origin, .own)
        XCTAssertEqual(SavvyMapPhotoDisplay.surface(for: .failed), .coral)

        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("CachedAsyncImage"))
        XCTAssertTrue(pins.contains("SavvyMapPinPhotoFill"))
        XCTAssertTrue(pins.contains("firstOwnSharedPhoto"))
        XCTAssertTrue(pins.contains("firstFriendSharedPhoto"))
        XCTAssertFalse(pins.contains("xmark"))
        XCTAssertFalse(pins.contains("PlaceBusinessEnricher"))
        XCTAssertFalse(pins.contains("Photos: Google"))

        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertFalse(root.contains("Photos: Google"))
        XCTAssertFalse(root.contains("map.photoAttribution"))
        XCTAssertFalse(root.contains("PlaceBusinessEnricher"))
        XCTAssertFalse(root.contains("businessPhotoUrls"))
    }

    func testP16OwnThenFriendThenCoralWithBothSourcesStubbed() {
        XCTAssertEqual(SavvyMapOwnPhotoSource.endpointPath, "/v0/shared-posts/{id}/photos/{n}")
        XCTAssertEqual(SavvyMapOwnPhotoSource.thumbnailCacheTTL, 3600, accuracy: 0.001)
        XCTAssertFalse(SavvyMapOwnPhotoSource.readsSourceImageURL)
        XCTAssertFalse(SavvyMapOwnPhotoSource.readsBusinessPhotoURLs)
        XCTAssertTrue(SavvyMapOwnPhotoSource.missingPlaceBindFields.contains("SharedPlacePost.place_id"))
        let stored = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(SavvyMapOwnPhotoSource.isThumbnailFresh(storedAt: stored, now: stored.addingTimeInterval(3599)))
        XCTAssertFalse(SavvyMapOwnPhotoSource.isThumbnailFresh(storedAt: stored, now: stored.addingTimeInterval(3601)))

        let saved = samplePlace()
        let own = sampleSharedPost(name: saved.name, address: saved.address, photoCount: 1)
        let friend = sampleSharedPost(name: saved.name, address: saved.address, photoCount: 2)
        XCTAssertFalse(SavvyMapOwnPhotoSource.canBindToSavedPlace(own))
        XCTAssertNil(SavvyMapPhotoPolicy.firstOwnSharedPhoto(in: [own], matching: saved))
        XCTAssertNil(SavvyMapPhotoPolicy.firstFriendSharedPhoto(in: [friend], matching: saved))
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(
                for: saved,
                isConfirmedSaved: true,
                ownPosts: [own],
                friendPosts: [friend]
            ),
            .coral
        )

        let googleOnly = samplePlace(
            sourceImageUrl: "https://example.invalid/og.jpg",
            businessPhotoUrls: ["https://maps.googleapis.com/photo/1"]
        )
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: googleOnly, isConfirmedSaved: true),
            .coral
        )
        XCTAssertTrue(SavvyMapPhotoPolicy.userAlbumPhotoURLs(for: googleOnly).isEmpty)
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: saved, isConfirmedSaved: false, ownPosts: [own]),
            .coral
        )
    }

    func testGate5PreviewCatalogCoversPhotoAndCoralStates() throws {
        XCTAssertEqual(
            SavvyMapPhotoPinPreviewState.allCases.map(\.rawValue),
            [
                "photoRoundPin",
                "photoVisitedRing",
                "photoBadge",
                "photoCardHero",
                "coralRoundPin",
                "coralVisitedRing",
                "coralBadge",
                "coralCardHero",
            ]
        )
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.photoRoundPin.usesFixturePhoto)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.photoVisitedRing.isVisited)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.photoBadge.showsBadge)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.photoCardHero.showsCard)
        XCTAssertFalse(SavvyMapPhotoPinPreviewState.coralRoundPin.usesFixturePhoto)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.coralVisitedRing.isVisited)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.coralBadge.showsBadge)
        XCTAssertTrue(SavvyMapPhotoPinPreviewState.coralCardHero.showsCard)

        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("SavvyMapPhotoPinPreviewCatalog"))
        XCTAssertTrue(pins.contains("savvyMapPreviewPhoto"))
        XCTAssertTrue(pins.contains("DEBUG FIXTURE"))
        XCTAssertTrue(pins.contains("#if DEBUG"))
        XCTAssertFalse(pins.contains("PlaceBusinessEnricher"))
        XCTAssertEqual(
            SavvyMapPhotoPolicy.resolvedPhoto(for: samplePlace(), isConfirmedSaved: true),
            .coral
        )
        XCTAssertEqual(
            PlaceCategory.attraction.displayName(language: .traditionalChinese),
            "景點"
        )
    }

    func testP0NoPhotoCardUsesFullCoralAndCreamIcon() throws {
        let pins = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pins.contains("cardCoralIcon"))
        XCTAssertTrue(pins.contains("place.category.iconName"))
        XCTAssertTrue(pins.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(pins.contains("SaveTheme.Colors.cream"))
        XCTAssertTrue(pins.contains("SaveAtlasPalette.paper"))
        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains(".camera(next)"))
        XCTAssertTrue(root.contains("pitch: 0"))
        XCTAssertFalse(root.contains("longitudeDelta: delta"))
        XCTAssertTrue(pins.contains("Circle()"))
        XCTAssertTrue(pins.contains("badgeBaseIsCircle"))
        XCTAssertTrue(pins.contains("usesArc"))
        XCTAssertTrue(pins.contains("languageSettings.language != .traditionalChinese"))
        XCTAssertTrue(pins.contains("snapshotLayout"))
        XCTAssertTrue(pins.contains("overrideUserInterfaceStyle"))
        XCTAssertTrue(pins.contains("SavvyMapPinMetrics.cardPhotoInset - 6"))
        XCTAssertFalse(pins.contains(".offset(y: -14)"))
        XCTAssertTrue(pins.contains("Color.black.opacity(0.55)"))
        XCTAssertFalse(pins.contains("SaveAtlasPalette.ink.opacity(0.55)"))
        XCTAssertTrue(pins.contains(".frame(height: SavvyMapPinMetrics.cardPhotoHeight)"))
        XCTAssertTrue(pins.contains(".clipped()"))
        XCTAssertFalse(
            pins.contains(".rotationEffect(.degrees(angle))\n                    .offset(y: -radius)"),
            "Arc letters must not rotate before the radius offset"
        )
        XCTAssertTrue(pins.contains(".offset(y: -radius)\n                    .rotationEffect(.degrees(angle))"))
        XCTAssertTrue(pins.contains("badgeWordLabelExtraLift"))
        XCTAssertTrue(pins.contains("badgeArcLabelOffsetY"))
        XCTAssertEqual(SavvyMapArcText.spreadDegrees(characterCount: 10), 150)
        XCTAssertGreaterThan(SavvyMapArcText.maxSpreadDegrees, 110)
        XCTAssertGreaterThan(SavvyMapArcText.degreesPerCharacter, 16)
    }

    func testGate5ImageRendererExportWritesLightDarkAndChinese() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-gate5-\(UUID().uuidString)", isDirectory: true)
        let urls = try SavvyMapPhotoPinSnapshotExport.writeAll(to: directory)
        XCTAssertGreaterThanOrEqual(urls.count, 20)
        let names = Set(urls.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("light-photoRoundPin.png"))
        XCTAssertTrue(names.contains("dark-coralCardHero.png"))
        XCTAssertTrue(names.contains("catalog-light.png"))
        XCTAssertTrue(names.contains("catalog-dark.png"))
        XCTAssertTrue(names.contains("zh-Hant-photoBadge.png"))
        XCTAssertTrue(names.contains("zh-Hant-coralCardHero.png"))
        XCTAssertTrue(names.contains("zh-Hant-coralCardBack.png"))
        XCTAssertTrue(names.contains("zh-Hant-coralCardVisitedBack.png"))
        XCTAssertTrue(names.contains("dark-coralCardBack.png"))
        XCTAssertTrue(names.contains("zh-Hant-foodCardHero.png"))
        XCTAssertTrue(names.contains("p14-saved-unsaved-visited.png"))
        XCTAssertTrue(names.contains("light-coralCardBack.png"))
        let lightCard = try Data(contentsOf: directory.appendingPathComponent("light-coralCardHero.png"))
        let darkCard = try Data(contentsOf: directory.appendingPathComponent("dark-coralCardHero.png"))
        XCTAssertNotEqual(
            lightCard,
            darkCard,
            "dark coral card must use charcoal paper, not a second light render"
        )
        XCTAssertGreaterThan(
            try Data(contentsOf: directory.appendingPathComponent("catalog-light.png")).count,
            200_000,
            "catalog-light.png must be a painted grid, not a blank paper page"
        )
        XCTAssertGreaterThan(
            try Data(contentsOf: directory.appendingPathComponent("catalog-dark.png")).count,
            200_000,
            "catalog-dark.png must be a painted grid, not a blank paper page"
        )
        for url in urls {
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 800, url.lastPathComponent)
            let attachment = XCTAttachment(contentsOfFile: url)
            attachment.name = url.lastPathComponent
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if let dest = ProcessInfo.processInfo.environment["SAVE_GATE5_EVIDENCE_DIR"] {
            let destURL = URL(fileURLWithPath: dest, isDirectory: true)
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
            for url in urls {
                let target = destURL.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
    }

    func testCardBackUsesDecision2FieldsFromPlace() {
        let place = samplePlace(
            note: "Bring cash",
            openingHours: "10:00–18:00",
            status: .visited
        )
        let defaults = UserDefaults(suiteName: "savvy.map.visits.model.\(UUID().uuidString)")!
        let store = SavvyMapVisitStore(defaults: defaults, key: "model")
        let model = SavvyMapCardBackModel.make(place: place, visits: store)
        XCTAssertEqual(model.note, "Bring cash")
        XCTAssertTrue(model.showsHours)
        XCTAssertTrue(model.hasVisited)
        XCTAssertTrue(model.albumURLs.isEmpty)
        XCTAssertEqual(model.address, "Tiantan Rd")
    }

    func testProductMapUsesAppleMapsNotTileTownCanvas() throws {
        let map = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(map.contains(".standard("))
        XCTAssertTrue(map.contains("pointsOfInterest: .all"))
        XCTAssertFalse(map.contains("SaveTileTownCanvas"))
        XCTAssertTrue(map.contains("SavvyMapMotion.camera"))
        XCTAssertTrue(map.contains("SavvyMapCameraFollow.scheduleOpenMove"))
    }

    private func sampleSharedPost(
        name: String,
        address: String,
        photoCount: Int
    ) -> SharedPlacePost {
        SharedPlacePost(
            id: UUID(),
            name: name,
            address: address,
            category: PlaceCategory.attraction.rawValue,
            status: .wantToGo,
            stars: nil,
            caption: nil,
            shared_at: "2026-10-21T00:00:00Z",
            author_id: "self",
            author_name: "Self",
            author_handle: "self",
            author_avatar_url: nil,
            visible_to_followers: true,
            photo_count: photoCount,
            photo_version: "1"
        )
    }

    private func samplePlace(
        name: String = "Temple of Heaven",
        latitude: Double = 39.8822,
        longitude: Double = 116.4066,
        sourceImageUrl: String? = nil,
        businessPhotoUrls: [String]? = nil,
        note: String? = "Bring cash",
        openingHours: String? = "10:00–18:00",
        status: PlaceStatus = .wantToGo
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Tiantan Rd",
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: .attraction,
            status: status,
            rating: nil,
            note: note,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: sourceImageUrl,
            businessPhotoUrls: businessPhotoUrls,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: openingHours,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func hostedFittingSize<V: View>(_ view: V) -> CGSize {
        let host = UIHostingController(rootView: view.fixedSize())
        let size = CGSize(width: 390, height: 400)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        let fitted = host.sizeThatFits(in: size)
        window.isHidden = true
        return fitted
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

