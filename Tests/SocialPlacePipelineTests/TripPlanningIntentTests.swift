import XCTest
@testable import SAVE

@MainActor
final class TripPlanningIntentValidatorTests: XCTestCase {
    private let validator = TripIntentJSONValidator()

    func testParsesDaysAndTerms() throws {
        let intent = try validator.parse(#"{"days":2,"searchTerms":["taipei","food"]}"#, rawQuery: "weekend in Taipei")

        XCTAssertEqual(intent.days, 2)
        XCTAssertEqual(intent.searchTerms, ["taipei", "food"])
        XCTAssertEqual(intent.rawMessage, "weekend in Taipei")
    }

    func testNullDaysMeansLetThePlannerDecide() throws {
        let intent = try validator.parse(#"{"days":null,"searchTerms":[]}"#, rawQuery: "plan a trip")

        XCTAssertNil(intent.days)
        XCTAssertFalse(intent.hasSpecificRequest)
    }

    func testClampsAbsurdDayCounts() throws {
        XCTAssertEqual(try validator.parse(#"{"days":365}"#, rawQuery: "").days, 7)
        XCTAssertEqual(try validator.parse(#"{"days":0}"#, rawQuery: "").days, 1)
        XCTAssertEqual(try validator.parse(#"{"days":-4}"#, rawQuery: "").days, 1)
    }

    func testDropsJunkTermsAndCapsTheList() throws {
        let json = #"{"days":1,"searchTerms":["Taipei","  ","taipei","food","cafe","bar","attraction","shopping","stay","aVeryLongTermThatNoPlaceNameWouldEverMatchInPractice"]}"#

        let terms = try validator.parse(json, rawQuery: "").searchTerms

        // Lowercased, deduped, blank and overlong dropped, capped.
        XCTAssertEqual(terms, ["taipei", "food", "cafe", "bar", "attraction", "shopping"])
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try validator.parse("not json at all", rawQuery: "x"))
    }

    func testToleratesMissingFields() throws {
        let intent = try validator.parse("{}", rawQuery: "plan a trip")

        XCTAssertNil(intent.days)
        XCTAssertEqual(intent.searchTerms, [])
    }
}

@MainActor
final class SavePlanConversationConditionsTests: XCTestCase {
    func testSixDayConversationUsesCityFromRealSavedAddressSuffix() throws {
        let places = ReviewDemoSeed.places()
        let areas = SavePlanDraftBuilder.areas(from: places)
        XCTAssertTrue(areas.contains("Taipei"))
        var conditions = SavePlanConversationConditions()
        for answer in ["日本旅行6天五夜", "Taipei", "relaxed", "no time constraints"] {
            conditions.receive(answer, areas: areas)
        }
        XCTAssertNil(conditions.clarification(language: .english))
        let request = try XCTUnwrap(conditions.request(language: .english))
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: places))
        XCTAssertEqual(draft.itineraryDays.count, 6)
        XCTAssertTrue(draft.placeIds.allSatisfy { id in
            places.contains { $0.id.uuidString == id && $0.address.contains("Taipei") }
        })
    }

    func testJapanSixDaysAsksForCityWithoutSelectingSavedTaipei() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("日本旅行6天五夜", areas: ["Taipei"])
        XCTAssertEqual(conditions.days, 6)
        XCTAssertNil(conditions.area)
        XCTAssertNil(conditions.pace)
        XCTAssertTrue(conditions.clarification(language: .traditionalChinese)?.contains("6 天") == true)
        XCTAssertNil(conditions.request(language: .english))
    }

    func testLatestAnswersCompleteOnlyAfterExplicitClockChoice() throws {
        var conditions = SavePlanConversationConditions()
        conditions.receive("臺北", areas: ["Taipei"])
        conditions.receive("6", areas: ["Taipei"])
        conditions.receive("緊湊", areas: ["Taipei"])
        XCTAssertNil(conditions.request(language: .english))
        XCTAssertTrue(conditions.clarification(language: .english)?.contains("start") == true)
        conditions.receive("不用", areas: ["Taipei"])
        let request = try XCTUnwrap(conditions.request(language: .english))
        XCTAssertEqual(request.area, "Taipei")
        XCTAssertEqual(request.days, 6)
        XCTAssertEqual(request.pace, .packed)
        XCTAssertNil(request.arrivalMinutes)
        XCTAssertNil(request.departureMinutes)
        XCTAssertFalse(request.usesFlightBuffers)
    }

    func testUnknownCitySwitchNeverUsesPreviousCity() {
        for next in ["改去京都", "京都", "京都6天", "日本旅行6天五夜", "不要台北，改去京都"] {
            var conditions = completed()
            conditions.receive(next, areas: ["Taipei"])
            XCTAssertNil(conditions.area, next)
            XCTAssertNil(conditions.request(language: .english), next)
            XCTAssertNotNil(conditions.clarification(language: .english), next)
            XCTAssertNotNil(conditions.days, next)
        }
    }

    func testUnknownCityAnswerHasAnActionableSavedPlaceExplanation() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("東京", areas: ["Taipei"])
        XCTAssertEqual(conditions.unmatchedDestination, "東京")
        XCTAssertTrue(conditions.clarification(language: .english)?.contains("saved places") == true)
    }

    func testEquivalentTaipeiLabelsAreNotMultipleCities() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("台北市", areas: ["Taipei", "臺北市"])
        XCTAssertNotNil(conditions.area)
        conditions.receive("不要台北", areas: ["Taipei"])
        XCTAssertNil(conditions.area)
    }

    func testDurationNeverSilentlyClampsOrTreatsLastDayAsTripLength() {
        var conditions = completed()
        conditions.receive("20天", areas: ["Taipei"])
        XCTAssertNil(conditions.days)
        XCTAssertEqual(conditions.unsupportedDays, 20)
        conditions.receive("六天五夜", areas: ["Taipei"])
        XCTAssertEqual(conditions.days, 6)
        conditions.receive("最後一天 18:00 結束", areas: ["Taipei"])
        XCTAssertEqual(conditions.days, 6)
        conditions.receive("2.5天", areas: ["Taipei"])
        XCTAssertNil(conditions.days)
    }

    func testClockCorrectionsUseLatestExplicitTimeAndPreserveArea() {
        var conditions = completed()
        conditions.receive("開始 14:00，結束 19:00", areas: ["Taipei"])
        conditions.receive("改成開始 16:00", areas: ["Taipei"])
        XCTAssertEqual(conditions.area, "Taipei")
        XCTAssertEqual(conditions.arrivalMinutes, 16 * 60)
        XCTAssertEqual(conditions.departureMinutes, 19 * 60)
        conditions.receive("出發日本6天", areas: ["Taipei"])
        XCTAssertEqual(conditions.arrivalMinutes, 16 * 60)
        conditions.receive("開始 25:00", areas: ["Taipei"])
        XCTAssertFalse(conditions.arrivalAnswered)
        XCTAssertNil(conditions.request(language: .english))
    }

    func testOneRemainingClockCanBeAnsweredDirectlyOrSkipped() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("台北3天輕鬆", areas: ["Taipei"])
        conditions.receive("開始 14:00", areas: ["Taipei"])
        conditions.receive("19:00", areas: ["Taipei"])
        XCTAssertEqual(conditions.arrivalMinutes, 840)
        XCTAssertEqual(conditions.departureMinutes, 1140)
        var skipped = SavePlanConversationConditions()
        skipped.receive("台北3天輕鬆", areas: ["Taipei"])
        skipped.receive("開始 14:00", areas: ["Taipei"])
        skipped.receive("不用", areas: ["Taipei"])
        XCTAssertEqual(skipped.arrivalMinutes, 840)
        XCTAssertNil(skipped.departureMinutes)
        XCTAssertNotNil(skipped.request(language: .english))
    }

    func testNoTimeLimitAnswersDoNotBecomeDestinations() {
        for answer in ["沒有", "沒有時間限制", "no constraints", "none"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive("Taipei 3 days relaxed", areas: ["Taipei"])
            conditions.receive(answer, areas: ["Taipei"])
            XCTAssertNotNil(conditions.request(language: .english), answer)
            XCTAssertEqual(conditions.area, "Taipei", answer)
        }
    }

    func testInvalidOneDayWindowAsksForCorrectionWithoutBuilding() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("Taipei 1 day relaxed", areas: ["Taipei"])
        conditions.receive("start 18:00, end by 14:00", areas: ["Taipei"])
        XCTAssertNil(conditions.request(language: .english))
        conditions.receive("20:00", areas: ["Taipei"])
        XCTAssertEqual(conditions.departureMinutes, 1200)
        XCTAssertNotNil(conditions.request(language: .english))
    }

    func testPaceAnswersAreConsistentAndNegationIsNotOldPreference() {
        var conditions = completed()
        conditions.receive("easy", areas: ["Taipei"])
        XCTAssertEqual(conditions.pace, .relaxed)
        conditions.receive("不要輕鬆，排滿", areas: ["Taipei"])
        XCTAssertEqual(conditions.pace, .packed)
        conditions.receive("relaxed or packed", areas: ["Taipei"])
        XCTAssertNil(conditions.pace)
    }

    func testThinVaultKeepsSixDaysAndNeverUsesOtherCity() throws {
        let taipei = place("Taipei Museum", address: "Taipei")
        let kyoto = place("Kyoto Museum", address: "Kyoto")
        let request = SavePlanRequest(area: "Taipei", days: 6, pace: .relaxed,
                                      arrivalMinutes: nil, departureMinutes: nil, language: .english)
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: [taipei, kyoto]))
        XCTAssertEqual(draft.itineraryDays.map(\.dayNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(draft.title?.contains("6 days") == true)
        XCTAssertTrue(draft.itineraryDays.contains(where: { $0.stops.isEmpty }))
        XCTAssertFalse(draft.placeIds.contains(kyoto.id.uuidString))
        XCTAssertTrue(draft.itineraryDays.allSatisfy { $0.stops.count <= ItineraryPace.relaxed.maxStopsPerDay })
    }

    func testPolishCannotShortenOrReplaceConfirmedSchedule() throws {
        let saved = place("Taipei Museum", address: "Taipei")
        let request = SavePlanRequest(area: "Taipei", days: 6, pace: .relaxed,
                                      arrivalMinutes: 14 * 60, departureMinutes: 19 * 60, language: .english,
                                      usesFlightBuffers: false)
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: [saved]))
        let shortened = draft.replacingItineraryDays(Array(draft.itineraryDays.prefix(1)), tripHealth: nil)
        XCTAssertEqual(SavePlanDraftBuilder.preservingSchedule(shortened, draft: draft), draft)
        let different = ItineraryStop(id: UUID(), placeId: UUID().uuidString,
                                     placeName: "Other city", time: "9:00 AM", duration: 60, note: nil)
        let changed = draft.replacingItineraryDays(draft.itineraryDays.map {
            ItineraryDay(dayNumber: $0.dayNumber, label: $0.label, stops: [different])
        }, tripHealth: nil)
        XCTAssertEqual(SavePlanDraftBuilder.preservingSchedule(changed, draft: draft), draft)
        XCTAssertEqual(SavePlanDraftBuilder.preservingSchedule(draft, draft: draft), draft)
    }

    func testPlaceActionStagesWithoutSubmittingOrLosingDraft() throws {
        let saved = place("Taipei Museum", address: "Taipei")
        let conversation = SavePlanConversation()
        conversation.draft = SavePlanDraftBuilder.draft(
            request: SavePlanRequest(area: "Taipei", days: 2, pace: .balanced,
                                     arrivalMinutes: nil, departureMinutes: nil, language: .english),
            savedPlaces: [saved]
        )
        let previous = try XCTUnwrap(conversation.draft)
        conversation.stage(place: saved, addingToTrip: false, language: .english)
        XCTAssertEqual(conversation.anchorPlaceID, saved.id)
        XCTAssertTrue(conversation.input.contains(saved.name))
        XCTAssertNil(conversation.conditions.days)
        XCTAssertNil(conversation.conditions.pace)
        XCTAssertEqual(conversation.draft, previous)
        conversation.stage(place: saved, addingToTrip: true, language: .english)
        XCTAssertEqual(conversation.assignmentPlace?.id, saved.id)
        XCTAssertEqual(conversation.draft, previous)
        XCTAssertFalse(conversation.assignmentInProgress)
    }

    func testCoordinateOnlySavedPlaceCanAnchorANewConversation() throws {
        let saved = place("Quarter Sheets Pizza Club", address: "")
        let conversation = SavePlanConversation()
        conversation.stage(place: saved, addingToTrip: false, language: .english)
        var conditions = conversation.conditions
        conditions.receive(conversation.input, areas: SavePlanDraftBuilder.areas(from: [saved]))
        XCTAssertEqual(conditions.area, saved.name)
        XCTAssertNil(conditions.days)
        XCTAssertNil(conditions.pace)
        conditions.receive("1 day balanced; no time constraints", areas: SavePlanDraftBuilder.areas(from: [saved]))
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(
            request: SavePlanRequest(area: try XCTUnwrap(conditions.area),
                days: try XCTUnwrap(conditions.days), pace: try XCTUnwrap(conditions.pace),
                arrivalMinutes: nil, departureMinutes: nil, language: .english,
                usesFlightBuffers: false, anchorPlaceID: saved.id), savedPlaces: [saved]))
        XCTAssertTrue(draft.placeIds.contains(saved.id.uuidString))
        XCTAssertEqual(draft.itineraryDays.count, 1)
    }

    private func completed() -> SavePlanConversationConditions {
        var conditions = SavePlanConversationConditions()
        conditions.receive("台北3天輕鬆", areas: ["Taipei"])
        conditions.receive("不用", areas: ["Taipei"])
        return conditions
    }

    private func place(_ name: String, address: String) -> Place {
        Place(id: UUID(), name: name, address: address, latitude: 25.04, longitude: 121.54,
              category: .attraction, status: .wantToGo, sourcePlatform: .other, createdAt: .distantPast)
    }
}
