import XCTest
@testable import SAVE

final class SaveDayRhythmSchedulerTests: XCTestCase {
    @MainActor
    func testArrivalBufferDelaysFirstStopAndSkipsBreakfast() {
        var windows = TripPlanWindows.standard
        windows.arrivalMinutes = 14 * 60
        let park = place("City Park", category: .attraction)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [park],
            unsavedCandidates: [],
            lodging: nil,
            dayNumber: 1,
            dayCount: 1,
            windows: windows,
            outputLanguage: .english
        )

        XCTAssertEqual(result.windowNote?.contains("Arrive 2:00 PM"), true)
        let first = try? XCTUnwrap(result.stops.first)
        let start = TripClock.minutes(fromDisplay: first?.time ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(start, 14 * 60 + 90)
        XCTAssertFalse(result.stops.contains(where: { ($0.time ?? "").contains("9:00") }))
    }

    @MainActor
    func testDepartureBufferEndsTheDayBeforeTheFlight() {
        var windows = TripPlanWindows.standard
        windows.departureMinutes = 19 * 60
        let lunch = place("Noodle Shop", category: .food)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [lunch],
            unsavedCandidates: [],
            lodging: nil,
            dayNumber: 1,
            dayCount: 1,
            windows: windows,
            outputLanguage: .english
        )

        XCTAssertEqual(result.windowNote?.contains("depart 7:00 PM"), true)
        for stop in result.stops {
            let start = TripClock.minutes(fromDisplay: stop.time ?? "") ?? 0
            let end = start + (stop.duration ?? 0)
            XCTAssertLessThanOrEqual(end, 19 * 60 - 180)
        }
        XCTAssertFalse(result.stops.contains(where: { ($0.time ?? "").hasPrefix("6:30") }))
    }

    @MainActor
    func testSavedStayBecomesCheckInAndCheckOutNotAMiddayStop() {
        let hotel = place("Riverside Hotel", category: .stay)
        let cafe = place("Morning Cafe", category: .cafe)
        let park = place("Old Town Walk", category: .attraction)
        let scheduler = SaveDayRhythmScheduler()

        let first = scheduler.schedule(
            orderedPlaces: [cafe, park],
            unsavedCandidates: [],
            lodging: hotel,
            dayNumber: 1,
            dayCount: 2,
            windows: .standard,
            outputLanguage: .english
        )
        let last = scheduler.schedule(
            orderedPlaces: [cafe],
            unsavedCandidates: [],
            lodging: hotel,
            dayNumber: 2,
            dayCount: 2,
            windows: .standard,
            outputLanguage: .english
        )

        XCTAssertTrue(first.stops.contains(where: { $0.placeName == "Riverside Hotel" && ($0.note ?? "").contains("check-in") }))
        XCTAssertTrue(last.stops.contains(where: { $0.placeName == "Riverside Hotel" && ($0.note ?? "").contains("check-out") }))
        XCTAssertFalse(first.gaps.contains(where: { $0.type == .missingLodging }))
    }

    @MainActor
    func testMissingStayOnAMultiDayTripIsALodgingGap() {
        let cafe = place("Morning Cafe", category: .cafe)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [cafe],
            unsavedCandidates: [],
            lodging: nil,
            dayNumber: 1,
            dayCount: 3,
            windows: .standard,
            outputLanguage: .english
        )
        XCTAssertTrue(result.gaps.contains(where: { $0.type == .missingLodging }))
    }

    @MainActor
    func testUnsavedAttractionFillsAnEmptyAfternoonAndStaysUnsaved() {
        let lunch = place("Lunch Bowl", category: .food)
        let unsaved = SaveMapCandidate(
            title: "Castle Hill",
            subtitle: "Taipei",
            latitude: 25.03,
            longitude: 121.52,
            category: .attraction
        )
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [lunch],
            unsavedCandidates: [unsaved],
            lodging: nil,
            dayNumber: 1,
            dayCount: 1,
            windows: .standard,
            outputLanguage: .english
        )
        let castle = result.stops.first { $0.placeName == "Castle Hill" }
        XCTAssertEqual(castle?.placeState, .externalSuggestion)
        XCTAssertNil(castle?.placeId)
        XCTAssertEqual(castle?.sourceSummary, "Unsaved Candidate")
    }

    @MainActor
    func testMealsDoNotStackInTheSameWindow() {
        let lunch = place("Lunch Bowl", category: .food)
        let dinner = place("Dinner House", category: .food)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [lunch, dinner],
            unsavedCandidates: [],
            lodging: nil,
            dayNumber: 1,
            dayCount: 1,
            windows: .standard,
            outputLanguage: .english
        )
        let times = result.stops.compactMap { TripClock.minutes(fromDisplay: $0.time ?? "") }
        XCTAssertEqual(times.count, 2)
        XCTAssertNotEqual(times[0], times[1])
        XCTAssertTrue(times.contains { (12 * 60)...(14 * 60 + 30) ~= $0 })
        XCTAssertTrue(times.contains { (18 * 60)...(20 * 60) ~= $0 })
        assertStopsDoNotOverlap(result.stops)
    }

    @MainActor
    func testCheckInDoesNotOverlapAfternoonActivity() {
        let hotel = place("Riverside Hotel", category: .stay)
        let cafe = place("Morning Cafe", category: .cafe)
        let park = place("Old Town Walk", category: .attraction)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [cafe, park],
            unsavedCandidates: [],
            lodging: hotel,
            dayNumber: 1,
            dayCount: 2,
            windows: .standard,
            outputLanguage: .english
        )
        assertStopsDoNotOverlap(result.stops)
        XCTAssertFalse(result.stops.contains(where: {
            $0.placeName == "Riverside Hotel" && ($0.note ?? "").contains("tourist")
        }))
    }

    @MainActor
    func testUnsavedStayFillsCheckInWithoutBecomingAMapStamp() {
        let cafe = place("Morning Cafe", category: .cafe)
        let unsavedStay = SaveMapCandidate(
            title: "Harbor Inn",
            subtitle: "Taipei",
            latitude: 25.05,
            longitude: 121.52,
            category: .stay
        )
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [cafe],
            unsavedCandidates: [unsavedStay],
            lodging: nil,
            dayNumber: 1,
            dayCount: 2,
            windows: .standard,
            outputLanguage: .english
        )
        let inn = result.stops.first { $0.placeName == "Harbor Inn" }
        XCTAssertEqual(inn?.placeState, .externalSuggestion)
        XCTAssertNil(inn?.placeId)
        XCTAssertFalse(result.gaps.contains(where: { $0.type == .missingLodging }))
    }

    @MainActor
    func testOneDayStayIsCheckInOnly() {
        let hotel = place("Riverside Hotel", category: .stay)
        let cafe = place("Morning Cafe", category: .cafe)
        let result = SaveDayRhythmScheduler().schedule(
            orderedPlaces: [cafe],
            unsavedCandidates: [],
            lodging: hotel,
            dayNumber: 1,
            dayCount: 1,
            windows: .standard,
            outputLanguage: .english
        )
        XCTAssertTrue(result.stops.contains(where: {
            $0.placeName == "Riverside Hotel" && ($0.note ?? "").contains("check-in")
        }))
        XCTAssertFalse(result.stops.contains(where: {
            $0.placeName == "Riverside Hotel" && ($0.note ?? "").contains("check-out")
        }))
    }

    @MainActor
    private func assertStopsDoNotOverlap(_ stops: [ItineraryStop], file: StaticString = #filePath, line: UInt = #line) {
        let timed = stops.compactMap { stop -> (Int, Int)? in
            guard let start = TripClock.minutes(fromDisplay: stop.time ?? "") else { return nil }
            return (start, start + (stop.duration ?? 0))
        }.sorted { $0.0 < $1.0 }
        guard timed.count >= 2 else { return }
        for index in 1..<timed.count {
            XCTAssertLessThanOrEqual(timed[index - 1].1, timed[index].0, file: file, line: line)
        }
    }

    @MainActor
    private func place(_ name: String, category: PlaceCategory) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Da'an District, Taipei",
            latitude: 25.04,
            longitude: 121.54,
            category: category,
            status: .wantToGo,
            sourcePlatform: .other,
            createdAt: .distantPast
        )
    }
}
