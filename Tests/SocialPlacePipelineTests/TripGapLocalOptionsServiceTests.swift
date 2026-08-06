import CoreLocation
import MapKit
import XCTest
@testable import SAVE

final class TripGapLocalOptionsServiceTests: XCTestCase {
    // MARK: - Categories

    @MainActor
    func testCategoriesUnionWhatEachOpenGapNeeds() {
        let categories = TripGapLocalOptionsService.categories(for: [
            gap(.missingLunch),
            gap(.missingCoffeeBreak),
        ])
        XCTAssertEqual(categories, [.food, .cafe])
    }

    @MainActor
    func testHoursCheckGapAsksForNoCandidates() {
        // The stops exist; their hours are unverified. Offering more places
        // would answer a question the user did not ask.
        XCTAssertTrue(TripGapLocalOptionsService.categories(for: [gap(.needsHoursCheck)]).isEmpty)
    }

    @MainActor
    func testRainBackupAsksForIndoorCategories() {
        XCTAssertEqual(
            TripGapLocalOptionsService.categories(for: [gap(.needsRainBackup)]),
            [.attraction, .shopping, .cafe]
        )
    }

    // MARK: - Anchoring

    @MainActor
    func testAnchorIsTheCentroidOfTheStopsTheUserCommittedTo() throws {
        let first = place("A", latitude: 34.00, longitude: -118.00)
        let second = place("B", latitude: 34.10, longitude: -118.20)
        let days = [day(stops: [stop(for: first), stop(for: second)])]

        let anchor = try XCTUnwrap(
            TripGapLocalOptionsService.anchorCoordinate(days: days, savedPlaces: [first, second])
        )
        XCTAssertEqual(anchor.latitude, 34.05, accuracy: 0.0001)
        XCTAssertEqual(anchor.longitude, -118.10, accuracy: 0.0001)
    }

    @MainActor
    func testAnchorIgnoresStopsWithoutCoordinates() throws {
        let located = place("A", latitude: 34.00, longitude: -118.00)
        let unlocated = place("B", latitude: 0, longitude: 0)
        let days = [day(stops: [stop(for: located), stop(for: unlocated)])]

        let anchor = try XCTUnwrap(
            TripGapLocalOptionsService.anchorCoordinate(days: days, savedPlaces: [located, unlocated])
        )
        XCTAssertEqual(anchor.latitude, 34.00, accuracy: 0.0001)
    }

    @MainActor
    func testNoAnchorWhenThePlanHasNoLocatedStop() {
        // Never fall back to the phone's location: a Tokyo plan must not pull
        // suggestions from Taipei because that is where the user is sitting.
        let days = [day(stops: [ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeState: .externalSuggestion,
            placeName: "Somewhere",
            time: nil,
            duration: nil,
            note: nil,
            sourceSummary: nil,
            risks: []
        )])]
        XCTAssertNil(TripGapLocalOptionsService.anchorCoordinate(days: days, savedPlaces: []))
    }

    // MARK: - Fetching

    @MainActor
    func testFetchesNearTheAnchorAndCapsResults() async {
        let anchorPlace = place("A", latitude: 35.0, longitude: 139.0)
        let search = StubCandidateSearch(results: (0..<30).map { candidate("Spot \($0)") })
        let service = TripGapLocalOptionsService(searchService: search)

        let candidates = await service.candidates(
            forGaps: [gap(.missingLunch)],
            days: [day(stops: [stop(for: anchorPlace)])],
            savedPlaces: [anchorPlace]
        )

        XCTAssertEqual(candidates.count, TripGapLocalOptionsService.maximumCandidates)
        XCTAssertEqual(search.receivedCategories, [.food])
        XCTAssertEqual(search.receivedCoordinate?.latitude ?? 0, 35.0, accuracy: 0.0001)
        // Saved places are excluded so the plan never suggests what is already in it.
        XCTAssertEqual(search.receivedExcluded.map(\.id), [anchorPlace.id])
    }

    @MainActor
    func testDoesNotSearchWithoutAnAnchor() async {
        let search = StubCandidateSearch(results: [candidate("Spot")])
        let service = TripGapLocalOptionsService(searchService: search)

        let candidates = await service.candidates(
            forGaps: [gap(.missingLunch)],
            days: [],
            savedPlaces: []
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertFalse(search.didSearch)
    }

    @MainActor
    func testDoesNotSearchWhenNoGapAsksForPlaces() async {
        let anchorPlace = place("A", latitude: 35.0, longitude: 139.0)
        let search = StubCandidateSearch(results: [candidate("Spot")])
        let service = TripGapLocalOptionsService(searchService: search)

        _ = await service.candidates(
            forGaps: [gap(.needsHoursCheck)],
            days: [day(stops: [stop(for: anchorPlace)])],
            savedPlaces: [anchorPlace]
        )

        XCTAssertFalse(search.didSearch)
    }

    // MARK: - The pipe the engine renders

    @MainActor
    func testFetchedCandidatesBecomeApprovalGatedExternalOptions() {
        let anchorPlace = place("A", latitude: 35.0, longitude: 139.0)
        let suggestions = TripGapSuggestionEngine().suggestions(
            for: [gap(.missingLunch)],
            days: [day(stops: [stop(for: anchorPlace)])],
            savedPlaces: [anchorPlace],
            reviewCandidates: [],
            mapCandidates: [candidate("Nearby Ramen", latitude: 35.001, longitude: 139.001)],
            outputLanguage: .english
        )

        let option = suggestions.first?.options.first { $0.source == .externalSuggestion }
        XCTAssertNotNil(option, "public candidates must reach the plan as external suggestions")
        XCTAssertEqual(option?.action, .addExternalWithApproval)
        XCTAssertNil(option?.placeId, "an external suggestion is not a saved place")
        XCTAssertEqual(suggestions.first?.requiresUserApproval, true)
    }

    // MARK: - Helpers

    private final class StubCandidateSearch: MapCandidateSearchServiceProtocol {
        let results: [SaveMapCandidate]
        private(set) var didSearch = false
        private(set) var receivedCategories: Set<PlaceCategory> = []
        private(set) var receivedCoordinate: CLLocationCoordinate2D?
        private(set) var receivedExcluded: [Place] = []

        init(results: [SaveMapCandidate]) { self.results = results }

        func searchCandidates(
            near coordinate: CLLocationCoordinate2D,
            span: MKCoordinateSpan,
            excluding savedPlaces: [Place],
            categories: Set<PlaceCategory>
        ) async -> [SaveMapCandidate] {
            didSearch = true
            receivedCategories = categories
            receivedCoordinate = coordinate
            receivedExcluded = savedPlaces
            return results
        }

        func searchCandidates(
            matching query: String,
            near coordinate: CLLocationCoordinate2D?,
            span: MKCoordinateSpan?,
            excluding savedPlaces: [Place]
        ) async -> [SaveMapCandidate] {
            didSearch = true
            return results
        }
    }

    private func gap(_ type: TripGap.GapType) -> TripGap {
        TripGap(id: "gap-\(type.rawValue)", type: type, dayId: "day-1", severity: .medium, message: "gap")
    }

    private func day(stops: [ItineraryStop]) -> ItineraryDay {
        ItineraryDay(dayNumber: 1, label: "Day 1", stops: stops)
    }

    @MainActor
    private func stop(for place: Place) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: "12:00",
            duration: 60,
            note: nil,
            sourceSummary: nil,
            risks: []
        )
    }

    @MainActor
    private func candidate(
        _ title: String,
        latitude: Double = 35.0,
        longitude: Double = 139.0,
        category: PlaceCategory = .food
    ) -> SaveMapCandidate {
        SaveMapCandidate(
            id: "candidate-\(title)",
            title: title,
            subtitle: "Nearby",
            latitude: latitude,
            longitude: longitude,
            category: category,
            rating: nil,
            reviewCount: nil,
            sourceURL: nil,
            sourcePlatform: nil,
            photoURL: nil,
            businessPhotoURLs: nil,
            distanceMeters: nil,
            evidence: [],
            createdAt: Date()
        )
    }

    @MainActor
    private func place(_ name: String, latitude: Double, longitude: Double) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "1 Main St, Somewhere",
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }

    // MARK: - Diversity: three of the same thing is not a choice

    @MainActor
    func testCollapsesBranchesOfTheSameChain() {
        let result = TripGapLocalOptionsService.diversify(
            [
                candidate("Dreamers Coffee Roasters 光復店", category: .cafe),
                candidate("Dreamers Coffee Roasters 微風復興店", category: .cafe),
                candidate("HOOD COFFEE", category: .cafe),
            ],
            requestedCategories: [.cafe]
        )
        XCTAssertEqual(result.map(\.title), ["Dreamers Coffee Roasters 光復店", "HOOD COFFEE"])
    }

    @MainActor
    func testCollapsesParentheticalBranches() {
        XCTAssertEqual(
            TripGapLocalOptionsService.brandKey(for: "Blue Bottle (Shibuya)"),
            TripGapLocalOptionsService.brandKey(for: "Blue Bottle (Nakameguro)")
        )
    }

    @MainActor
    func testDoesNotLetOneDenseCategoryTakeEverySlot() {
        // The failure seen on the real vault: an afternoon-activity gap asking
        // for attraction/shopping/cafe came back as three cafés.
        var candidates = (0..<10).map { candidate("Cafe \($0)", category: .cafe) }
        candidates.append(candidate("Museum", category: .attraction))
        candidates.append(candidate("Market", category: .shopping))

        let result = TripGapLocalOptionsService.diversify(
            candidates,
            requestedCategories: [.attraction, .shopping, .cafe]
        )

        let categories = Set(result.prefix(3).compactMap(\.category))
        XCTAssertEqual(categories, [.attraction, .shopping, .cafe], "each requested category deserves a slot first")
    }

    @MainActor
    func testDiversifyStillHonoursTheCap() {
        let candidates = (0..<40).map { candidate("Spot \($0)", category: .food) }
        XCTAssertLessThanOrEqual(
            TripGapLocalOptionsService.diversify(candidates, requestedCategories: [.food]).count,
            TripGapLocalOptionsService.maximumCandidates
        )
    }

    @MainActor
    func testCollapsesLatinBranchNamesOntoTheirChain() {
        // Seen on the real vault: "STARBUCKS Beining Shop" and "Starbucks"
        // both offered for the same gap.
        let result = TripGapLocalOptionsService.diversify(
            [
                candidate("STARBUCKS Beining Shop", category: .cafe),
                candidate("EVEN Select Shop", category: .cafe),
                candidate("Starbucks", category: .cafe),
            ],
            requestedCategories: [.cafe]
        )
        XCTAssertEqual(result.map(\.title), ["EVEN Select Shop", "Starbucks"],
                       "the chain name should survive, not the branch name")
    }

    @MainActor
    func testNumberedNamesAreNotTreatedAsBranches() {
        // "Spot 1" is a raw prefix of "Spot 10", but numbering is not branching.
        XCTAssertFalse(TripGapLocalOptionsService.isSameChain("spot 1", "spot 10"))
        XCTAssertTrue(TripGapLocalOptionsService.isSameChain("starbucks", "starbucks beining"))
    }

    @MainActor
    func testDoesNotCollapseDifferentBusinessesSharingAFirstWord() {
        let result = TripGapLocalOptionsService.diversify(
            [
                candidate("Blue Bottle Coffee", category: .cafe),
                candidate("Blue Note Tokyo", category: .bar),
            ],
            requestedCategories: [.cafe, .bar]
        )
        XCTAssertEqual(result.count, 2, "different businesses must not be merged by a shared first word")
    }
}
