import CoreLocation
import Foundation

struct SavePlanAroundController {
    private let reviewCandidateConfidenceThreshold = 0.55

    func planAround(
        anchor: SaveSearchResult,
        savedResults: [SaveSearchResult],
        mapCandidates: [SaveMapCandidate],
        request: SavePlanAroundRequest
    ) -> SavePlanAroundResult {
        guard !anchor.isRecommendationShell, anchor.objectType != .sourceOnlyClue else {
            return .blocked(
                SavePlanBlockedState(
                    title: "Exact place needed",
                    message: "SAV-E needs a confirmed map place before it can plan nearby stops.",
                    missingInfo: ["place coordinates"],
                    allowedActions: [.runRecovery, .openSource]
                )
            )
        }

        guard let anchorStop = makeStop(from: anchor, source: .anchor, anchor: nil) else {
            return .blocked(
                SavePlanBlockedState(
                    title: "Location needed",
                    message: "This place needs coordinates before SAV-E can order nearby stops.",
                    missingInfo: ["coordinates"],
                    allowedActions: [.runRecovery, .showNearby]
                )
            )
        }

        var skippedReasons: [String] = []
        let desiredGaps = desiredFillerSlots(for: request, anchor: anchorStop)
        let region = normalizedRegion(request.planIntent.cityOrRegion)

        let savedStops = savedResults
            .filter { $0.id != anchor.id }
            .filter { !request.planIntent.avoidResultIDs.contains($0.id) }
            .filter { result in
                guard matches(region: region, result: result) else {
                    skippedReasons.append("Skipped \(result.title): outside requested city or region.")
                    return false
                }
                return true
            }
            .compactMap { result -> SavePlanStop? in
                switch result.objectType {
                case .savedPlace, .triedMemory:
                    return makeStop(from: result, source: .userSaved, anchor: anchorStop)
                case .pendingCandidate:
                    guard isHighConfidenceReviewCandidate(result) else {
                        skippedReasons.append("Skipped \(result.title): review candidate needs coordinates, category, and confidence >= \(reviewCandidateConfidenceThreshold).")
                        return nil
                    }
                    return makeStop(from: result, source: .pendingCandidate, anchor: anchorStop)
                default:
                    return nil
                }
            }
            .filter { stop in
                guard isNearEnough(stop, request: request) else {
                    skippedReasons.append("Skipped \(stop.title): outside \(request.duration.displayName.lowercased()) radius.")
                    return false
                }
                return true
            }

        let suggestionStops = mapCandidates
            .filter { candidate in
                guard matches(region: region, candidate: candidate) else {
                    skippedReasons.append("Skipped \(candidate.title): outside requested city or region.")
                    return false
                }
                return true
            }
            .compactMap { makeStop(from: $0, anchor: anchorStop, desiredGaps: desiredGaps) }
            .filter { stop in
                guard isNearEnough(stop, request: request) else {
                    skippedReasons.append("Skipped \(stop.title): outside \(request.duration.displayName.lowercased()) radius.")
                    return false
                }
                return true
            }

        let nearbySaved = ranked(savedStops, request: request)
        let newSuggestions = ranked(suggestionStops, request: request)
        if mapCandidates.isEmpty {
            skippedReasons.append("No public recommendation candidates were available; returning a saved-only draft.")
        }

        guard !nearbySaved.isEmpty || !newSuggestions.isEmpty else {
            return .blocked(
                SavePlanBlockedState(
                    title: "Not enough saved places",
                    message: "SAV-E needs at least one nearby Map Stamp or a clearly labeled public recommendation candidate before building this plan.",
                    missingInfo: desiredGaps.map(\.displayName),
                    allowedActions: [.showNearby, .savePlace]
                )
            )
        }

        let routeResult = route(anchor: anchorStop, nearbySaved: nearbySaved, newSuggestions: newSuggestions, desiredGaps: desiredGaps, request: request)
        let receipt = retrievalReceipt(
            request: request,
            desiredGaps: desiredGaps,
            mapCandidateCount: mapCandidates.count,
            skippedReasons: skippedReasons + routeResult.skippedReasons
        )
        let draft = SavePlanAroundDraft(
            request: request,
            anchor: anchorStop,
            nearbySaved: nearbySaved,
            newSuggestions: newSuggestions,
            routeStops: routeResult.stops,
            routeNotes: routeNotes(for: routeResult.stops),
            explanation: explanation(for: request, nearbySaved: nearbySaved, newSuggestions: newSuggestions, unfilledGaps: routeResult.unfilledGaps),
            unfilledGaps: routeResult.unfilledGaps,
            retrievalReceipt: receipt
        )

        return .draft(draft)
    }

    private func makeStop(from result: SaveSearchResult, source: SavePlanStopSource, anchor: SavePlanStop?) -> SavePlanStop? {
        guard let latitude = result.latitude, let longitude = result.longitude else { return nil }
        let distance = anchor.flatMap { distanceMeters(from: $0, toLatitude: latitude, longitude: longitude) }
        return SavePlanStop(
            id: result.id,
            title: result.title,
            subtitle: result.subtitle.isEmpty ? nil : result.subtitle,
            source: source,
            category: result.category,
            distanceMeters: distance,
            distanceLabel: distance.map(Self.distanceLabel),
            reason: reason(for: result.category, source: source),
            latitude: latitude,
            longitude: longitude,
            evidence: evidence(from: result)
        )
    }

    private func makeStop(from candidate: SaveMapCandidate, anchor: SavePlanStop, desiredGaps: [SavePlanFillerSlot]) -> SavePlanStop? {
        guard let distance = distanceMeters(from: anchor, toLatitude: candidate.latitude, longitude: candidate.longitude) else {
            return nil
        }
        let fillerSlot = fillerSlot(for: candidate.category, desiredGaps: desiredGaps)
        return SavePlanStop(
            id: "map-candidate-\(candidate.id)",
            title: candidate.title,
            subtitle: candidate.subtitle,
            source: .unsavedMapCandidate,
            category: candidate.category,
            distanceMeters: distance,
            distanceLabel: Self.distanceLabel(distance),
            reason: reason(for: candidate.category, source: .unsavedMapCandidate, fillerSlot: fillerSlot),
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            evidence: evidence(from: candidate),
            fillerSlot: fillerSlot
        )
    }

    private func ranked(_ stops: [SavePlanStop], request: SavePlanAroundRequest) -> [SavePlanStop] {
        stops.sorted { lhs, rhs in
            let leftScore = intentScore(lhs, request: request)
            let rightScore = intentScore(rhs, request: request)
            if leftScore != rightScore { return leftScore > rightScore }
            return (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    private struct RouteResult {
        var stops: [SavePlanStop]
        var unfilledGaps: [SavePlanFillerSlot]
        var skippedReasons: [String]
    }

    private func route(
        anchor: SavePlanStop,
        nearbySaved: [SavePlanStop],
        newSuggestions: [SavePlanStop],
        desiredGaps: [SavePlanFillerSlot],
        request: SavePlanAroundRequest
    ) -> RouteResult {
        var selected: [SavePlanStop] = [anchor]
        var skippedReasons: [String] = []
        let mustInclude = nearbySaved.filter { request.planIntent.mustIncludeResultIDs.contains($0.id) }
        selected.append(contentsOf: mustInclude.prefix(max(0, request.duration.maxStops - selected.count)))

        if selected.count < request.duration.maxStops {
            selected.append(
                contentsOf: nearbySaved
                    .filter { stop in !selected.contains(where: { $0.id == stop.id }) }
                    .prefix(max(0, request.duration.maxStops - selected.count))
            )
        }

        if selected.count < request.duration.maxStops {
            let gapFillers = newSuggestions.filter { suggestion in
                !selected.contains(where: { $0.id == suggestion.id }) &&
                    shouldFillCategoryGap(suggestion, selected: selected, desiredGaps: desiredGaps, request: request)
            }
            selected.append(contentsOf: gapFillers.prefix(request.duration.maxStops - selected.count))
        }

        if selected.count < request.duration.maxStops {
            selected.append(
                contentsOf: newSuggestions
                    .filter { suggestion in !selected.contains(where: { $0.id == suggestion.id }) }
                    .prefix(request.duration.maxStops - selected.count)
            )
        }

        let unfilledGaps = unfilledGaps(for: selected, desiredGaps: desiredGaps)
        if newSuggestions.isEmpty, !unfilledGaps.isEmpty {
            skippedReasons.append("Public recommendation fetch failed or returned no routeable candidates; gaps left unfilled: \(unfilledGaps.map(\.displayName).joined(separator: ", ")).")
        }
        return RouteResult(stops: selected, unfilledGaps: unfilledGaps, skippedReasons: skippedReasons)
    }

    private func routeNotes(for stops: [SavePlanStop]) -> [String] {
        guard stops.count > 1 else {
            return ["Start with the anchor. Add nearby Map Stamps once SAV-E has routeable matches."]
        }
        return stops.dropFirst().map { stop in
            let distance = stop.distanceLabel ?? "nearby"
            return "\(stop.title) is \(distance) from the anchor. Source label: \(stop.sourceLabel)."
        }
    }

    private func explanation(
        for request: SavePlanAroundRequest,
        nearbySaved: [SavePlanStop],
        newSuggestions: [SavePlanStop],
        unfilledGaps: [SavePlanFillerSlot]
    ) -> String {
        let savedCount = nearbySaved.count
        let suggestionCount = newSuggestions.count
        let gapCopy = unfilledGaps.isEmpty ? "" : " Unfilled gaps: \(unfilledGaps.map(\.displayName).joined(separator: ", "))."
        return "Built a \(request.duration.displayName.lowercased()) \(request.intent.displayName.lowercased()) draft from \(savedCount) Map \(savedCount == 1 ? "Stamp" : "Stamps") and \(suggestionCount) clearly labeled public \(suggestionCount == 1 ? "candidate" : "candidates").\(gapCopy)"
    }

    private func isNearEnough(_ stop: SavePlanStop, request: SavePlanAroundRequest) -> Bool {
        guard let distance = stop.distanceMeters else { return false }
        return distance <= request.duration.maxDistanceMeters
    }

    private func shouldFillCategoryGap(_ stop: SavePlanStop, selected: [SavePlanStop], desiredGaps: [SavePlanFillerSlot], request: SavePlanAroundRequest) -> Bool {
        guard request.intent == .balanced else { return intentScore(stop, request: request) > 0 }
        let selectedCategories = Set(selected.compactMap(\.category))
        guard let category = stop.category else { return false }
        if let fillerSlot = stop.fillerSlot, desiredGaps.contains(fillerSlot) {
            return true
        }
        return !selectedCategories.contains(category)
    }

    private func intentScore(_ stop: SavePlanStop, request: SavePlanAroundRequest) -> Int {
        guard let category = stop.category else { return 0 }
        let sourceBoost: Int
        switch stop.source {
        case .anchor, .userSaved:
            sourceBoost = 8
        case .pendingCandidate:
            sourceBoost = 4
        case .unsavedMapCandidate:
            sourceBoost = 0
        }
        let goalBoost = request.planIntent.categoryGoals.contains(category) ? 2 : 0
        let fillerBoost = stop.fillerSlot == nil ? 0 : 1
        switch request.intent {
        case .balanced:
            return sourceBoost + goalBoost + fillerBoost + 1
        case .food:
            return (category == .food ? 6 : 0) + sourceBoost + goalBoost
        case .coffee:
            return (category == .cafe ? 6 : 0) + sourceBoost + goalBoost
        case .culture:
            return (category == .attraction ? 6 : 0) + sourceBoost + goalBoost
        case .shopping:
            return (category == .shopping ? 6 : 0) + sourceBoost + goalBoost
        }
    }

    private func reason(for category: PlaceCategory?, source: SavePlanStopSource, fillerSlot: SavePlanFillerSlot? = nil) -> String {
        switch source {
        case .anchor:
            return "Anchor place for this plan."
        case .userSaved:
            return "Nearby Map Stamp from your spatial memory canvas."
        case .pendingCandidate:
            return "Nearby review clue; confirm before treating it as saved."
        case .unsavedMapCandidate:
            if let fillerSlot {
                return "Public filler for missing \(fillerSlot.displayName); not saved to SAV-E."
            }
            if category == .attraction {
                return "Adds a non-food unsaved candidate between Map Stamps."
            }
            return "Nearby unsaved candidate; not a saved memory yet."
        }
    }

    private func desiredFillerSlots(for request: SavePlanAroundRequest, anchor: SavePlanStop) -> [SavePlanFillerSlot] {
        let explicit = request.planIntent.allowedPublicFillerSlots
        let base: [SavePlanFillerSlot]
        switch request.intent {
        case .balanced:
            switch request.duration {
            case .quickStop:
                base = [.coffee, .walkableActivity]
            case .halfDay:
                base = [.coffee, .walkableActivity, .dinner]
            case .fullDay:
                base = [.breakfast, .coffee, .museum, .viewpoint, .dinner, .lateNight]
            }
        case .food:
            base = [.breakfast, .coffee, .dinner, .lateNight]
        case .coffee:
            base = [.coffee, .walkableActivity]
        case .culture:
            base = [.museum, .viewpoint, .walkableActivity, .coffee]
        case .shopping:
            base = [.walkableActivity, .coffee, .dinner]
        }
        let selectedCategories = Set([anchor.category].compactMap { $0 })
        return base
            .filter { explicit.contains($0) }
            .filter { slot in slot.preferredCategories.isDisjoint(with: selectedCategories) || slot == .coffee || slot == .dinner }
    }

    private func fillerSlot(for category: PlaceCategory?, desiredGaps: [SavePlanFillerSlot]) -> SavePlanFillerSlot? {
        guard let category else { return nil }
        return desiredGaps.first { $0.preferredCategories.contains(category) }
    }

    private func unfilledGaps(for selected: [SavePlanStop], desiredGaps: [SavePlanFillerSlot]) -> [SavePlanFillerSlot] {
        desiredGaps.filter { slot in
            !selected.contains { stop in
                guard let category = stop.category else { return false }
                return slot.preferredCategories.contains(category)
            }
        }
    }

    private func retrievalReceipt(
        request: SavePlanAroundRequest,
        desiredGaps: [SavePlanFillerSlot],
        mapCandidateCount: Int,
        skippedReasons: [String]
    ) -> SavePlanRetrievalReceipt {
        let region = request.planIntent.cityOrRegion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slots = desiredGaps.map(\.displayName).joined(separator: ", ")
        return SavePlanRetrievalReceipt(
            sourceBoundary: "Confirmed Map Stamps and high-confidence review candidates are evaluated separately from unsaved public recommendations.",
            querySelector: "Anchor-bounded \(request.duration.displayName.lowercased()) plan\(region.map { " in \($0)" } ?? "") for gaps: \(slots.isEmpty ? "none" : slots).",
            candidateCount: mapCandidateCount,
            filterRule: "Reject wrong-region, out-of-radius, low-confidence review, and avoided candidates. Public fillers are never autosaved.",
            scoreRule: "Saved Map Stamps outrank review candidates; review candidates outrank new recommendations; distance and category gap fit break ties.",
            skippedReasons: Array(Set(skippedReasons)).sorted()
        )
    }

    private func isHighConfidenceReviewCandidate(_ result: SaveSearchResult) -> Bool {
        guard result.latitude != nil, result.longitude != nil, result.category != nil else { return false }
        return (result.confidence ?? 0) >= reviewCandidateConfidenceThreshold
    }

    private func matches(region: String?, result: SaveSearchResult) -> Bool {
        guard let region else { return true }
        return [result.title, result.subtitle, result.cityOrArea]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(region) }
    }

    private func matches(region: String?, candidate: SaveMapCandidate) -> Bool {
        guard let region else { return true }
        return [candidate.title, candidate.subtitle]
            .map { $0.lowercased() }
            .contains { $0.contains(region) }
    }

    private func normalizedRegion(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func evidence(from result: SaveSearchResult) -> [String] {
        var evidence = result.evidence
        if let sourcePlatform = result.sourcePlatform {
            evidence.append("Source: \(sourcePlatform.displayName)")
        }
        if let rating = result.rating {
            evidence.append("Rating: \(rating)")
        }
        return Array(evidence.filter { !$0.isEmpty }.prefix(4))
    }

    private func evidence(from candidate: SaveMapCandidate) -> [String] {
        var evidence = candidate.evidence
        if let sourcePlatform = candidate.sourcePlatform {
            evidence.append("Source: \(sourcePlatform.displayName)")
        }
        if let rating = candidate.rating {
            evidence.append("Rating: \(rating)")
        }
        return Array(evidence.filter { !$0.isEmpty }.prefix(4))
    }

    private func distanceMeters(from stop: SavePlanStop, toLatitude latitude: Double, longitude: Double) -> Double? {
        guard let sourceLatitude = stop.latitude, let sourceLongitude = stop.longitude else { return nil }
        let source = CLLocation(latitude: sourceLatitude, longitude: sourceLongitude)
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return source.distance(from: target)
    }

    private static func distanceLabel(_ meters: Double) -> String {
        if meters < 1_000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1_000)
    }
}
