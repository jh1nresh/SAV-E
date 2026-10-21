import CoreLocation
import SwiftUI
import XCTest
@testable import SAVE

@MainActor
final class SavvyMapPhotoPinsTests: XCTestCase {
    func testQ1HasPhotoFieldsButNoLicensedUserAlbum() {
        let place = samplePlace(
            sourceImageUrl: "https://example.invalid/og.jpg",
            businessPhotoUrls: ["https://maps.googleapis.com/photo/1"],
            note: nil
        )
        XCTAssertFalse(place.businessPhotoURLStrings.isEmpty)
        XCTAssertNil(SavvyMapPhotoPolicy.licensedPhotoURL(for: place))
        XCTAssertTrue(SavvyMapPhotoPolicy.userAlbumPhotoURLs(for: place).isEmpty)
        XCTAssertTrue(SavvyMapPhotoPolicy.usesCoralPinsOnly)
    }

    func testP1PinMetricsStayFixedAndHittable() {
        XCTAssertEqual(SavvyMapPinMetrics.smallPinOuter, 40)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinPaperStroke, 4)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinNoPhotoOuter, 20)
        XCTAssertEqual(SavvyMapPinMetrics.smallPinVisitedOuter, 45)
        XCTAssertEqual(SavvyMapPinMetrics.visitedRing, 2.5)
        XCTAssertGreaterThanOrEqual(SavvyMapPinMetrics.hitTarget, 44)
        XCTAssertEqual(SavvyMapPinMetrics.badgeWidth, 89)
        XCTAssertEqual(SavvyMapPinMetrics.badgeHeight, 104)
        XCTAssertEqual(SavvyMapPinMetrics.badgePhoto, 59)
        XCTAssertEqual(SavvyMapPinMetrics.badgeScaleFromPin, 40 / 89, accuracy: 0.0001)
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
    }

    func testP4CameraPansNorthWithoutChangingLongitude() {
        let pin = CLLocationCoordinate2D(latitude: 39.8822, longitude: 116.4066)
        let center = SavvyMapCameraFocus.center(for: pin, latitudeDelta: 0.02)
        XCTAssertEqual(center.latitude, pin.latitude + 0.225 * 0.02, accuracy: 0.0000001)
        XCTAssertEqual(center.longitude, pin.longitude, accuracy: 0.0000001)
        XCTAssertEqual(SavvyMapPinMetrics.cameraDelay, 0.05, accuracy: 0.0001)
        XCTAssertEqual(SavvyMapPinMetrics.pinScreenYFraction, 0.725, accuracy: 0.0001)
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

    func testP9ReduceMotionIsOnlyAQuarterSecondFade() {
        let reduced = SavvyMapMotion.cardOpen(reduceMotion: true)
        let full = SavvyMapMotion.cardOpen(reduceMotion: false)
        XCTAssertEqual(String(describing: reduced), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertEqual(String(describing: SavvyMapMotion.badge(reduceMotion: true)), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertEqual(String(describing: SavvyMapMotion.camera(reduceMotion: true)), String(describing: SavvyMapMotion.reduceMotion))
        XCTAssertNotEqual(String(describing: reduced), String(describing: full))
    }

    func testP10VoiceOverCopyNamesVisitState() throws {
        let pin = try source(at: "SAV-E/Views/Map/SavvyMapPhotoPins.swift")
        XCTAssertTrue(pin.contains("accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(pin.contains("traditionalChinese: \"去過\""))
        XCTAssertTrue(pin.contains("traditionalChinese: \"沒去過\""))
        XCTAssertTrue(pin.contains("accessibilityAction(.escape"))
        XCTAssertTrue(pin.contains("traditionalChinese: \"看細節\""))
        XCTAssertTrue(pin.contains("map.peek.name"))
    }

    func testP11ThirtyPinsStayIndividualAnnotations() throws {
        let root = try source(at: "SAV-E/Views/Map/SaveMapPhotoPinsRoot.swift")
        XCTAssertTrue(root.contains("ForEach(visiblePlaces.filter(\\ .isMapKitMappable))".replacingOccurrences(of: "\\ ", with: "\\")) || root.contains("isMapKitMappable"))
        XCTAssertTrue(root.contains("Annotation("))
        XCTAssertFalse(root.contains("MKClusterAnnotation"))
        XCTAssertFalse(root.contains("clusteringIdentifier"))
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
        XCTAssertTrue(map.contains("0.05") || map.contains("cameraDelay"))
    }

    private func samplePlace(
        sourceImageUrl: String? = nil,
        businessPhotoUrls: [String]? = nil,
        note: String? = "Bring cash",
        openingHours: String? = "10:00–18:00",
        status: PlaceStatus = .wantToGo
    ) -> Place {
        Place(
            id: UUID(),
            name: "Temple of Heaven",
            address: "Tiantan Rd",
            latitude: 39.8822,
            longitude: 116.4066,
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

