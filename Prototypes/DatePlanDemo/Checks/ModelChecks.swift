import Foundation

@main
struct ModelChecks {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() throws {
        try fixturesAndIndependentVotes()
        try shortlistRemovalAndSnapshots()
        try changedMutualChoicesAndRegeneration()
        try reorderingAndStartTime()
        try explicitSavesOnly()
        try manualProgressAndCompletion()
        try budgetDoesNotHideUnknownPrices()
        print("DatePlan model checks PASS (7 groups; local fictional fixtures only)")
    }

    @MainActor
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor
    private static func mutualThree(_ store: DatePlanStore) {
        for id in ["coffee", "park", "dinner"] { store.toggleVote(id, participant: .you) }
    }

    @MainActor
    private static func verifyTimeline(_ store: DatePlanStore) throws {
        let stops = store.timeline
        try check(stops.map(\.placeID) == store.planIDs, "Timeline must follow the actual editable order")
        for (index, stop) in stops.enumerated() {
            let place = store.place(stop.placeID)
            try check(stop.id == stop.placeID, "Timeline identity must remain tied to the stable place ID")
            try check(stop.departureMinutes - stop.arrivalMinutes == place?.durationMinutes, "Stop duration must match its fixture")
            if index == 0 {
                try check(stop.travelMinutes == 0 && stop.arrivalMinutes == store.startsAtMinutes, "First stop starts at the chosen time")
            } else {
                try check((5...25).contains(stop.travelMinutes), "Transfers must remain bounded illustrative walking estimates")
                try check(stop.arrivalMinutes == stops[index - 1].departureMinutes + stop.travelMinutes, "Arrival must include the transfer")
                try check(stop.arrivalMinutes >= stops[index - 1].departureMinutes, "Stops must never overlap")
            }
        }
    }

    @MainActor
    private static func fixturesAndIndependentVotes() throws {
        let store = DatePlanStore()
        try check(store.places.map(\.id) == ["coffee", "park", "dinner", "dessert"], "Four stable fixture identities are required")
        try check(store.candidateIDs == ["coffee", "park", "dinner"], "Primary shortlist must have three fixtures")
        try check(store.savedIDs == Set(["park", "dessert"]), "Saved fixtures must be independent from shortlist")
        try check(store.activeParticipant == .you && store.startsAtMinutes == 840, "Initial participant and 14:00 start")
        try check(store.places.map(\.durationMinutes) == [60, 70, 90, 45], "Fixture durations are part of the local contract")
        try check(store.place("coffee")?.recommendedBy == .an && store.place("park")?.isOutdoor == true,
                  "Coffee keeps An attribution; park remains the outdoor option")
        try check(store.candidateIDs.allSatisfy { store.votes[$0] == Set([.an]) }, "An initially votes for the primary three")
        try check(store.sharedIDs.isEmpty && !store.hasPlan && !store.generatePlan(), "No plan may be generated before mutual consent")
        store.toggleVote("coffee", participant: .you)
        try check(store.sharedIDs == ["coffee"], "Both explicit votes produce the intersection")
        store.toggleVote("coffee", participant: .an)
        try check(store.sharedIDs.isEmpty && store.votes["coffee"] == Set([.you]), "Each participant can independently withdraw")
        store.toggleVote("dessert", participant: .you)
        store.toggleVote("unknown", participant: .an)
        store.toggleCandidate("unknown")
        try check(store.votes["dessert"] == nil && store.place("unknown") == nil, "Unknown or unshortlisted places cannot acquire votes")
        try check(store.savedIDs == Set(["park", "dessert"]), "Voting and picking must not save places")
    }

    @MainActor
    private static func shortlistRemovalAndSnapshots() throws {
        let store = DatePlanStore()
        mutualThree(store)
        try check(store.generatePlan(), "Mutual primary choices should generate a plan")
        let snapshot = store.planIDs
        store.toggleCandidate("park")
        try check(!store.candidateIDs.contains("park") && store.votes["park"] == nil, "Removal clears both local persona votes")
        try check(store.sharedIDs == ["coffee", "dinner"], "Removed shortlist items cannot remain mutual")
        try check(store.planIDs == snapshot && store.isPlanStale, "Existing plan is a labeled snapshot until explicit regeneration")
        try check(store.savedIDs.contains("park"), "Removing a candidate does not unsave it")
        store.toggleCandidate("park")
        try check(store.candidateIDs == ["coffee", "park", "dinner"] && store.votes["park"] == nil,
                  "Re-adding follows fixture order and requires fresh votes")
        try verifyTimeline(store)
    }

    @MainActor
    private static func changedMutualChoicesAndRegeneration() throws {
        let store = DatePlanStore()
        mutualThree(store)
        try check(store.generatePlan() && !store.isPlanStale, "Successful generation snapshots the mutual set")
        store.toggleCandidate("dessert")
        store.toggleVote("dessert", participant: .you)
        try check(!store.isPlanStale, "A single extra vote does not change mutual choices")
        store.toggleVote("dessert", participant: .an)
        try check(store.isPlanStale && store.planIDs.count == 3, "New mutual choices cannot silently rewrite a plan")
        try check(store.generatePlan() && store.planIDs == ["coffee", "park", "dinner", "dessert"], "Regeneration uses deterministic fixture order")
        store.toggleVote("dessert", participant: .you)
        try check(store.isPlanStale && store.planIDs.count == 4, "Withdrawing mutual consent marks the old snapshot stale")
        try check(store.generatePlan() && store.planIDs.count == 3 && !store.isPlanStale, "Explicit regeneration removes the withdrawn stop")
        let snapshot = store.planIDs
        for id in store.sharedIDs { store.toggleVote(id, participant: .you) }
        try check(!store.generatePlan() && store.planIDs == snapshot && store.isPlanStale,
                  "Empty generation must reject without erasing the last plan")
    }

    @MainActor
    private static func reorderingAndStartTime() throws {
        let store = DatePlanStore()
        mutualThree(store)
        try check(store.generatePlan(), "Three mutual stops should generate")
        let original = store.timeline
        try check(original.last!.departureMinutes <= 19 * 60, "Initial three-stop outing fits the stated afternoon")
        store.moveStop("park", offset: -1)
        try check(store.planIDs == ["park", "coffee", "dinner"], "Reorder must actually change the plan")
        try check(store.timeline.first?.arrivalMinutes == 840 && store.timeline.first?.placeID == "park", "New first stop receives the start time")
        try check(store.timeline.first?.arrivalMinutes != original.first(where: { $0.placeID == "park" })?.arrivalMinutes,
                  "Reordering must recompute arrival times, not just rearrange labels")
        try check(!store.isPlanStale, "Order edits must not invalidate the mutual-choice snapshot")
        let ordered = store.planIDs
        store.moveStop("park", offset: -1); store.moveStop("dinner", offset: 1)
        store.moveStop("coffee", offset: 3); store.moveStop("unknown", offset: 1)
        try check(store.planIDs == ordered, "Bounds and unsupported offsets must be no-ops")
        let before = store.timeline
        store.setStartMinutes(15 * 60 + 30)
        for (old, new) in zip(before, store.timeline) {
            try check(new.arrivalMinutes - old.arrivalMinutes == 90 && new.departureMinutes - old.departureMinutes == 90,
                      "Start-time change must shift the entire plan")
            try check(new.travelMinutes == old.travelMinutes, "A clock edit must not alter transfer estimates")
        }
        try verifyTimeline(store)
        store.setStartMinutes(Int.min); try check(store.startsAtMinutes == 600, "Lower half-day boundary")
        store.setStartMinutes(Int.max); try check(store.startsAtMinutes == 1080, "Upper half-day boundary")
        try check(DatePlanStore.clock(840) == "14:00" && DatePlanStore.clock(930) == "15:30", "Clock labels use integer local minutes")
        try verifyTimeline(store)
    }

    @MainActor
    private static func explicitSavesOnly() throws {
        let store = DatePlanStore()
        let saved = store.savedIDs, notes = store.places.map(\.note)
        mutualThree(store); store.generatePlan(); store.moveStop("coffee", offset: 1)
        store.setStartMinutes(900); store.startDate(); store.advanceStop()
        store.toggleCandidate("dessert"); store.toggleVote("dessert", participant: .an)
        try check(store.savedIDs == saved && store.places.map(\.note) == notes, "Planning cannot rewrite saved truth or attributed fixture notes")
        let candidates = store.candidateIDs, votes = store.votes, plan = store.planIDs
        store.setSaved("coffee", true); store.setSaved("coffee", true)
        try check(store.savedIDs == saved.union(["coffee"]), "Explicit save is idempotent")
        store.setSaved("park", false); store.setSaved("unknown", true)
        try check(!store.savedIDs.contains("park") && !store.savedIDs.contains("unknown"), "Only known fixture identities can be saved")
        try check(store.candidateIDs == candidates && store.votes == votes && store.planIDs == plan, "Saving must not choose or vote for a place")
    }

    @MainActor
    private static func manualProgressAndCompletion() throws {
        let store = DatePlanStore(), saved = Set(["park", "dessert"])
        store.startDate(); store.advanceStop()
        try check(!store.started && store.currentStopIndex == 0, "Progress cannot start without a plan")
        mutualThree(store); store.generatePlan(); store.advanceStop()
        try check(store.currentStopIndex == 0, "Unstarted plans must not advance")
        store.startDate(); store.advanceStop()
        let current = store.planIDs[store.currentStopIndex], order = store.planIDs, began = store.startsAtMinutes
        store.startDate()
        try check(store.currentStopIndex == 1, "Repeated start must not reset active progress")
        store.moveStop(current, offset: -1)
        store.moveStop("dinner", offset: -1)
        store.setStartMinutes(began + 15)
        try check(store.planIDs == order && store.startsAtMinutes == began, "Started plans lock order and original start time")
        var remaining: [String] = []
        for _ in store.planIDs.indices {
            if store.currentStopIndex >= store.planIDs.count { break }
            remaining.append(store.planIDs[store.currentStopIndex]); store.advanceStop()
        }
        try check(remaining == ["park", "dinner"], "Reorder attempts cannot skip uncompleted stops or repeat completed ones")
        let terminal = store.currentStopIndex
        for _ in 0..<5 { store.advanceStop(); store.startDate() }
        try check(terminal == store.planIDs.count && store.currentStopIndex == terminal && store.started, "Completion must be terminal and idempotent")
        try check(store.savedIDs == saved, "Manual outing progress must never add a save or visit")
        store.generatePlan()
        try check(!store.started && store.currentStopIndex == 0, "Explicit regeneration starts a new local plan")
        store.toggleVote("coffee", participant: .an)
        store.startDate()
        try check(!store.started, "A stale proposal cannot start without explicit regeneration")
        store.generatePlan(); store.startDate()
        store.toggleVote("park", participant: .an)
        store.advanceStop()
        try check(store.currentStopIndex == 0, "Stale active plans must wait for confirmation before advancing")
    }

    @MainActor
    private static func budgetDoesNotHideUnknownPrices() throws {
        let store = DatePlanStore()
        try check(!store.budget.isComplete && store.budget.totalStops == 0, "Empty plans cannot claim a free complete budget")
        mutualThree(store); store.generatePlan()
        let total = store.budget
        try check(total.isComplete && total.minimumPerPerson == 680 && total.maximumPerPerson == 980,
                  "Totals must follow the actual selected fixture stops")
        try check(total.minimumForTwo == 1360 && total.maximumForTwo == 1960, "Two-person total must remain explicit")
        let unknown = DemoBudgetTotals.fixtures(for: ["coffee", "unknown"])
        try check(!unknown.isComplete && unknown.coveredStops == 1 && unknown.totalStops == 2,
                  "Unknown prices cannot silently become zero-cost confirmed stops")
        store.moveStop("park", offset: -1)
        try check(store.budget == total, "Reordering cannot change the budget")
        store.toggleVote("dinner", participant: .an); store.generatePlan()
        try check(store.budget.minimumPerPerson == 180 && store.budget.maximumPerPerson == 280,
                  "A regenerated plan must omit deselected stop costs")
    }
}
