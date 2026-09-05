import XCTest
@testable import SAVE

/// Persisting an AI itinerary plan as a Trip: canvas distillation plus the
/// bulk `createTrip(fromPlanNamed:)` store path.
@MainActor
final class TripPlanSaveTests: XCTestCase {

    // MARK: - TripCanvasDraft.tripSaveSelection

    func testSelectionKeepsOnlyConfirmedMapStampsAndCountsExclusions() throws {
        let confirmedA = makePlace("Ramen Bar")
        let confirmedB = makePlace("Museum")
        let draft = TripCanvasDraft(days: [
            ItineraryDay(dayNumber: 1, label: nil, stops: [
                stop(for: confirmedA, time: "12:30 PM", duration: 60, note: "Lunch"),
                externalStop(named: "Public Garden"),
            ]),
            ItineraryDay(dayNumber: 2, label: nil, stops: [
                stop(for: confirmedB, time: "10:30 AM", duration: 90, note: nil),
                reviewCandidateStop(named: "Unverified Cafe"),
            ]),
        ])

        let selection = try draft.tripSaveSelection(availablePlaces: [confirmedA, confirmedB])

        XCTAssertEqual(selection.stops.count, 2)
        XCTAssertEqual(selection.excludedStopCount, 2)

        let first = selection.stops[0]
        XCTAssertEqual(first.placeID, confirmedA.id)
        XCTAssertEqual(first.day, 1)
        XCTAssertEqual(first.orderIndex, 0)
        XCTAssertEqual(first.startTime, "12:30 PM")
        XCTAssertEqual(first.duration, 60)
        XCTAssertEqual(first.note, "Lunch")

        let second = selection.stops[1]
        XCTAssertEqual(second.placeID, confirmedB.id)
        XCTAssertEqual(second.day, 2)
        XCTAssertEqual(second.orderIndex, 0)
    }

    func testSelectionSkipsSkippedStopsAndDeduplicatesPlaces() throws {
        let place = makePlace("Ramen Bar")
        let visible = stop(for: place)
        let skipped = stop(for: makePlace("Skipped Cafe"))
        let duplicate = stop(for: place)
        var draft = TripCanvasDraft(days: [
            ItineraryDay(dayNumber: 1, label: nil, stops: [visible, skipped, duplicate]),
        ])
        draft.skipStop(skipped.id)

        let selection = try draft.tripSaveSelection(availablePlaces: [place])

        XCTAssertEqual(selection.stops.map(\.placeID), [place.id])
        // The duplicate is excluded; the skipped stop is invisible, not excluded.
        XCTAssertEqual(selection.excludedStopCount, 1)
    }

    func testSelectionThrowsWithoutConfirmedMapStamps() {
        let draft = TripCanvasDraft(days: [
            ItineraryDay(dayNumber: 1, label: nil, stops: [externalStop(named: "Public Garden")]),
        ])

        XCTAssertThrowsError(try draft.tripSaveSelection(availablePlaces: [])) { error in
            XCTAssertEqual(error as? TripKmlExportSelectionError, .noConfirmedMapStamps)
        }
    }

    func testSelectionRejectsPlacesMissingFromVault() {
        let vanished = makePlace("Deleted Place")
        let draft = TripCanvasDraft(days: [
            ItineraryDay(dayNumber: 1, label: nil, stops: [stop(for: vanished)]),
        ])

        XCTAssertThrowsError(try draft.tripSaveSelection(availablePlaces: [])) { error in
            XCTAssertEqual(error as? TripKmlExportSelectionError, .noConfirmedMapStamps)
        }
    }

    func testCrossDayStaySurvivesSelectionPersistenceAndReload() async throws {
        let hotel = makePlace("Hotel")
        let draft = TripCanvasDraft(days: [
            ItineraryDay(dayNumber: 1, label: nil, stops: [stop(for: hotel, time: "3:00 PM", duration: 45, note: "Check in")]),
            ItineraryDay(dayNumber: 2, label: nil, stops: [stop(for: hotel, time: "11:00 AM", duration: 30, note: "Check out")]),
        ])
        let selection = try draft.tripSaveSelection(availablePlaces: [hotel])
        XCTAssertEqual(selection.excludedStopCount, 0)
        XCTAssertEqual(selection.stops.map(\.day), [1, 2])
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "test-user", persistence: persistence)
        let trip = await store.createTrip(fromPlanNamed: "Stay", city: "Taipei", stops: selection.stops)
        XCTAssertEqual(trip?.places.map(\.day), [1, 2])
        XCTAssertEqual(trip?.places.map(\.startTime), ["3:00 PM", "11:00 AM"])
        XCTAssertEqual(Set(trip?.places.map(\.id) ?? []).count, 2)
        let reloaded = TripPackStore(userID: "test-user", persistence: persistence)
        await reloaded.load()
        XCTAssertEqual(reloaded.trips.first?.places.map(\.day), [1, 2])
    }

    func testCandidateOnlyPersistsAfterExplicitConfirmation() throws {
        let saved = makePlace("Garden")
        let candidate = SaveMapCandidate(title: "Garden", subtitle: "Taipei", latitude: 25.04, longitude: 121.54, category: .attraction,
            sourceURL: "https://example.com/garden")
        var external = externalStop(named: "Garden", note: "Visit after lunch")
        external.mapCandidate = candidate
        var draft = TripCanvasDraft(days: [ItineraryDay(dayNumber: 2, label: nil, stops: [external])])
        draft.approveExternalStop(external.id)
        XCTAssertThrowsError(try draft.tripSaveSelection(availablePlaces: [saved]))
        draft.confirmExternalStop(external.id, as: saved)
        let selection = try draft.tripSaveSelection(availablePlaces: [saved])
        XCTAssertEqual(selection.stops.map(\.placeID), [saved.id])
        XCTAssertEqual(selection.stops.first?.day, 2)
        XCTAssertEqual(draft.visibleDays.first?.stops.first?.id, external.id)
        XCTAssertEqual(draft.visibleDays.first?.stops.first?.placeState, .confirmedMapStamp)
        XCTAssertEqual(draft.visibleDays.first?.stops.first?.note, external.note)
    }

    // MARK: - TripPackStore.createTrip(fromPlanNamed:)

    func testCreateTripFromPlanPersistsOneSnapshot() async {
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        let placeA = UUID()
        let placeB = UUID()

        let trip = await store.createTrip(
            fromPlanNamed: "  Tokyo Weekend  ",
            city: "Tokyo",
            stops: [
                planStop(placeID: placeA, name: "Ramen Bar", day: 1, order: 0, startTime: "12:30 PM"),
                planStop(placeID: placeB, name: "Museum", day: 2, order: 0, startTime: "10:30 AM"),
            ]
        )

        XCTAssertEqual(trip?.name, "Tokyo Weekend")
        XCTAssertEqual(trip?.city, "Tokyo")
        XCTAssertEqual(trip?.places.count, 2)
        XCTAssertEqual(persistence.saveCalls.count, 1)
        XCTAssertEqual(persistence.saveCalls.first?.places.map(\.placeId), [placeA, placeB])
        XCTAssertEqual(store.selectedTrip?.id, trip?.id)
        XCTAssertEqual(store.state, .saved)
    }

    func testCreateTripFromPlanRejectsEmptyPlan() async {
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "user-1", persistence: persistence)

        let trip = await store.createTrip(fromPlanNamed: "Empty", city: "", stops: [])

        XCTAssertNil(trip)
        XCTAssertTrue(persistence.saveCalls.isEmpty)
        XCTAssertEqual(
            store.state,
            .failed(TripPackStoreError.planHasNoStops.localizedDescription)
        )
    }

    func testCreateTripFromPlanRejectsOversizedPlan() async {
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        let stops = (0..<101).map { index in
            planStop(placeID: UUID(), name: "Stop \(index)", day: 1, order: index)
        }

        let trip = await store.createTrip(fromPlanNamed: "Huge", city: "", stops: stops)

        XCTAssertNil(trip)
        XCTAssertTrue(persistence.saveCalls.isEmpty)
    }

    func testCreateTripFromPlanDropsOverLimitTextInsteadOfFailing() async {
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        let longStartTime = String(repeating: "早", count: 40) // 120 UTF-8 bytes
        let longNote = String(repeating: "n", count: 5000)

        let trip = await store.createTrip(
            fromPlanNamed: "Trim",
            city: "",
            stops: [
                planStop(
                    placeID: UUID(),
                    name: "Ramen Bar",
                    day: 1,
                    order: 0,
                    startTime: longStartTime,
                    note: longNote
                ),
            ]
        )

        XCTAssertEqual(trip?.places.count, 1)
        XCTAssertNil(trip?.places.first?.startTime)
        XCTAssertNil(trip?.places.first?.note)
    }

    func testCreateTripFromPlanRejectsInvalidDuration() async {
        let persistence = PlanFakeTripPersistence()
        let store = TripPackStore(userID: "user-1", persistence: persistence)

        let trip = await store.createTrip(
            fromPlanNamed: "Bad Duration",
            city: "",
            stops: [planStop(placeID: UUID(), name: "Ramen Bar", day: 1, order: 0, duration: 0)]
        )

        XCTAssertNil(trip)
        XCTAssertTrue(persistence.saveCalls.isEmpty)
    }

    func testCreateTripFromPlanSurfacesPersistenceFailure() async {
        let persistence = PlanFakeTripPersistence()
        persistence.saveError = SupabaseError.networkError(URLError(.notConnectedToInternet))
        let store = TripPackStore(userID: "user-1", persistence: persistence)

        let trip = await store.createTrip(
            fromPlanNamed: "Offline",
            city: "",
            stops: [planStop(placeID: UUID(), name: "Ramen Bar", day: 1, order: 0)]
        )

        XCTAssertNil(trip)
        XCTAssertTrue(store.trips.isEmpty)
        if case .failed = store.state {} else {
            XCTFail("Expected failed state, got \(store.state)")
        }
    }

    // MARK: - Fixtures

    private func makePlace(_ name: String) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Tokyo, Japan",
            latitude: 35.68,
            longitude: 139.76,
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

    private func stop(
        for place: Place,
        time: String? = nil,
        duration: Int? = nil,
        note: String? = nil
    ) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: time,
            duration: duration,
            note: note
        )
    }

    private func externalStop(named name: String, note: String? = nil) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeState: .externalSuggestion,
            placeName: name,
            time: nil,
            duration: 60,
            note: note
        )
    }

    private func reviewCandidateStop(named name: String) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: UUID().uuidString,
            placeState: .reviewCandidate,
            placeName: name,
            time: nil,
            duration: 60,
            note: nil
        )
    }

    private func planStop(
        placeID: UUID,
        name: String,
        day: Int,
        order: Int,
        startTime: String? = nil,
        duration: Int? = nil,
        note: String? = nil
    ) -> TripPlanPersistableStop {
        TripPlanPersistableStop(
            placeID: placeID,
            placeName: name,
            day: day,
            orderIndex: order,
            startTime: startTime,
            duration: duration,
            note: note
        )
    }
}

@MainActor
private final class PlanFakeTripPersistence: TripPersisting {
    private(set) var saveCalls: [Trip] = []
    var saveError: Error?

    func fetchTrips(for userId: String) async throws -> [Trip] { saveCalls }

    func saveTrip(_ trip: Trip, userId: String) async throws {
        if let saveError { throw saveError }
        saveCalls.append(trip)
    }

    func updateTrip(_ trip: Trip) async throws {}

    func deleteTrip(_ tripId: UUID) async throws {}
}
