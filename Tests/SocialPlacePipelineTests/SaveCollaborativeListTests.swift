import CoreLocation
import SwiftUI
import UIKit
import XCTest
@testable import SAVE

final class SaveCollaborativeListTests: XCTestCase {
    @MainActor
    func testSharedListLinkRoundTripsViewerRole() throws {
        var list = SaveCollaborativeList(title: "Tokyo cafes", note: "For Saturday")
        list.add(.from(place: place(name: "Onibus Coffee", category: .cafe)))

        let url = try XCTUnwrap(list.shareURL(role: .viewer))
        let payload = try XCTUnwrap(SaveSharedListPayload.from(url: url))

        XCTAssertEqual(payload.role, .viewer)
        XCTAssertEqual(payload.list.viewerRole, .viewer)
        XCTAssertEqual(payload.list.title, "Tokyo cafes")
        XCTAssertEqual(payload.list.items.first?.title, "Onibus Coffee")
    }

    @MainActor
    func testListAcceptsSavedPlaceAndUnsavedMapCandidateSnapshots() {
        var list = SaveCollaborativeList(title: "OC weekend")
        let saved = place(name: "Maru Coffee", category: .cafe)
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.6,
            reviewCount: 120,
            sourceURL: "https://maps.apple.com/?q=Bright%20Coffee",
            photoURL: "https://example.com/bright.jpg",
            businessPhotoURLs: ["https://example.com/bright-2.jpg"],
            evidence: ["Apple Maps result"]
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: candidate))

        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items.map(\.source), [.savedPlace, .mapCandidate])
        XCTAssertEqual(list.items.last?.photoURLs, ["https://example.com/bright.jpg", "https://example.com/bright-2.jpg"])
    }

    @MainActor
    func testViewerJoinedListCannotAddItems() {
        var list = SaveCollaborativeList(title: "Viewer list", viewerRole: .viewer)
        list.add(.from(place: place(name: "Viewer Coffee", category: .cafe)))

        XCTAssertTrue(list.items.isEmpty)
        XCTAssertFalse(list.canEdit)
    }

    @MainActor
    func testEditorJoinedListCanAddItems() {
        var list = SaveCollaborativeList(title: "Editor list", viewerRole: .editor)
        list.add(.from(place: place(name: "Editor Coffee", category: .cafe)))

        XCTAssertEqual(list.items.count, 1)
        XCTAssertTrue(list.canEdit)
    }

    @MainActor
    func testFriendCanSaveListItemIntoOwnSave() {
        let candidate = SaveMapCandidate(
            title: "List Ramen",
            subtitle: "Los Angeles, CA",
            latitude: 34.0522,
            longitude: -118.2437,
            category: .food,
            rating: 4.7,
            sourceURL: "https://maps.apple.com/?q=List%20Ramen",
            evidence: ["Apple Maps result"]
        )
        let item = SaveListItem.from(candidate: candidate, addedByDisplayName: "Ezven")
        let saved = item.asPlace()

        XCTAssertEqual(saved.name, "List Ramen")
        XCTAssertEqual(saved.category, .food)
        XCTAssertEqual(saved.googleRating, 4.7)
        XCTAssertEqual(saved.recommender, "Ezven")
        XCTAssertEqual(saved.sourceUrl, "https://maps.apple.com/?q=List%20Ramen")
    }

    @MainActor
    func testListItineraryKeepsUnsavedItemsSeparateFromPlaceIds() {
        var list = SaveCollaborativeList(title: "Mixed plan")
        let saved = place(name: "Saved Cafe", category: .cafe)
        let unsaved = SaveMapCandidate(
            title: "Unsaved Sushi",
            subtitle: "Costa Mesa, CA",
            latitude: 33.6638,
            longitude: -117.9047,
            category: .food
        )

        list.add(.from(place: saved))
        list.add(.from(candidate: unsaved))
        let response = list.itineraryResponse()

        XCTAssertEqual(response.componentType, .tripItinerary)
        XCTAssertEqual(response.placeIds, [saved.id.uuidString])
        XCTAssertEqual(response.itineraryDays.first?.stops.count, 2)
        XCTAssertTrue(response.itineraryDays.first?.stops.last?.note?.contains("Map result") == true)
    }

    @MainActor
    func testRemoteBusinessPhotoColumnIsNeverImported() {
        XCTAssertNil(PlaceBusinessPhotoPersistence.importedRemoteURLs([
            "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref",
            "https://example.com/own.jpg",
        ]))
        XCTAssertNil(PlaceBusinessPhotoPersistence.importedRemoteURLs(nil))
    }

    @MainActor
    func testHomeThumbnailMarksGooglePhotosWithGoogleMapsText() throws {
        let google = try XCTUnwrap(URL(
            string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref"
        ))
        let placesMedia = try XCTUnwrap(URL(
            string: "https://places.googleapis.com/v1/places/ChIJ123/photos/ABC/media"
        ))
        let own = try XCTUnwrap(URL(string: "https://example.com/own.jpg"))
        let friend = try XCTUnwrap(URL(string: "https://cdn.instagram.com/private-post.jpg"))

        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.homeLines, ["Google", "Maps"])
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.homeMinPointSize, 10)
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.homeGapAbove, 2)
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.homeReservedHeight, 24)
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.homePointSize(for: .large), 10)
        XCTAssertGreaterThanOrEqual(
            GooglePlacesPhotoSourceMarkMetrics.homePointSize(for: .xxxLarge),
            10
        )
        XCTAssertGreaterThanOrEqual(GooglePlacesPhotoSourceMarkMetrics.homeMarkHeight(for: .large), 24)
        XCTAssertTrue(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(google))
        XCTAssertTrue(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(placesMedia))
        XCTAssertFalse(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(own))
        XCTAssertFalse(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(friend))
        XCTAssertFalse(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(nil))
        XCTAssertEqual(
            GooglePlacesPhotoSourceMarkMetrics.voiceOverLabel(language: .english),
            "Photo: Google Maps"
        )
        XCTAssertEqual(
            GooglePlacesPhotoSourceMarkMetrics.voiceOverLabel(language: .traditionalChinese),
            "照片來源：Google Maps"
        )
        XCTAssertGreaterThanOrEqual(GooglePlacesPhotoSourceMarkMetrics.lightContrastRatio(), 4.5)
        XCTAssertGreaterThanOrEqual(GooglePlacesPhotoSourceMarkMetrics.darkContrastRatio(), 4.5)

        let mark = try source(at: "SAV-E/Views/Components/GooglePlacesPhotoSourceMark.swift")
        XCTAssertTrue(mark.contains("case homeStacked"))
        XCTAssertTrue(mark.contains("weight: .semibold"))
        XCTAssertTrue(mark.contains("homeMinPointSize: CGFloat = 10"))
        XCTAssertTrue(mark.contains("homeGapAbove: CGFloat = 2"))
        XCTAssertTrue(mark.contains("minimumScaleFactor(1.0)"))
        XCTAssertFalse(mark.contains("minimumScaleFactor(0."))
        XCTAssertTrue(mark.contains("Color(hex: \"1F1F1F\")"))
        XCTAssertTrue(mark.contains("Color.white"))
        XCTAssertFalse(mark.contains("5E5E5E"))
        XCTAssertFalse(mark.contains("accessibilityHidden(true)"))
        XCTAssertFalse(mark.contains(".font(.system(size: 6, weight: .semibold))"))

        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertTrue(stamp.contains("GooglePlacesPhotoSourceMark(style: .homeStacked)"))
        XCTAssertTrue(stamp.contains("homeGapAbove"))
        XCTAssertFalse(stamp.contains("GoogleMapsAttributionLogo"))
        XCTAssertFalse(stamp.contains(".font(.system(size: 6, weight: .semibold))"))

        let peek = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(peek.contains("GooglePlacesPhotoSourceMark(style: .homeStacked)"))
        XCTAssertTrue(peek.contains("homeGapAbove"))
        XCTAssertFalse(peek.contains("ZStack(alignment: .bottom"))
    }

    @MainActor
    func testGooglePhotoSourceMarkLayoutRulesAndFallback() throws {
        let google = try XCTUnwrap(URL(
            string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref"
        ))
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.text, "Google Maps")
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.minPointSize, 12)
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.maxPointSize, 16)
        XCTAssertEqual(GooglePlacesPhotoSourceMarkMetrics.pointSize(for: .large), 12)
        XCTAssertLessThanOrEqual(GooglePlacesPhotoSourceMarkMetrics.pointSize(for: .xxxLarge), 16)
        XCTAssertFalse(
            GooglePlacesPhotoSourceMarkMetrics.canShowGooglePhoto(in: 40, dynamicType: .large),
            "Footer cards that cannot fit a single line must not squeeze the mark"
        )
        XCTAssertFalse(
            GooglePlacesPhotoSourceMarkMetrics.displaysGooglePhoto(google, availableWidth: 40, dynamicType: .large)
        )

        let drawer = try source(at: "SAV-E/Views/Drawer/Components/SaveSearchResultsComponent.swift")
        XCTAssertTrue(drawer.contains("GooglePlacesPhotoSourceMark()"))

        let trip = try source(at: "SAV-E/Views/Trips/TripPackViews.swift")
        XCTAssertTrue(trip.contains("GooglePlacesPhotoSourceMark()"))

        let origin = try source(at: "SAV-E/Views/Origin/SaveOriginView.swift")
        XCTAssertTrue(origin.contains("GooglePlacesPhotoSourceMark()"))
        XCTAssertTrue(origin.contains("struct SaveOriginFoodCard"))
    }

    @MainActor
    func testHomeThumbnailViewsAnnounceGoogleMapsPhoto() throws {
        let google = try XCTUnwrap(URL(
            string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=view-test"
        ))
        let own = try XCTUnwrap(URL(string: "https://example.com/own-view-test.jpg"))
        let fixture = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        CachedImageStore.shared.store(fixture, for: google)
        CachedImageStore.shared.store(fixture, for: own)

        let english = hostedTexts(
            language: .english,
            google: google,
            own: own
        )
        XCTAssertTrue(
            english.contains(where: { $0.contains("Photo: Google Maps") }),
            "Rendered 52pt Google stamp must expose a VoiceOver Google Maps label. saw=\(english)"
        )
        XCTAssertTrue(
            english.contains(where: { $0.contains("Map Stamp, Harbor Oven") }),
            "Rendered stamp must keep Map Stamp language. saw=\(english)"
        )
        XCTAssertTrue(
            english.contains(where: { $0.contains("Harbor Oven, Photo: Google Maps") }),
            "Rendered 44pt featured peek must announce Photo: Google Maps. saw=\(english)"
        )
        XCTAssertFalse(
            english.contains(where: { $0.contains("Own shot") && $0.contains("Photo: Google Maps") }),
            "Own photo must stay unlabeled. saw=\(english)"
        )

        let chinese = hostedTexts(language: .traditionalChinese, google: google, own: own)
        XCTAssertTrue(
            chinese.contains(where: { $0.contains("照片來源：Google Maps") }),
            "zh-Hant VoiceOver must say 照片來源：Google Maps. saw=\(chinese)"
        )
    }

    @MainActor
    func testHomeThumbnailsKeepGooglePhotoWhenStackedMarkIsUsed() throws {
        let google = try XCTUnwrap(URL(
            string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=home-stacked"
        ))
        XCTAssertTrue(GooglePlacesPhotoSourceMarkMetrics.isGooglePhotoURL(google))
        let peek = try source(at: "SAV-E/Views/TileTown/SaveTileTownMap.swift")
        XCTAssertTrue(peek.contains("isGooglePhotoURL(photoURL)"))
        XCTAssertTrue(peek.contains("style: .homeStacked"))
        let stamp = try source(at: "SAV-E/Views/TileTown/SaveKraftStamp.swift")
        XCTAssertTrue(stamp.contains("isGooglePhotoURL(photoURL)"))
        XCTAssertTrue(stamp.contains("style: .homeStacked"))
    }

    @MainActor
    func testPersistableStringDropsPhotoNamesAndPlacesMediaURLs() {
        XCTAssertNil(GooglePlacesPhotoURL.persistableString(
            "places/ChIJ123/photos/ABC"
        ))
        XCTAssertNil(GooglePlacesPhotoURL.persistableString(
            "https://places.googleapis.com/v1/places/ChIJ123/photos/ABC/media"
        ))
        XCTAssertNil(GooglePlacesPhotoURL.persistableString(
            "https://lh3.googleusercontent.com/places/ANXAkqG-places-path"
        ))
        XCTAssertEqual(
            GooglePlacesPhotoURL.persistableString("https://lh3.googleusercontent.com/p/AF1Qip-generic"),
            "https://lh3.googleusercontent.com/p/AF1Qip-generic"
        )
        XCTAssertEqual(
            GooglePlacesPhotoURL.persistableString("https://example.com/own.jpg"),
            "https://example.com/own.jpg"
        )
        XCTAssertTrue(
            GooglePlacesPhotoURL.isGooglePlacesPhotoURL(
                URL(string: "https://lh3.googleusercontent.com/places/ANXAkqG-places-path")!
            )
        )
        XCTAssertFalse(
            GooglePlacesPhotoURL.isGooglePlacesPhotoURL(
                URL(string: "https://lh3.googleusercontent.com/p/AF1Qip-generic")!
            )
        )
    }

    @MainActor
    func testGooglePhotoKeyIsAddedOnlyForTheTransientRequest() throws {
        let service = GooglePlacesService(
            apiKey: "TEST_ONLY_NON_SECRET_VALUE",
            bundleIdentifier: "com.wanderly.app"
        )
        let persistedURL = try XCTUnwrap(service.photoURL(reference: "photo/reference+value", maxWidth: 900))
        let persistedItems = try XCTUnwrap(URLComponents(url: persistedURL, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertNil(persistedItems.first(where: { $0.name == "key" }))
        XCTAssertEqual(persistedItems.first(where: { $0.name == "photo_reference" })?.value, "photo/reference+value")
        XCTAssertTrue(persistedURL.absoluteString.contains("%2B"))
        XCTAssertFalse(persistedURL.absoluteString.contains("photo_reference=photo/reference+value"))

        let requestURL = try XCTUnwrap(service.authorizedPhotoURL(for: persistedURL))
        let requestItems = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(requestItems.first(where: { $0.name == "key" })?.value, "TEST_ONLY_NON_SECRET_VALUE")
        XCTAssertEqual(GooglePlacesPhotoURL.persistableURL(requestURL), persistedURL)

        let request = try XCTUnwrap(service.authorizedPhotoRequest(for: persistedURL))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"), "com.wanderly.app")
    }

    @MainActor
    func testBusinessPhotoEnrichmentFallsBackWhenSavedGooglePlaceIDIsStale() async throws {
        var saved = place(name: "amamotobros", category: .food)
        saved.address = "No. 377, Section 4, Ren'ai Road, Taipei"
        saved.latitude = 25.0386
        saved.longitude = 121.5557
        saved.googlePlaceId = "stale-place-id"
        let service = StaleGooglePlaceIDService()

        let result = await PlaceBusinessEnricher.enrich(saved, service: service)
        let enriched = try XCTUnwrap(result)

        XCTAssertEqual(service.requestedDetailIDs, ["stale-place-id", "fresh-place-id"])
        XCTAssertEqual(enriched.businessPhotoURLStrings, ["https://example.com/amamotobros.jpg"])
        XCTAssertEqual(enriched.googlePlaceId, "fresh-place-id")
        XCTAssertEqual(enriched.googleRating, 4.8)
    }

    @MainActor
    func testStaleGooglePlaceIDReplacesWrongCoverPhoto() async throws {
        var saved = place(name: "amamotobros", category: .food)
        saved.address = "No. 377, Section 4, Ren'ai Road, Taipei"
        saved.latitude = 25.0386
        saved.longitude = 121.5557
        saved.googlePlaceId = "stale-place-id"
        saved.businessPhotoUrls = ["https://example.com/wrong-ceiling.jpg"]
        let service = StaleGooglePlaceIDService()

        let result = await PlaceBusinessEnricher.enrich(saved, service: service)
        let enriched = try XCTUnwrap(result)

        XCTAssertEqual(enriched.businessPhotoURLStrings.first, "https://example.com/amamotobros.jpg")
        XCTAssertEqual(enriched.googlePlaceId, "fresh-place-id")
        XCTAssertFalse(try XCTUnwrap(enriched.businessPhotoURLStrings.first).contains("wrong-ceiling"))
    }

    @MainActor
    func testBusinessPhotoLookupRejectsDistantSameNameBranch() async {
        var saved = place(name: "竣師父牛肉麵-大安店", category: .food)
        saved.latitude = 25.0410
        saved.longitude = 121.5434

        let enriched = await PlaceBusinessEnricher.enrich(
            saved,
            service: DistantSameNameGooglePlacesService()
        )

        XCTAssertNil(enriched)
    }

    @MainActor
    func testBusinessPhotosStayAheadOfSourceImageAndKeepTheirOrder() async throws {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.sourceImageUrl = "https://example.com/social-post.jpg"
        saved.businessPhotoUrls = ["https://example.com/stable-cover.jpg"]

        let result = await PlaceBusinessEnricher.enrich(
            saved,
            service: ReorderedPhotoGooglePlacesService()
        )
        let enriched = try XCTUnwrap(result)

        XCTAssertEqual(enriched.businessPhotoURLStrings, [
            "https://example.com/stable-cover.jpg",
            "https://example.com/new-first.jpg",
            "https://example.com/social-post.jpg",
        ])
    }

    @MainActor
    func testExhaustedGalleryRefreshPutsRecoveredPhotoFirst() async throws {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.businessPhotoUrls = (0..<5).map { "https://example.com/expired-\($0).jpg" }
        saved.googleRating = 4
        saved.priceRange = "$$"
        saved.openingHours = "9-5"
        XCTAssertFalse(PlaceBusinessEnricher.needsEnrichment(saved))
        let result = await PlaceBusinessEnricher.enrich(
            saved, service: ReorderedPhotoGooglePlacesService(), refreshPhotos: true
        )
        let refreshed = try XCTUnwrap(result)
        XCTAssertEqual(refreshed.businessPhotoURLStrings.first, "https://example.com/new-first.jpg")
    }

    @MainActor
    func testBusinessPhotoLookupRejectsNearbyWrongBusiness() async {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.latitude = 25.0330
        saved.longitude = 121.5654

        let enriched = await PlaceBusinessEnricher.enrich(
            saved,
            service: NearbyWrongBusinessGooglePlacesService()
        )

        XCTAssertNil(enriched)
    }

    @MainActor
    func testVisibleHomePhotoBeyondFirstSixRefreshesOncePerSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HomePhotoGooglePlacesService()
        let map = MapViewModel(
            googlePlacesService: service,
            saveLocalVaultService: SaveLocalVaultService(
                overrideVaultURL: directory.appendingPathComponent("save-memory-records.json")
            ),
            usesRemotePersistence: false
        )
        let missing = place(name: "Memory Cafe", category: .cafe)
        var existing = place(name: "Existing Photo", category: .cafe)
        existing.sourceImageUrl = "https://example.com/existing.jpg"
        map.places = (0..<6).map { place(name: "Earlier \($0)", category: .cafe) } + [missing, existing]

        await map.refreshHomePlacePhoto(id: missing.id)
        await map.refreshHomePlacePhoto(id: missing.id)

        XCTAssertEqual(
            map.places.first(where: { $0.id == missing.id })?.businessPhotoURLStrings,
            ["https://example.com/memory-cafe.jpg"]
        )
        XCTAssertEqual(
            map.places.first(where: { $0.id == existing.id })?.businessPhotoURLStrings,
            ["https://example.com/existing.jpg"]
        )
        XCTAssertEqual(service.searchCallCount, 1)
    }

    @MainActor
    func testPersistedMemoryAndSharedListsDropGooglePhotoURLs() throws {
        let legacyURL = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref&key=TEST_ONLY_NON_SECRET_VALUE"
        let ownPhoto = "https://example.com/own-photo.jpg"
        let record = SaveMemoryRecord(
            state: .confirmedPlace,
            title: "Legacy Cafe",
            sourceImageUrl: legacyURL,
            businessPhotoUrls: [legacyURL, ownPhoto]
        )
        XCTAssertNil(record.sourceImageUrl)
        XCTAssertEqual(record.businessPhotoUrls, [ownPhoto])

        var legacyPlace = place(name: "Legacy Cafe", category: .cafe)
        legacyPlace.sourceImageUrl = legacyURL
        legacyPlace.businessPhotoUrls = [legacyURL]
        var list = SaveCollaborativeList(title: "Safe list")
        list.add(.from(place: legacyPlace))

        let shareURL = try XCTUnwrap(list.shareURL())
        let payload = try XCTUnwrap(SaveSharedListPayload.from(url: shareURL))
        XCTAssertEqual(payload.list.items.first?.photoURLs ?? [], [])
    }

    @MainActor
    func testHTMLAttributionsExposeAuthorNameAndLink() {
        let authors = GooglePlacesHTMLAttribution.authors(from: [
            #"<a href="https://maps.google.com/maps/contrib/123">Jane Doe</a>"#,
            "Photo by the shop",
        ])
        XCTAssertEqual(authors.count, 2)
        XCTAssertEqual(authors[0].displayName, "Jane Doe")
        XCTAssertEqual(authors[0].uri?.absoluteString, "https://maps.google.com/maps/contrib/123")
        XCTAssertEqual(authors[1].displayName, "Photo by the shop")
        XCTAssertNil(authors[1].uri)
    }

    @MainActor
    func testAttributionLogoHeightStaysInsideGoogleSpec() {
        XCTAssertGreaterThanOrEqual(GoogleMapsAttributionMetrics.logoHeight, GoogleMapsAttributionMetrics.logoMinHeight)
        XCTAssertLessThanOrEqual(GoogleMapsAttributionMetrics.logoHeight, GoogleMapsAttributionMetrics.logoMaxHeight)
        XCTAssertEqual(GoogleMapsAttributionMetrics.clearSpaceLeading, 10)
        XCTAssertEqual(GoogleMapsAttributionMetrics.clearSpaceTrailing, 10)
        XCTAssertEqual(GoogleMapsAttributionMetrics.clearSpaceTop, 10)
        XCTAssertEqual(GoogleMapsAttributionMetrics.clearSpaceBottom, 5)
        XCTAssertEqual(GoogleMapsAttributionMetrics.minimumTapTarget, 44)
        XCTAssertGreaterThanOrEqual(GoogleMapsAttributionMetrics.gradientTopOpacity, 0.25)
        XCTAssertEqual(GoogleMapsAttributionMetrics.carouselHeight, 156)
        XCTAssertGreaterThanOrEqual(GoogleMapsAttributionMetrics.authorShadowOpacity, 0.5)
    }

    @MainActor
    func testAttributionWhiteTextMeetsContrastOnLightPhoto() {
        let ratio = GoogleMapsAttributionContrast.whiteTextRatio(
            photo: GoogleMapsAttributionMetrics.lightPhotoCream,
            overlayOpacity: GoogleMapsAttributionMetrics.gradientTopOpacity
        )
        XCTAssertGreaterThanOrEqual(
            ratio,
            4.5,
            "White attribution type over the cream fixture must stay at WCAG 4.5:1"
        )
    }

    func testCompactAttributionRowIsAHittableButton() throws {
        let sheet = try source(at: "SAV-E/Views/Map/PlaceBottomSheet.swift")
        let uiTest = try source(at: "Tests/SAVEUITests/SAVEGooglePhotoAttributionTests.swift")
        let evidence = try source(at: "SAV-E/Testing/GooglePlacesPhotoAttributionEvidenceView.swift")

        guard let compactStart = sheet.range(of: "private var compactRow: some View"),
              let compactEnd = sheet.range(of: "private var expandedStack: some View") else {
            return XCTFail("Missing compactRow")
        }
        let compact = String(sheet[compactStart.lowerBound..<compactEnd.lowerBound])
        XCTAssertTrue(compact.contains("Button {"), "Compact row must be a SwiftUI Button so app.buttons can see it")
        XCTAssertTrue(compact.contains("compactVisualRow"), "Visual row must be the Button label so the tap hits content")
        XCTAssertTrue(compact.contains("place.photo.attribution.row"))
        XCTAssertFalse(compact.contains("foregroundStyle(.clear)"), "Clear overlay buttons swallow taps")
        XCTAssertFalse(compact.contains("accessibilityHidden"), "Hidden children swallow the Button identifier")
        XCTAssertFalse(compact.contains("place.photo.attribution.logo"), "Nested logo identifier splits the Button")
        XCTAssertFalse(compact.contains("accessibilityElement(children:"), "AX containers are not hittable in XCTest")
        XCTAssertFalse(compact.contains("UIViewRepresentable"), "UIKit hosts often land in otherElements, not buttons")
        XCTAssertFalse(compact.contains("allowsHitTesting(false)"), "The Button label must receive the tap")
        XCTAssertTrue(uiTest.contains("app.buttons[\"place.photo.attribution.row\"]"))
        XCTAssertTrue(evidence.contains("sceneIdentifier: \"evidence.googleCarousel\""))
        XCTAssertFalse(
            evidence.contains("accessibilityElement(children: .contain)"),
            "Contain-container identifiers are invisible to descendants(matching: .any)"
        )
        guard let bodyStart = evidence.range(of: "var body: some View"),
              let pickerStart = evidence.range(of: "private var scenePicker: some View") else {
            return XCTFail("Missing evidence body")
        }
        let body = String(evidence[bodyStart.lowerBound..<pickerStart.lowerBound])
        XCTAssertTrue(
            body.contains("Text(\"Evidence\")"),
            "Root identifier must live on a leaf, not the stack that wraps the carousel"
        )
        XCTAssertTrue(body.contains(".accessibilityIdentifier(\"evidence.googlePhoto.root\")"))
        XCTAssertFalse(
            body.contains(".navigationBarTitleDisplayMode(.inline)\n            .accessibilityIdentifier(\"evidence.googlePhoto.root\")"),
            "Parent root identifier overwrites Harbor Oven, the compact Button, and evidence.googleCarousel"
        )
        XCTAssertTrue(evidence.contains("GoogleMapsAttributionLogo()"))
        XCTAssertTrue(
            evidence.contains("LazyVGrid"),
            "Scene chips must wrap. A horizontal ScrollView leaves Logo close-up off-screen"
        )
        XCTAssertFalse(
            evidence.contains("ScrollView(.horizontal"),
            "Horizontal scene picker makes logoCloseup exist but not hittable"
        )
        guard let sceneBodyStart = evidence.range(of: "private var sceneBody: some View"),
              let carouselPageStart = evidence.range(of: "private var googleCarouselPage: some View") else {
            return XCTFail("Missing evidence sceneBody")
        }
        let sceneBody = String(evidence[sceneBodyStart.lowerBound..<carouselPageStart.lowerBound])
        guard let logoStart = sceneBody.range(of: "case .logoCloseup:"),
              let noAuthorStart = sceneBody.range(of: "case .noAuthor:") else {
            return XCTFail("Missing logoCloseup scene")
        }
        let logoScene = String(sceneBody[logoStart.lowerBound..<noAuthorStart.lowerBound])
        XCTAssertTrue(logoScene.contains("GoogleMapsAttributionLogo()"))
        XCTAssertTrue(
            logoScene.contains(".accessibilityIdentifier(\"evidence.logoCloseup\")")
        )
        XCTAssertFalse(
            logoScene.contains("}\n            .accessibilityIdentifier(\"evidence.logoCloseup\")"),
            "Parent evidence.logoCloseup overwrites place.photo.attribution.logo"
        )
        XCTAssertTrue(
            sheet.contains("enum GooglePlacesPhotoCardLayout"),
            "Carousel must size the photo before overlaying the logo row"
        )
        XCTAssertTrue(sheet.contains("GooglePlacesPhotoCardLayout.overlayCard"))
        XCTAssertTrue(evidence.contains("GooglePlacesPhotoCardLayout.overlayCard"))
        XCTAssertFalse(
            evidence.contains("url.host?.contains(\"contrib\")"),
            "Author URLs put contrib in the path. Host maps.google.com never matches."
        )
        XCTAssertTrue(evidence.contains("isAuthorDestination"))
        XCTAssertTrue(evidence.contains("Color(hex: \"3A2415\")"))
        XCTAssertTrue(evidence.contains("evidence.openedPage.author"))
        XCTAssertTrue(evidence.contains("evidence.openedPage.maps"))
        XCTAssertTrue(evidence.contains("evidence.mixedCard"))
        XCTAssertTrue(evidence.contains("evidence.mapPins"))
        XCTAssertTrue(evidence.contains("evidence.cityPage"))
        XCTAssertTrue(evidence.contains("evidence.reportEntry"))
        XCTAssertTrue(evidence.contains("case homeThumbs"))
        XCTAssertTrue(evidence.contains("SaveTileTownPeekCard("))
        XCTAssertTrue(evidence.contains("size: .recent"))
        XCTAssertTrue(evidence.contains("evidence.homeThumbs"))
        XCTAssertTrue(uiTest.contains("evidence.openedPage.author"))
        XCTAssertTrue(uiTest.contains("appearance)-mixed-card"))
        XCTAssertTrue(uiTest.contains("appearance)-map-pins"))
        XCTAssertTrue(uiTest.contains("appearance)-city-page"))
        XCTAssertTrue(uiTest.contains("appearance)-report-entry"))
        XCTAssertTrue(uiTest.contains("appearance)-home-thumbs"))
    }

    @MainActor
    func testDestinationPageInkMeetsContrastOnWhite() {
        let ratio = GoogleMapsAttributionContrast.ratio(
            foreground: (r: 0x3A / 255.0, g: 0x24 / 255.0, b: 0x15 / 255.0),
            background: (r: 1, g: 1, b: 1)
        )
        XCTAssertGreaterThanOrEqual(
            ratio,
            4.5,
            "Maps/author page title on white must stay WCAG 4.5:1 in Dark Mode"
        )
    }

    @MainActor
    func testGooglePhotosWithoutAuthorsAreDroppedForG1() {
        GooglePlacePhotoSessionStore.resetForTests()
        let googleURL = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=no-author"
        let ownURL = "https://example.com/own.jpg"
        let pages = PlacePhotoPage.pages(
            imageURLs: [googleURL, ownURL],
            googlePlaceId: "ChIJ123",
            googleMapsURI: URL(string: "https://maps.google.com/?cid=1")
        )
        XCTAssertEqual(pages.count, 1)
        XCTAssertFalse(pages[0].isGooglePlacesPhoto)
        XCTAssertEqual(pages[0].url.absoluteString, ownURL)
    }

    @MainActor
    func testGooglePhotoRecordWithEmptyAuthorsIsDroppedForG1() {
        GooglePlacePhotoSessionStore.resetForTests()
        let googleURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=empty-authors")!
        GooglePlacePhotoSessionStore.remember([
            GooglePlacePhotoRecord(url: googleURL, authors: [], googleMapsURI: nil)
        ])
        XCTAssertNotNil(GooglePlacePhotoSessionStore.record(for: googleURL))
        XCTAssertTrue(GooglePlacePhotoSessionStore.record(for: googleURL)?.authors.isEmpty == true)

        let pages = PlacePhotoPage.pages(
            imageURLs: [googleURL.absoluteString],
            googlePlaceId: "ChIJEmpty",
            googleMapsURI: nil
        )
        XCTAssertTrue(pages.isEmpty, "A stored Google photo with no authors must not render")
    }

    @MainActor
    func testMainlandChinaUsersSkipGooglePhotoEnrichment() async {
        var saved = place(name: "Memory Cafe", category: .cafe)
        saved.latitude = 31.2304
        saved.longitude = 121.4737
        let service = HomePhotoGooglePlacesService()

        let result = await PlaceBusinessEnricher.enrich(
            saved,
            service: service,
            mapsPlatformAllowed: false
        )

        XCTAssertNil(result)
        XCTAssertEqual(service.searchCallCount, 0)
        XCTAssertEqual(service.detailCallCount, 0)
    }

    @MainActor
    func testGooglePhotoPagesKeepAuthorAttributionAndSkipUserPhotos() {
        GooglePlacePhotoSessionStore.resetForTests()
        let googleURL = URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=ref-1")!
        let userURL = "https://example.com/own.jpg"
        GooglePlacePhotoSessionStore.remember([
            GooglePlacePhotoRecord(
                url: googleURL,
                authors: [
                    GooglePlacePhotoAuthor(displayName: "Jane Doe", uri: URL(string: "https://maps.google.com/maps/contrib/123")),
                    GooglePlacePhotoAuthor(displayName: "Alex Chen", uri: URL(string: "https://maps.google.com/maps/contrib/987")),
                ],
                googleMapsURI: URL(string: "https://maps.google.com/?cid=1")
            )
        ])

        let pages = PlacePhotoPage.pages(
            imageURLs: [googleURL.absoluteString, userURL],
            googlePlaceId: "ChIJ123",
            googleMapsURI: nil
        )

        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages[0].isGooglePlacesPhoto)
        XCTAssertEqual(pages[0].authors.map(\.displayName), ["Jane Doe", "Alex Chen"])
        XCTAssertEqual(pages[0].mapsURI?.absoluteString, "https://maps.google.com/?cid=1")
        XCTAssertFalse(pages[1].isGooglePlacesPhoto)
        XCTAssertTrue(pages[1].authors.isEmpty)
        XCTAssertNil(pages[1].mapsURI)
    }

    @MainActor
    func testMapsPlatformIsBlockedOnlyForMainlandChinaRegion() {
        XCTAssertFalse(GoogleMapsPlatformAvailability.isAllowed(regionCode: "CN"))
        XCTAssertTrue(GoogleMapsPlatformAvailability.isAllowed(regionCode: "TW"))
        XCTAssertTrue(GoogleMapsPlatformAvailability.isAllowed(regionCode: "US"))
        XCTAssertTrue(GoogleMapsPlatformAvailability.isAllowed(regionCode: "HK"))
    }

    // MARK: - Server short-code links (`?c=`)

    @MainActor
    func testShareCodeParsesServerListLinks() throws {
        let https = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=Ab3_x-9Q"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: https), "Ab3_x-9Q")
        XCTAssertTrue(SaveSharedListPayload.isListLink(https))

        let currentScheme = try XCTUnwrap(URL(string: "savvy://list?c=abcdef"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: currentScheme), "abcdef")

        let legacyScheme = try XCTUnwrap(URL(string: "wanderly://list?c=abcdef"))
        XCTAssertEqual(SaveSharedListPayload.shareCode(from: legacyScheme), "abcdef")
    }

    @MainActor
    func testShareCodeRejectsMalformedOrLegacyLinks() throws {
        // Legacy embedded-snapshot link has no code.
        let legacy = try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?d=eyJ9&r=viewer"))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: legacy))

        // Too short, bad characters, wrong host/path.
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=abc"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/list?c=abc%20def1"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://evil.example.com/list?c=abcdef"))))
        XCTAssertNil(SaveSharedListPayload.shareCode(from: try XCTUnwrap(URL(string: "https://sav-e-app.vercel.app/trip?c=abcdef"))))
    }

    // MARK: - Server row mapping

    @MainActor
    func testServerRowMapsToCollaborativeListAndRoundTripsItemPayload() throws {
        let item = SaveListItem.from(place: place(name: "Onibus Coffee", category: .cafe), addedByDisplayName: "Ezven")
        let listID = UUID()
        let row = SaveCollaborativeListServerRow(
            id: listID.uuidString.lowercased(),
            title: "Tokyo cafes",
            note: "Saturday",
            owner_id: "did:privy:owner",
            viewer_role: "editor",
            items: [SaveCollaborativeListServerItemRow(id: UUID().uuidString, payload: item, added_by: "did:privy:owner")],
            created_at: "2026-08-12T10:00:00Z",
            updated_at: "2026-08-12T11:30:00.123Z"
        )

        // Round trip the row itself the way the API layer does (plain coders).
        let data = try JSONEncoder.supabase.encode(row)
        let decodedRow = try JSONDecoder.supabase.decode(SaveCollaborativeListServerRow.self, from: data)
        let list = try XCTUnwrap(SaveCollaborativeList(serverRow: decodedRow))

        XCTAssertEqual(list.id, listID)
        XCTAssertEqual(list.title, "Tokyo cafes")
        XCTAssertEqual(list.note, "Saturday")
        XCTAssertEqual(list.viewerRole, .editor)
        XCTAssertTrue(list.serverBacked)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items.first?.title, "Onibus Coffee")
        XCTAssertEqual(list.items.first?.addedByDisplayName, "Ezven")
        XCTAssertEqual(list.createdAt, SaveCollaborativeList.serverDate("2026-08-12T10:00:00Z"))
        XCTAssertEqual(list.updatedAt, SaveCollaborativeList.serverDate("2026-08-12T11:30:00.123Z"))
    }

    @MainActor
    func testServerRowDropsUndecodableItemPayloadsInsteadOfFailing() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Lenient list",
          "viewer_role": "viewer",
          "items": [
            {"id": "x", "payload": {"unexpected": true}, "added_by": null, "created_at": null}
          ]
        }
        """
        let row = try JSONDecoder.supabase.decode(SaveCollaborativeListServerRow.self, from: Data(json.utf8))
        let list = try XCTUnwrap(SaveCollaborativeList(serverRow: row))

        XCTAssertTrue(list.items.isEmpty)
        XCTAssertEqual(list.viewerRole, .viewer)
        XCTAssertFalse(list.canEdit)
    }

    @MainActor
    func testServerRowWithNonUUIDIdIsRejected() {
        let row = SaveCollaborativeListServerRow(id: "not-a-uuid", title: "Bad", viewer_role: "owner")
        XCTAssertNil(SaveCollaborativeList(serverRow: row))
    }

    // MARK: - Merge + cache compatibility

    @MainActor
    func testMergeServerWinsByIdAndKeepsLocalOnlyLists() {
        let sharedID = UUID()
        let serverList = SaveCollaborativeList(
            id: sharedID,
            title: "Server title",
            viewerRole: .editor,
            updatedAt: Date(timeIntervalSinceNow: -10),
            serverBacked: true
        )
        let staleLocal = SaveCollaborativeList(id: sharedID, title: "Stale local title", updatedAt: Date())
        let localOnly = SaveCollaborativeList(title: "Offline list", updatedAt: Date(timeIntervalSinceNow: -100))

        let merged = MapViewModel.mergeCollaborativeLists(server: [serverList], local: [staleLocal, localOnly])

        XCTAssertEqual(merged.count, 2)
        let winner = merged.first(where: { $0.id == sharedID })
        XCTAssertEqual(winner?.title, "Server title")
        XCTAssertEqual(winner?.viewerRole, .editor)
        XCTAssertTrue(merged.contains(where: { $0.id == localOnly.id }))
        // Sorted by updatedAt descending.
        XCTAssertEqual(merged.map(\.id), [sharedID, localOnly.id])
    }

    @MainActor
    func testLegacyPersistedListsDecodeWithServerBackedDefaultingFalse() throws {
        // Snapshot of the pre-serverBacked persisted shape (plain JSONEncoder:
        // dates are seconds since the reference date).
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy list",
          "ownerDisplayName": "You",
          "viewerRole": "owner",
          "items": [],
          "createdAt": 745000000,
          "updatedAt": 745000000
        }
        """
        let list = try JSONDecoder().decode(SaveCollaborativeList.self, from: Data(json.utf8))
        XCTAssertFalse(list.serverBacked)
        XCTAssertEqual(list.title, "Legacy list")

        // And the new field survives its own round trip.
        var backed = list
        backed.serverBacked = true
        let reencoded = try JSONEncoder().encode(backed)
        XCTAssertTrue(try JSONDecoder().decode(SaveCollaborativeList.self, from: reencoded).serverBacked)
    }

    // MARK: - Member + share-code row mapping

    @MainActor
    func testListMemberRowMapsRoleDateAndDisplayNameFallback() throws {
        let named = try JSONDecoder().decode(SaveListMemberRow.self, from: Data("""
        {"user_id": "did:privy:abc", "role": "owner", "display_name": "  Ezven  ", "created_at": "2026-08-01T10:20:30.123Z"}
        """.utf8))
        let info = SaveListMemberInfo(row: named)
        XCTAssertEqual(info.id, "did:privy:abc")
        XCTAssertEqual(info.role, .owner)
        XCTAssertEqual(info.displayName, "Ezven")
        XCTAssertNotNil(info.joinedAt)

        // Missing role/name/date degrade instead of dropping the row.
        let bare = SaveListMemberInfo(row: SaveListMemberRow(user_id: "did:privy:xyz"))
        XCTAssertEqual(bare.role, .viewer)
        XCTAssertEqual(bare.displayName, "Traveler")
        XCTAssertNil(bare.joinedAt)
    }

    @MainActor
    func testListShareCodeRowMapsAndNeverGrantsOwnerBadge() {
        let editor = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(
            code: "abc123",
            role: "editor",
            url: "https://sav-e-app.vercel.app/list?c=abc123",
            expires_at: "2026-09-01T00:00:00Z",
            created_at: "2026-08-01T00:00:00Z"
        ))
        XCTAssertEqual(editor.id, "abc123")
        XCTAssertEqual(editor.role, .editor)
        XCTAssertEqual(editor.url?.absoluteString, "https://sav-e-app.vercel.app/list?c=abc123")
        XCTAssertNotNil(editor.expiresAt)
        XCTAssertNotNil(editor.createdAt)

        // Share codes only ever grant viewer/editor; an "owner" (or unknown)
        // role from the server renders as the safer viewer badge.
        let owner = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(code: "own", role: "owner"))
        XCTAssertEqual(owner.role, .viewer)
        let unknown = SaveListShareCodeInfo(row: SaveListShareCodeInfoRow(code: "wat", role: "banana"))
        XCTAssertEqual(unknown.role, .viewer)
        XCTAssertNil(unknown.url)
        XCTAssertNil(unknown.expiresAt)
    }

    @MainActor
    private func place(name: String, category: PlaceCategory) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            googlePlaceId: nil,
            category: category,
            status: .wantToGo,
            rating: nil,
            note: "House pick",
            sourceUrl: "https://example.com/\(name)",
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }

    @MainActor
    private func hostedTexts(language: AppLanguage, google: URL, own: URL) -> [String] {
        let suite = "save.home.thumb.\(language.rawValue).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(language.rawValue, forKey: "save.appLanguage")
        let settings = AppLanguageSettings(userDefaults: defaults)
        let root = VStack(alignment: .leading, spacing: 12) {
            SaveTileTownPeekCard(
                title: "Harbor Oven",
                subtitle: "Featured",
                photoURL: google,
                accessibilityNameID: "test.featured.google"
            )
            .frame(width: 280, height: 110)
            SaveTileTownPeekCard(
                title: "Own shot",
                subtitle: "Featured",
                photoURL: own,
                accessibilityNameID: "test.featured.own"
            )
            .frame(width: 280, height: 110)
            HStack(alignment: .top, spacing: 16) {
                SaveKraftStamp(
                    title: "Harbor Oven",
                    face: .photo(google),
                    size: .recent,
                    accessibilityIdentifier: "test.recent.google"
                )
                SaveKraftStamp(
                    title: "Own shot",
                    face: .photo(own),
                    size: .recent,
                    accessibilityIdentifier: "test.recent.own"
                )
            }
        }
        .environment(\.appLanguageSettings, settings)
        .frame(width: 320, height: 280)

        let host = UIHostingController(rootView: root)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 280)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 280))
        }
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(1)
        var texts: [String] = []
        let expected = language.localized(english: "Photo: Google Maps", traditionalChinese: "照片來源：Google Maps")
        while Date() < deadline {
            texts = collectAccessibilityStrings(from: host.view, seen: NSHashTable<NSObject>.weakObjects())
            if texts.contains(where: { $0.contains(expected) }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        window.isHidden = true
        defaults.removePersistentDomain(forName: suite)
        return texts
    }

    @MainActor
    private func collectAccessibilityStrings(from element: Any?, seen: NSHashTable<NSObject>) -> [String] {
        guard let node = element as? NSObject else { return [] }
        if seen.contains(node) { return [] }
        seen.add(node)
        var texts: [String] = []
        if let text = node.accessibilityLabel, !text.isEmpty { texts.append(text) }
        if let value = node.accessibilityValue as? String, !value.isEmpty { texts.append(value) }
        if let identified = node as? UIAccessibilityIdentification,
           let identifier = identified.accessibilityIdentifier, !identifier.isEmpty {
            texts.append(identifier)
        }
        if let view = node as? UIView {
            for subview in view.subviews {
                texts.append(contentsOf: collectAccessibilityStrings(from: subview, seen: seen))
            }
        }
        if let elements = node.accessibilityElements {
            for child in elements {
                texts.append(contentsOf: collectAccessibilityStrings(from: child, seen: seen))
            }
        }
        if node.responds(to: #selector(NSObject.accessibilityElementCount)) {
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count {
                    texts.append(contentsOf: collectAccessibilityStrings(
                        from: node.accessibilityElement(at: index),
                        seen: seen
                    ))
                }
            }
        }
        return texts
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

@MainActor
private final class StaleGooglePlaceIDService: GooglePlacesServiceProtocol {
    private(set) var requestedDetailIDs: [String] = []

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [
            GooglePlaceMatch(
                id: "fresh-place-id",
                name: "amamotobros",
                address: "No. 377, Section 4, Ren'ai Road, Taipei",
                latitude: 25.0386,
                longitude: 121.5557,
                rating: 4.8,
                photoReference: "amamotobros-photo"
            )
        ]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        requestedDetailIDs.append(placeId)
        guard placeId == "fresh-place-id" else {
            throw URLError(.badServerResponse)
        }
        return GooglePlaceDetails(
            placeId: placeId,
            name: "amamotobros",
            formattedAddress: "No. 377, Section 4, Ren'ai Road, Taipei",
            latitude: 25.0386,
            longitude: 121.5557,
            rating: 4.8,
            priceLevel: nil,
            openingHours: nil,
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["amamotobros-photo"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/amamotobros.jpg")
    }
}

@MainActor
private final class HomePhotoGooglePlacesService: GooglePlacesServiceProtocol {
    private(set) var searchCallCount = 0
    private(set) var detailCallCount = 0

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        searchCallCount += 1
        return [
            GooglePlaceMatch(
                id: "memory-cafe",
                name: "Memory Cafe",
                address: "Irvine, CA",
                latitude: 33.6849,
                longitude: -117.8262,
                rating: 4.6,
                photoReference: "memory-cafe-photo"
            )
        ]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        detailCallCount += 1
        return GooglePlaceDetails(
            placeId: placeId,
            name: "Memory Cafe",
            formattedAddress: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            rating: 4.6,
            priceLevel: nil,
            openingHours: nil,
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["memory-cafe-photo"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/memory-cafe.jpg")
    }
}

@MainActor
private final class ReorderedPhotoGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [GooglePlaceMatch(
            id: "memory-cafe",
            name: "Memory Cafe",
            address: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            photoReference: "new-first"
        )]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        GooglePlaceDetails(
            placeId: placeId,
            name: "Memory Cafe",
            formattedAddress: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            rating: 4.6,
            priceLevel: 2,
            openingHours: ["Monday: 9:00 AM – 5:00 PM"],
            phoneNumber: nil,
            websiteUrl: nil,
            photoReferences: ["new-first"]
        )
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/new-first.jpg")
    }
}

@MainActor
private final class NearbyWrongBusinessGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [GooglePlaceMatch(
            id: "wrong-restaurant",
            name: "Different Restaurant",
            address: "Nearby",
            latitude: 25.0337,
            longitude: 121.5654,
            photoReference: "wrong-photo"
        )]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        XCTFail("An unrelated nearby business must not be enriched")
        throw URLError(.resourceUnavailable)
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/wrong.jpg")
    }
}

@MainActor
private final class DistantSameNameGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        [GooglePlaceMatch(
            id: "other-branch",
            name: "竣師父牛肉麵",
            address: "Zhongxiao",
            latitude: 25.0545,
            longitude: 121.5434,
            photoReference: "other-branch-photo"
        )]
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        XCTFail("A same-name shop 1.5 km away must not bind Home cover art")
        throw URLError(.resourceUnavailable)
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        URL(string: "https://example.com/other-branch.jpg")
    }
}
