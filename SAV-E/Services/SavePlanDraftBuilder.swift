import Foundation

struct SavePlanRequest: Equatable {
    var area: String
    var days: Int
    var pace: ItineraryPace
    var arrivalMinutes: Int?
    var departureMinutes: Int?
    var language: AppLanguage
    var usesFlightBuffers: Bool = true
    var anchorPlaceID: UUID? = nil
    var excludedPlaceIDs: Set<UUID> = []
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
        let excluded = inArea.filter { !$0.savedIDs.isDisjoint(with: request.excludedPlaceIDs) }
        let plannable = inArea.filter {
            $0.savedIDs.isDisjoint(with: request.excludedPlaceIDs) && ($0.latitude != 0 || $0.longitude != 0)
        }
        guard !plannable.isEmpty else { return nil }

        guard (1...TripPlanningIntent.maximumDays).contains(request.days) else { return nil }
        let days = request.days
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
        if !request.usesFlightBuffers {
            windows.airportBufferMinutes = 0
            windows.airportTransferMinutes = 0
        }
        let lodging = plannable.first(where: { $0.category == .stay })
        let scheduler = SaveDayRhythmScheduler()
        var unusedUnsaved = unsavedCandidates.filter { candidate in
            matches(area: request.area, candidate: candidate) && !excluded.contains {
                $0.name.caseInsensitiveCompare(candidate.title) == .orderedSame
                    && abs($0.latitude - candidate.latitude) < 0.001 && abs($0.longitude - candidate.longitude) < 0.001
            }
        }
        // A thin vault must not silently turn a six-day request into one day.
        let plannedDays = (1...days).map { number in
            response.itineraryDays.first(where: { $0.dayNumber == number }) ?? ItineraryDay(
                dayNumber: number,
                label: request.language.localized(english: "Day \(number) · needs more places", traditionalChinese: "第 \(number) 天 · 待補地點"),
                stops: []
            )
        }
        let dayCount = days

        let rebuiltDays: [ItineraryDay] = plannedDays.map { day in
            var dayPlaces = day.stops.compactMap { stop -> Place? in
                guard let raw = stop.placeId, let id = UUID(uuidString: raw) else { return nil }
                return plannable.first(where: { $0.id == id })
            }
            if let anchorID = request.anchorPlaceID,
               let anchor = plannable.first(where: { $0.id == anchorID }) {
                dayPlaces.removeAll { $0.id == anchorID }
                if day.dayNumber == 1 { dayPlaces.insert(anchor, at: 0) }
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
            let scheduledStops = paceLimitedStops(result.stops, maxStops: request.pace.maxStopsPerDay,
                                                  savedPlaces: plannable, anchorPlaceID: request.anchorPlaceID)
            let usedNames = Set(scheduledStops.map(\.placeName))
            unusedUnsaved.removeAll { $0.category != .stay && usedNames.contains($0.title) }
            let health = DeterministicTripPlanner().tripHealth(
                for: scheduledStops,
                savedPlaces: plannable,
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
                stops: scheduledStops,
                health: TripHealth.scored(
                    strengths: health.strengths,
                    warnings: health.warnings,
                    gaps: mergedGaps
                ),
                windowNote: result.windowNote
            )
        }

        let placeIds = rebuiltDays.flatMap(\.stops).compactMap(\.placeId)
        if let anchor = request.anchorPlaceID, !placeIds.contains(anchor.uuidString) { return nil }
        response = SaveAIResponse(
            componentType: .tripItinerary,
            title: request.language.localized(english: "\(request.area) · \(days) days", traditionalChinese: "\(request.area) · \(days) 天"),
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

    static func removalTarget(in message: String) -> String? {
        let pattern = #"(?i)^(?:(?:keep the plan but|please)\s+)?remove\s+(.+?)(?:\s+from (?:the|my) (?:plan|draft))?[.!]?$|^(?:保留行程[，,]?但)?(?:移除|刪除|去掉)\s*(.+?)[。！]?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..<message.endIndex, in: message)) else { return nil }
        for group in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: group), in: message) { return String(message[range]) }
        }
        return nil
    }

    /// Explicit removal changes only the in-memory draft. Exact saved identity
    /// and a unique name/address match are required; ambiguity changes nothing.
    static func removingConfirmedStop(named target: String, from draft: SaveAIResponse,
                                      savedPlaces: [Place], area: String, pace: ItineraryPace,
                                      language: AppLanguage) -> (draft: SaveAIResponse, removedIDs: Set<UUID>)? {
        func key(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let allStops = draft.itineraryDays.flatMap(\.stops)
        let draftIDs = Set(allStops.compactMap { $0.placeId.flatMap(UUID.init(uuidString:)) })
        let matches = savedPlaces.filter { place in
            guard Self.matches(area: area, place: place), !place.savedIDs.isDisjoint(with: draftIDs) else { return false }
            let displayedNames = allStops.filter { $0.placeId.flatMap(UUID.init(uuidString:)).map(place.savedIDs.contains) ?? false }.map(\.placeName)
            let labels = [place.name, "\(place.name), \(place.address)"] + displayedNames
            return labels.contains { key($0) == key(target) }
        }
        guard matches.count == 1, let place = matches.first else { return nil }
        let removedIDs = place.savedIDs
        let eligible = savedPlaces.filter { $0.savedIDs.isDisjoint(with: removedIDs) }
        let days = draft.itineraryDays.map { day in
            let stops = day.stops.filter { stop in
                !(stop.placeId.flatMap(UUID.init(uuidString:)).map(removedIDs.contains) ?? false)
            }
            var changed = day.replacingStops(stops)
            changed.health = DeterministicTripPlanner().tripHealth(for: stops, savedPlaces: eligible,
                dayNumber: day.dayNumber, maxStopsPerDay: pace.maxStopsPerDay, outputLanguage: language)
            return changed
        }
        let remainingIDs = days.flatMap(\.stops).compactMap(\.placeId)
        let response = SaveAIResponse(componentType: draft.componentType, title: draft.title,
            placeIds: remainingIDs, navigationPlaceId: draft.navigationPlaceId.flatMap { remainingIDs.contains($0) ? $0 : nil },
            transportMode: draft.transportMode, itineraryDays: days,
            tripHealth: DeterministicTripPlanner().overallTripHealth(for: days, outputLanguage: language),
            messageText: draft.messageText, mapAction: nil, aiMessage: nil)
        return (response, removedIDs)
    }

    /// Pick the anchor and saved lodging constraints before ordinary memory and external fills,
    /// then retain the scheduler's chronological order and clocks.
    static func paceLimitedStops(_ stops: [ItineraryStop], maxStops: Int,
                                 savedPlaces: [Place], anchorPlaceID: UUID?) -> [ItineraryStop] {
        let savedIDs = Set(savedPlaces.flatMap { $0.savedIDs })
        let anchorIDs = savedPlaces.first(where: { $0.id == anchorPlaceID })?.savedIDs ?? []
        let lodgingIDs = Set(savedPlaces.filter { $0.category == .stay }.flatMap { $0.savedIDs })
        func priority(_ stop: ItineraryStop) -> Int {
            guard let raw = stop.placeId, let id = UUID(uuidString: raw) else { return 3 }
            if anchorIDs.contains(id) { return 0 }
            if lodgingIDs.contains(id) { return 1 }
            return savedIDs.contains(id) ? 2 : 3
        }
        let chosen = stops.indices.sorted {
            let left = priority(stops[$0]), right = priority(stops[$1])
            return left == right ? $0 < $1 : left < right
        }.prefix(max(0, maxStops))
        let indices = Set(chosen)
        return stops.enumerated().filter { indices.contains($0.offset) }.map(\.element)
    }

    /// Plan conditions own place identity, day count, pace and clocks. A remote
    /// polish may change notes only when it echoes that exact schedule.
    static func preservingSchedule(_ polished: SaveAIResponse, draft: SaveAIResponse) -> SaveAIResponse {
        guard polished.componentType == .tripItinerary,
              polished.itineraryDays.count == draft.itineraryDays.count else { return draft }
        var days: [ItineraryDay] = []
        for (original, proposed) in zip(draft.itineraryDays, polished.itineraryDays) {
            guard original.dayNumber == proposed.dayNumber, original.stops.count == proposed.stops.count else { return draft }
            var stops: [ItineraryStop] = []
            for (stop, copy) in zip(original.stops, proposed.stops) {
                guard stop.placeId == copy.placeId, stop.placeName == copy.placeName,
                      stop.time == copy.time, stop.duration == copy.duration else { return draft }
                stops.append(ItineraryStop(
                    id: stop.id, placeId: stop.placeId, placeState: stop.placeState,
                    placeName: stop.placeName, time: stop.time, duration: stop.duration,
                    note: copy.note ?? stop.note, sourceSummary: stop.sourceSummary,
                    risks: stop.risks, mapCandidate: stop.mapCandidate
                ))
            }
            days.append(ItineraryDay(dayNumber: original.dayNumber, label: original.label,
                                     stops: stops, health: original.health, windowNote: original.windowNote))
        }
        return draft.replacingItineraryDays(days, tripHealth: draft.tripHealth)
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

    /// Prefer the actual locality over the US state/country component used by
    /// generic share labels. A coordinate-only stamp can still use its name.
    static func areaLabel(for place: Place) -> String? {
        let parts = place.address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let locality = (parts.count >= 3 ? Array(parts.dropFirst()) : parts).joined(separator: ", ")
        if let city = SaveSearchIntentParser.namedArea(in: " " + SaveSearchIntentParser.normalize(locality)) { return city }
        let countries = ["us", "usa", "united states", "united states of america"]
        var localParts = parts
        if let last = localParts.last, countries.contains(last.lowercased()) { localParts.removeLast() }
        if localParts.count >= 2, let region = localParts.last,
           region.range(of: #"^[A-Z]{2}(?:\s+\d{5}(?:-\d{4})?)?$"#, options: .regularExpression) != nil {
            return localParts[localParts.count - 2]
        }
        guard let label = SavedPlaceTripRecommender.areaLabel(for: place),
              label.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) == nil else { return nil }
        return label
    }

    static func areas(from places: [Place]) -> [String] {
        var counts: [String: Int] = [:]
        for place in places {
            let label = areaLabel(for: place) ?? place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { counts[label, default: 0] += 1 }
        }
        return counts.keys.sorted { lhs, rhs in
            if counts[lhs, default: 0] != counts[rhs, default: 0] {
                return counts[lhs, default: 0] > counts[rhs, default: 0]
            }
            return lhs < rhs
        }
    }

    static func matches(area: String, place: Place) -> Bool {
        let label = areaLabel(for: place) ?? place.name
        return !Set(SavePlanConversationConditions.areaAliases(area))
            .isDisjoint(with: SavePlanConversationConditions.areaAliases(label))
    }

    static func matches(area: String, candidate: SaveMapCandidate) -> Bool {
        matches(area: area, text: "\(candidate.title) \(candidate.subtitle)")
    }

    private static func matches(area: String, text: String) -> Bool {
        let needle = area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let foldedNeedle = needle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).replacingOccurrences(of: "臺", with: "台")
        let foldedText = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).replacingOccurrences(of: "臺", with: "台")
        return SavePlanConversationConditions.areaAliases(foldedNeedle).contains { alias in
            if alias.range(of: #"^[a-z .'-]+$"#, options: .regularExpression) != nil {
                return foldedText.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: alias) + #"\b"#, options: .regularExpression) != nil
            }
            return foldedText.contains(alias)
        }
    }

    private static func searchTerms(for area: String) -> [String] {
        SavePlanConversationConditions.areaAliases(area)
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
                english: request.usesFlightBuffers ? "Flight times only shrink the walking day. Savvy does not book tickets." : "Your start and end clocks bound the itinerary; airport transfers are not assumed.",
                traditionalChinese: request.usesFlightBuffers ? "機票時間只用來縮短可走路程；Savvy 不會代訂機票。" : "開始與結束時間只限制可排行程的時段，不會自行假設機場接駁時間。"
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
