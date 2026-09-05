import XCTest
@testable import SAVE

/// Routes API client + the planner's route-enhanced path. Everything must
/// degrade to the deterministic order when routing is unavailable.
@MainActor
final class TripRouteServiceTests: XCTestCase {

    override func tearDown() {
        StubRoutesURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - GoogleTripRouteService

    func testOptimizedDayReordersIntermediatesAndMapsLegs() async throws {
        let places = [
            makePlace("Start", latitude: 35.0, longitude: 139.0),
            makePlace("Middle A", latitude: 35.1, longitude: 139.1),
            makePlace("Middle B", latitude: 35.2, longitude: 139.2),
            makePlace("End", latitude: 35.3, longitude: 139.3),
        ]
        StubRoutesURLProtocol.handler = { _ in
            (200, [
                "routes": [[
                    "optimizedIntermediateWaypointIndex": [1, 0],
                    "legs": [
                        ["duration": "600s", "distanceMeters": 800],
                        ["duration": "300s", "distanceMeters": 400],
                        ["duration": "900s", "distanceMeters": 1200],
                    ],
                ]],
            ])
        }

        let service = GoogleTripRouteService(
            apiKey: "test-key",
            session: StubRoutesURLProtocol.session()
        )
        let plan = try await service.optimizedDay(places, mode: .walking)

        XCTAssertEqual(plan.orderedPlaces.map(\.name), ["Start", "Middle B", "Middle A", "End"])
        XCTAssertEqual(plan.legs.count, 3)
        XCTAssertEqual(plan.legs[0].durationMinutes, 10)
        XCTAssertEqual(plan.legs[0].distanceMeters, 800)
        XCTAssertEqual(plan.legs[0].fromPlaceId, places[0].id.uuidString)
        XCTAssertEqual(plan.legs[0].toPlaceId, places[2].id.uuidString)
        XCTAssertEqual(plan.legs.map(\.mode), [.walking, .walking, .walking])
    }

    func testOptimizedDayKeepsOrderWhenIndicesInvalid() async throws {
        let places = [
            makePlace("Start", latitude: 35.0, longitude: 139.0),
            makePlace("Middle", latitude: 35.1, longitude: 139.1),
            makePlace("End", latitude: 35.2, longitude: 139.2),
        ]
        StubRoutesURLProtocol.handler = { _ in
            (200, [
                "routes": [[
                    "optimizedIntermediateWaypointIndex": [7],
                    "legs": [
                        ["duration": "60s", "distanceMeters": 100],
                        ["duration": "60s", "distanceMeters": 100],
                    ],
                ]],
            ])
        }

        let service = GoogleTripRouteService(
            apiKey: "test-key",
            session: StubRoutesURLProtocol.session()
        )
        let plan = try await service.optimizedDay(places, mode: .walking)

        XCTAssertEqual(plan.orderedPlaces.map(\.name), ["Start", "Middle", "End"])
        XCTAssertEqual(plan.legs.count, 2)
    }

    func testOptimizedDayRejectsTransit() async {
        let service = GoogleTripRouteService(
            apiKey: "test-key",
            session: StubRoutesURLProtocol.session()
        )
        let places = [
            makePlace("A", latitude: 35.0, longitude: 139.0),
            makePlace("B", latitude: 35.1, longitude: 139.1),
        ]

        do {
            _ = try await service.optimizedDay(places, mode: .transit)
            XCTFail("Expected unsupportedMode")
        } catch {
            XCTAssertEqual(error as? TripRouteServiceError, .unsupportedMode)
        }
    }

    func testOptimizedDayThrowsWithoutKey() async {
        let service = GoogleTripRouteService(
            apiKey: "REPLACE_ME",
            session: StubRoutesURLProtocol.session()
        )
        let places = [
            makePlace("A", latitude: 35.0, longitude: 139.0),
            makePlace("B", latitude: 35.1, longitude: 139.1),
        ]

        do {
            _ = try await service.optimizedDay(places, mode: .walking)
            XCTFail("Expected apiKeyMissing")
        } catch {
            XCTAssertEqual(error as? TripRouteServiceError, .apiKeyMissing)
        }
    }

    func testOptimizedDayThrowsOnAPIError() async {
        StubRoutesURLProtocol.handler = { _ in (403, [:]) }
        let service = GoogleTripRouteService(
            apiKey: "test-key",
            session: StubRoutesURLProtocol.session()
        )
        let places = [
            makePlace("A", latitude: 35.0, longitude: 139.0),
            makePlace("B", latitude: 35.1, longitude: 139.1),
        ]

        do {
            _ = try await service.optimizedDay(places, mode: .driving)
            XCTFail("Expected apiError")
        } catch {
            XCTAssertEqual(error as? TripRouteServiceError, .apiError(403))
        }
    }

    func testOptimizedDayPassesThroughSingleStop() async throws {
        let service = GoogleTripRouteService(
            apiKey: "test-key",
            session: StubRoutesURLProtocol.session()
        )
        let places = [makePlace("Solo", latitude: 35.0, longitude: 139.0)]

        let plan = try await service.optimizedDay(places, mode: .walking)

        XCTAssertEqual(plan.orderedPlaces.map(\.name), ["Solo"])
        XCTAssertTrue(plan.legs.isEmpty)
    }

    // MARK: - DeterministicTripPlanner.routeEnhancedPlan

    func testRouteEnhancedPlanAppliesOptimizedOrderAndLegs() async {
        let places = tokyoDayPlaces()
        let planner = DeterministicTripPlanner()
        let intent = planner.deterministicIntent(from: "Plan one day in Tokyo")
        let baseline = planner.plan(intent: intent, places: places, outputLanguage: .english)
        let baselineStops = baseline?.itineraryDays.first?.stops.map(\.placeName) ?? []
        XCTAssertFalse(baselineStops.isEmpty)

        let service = ReversingFakeRouteService()
        let enhanced = await planner.routeEnhancedPlan(
            intent: intent,
            places: places,
            outputLanguage: .english,
            routeService: service
        )

        let enhancedStops = enhanced?.itineraryDays.first?.stops.map(\.placeName) ?? []
        XCTAssertEqual(enhancedStops.first, baselineStops.first, "Origin stays fixed")
        XCTAssertEqual(enhancedStops.last, baselineStops.last, "Destination stays fixed")
        if baselineStops.count >= 4 {
            XCTAssertEqual(
                Array(enhancedStops.dropFirst().dropLast()),
                Array(baselineStops.dropFirst().dropLast()).reversed(),
                "Intermediates take the service's order"
            )
        }
        XCTAssertEqual(enhanced?.travelLegs.count, max(0, enhancedStops.count - 1))
        // Times are re-derived for the optimized order, so every stop keeps one.
        XCTAssertTrue(enhanced?.itineraryDays.first?.stops.allSatisfy { $0.time != nil } ?? false)
    }

    func testRouteEnhancedPlanFallsBackWhenServiceThrows() async {
        let places = tokyoDayPlaces()
        let planner = DeterministicTripPlanner()
        let intent = planner.deterministicIntent(from: "Plan one day in Tokyo")

        let baseline = planner.plan(intent: intent, places: places, outputLanguage: .english)
        let enhanced = await planner.routeEnhancedPlan(
            intent: intent,
            places: places,
            outputLanguage: .english,
            routeService: ThrowingFakeRouteService()
        )

        XCTAssertEqual(
            enhanced?.itineraryDays.flatMap(\.stops).map(\.placeName),
            baseline?.itineraryDays.flatMap(\.stops).map(\.placeName)
        )
        XCTAssertEqual(enhanced?.travelLegs, [])
    }

    func testRouteEnhancedPlanIgnoresServiceThatDropsPlaces() async {
        let places = tokyoDayPlaces()
        let planner = DeterministicTripPlanner()
        let intent = planner.deterministicIntent(from: "Plan one day in Tokyo")

        let baseline = planner.plan(intent: intent, places: places, outputLanguage: .english)
        let enhanced = await planner.routeEnhancedPlan(
            intent: intent,
            places: places,
            outputLanguage: .english,
            routeService: PlaceDroppingFakeRouteService()
        )

        XCTAssertEqual(
            enhanced?.itineraryDays.flatMap(\.stops).map(\.placeName),
            baseline?.itineraryDays.flatMap(\.stops).map(\.placeName),
            "A route plan that loses places must be discarded"
        )
    }

    // MARK: - Fixtures

    private func tokyoDayPlaces() -> [Place] {
        [
            makePlace("Morning Cafe", latitude: 35.658, longitude: 139.700, category: .cafe),
            makePlace("Shrine Walk", latitude: 35.676, longitude: 139.699, category: .attraction),
            makePlace("Ramen Counter", latitude: 35.660, longitude: 139.702, category: .food),
            makePlace("Design Store", latitude: 35.670, longitude: 139.705, category: .shopping),
            makePlace("Izakaya Dinner", latitude: 35.665, longitude: 139.710, category: .food),
        ]
    }

    func testFixedOrderRequestDoesNotOptimizeMealOrStayOrder() async throws {
        let places = [makePlace("Breakfast"), makePlace("Check out"), makePlace("Lunch")]
        StubRoutesURLProtocol.handler = { request in
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            XCTAssertNotNil(body)
            XCTAssertNil(body?["optimizeWaypointOrder"])
            return (200, ["routes": [["legs": [
                ["duration": "600s", "distanceMeters": 800],
                ["duration": "900s", "distanceMeters": 1200],
            ]]]])
        }
        let service = GoogleTripRouteService(apiKey: "test-key", session: StubRoutesURLProtocol.session())
        let result = try await service.fixedOrderDay(places, mode: .walking)
        XCTAssertEqual(result.orderedPlaces.map(\.id), places.map(\.id))
        XCTAssertEqual(result.legs.map(\.durationMinutes), [10, 15])
    }

    func testPlanTravelMarksRealTimingConflictAndPreservesOrder() async throws {
        let places = [makePlace("Lunch"), makePlace("Museum")]
        let draft = travelDraft(places)
        let result = await SavePlanDraftBuilder.checkingTravel(draft, savedPlaces: places, language: .english,
            routeService: FixedOrderFakeRouteService(minutes: 90))
        XCTAssertEqual(result.itineraryDays[0].stops.map(\.placeId), places.map { Optional($0.id.uuidString) })
        XCTAssertEqual(result.travelLegs.first?.durationMinutes, 90)
        XCTAssertTrue(result.itineraryDays[0].stops[1].risks.contains(.tooFarFromPrevious))
        XCTAssertTrue(result.itineraryDays[0].windowNote?.contains("Travel does not fit") == true)
    }

    func testPlanTravelFallbackKeepsDraftAndNamesUnverifiedTimes() async {
        let places = [makePlace("Lunch"), makePlace("Museum")]
        let draft = travelDraft(places)
        let services: [TripRouteServiceProtocol] = [ThrowingFakeRouteService(), PlaceDroppingFakeRouteService()]
        for service in services {
            let result = await SavePlanDraftBuilder.checkingTravel(draft, savedPlaces: places, language: .english, routeService: service)
            XCTAssertEqual(result.itineraryDays[0].stops, draft.itineraryDays[0].stops)
            XCTAssertTrue(result.travelLegs.isEmpty)
            XCTAssertTrue(result.itineraryDays[0].windowNote?.contains("unverified") == true)
        }
    }

    private func travelDraft(_ places: [Place]) -> SaveAIResponse {
        SaveAIResponse(componentType: .tripItinerary, title: "Day", placeIds: places.map { $0.id.uuidString },
            navigationPlaceId: nil, transportMode: .walking,
            itineraryDays: [ItineraryDay(dayNumber: 1, label: nil, stops: places.enumerated().map { index, place in
                ItineraryStop(id: UUID(), placeId: place.id.uuidString, placeState: .confirmedMapStamp,
                    placeName: place.name, time: index == 0 ? "12:30 PM" : "2:00 PM", duration: 60, note: nil)
            })], messageText: nil, mapAction: nil, aiMessage: nil)
    }

    private func makePlace(
        _ name: String,
        latitude: Double = 35.68,
        longitude: Double = 139.76,
        category: PlaceCategory = .food
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Tokyo, Japan",
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

// MARK: - Fakes

/// Reverses the intermediates and fabricates one leg per consecutive pair.
private struct ReversingFakeRouteService: TripRouteServiceProtocol {
    func optimizedDay(
        _ places: [Place],
        mode: SaveAIResponse.TransportMode
    ) async throws -> TripRouteDayPlan {
        guard places.count >= 2 else { return TripRouteDayPlan(orderedPlaces: places, legs: []) }
        let ordered = [places[0]]
            + Array(places.dropFirst().dropLast()).reversed()
            + [places[places.count - 1]]
        let legs = zip(ordered, ordered.dropFirst()).map { from, to in
            TripTravelLeg(
                fromPlaceId: from.id.uuidString,
                toPlaceId: to.id.uuidString,
                durationMinutes: 12,
                distanceMeters: 900,
                mode: mode
            )
        }
        return TripRouteDayPlan(orderedPlaces: ordered, legs: legs)
    }
}

private struct ThrowingFakeRouteService: TripRouteServiceProtocol {
    func optimizedDay(
        _ places: [Place],
        mode: SaveAIResponse.TransportMode
    ) async throws -> TripRouteDayPlan {
        throw TripRouteServiceError.apiKeyMissing
    }
}

private struct PlaceDroppingFakeRouteService: TripRouteServiceProtocol {
    func optimizedDay(
        _ places: [Place],
        mode: SaveAIResponse.TransportMode
    ) async throws -> TripRouteDayPlan {
        TripRouteDayPlan(orderedPlaces: Array(places.dropLast()), legs: [])
    }
}

// MARK: - URLProtocol stub

private final class StubRoutesURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: Any]))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubRoutesURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, json) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FixedOrderFakeRouteService: TripRouteServiceProtocol {
    let minutes: Int
    func optimizedDay(_ places: [Place], mode: SaveAIResponse.TransportMode) async throws -> TripRouteDayPlan {
        TripRouteDayPlan(orderedPlaces: places, legs: zip(places, places.dropFirst()).map { from, to in
            TripTravelLeg(fromPlaceId: from.id.uuidString, toPlaceId: to.id.uuidString,
                durationMinutes: minutes, distanceMeters: 6000, mode: mode)
        })
    }
}
