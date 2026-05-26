import CoreLocation
import Foundation

struct SaveGuideCustomizationController {
    func customize(
        guide: SaveGuide,
        savedPlaces: [Place],
        nearbyCandidates: [SaveMapCandidate] = []
    ) -> SaveGuideCustomizationDraft {
        let keepStops = guide.stops.map { classify($0, savedPlaces: savedPlaces) }
        let savedSwaps = savedPlaces
            .filter { isRelevantSavedPlace($0, guide: guide, guideStops: keepStops) }
            .map { planStop(from: $0, reason: "Saved place near this guide.") }
        let suggestions = nearbyCandidates.map { candidate in
            SaveGuidePlanStop(
                id: "map-candidate-\(candidate.id)",
                title: candidate.title,
                subtitle: candidate.subtitle,
                origin: .newSuggestion,
                category: candidate.category,
                sourceURL: candidate.sourceURL,
                sourcePlatform: candidate.sourcePlatform,
                reason: "Unsaved nearby suggestion; review before saving.",
                placeId: nil,
                guideStopId: nil
            )
        }

        return SaveGuideCustomizationDraft(
            originalGuide: guide,
            keepStops: keepStops,
            swapInSavedPlaces: savedSwaps,
            addNearbySuggestions: suggestions,
            explanation: explanation(guide: guide, keepStops: keepStops, savedSwaps: savedSwaps, suggestions: suggestions)
        )
    }

    func makeTripDraft(from draft: SaveGuideCustomizationDraft, name: String? = nil, createdAt: Date = Date()) -> Trip {
        let stops = draft.keepStops.enumerated().map { index, stop in
            TripStop(
                id: UUID(),
                placeId: UUID(),
                placeName: stop.title,
                day: max(1, (index / 4) + 1),
                orderIndex: index,
                startTime: nil,
                duration: nil,
                note: tripNote(for: stop, guide: draft.originalGuide)
            )
        }

        return Trip(
            id: UUID(),
            name: name ?? draft.originalGuide.title,
            city: draft.originalGuide.cityOrArea ?? "Guide draft",
            startDate: nil,
            endDate: nil,
            places: stops,
            isOptimized: false,
            createdAt: createdAt
        )
    }

    private func classify(_ stop: SaveGuideStop, savedPlaces: [Place]) -> SaveGuideStop {
        var copy = stop
        if lacksPlaceEvidence(stop) {
            copy.state = .needsRecovery
        } else if savedPlaces.contains(where: { matches(stop, savedPlace: $0) }) {
            copy.state = .alreadySaved
        } else {
            copy.state = .guideOnly
        }
        return copy
    }

    private func lacksPlaceEvidence(_ stop: SaveGuideStop) -> Bool {
        let hasAddress = stop.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasCoordinates = stop.latitude != nil && stop.longitude != nil
        return !hasAddress && !hasCoordinates
    }

    private func matches(_ stop: SaveGuideStop, savedPlace: Place) -> Bool {
        if normalize(stop.title) == normalize(savedPlace.name) {
            return true
        }
        if let address = stop.address, normalize(address) == normalize(savedPlace.address) {
            return true
        }
        if let latitude = stop.latitude, let longitude = stop.longitude {
            let stopLocation = CLLocation(latitude: latitude, longitude: longitude)
            let savedLocation = CLLocation(latitude: savedPlace.latitude, longitude: savedPlace.longitude)
            return stopLocation.distance(from: savedLocation) <= 120
        }
        return false
    }

    private func isRelevantSavedPlace(_ place: Place, guide: SaveGuide, guideStops: [SaveGuideStop]) -> Bool {
        if let city = guide.cityOrArea, normalize(place.address).contains(normalize(city)) {
            return true
        }
        return guideStops.contains { stop in
            guard let latitude = stop.latitude, let longitude = stop.longitude else {
                return stop.category == place.category
            }
            let stopLocation = CLLocation(latitude: latitude, longitude: longitude)
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            return stopLocation.distance(from: placeLocation) <= 5_000
        }
    }

    private func planStop(from place: Place, reason: String) -> SaveGuidePlanStop {
        SaveGuidePlanStop(
            id: "place-\(place.id.uuidString)",
            title: place.name,
            subtitle: place.address,
            origin: .userSaved,
            category: place.category,
            sourceURL: place.sourceUrl,
            sourcePlatform: place.sourcePlatform,
            reason: reason,
            placeId: place.id,
            guideStopId: nil
        )
    }

    private func explanation(
        guide: SaveGuide,
        keepStops: [SaveGuideStop],
        savedSwaps: [SaveGuidePlanStop],
        suggestions: [SaveGuidePlanStop]
    ) -> String {
        let recoveryCount = keepStops.filter { $0.state == .needsRecovery }.count
        return "Customized \(guide.title) with \(savedSwaps.count) saved SAV-E \(savedSwaps.count == 1 ? "place" : "places"), \(suggestions.count) unsaved suggestions, and \(recoveryCount) stops needing recovery."
    }

    private func tripNote(for stop: SaveGuideStop, guide: SaveGuide) -> String {
        var pieces = ["Copied from guide: \(guide.title)", "State: \(stop.state.displayName)"]
        if let creator = guide.creatorLabel {
            pieces.append("Creator: \(creator)")
        }
        if let sourceURL = stop.sourceURL ?? guide.sourceURL {
            pieces.append("Source: \(sourceURL)")
        }
        return pieces.joined(separator: "\n")
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
