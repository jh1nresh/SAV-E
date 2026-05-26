import XCTest
@testable import Wanderly

final class SaveGuideCustomizationControllerTests: XCTestCase {
    func testGuideDraftKeepsStopsAndSuggestsSavedSwaps() {
        let controller = SaveGuideCustomizationController()
        let guide = SaveGuide(
            title: "3 Days in Tokyo Food Guide",
            sourceURL: "https://example.com/tokyo-guide",
            sourcePlatform: .other,
            creatorLabel: "@tokyo_creator",
            cityOrArea: "Tokyo",
            stops: [
                guideStop(title: "Tsukiji Outer Market", address: "Tsukiji, Tokyo", latitude: 35.6654, longitude: 139.7707, category: .food),
                guideStop(title: "Koffee Mameya", address: "4 Chome Jingumae, Tokyo", latitude: 35.6672, longitude: 139.7072, category: .cafe),
                guideStop(title: "teamLab Borderless", address: "Azabudai Hills, Tokyo", latitude: 35.6602, longitude: 139.7409, category: .attraction)
            ],
            evidence: ["Public guide fixture"]
        )
        let saved = [
            place(name: "Onibus Coffee", address: "Meguro, Tokyo", category: .cafe, latitude: 35.6378, longitude: 139.6985),
            place(name: "Ginza Kagari", address: "Ginza, Tokyo", category: .food, latitude: 35.6720, longitude: 139.7650)
        ]

        let draft = controller.customize(guide: guide, savedPlaces: saved)

        XCTAssertEqual(draft.keepStops.count, 3)
        XCTAssertEqual(draft.keepStops.map(\.state), [.guideOnly, .guideOnly, .guideOnly])
        XCTAssertEqual(Set(draft.swapInSavedPlaces.map(\.title)), Set(["Onibus Coffee", "Ginza Kagari"]))
        XCTAssertEqual(draft.originalGuide.creatorLabel, "@tokyo_creator")
        XCTAssertTrue(draft.explanation.contains("saved SAV-E"))
    }

    func testUncertainGuideStopNeedsRecovery() {
        let controller = SaveGuideCustomizationController()
        let guide = SaveGuide(
            title: "Caption-only LA list",
            cityOrArea: "Los Angeles",
            stops: [
                SaveGuideStop(title: "hidden pasta spot", category: .food, evidence: ["Caption clue"])
            ]
        )

        let draft = controller.customize(guide: guide, savedPlaces: [])

        XCTAssertEqual(draft.keepStops.first?.state, .needsRecovery)
        XCTAssertTrue(draft.explanation.contains("1 stops needing recovery"))
    }

    func testAlreadySavedClassificationPreservesGuideAttribution() {
        let controller = SaveGuideCustomizationController()
        let guide = SaveGuide(
            title: "LA food guide",
            sourceURL: "https://example.com/la-food",
            sourcePlatform: .instagram,
            creatorLabel: "@creator",
            cityOrArea: "Los Angeles",
            stops: [
                guideStop(
                    title: "Sushi Gen",
                    address: "422 E 2nd St, Los Angeles, CA",
                    latitude: 34.0478,
                    longitude: -118.2386,
                    category: .food,
                    sourceURL: "https://www.instagram.com/reel/sushi/"
                )
            ]
        )
        let saved = [
            place(name: "Sushi Gen", address: "422 E 2nd St, Los Angeles, CA", category: .food, latitude: 34.0478, longitude: -118.2386)
        ]

        let draft = controller.customize(guide: guide, savedPlaces: saved)

        XCTAssertEqual(draft.keepStops.first?.state, .alreadySaved)
        XCTAssertEqual(draft.keepStops.first?.sourceURL, "https://www.instagram.com/reel/sushi/")
        XCTAssertEqual(draft.originalGuide.sourceURL, "https://example.com/la-food")
    }

    func testCopyGuideToTripCreatesTripStopsNotSavedMemories() {
        let controller = SaveGuideCustomizationController()
        let guide = SaveGuide(
            title: "Tokyo guide",
            sourceURL: "https://example.com/tokyo",
            sourcePlatform: .other,
            creatorLabel: "@creator",
            cityOrArea: "Tokyo",
            stops: [
                guideStop(title: "Tsukiji Outer Market", address: "Tsukiji, Tokyo", latitude: 35.6654, longitude: 139.7707, category: .food),
                SaveGuideStop(title: "unknown dessert shop", category: .food, evidence: ["Caption-only clue"])
            ]
        )
        let draft = controller.customize(guide: guide, savedPlaces: [])

        let trip = controller.makeTripDraft(from: draft)

        XCTAssertEqual(trip.name, "Tokyo guide")
        XCTAssertEqual(trip.city, "Tokyo")
        XCTAssertEqual(trip.places.count, 2)
        XCTAssertTrue(trip.places.first?.note?.contains("Copied from guide: Tokyo guide") == true)
        XCTAssertTrue(trip.places.last?.note?.contains("State: Needs recovery") == true)
    }

    func testNearbyMapCandidatesStayUnsavedSuggestions() {
        let controller = SaveGuideCustomizationController()
        let guide = SaveGuide(
            title: "LA guide",
            cityOrArea: "Los Angeles",
            stops: [
                guideStop(title: "Sushi Gen", address: "422 E 2nd St, Los Angeles, CA", latitude: 34.0478, longitude: -118.2386, category: .food)
            ]
        )

        let draft = controller.customize(
            guide: guide,
            savedPlaces: [],
            nearbyCandidates: [
                SaveMapCandidate(
                    title: "The Geffen Contemporary at MOCA",
                    subtitle: "Little Tokyo · Museum",
                    latitude: 34.0506,
                    longitude: -118.2396,
                    category: .attraction,
                    sourceURL: "https://maps.google.com/?q=moca",
                    sourcePlatform: .googleMaps,
                    evidence: ["Map suggestion"]
                )
            ]
        )

        XCTAssertEqual(draft.addNearbySuggestions.first?.title, "The Geffen Contemporary at MOCA")
        XCTAssertEqual(draft.addNearbySuggestions.first?.origin, .newSuggestion)
        XCTAssertEqual(draft.addNearbySuggestions.first?.sourcePlatform, .googleMaps)
    }

    private func guideStop(
        title: String,
        address: String?,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory,
        sourceURL: String? = nil
    ) -> SaveGuideStop {
        SaveGuideStop(
            title: title,
            address: address,
            latitude: latitude,
            longitude: longitude,
            category: category,
            sourceURL: sourceURL,
            sourcePlatform: sourceURL == nil ? nil : .instagram,
            evidence: ["Guide stop: \(title)"]
        )
    }

    private func place(
        name: String,
        address: String,
        category: PlaceCategory,
        latitude: Double,
        longitude: Double
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
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
}
