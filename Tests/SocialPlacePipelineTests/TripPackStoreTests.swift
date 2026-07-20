import XCTest
@testable import SAVE

final class TripPackStoreTests: XCTestCase {
    func testTripWorkspaceBadgeHidesZeroAndCapsLargeCounts() {
        XCTAssertNil(TripWorkspaceBadge.label(for: 0))
        XCTAssertEqual(TripWorkspaceBadge.label(for: 4), "4")
        XCTAssertEqual(TripWorkspaceBadge.label(for: 99), "99")
        XCTAssertEqual(TripWorkspaceBadge.label(for: 100), "99+")
    }

    @MainActor
    func testClassifiesCurrentUpcomingPlanningAndPastAtDayBoundaries() async {
        let calendar = utcCalendar
        let now = date(2026, 7, 19, hour: 12, calendar: calendar)
        let trips = [
            trip(name: "Current", start: date(2026, 7, 19, calendar: calendar), end: date(2026, 7, 19, calendar: calendar)),
            trip(name: "Upcoming", start: date(2026, 7, 20, calendar: calendar), end: date(2026, 7, 22, calendar: calendar)),
            trip(name: "Planning"),
            trip(name: "Past", start: date(2026, 7, 16, calendar: calendar), end: date(2026, 7, 18, hour: 23, calendar: calendar)),
        ]
        let store = TripPackStore(
            userID: "user-1",
            persistence: FakeTripPersistence(trips: trips),
            calendar: calendar,
            nowProvider: { now }
        )

        await store.load()

        XCTAssertEqual(store.currentTrips.map(\.name), ["Current"])
        XCTAssertEqual(store.upcomingTrips.map(\.name), ["Upcoming"])
        XCTAssertEqual(store.planningTrips.map(\.name), ["Planning"])
        XCTAssertEqual(store.pastTrips.map(\.name), ["Past"])
        XCTAssertEqual(store.suggestedTrip?.name, "Current")
        XCTAssertEqual(store.selectedTrip?.name, "Current")
    }

    @MainActor
    func testAddsConfirmedPlaceOnceAndPersistsAcceptedMutation() async throws {
        let initial = trip(name: "Taipei", places: [])
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        let place = makePlace(name: "Fujin Tree 353 Cafe")
        await store.load()

        let didAdd = await store.addConfirmedPlace(place, to: initial.id)
        let didAddDuplicate = await store.addConfirmedPlace(place, to: initial.id)

        XCTAssertTrue(didAdd)
        XCTAssertFalse(didAddDuplicate)

        XCTAssertEqual(persistence.updateCalls.count, 1)
        let saved = try XCTUnwrap(persistence.trips.first)
        XCTAssertEqual(saved.places.map(\.placeId), [place.id])
        XCTAssertEqual(saved.places.map(\.placeName), [place.name])
        XCTAssertNil(saved.places.first?.note, "A Trip Pack must not copy a private memory note")
        XCTAssertEqual(store.state, .saved)
    }

    @MainActor
    func testAddsConfirmedPlaceToRequestedDayAtThatDaysEnd() async throws {
        let existing = makePlace(name: "Existing")
        let added = makePlace(name: "Added")
        let initial = trip(name: "Taipei", places: [stop(existing, day: 3, order: 8)])
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let didAdd = await store.addConfirmedPlace(added, to: initial.id, day: 3)

        XCTAssertTrue(didAdd)
        XCTAssertEqual(persistence.updateCalls.count, 1)
        let dayThree = try XCTUnwrap(persistence.trips.first).places.filter { $0.day == 3 }
        XCTAssertEqual(dayThree.map(\.placeName), [existing.name, added.name])
        XCTAssertEqual(dayThree.map(\.orderIndex), [0, 1])
    }

    @MainActor
    func testCrossDayUpdateAppendsMetadataAndSurvivesReopen() async throws {
        let first = makePlace(name: "First")
        let second = makePlace(name: "Second")
        let third = makePlace(name: "Third")
        let firstStop = stop(first, day: 1, order: 0)
        let initial = trip(
            name: "Tokyo",
            places: [
                firstStop,
                stop(second, day: 1, order: 1),
                stop(third, day: 2, order: 0),
            ]
        )
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let didUpdate = await store.updateStop(
            firstStop.id,
            in: initial.id,
            day: 2,
            startTime: " 09:30 ",
            duration: 75,
            note: " Breakfast stop "
        )

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(persistence.updateCalls.count, 1)

        let reopened = TripPackStore(userID: "user-1", persistence: persistence)
        await reopened.load()
        let saved = try XCTUnwrap(reopened.trips.first)
        XCTAssertEqual(saved.places.map(\.placeName), [second.name, third.name, first.name])
        XCTAssertEqual(saved.places.map(\.day), [1, 2, 2])
        XCTAssertEqual(saved.places.map(\.orderIndex), [0, 0, 1])
        let updated = try XCTUnwrap(saved.places.first { $0.id == firstStop.id })
        XCTAssertEqual(updated.startTime, "09:30")
        XCTAssertEqual(updated.duration, 75)
        XCTAssertEqual(updated.note, "Breakfast stop")
    }

    @MainActor
    func testRemoveStopNormalizesRemainingDayOrder() async throws {
        let first = makePlace(name: "First")
        let removed = makePlace(name: "Removed")
        let last = makePlace(name: "Last")
        let removedStop = stop(removed, day: 2, order: 1)
        let initial = trip(
            name: "Taipei",
            places: [
                stop(first, day: 2, order: 0),
                removedStop,
                stop(last, day: 2, order: 2),
            ]
        )
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let didRemove = await store.removeStop(removedStop.id, from: initial.id)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(persistence.updateCalls.count, 1)
        let dayTwo = try XCTUnwrap(persistence.trips.first).places.filter { $0.day == 2 }
        XCTAssertEqual(dayTwo.map(\.placeName), [first.name, last.name])
        XCTAssertEqual(dayTwo.map(\.orderIndex), [0, 1])
    }

    @MainActor
    func testInvalidStopInputsDoNotPersist() async {
        let existing = makePlace(name: "Existing")
        let newPlace = makePlace(name: "New")
        let existingStop = stop(existing, order: 0)
        let initial = trip(name: "Taipei", places: [existingStop])
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let invalidLowerDayAdd = await store.addConfirmedPlace(newPlace, to: initial.id, day: 0)
        let invalidUpperDayAdd = await store.addConfirmedPlace(newPlace, to: initial.id, day: 366)
        let invalidDayUpdate = await store.updateStop(
            existingStop.id,
            in: initial.id,
            day: 0,
            startTime: nil,
            duration: nil,
            note: nil
        )
        let invalidDurationUpdate = await store.updateStop(
            existingStop.id,
            in: initial.id,
            day: 1,
            startTime: nil,
            duration: 1441,
            note: nil
        )
        let invalidStartTimeUpdate = await store.updateStop(
            existingStop.id,
            in: initial.id,
            day: 1,
            startTime: String(repeating: "時", count: 22),
            duration: nil,
            note: nil
        )
        let invalidNoteUpdate = await store.updateStop(
            existingStop.id,
            in: initial.id,
            day: 1,
            startTime: nil,
            duration: nil,
            note: String(repeating: "記", count: 1_366)
        )

        XCTAssertFalse(invalidLowerDayAdd)
        XCTAssertFalse(invalidUpperDayAdd)
        XCTAssertFalse(invalidDayUpdate)
        XCTAssertFalse(invalidDurationUpdate)
        XCTAssertFalse(invalidStartTimeUpdate)
        XCTAssertFalse(invalidNoteUpdate)
        XCTAssertTrue(persistence.saveCalls.isEmpty)
        XCTAssertTrue(persistence.updateCalls.isEmpty)
        XCTAssertEqual(persistence.trips, [initial])
    }

    @MainActor
    func testReorderNormalizesIndexesAndSurvivesReload() async throws {
        let placeA = makePlace(name: "A")
        let placeB = makePlace(name: "B")
        let placeC = makePlace(name: "C")
        let stopA = stop(placeA, order: 5)
        let stopB = stop(placeB, order: 9)
        let stopC = stop(placeC, order: 12)
        let initial = trip(name: "Ordered", places: [stopC, stopA, stopB])
        let persistence = FakeTripPersistence(trips: [initial])
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let didMove = await store.moveStop(stopB.id, in: initial.id, by: -1)

        XCTAssertTrue(didMove)
        XCTAssertEqual(persistence.updateCalls.count, 1)

        let reopened = TripPackStore(userID: "user-1", persistence: persistence)
        await reopened.load()
        let reloadedTrip = try XCTUnwrap(reopened.trips.first)
        XCTAssertEqual(reloadedTrip.places.map(\.placeName), ["B", "A", "C"])
        XCTAssertEqual(reloadedTrip.places.map(\.orderIndex), [0, 1, 2])
    }

    @MainActor
    func testRapidReordersSerializeFullSnapshotsWithoutLosingLatestOrder() async throws {
        let placeA = makePlace(name: "A")
        let placeB = makePlace(name: "B")
        let placeC = makePlace(name: "C")
        let stopA = stop(placeA, order: 0)
        let initial = trip(
            name: "Rapid",
            places: [stopA, stop(placeB, order: 1), stop(placeC, order: 2)]
        )
        let persistence = FakeTripPersistence(
            trips: [initial],
            updateDelayNanoseconds: 50_000_000
        )
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let firstMove = Task { await store.moveStop(stopA.id, in: initial.id, by: 1) }
        for _ in 0..<100 where persistence.updateCalls.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(persistence.updateCalls.count, 1, "First move should reach the delayed persistence boundary")
        let secondMove = Task { await store.moveStop(stopA.id, in: initial.id, by: 1) }
        let firstResult = await firstMove.value
        let secondResult = await secondMove.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(persistence.updateCalls.count, 2)
        XCTAssertEqual(persistence.updateCalls[0].places.map(\.placeName), ["B", "A", "C"])
        XCTAssertEqual(persistence.updateCalls[1].places.map(\.placeName), ["B", "C", "A"])
        XCTAssertEqual(try XCTUnwrap(persistence.trips.first).places.map(\.placeName), ["B", "C", "A"])
        XCTAssertEqual(try XCTUnwrap(store.trips.first).places.map(\.placeName), ["B", "C", "A"])
    }

    @MainActor
    func testRapidMixedStopMutationsSerializeWithoutLosingChanges() async throws {
        let placeA = makePlace(name: "A")
        let placeB = makePlace(name: "B")
        let placeC = makePlace(name: "C")
        let stopA = stop(placeA, order: 0)
        let stopC = stop(placeC, order: 2)
        let initial = trip(
            name: "Rapid mixed",
            places: [stopA, stop(placeB, order: 1), stopC]
        )
        let persistence = FakeTripPersistence(
            trips: [initial],
            updateDelayNanoseconds: 50_000_000
        )
        let store = TripPackStore(userID: "user-1", persistence: persistence)
        await store.load()

        let move = Task { await store.moveStop(stopA.id, in: initial.id, by: 1) }
        for _ in 0..<100 where persistence.updateCalls.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(persistence.updateCalls.count, 1)

        let update = Task {
            await store.updateStop(
                stopA.id,
                in: initial.id,
                day: 1,
                startTime: "09:30",
                duration: 45,
                note: "Breakfast"
            )
        }
        let moveResult = await move.value
        XCTAssertTrue(moveResult)
        for _ in 0..<100 where persistence.updateCalls.count < 2 {
            await Task.yield()
        }
        XCTAssertEqual(persistence.updateCalls.count, 2)

        let remove = Task { await store.removeStop(stopC.id, from: initial.id) }
        let updateResult = await update.value
        let removeResult = await remove.value
        XCTAssertTrue(updateResult)
        XCTAssertTrue(removeResult)

        XCTAssertEqual(persistence.updateCalls.count, 3)
        XCTAssertEqual(persistence.updateCalls[0].places.map(\.placeName), ["B", "A", "C"])
        XCTAssertEqual(persistence.updateCalls[1].places.map(\.placeName), ["B", "A", "C"])
        XCTAssertEqual(persistence.updateCalls[2].places.map(\.placeName), ["B", "A"])
        let updated = try XCTUnwrap(persistence.updateCalls[2].places.first { $0.id == stopA.id })
        XCTAssertEqual(updated.startTime, "09:30")
        XCTAssertEqual(updated.duration, 45)
        XCTAssertEqual(updated.note, "Breakfast")
        XCTAssertEqual(try XCTUnwrap(persistence.trips.first).places.map(\.placeName), ["B", "A"])
        XCTAssertEqual(try XCTUnwrap(store.trips.first).places.map(\.placeName), ["B", "A"])
    }

    @MainActor
    func testReviewerDemoSeedsConfirmedPlacesAndReopensLocalJSON() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trip-pack-store-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("trip-packs.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let calendar = utcCalendar
        let now = date(2026, 7, 19, hour: 12, calendar: calendar)
        let places = ["Tokyo Cafe", "Tokyo Dinner", "Taipei Cafe", "Taipei Night Market"]
            .map { makePlace(name: $0) }
        let persistence = ReviewDemoTripPersistence(fileURL: fileURL)
        let store = TripPackStore(
            userID: ReviewDemo.userId,
            persistence: persistence,
            calendar: calendar,
            nowProvider: { now }
        )
        await store.load()

        await store.seedReviewerDemoIfNeeded(confirmedPlaces: places)

        XCTAssertEqual(store.currentTrips.count, 1)
        XCTAssertEqual(store.upcomingTrips.count, 1)
        XCTAssertEqual(Set(store.trips.flatMap(\.places).map(\.placeId)), Set(places.map(\.id)))
        XCTAssertEqual(store.state, .saved)

        let reopened = TripPackStore(
            userID: ReviewDemo.userId,
            persistence: ReviewDemoTripPersistence(fileURL: fileURL),
            calendar: calendar,
            nowProvider: { now }
        )
        await reopened.load()

        XCTAssertEqual(reopened.trips.map(\.id), store.trips.map(\.id))
        XCTAssertEqual(reopened.trips.flatMap(\.places).map(\.placeId), store.trips.flatMap(\.places).map(\.placeId))
        XCTAssertEqual(reopened.currentTrips.count, 1)
        XCTAssertEqual(reopened.upcomingTrips.count, 1)
    }

    @MainActor
    func testTripShareUsesOnlyConfirmedPlacesInPlanOrderAndDropsPrivateNotes() throws {
        let first = makePlace(name: "First")
        let second = makePlace(name: "Second")
        let missing = makePlace(name: "Missing")
        let trip = Trip(
            id: UUID(),
            name: "Tokyo",
            city: "Tokyo",
            startDate: nil,
            endDate: nil,
            places: [
                TripStop(id: UUID(), placeId: second.id, placeName: "Spoofed", day: 2, orderIndex: 0, startTime: nil, duration: nil, note: "Private stop note"),
                TripStop(id: UUID(), placeId: missing.id, placeName: missing.name, day: 1, orderIndex: 1, startTime: nil, duration: nil, note: nil),
                TripStop(id: UUID(), placeId: first.id, placeName: first.name, day: 1, orderIndex: 0, startTime: "09:00", duration: nil, note: "Private stop note"),
            ],
            isOptimized: false,
            createdAt: Date()
        )

        let payload = try XCTUnwrap(SharedTripData.from(trip: trip, places: [first, second]))

        XCTAssertEqual(payload.stops.map(\.id), [first.id.uuidString, second.id.uuidString])
        XCTAssertEqual(payload.stops.map(\.name), [first.name, second.name], "Share names come from canonical Map Stamps")
        XCTAssertEqual(payload.stops.map(\.day), [1, 2])
        XCTAssertTrue(payload.stops.allSatisfy { $0.note == nil })

        let url = try XCTUnwrap(payload.toURL())
        let reopened = try XCTUnwrap(SharedTripData.from(url: url))
        XCTAssertEqual(reopened.stops.map(\.id), payload.stops.map(\.id))
        XCTAssertEqual(reopened.stops.map(\.day), [1, 2])
    }

    @MainActor
    func testTripShareDecoderKeepsLegacyLinksAndRejectsUnresolvedCoordinates() throws {
        let legacy = LegacyTripSharePayload(
            name: "Legacy",
            city: "Taipei",
            stops: [LegacyTripShareStop(
                id: UUID().uuidString,
                name: "Cafe",
                address: "Taipei",
                lat: 25.03,
                lng: 121.56,
                time: nil,
                note: nil
            )]
        )
        let legacyURL = try XCTUnwrap(ShareRouteCodec.url(
            for: legacy,
            baseURL: SaveShareLinkConfig.tripBaseURL
        ))
        let decoded = try XCTUnwrap(SharedTripData.from(url: legacyURL))
        XCTAssertNil(decoded.stops.first?.day)
        XCTAssertNil(decoded.stops.first?.order)

        let unresolved = LegacyTripSharePayload(
            name: "Unresolved",
            city: "",
            stops: [LegacyTripShareStop(
                id: UUID().uuidString,
                name: "Unknown",
                address: "",
                lat: 0,
                lng: 0,
                time: nil,
                note: nil
            )]
        )
        let unresolvedURL = try XCTUnwrap(ShareRouteCodec.url(
            for: unresolved,
            baseURL: SaveShareLinkConfig.tripBaseURL
        ))
        XCTAssertNil(SharedTripData.from(url: unresolvedURL))
    }

    @MainActor
    func testTripShareBoundaryNeverCreatesALinkItCannotReopen() throws {
        var lastAcceptedURL: URL?
        var firstRejectedPayload: SharedTripData?

        for addressLength in stride(from: 0, through: 320, by: 8) {
            let stops = (0..<50).map { index in
                SharedTripData.SharedStop(
                    id: UUID().uuidString,
                    name: "Stop \(index)",
                    address: String(repeating: "x", count: addressLength),
                    lat: 25.03 + Double(index) / 10_000,
                    lng: 121.56 + Double(index) / 10_000,
                    time: nil,
                    note: nil,
                    day: 1,
                    order: index
                )
            }
            let payload = SharedTripData(name: "Boundary", city: "Taipei", stops: stops)
            if let url = payload.toURL() {
                lastAcceptedURL = url
                XCTAssertLessThanOrEqual(
                    url.lastPathComponent.count,
                    ShareRoutePayloadLimits.embeddedTokenMaxCharacters
                )
                XCTAssertNotNil(SharedTripData.from(url: url))
            } else {
                firstRejectedPayload = payload
                break
            }
        }

        XCTAssertNotNil(lastAcceptedURL)
        let rejected = try XCTUnwrap(firstRejectedPayload)
        XCTAssertGreaterThan(
            try JSONEncoder().encode(rejected).count,
            ShareRoutePayloadLimits.tripPayloadMaxBytes
        )
    }

    @MainActor
    func testReviewerDemoKMLUsesConfirmedPlacesInOrderWithoutPrivateNotes() throws {
        let first = makePlace(name: "A & B", address: "1 <Tokyo>")
        let second = makePlace(name: "Second", address: "2 Tokyo")

        let data = try TripKMLExportService.reviewerDemoData(
            placeIDs: [second.id, first.id],
            places: [first, second]
        )
        let document = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertLessThan(
            try XCTUnwrap(document.range(of: "Second")).lowerBound,
            try XCTUnwrap(document.range(of: "A &amp; B")).lowerBound
        )
        XCTAssertTrue(document.contains("1 &lt;Tokyo&gt;"))
        XCTAssertTrue(document.contains("139.6503,35.6762,0"))
        XCTAssertFalse(document.contains("Private memory"))
    }

    @MainActor
    func testTripRoutePlacesIgnorePreviousCategoryFilterAndKeepPlanOrder() {
        let cafe = makePlace(name: "Cafe", category: .cafe)
        let dinner = makePlace(name: "Dinner", category: .food)
        let map = MapViewModel()
        map.places = [dinner, cafe]
        map.selectedCategories = [.cafe]

        XCTAssertEqual(map.filteredPlaces.map(\.id), [cafe.id])
        XCTAssertEqual(
            map.placesForRoute(placeIDs: [cafe.id, dinner.id]).map(\.id),
            [cafe.id, dinner.id]
        )
    }

    @MainActor
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor
    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @MainActor
    private func trip(
        name: String,
        start: Date? = nil,
        end: Date? = nil,
        places: [TripStop] = []
    ) -> Trip {
        Trip(
            id: UUID(),
            name: name,
            city: "",
            startDate: start,
            endDate: end,
            places: places,
            isOptimized: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @MainActor
    private func stop(_ place: Place, day: Int = 1, order: Int) -> TripStop {
        TripStop(
            id: UUID(),
            placeId: place.id,
            placeName: place.name,
            day: day,
            orderIndex: order,
            startTime: nil,
            duration: nil,
            note: nil
        )
    }

    @MainActor
    private func makePlace(
        name: String,
        address: String = "Tokyo, Japan",
        category: PlaceCategory = .food
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: 35.6762,
            longitude: 139.6503,
            googlePlaceId: nil,
            category: category,
            status: .wantToGo,
            rating: nil,
            note: "Private memory",
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            businessPhotoUrls: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct LegacyTripSharePayload: Codable {
    let name: String
    let city: String
    let stops: [LegacyTripShareStop]
}

private struct LegacyTripShareStop: Codable {
    let id: String
    let name: String
    let address: String
    let lat: Double
    let lng: Double
    let time: String?
    let note: String?
}

@MainActor
private final class FakeTripPersistence: TripPersisting {
    var trips: [Trip]
    private(set) var saveCalls: [Trip] = []
    private(set) var updateCalls: [Trip] = []
    private(set) var deleteCalls: [UUID] = []
    private let updateDelayNanoseconds: UInt64

    init(trips: [Trip] = [], updateDelayNanoseconds: UInt64 = 0) {
        self.trips = trips
        self.updateDelayNanoseconds = updateDelayNanoseconds
    }

    func fetchTrips(for userId: String) async throws -> [Trip] {
        trips
    }

    func saveTrip(_ trip: Trip, userId: String) async throws {
        saveCalls.append(trip)
        trips.append(trip)
    }

    func updateTrip(_ trip: Trip) async throws {
        updateCalls.append(trip)
        if updateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        }
    }

    func deleteTrip(_ tripId: UUID) async throws {
        deleteCalls.append(tripId)
        trips.removeAll { $0.id == tripId }
    }
}
