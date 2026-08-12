import XCTest
@testable import SAVE

/// Structured opening-hours parsing plus the itinerary hours annotation pass.
@MainActor
final class TripHoursAnnotatorTests: XCTestCase {

    // MARK: - Period parsing

    func testParsesGooglePeriodsIncludingOvernightSpans() {
        let periods = SavePlaceOpeningPeriod.periods(fromGooglePeriods: [
            ["open": ["day": 1, "time": "0900"], "close": ["day": 1, "time": "2100"]],
            ["open": ["day": 5, "time": "2000"], "close": ["day": 6, "time": "0200"]],
        ])

        XCTAssertEqual(periods?.count, 2)
        XCTAssertEqual(periods?[0], SavePlaceOpeningPeriod(day: 1, openMinutes: 540, closeMinutes: 1260))
        // Friday 8 PM → Saturday 2 AM crosses midnight.
        XCTAssertEqual(periods?[1], SavePlaceOpeningPeriod(day: 5, openMinutes: 1200, closeMinutes: 1560))
    }

    func testParsesAlwaysOpenAsSevenDaySpan() {
        let periods = SavePlaceOpeningPeriod.periods(fromGooglePeriods: [
            ["open": ["day": 0, "time": "0000"]],
        ])

        let hours = SavePlaceOpeningHours(periods: periods ?? [])
        XCTAssertTrue(hours.isAlwaysOpen)
        XCTAssertTrue(hours.isOpen(day: 3, atMinutes: 90))
        XCTAssertEqual(hours.weekdaysClosed(atMinutes: 60), [])
    }

    func testRejectsMalformedPeriods() {
        XCTAssertNil(SavePlaceOpeningPeriod.periods(fromGooglePeriods: []))
        XCTAssertNil(SavePlaceOpeningPeriod.periods(fromGooglePeriods: [
            ["open": ["day": 9, "time": "0900"]],
            ["open": ["day": 1, "time": "9am"]],
        ]))
    }

    func testOpenAndClosedEvaluationAcrossWeekdays() {
        // Open 11:00–15:00 every day except Monday (day 1).
        let hours = SavePlaceOpeningHours(periods: (0...6).compactMap { day in
            day == 1 ? nil : SavePlaceOpeningPeriod(day: day, openMinutes: 660, closeMinutes: 900)
        })

        XCTAssertTrue(hours.isOpen(day: 0, atMinutes: 750))
        XCTAssertFalse(hours.isOpen(day: 1, atMinutes: 750))
        XCTAssertEqual(hours.weekdaysClosed(atMinutes: 750), [1])
        XCTAssertEqual(hours.weekdaysClosed(atMinutes: 60).count, 7)
    }

    func testOvernightSpanCoversEarlyMorningOfNextDay() {
        // Saturday 8 PM – Sunday 2 AM.
        let hours = SavePlaceOpeningHours(periods: [
            SavePlaceOpeningPeriod(day: 6, openMinutes: 1200, closeMinutes: 1560),
        ])

        XCTAssertTrue(hours.isOpen(day: 6, atMinutes: 1260))
        XCTAssertTrue(hours.isOpen(day: 0, atMinutes: 60), "1 AM Sunday is inside Saturday's span")
        XCTAssertFalse(hours.isOpen(day: 0, atMinutes: 180))
    }

    // MARK: - Annotation

    func testAnnotationClearsHoursRiskWhenOpenEveryDay() async {
        let place = makePlace("Ramen Bar")
        let response = itineraryResponse(stops: [
            confirmedStop(for: place, time: "12:30 PM"),
        ])
        let annotator = TripHoursAnnotator(hoursProvider: StubHoursProvider(hours: [
            place.id.uuidString: openDaily(from: 660, to: 900),
        ]))

        let annotated = await annotator.annotated(response, places: [place], outputLanguage: .english)

        let stop = annotated.itineraryDays.first?.stops.first
        XCTAssertEqual(stop?.risks.contains(.hoursUnknown), false)
        XCTAssertEqual(stop?.risks.contains(.bookingUnknown), true, "Other risks stay")
        XCTAssertEqual(
            annotated.itineraryDays.first?.health?.warnings.contains { $0.type == .hoursUnknown },
            false
        )
        XCTAssertEqual(annotated.tripHealth?.warnings.contains { $0.type == .hoursUnknown }, false)
    }

    func testAnnotationAddsHoursGapWhenClosedOnSomeWeekday() async {
        let place = makePlace("Closed Mondays Cafe")
        let response = itineraryResponse(stops: [
            confirmedStop(for: place, time: "12:30 PM"),
        ])
        // Open 11:00–15:00 except day 1.
        let annotator = TripHoursAnnotator(hoursProvider: StubHoursProvider(hours: [
            place.id.uuidString: SavePlaceOpeningHours(periods: (0...6).compactMap { day in
                day == 1 ? nil : SavePlaceOpeningPeriod(day: day, openMinutes: 660, closeMinutes: 900)
            }),
        ]))

        let annotated = await annotator.annotated(response, places: [place], outputLanguage: .english)

        let stop = annotated.itineraryDays.first?.stops.first
        XCTAssertEqual(stop?.risks.contains(.hoursUnknown), true, "Closed-some-days stays unverified")
        let gap = annotated.itineraryDays.first?.health?.gaps.first { $0.type == .needsHoursCheck }
        XCTAssertNotNil(gap)
        XCTAssertTrue(gap?.message.contains("Closed Mondays Cafe") ?? false)
        XCTAssertEqual(annotated.tripHealth?.gaps.contains { $0.type == .needsHoursCheck }, true)
    }

    func testAnnotationLeavesUnknownHoursUntouched() async {
        let place = makePlace("Mystery Bar")
        let response = itineraryResponse(stops: [
            confirmedStop(for: place, time: "8:30 PM"),
        ])
        let annotator = TripHoursAnnotator(hoursProvider: StubHoursProvider(hours: [:]))

        let annotated = await annotator.annotated(response, places: [place], outputLanguage: .english)

        XCTAssertEqual(annotated, response, "No hours data → response unchanged")
    }

    func testAnnotationSkipsExternalSuggestionsAndUnparseableTimes() async {
        let place = makePlace("Ramen Bar")
        var external = confirmedStop(for: place, time: "12:30 PM")
        external.placeState = .externalSuggestion
        let noTime = ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: "sometime",
            duration: 60,
            note: nil,
            risks: [.hoursUnknown]
        )
        let response = itineraryResponse(stops: [external, noTime])
        let annotator = TripHoursAnnotator(hoursProvider: StubHoursProvider(hours: [
            place.id.uuidString: openDaily(from: 0, to: 1440),
        ]))

        let annotated = await annotator.annotated(response, places: [place], outputLanguage: .english)

        XCTAssertEqual(annotated, response, "Nothing checkable → response unchanged")
    }

    func testAnnotationSurvivesSlowProviderViaTimeout() async {
        let place = makePlace("Slow Cafe")
        let response = itineraryResponse(stops: [
            confirmedStop(for: place, time: "9:00 AM"),
        ])
        var annotator = TripHoursAnnotator(hoursProvider: NeverRespondingHoursProvider())
        annotator.fetchTimeoutNanoseconds = 50_000_000

        let annotated = await annotator.annotated(response, places: [place], outputLanguage: .english)

        XCTAssertEqual(annotated, response)
    }

    // MARK: - Fixtures

    private func openDaily(from open: Int, to close: Int) -> SavePlaceOpeningHours {
        SavePlaceOpeningHours(periods: (0...6).map {
            SavePlaceOpeningPeriod(day: $0, openMinutes: open, closeMinutes: close)
        })
    }

    private func itineraryResponse(stops: [ItineraryStop]) -> SaveAIResponse {
        let day = ItineraryDay(
            dayNumber: 1,
            label: "Day 1",
            stops: stops,
            health: TripHealth.scored(
                strengths: ["Drafted from confirmed Map Stamps"],
                warnings: [TripWarning(
                    id: "day-1-hours-unknown",
                    type: .hoursUnknown,
                    severity: .low,
                    message: "Opening hours are not verified for every stop.",
                    dayId: "day-1",
                    affectedBlockIds: stops.map(\.id.uuidString)
                )],
                gaps: []
            )
        )
        return SaveAIResponse(
            componentType: .tripItinerary,
            title: "Test Plan",
            placeIds: stops.compactMap(\.placeId),
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [day],
            tripHealth: TripHealth.aggregating([day], strengths: ["Drafted from confirmed Map Stamps"]),
            messageText: nil,
            mapAction: nil,
            aiMessage: nil
        )
    }

    private func confirmedStop(for place: Place, time: String) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: time,
            duration: 60,
            note: nil,
            risks: [.hoursUnknown, .bookingUnknown]
        )
    }

    private func makePlace(_ name: String) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: "Tokyo, Japan",
            latitude: 35.68,
            longitude: 139.76,
            googlePlaceId: "google-\(name)",
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
}

// MARK: - Fakes

private struct StubHoursProvider: TripHoursProviding {
    let hours: [String: SavePlaceOpeningHours]

    func openingHours(for place: Place) async -> SavePlaceOpeningHours? {
        hours[place.id.uuidString]
    }
}

private struct NeverRespondingHoursProvider: TripHoursProviding {
    func openingHours(for place: Place) async -> SavePlaceOpeningHours? {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        return nil
    }
}
