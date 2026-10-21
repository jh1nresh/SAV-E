import CoreLocation
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
        XCTAssertTrue(root.contains("ForEach(savvyPinPlaces)"))
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

    func testP14OnlyConfirmedSavedPlacesGetSavvyPins() throws {
        let saved = samplePlace(status: .wantToGo)
        let visited = samplePlace(status: .visited)
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

