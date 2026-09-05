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
            unusedUnsaved.removeAll { $0.category != .stay && usedNames.contains($0.title) }
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

    /// Validate travel against the scheduled order; routing must never move a meal or a stay.
    static func checkingTravel(
        _ response: SaveAIResponse,
        savedPlaces: [Place],
        language: AppLanguage,
        routeService: TripRouteServiceProtocol = GoogleTripRouteService()
    ) async -> SaveAIResponse {
        let placesByID = Dictionary(savedPlaces.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var days: [ItineraryDay] = []
        var legs: [TripTravelLeg] = []
        for day in response.itineraryDays {
            guard !Task.isCancelled else { return response }
            guard day.stops.count > 1 else { days.append(day); continue }
            let routePlaces = day.stops.compactMap { stop -> Place? in
                if let id = stop.placeId { return placesByID[id] }
                guard let candidate = stop.mapCandidate else { return nil }
                return Place(
                    id: stop.id, name: candidate.title, address: candidate.subtitle,
                    latitude: candidate.latitude, longitude: candidate.longitude,
                    category: candidate.category ?? .attraction, status: .wantToGo,
                    sourcePlatform: candidate.sourcePlatform ?? .other, createdAt: candidate.createdAt
                )
            }
            var updated = day
            do {
                guard routePlaces.count == day.stops.count else { throw TripRouteServiceError.invalidResponse }
                let route = try await routeService.fixedOrderDay(routePlaces, mode: response.transportMode)
                guard !Task.isCancelled else { return response }
                guard route.orderedPlaces.map(\.id) == routePlaces.map(\.id),
                      route.legs.count == day.stops.count - 1 else { throw TripRouteServiceError.invalidResponse }
                var stops = day.stops
                for index in 1..<stops.count {
                    let leg = route.legs[index - 1]
                    guard leg.fromPlaceId == stops[index - 1].routingID,
                          leg.toPlaceId == stops[index].routingID,
                          leg.durationMinutes > 0 else { throw TripRouteServiceError.invalidResponse }
                    if let previousStart = TripClock.minutes(fromDisplay: stops[index - 1].time ?? ""),
                       let nextStart = TripClock.minutes(fromDisplay: stops[index].time ?? ""),
                       previousStart + (stops[index - 1].duration ?? 60) + leg.durationMinutes > nextStart {
                        if !stops[index].risks.contains(.tooFarFromPrevious) { stops[index].risks.append(.tooFarFromPrevious) }
                    }
                }
                updated = day.replacingStops(stops)
                legs.append(contentsOf: route.legs)
                if stops.contains(where: { $0.risks.contains(.tooFarFromPrevious) }) {
                    let warning = language.localized(
                        english: "Travel does not fit between some stops. Adjust the order or times before following this draft.",
                        traditionalChinese: "部分站點間的交通時間不足。出發前請調整順序或時段。"
                    )
                    updated.windowNote = [day.windowNote, warning].compactMap { $0 }.joined(separator: " · ")
                }
            } catch {
                let warning = language.localized(
                    english: "Travel times are unverified. Check the route before following this draft.",
                    traditionalChinese: "交通時間尚未確認。出發前請先檢查路線。"
                )
                updated.windowNote = [day.windowNote, warning].compactMap { $0 }.joined(separator: " · ")
            }
            days.append(updated)
        }
        var result = response.replacingItineraryDays(days, tripHealth: response.tripHealth)
        result.travelLegs = legs
        return result
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
        return terms.map {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
        }
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
