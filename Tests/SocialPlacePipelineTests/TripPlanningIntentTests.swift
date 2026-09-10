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
    func testScreenshotColloquialPaceAdvancesToTimeThenDraft() throws {
        var conditions = SavePlanConversationConditions()
        for answer in ["以「and.room_taipei」為中心規劃 · Taipei", "7", "多一點"] {
            conditions.receive(answer, areas: ["Taipei"])
        }
        XCTAssertEqual(conditions.pace, .packed)
        XCTAssertFalse(conditions.needsFollowUpClarification)
        XCTAssertTrue(conditions.clarification(language: .traditionalChinese)?.contains("第一天") == true)
        conditions.receive("沒有", areas: ["Taipei"])
        let request = try XCTUnwrap(conditions.request(language: .traditionalChinese))
        XCTAssertEqual(request.days, 7)
        XCTAssertEqual(request.pace, .packed)
    }

    func testNoPacePreferenceAnswersOnlyPaceQuestion() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("Taipei 2 days", areas: ["Taipei"])
        conditions.receive("都可以", areas: ["Taipei"])
        XCTAssertEqual(conditions.pace, .balanced)
        XCTAssertFalse(conditions.arrivalAnswered)
        XCTAssertNil(conditions.request(language: .english))
        conditions.receive("都可以", areas: ["Taipei"])
        XCTAssertNotNil(conditions.request(language: .english))
    }

    func testNegatedMorePlacesDoesNotSelectPacked() {
        for answer in ["不要多一點", "not more places", "不要太緊湊"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive("Taipei 2 days", areas: ["Taipei"])
            conditions.receive(answer, areas: ["Taipei"])
            XCTAssertNil(conditions.pace, answer)
        }
    }

    func testNewPlanResetsEveryConversationConditionAndAllowsSecondDraft() throws {
        let conversation = SavePlanConversation()
        let saved = place("Taipei Museum", address: "Taipei")
        conversation.conditions = completed()
        conversation.draft = SavePlanDraftBuilder.draft(
            request: try XCTUnwrap(conversation.conditions.request(language: .english)), savedPlaces: [saved])
        conversation.messages = [.init(request: "old", reply: "old draft")]
        conversation.input = "old input"
        conversation.submittedQuery = "queued old request"
        conversation.anchorPlaceID = saved.id
        conversation.excludedPlaceIDs = [saved.id]
        let oldID = conversation.sessionID
        conversation.startNewPlan()
        XCTAssertNotEqual(conversation.sessionID, oldID)
        XCTAssertNil(conversation.draft)
        XCTAssertNil(conversation.submittedQuery)
        XCTAssertNil(conversation.anchorPlaceID)
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertTrue(conversation.input.isEmpty)
        XCTAssertTrue(conversation.excludedPlaceIDs.isEmpty)
        XCTAssertTrue(conversation.turns.isEmpty)
        XCTAssertNil(conversation.conditions.area)
        conversation.conditions.receive("Taipei 1 day packed; no time constraints", areas: ["Taipei"])
        let request = try XCTUnwrap(conversation.conditions.request(language: .english))
        XCTAssertEqual(request.days, 1)
        XCTAssertNotNil(SavePlanDraftBuilder.draft(request: request, savedPlaces: [saved]))
    }

    func testLosAngelesAliasesResolveOnlyEquivalentSavedCities() {
        for label in ["Los Angeles", "洛杉磯", "洛杉矶", "LA"] {
            for query in ["規劃 LA", "洛杉磯", "LA", "plan a trip to LA", "LA 3 days", "規劃 LA 3 天行程", "LA 3 days relaxed",
                          "LA.", "LA!", "LA trip", "LA。", "LA，輕鬆", "LA relaxed", "LA3天", "LA two days", "LA a day", "LA day trip",
                          "幫我規劃 LA 兩天行程", "请帮我规划 LA 2天", "請幫我規劃 LA 行程", "plan LA", "please plan LA", "help me plan LA"] {
                var conditions = SavePlanConversationConditions()
                conditions.receive(query, areas: [label, "Taipei"])
                XCTAssertEqual(conditions.area, label, query)
            }
        }
        for query in ["La Jolla", "La-Jolla", "La.Jolla", "La Jolla trip", "Kuala Lumpur", "Dallas", "不要 LA"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive(query, areas: ["Los Angeles"])
            XCTAssertNil(conditions.area, query)
        }
        XCTAssertFalse(SavePlanConversationConditions.areaAliases("Los Angeles").contains("la"))
    }

    func testEquivalentLosAngelesCitySuffixesDoNotRequireClarification() {
        let labels = ["Los Angeles", "洛杉磯市", "洛杉矶市"]
        for query in labels + ["規劃 LA"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive(query, areas: labels)
            XCTAssertEqual(conditions.area, "Los Angeles", query)
            XCTAssertTrue(conditions.clarification(language: .english)?.contains("days") == true)
        }
    }

    func testRejectedLosAngelesShorthandCannotReturnOnLaterCondition() {
        for rejection in ["不要 LA", "不去LA", "not LA", "不要 LA。", "not LA, please", "not LA!", "不要 LA trip", "LA 3 days, not LA"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive("Los Angeles 3 days relaxed; no time constraints", areas: ["Los Angeles"])
            conditions.receive(rejection, areas: ["Los Angeles"])
            XCTAssertNil(conditions.area, rejection)
            XCTAssertEqual(conditions.days, 3)
            conditions.receive("packed", areas: ["Los Angeles"])
            XCTAssertNil(conditions.request(language: .english), rejection)
        }
        var conditions = SavePlanConversationConditions()
        conditions.receive("Los Angeles 3 days relaxed; no time constraints", areas: ["Los Angeles"])
        conditions.receive("not La Jolla", areas: ["Los Angeles"])
        XCTAssertEqual(conditions.area, "Los Angeles")
        XCTAssertTrue(conditions.needsFollowUpClarification)
    }

    func testRejectingUnselectedLosAngelesKeepsConfirmedCityAndConditions() {
        let areas = ["Taipei", "Los Angeles"]
        for rejection in ["not LA", "不要 LA。", "not Los Angeles", "不要洛杉磯"] {
            var conditions = SavePlanConversationConditions()
            conditions.receive("Taipei 3 days relaxed; no time constraints", areas: areas)
            conditions.receive(rejection, areas: areas)
            XCTAssertEqual(conditions.area, "Taipei", rejection)
            XCTAssertEqual(conditions.days, 3)
            XCTAssertEqual(conditions.pace, .relaxed)
            conditions.receive("packed", areas: areas)
            XCTAssertEqual(conditions.request(language: .english)?.area, "Taipei", rejection)
        }
    }

    func testScreenshotConversationExplainsDurationAndRecoversAfterCorrection() throws {
        var conditions = SavePlanConversationConditions()
        for answer in ["規劃 LA", "10 天行程", "洛杉磯"] {
            conditions.receive(answer, areas: ["Los Angeles", "Taipei"])
        }
        XCTAssertEqual(conditions.area, "Los Angeles")
        XCTAssertEqual(conditions.unsupportedDays, 10)
        XCTAssertNil(conditions.days)
        XCTAssertTrue(conditions.clarification(language: .traditionalChinese)?.contains("10 天") == true)
        XCTAssertNil(conditions.request(language: .english))
        for answer in ["3 天", "輕鬆", "不用"] {
            conditions.receive(answer, areas: ["Los Angeles", "Taipei"])
        }
        let request = try XCTUnwrap(conditions.request(language: .english))
        XCTAssertEqual(request.area, "Los Angeles")
        XCTAssertEqual(request.days, 3)
        XCTAssertEqual(request.pace, .relaxed)
    }

    func testUnsupportedDurationIsNotHiddenByMissingSavedCity() {
        var conditions = SavePlanConversationConditions()
        conditions.receive("規劃 LA", areas: ["Taipei"])
        XCTAssertEqual(conditions.unmatchedDestination, "la")
        conditions.receive("10 天行程", areas: ["Taipei"])
        XCTAssertTrue(conditions.clarification(language: .traditionalChinese)?.contains("10 天") == true)
        XCTAssertNil(conditions.area)
        XCTAssertNil(conditions.request(language: .english))
        conditions.receive("3", areas: ["Taipei"])
        XCTAssertEqual(conditions.days, 3)
        XCTAssertEqual(conditions.unmatchedDestination, "la")
        XCTAssertTrue(conditions.clarification(language: .english)?.contains("saved places") == true)
    }

    func testLosAngelesConversationDraftUsesOnlyMatchingSavedPlaces() throws {
        let museum = place("Anchor Museum", address: "123 Main St, Los Angeles, CA, USA")
        let unrelated = place("La Jolla Museum", address: "La Jolla")
        let places = [museum, unrelated]
        var conditions = SavePlanConversationConditions()
        for answer in ["規劃 LA", "洛杉磯", "3 天", "輕鬆", "不用"] {
            conditions.receive(answer, areas: SavePlanDraftBuilder.areas(from: places))
        }
        let request = try XCTUnwrap(conditions.request(language: .traditionalChinese))
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: places))
        XCTAssertEqual(draft.itineraryDays.count, 3)
        XCTAssertTrue(draft.placeIds.contains(museum.id.uuidString))
        XCTAssertFalse(draft.placeIds.contains(unrelated.id.uuidString))
        XCTAssertTrue(SavePlanDraftBuilder.matches(area: "洛杉磯", place: museum))
        XCTAssertFalse(SavePlanDraftBuilder.matches(area: "LA", place: unrelated))
    }

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
        for next in ["改去京都", "不要台北，改去京都"] {
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

    func testDestinationAfterDurationClearsPreviousPlanArea() {
        for answer in ["3 days in Kyoto", "plan a 3 day trip to Kyoto", "3 days in Kyoto relaxed"] {
            var conditions = completed()
            conditions.receive(answer, areas: ["Taipei", "Tokyo"])
            XCTAssertNil(conditions.area, answer)
            XCTAssertEqual(conditions.days, 3)
            XCTAssertEqual(conditions.pace, .relaxed)
            XCTAssertNil(conditions.request(language: .english))
            XCTAssertTrue(conditions.clarification(language: .english)?.contains("kyoto") == true)
        }
        var conditions = completed()
        conditions.receive("3 days in a relaxed pace", areas: ["Taipei"])
        XCTAssertEqual(conditions.area, "Taipei")
        conditions.receive("plan a 2 day trip to Tokyo", areas: ["Taipei", "Tokyo"])
        XCTAssertEqual(conditions.area, "Tokyo")
        XCTAssertEqual(conditions.days, 2)
    }

    func testTokyoLocalizedAliasesMatchSavedAreaAndDraft() throws {
        let saved = place("Tokyo Museum", address: "Ueno, Tokyo, Japan")
        let areas = SavePlanDraftBuilder.areas(from: [saved])
        XCTAssertTrue(areas.contains("Tokyo"))
        for answer in ["東京", "東京都", "Tokyo"] {
            var conditions = completed()
            conditions.receive(answer, areas: areas)
            let request = try XCTUnwrap(conditions.request(language: .traditionalChinese))
            let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: [saved]))
            XCTAssertTrue(draft.placeIds.contains(saved.id.uuidString))
        }
        var conditions = completed()
        conditions.receive("不要東京", areas: ["Tokyo"])
        XCTAssertNil(conditions.area)
        let candidate = SaveMapCandidate(id: "tokyo-fill", title: "喫茶店", subtitle: "東京都台東區",
            latitude: 35.71, longitude: 139.77, category: .cafe)
        XCTAssertTrue(SavePlanDraftBuilder.matches(area: "Tokyo", candidate: candidate))
        XCTAssertFalse(SavePlanDraftBuilder.matches(area: "Taipei", candidate: candidate))
    }

    func testTripDescriptorsWithoutDurationPreserveCityAndAsk() {
        for query in ["family trip with kids", "food trip", "family travel with kids",
                      "親子旅行", "美食行程", "美食旅遊"] {
            var conditions = completed()
            conditions.receive(query, areas: ["Taipei", "Tokyo"])
            XCTAssertEqual(conditions.area, "Taipei", query)
            XCTAssertEqual(conditions.days, 3, query)
            XCTAssertNil(conditions.request(language: .english), query)
            XCTAssertTrue(conditions.clarification(language: .english)?.contains("kept") == true, query)
        }
    }

    func testUnknownDurationPrefixAsksDestinationOrPreferenceUntilCityIsAnswered() {
        // Unknown cities and descriptors share the same ambiguous grammar.
        // Keeping the city while blocking a new draft avoids guessing either way.
        for query in ["family trip for 2 days", "food trip 2 days", "beach trip 2 days",
                      "shopping trip 2 days", "relaxed trip 2 days", "親子旅行2天", "美食行程2天",
                      "浪漫旅行2天", "Kyoto for 2 days", "京都6天", "日本旅行6天五夜"] {
            var conditions = completed()
            conditions.receive(query, areas: ["Taipei", "Tokyo"])
            XCTAssertEqual(conditions.area, "Taipei", query)
            XCTAssertNil(conditions.request(language: .english), query)
            XCTAssertTrue(conditions.clarification(language: .english)?.contains("destination or") == true, query)
            for followup in ["2 days", "packed", "start 10:00", "none"] {
                conditions.receive(followup, areas: ["Taipei", "Tokyo"])
                XCTAssertNil(conditions.request(language: .english), "\(query) → \(followup) must not assume Taipei")
            }
            conditions.receive("保留Taipei", areas: ["Taipei", "Tokyo"])
            XCTAssertEqual(conditions.request(language: .english)?.area, "Taipei")
            XCTAssertEqual(conditions.request(language: .english)?.days, 2)
        }
        var prompted = completed()
        prompted.receive("beach trip 2 days", areas: ["Taipei", "Tokyo"])
        let question = prompted.clarification(language: .traditionalChinese) ?? ""
        let answer = question.components(separatedBy: "「").last?.components(separatedBy: "」").first ?? ""
        XCTAssertEqual(answer, "保留 Taipei")
        prompted.receive(answer, areas: ["Taipei", "Tokyo"])
        XCTAssertEqual(prompted.request(language: .english)?.area, "Taipei", "The answer printed in the clarification must work")

        var conditions = completed()
        conditions.receive("Kyoto for 2 days", areas: ["Taipei", "Tokyo"])
        conditions.receive("switch to Kyoto", areas: ["Taipei", "Tokyo"])
        XCTAssertNil(conditions.area)
        XCTAssertNil(conditions.ambiguousDestinationPrefix)
        XCTAssertEqual(conditions.unmatchedDestination, "kyoto")
        XCTAssertNil(conditions.request(language: .english))
        conditions.receive("Tokyo", areas: ["Taipei", "Tokyo"])
        XCTAssertEqual(conditions.request(language: .english)?.area, "Tokyo")
        XCTAssertEqual(conditions.request(language: .english)?.days, 2)
    }

    func testExplicitAndKnownDestinationsResolveDurationAmbiguity() {
        for (query, destination) in [("family trip in Kyoto for 2 days", "kyoto"),
                                      ("3 days in Kyoto", "kyoto"), ("plan a 3 day trip to Kyoto", "kyoto")] {
            var conditions = completed()
            conditions.receive(query, areas: ["Taipei", "Tokyo"])
            XCTAssertNil(conditions.area, query)
            XCTAssertEqual(conditions.unmatchedDestination, destination, query)
            XCTAssertNil(conditions.request(language: .english), query)
        }
        for query in ["Tokyo trip", "東京旅行", "Tokyo for 2 days"] {
            var conditions = completed()
            conditions.receive("beach trip 2 days", areas: ["Taipei", "Tokyo"])
            conditions.receive(query, areas: ["Taipei", "Tokyo"])
            XCTAssertEqual(conditions.request(language: .english)?.area, "Tokyo", query)
        }
    }

    func testRelaxedPaceKeepsCheckInAndOutWithAnchorBeforeSavedMeals() throws {
        let anchor = place("Anchor", address: "Taipei")
        var stay = place("Hotel", address: "Taipei")
        stay.category = .stay
        var breakfast = place("Breakfast", address: "Taipei")
        breakfast.category = .cafe
        var lunch = place("Lunch", address: "Taipei")
        lunch.category = .food
        let saved = [anchor, stay, breakfast, lunch]
        for language in [AppLanguage.english, .traditionalChinese] {
            for day in [1, 2] {
                let scheduled = SaveDayRhythmScheduler().schedule(orderedPlaces: [breakfast, lunch, anchor],
                    unsavedCandidates: [], lodging: stay, dayNumber: day, dayCount: 2,
                    windows: .standard, outputLanguage: language)
                XCTAssertGreaterThan(scheduled.stops.count, ItineraryPace.relaxed.maxStopsPerDay)
                let hotel = try XCTUnwrap(scheduled.stops.first { $0.placeId == stay.id.uuidString })
                let activity = try XCTUnwrap(scheduled.stops.first { $0.placeId == anchor.id.uuidString })
                let limited = SavePlanDraftBuilder.paceLimitedStops(scheduled.stops,
                    maxStops: ItineraryPace.relaxed.maxStopsPerDay, savedPlaces: saved, anchorPlaceID: anchor.id)
                XCTAssertEqual(limited.count, 3)
                XCTAssertTrue(limited.contains(hotel), "Retain the exact lodging identity and clock")
                XCTAssertTrue(limited.contains(activity), "Retain the exact anchor identity and clock")
                XCTAssertEqual(limited, scheduled.stops.filter { limited.contains($0) })
                let health = DeterministicTripPlanner().tripHealth(for: limited, savedPlaces: saved,
                    dayNumber: day, maxStopsPerDay: 3, outputLanguage: language)
                XCTAssertTrue(health.gaps.contains { $0.type == .missingLunch }, "A trimmed meal must remain a visible gap")
            }
        }
        let request = SavePlanRequest(area: "Taipei", days: 2, pace: .relaxed,
            arrivalMinutes: nil, departureMinutes: nil, language: .english,
            usesFlightBuffers: false, anchorPlaceID: anchor.id)
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: saved))
        XCTAssertTrue(draft.itineraryDays[0].stops.contains { $0.placeId == anchor.id.uuidString })
        for day in draft.itineraryDays {
            XCTAssertTrue(day.stops.contains { $0.placeId == stay.id.uuidString })
            XCTAssertLessThanOrEqual(day.stops.count, 3)
        }
    }

    func testMergedLodgingIdentityIsPrioritizedWithoutExceedingCap() {
        let anchor = place("Anchor", address: "Taipei")
        var stay = place("Hotel", address: "Taipei")
        stay.category = .stay
        let oldID = UUID()
        stay.mergedPlaceIDs = [oldID]
        let breakfast = place("Breakfast", address: "Taipei")
        let early = ItineraryStop(id: UUID(), placeId: breakfast.id.uuidString,
            placeName: breakfast.name, time: "9:00 AM", duration: 45, note: nil)
        let hotel = ItineraryStop(id: UUID(), placeId: oldID.uuidString,
            placeName: stay.name, time: "11:00 AM", duration: 30, note: nil)
        let late = ItineraryStop(id: UUID(), placeId: anchor.id.uuidString,
            placeName: anchor.name, time: "3:00 PM", duration: 60, note: nil)
        let stops = [early, hotel, late]
        let saved = [breakfast, stay, anchor]
        XCTAssertEqual(SavePlanDraftBuilder.paceLimitedStops(stops, maxStops: 2,
            savedPlaces: saved, anchorPlaceID: anchor.id), [hotel, late])
        XCTAssertEqual(SavePlanDraftBuilder.paceLimitedStops(stops, maxStops: 1,
            savedPlaces: saved, anchorPlaceID: anchor.id), [late])
        XCTAssertTrue(SavePlanDraftBuilder.paceLimitedStops(stops, maxStops: 0,
            savedPlaces: saved, anchorPlaceID: anchor.id).isEmpty)
    }

    func testRelaxedDraftKeepsSavedAttractionAfterSuggestedMealsAndStay() throws {
        let anchor = place("Taipei Museum", address: "Taipei")
        var stay = place("Taipei Hotel", address: "Taipei")
        stay.category = .stay
        let suggestions = [PlaceCategory.cafe, .food].enumerated().map { index, category in
            SaveMapCandidate(id: "fill-\(index)", title: "Meal \(index)", subtitle: "Taipei",
                latitude: 25.04, longitude: 121.54, category: category)
        }
        let scheduled = SaveDayRhythmScheduler().schedule(orderedPlaces: [anchor], unsavedCandidates: suggestions,
            lodging: stay, dayNumber: 1, dayCount: 2, windows: .standard, outputLanguage: .english)
        XCTAssertFalse(scheduled.stops.prefix(ItineraryPace.relaxed.maxStopsPerDay).contains { $0.placeId == anchor.id.uuidString },
            "Fixture must exercise the old chronological-prefix loss")
        for anchorID in [nil, anchor.id] as [UUID?] {
            let request = SavePlanRequest(area: "Taipei", days: 2, pace: .relaxed,
                arrivalMinutes: nil, departureMinutes: nil, language: .english, usesFlightBuffers: false,
                anchorPlaceID: anchorID)
            let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request,
                savedPlaces: [anchor, stay], unsavedCandidates: suggestions))
            XCTAssertTrue(draft.placeIds.contains(anchor.id.uuidString))
            XCTAssertTrue(draft.itineraryDays.allSatisfy { $0.stops.count <= ItineraryPace.relaxed.maxStopsPerDay })
            if anchorID != nil { XCTAssertTrue(draft.itineraryDays[0].stops.contains { $0.placeId == anchor.id.uuidString }) }
        }
    }

    func testPaceCapPrioritizesMergedAnchorIdentityWithoutChangingClocks() {
        var anchor = place("Anchor", address: "Taipei")
        let oldID = UUID()
        anchor.mergedPlaceIDs = [oldID]
        let early = ItineraryStop(id: UUID(), placeId: nil, placeName: "Suggested breakfast", time: "9:00 AM", duration: 60, note: nil)
        let late = ItineraryStop(id: UUID(), placeId: oldID.uuidString, placeName: "Anchor", time: "3:00 PM", duration: 75, note: nil)
        let limited = SavePlanDraftBuilder.paceLimitedStops([early, late], maxStops: 1,
            savedPlaces: [anchor], anchorPlaceID: anchor.id)
        XCTAssertEqual(limited, [late])
    }

    func testAlreadyAssignedMergedPlaceClosesChoicesWithoutWritingAgain() async {
        var saved = place("Merged Museum", address: "Taipei")
        let oldID = UUID()
        saved.mergedPlaceIDs = [oldID]
        let stop = TripStop(id: UUID(), placeId: oldID, placeName: "Old museum name", day: 1, orderIndex: 0)
        let trip = Trip(id: UUID(), name: "Existing", city: "Taipei", places: [stop], isOptimized: false, createdAt: .distantPast)
        let persistence = PlanAssignmentPersistence(trips: [trip])
        let store = TripPackStore(userID: "plan-unit-test", persistence: persistence)
        await store.load()
        let conversation = SavePlanConversation()
        conversation.stage(place: saved, addingToTrip: true, language: .english)

        await conversation.assignPlace(saved, to: trip, store: store, language: .english)

        XCTAssertEqual(conversation.messages.last?.reply, "Already in your trip.")
        XCTAssertNil(conversation.assignmentPlace)
        XCTAssertFalse(conversation.assignmentInProgress)
        XCTAssertEqual(store.trips.first?.places, [stop])
        XCTAssertEqual(persistence.updateCount, 0)
    }

    func testAssignmentRequiresStagingAndKeepsChoicesOnRealFailure() async {
        let saved = place("Museum", address: "Taipei")
        let trip = Trip(id: UUID(), name: "Existing", city: "Taipei", places: [], isOptimized: false, createdAt: .distantPast)
        let persistence = PlanAssignmentPersistence(trips: [trip])
        let store = TripPackStore(userID: "plan-unit-test", persistence: persistence)
        await store.load()
        let conversation = SavePlanConversation()
        await conversation.assignPlace(saved, to: trip, store: store, language: .english)
        XCTAssertEqual(persistence.updateCount, 0)
        conversation.stage(place: saved, addingToTrip: true, language: .english)
        persistence.failsUpdate = true
        await conversation.assignPlace(saved, to: trip, store: store, language: .english)
        XCTAssertNotEqual(conversation.messages.last?.reply, "Already in your trip.")
        XCTAssertNotNil(conversation.assignmentPlace)
        XCTAssertTrue(store.trips.first?.places.isEmpty == true)
        persistence.failsUpdate = false
        await conversation.assignPlace(saved, to: trip, store: store, language: .english)
        XCTAssertEqual(conversation.messages.last?.reply, "Added to your trip.")
        XCTAssertNil(conversation.assignmentPlace)
        XCTAssertEqual(store.trips.first?.places.count, 1)
    }

    func testPreferenceAndAmbiguousCityFollowupsPreserveConditionsAndAsk() {
        for query in ["more cafes", "avoid bars", "京都", "make it kid friendly"] {
            var conditions = completed()
            conditions.receive(query, areas: ["Taipei"])
            XCTAssertEqual(conditions.area, "Taipei")
            XCTAssertEqual(conditions.days, 3)
            XCTAssertEqual(conditions.pace, .relaxed)
            XCTAssertNil(conditions.request(language: .english))
            XCTAssertTrue(conditions.clarification(language: .english)?.contains("kept") == true)
            conditions.receive("2 days", areas: ["Taipei"])
            XCTAssertEqual(conditions.request(language: .english)?.days, 2)
        }
    }

    func testExplicitRemovalChangesDraftAndCannotBeUndoneByPolish() throws {
        let museum = place("Museum A", address: "Taipei")
        let garden = place("Garden B", address: "Taipei")
        let conversation = SavePlanConversation()
        conversation.conditions = completed()
        conversation.anchorPlaceID = museum.id
        let request = try XCTUnwrap(conversation.conditions.request(language: .english))
        let original = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: [museum, garden]))
        conversation.draft = original
        conversation.conditions.receive("more cafes", areas: ["Taipei"])

        XCTAssertTrue(conversation.applyStopRemoval("keep the plan but remove Museum A", savedPlaces: [museum, garden], language: .english))
        let edited = try XCTUnwrap(conversation.draft)
        XCTAssertFalse(edited.placeIds.contains(museum.id.uuidString))
        XCTAssertTrue(edited.placeIds.contains(garden.id.uuidString))
        XCTAssertEqual(edited.itineraryDays.count, original.itineraryDays.count)
        XCTAssertEqual(edited.itineraryDays.flatMap(\.stops).filter { $0.placeId == garden.id.uuidString },
                       original.itineraryDays.flatMap(\.stops).filter { $0.placeId == garden.id.uuidString })
        XCTAssertNil(conversation.anchorPlaceID)
        XCTAssertTrue(conversation.excludedPlaceIDs.contains(museum.id))
        XCTAssertEqual(SavePlanDraftBuilder.preservingSchedule(original, draft: edited), edited)
        conversation.conditions.receive("2 days", areas: ["Taipei"])
        var revisedRequest = try XCTUnwrap(conversation.conditions.request(language: .english))
        XCTAssertEqual(revisedRequest.days, 2, "Clarification before removal cannot block a later valid condition")
        revisedRequest.excludedPlaceIDs = conversation.excludedPlaceIDs
        let duplicate = SaveMapCandidate(id: "same-museum", title: museum.name, subtitle: "Taipei",
            latitude: museum.latitude, longitude: museum.longitude, category: .attraction)
        let rebuilt = try XCTUnwrap(SavePlanDraftBuilder.draft(request: revisedRequest,
            savedPlaces: [museum, garden], unsavedCandidates: [duplicate]))
        XCTAssertFalse(rebuilt.placeIds.contains(museum.id.uuidString))
        XCTAssertFalse(rebuilt.itineraryDays.flatMap(\.stops).contains { $0.placeName == museum.name })
        XCTAssertEqual(museum.name, "Museum A", "A draft edit never mutates the saved place")
    }

    func testRemovalAmbiguityAndUnsupportedEditsKeepDraft() throws {
        let first = place("Museum A", address: "1 Road, Taipei")
        let second = place("Museum A", address: "2 Road, Taipei")
        let stops = [first, second].map { ItineraryStop(id: UUID(), placeId: $0.id.uuidString,
            placeName: $0.name, time: "3:00 PM", duration: 60, note: nil) }
        let conversation = SavePlanConversation()
        conversation.conditions = completed()
        conversation.anchorPlaceID = second.id
        let original = SaveAIResponse(componentType: .tripItinerary, title: "Taipei", placeIds: stops.compactMap(\.placeId),
            navigationPlaceId: nil, transportMode: .walking, itineraryDays: [ItineraryDay(dayNumber: 1, label: nil, stops: stops)],
            messageText: nil, mapAction: nil, aiMessage: nil)
        conversation.draft = original
        XCTAssertTrue(conversation.applyStopRemoval("remove Museum A", savedPlaces: [first, second], language: .english))
        XCTAssertEqual(conversation.draft, original)
        XCTAssertTrue(conversation.messages.last?.reply.contains("Full address") == true)
        XCTAssertTrue(conversation.excludedPlaceIDs.isEmpty)
        XCTAssertFalse(conversation.applyStopRemoval("don't remove Museum A", savedPlaces: [first, second], language: .english))
        XCTAssertTrue(conversation.applyStopRemoval("remove Museum A, 1 Road, Taipei", savedPlaces: [first, second], language: .english))
        XCTAssertFalse(conversation.draft?.placeIds.contains(first.id.uuidString) ?? true)
        XCTAssertTrue(conversation.draft?.placeIds.contains(second.id.uuidString) == true)
        XCTAssertEqual(conversation.anchorPlaceID, second.id)
    }

    func testCityResolutionPreservesChineseAddresses() {
        for (address, area) in [("110台灣臺北市信義區, Taiwan", "臺北市"),
                                ("臺北市信義區", "Taipei"), ("東京都台東区上野", "東京")] {
            let saved = place("Museum", address: address)
            XCTAssertTrue(SavePlanDraftBuilder.matches(area: area, place: saved), address)
            XCTAssertEqual(SavePlanDraftBuilder.areas(from: [saved]).count, 1)
        }
    }

    func testFullAddressStagesCityAndNeverMatchesCafeSubstring() throws {
        let losAngeles = place("Anchor Museum", address: "123 Main St, Los Angeles, CA, USA")
        let unrelated = place("Cafe Anywhere", address: "Taipei")
        XCTAssertEqual(SavePlanDraftBuilder.areaLabel(for: losAngeles), "Los Angeles")
        XCTAssertEqual(Set(SavePlanDraftBuilder.areas(from: [losAngeles, unrelated])), ["Los Angeles", "Taipei"])
        XCTAssertFalse(SavePlanDraftBuilder.matches(area: "Los Angeles", place: unrelated))
        XCTAssertFalse(SavePlanDraftBuilder.matches(area: "CA", place: unrelated))
        let conversation = SavePlanConversation()
        conversation.stage(place: losAngeles, addingToTrip: false, language: .english)
        XCTAssertTrue(conversation.input.contains("Los Angeles"))
        XCTAssertEqual(conversation.anchorPlaceID, losAngeles.id)
        conversation.conditions.receive(conversation.input, areas: SavePlanDraftBuilder.areas(from: [losAngeles, unrelated]))
        conversation.conditions.receive("1 day balanced; no time constraints", areas: ["Los Angeles", "Taipei"])
        var request = try XCTUnwrap(conversation.conditions.request(language: .english))
        request.anchorPlaceID = losAngeles.id
        let draft = try XCTUnwrap(SavePlanDraftBuilder.draft(request: request, savedPlaces: [losAngeles, unrelated]))
        XCTAssertTrue(draft.placeIds.contains(losAngeles.id.uuidString))
        XCTAssertFalse(draft.placeIds.contains(unrelated.id.uuidString))
        let berkeley = place("Museum", address: "123 Main St, Berkeley, CA 94704, USA")
        XCTAssertEqual(SavePlanDraftBuilder.areaLabel(for: berkeley), "Berkeley")
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

@MainActor
private final class PlanAssignmentPersistence: TripPersisting {
    enum Failure: Error { case update }
    var trips: [Trip]
    var updateCount = 0
    var failsUpdate = false
    init(trips: [Trip]) { self.trips = trips }
    func fetchTrips(for userId: String) async throws -> [Trip] { trips }
    func saveTrip(_ trip: Trip, userId: String) async throws { trips.append(trip) }
    func updateTrip(_ trip: Trip) async throws {
        updateCount += 1
        if failsUpdate { throw Failure.update }
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
    }
    func deleteTrip(_ tripId: UUID) async throws { trips.removeAll { $0.id == tripId } }
}
