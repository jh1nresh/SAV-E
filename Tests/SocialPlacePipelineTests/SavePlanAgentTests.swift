import XCTest
@testable import SAVE

@MainActor
final class SavePlanAgentTests: XCTestCase {
    private func place(_ name: String, area: String = "Taipei", category: PlaceCategory = .attraction) -> Place {
        Place(id: UUID(), name: name, address: area, latitude: 25.04, longitude: 121.54,
              category: category, status: .wantToGo, sourcePlatform: .other, createdAt: Date())
    }
    private func decision(_ days: [[Place]]) -> SavePlanAgentDecision {
        .init(action: "draft", message: "先排好草稿。", area: "Taipei", days: days.count, pace: "balanced",
              transport: "walking", assumptions: ["未指定步調，先適中安排"],
              changedDays: days.enumerated().map { index, places in
                .init(day: index + 1, stops: places.enumerated().map { offset, place in
                    .init(ref: "s:" + place.id.uuidString, start: 600 + offset * 120, duration: 60)
                })
              })
    }
    private func validate(_ action: SavePlanAgentDecision, places: [Place], candidates: [SaveMapCandidate] = [],
                          previous: SavePlanAgentResult? = nil, anchor: UUID? = nil) throws -> SavePlanAgentResult {
        try SavePlanAgent.validate(action, request: previous?.request, draft: previous?.draft,
            inventory: .init(savedPlaces: places, candidates: candidates, draft: previous?.draft, anchorID: anchor),
            anchorID: anchor, language: .traditionalChinese)
    }
    private func json(_ action: SavePlanAgentDecision) throws -> String {
        String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
    }
    private func agent(_ generate: @escaping SavePlanAgent.Generate) -> SavePlanAgent {
        SavePlanAgent(generate: generate, checkTravel: { draft, _, _ in draft }, search: { _, _ in [] })
    }
    private func respond(_ agent: SavePlanAgent, places: [Place], query: String = "台北，想多玩一點",
                         previous: SavePlanAgentResult? = nil) async throws -> SavePlanAgentResult {
        try await agent.respond(query: query, history: [], request: previous?.request, draft: previous?.draft,
            savedPlaces: places, candidates: [], anchorID: nil, language: .traditionalChinese)
    }

    func testOfflineFixturePlansAroundCoordinateOnlyStamp() throws {
        let anchor = place("Quarter Sheets Pizza Club", area: "", category: .food)
        let conversation = SavePlanConversation()
        conversation.stage(place: anchor, addingToTrip: false, language: .english)
        let result = try SavePlanAgent.reviewFixture(
            query: conversation.input + " 1 day balanced; no time constraints", history: [],
            request: nil, draft: nil, savedPlaces: [anchor], anchorID: anchor.id, language: .english)
        XCTAssertEqual(try XCTUnwrap(result.draft).placeIds, [anchor.id.uuidString])
    }

    func testConfirmedCanvasIdentitySurvivesUntouchedDayFollowUp() throws {
        let a = place("Museum"), b = place("Garden"), confirmed = place("New Cafe", category: .cafe)
        let candidate = SaveMapCandidate(id: "new-cafe", title: confirmed.name, subtitle: "Taipei",
                                        latitude: confirmed.latitude, longitude: confirmed.longitude, category: .cafe)
        var action = decision([[a], [b]])
        action.changedDays?[0].stops[0].ref = "c:" + candidate.id
        let first = try validate(action, places: [a, b], candidates: [candidate])
        let original = try XCTUnwrap(first.draft)
        let conversation = SavePlanConversation()
        conversation.draft = original
        var canvas = TripCanvasDraft(days: original.itineraryDays)
        canvas.confirmExternalStop(original.itineraryDays[0].stops[0].id, as: confirmed)
        conversation.updateDraftDays(canvas.visibleDays, replacing: original)
        let edited = try XCTUnwrap(conversation.draft)
        XCTAssertEqual(edited.itineraryDays[0].stops[0].placeState, .confirmedMapStamp)
        XCTAssertTrue(edited.placeIds.contains(confirmed.id.uuidString))
        var followUp = decision([[a], [b]])
        followUp.changedDays?.removeFirst()
        followUp.changedDays?[0].stops[0].duration = 45
        let result = try validate(followUp, places: [a, b, confirmed],
                                  previous: .init(message: first.message, request: first.request, draft: edited))
        XCTAssertEqual(result.draft?.itineraryDays[0], edited.itineraryDays[0])
        conversation.startNewPlan()
        conversation.updateDraftDays(canvas.visibleDays, replacing: edited)
        XCTAssertNil(conversation.draft, "A late callback cannot restore a discarded draft.")
    }

    func testManualCanvasEditsBecomeTheConversationDraft() throws {
        let a = place("Museum"), b = place("Garden"), c = place("Gallery")
        let original = try XCTUnwrap(validate(decision([[a, b, c]]), places: [a, b, c]).draft)
        let conversation = SavePlanConversation()
        conversation.draft = original
        var canvas = TripCanvasDraft(days: original.itineraryDays)
        canvas.moveStopEarlier(original.itineraryDays[0].stops[1].id)
        canvas.skipStop(original.itineraryDays[0].stops[2].id)
        conversation.updateDraftDays(canvas.visibleDays, replacing: original)
        XCTAssertEqual(conversation.draft?.itineraryDays, canvas.visibleDays)
        XCTAssertEqual(conversation.draft?.placeIds, [b.id.uuidString, a.id.uuidString])
    }

    func testFirstTurnReachesModelWithoutPaceOrClockQuestionnaire() async throws {
        let a = place("Museum")
        var calls = 0
        let response = try json(decision([[a]]))
        let result = try await respond(agent { prompt in
            calls += 1
            XCTAssertTrue(prompt.contains("台北，想多玩一點"))
            return response
        }, places: [a])
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result.draft?.placeIds, [a.id.uuidString])
        XCTAssertTrue(result.message.contains("這版先採用"))
    }

    func testExplicitCanvasAnchorRemovalReleasesConstraintForNextEdit() throws {
        let anchor = place("Museum"), other = place("Garden")
        let first = try validate(decision([[anchor], [other]]), places: [anchor, other], anchor: anchor.id)
        let original = try XCTUnwrap(first.draft)
        let conversation = SavePlanConversation()
        conversation.draft = original
        conversation.agentRequest = first.request
        conversation.anchorPlaceID = anchor.id
        var canvas = TripCanvasDraft(days: original.itineraryDays)
        canvas.skipStop(original.itineraryDays[0].stops[0].id)
        conversation.updateDraftDays(canvas.visibleDays, replacing: original)
        XCTAssertNil(conversation.anchorPlaceID)
        XCTAssertNil(conversation.agentRequest?.anchorPlaceID)
        var patch = decision([[], [other]])
        patch.changedDays?.removeFirst()
        patch.changedDays?[0].stops[0].duration = 45
        let result = try validate(patch, places: [anchor, other], previous: .init(
            message: first.message, request: conversation.agentRequest, draft: conversation.draft))
        XCTAssertEqual(result.draft?.placeIds, [other.id.uuidString])
        XCTAssertNil(result.request?.anchorPlaceID)
    }

    func testLocalDayEditPreservesOtherDayExactlyAndChangesActualStops() throws {
        let a = place("Museum"), b = place("Garden"), c = place("Cafe", category: .cafe)
        let first = try validate(decision([[a], [b, c]]), places: [a, b, c])
        var patch = decision([[a], [c]])
        patch.changedDays?.removeFirst()
        let result = try validate(patch, places: [a, b, c], previous: first)
        XCTAssertEqual(result.draft?.itineraryDays[0], first.draft?.itineraryDays[0])
        XCTAssertEqual(result.draft?.itineraryDays[1].stops.map(\.placeId), [c.id.uuidString])
        XCTAssertFalse(result.draft?.placeIds.contains(b.id.uuidString) ?? true)
        XCTAssertEqual(c.name, "Cafe")
    }

    func testRetainedManuallyReorderedDayRequiresExplicitRepair() async throws {
        let a = place("Museum"), b = place("Garden"), c = place("Cafe")
        var first = try validate(decision([[a, b], [c]]), places: [a, b, c])
        let original = try XCTUnwrap(first.draft)
        var canvas = TripCanvasDraft(days: original.itineraryDays)
        canvas.moveStopEarlier(original.itineraryDays[0].stops[1].id)
        first.draft = original.replacingItineraryDays(canvas.visibleDays, tripHealth: original.tripHealth)
        var patch = decision([[a, b], [c]])
        patch.changedDays?.removeFirst()
        let invalid = try json(patch)
        let repaired = try json(decision([[b, a], [c]]))
        var calls = 0
        let result = try await respond(agent { prompt in
            calls += 1
            if calls == 1 { return invalid }
            XCTAssertTrue(prompt.contains("Day 1 has overlapping/out-of-window stops"))
            return repaired
        }, places: [a, b, c], previous: first)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result.draft?.itineraryDays[0].stops.map(\.placeId), [b.id.uuidString, a.id.uuidString])
        XCTAssertEqual(result.draft?.itineraryDays[0].stops.map(\.time), ["10:00 AM", "12:00 PM"])
    }

    func testRetainedDayRejectsInvalidDurationWindowClockAndPace() throws {
        let a = place("Museum"), b = place("Garden")
        let first = try validate(decision([[a], [b]]), places: [a, b])
        let draft = try XCTUnwrap(first.draft)
        let stop = draft.itineraryDays[0].stops[0]
        var patch = decision([[a], [b]])
        patch.changedDays?.removeFirst()
        for (time, duration) in [("10:00 AM", 14), ("10:00 AM", 241), ("8:00 AM", 60), ("8:30 PM", 60), ("invalid", 60)] {
            let invalid = ItineraryStop(id: stop.id, placeId: stop.placeId, placeName: stop.placeName,
                                        time: time, duration: duration, note: nil)
            var days = draft.itineraryDays
            days[0] = days[0].replacingStops([invalid])
            XCTAssertThrowsError(try validate(patch, places: [a, b], previous: .init(message: first.message,
                request: first.request, draft: draft.replacingItineraryDays(days, tripHealth: draft.tripHealth))))
        }
        var days = draft.itineraryDays
        days[0] = days[0].replacingStops(Array(repeating: stop, count: 20))
        XCTAssertThrowsError(try validate(patch, places: [a, b], previous: .init(message: first.message,
            request: first.request, draft: draft.replacingItineraryDays(days, tripHealth: draft.tripHealth)))) { error in
            XCTAssertTrue(String(describing: error).contains("pace limit"))
        }
    }

    func testReplacementAndReorderingUseCanonicalPlaceIdentity() throws {
        let a = place("Museum"), b = place("Cafe A", category: .cafe), c = place("Cafe B", category: .cafe)
        let first = try validate(decision([[a, b]]), places: [a, b, c])
        let result = try validate(decision([[c, a]]), places: [a, b, c], previous: first)
        XCTAssertEqual(result.draft?.placeIds, [c.id.uuidString, a.id.uuidString])
        XCTAssertEqual(result.draft?.itineraryDays[0].stops.last?.id, first.draft?.itineraryDays[0].stops.first?.id)
    }

    func testRepeatedHotelKeepsDistinctDayIdentityAfterLaterDayPatch() throws {
        let hotel = place("Hotel", category: .stay), museum = place("Museum")
        let first = try validate(decision([[hotel], [museum, hotel]]), places: [hotel, museum])
        let original = try XCTUnwrap(first.draft)
        var patch = decision([[hotel], [museum, hotel]])
        patch.changedDays?.removeFirst()
        patch.changedDays?[0].stops[1].duration = 45
        let result = try validate(patch, places: [hotel, museum], previous: first)
        let days = try XCTUnwrap(result.draft).itineraryDays
        XCTAssertEqual(days[0], original.itineraryDays[0])
        XCTAssertEqual(days[1].stops[1].id, original.itineraryDays[1].stops[1].id)
        XCTAssertEqual(Set(days.flatMap(\.stops).map(\.id)).count, 3)
        var canvas = TripCanvasDraft(days: days)
        canvas.moveStopEarlier(days[1].stops[1].id)
        XCTAssertEqual(canvas.visibleDays[0], days[0])
        XCTAssertEqual(canvas.visibleDays[1].stops.first?.id, days[1].stops[1].id)
        canvas.skipStop(days[1].stops[1].id)
        XCTAssertEqual(canvas.visibleDays[0], days[0])
        XCTAssertEqual(canvas.visibleDays[1].stops.map(\.placeId), [museum.id.uuidString])
    }

    func testNewHotelOccurrenceCannotReuseLaterRetainedDayIdentity() throws {
        let hotel = place("Hotel", category: .stay), museum = place("Museum")
        let first = try validate(decision([[museum], [hotel]]), places: [hotel, museum])
        var patch = decision([[museum, hotel], [hotel]])
        patch.changedDays?.removeLast()
        let result = try validate(patch, places: [hotel, museum], previous: first)
        let days = try XCTUnwrap(result.draft).itineraryDays
        XCTAssertEqual(days[1], first.draft?.itineraryDays[1])
        XCTAssertNotEqual(days[0].stops[1].id, days[1].stops[0].id)
    }

    func testInvalidModelReferencesCannotBePromoted() throws {
        let a = place("Museum")
        var value = decision([[a]])
        value.changedDays?[0].stops[0].ref = "s:" + UUID().uuidString
        XCTAssertThrowsError(try validate(value, places: [a]))
        let elsewhere = place("Tokyo Museum", area: "Tokyo")
        value.changedDays?[0].stops[0].ref = "s:" + elsewhere.id.uuidString
        XCTAssertThrowsError(try validate(value, places: [a, elsewhere]))
    }

    func testTimeOverlapPaceAndDuplicateBoundariesRejectWholeAction() throws {
        let a = place("Museum"), b = place("Garden")
        var value = decision([[a, b]])
        value.changedDays?[0].stops[1].start = 630
        XCTAssertThrowsError(try validate(value, places: [a, b]))
        value = decision([[a]])
        value.endMinutes = 620
        XCTAssertThrowsError(try validate(value, places: [a]))
        value = decision([[a, a]])
        XCTAssertThrowsError(try validate(value, places: [a]))
        value = decision([[a]])
        value.startMinutes = -1
        XCTAssertThrowsError(try validate(value, places: [a]))
        value = decision([[a]])
        value.changedDays?[0].stops[0].duration = 1000
        XCTAssertThrowsError(try validate(value, places: [a]))
        let many = (1...4).map { place("Stop \($0)") }
        value = decision([many]); value.pace = "relaxed"
        XCTAssertThrowsError(try validate(value, places: many))
    }

    func testGlobalConstraintChangesCannotLeaveUnvalidatedDays() throws {
        let a = place("Museum"), b = place("Garden")
        let first = try validate(decision([[a], [b]]), places: [a, b])
        var value = decision([[a], [b]])
        value.changedDays?.removeLast()
        value.pace = "packed"
        XCTAssertThrowsError(try validate(value, places: [a, b], previous: first))
        value = decision([[a], [b]])
        value.changedDays?[1].day = 1
        XCTAssertThrowsError(try validate(value, places: [a, b]))
    }

    func testAskKeepsDraftOutOfMutationAndAnchorIsRequiredInitially() throws {
        let a = place("Museum"), b = place("Garden")
        let first = try validate(decision([[a]]), places: [a])
        let result = try validate(.init(action: "ask", message: "想改去哪個城市？"), places: [a], previous: first)
        XCTAssertNil(result.draft)
        XCTAssertEqual(first.draft?.placeIds, [a.id.uuidString])
        XCTAssertThrowsError(try validate(decision([[b]]), places: [a, b], anchor: a.id))
        XCTAssertThrowsError(try validate(decision([[b]]), places: [a, b], previous: first, anchor: a.id))
        var replacement = decision([[b]])
        replacement.releaseAnchor = true
        let later = try validate(replacement, places: [a, b], previous: first, anchor: a.id)
        XCTAssertEqual(later.draft?.placeIds, [b.id.uuidString])
        XCTAssertNil(later.request?.anchorPlaceID)
    }

    func testInitialWrongCityCannotBypassAnchorEvenWithReleaseMarker() throws {
        let anchor = place("Museum"), elsewhere = place("Tokyo Garden", area: "Tokyo")
        var action = decision([[elsewhere]])
        action.area = "Tokyo"
        for release in [false, true] {
            action.releaseAnchor = release
            XCTAssertThrowsError(try validate(action, places: [anchor, elsewhere], anchor: anchor.id))
        }
    }

    func testLocalPatchPreservesActiveAnchorWithoutReleaseMarker() throws {
        let anchor = place("Museum"), other = place("Garden")
        let first = try validate(decision([[anchor], [other]]), places: [anchor, other], anchor: anchor.id)
        var patch = decision([[anchor], [other]])
        patch.changedDays?.removeFirst()
        patch.changedDays?[0].stops[0].duration = 45
        let result = try validate(patch, places: [anchor, other], previous: first)
        XCTAssertEqual(result.request?.anchorPlaceID, anchor.id)
        XCTAssertEqual(result.draft?.itineraryDays[0], first.draft?.itineraryDays[0])
        var omission = decision([[other], []])
        XCTAssertThrowsError(try validate(omission, places: [anchor, other], previous: result))
        omission.releaseAnchor = false
        XCTAssertThrowsError(try validate(omission, places: [anchor, other], previous: result))
    }

    func testSearchReturnsGroundedUnconfirmedPlaceThroughSameValidator() async throws {
        let a = place("Museum")
        let candidate = SaveMapCandidate(id: "new-cafe", title: "Cafe", subtitle: "Nearby unsaved place", latitude: 25.041,
                                        longitude: 121.54, category: .cafe)
        let far = SaveMapCandidate(id: "far-cafe", title: "Far Cafe", subtitle: "Taipei", latitude: 26,
                                  longitude: 121.54, category: .cafe)
        let invalid = SaveMapCandidate(id: "invalid-cafe", title: "Invalid Cafe", subtitle: "Taipei", latitude: .nan,
                                      longitude: 121.54, category: .cafe)
        let search = SavePlanAgentDecision(action: "search", message: "找附近咖啡店", area: "Taipei",
                                          searchAnchor: "s:" + a.id.uuidString, searchCategories: ["cafe"])
        var proposal = decision([[a]])
        proposal.changedDays?[0].stops.append(.init(ref: "c:new-cafe", start: 750, duration: 60))
        let replies = try [json(search), json(proposal)]
        var calls = 0, searches = 0
        var runner = agent { prompt in
            defer { calls += 1 }
            if calls == 1 {
                XCTAssertTrue(prompt.contains("new-cafe"))
                XCTAssertFalse(prompt.contains("far-cafe"))
                XCTAssertFalse(prompt.contains("invalid-cafe"))
            }
            return replies[calls]
        }
        runner.search = { anchor, categories in
            searches += 1
            XCTAssertEqual(anchor.id, a.id)
            XCTAssertEqual(categories, [.cafe])
            return [candidate, far, invalid]
        }
        let result = try await respond(runner, places: [a])
        XCTAssertEqual(calls, 2); XCTAssertEqual(searches, 1)
        let stop = try XCTUnwrap(result.draft?.itineraryDays[0].stops.last)
        XCTAssertNil(stop.placeId)
        XCTAssertEqual(stop.placeState, .externalSuggestion)
        XCTAssertEqual(stop.mapCandidate, candidate)
        XCTAssertEqual(result.draft?.placeIds, [a.id.uuidString])
        proposal.changedDays?[0].stops[1].duration = 45
        let followUp = try validate(proposal, places: [a], previous: result)
        let preserved = try XCTUnwrap(followUp.draft?.itineraryDays[0].stops.last)
        XCTAssertEqual(preserved.id, stop.id)
        XCTAssertEqual(preserved.mapCandidate, candidate)
        XCTAssertEqual(preserved.placeState, .externalSuggestion)
        XCTAssertNil(preserved.placeId)
        XCTAssertEqual(preserved.duration, 45)
    }

    func testNearbySearchBoundsWrapLongitudeAndRejectOutsideRegion() {
        var anchor = place("Island")
        anchor.longitude = 179.99
        let near = SaveMapCandidate(id: "near", title: "Cafe", subtitle: "", latitude: anchor.latitude,
                                   longitude: -179.99, category: .cafe)
        let far = SaveMapCandidate(id: "far", title: "Cafe", subtitle: "Taipei", latitude: anchor.latitude + 0.026,
                                  longitude: 179.99, category: .cafe)
        XCTAssertTrue(SavePlanAgent.Inventory.isNearby(near, anchor: anchor))
        XCTAssertFalse(SavePlanAgent.Inventory.isNearby(far, anchor: anchor))
        let inventory = SavePlanAgent.Inventory(savedPlaces: [anchor], candidates: [near], draft: nil, anchorID: nil)
        XCTAssertTrue(inventory.matches(area: "Taipei", candidate: near))
        XCTAssertFalse(inventory.matches(area: "Tokyo", candidate: near))
    }

    func testInvalidDecisionGetsFeedbackAndBoundedRepair() async throws {
        let a = place("Museum")
        var broken = decision([[a]])
        broken.changedDays?[0].stops[0].ref = "invented"
        let outputs = try [json(broken), json(decision([[a]]))]
        var calls = 0
        let result = try await respond(agent { prompt in
            defer { calls += 1 }
            if calls == 1 { XCTAssertTrue(prompt.contains("Unknown or out-of-area")) }
            return outputs[calls]
        }, places: [a])
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result.draft?.placeIds.count, 1)
        calls = 0
        do {
            _ = try await respond(agent { _ in calls += 1; return "garbage" }, places: [a])
            XCTFail("Malformed decisions must not succeed")
        } catch { XCTAssertEqual(calls, SavePlanAgent.maximumDecisions) }
    }

    func testRepeatedSearchIsBoundedAndNeverApplied() async throws {
        let a = place("Museum")
        let output = try json(.init(action: "search", message: "找附近", area: "Taipei",
            searchAnchor: "s:" + a.id.uuidString, searchCategories: ["cafe"]))
        var searches = 0
        var runner = agent { _ in output }
        runner.search = { _, _ in searches += 1; return [] }
        do { _ = try await respond(runner, places: [a]); XCTFail("Repeated search cannot complete a draft") }
        catch { XCTAssertEqual(searches, 1) }
    }

    func testTravelFailureFeedsRealFeedbackBackToModel() async throws {
        let a = place("Museum"), b = place("Garden")
        var calls = 0, checks = 0
        let output = try json(decision([[a, b]]))
        var runner = agent { prompt in
            calls += 1
            if calls == 2 { XCTAssertTrue(prompt.contains("Travel check rejected")) }
            return output
        }
        runner.checkTravel = { draft, _, _ in
            checks += 1
            guard checks == 1 else { return draft }
            var stops = draft.itineraryDays[0].stops
            stops[1].risks.append(.tooFarFromPrevious)
            return draft.replacingItineraryDays([draft.itineraryDays[0].replacingStops(stops)], tripHealth: nil)
        }
        let result = try await respond(runner, places: [a, b])
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(result.draft!.itineraryDays[0].stops[1].risks.contains(.tooFarFromPrevious))
    }

    func testNetworkFailureAndCancellationDoNotReturnReplacementDraft() async throws {
        let a = place("Museum")
        let first = try validate(decision([[a]]), places: [a])
        do {
            _ = try await respond(agent { _ in throw URLError(.notConnectedToInternet) }, places: [a], previous: first)
            XCTFail("Network failure must not masquerade as an edit")
        } catch { XCTAssertEqual(first.draft?.placeIds, [a.id.uuidString]) }
        let task = Task { try await respond(agent { _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return "{}"
        }, places: [a]) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled result must not be returned") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPromptExcludesPrivateNotesAddressesAndCoordinates() throws {
        var a = place("Museum", area: "123 Secret Road, Taipei")
        a.note = "PRIVATE-NOTE-NOT-FOR-PROVIDER"
        let inventory = SavePlanAgent.Inventory(savedPlaces: [a], candidates: [], draft: nil, anchorID: nil)
        let prompt = try SavePlanAgent.prompt(query: "Plan Taipei", history: [], request: nil, draft: nil,
            inventory: inventory, anchorID: nil, language: .english, feedback: "")
        XCTAssertFalse(prompt.contains("PRIVATE-NOTE"))
        XCTAssertFalse(prompt.contains("123 Secret Road"))
        XCTAssertFalse(prompt.contains("121.54"))
        XCTAssertFalse(prompt.contains("25.04"))
        XCTAssertTrue(prompt.contains(a.name))
        XCTAssertTrue(prompt.contains("Taipei"))
    }

    func testLargeInventoryPrioritizesRequestedAreaAndKeepsCurrentDraft() throws {
        let elsewhere = (1...100).map { place("Other \($0)", area: "Tokyo") }
        let target = place("Taipei Museum")
        let inventory = SavePlanAgent.Inventory(savedPlaces: elsewhere + [target], candidates: [], draft: nil,
                                                anchorID: nil, preferredAreas: ["Taipei"])
        XCTAssertNotNil(inventory.saved["s:" + target.id.uuidString])
        XCTAssertEqual(inventory.saved.count, 80)
        XCTAssertTrue(inventory.availableAreas.contains("Tokyo"))
    }

    func testTravelChecksOnlyChangedDayAndPreservesOtherDayDecoration() async throws {
        let a = place("Museum"), b = place("Garden"), c = place("Cafe", category: .cafe)
        var first = try validate(decision([[a, b], [c]]), places: [a, b, c])
        let draft = try XCTUnwrap(first.draft)
        var days = draft.itineraryDays
        var stops = days[0].stops
        stops[1].risks.append(.tooFarFromPrevious)
        days[0] = days[0].replacingStops(stops)
        days[0].windowNote = "Existing transfer warning"
        first.draft = draft.replacingItineraryDays(days, tripHealth: draft.tripHealth)
        let retainedLeg = TripTravelLeg(fromPlaceId: a.id.uuidString, toPlaceId: b.id.uuidString,
                                        durationMinutes: 90, distanceMeters: 6000, mode: .walking)
        first.draft?.travelLegs = [retainedLeg]
        var patch = decision([[a, b], [c]])
        patch.changedDays?[1].stops[0].duration = 45
        patch.changedDays?.removeFirst()
        let output = try json(patch)
        var checkedNumbers: [Int] = []
        var calls = 0
        var runner = agent { _ in calls += 1; return output }
        runner.checkTravel = { draft, _, _ in
            checkedNumbers = draft.itineraryDays.map(\.dayNumber)
            return draft
        }
        let result = try await respond(runner, places: [a, b, c], previous: first)
        XCTAssertTrue(result.message.contains("部分交通仍需要更多時間"))
        XCTAssertEqual(calls, 1, "A retained travel warning must not retry an unrelated day edit.")
        XCTAssertEqual(checkedNumbers, [2])
        XCTAssertEqual(result.draft?.travelLegs, [retainedLeg])
        XCTAssertEqual(result.draft?.itineraryDays[1].stops[0].duration, 45)
        XCTAssertEqual(result.draft?.itineraryDays[0], first.draft?.itineraryDays[0])
    }

    func testInventoryBoundsInvalidCoordinatesAndThinSevenDayDraft() throws {
        let a = place("Museum")
        var invalid = place("Invalid")
        invalid.latitude = .nan
        let inventory = SavePlanAgent.Inventory(savedPlaces: [a, invalid], candidates: [], draft: nil, anchorID: nil)
        XCTAssertEqual(inventory.saved.count, 1)
        let result = try validate(decision([[a], [], [], [], [], [], []]), places: [a])
        XCTAssertEqual(result.draft?.itineraryDays.count, 7)
        XCTAssertEqual(result.draft?.placeIds, [a.id.uuidString])
    }
}

/// Opt-in synthetic provider evaluation; default CI never makes paid/live model calls.
@MainActor
final class SavePlanAgentLiveEvaluation: XCTestCase {
    func testLiveChinesePlanningAndLocalEdits() async throws {
        guard ProcessInfo.processInfo.environment["SAVE_RUN_PLAN_LIVE_EVAL"] == "1" else {
            throw XCTSkip("Opt-in live provider evaluation")
        }
        let endpoint = SAVEProductionConfig.defaultAPIBaseURL
        var guestRequest = URLRequest(url: URL(string: endpoint + "/v0/guest-sessions")!)
        guestRequest.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: guestRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 || (response as? HTTPURLResponse)?.statusCode == 201,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["guest_token"] as? String else {
            XCTFail("Existing review-demo guest transport unavailable"); return
        }
        let transport = SAVEGeminiTransport(guestTokenProvider: { token }, directAPIKey: nil, maxAttemptsPerModel: 1)
        let names = ["Taipei Museum A", "Taipei Garden B", "Taipei Riverside C", "Taipei Gallery D",
                     "Taipei Cafe E", "Taipei Cafe F", "Taipei Restaurant G", "Taipei Restaurant H"]
        let places = names.enumerated().map { index, name in
            Place(id: UUID(), name: name, address: "Taipei", latitude: 25.04 + Double(index) * 0.001,
                  longitude: 121.54, category: index < 4 ? .attraction : index < 6 ? .cafe : .food,
                  status: .wantToGo, sourcePlatform: .other, createdAt: Date())
        }
        var captures: [String] = []
        let agent = SavePlanAgent(generate: { prompt in
            let response = try await transport.generateContent(body: [
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": ["temperature": 0.2, "maxOutputTokens": 4096, "responseMimeType": "application/json"]
            ])
            let candidates = response["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            let text = try XCTUnwrap(parts?.first?["text"] as? String)
            captures.append(text)
            return text
        }, checkTravel: { draft, _, _ in draft }, search: { _, _ in [] })
        defer {
            let attachment = XCTAttachment(string: captures.joined(separator: "\n\n"))
            attachment.name = "plan-agent-live-synthetic-responses"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let initial = "台北兩天，想逛景點也想喝咖啡，你幫我安排就好"
        let first = try await agent.respond(query: initial, history: [], request: nil, draft: nil,
            savedPlaces: places, candidates: [], anchorID: nil, language: .traditionalChinese)
        let draft = try XCTUnwrap(first.draft, "A clear city and duration should produce a draft without a questionnaire")
        XCTAssertEqual(draft.itineraryDays.count, 2)
        XCTAssertTrue(draft.itineraryDays.allSatisfy { !$0.stops.isEmpty })
        let followup = "第二天太累，少排一點，第一天不要動"
        let second = try await agent.respond(query: followup,
            history: [.init(userMessage: initial, assistantResponse: first.message)], request: first.request, draft: draft,
            savedPlaces: places, candidates: [], anchorID: nil, language: .traditionalChinese)
        let revised = try XCTUnwrap(second.draft)
        XCTAssertEqual(revised.itineraryDays[0], draft.itineraryDays[0])
        XCTAssertLessThan(revised.itineraryDays[1].stops.count, draft.itineraryDays[1].stops.count)
        let unknown = try await agent.respond(query: "改去京都", history: [], request: second.request, draft: revised,
            savedPlaces: places, candidates: [], anchorID: nil, language: .traditionalChinese)
        XCTAssertNil(unknown.draft, "Unavailable destination must not silently become Taipei")
        XCTAssertTrue(unknown.message.contains("京都"))
    }
}
