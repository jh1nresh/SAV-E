import XCTest
import MapKit
import CoreLocation
@testable import SAVE

final class SaveSearchControllerTests: XCTestCase {
    func testPlaceActionResolutionIsStateSafe() {
        let weakCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Unverified brunch reel",
            address: "",
            city: "Irvine",
            latitude: nil,
            longitude: nil,
            evidence: ["Source clue only"],
            confidence: 0.42,
            missingInfo: ["Verified address", "Verified coordinates"],
            status: "pending",
            createdAt: Date()
        )
        let weakAction = SavePlaceActionResolution(candidate: weakCandidate)

        XCTAssertEqual(weakAction.kind, .runRecovery)
        XCTAssertEqual(weakAction.title, "Find exact place")
        XCTAssertFalse(weakAction.confirmsMapStamp)

        let staleSavePlaceCandidate = SaveSearchResult(
            id: UUID().uuidString,
            objectType: .pendingCandidate,
            userState: .waitingReview,
            title: "Unverified brunch reel",
            subtitle: "Irvine",
            statusLabel: "Review Candidate",
            sourceURL: "https://www.instagram.com/reel/example",
            sourcePlatform: .instagram,
            category: .cafe,
            cityOrArea: "Irvine",
            latitude: nil,
            longitude: nil,
            rating: nil,
            reviewCount: nil,
            confidence: 0.42,
            missingInfo: ["Verified address", "Verified coordinates"],
            evidence: ["Source clue only"],
            recoveryQueries: ["Unverified brunch reel Irvine"],
            createdAt: Date(),
            canRunRecovery: true,
            isRecommendationShell: false,
            primaryAction: .savePlace
        )
        let staleAction = SavePlaceActionResolution(result: staleSavePlaceCandidate)

        XCTAssertEqual(staleAction.kind, .runRecovery)
        XCTAssertFalse(staleAction.confirmsMapStamp)

        let mapReadyCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Quarter Sheets",
            address: "1305 Portia St",
            city: "Los Angeles",
            latitude: 34.083,
            longitude: -118.254,
            evidence: ["Google Places match", "Verified coordinates"],
            confidence: 0.86,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let mapReadyAction = SavePlaceActionResolution(candidate: mapReadyCandidate)

        XCTAssertEqual(mapReadyAction.kind, .confirmMapStamp)
        XCTAssertEqual(mapReadyAction.title, "Confirm Map Stamp")
        XCTAssertTrue(mapReadyAction.confirmsMapStamp)

        let savedPlace = place(
            name: "Saved Cafe",
            address: "Irvine, CA",
            category: .cafe
        )
        let savedAction = SavePlaceActionResolution(place: savedPlace)
        XCTAssertEqual(savedAction.kind, .recommendOrder)
    }

    func testSavePlaceDrawerPresentationMapsCoreStates() {
        let savedPlace = place(
            name: "Bright Coffee Bar",
            address: "Irvine, CA",
            category: .cafe
        )
        let savedPresentation = SavePlaceDrawerPresentation(place: savedPlace)

        XCTAssertEqual(savedPresentation.state, .mapStamp)
        XCTAssertEqual(savedPresentation.eyebrow, "Map Stamp · From your SAV-E")
        XCTAssertEqual(savedPresentation.trustLine, "Saved to your place memory.")
        XCTAssertEqual(savedPresentation.primaryActionTitle, "What should I order?")

        let reviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Quarter Sheets",
            address: "1305 Portia St",
            city: "Los Angeles",
            latitude: 34.083,
            longitude: -118.254,
            evidence: ["Google Places match"],
            confidence: 0.86,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let reviewPresentation = SavePlaceDrawerPresentation(reviewCandidate: reviewCandidate)

        XCTAssertEqual(reviewPresentation.state, .reviewCandidate)
        XCTAssertEqual(reviewPresentation.eyebrow, "Review Candidate · Check before saving")
        XCTAssertEqual(reviewPresentation.trustLine, "SAV-E found a likely place. Review the evidence before stamping it to your map.")
        XCTAssertEqual(reviewPresentation.primaryActionTitle, "Confirm Map Stamp")

        let sourceClue = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Brunch reel",
            address: "",
            city: "Irvine",
            latitude: nil,
            longitude: nil,
            evidence: ["Instagram source clue"],
            confidence: 0.42,
            missingInfo: ["Confirm address", "Confirm coordinates"],
            status: "pending",
            createdAt: Date()
        )
        let cluePresentation = SavePlaceDrawerPresentation(reviewCandidate: sourceClue)

        XCTAssertEqual(cluePresentation.state, .clue)
        XCTAssertEqual(cluePresentation.eyebrow, "Clue · Needs exact place")
        XCTAssertEqual(cluePresentation.trustLine, "SAV-E found a source, but not enough proof for a place yet.")
        XCTAssertEqual(cluePresentation.primaryActionTitle, "Find exact place")

        let orderDraftPresentation = SavePlaceDrawerPresentation.menuOrderDraft(
            title: "Bright Coffee Bar",
            contextLine: "Saved coffee place from your map memory."
        )

        XCTAssertEqual(orderDraftPresentation.state, .menuOrderDraft)
        XCTAssertEqual(orderDraftPresentation.eyebrow, "Order draft · From your SAV-E")
        XCTAssertEqual(orderDraftPresentation.primaryActionTitle, "Draft order idea")
    }

    func testSavePlaceDrawerPresentationLabelsUnsavedMapCandidatesSeparately() {
        let candidate = SaveMapCandidate(
            title: "Costco Wholesale",
            subtitle: "Selected on map",
            latitude: 33.69,
            longitude: -117.83,
            category: .shopping,
            distanceMeters: 1_700,
            evidence: ["Apple Maps POI"]
        )

        let presentation = SavePlaceDrawerPresentation(mapCandidate: candidate)

        XCTAssertEqual(presentation.state, .unsavedMapCandidate)
        XCTAssertEqual(presentation.eyebrow, "Public discovery · Not saved yet")
        XCTAssertEqual(presentation.primaryActionTitle, "Save this place")
        XCTAssertTrue(presentation.contextLine.contains("Shopping"))
        XCTAssertTrue(presentation.contextLine.contains("1.7 km away"))
        XCTAssertFalse(presentation.trustLine.contains("Map Stamp"))
    }

    func testSavedPlaceMatchesUnderlyingMapPOI() {
        let savedPlace = place(
            name: "Bright Coffee Bar",
            address: "Irvine, CA",
            category: .cafe,
            latitude: 33.6849,
            longitude: -117.8262
        )

        XCTAssertTrue(savedPlace.matchesMapFeature(
            title: "Bright Coffee Bar",
            coordinate: CLLocationCoordinate2D(latitude: 33.68491, longitude: -117.82619)
        ))
        XCTAssertFalse(savedPlace.matchesMapFeature(
            title: "Different Coffee",
            coordinate: CLLocationCoordinate2D(latitude: 33.6858, longitude: -117.8262)
        ))
    }

    func testMapCandidateKeepsMultipleBusinessPhotosForPreview() {
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            photoURL: "https://example.com/photo-1.jpg",
            businessPhotoURLs: [
                "https://example.com/photo-1.jpg",
                "https://example.com/photo-2.jpg",
                "https://example.com/photo-3.jpg"
            ]
        )

        XCTAssertEqual(candidate.businessPhotoURLStrings, [
            "https://example.com/photo-1.jpg",
            "https://example.com/photo-2.jpg",
            "https://example.com/photo-3.jpg"
        ])
    }

    func testCategoryInferenceUsesPOIAndAvoidsSubstringFalsePositives() {
        XCTAssertEqual(PlaceCategory.inferred(from: "Heritage Barbecue Chicken"), .food)
        XCTAssertEqual(PlaceCategory.inferred(from: "Bright Barber Shop"), .shopping)
        XCTAssertEqual(PlaceCategory.inferred(from: "Disneyland Park"), .attraction)
        XCTAssertEqual(
            PlaceCategory.inferredMapCategory(
                title: "Kung Fu Foot Massage",
                subtitle: "Westminster, CA",
                pointOfInterestCategory: "MKPOICategorySpa",
                fallback: .food
            ),
            .shopping
        )
        XCTAssertEqual(
            PlaceCategory.inferredMapCategory(
                title: "Sushi Gen",
                subtitle: "Little Tokyo",
                pointOfInterestCategory: "MKPOICategoryRestaurant",
                fallback: .attraction
            ),
            .food
        )
    }

    func testChineseMilkTeaQueryUnderstandsCafeDrinkIntent() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "今天想喝奶茶",
            places: [
                place(
                    name: "Sunright Tea Studio",
                    address: "Irvine, CA",
                    category: .cafe,
                    note: "Brown sugar boba and milk tea"
                ),
                place(name: "Sushi Gen", address: "Los Angeles, CA", category: .food)
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Sunright Tea Studio"])
        XCTAssertEqual(response.fromYourSave.results.first?.category, .cafe)
        XCTAssertEqual(response.newRecommendations.results.count, 0)
    }

    func testMilkTeaQueryMatchesSavedBobaEvidenceBeforeGenericCafe() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "milk tea",
            places: [
                place(name: "Generic Coffee", address: "Taipei, Taiwan", category: .cafe),
                place(
                    name: "Half and Half Tea Express",
                    address: "San Gabriel, CA",
                    category: .cafe,
                    extractedDishes: ["honey boba", "milk tea"]
                )
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Half and Half Tea Express"])
        XCTAssertTrue(response.fromYourSave.results.first?.evidence.contains { $0.contains("milk tea") } == true)
    }

    func testNewRecommendationQueryShowsUnsavedShellWhenNoSavedMatch() throws {
        let controller = SaveSearchController()
        let response = controller.search(query: "推薦新的奶茶店", places: [], localRecords: [])

        XCTAssertEqual(response.fromYourSave.results.count, 0)
        let shell = try XCTUnwrap(response.newRecommendations.results.first)
        XCTAssertEqual(shell.objectType, .newRecommendation)
        XCTAssertEqual(shell.userState, .unsaved)
        XCTAssertEqual(shell.category, .cafe)
        XCTAssertTrue(shell.isRecommendationShell)
        XCTAssertTrue(shell.evidence.contains { $0.contains("no map pin or saved memory") })
    }

    func testCoffeeCravingQueryReturnsNearbyUnsavedCafeCandidate() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "找附近新的咖啡廳",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Quiet Coffee",
                    subtitle: "Irvine, CA",
                    latitude: 33.6846,
                    longitude: -117.8265,
                    category: .cafe,
                    rating: 4.2,
                    reviewCount: 80,
                    sourceURL: "https://maps.google.com/?q=Quiet+Coffee",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map"]
                ),
                SaveMapCandidate(
                    title: "Bright Coffee Bar",
                    subtitle: "Irvine, CA",
                    latitude: 33.6849,
                    longitude: -117.8262,
                    category: .cafe,
                    rating: 4.8,
                    reviewCount: 1200,
                    sourceURL: "https://maps.google.com/?q=Bright+Coffee+Bar",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map"]
                )
            ]
        )

        XCTAssertEqual(response.fromYourSave.results.count, 0)
        XCTAssertEqual(response.newRecommendations.results.first?.title, "Bright Coffee Bar")
        XCTAssertEqual(response.newRecommendations.results.first?.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(response.newRecommendations.results.first?.primaryAction, .savePlace)
        XCTAssertEqual(response.newRecommendations.results.first?.rating, 4.8)
        XCTAssertEqual(response.newRecommendations.results.first?.reviewCount, 1200)
    }

    func testMapCandidatePreparationRecognizesPlaceSearchIntent() {
        let controller = SaveSearchController()

        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "附近咖啡廳"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "咖啡廳"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "餐廳"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "我想找餐廳"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "find restaurants"))
        XCTAssertFalse(controller.shouldPrepareMapCandidates(for: "New York"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "Search nearby unsaved cafes"))
        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "找附近新的咖啡廳"))
        XCTAssertEqual(controller.mapCandidateCategories(for: "咖啡廳"), [.cafe])
        XCTAssertEqual(controller.mapCandidateCategories(for: "search nearby unsaved candidates for 我今天想喝咖啡推薦一家"), [.cafe])
    }

    func testNearbyCafeRecommendationIsSavedFirstBeforeUnsavedSearch() {
        let controller = SaveSearchController()

        XCTAssertTrue(controller.shouldPrepareMapCandidates(for: "推薦我附近咖啡"))
        XCTAssertFalse(controller.shouldSearchNearbyUnsavedCandidatesImmediately(for: "推薦我附近咖啡"))
        XCTAssertFalse(controller.shouldSearchNearbyUnsavedCandidatesImmediately(for: "附近咖啡廳"))

        XCTAssertTrue(controller.shouldSearchNearbyUnsavedCandidatesImmediately(for: "search nearby unsaved cafes"))
        XCTAssertTrue(controller.shouldSearchNearbyUnsavedCandidatesImmediately(for: "找附近新的咖啡廳"))
    }

    func testPlainCafeSearchReturnsSavedAndUnsavedCandidatesWhenPrepared() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "咖啡廳",
            places: [
                place(
                    name: "Saved Coffee",
                    address: "Irvine, CA",
                    category: .cafe
                )
            ],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Unsaved Coffee",
                    subtitle: "Irvine, CA",
                    latitude: 33.6846,
                    longitude: -117.8265,
                    category: .cafe,
                    rating: 4.6,
                    reviewCount: 420,
                    sourceURL: "https://maps.apple.com/?q=Unsaved+Coffee",
                    sourcePlatform: .other,
                    photoURL: "https://example.com/coffee.jpg",
                    distanceMeters: 350,
                    evidence: ["Apple Maps result", "Search: coffee"]
                )
            ]
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Saved Coffee"])
        XCTAssertEqual(response.fromYourSave.results.first?.userState.displayName, "Saved")
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Unsaved Coffee"])
        XCTAssertEqual(response.newRecommendations.results.first?.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(response.newRecommendations.results.first?.userState, .unsaved)
        XCTAssertEqual(response.newRecommendations.results.first?.photoURL, "https://example.com/coffee.jpg")
        XCTAssertEqual(response.newRecommendations.results.first?.distanceLabel, "350 m away")
        XCTAssertTrue(response.assistantMessage?.contains("Saved") == true)
        XCTAssertTrue(response.assistantMessage?.contains("unsaved") == true)
        XCTAssertEqual(response.resolvedAgentAnswer?.source, .deterministic)
        XCTAssertEqual(
            response.resolvedAgentAnswer?.grounding.allowedResultIDs,
            response.fromYourSave.results.map(\.id) + response.newRecommendations.results.map(\.id)
        )
        XCTAssertEqual(SharedPlaceData.from(result: try XCTUnwrap(response.newRecommendations.results.first))?.photoURLs, ["https://example.com/coffee.jpg"])
    }

    @MainActor
    func testDrawerResetClearsPreparedMapCandidates() {
        let drawer = AIDrawerViewModel()
        drawer.query = "咖啡廳"
        drawer.mapCandidates = [
            SaveMapCandidate(
                title: "Unsaved Coffee",
                subtitle: "Irvine, CA",
                latitude: 33.6846,
                longitude: -117.8265,
                category: .cafe
            )
        ]

        drawer.reset()

        XCTAssertEqual(drawer.drawerState, .idle)
        XCTAssertEqual(drawer.query, "")
        XCTAssertTrue(drawer.mapCandidates.isEmpty)
    }

    @MainActor
    func testDrawerNearbyRecommendationUsesGroundedAnswerClient() async {
        let client = StubGroundedAnswerClient(answer: "I would pick Saved Coffee because it matches your saved cafe memory. What budget are you thinking?")
        let drawer = AIDrawerViewModel(groundedAnswerClient: client)
        let savedPlace = place(
            name: "Saved Coffee",
            address: "1 Main St, Irvine, CA",
            category: .cafe
        )
        drawer.places = [savedPlace]
        drawer.query = "coffee"

        await drawer.submit()

        guard case .saveSearchResults(let response) = drawer.drawerState else {
            return XCTFail("Expected save search results")
        }
        XCTAssertEqual(response.assistantMessage, client.answer)
        XCTAssertEqual(response.agentAnswer?.message, client.answer)
        XCTAssertEqual(response.agentAnswer?.source, .groundedLLM)
        XCTAssertEqual(response.agentAnswer?.grounding.allowedResultIDs, ["place-\(savedPlace.id.uuidString)"])
        XCTAssertEqual(client.requests.map(\.query), ["coffee"])
        XCTAssertEqual(client.requests.first?.allowedPlaceIds, ["place-\(savedPlace.id.uuidString)"])
    }

    @MainActor
    func testDrawerPreparedPublicDiscoveryUsesGroundedAnswerClient() async {
        let client = StubGroundedAnswerClient(answer: "I would try Bright Coffee Bar first because it is nearby, highly rated, and still unsaved. Want quiet or quick?")
        let drawer = AIDrawerViewModel(groundedAnswerClient: client)
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.8,
            reviewCount: 1200,
            distanceMeters: 180,
            evidence: ["Apple Maps result"]
        )
        drawer.mapCandidates = [candidate]
        drawer.query = "coffee"

        await drawer.submit()

        guard case .saveSearchResults(let response) = drawer.drawerState else {
            return XCTFail("Expected save search results")
        }
        XCTAssertEqual(response.assistantMessage, client.answer)
        XCTAssertEqual(client.requests.map(\.query), ["coffee"])
        XCTAssertEqual(client.requests.first?.allowedPlaceIds, ["map-candidate-\(candidate.id)"])
        XCTAssertEqual(client.requests.first?.sections.flatMap(\.results).map(\.objectType), [.mapVisibleUnsavedPlace])
    }

    @MainActor
    func testDrawerPreparedPublicDiscoveryKeepsRecommendationPathBounded() async {
        let client = StubGroundedAnswerClient(answer: "I would start with Saved Coffee, then compare Unsaved Coffee as public discovery.")
        let drawer = AIDrawerViewModel(
            locationService: StubAIDrawerLocationProvider(
                currentLocation: CLLocation(latitude: 33.6846, longitude: -117.8265)
            ),
            groundedAnswerClient: client
        )
        let savedPlace = place(
            name: "Saved Coffee",
            address: "1 Main St, Irvine, CA",
            category: .cafe,
            latitude: 33.6847,
            longitude: -117.8266
        )
        let farSavedPlace = place(
            name: "Far Coffee",
            address: "Los Angeles, CA",
            category: .cafe,
            latitude: 34.0522,
            longitude: -118.2437
        )
        let candidate = SaveMapCandidate(
            title: "Unsaved Coffee",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.8,
            reviewCount: 1200,
            distanceMeters: 180,
            evidence: ["Apple Maps result"]
        )
        drawer.places = [farSavedPlace, savedPlace]
        drawer.mapCandidates = [candidate]
        drawer.query = "推薦我附近咖啡"

        await drawer.submit()

        guard case .saveSearchResults(let response) = drawer.drawerState else {
            return XCTFail("Expected save search results")
        }
        XCTAssertEqual(response.fromYourSave.id, "from-your-save-nearby")
        XCTAssertNotEqual(response.fromYourSave.title, "Spatial memory canvas")
        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Saved Coffee"])
        XCTAssertEqual(response.additionalSections.first { $0.id == "saved-but-not-nearby" }?.results.map(\.title), ["Far Coffee"])
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Unsaved Coffee"])
        XCTAssertEqual(client.requests.first?.allowedPlaceIds, ["place-\(savedPlace.id.uuidString)"])
        XCTAssertEqual(client.requests.first?.sections.map(\.id), ["from-your-save-nearby"])
    }

    @MainActor
    func testDrawerSourceOnlyRecordSearchResultOpensFallbackDetail() {
        let drawer = AIDrawerViewModel(
            locationService: StubAIDrawerLocationProvider(currentLocation: nil),
            groundedAnswerClient: nil
        )
        let result = SaveSearchResult(
            id: "record-\(UUID().uuidString)",
            objectType: .sourceOnlyClue,
            userState: .sourceOnly,
            title: "Boba reel clue",
            subtitle: "Needs address confirmation",
            statusLabel: "Clue · needs exact place",
            sourceURL: "https://www.instagram.com/reel/boba/",
            sourcePlatform: .instagram,
            category: .cafe,
            cityOrArea: nil,
            latitude: nil,
            longitude: nil,
            rating: nil,
            reviewCount: nil,
            confidence: nil,
            missingInfo: ["exact place", "coordinates"],
            evidence: ["Caption says milk tea near Irvine"],
            recoveryQueries: [],
            createdAt: Date(),
            canRunRecovery: true,
            isRecommendationShell: false,
            primaryAction: .runRecovery
        )

        drawer.showSearchResult(result)

        guard case .displaying(let response) = drawer.drawerState else {
            return XCTFail("Expected fallback detail message")
        }
        XCTAssertEqual(response.title, "Clue · needs exact place")
        XCTAssertTrue(response.messageText?.contains("Caption says milk tea near Irvine") == true)
        XCTAssertTrue(response.messageText?.contains("Missing: exact place, coordinates") == true)
        XCTAssertTrue(response.messageText?.contains("https://www.instagram.com/reel/boba/") == true)
    }

    @MainActor
    func testDrawerPreparedReviewAndPublicResultsUseGroundedAnswerClient() async {
        let client = StubGroundedAnswerClient(answer: "I would review Review Coffee first, then compare Unsaved Coffee before saving anything. Want a sit-down spot?")
        let drawer = AIDrawerViewModel(groundedAnswerClient: client)
        let reviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Review Coffee",
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.6851,
            longitude: -117.8264,
            evidence: ["Instagram caption mentions coffee"],
            confidence: 0.78,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        let mapCandidate = SaveMapCandidate(
            title: "Unsaved Coffee",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.6,
            reviewCount: 300,
            distanceMeters: 240,
            evidence: ["Apple Maps result"]
        )
        drawer.mapCandidates = [mapCandidate]
        drawer.query = "coffee"

        await drawer.submit(reviewCandidates: [reviewCandidate])

        guard case .saveSearchResults(let response) = drawer.drawerState else {
            return XCTFail("Expected save search results")
        }
        XCTAssertEqual(response.assistantMessage, client.answer)
        XCTAssertEqual(
            Set(client.requests.first?.allowedPlaceIds ?? []),
            Set(["review-candidate-\(reviewCandidate.id.uuidString)", "map-candidate-\(mapCandidate.id)"])
        )
    }

    @MainActor
    func testDrawerReviewOnlyResultsUseGroundedAnswerClient() async {
        let client = StubGroundedAnswerClient(answer: "I found one review candidate: Review Coffee. Confirm the exact place before saving it as a Map Stamp.")
        let drawer = AIDrawerViewModel(groundedAnswerClient: client)
        let reviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Review Coffee",
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.6851,
            longitude: -117.8264,
            evidence: ["Instagram caption mentions coffee"],
            confidence: 0.78,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )
        drawer.query = "coffee"

        await drawer.submit(reviewCandidates: [reviewCandidate])

        guard case .saveSearchResults(let response) = drawer.drawerState else {
            return XCTFail("Expected save search results")
        }
        XCTAssertEqual(response.assistantMessage, client.answer)
        XCTAssertEqual(client.requests.first?.allowedPlaceIds, ["review-candidate-\(reviewCandidate.id.uuidString)"])
    }

    @MainActor
    func testMapSearchClearRemovesUnsavedPinsAndCategoryFilter() {
        let map = MapViewModel()
        let candidate = SaveMapCandidate(
            title: "Unsaved Coffee",
            subtitle: "Irvine, CA",
            latitude: 33.6846,
            longitude: -117.8265,
            category: .cafe
        )
        var route = [
            CLLocationCoordinate2D(latitude: 33.6846, longitude: -117.8265),
            CLLocationCoordinate2D(latitude: 33.6850, longitude: -117.8270)
        ]
        map.mapCandidates = [candidate]
        map.selectedMapCandidate = candidate
        map.selectedCategories = [.cafe]
        map.activeFilter = [UUID()]
        map.routeCoordinates = route
        map.calculatedRoute = MKPolyline(coordinates: &route, count: route.count)

        map.clearMapSearchResults()

        XCTAssertTrue(map.mapCandidates.isEmpty)
        XCTAssertNil(map.selectedMapCandidate)
        XCTAssertTrue(map.selectedCategories.isEmpty)
        XCTAssertNil(map.activeFilter)
        XCTAssertTrue(map.routeCoordinates.isEmpty)
        XCTAssertNil(map.calculatedRoute)
    }

    @MainActor
    func testSelectedApplePOIBecomesEphemeralUnsavedMapCandidateDetail() {
        let map = MapViewModel()
        let coordinate = CLLocationCoordinate2D(latitude: 33.6846, longitude: -117.8265)

        map.selectMapPOI(
            title: "Utopia Euro Caffe",
            coordinate: coordinate,
            pointOfInterestCategory: "MKPOICategoryCafe"
        )

        let candidate = map.selectedMapCandidate
        XCTAssertEqual(candidate?.title, "Utopia Euro Caffe")
        XCTAssertEqual(candidate?.subtitle, "Selected on map")
        XCTAssertEqual(candidate?.category, .cafe)
        XCTAssertTrue(map.mapCandidates.isEmpty)
        XCTAssertTrue(candidate?.evidence.contains("Apple Maps POI") == true)
        XCTAssertNil(map.selectedPlace)
    }

    @MainActor
    func testSelectedApplePOIMatchesSavedPlaceInsteadOfCreatingUnsavedCandidate() {
        let savedPlace = place(
            name: "Utopia Euro Caffe",
            address: "Irvine, CA",
            category: .cafe,
            latitude: 33.6846,
            longitude: -117.8265
        )
        let map = MapViewModel()
        map.places = [savedPlace]

        map.selectMapPOI(
            title: "Utopia Euro Caffe",
            coordinate: CLLocationCoordinate2D(latitude: 33.68461, longitude: -117.82651),
            pointOfInterestCategory: "MKPOICategoryCafe"
        )

        XCTAssertEqual(map.selectedPlace?.id, savedPlace.id)
        XCTAssertNil(map.selectedMapCandidate)
        XCTAssertTrue(map.mapCandidates.isEmpty)
    }

    func testUnsavedMapCandidatesSortByDistanceWhenScoresTie() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "咖啡廳",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Far Coffee",
                    subtitle: "Irvine, CA",
                    latitude: 33.6800,
                    longitude: -117.8200,
                    category: .cafe,
                    distanceMeters: 1_200,
                    evidence: ["Distance: 1.2 km away"]
                ),
                SaveMapCandidate(
                    title: "Near Coffee",
                    subtitle: "Irvine, CA",
                    latitude: 33.6846,
                    longitude: -117.8265,
                    category: .cafe,
                    distanceMeters: 120,
                    evidence: ["Distance: 120 m away"]
                )
            ]
        )

        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Near Coffee", "Far Coffee"])
    }

    func testRestaurantSearchReturnsSavedAndUnsavedCandidatesWhenPrepared() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "我想找餐廳",
            places: [
                place(
                    name: "Saved Sushi",
                    address: "Irvine, CA",
                    category: .food
                )
            ],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Unsaved Ramen",
                    subtitle: "Irvine, CA",
                    latitude: 33.6846,
                    longitude: -117.8265,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 420,
                    sourceURL: "https://maps.apple.com/?q=Unsaved+Ramen",
                    sourcePlatform: .other,
                    evidence: ["Apple Maps result", "Search: restaurant"]
                ),
                SaveMapCandidate(
                    title: "Unsaved Coffee",
                    subtitle: "Irvine, CA",
                    latitude: 33.6848,
                    longitude: -117.8267,
                    category: .cafe,
                    rating: 4.8,
                    reviewCount: 1200,
                    sourceURL: "https://maps.apple.com/?q=Unsaved+Coffee",
                    sourcePlatform: .other,
                    evidence: ["Apple Maps result", "Search: coffee"]
                )
            ]
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Saved Sushi"])
        XCTAssertEqual(response.newRecommendations.results.map(\.title), ["Unsaved Ramen"])
        XCTAssertEqual(response.newRecommendations.results.first?.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(response.newRecommendations.results.first?.userState, .unsaved)
    }

    func testRecommendationSearchIncludesReviewCandidatesAndAssistantMessage() throws {
        let controller = SaveSearchController()
        let reviewRestaurant = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Review Ramen",
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.6851,
            longitude: -117.8264,
            evidence: ["Caption says restaurant near Irvine"],
            confidence: 0.78,
            missingInfo: [],
            status: "pending",
            createdAt: Date()
        )

        let response = controller.search(
            query: "推薦餐廳",
            places: [],
            localRecords: [],
            reviewCandidates: [reviewRestaurant]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.title, "Review Ramen")
        XCTAssertEqual(result.objectType, .pendingCandidate)
        XCTAssertEqual(result.userState, .waitingReview)
        XCTAssertTrue(response.assistantMessage?.contains("Review") == true)
    }

    func testReviewCandidateMilkTeaMatchStaysReviewScoped() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "珍珠奶茶",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .reviewCandidate,
                    sourceURL: "https://www.instagram.com/reel/boba/",
                    title: "Possible boba place",
                    placeName: "Possible Tea Shop",
                    evidence: ["Caption clue: 珍珠奶茶 with fresh taro"]
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.title, "Possible Tea Shop")
        XCTAssertEqual(result.objectType, .pendingCandidate)
        XCTAssertEqual(result.userState, .waitingReview)
        XCTAssertEqual(result.primaryAction, .runRecovery)
    }

    func testSourceOnlyMilkTeaClueRequiresRecovery() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "boba",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/boba-source/",
                    title: "Boba reel clue",
                    evidence: ["Caption says boba near Taipei"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source URL: https://www.instagram.com/reel/boba-source/"],
                        attempts: ["Checked caption text"],
                        missingFields: ["Verified place name", "verified address", "coordinates"],
                        nextBestClue: "Run source recovery search",
                        suggestedSearchQueries: ["boba-source Taipei boba"],
                        recoveryPlan: SocialPlaceEvidenceRecoveryPlan(
                            sourceURL: "https://www.instagram.com/reel/boba-source/",
                            evidenceAtoms: ["source_url: https://www.instagram.com/reel/boba-source/"],
                            queriesToTry: ["boba-source Taipei boba", "Instagram boba-source place"],
                            blockedResultHints: ["creator profile without venue name/address"],
                            requiredEvidence: ["Verified address", "Verified coordinates"],
                            decision: .sourceOnly,
                            allowsDirectSave: false
                        ),
                        rejectedEvidence: [
                            SocialPlaceRejectedEvidence(value: "creator handle", reason: "not venue proof")
                        ]
                    )
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.objectType, .sourceOnlyClue)
        XCTAssertEqual(result.userState, .sourceOnly)
        XCTAssertEqual(result.primaryAction, .runRecovery)
        XCTAssertTrue(result.missingInfo.contains("Verified place name"))
        XCTAssertEqual(result.recoveryQueries, ["boba-source Taipei boba", "Instagram boba-source place"])
        XCTAssertTrue(result.evidence.contains("Recovery status: Source clue"))
        XCTAssertTrue(result.evidence.contains("Next action: Add caption / screenshot / map link"))
        XCTAssertTrue(result.evidence.contains("Recovery decision: sourceOnly; direct save blocked"))
        XCTAssertTrue(result.evidence.contains("Rejected evidence: creator handle — not venue proof"))
    }

    func testSearchPrioritizesSavedPlacesBeforeRecommendationShell() {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "recommend new food in LA",
            places: [
                place(name: "Quarter Sheets Pizza Club", address: "1305 Portia St, Los Angeles, CA", category: .food)
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.map(\.title), ["Quarter Sheets Pizza Club"])
        XCTAssertEqual(response.newRecommendations.results.count, 0)
    }

    func testVisitedPlaceBecomesTriedMemorySearchResult() {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "visited cafe",
            places: [
                place(name: "Tried Coffee", address: "1 Main St, Taipei, Taiwan", category: .cafe, status: .visited),
                place(name: "Want Coffee", address: "2 Main St, Taipei, Taiwan", category: .cafe, status: .wantToGo)
            ],
            localRecords: []
        )

        XCTAssertEqual(response.fromYourSave.results.count, 1)
        XCTAssertEqual(response.fromYourSave.results.first?.title, "Tried Coffee")
        XCTAssertEqual(response.fromYourSave.results.first?.objectType, .triedMemory)
        XCTAssertEqual(response.fromYourSave.results.first?.userState, .visited)
    }

    func testUnsavedMapCandidatesStayCollectibleButNotSaved() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        XCTAssertEqual(result.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(result.userState, .unsaved)
        XCTAssertEqual(result.title, "Sushi Gen")
        XCTAssertEqual(result.rating, 4.6)
        XCTAssertEqual(result.reviewCount, 4100)
        XCTAssertEqual(result.primaryAction, .savePlace)
        XCTAssertFalse(result.isRecommendationShell)
        XCTAssertTrue(result.evidence.contains("Visible on map"))
    }

    func testUnsavedMapCandidateMakesSaveDraftWithMapEvidence() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        let draft = try XCTUnwrap(controller.makeSaveDraft(from: result))

        XCTAssertEqual(draft.title, "Sushi Gen")
        XCTAssertEqual(draft.address, "Little Tokyo · Japanese")
        XCTAssertEqual(draft.latitude, 34.0478)
        XCTAssertEqual(draft.longitude, -118.2386)
        XCTAssertEqual(draft.category, .food)
        XCTAssertEqual(draft.sourceURL, "https://maps.google.com/?q=Sushi+Gen")
        XCTAssertEqual(draft.sourcePlatform, .googleMaps)
        XCTAssertEqual(draft.externalRating, 4.6)
        XCTAssertEqual(draft.externalReviewCount, 4100)
        XCTAssertTrue(draft.evidence.contains("Visible on map"))
    }

    func testSourceOnlyClueCannotMakeSaveDraft() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "instagram",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/example/",
                    title: "Instagram Reel",
                    evidence: ["Source URL: https://www.instagram.com/reel/example/"]
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertNil(controller.makeSaveDraft(from: result))
    }

    func testSaveDraftBecomesPlaceWithoutPrivateRating() async throws {
        let controller = SaveSearchController()
        let draft = SavePlaceDraft(
            title: "Sushi Gen",
            address: "Little Tokyo · Japanese",
            latitude: 34.0478,
            longitude: -118.2386,
            category: .food,
            sourceURL: "https://maps.google.com/?q=Sushi+Gen",
            sourcePlatform: .googleMaps,
            evidence: ["Visible on map"],
            externalRating: 4.6,
            externalReviewCount: 4100
        )

        let place = try await controller.saveMapCandidate(draft)

        XCTAssertEqual(place.name, "Sushi Gen")
        XCTAssertEqual(place.address, "Little Tokyo · Japanese")
        XCTAssertEqual(place.status, .wantToGo)
        XCTAssertNil(place.rating)
        XCTAssertEqual(place.googleRating, 4.6)
        XCTAssertEqual(place.sourceUrl, "https://maps.google.com/?q=Sushi+Gen")
        XCTAssertEqual(place.sourcePlatform, .googleMaps)
        XCTAssertTrue(place.note?.contains("Visible on map") == true)
        XCTAssertTrue(place.note?.contains("External reviews: 4100") == true)
    }

    func testSavedMapCandidateSearchesFromYourSaveAfterSave() async throws {
        let controller = SaveSearchController()
        let draft = SavePlaceDraft(
            title: "Sushi Gen",
            address: "Little Tokyo · Japanese",
            latitude: 34.0478,
            longitude: -118.2386,
            category: .food,
            sourceURL: "https://maps.google.com/?q=Sushi+Gen",
            sourcePlatform: .googleMaps,
            evidence: ["Visible on map"],
            externalRating: 4.6,
            externalReviewCount: 4100
        )
        let place = try await controller.saveMapCandidate(draft)

        let response = controller.search(query: "sushi", places: [place], localRecords: [], mapCandidates: [])
        let result = try XCTUnwrap(response.fromYourSave.results.first)

        XCTAssertEqual(response.newRecommendations.results.count, 0)
        XCTAssertEqual(result.title, "Sushi Gen")
        XCTAssertEqual(result.objectType, .savedPlace)
        XCTAssertEqual(result.userState, .wantToGo)
        XCTAssertEqual(result.userState.displayName, "Saved")
        XCTAssertEqual(result.primaryAction, .recommendOrder)
        XCTAssertEqual(result.rating, 4.6)
    }

    func testSourceOnlyAndReviewRecordsStayReviewScoped() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "instagram review taipei",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/example/",
                    title: "Instagram Reel",
                    evidence: ["Source URL: https://www.instagram.com/reel/example/"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Instagram source"],
                        attempts: ["Checked public metadata"],
                        missingFields: ["place name", "verified address", "coordinates"],
                        nextBestClue: "Share a screenshot with the venue tag"
                    )
                ),
                SaveMemoryRecord(
                    state: .reviewCandidate,
                    sourceURL: "https://www.instagram.com/reel/taipei/",
                    title: "Possible place found",
                    placeName: "東京家庭義大利麵 士林店",
                    address: "Taipei · near Shilin Station",
                    evidence: ["Place name detected from caption"]
                )
            ]
        )

        XCTAssertEqual(response.fromYourSave.results.count, 1)
        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.title, "東京家庭義大利麵 士林店")
        XCTAssertEqual(result.objectType, .pendingCandidate)
        XCTAssertEqual(result.objectType.displayName, "Review Candidate")
        XCTAssertEqual(result.statusLabel, "Review Candidate")
        XCTAssertEqual(result.userState, .waitingReview)
        XCTAssertNil(result.confidence)
        XCTAssertFalse(result.isRecommendationShell)
    }

    func testReviewDraftDefaultsToPrivateAndReceiptReadyWithoutChainWrite() {
        let draft = SavePrivateReviewDraft(
            placeId: UUID(),
            rating: 4.5,
            tags: ["date-night"],
            note: "Would go back.",
            proofRefs: [
                SaveReceiptProofRef(
                    kind: .receiptCommitment,
                    label: "Receipt commitment placeholder",
                    url: nil,
                    commitmentHash: "sha256-placeholder"
                )
            ]
        )

        XCTAssertEqual(draft.visibility, .privateOnly)
        XCTAssertEqual(draft.proofRefs.first?.kind, .receiptCommitment)
        XCTAssertEqual(draft.proofRefs.first?.commitmentHash, "sha256-placeholder")
    }

    func testAgentActionDrawerAdaptsToPlaceMemoryState() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "",
            places: [
                place(
                    name: "Kato",
                    address: "777 S Alameda St, Los Angeles, CA",
                    category: .food,
                    sourceUrl: "https://www.instagram.com/reel/kato/"
                )
            ],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/source-only/",
                    title: "Pasta reel clue",
                    evidence: ["Caption says best pasta in LA"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Instagram source"],
                        attempts: ["Parsed caption"],
                        missingFields: ["exact place", "coordinates"],
                        nextBestClue: "Find tagged venue profile"
                    )
                ),
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "javascript:alert(1)",
                    title: "Malformed source clue",
                    evidence: ["Invalid source URL should not render as a link"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source text"],
                        attempts: ["Parsed source"],
                        missingFields: ["valid source URL"],
                        nextBestClue: "Share the original link"
                    )
                ),
                SaveMemoryRecord(
                    state: .reviewCandidate,
                    sourceURL: "https://www.instagram.com/reel/review-place/",
                    title: "Possible cafe found",
                    placeName: "Dayglow Coffee",
                    address: "Los Angeles, CA",
                    evidence: ["Place name detected from caption"]
                ),
                SaveMemoryRecord(
                    state: .reviewCandidate,
                    sourceURL: "https://maps.google.com/?q=Quarter+Sheets",
                    title: "Map ready candidate",
                    placeName: "Quarter Sheets",
                    address: "1305 Portia St, Los Angeles, CA",
                    evidence: ["Google Places match", "Verified coordinates"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Google Places match", "Verified coordinates"],
                        attempts: ["Checked Google Places"],
                        missingFields: [],
                        nextBestClue: "Confirm map match"
                    ),
                    latitude: 34.083,
                    longitude: -118.254
                )
            ],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map", "Google rating 4.6"]
                )
            ]
        )

        let sourceOnly = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Pasta reel clue" })
        XCTAssertEqual(sourceOnly.objectType.displayName, "Clue")
        XCTAssertEqual(sourceOnly.agentDrawer.primaryAction.kind, .runRecovery)
        XCTAssertEqual(sourceOnly.agentDrawer.heading, "Source clue")
        XCTAssertEqual(sourceOnly.agentDrawer.contextLine, "SAV-E found a source, but not enough proof for a place yet.")
        XCTAssertTrue(sourceOnly.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
        XCTAssertTrue(sourceOnly.agentDrawer.secondaryActions.map(\.kind).contains(.addNote))
        XCTAssertTrue(sourceOnly.agentDrawer.secondaryActions.map(\.kind).contains(.saveClue))
        XCTAssertTrue(sourceOnly.agentDrawer.evidenceSummary.contains("Missing: exact place, coordinates"))

        let malformedSource = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Malformed source clue" })
        XCTAssertFalse(malformedSource.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))

        let weakReviewCandidate = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Dayglow Coffee" })
        XCTAssertEqual(weakReviewCandidate.agentDrawer.heading, "Review before stamping")
        XCTAssertEqual(weakReviewCandidate.agentDrawer.primaryAction.kind, .runRecovery)
        XCTAssertEqual(weakReviewCandidate.agentDrawer.primaryAction.label, "Find exact place")

        let mapReadyCandidate = try XCTUnwrap(response.fromYourSave.results.first { $0.title == "Quarter Sheets" })
        XCTAssertEqual(mapReadyCandidate.agentDrawer.heading, "Review before stamping")
        XCTAssertEqual(mapReadyCandidate.agentDrawer.primaryAction.kind, .confirmMapStamp)
        XCTAssertEqual(mapReadyCandidate.agentDrawer.primaryAction.label, "Confirm Map Stamp")

        let savedPlace = try XCTUnwrap(response.fromYourSave.results.first { $0.objectType == .savedPlace })
        XCTAssertEqual(savedPlace.objectType.displayName, "Map Stamp")
        XCTAssertEqual(savedPlace.agentDrawer.heading, "Saved to your place memory")
        XCTAssertEqual(savedPlace.agentDrawer.contextLine, "Ask what to order, plan around it, or add private notes later.")
        XCTAssertEqual(savedPlace.agentDrawer.primaryAction.kind, .recommendOrder)
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.addToTrip))
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.planAround))
        XCTAssertTrue(savedPlace.agentDrawer.secondaryActions.map(\.kind).contains(.addNote))

        let unsavedMapPlace = try XCTUnwrap(response.newRecommendations.results.first { $0.objectType == .mapVisibleUnsavedPlace })
        XCTAssertEqual(unsavedMapPlace.objectType.displayName, "Not saved yet")
        XCTAssertEqual(unsavedMapPlace.agentDrawer.primaryAction.kind, .savePlace)
        XCTAssertEqual(unsavedMapPlace.agentDrawer.heading, "Not saved yet")
        XCTAssertTrue(unsavedMapPlace.agentDrawer.secondaryActions.map(\.kind).contains(.planAround))
        XCTAssertTrue(unsavedMapPlace.agentDrawer.secondaryActions.map(\.kind).contains(.openSource))
    }

    func testSourceOnlyEvidenceDrawerIncludesMissingFieldsAndRecoveryQuery() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "pasta",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://www.instagram.com/reel/pasta/",
                    title: "Best pasta reel",
                    evidence: ["Caption says best pasta in LA"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source URL: https://www.instagram.com/reel/pasta/"],
                        attempts: ["Checked public metadata/caption text"],
                        missingFields: ["exact venue", "address", "coordinates"],
                        nextBestClue: "Run source recovery search",
                        suggestedSearchQueries: ["best pasta LA instagram reel"]
                    )
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .sourceOnlyClue)
        XCTAssertEqual(drawer.sourcePlatform, .instagram)
        XCTAssertEqual(drawer.missingFields, ["exact venue", "address", "coordinates"])
        XCTAssertEqual(drawer.recoveryQueries, ["best pasta LA instagram reel"])
        XCTAssertTrue(drawer.candidateExplanation?.contains("without creating a Map Stamp") == true)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .caption && $0.value.contains("best pasta in LA") })
    }

    func testUnsavedMapCandidateEvidenceDrawerShowsMapEvidenceWithoutMemoryClaim() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "nearby sushi",
            places: [],
            localRecords: [],
            mapCandidates: [
                SaveMapCandidate(
                    title: "Sushi Gen",
                    subtitle: "Little Tokyo · Japanese",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    rating: 4.6,
                    reviewCount: 4100,
                    sourceURL: "https://maps.google.com/?q=Sushi+Gen",
                    sourcePlatform: .googleMaps,
                    evidence: ["Visible on map"]
                )
            ]
        )

        let result = try XCTUnwrap(response.newRecommendations.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .mapVisibleUnsavedPlace)
        XCTAssertEqual(result.userState, .unsaved)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .rating && $0.value == "4.6" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .reviewCount && $0.value == "4100" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .coordinates && $0.value == "present" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .receipt && $0.value == "Unsaved; not a Map Stamp" })
        XCTAssertEqual(drawer.candidateExplanation, "This is an unsaved candidate, not a Map Stamp yet.")
    }

    func testSavedPlaceEvidenceDrawerIncludesSourcePlatformAndAddress() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "kato",
            places: [
                place(
                    name: "Kato",
                    address: "777 S Alameda St, Los Angeles, CA",
                    category: .food,
                    sourceUrl: "https://www.instagram.com/reel/kato/"
                )
            ],
            localRecords: []
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        let drawer = result.evidenceDrawer

        XCTAssertEqual(result.objectType, .savedPlace)
        XCTAssertEqual(drawer.sourcePlatform, .instagram)
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.label == "Platform" && $0.value == "Instagram" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .address && $0.value == "777 S Alameda St, Los Angeles, CA" })
        XCTAssertTrue(drawer.evidenceAtoms.contains { $0.kind == .receipt && $0.value == "Saved Map Stamp" })
    }

    func testEvidenceDrawerDoesNotTrustLookalikeSourceHost() throws {
        let controller = SaveSearchController()
        let response = controller.search(
            query: "lookalike",
            places: [],
            localRecords: [
                SaveMemoryRecord(
                    state: .sourceOnly,
                    sourceURL: "https://notinstagram.com/reel/source/",
                    title: "Lookalike source",
                    evidence: ["Caption says cafe"],
                    evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                        found: ["Source URL: https://notinstagram.com/reel/source/"],
                        attempts: ["Checked public metadata"],
                        missingFields: ["verified source platform"],
                        nextBestClue: "Share the original social link"
                    )
                )
            ]
        )

        let result = try XCTUnwrap(response.fromYourSave.results.first)
        XCTAssertEqual(result.sourcePlatform, .other)
        XCTAssertNotEqual(result.evidenceDrawer.sourcePlatform, .instagram)
        XCTAssertFalse(result.evidenceDrawer.evidenceAtoms.contains { $0.label == "Platform" && $0.value == "Instagram" })
    }

    func testSavedPlaceShareTextIncludesPlaceBasicsAndLinks() throws {
        let savedPlace = place(
            name: "Kato",
            address: "777 S Alameda St, Los Angeles, CA",
            category: .food,
            sourceUrl: "https://www.instagram.com/reel/kato/",
            note: "Try the tasting menu"
        )

        let shareText = savedPlace.shareText

        XCTAssertTrue(shareText.contains("SAV-E Map Stamp"))
        XCTAssertTrue(shareText.contains("Kato"))
        XCTAssertTrue(shareText.contains("777 S Alameda St, Los Angeles, CA"))
        XCTAssertTrue(shareText.contains("Source: https://www.instagram.com/reel/kato/"))
        XCTAssertTrue(shareText.contains("Open in SAV-E: https://sav-e-app.vercel.app/p/"))
        XCTAssertFalse(shareText.contains("Map fallback: https://maps.apple.com"))
        XCTAssertEqual(savedPlace.saveShareURL?.host, "sav-e-app.vercel.app")
        XCTAssertTrue(savedPlace.saveShareURL?.path.hasPrefix("/p/") == true)
    }

    func testSavedPlaceShareLinkOmitsInternalDiagnostics() throws {
        let savedPlace = place(
            name: "FUGU Japanese Gastropub",
            address: "110台灣臺北市信義區中興里嘉興街30號",
            category: .food,
            sourceUrl: "https://www.instagram.com/reel/DWBZBZFkSyV/",
            note: """
            Source URL: https://www.instagram.com/reel/DWBZBZFkSyV/
            Venue name: FUGU Japanese Gastropub
            Address clue: 110臺北市信義區嘉興街30號
            Analysis pipeline: collected metadata/caption/OCR anchors, scored candidate evidence, and kept unresolved fields for review
            Evidence tier: likely
            Google Places refined match: FUGU Japanese Gastropub
            Google Places coordinates: 25.0318009, 121.5581535
            Bring friends here for izakaya night
            """,
            latitude: 25.0318009,
            longitude: 121.5581535
        )

        let shareText = savedPlace.shareText
        let shareURL = try XCTUnwrap(savedPlace.saveShareURL)
        let payload = try XCTUnwrap(SharedPlaceData.from(url: shareURL))

        XCTAssertTrue(shareText.contains("Note: Bring friends here for izakaya night"))
        XCTAssertFalse(shareText.contains("Analysis pipeline:"))
        XCTAssertFalse(shareText.contains("Google Places coordinates:"))
        XCTAssertEqual(payload.note, "Bring friends here for izakaya night")
        XCTAssertFalse(shareURL.absoluteString.contains("QW5hbHlzaXM"))
        XCTAssertLessThan(shareURL.absoluteString.count, 700)
    }

    func testUnsavedMapCandidateShareTextIncludesRatingReviewsAndMapLink() throws {
        let candidate = SaveMapCandidate(
            title: "Bright Coffee Bar",
            subtitle: "Irvine, CA",
            latitude: 33.6849,
            longitude: -117.8262,
            category: .cafe,
            rating: 4.8,
            reviewCount: 1200,
            sourceURL: "https://maps.google.com/?q=Bright+Coffee+Bar",
            sourcePlatform: .googleMaps,
            evidence: ["Visible on map"]
        )

        let shareText = candidate.shareText

        XCTAssertTrue(shareText.contains("SAV-E Map Result"))
        XCTAssertTrue(shareText.contains("Bright Coffee Bar"))
        XCTAssertTrue(shareText.contains("Rating: 4.8"))
        XCTAssertTrue(shareText.contains("Reviews: 1200"))
        XCTAssertTrue(shareText.contains("Source: https://maps.google.com/?q=Bright+Coffee+Bar"))
        XCTAssertTrue(shareText.contains("Open in SAV-E: https://sav-e-app.vercel.app/p/"))
        XCTAssertFalse(shareText.contains("Map fallback: https://maps.apple.com"))
        XCTAssertEqual(candidate.saveShareURL?.host, "sav-e-app.vercel.app")
        XCTAssertTrue(candidate.saveShareURL?.path.hasPrefix("/p/") == true)
    }

    func testPOICategoryWinsOverTextFallback() {
        XCTAssertEqual(
            PlaceCategory.poiFirst(
                pointOfInterestCategory: .restaurant,
                fallbackText: "Coffee Lab"
            ),
            .food
        )
        XCTAssertEqual(
            PlaceCategory.poiFirst(
                pointOfInterestCategory: .cafe,
                fallbackText: "Dinner Bar"
            ),
            .cafe
        )
        XCTAssertEqual(PlaceCategory.from(googleTypes: ["tourist_attraction"]), .attraction)
        XCTAssertEqual(PlaceCategory.from(googleTypes: ["school", "point_of_interest"]), .attraction)
    }

    func testGooglePlaceTypesDriveSavedReviewCandidateCategory() {
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Bright Coffee Bar",
            address: "123 Main St",
            city: "Irvine",
            latitude: 33.7,
            longitude: -117.8,
            evidence: ["Google Places match"],
            confidence: 0.91,
            missingInfo: [],
            status: "confirmed",
            createdAt: Date()
        )
        let match = GooglePlaceMatch(
            id: "bright-coffee-bar",
            name: "Bright Coffee Bar",
            address: "123 Main St",
            latitude: 33.7,
            longitude: -117.8,
            rating: 4.8,
            priceLevel: 2,
            types: ["cafe", "food", "point_of_interest"]
        )

        let place = Place.from(candidate, refinedMatch: match)

        XCTAssertEqual(place.category, .cafe)
    }

    func testReviewCandidateNameOverrideWinsOverRefinedGoogleMatch() {
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Wrong parsed caption name",
            address: "123 Main St",
            city: "Irvine",
            latitude: nil,
            longitude: nil,
            evidence: ["Google Places match"],
            confidence: 0.91,
            missingInfo: [],
            status: "confirmed",
            createdAt: Date()
        )
        let match = GooglePlaceMatch(
            id: "google-place-id",
            name: "Google Places Business Name",
            address: "123 Main St",
            latitude: 33.7,
            longitude: -117.8,
            rating: 4.8,
            priceLevel: 2,
            types: ["restaurant", "food", "point_of_interest"]
        )

        let place = Place.from(candidate, refinedMatch: match, nameOverride: "My corrected display name")

        XCTAssertEqual(place.name, "My corrected display name")
        XCTAssertEqual(place.googlePlaceId, "google-place-id")
        XCTAssertEqual(place.address, "123 Main St")
    }

    func testBlankReviewCandidateNameOverrideFallsBackToRefinedGoogleMatch() {
        let candidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Wrong parsed caption name",
            address: "123 Main St",
            city: "Irvine",
            latitude: nil,
            longitude: nil,
            evidence: ["Google Places match"],
            confidence: 0.91,
            missingInfo: [],
            status: "confirmed",
            createdAt: Date()
        )
        let match = GooglePlaceMatch(
            id: "google-place-id",
            name: "Google Places Business Name",
            address: "123 Main St",
            latitude: 33.7,
            longitude: -117.8,
            rating: 4.8,
            priceLevel: 2,
            types: ["restaurant", "food", "point_of_interest"]
        )

        let place = Place.from(candidate, refinedMatch: match, nameOverride: "   ")

        XCTAssertEqual(place.name, "Google Places Business Name")
    }

    func testPassportStatsDeriveFromSavedPlaces() {
        let profile = UserProfile.empty
        let places = [
            place(name: "Irvine Coffee", address: "1 Main St, Irvine, CA", category: .cafe, status: .visited),
            place(name: "Irvine Dinner", address: "2 Main St, Irvine, CA", category: .food),
            place(name: "Tokyo Ramen", address: "Shibuya, Tokyo, Japan", category: .food, status: .visited)
        ]

        let stats = PassportStats(profile: profile, savedPlaces: places, waitingClues: 2)

        XCTAssertEqual(stats.savedCount, 3)
        XCTAssertEqual(stats.visitedCount, 2)
        XCTAssertEqual(stats.citiesCount, 2)
        XCTAssertEqual(stats.cityNames, ["Irvine", "Tokyo"])
        XCTAssertEqual(stats.waitingClues, 2)
        XCTAssertTrue(stats.usesSavedPlaces)
    }

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        sourceUrl: String? = nil,
        note: String? = nil,
        extractedDishes: [String]? = nil,
        latitude: Double = 34.0522,
        longitude: Double = -118.2437
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: nil,
            note: note,
            sourceUrl: sourceUrl,
            sourcePlatform: .instagram,
            sourceImageUrl: nil,
            extractedDishes: extractedDishes,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}

private final class StubGroundedAnswerClient: SaveLLMClient {
    let answer: String
    private(set) var requests: [GroundedAnswerRequest] = []

    init(answer: String) {
        self.answer = answer
    }

    func parseIntent(_ request: IntentParseRequest) async throws -> SaveSearchIntent {
        throw SaveSearchIntentValidationError.malformedJSON
    }

    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> String {
        requests.append(request)
        return answer
    }
}

private struct StubAIDrawerLocationProvider: AIDrawerLocationProviding {
    let currentLocation: CLLocation?

    func requestCurrentLocation() async -> CLLocation? {
        currentLocation
    }
}
