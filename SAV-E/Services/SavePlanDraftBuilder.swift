import Foundation

struct SavePlanRequest: Equatable {
    var area: String
    var days: Int
    var pace: ItineraryPace
    var arrivalMinutes: Int?
    var departureMinutes: Int?
    var language: AppLanguage
}

/// Turns a Plan composer request into an itinerary draft.
///
/// Selection and day grouping stay on `DeterministicTripPlanner`. This layer
/// only applies travel windows, meal rhythm, lodging check-in/out, and labeled
/// unsaved fills so the Plan tab has one contract.
enum SavePlanDraftBuilder {
    static func draft(
        request: SavePlanRequest,
        savedPlaces: [Place],
        unsavedCandidates: [SaveMapCandidate] = []
    ) -> SaveAIResponse? {
        let inArea = savedPlaces.filter { matches(area: request.area, place: $0) }
        let plannable = inArea.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !plannable.isEmpty else { return nil }

        let days = max(1, min(request.days, TripPlanningIntent.maximumDays))
        let query = days == 1
            ? "Plan a day in \(request.area)"
            : "Plan \(days) days in \(request.area)"
        let intent = TripPlanningIntent(
            days: days,
            searchTerms: searchTerms(for: request.area),
            rawMessage: pacePhrase(request.pace, query: query)
        )
        guard var response = DeterministicTripPlanner().plan(
            intent: intent,
            places: plannable,
            outputLanguage: request.language
        ) else { return nil }

        var windows = TripPlanWindows.standard
        windows.arrivalMinutes = request.arrivalMinutes
        windows.departureMinutes = request.departureMinutes
        let lodging = plannable.first(where: { $0.category == .stay })
        let scheduler = SaveDayRhythmScheduler()
        var unusedUnsaved = unsavedCandidates.filter { matches(area: request.area, candidate: $0) }
        let dayCount = max(response.itineraryDays.count, 1)

        let rebuiltDays: [ItineraryDay] = response.itineraryDays.enumerated().map { _, day in
            let dayPlaces = day.stops.compactMap { stop -> Place? in
                guard let raw = stop.placeId, let id = UUID(uuidString: raw) else { return nil }
                return plannable.first(where: { $0.id == id })
            }
            let result = scheduler.schedule(
                orderedPlaces: dayPlaces,
                unsavedCandidates: unusedUnsaved,
                lodging: lodging,
                dayNumber: day.dayNumber,
                dayCount: dayCount,
                windows: windows,
                outputLanguage: request.language
            )
            let usedNames = Set(result.stops.map(\.placeName))
            unusedUnsaved.removeAll { usedNames.contains($0.title) }
            let health = DeterministicTripPlanner().tripHealth(
                for: result.stops,
                dayNumber: day.dayNumber,
                maxStopsPerDay: request.pace.maxStopsPerDay,
                outputLanguage: request.language
            )
            let mergedGaps = health.gaps + result.gaps.filter { extra in
                !health.gaps.contains(where: { $0.type == extra.type && $0.dayId == extra.dayId })
            }
            return ItineraryDay(
                dayNumber: day.dayNumber,
                label: day.label,
                stops: result.stops,
                health: TripHealth.scored(
                    strengths: health.strengths,
                    warnings: health.warnings,
                    gaps: mergedGaps
                ),
                windowNote: result.windowNote
            )
        }

        let placeIds = rebuiltDays.flatMap(\.stops).compactMap(\.placeId)
        response = SaveAIResponse(
            componentType: .tripItinerary,
            title: response.title,
            placeIds: placeIds,
            navigationPlaceId: response.navigationPlaceId,
            transportMode: response.transportMode,
            itineraryDays: rebuiltDays,
            tripHealth: DeterministicTripPlanner().overallTripHealth(
                for: rebuiltDays,
                outputLanguage: request.language
            ),
            messageText: response.messageText,
            mapAction: MapActionData(
                type: .showRoute,
                placeIds: placeIds,
                lat: nil,
                lng: nil,
                span: nil,
                transportMode: response.transportMode
            ),
            aiMessage: planningMessage(request: request, lodging: lodging, outputLanguage: request.language),
            followUpChoices: response.followUpChoices,
            travelLegs: []
        )
        return response
    }

    static func areas(from places: [Place]) -> [String] {
        var counts: [String: Int] = [:]
        for place in places {
            guard let area = SavedPlaceTripRecommender.areaLabel(for: place) else { continue }
            counts[area, default: 0] += 1
        }
        return counts.keys.sorted { lhs, rhs in
            if counts[lhs, default: 0] != counts[rhs, default: 0] {
                return counts[lhs, default: 0] > counts[rhs, default: 0]
            }
            return lhs < rhs
        }
    }

    static func matches(area: String, place: Place) -> Bool {
        matches(area: area, text: "\(place.name) \(place.address) \(SavedPlaceTripRecommender.areaLabel(for: place) ?? "")")
    }

    static func matches(area: String, candidate: SaveMapCandidate) -> Bool {
        matches(area: area, text: "\(candidate.title) \(candidate.subtitle)")
    }

    private static func matches(area: String, text: String) -> Bool {
        let needle = area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let foldedNeedle = needle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let foldedText = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if foldedText.contains(foldedNeedle) { return true }
        if foldedNeedle.contains("taipei") && (foldedText.contains("台北") || foldedText.contains("臺北")) {
            return true
        }
        if (foldedNeedle.contains("台北") || foldedNeedle.contains("臺北")) && foldedText.contains("taipei") {
            return true
        }
        return false
    }

    private static func searchTerms(for area: String) -> [String] {
        let trimmed = area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var terms = [trimmed]
        if trimmed.contains("台北") || trimmed.contains("臺北") { terms.append("taipei") }
        if trimmed.lowercased().contains("taipei") { terms.append("台北") }
        return terms
    }

    private static func pacePhrase(_ pace: ItineraryPace, query: String) -> String {
        switch pace {
        case .relaxed: return "\(query) relaxed"
        case .packed: return "\(query) packed"
        case .balanced: return query
        }
    }

    private static func planningMessage(
        request: SavePlanRequest,
        lodging: Place?,
        outputLanguage: AppLanguage
    ) -> String {
        var notes = [
            outputLanguage.localized(
                english: "Drafted from your confirmed Map Stamps in \(request.area). Unsaved suggestions stay labeled until you approve them.",
                traditionalChinese: "先用你在\(request.area)已確認的地圖章排出草稿。未存候選會分開標記，核准後才留下。"
            )
        ]
        if request.arrivalMinutes != nil || request.departureMinutes != nil {
            notes.append(outputLanguage.localized(
                english: "Flight times only shrink the walking day. Savvy does not book tickets.",
                traditionalChinese: "機票時間只用來縮短可走路程；Savvy 不會代訂機票。"
            ))
        }
        if lodging == nil, request.days >= 2 {
            notes.append(outputLanguage.localized(
                english: "No saved stay yet, so lodging is still a gap.",
                traditionalChinese: "還沒有已存住宿，所以住宿仍是缺口。"
            ))
        }
        return notes.joined(separator: " ")
    }
}
