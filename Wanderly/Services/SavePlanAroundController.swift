import CoreLocation
import Foundation

struct SavePlanAroundController {
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

        let savedStops = savedResults
            .filter { $0.id != anchor.id }
            .compactMap { result -> SavePlanStop? in
                switch result.objectType {
                case .savedPlace, .triedMemory:
                    return makeStop(from: result, source: .userSaved, anchor: anchorStop)
                case .pendingCandidate:
                    return makeStop(from: result, source: .pendingCandidate, anchor: anchorStop)
                default:
                    return nil
                }
            }
            .filter { isNearEnough($0, request: request) }

        let suggestionStops = mapCandidates
            .compactMap { makeStop(from: $0, anchor: anchorStop) }
            .filter { isNearEnough($0, request: request) }

        let nearbySaved = ranked(savedStops, request: request)
        let newSuggestions = ranked(suggestionStops, request: request)
        let routeStops = route(anchor: anchorStop, nearbySaved: nearbySaved, newSuggestions: newSuggestions, request: request)
        let draft = SavePlanAroundDraft(
            request: request,
            anchor: anchorStop,
            nearbySaved: nearbySaved,
            newSuggestions: newSuggestions,
            routeStops: routeStops,
            routeNotes: routeNotes(for: routeStops),
            explanation: explanation(for: request, nearbySaved: nearbySaved, newSuggestions: newSuggestions)
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
            longitude: longitude
        )
    }

    private func makeStop(from candidate: SaveMapCandidate, anchor: SavePlanStop) -> SavePlanStop? {
        guard let distance = distanceMeters(from: anchor, toLatitude: candidate.latitude, longitude: candidate.longitude) else {
            return nil
        }
        return SavePlanStop(
            id: "map-candidate-\(candidate.id)",
            title: candidate.title,
            subtitle: candidate.subtitle,
            source: .unsavedMapCandidate,
            category: candidate.category,
            distanceMeters: distance,
            distanceLabel: Self.distanceLabel(distance),
            reason: reason(for: candidate.category, source: .unsavedMapCandidate),
            latitude: candidate.latitude,
            longitude: candidate.longitude
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

    private func route(
        anchor: SavePlanStop,
        nearbySaved: [SavePlanStop],
        newSuggestions: [SavePlanStop],
        request: SavePlanAroundRequest
    ) -> [SavePlanStop] {
        var selected: [SavePlanStop] = [anchor]
        selected.append(contentsOf: nearbySaved.prefix(max(1, request.duration.maxStops - 2)))

        if selected.count < request.duration.maxStops {
            let gapFillers = newSuggestions.filter { suggestion in
                !selected.contains(where: { $0.id == suggestion.id }) &&
                    shouldFillCategoryGap(suggestion, selected: selected, request: request)
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

        return selected
    }

    private func routeNotes(for stops: [SavePlanStop]) -> [String] {
        guard stops.count > 1 else {
            return ["Start with the anchor. Add nearby Map Stamps once SAV-E has routeable matches."]
        }
        return stops.dropFirst().map { stop in
            let distance = stop.distanceLabel ?? "nearby"
            return "\(stop.title) is \(distance) from the anchor."
        }
    }

    private func explanation(
        for request: SavePlanAroundRequest,
        nearbySaved: [SavePlanStop],
        newSuggestions: [SavePlanStop]
    ) -> String {
        let savedCount = nearbySaved.count
        let suggestionCount = newSuggestions.count
        return "Built a \(request.duration.displayName.lowercased()) \(request.intent.displayName.lowercased()) draft from \(savedCount) Map \(savedCount == 1 ? "Stamp" : "Stamps") and \(suggestionCount) unsaved nearby \(suggestionCount == 1 ? "candidate" : "candidates")."
    }

    private func isNearEnough(_ stop: SavePlanStop, request: SavePlanAroundRequest) -> Bool {
        guard let distance = stop.distanceMeters else { return false }
        return distance <= request.duration.maxDistanceMeters
    }

    private func shouldFillCategoryGap(_ stop: SavePlanStop, selected: [SavePlanStop], request: SavePlanAroundRequest) -> Bool {
        guard request.intent == .balanced else { return intentScore(stop, request: request) > 0 }
        let selectedCategories = Set(selected.compactMap(\.category))
        guard let category = stop.category else { return false }
        return !selectedCategories.contains(category)
    }

    private func intentScore(_ stop: SavePlanStop, request: SavePlanAroundRequest) -> Int {
        guard let category = stop.category else { return 0 }
        switch request.intent {
        case .balanced:
            return stop.source == .userSaved || stop.source == .pendingCandidate ? 3 : 1
        case .food:
            return category == .food ? 6 : 0
        case .coffee:
            return category == .cafe ? 6 : 0
        case .culture:
            return category == .attraction ? 6 : 0
        case .shopping:
            return category == .shopping ? 6 : 0
        }
    }

    private func reason(for category: PlaceCategory?, source: SavePlanStopSource) -> String {
        switch source {
        case .anchor:
            return "Anchor place for this plan."
        case .userSaved:
            return "Nearby Map Stamp from your spatial memory canvas."
        case .pendingCandidate:
            return "Nearby review clue; confirm before treating it as saved."
        case .unsavedMapCandidate:
            if category == .attraction {
                return "Adds a non-food unsaved candidate between Map Stamps."
            }
            return "Nearby unsaved candidate; not a saved memory yet."
        }
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
