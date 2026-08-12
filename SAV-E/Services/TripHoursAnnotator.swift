import Foundation

// MARK: - Structured opening hours

/// One open span in Google's `opening_hours.periods` shape.
/// `day` is 0 = Sunday … 6 = Saturday; minutes count from midnight, and
/// `closeMinutes` may exceed 1440 for spans that cross midnight.
struct SavePlaceOpeningPeriod: Equatable, Codable {
    let day: Int
    let openMinutes: Int
    let closeMinutes: Int

    static func periods(fromGooglePeriods raw: [[String: Any]]?) -> [SavePlaceOpeningPeriod]? {
        guard let raw, !raw.isEmpty else { return nil }
        let parsed = raw.compactMap { period -> SavePlaceOpeningPeriod? in
            guard let open = period["open"] as? [String: Any],
                  let openDay = open["day"] as? Int,
                  (0...6).contains(openDay),
                  let openMinutes = minutes(fromHHMM: open["time"] as? String) else {
                return nil
            }
            guard let close = period["close"] as? [String: Any],
                  let closeDay = close["day"] as? Int,
                  (0...6).contains(closeDay),
                  let closeMinutes = minutes(fromHHMM: close["time"] as? String) else {
                // Google encodes 24/7 as one open with no close.
                return SavePlaceOpeningPeriod(day: openDay, openMinutes: 0, closeMinutes: 24 * 60 * 7)
            }
            let dayOffset = (closeDay - openDay + 7) % 7
            return SavePlaceOpeningPeriod(
                day: openDay,
                openMinutes: openMinutes,
                closeMinutes: dayOffset * 24 * 60 + closeMinutes
            )
        }
        return parsed.isEmpty ? nil : parsed
    }

    private static func minutes(fromHHMM value: String?) -> Int? {
        guard let value, value.count == 4,
              let hours = Int(value.prefix(2)), (0...23).contains(hours),
              let mins = Int(value.suffix(2)), (0...59).contains(mins) else {
            return nil
        }
        return hours * 60 + mins
    }
}

struct SavePlaceOpeningHours: Equatable {
    let periods: [SavePlaceOpeningPeriod]

    var isAlwaysOpen: Bool {
        periods.contains { $0.closeMinutes - $0.openMinutes >= 24 * 60 * 7 }
    }

    func isOpen(day: Int, atMinutes minutes: Int) -> Bool {
        if isAlwaysOpen { return true }
        return periods.contains { period in
            if period.day == day,
               minutes >= period.openMinutes, minutes < period.closeMinutes {
                return true
            }
            // A span that started yesterday and crosses midnight.
            let overnightMinutes = minutes + 24 * 60
            return period.day == (day + 6) % 7
                && period.closeMinutes > 24 * 60
                && overnightMinutes >= period.openMinutes
                && overnightMinutes < period.closeMinutes
        }
    }

    /// Itinerary days carry no calendar date, so "open at this slot" is only
    /// verifiable across all weekdays: open on every day → verified; closed on
    /// some → worth a hours check before committing.
    func weekdaysClosed(atMinutes minutes: Int) -> [Int] {
        (0...6).filter { !isOpen(day: $0, atMinutes: minutes) }
    }
}

// MARK: - Hours provider

protocol TripHoursProviding: Sendable {
    func openingHours(for place: Place) async -> SavePlaceOpeningHours?
}

/// Fetches structured hours from Google Place Details. Best-effort: any miss
/// (no Google place ID, no key, offline, no periods) is simply unknown hours.
struct GoogleTripHoursService: TripHoursProviding {
    var placesService: GooglePlacesServiceProtocol = GooglePlacesService.shared

    func openingHours(for place: Place) async -> SavePlaceOpeningHours? {
        guard let googlePlaceId = place.googlePlaceId, !googlePlaceId.isEmpty else { return nil }
        guard let details = try? await placesService.getPlaceDetails(placeId: googlePlaceId),
              let periods = details.openingPeriods, !periods.isEmpty else {
            return nil
        }
        return SavePlaceOpeningHours(periods: periods)
    }
}

// MARK: - Annotator

/// Decorates a planned itinerary with verified opening hours: stops confirmed
/// open at their slot lose the `.hoursUnknown` risk; stops closed on some
/// weekday gain a `needsHoursCheck` gap. The deterministic draft stays the
/// source of truth for place IDs, day count, and stop order — this only
/// touches risks and health.
struct TripHoursAnnotator {
    var hoursProvider: TripHoursProviding
    /// Per-place fetch budget; the whole annotation is bounded by the slowest
    /// single fetch since they run concurrently.
    var fetchTimeoutNanoseconds: UInt64 = 4_000_000_000
    /// Fetch cap so a huge plan cannot fan out unbounded detail requests.
    var maxPlacesToCheck = 24

    func annotated(
        _ response: SaveAIResponse,
        places: [Place],
        outputLanguage: AppLanguage
    ) async -> SaveAIResponse {
        guard response.componentType == .tripItinerary else { return response }

        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id.uuidString, $0) })
        let checkablePlaces = response.itineraryDays
            .flatMap(\.stops)
            .filter { $0.placeState == .confirmedMapStamp && parseClockMinutes($0.time) != nil }
            .compactMap { $0.placeId.flatMap { placesByID[$0] } }
            .uniqued(by: \.id)
            .prefix(maxPlacesToCheck)

        guard !checkablePlaces.isEmpty else { return response }

        let hoursByPlaceID = await fetchHours(for: Array(checkablePlaces))
        guard !hoursByPlaceID.isEmpty else { return response }

        var updatedResponse = response
        let updatedDays = response.itineraryDays.map { day in
            annotatedDay(day, hoursByPlaceID: hoursByPlaceID, outputLanguage: outputLanguage)
        }
        updatedResponse = updatedResponse.replacingItineraryDays(
            updatedDays,
            tripHealth: response.tripHealth.map {
                TripHealth.aggregating(updatedDays, strengths: $0.strengths)
            }
        )
        return updatedResponse
    }

    // MARK: - Day rewrite

    private func annotatedDay(
        _ day: ItineraryDay,
        hoursByPlaceID: [String: SavePlaceOpeningHours],
        outputLanguage: AppLanguage
    ) -> ItineraryDay {
        var closedStopNames: [String] = []
        let stops = day.stops.map { stop -> ItineraryStop in
            guard stop.placeState == .confirmedMapStamp,
                  let placeID = stop.placeId,
                  let hours = hoursByPlaceID[placeID],
                  let minutes = parseClockMinutes(stop.time) else {
                return stop
            }
            let closedDays = hours.weekdaysClosed(atMinutes: minutes)
            if closedDays.isEmpty {
                var updated = stop
                updated.risks = stop.risks.filter { $0 != .hoursUnknown }
                return updated
            }
            if closedDays.count >= 1 {
                closedStopNames.append(stop.placeName)
            }
            return stop
        }

        guard let health = day.health else {
            return day.replacingStops(stops)
        }

        let dayId = "day-\(day.dayNumber)"
        // Re-derive the hours warning from the updated risks instead of
        // keeping the planner's blanket one.
        var warnings = health.warnings.filter { $0.type != .hoursUnknown }
        let unverifiedStops = stops.filter { $0.risks.contains(.hoursUnknown) }
        if !unverifiedStops.isEmpty {
            warnings.append(TripWarning(
                id: "\(dayId)-hours-unknown",
                type: .hoursUnknown,
                severity: .low,
                message: outputLanguage.localized(
                    english: "Opening hours are not verified for every stop.",
                    traditionalChinese: "不是每一站都已確認營業時間。"
                ),
                dayId: dayId,
                affectedBlockIds: unverifiedStops.map(\.id.uuidString)
            ))
        }

        var gaps = health.gaps.filter { $0.type != .needsHoursCheck }
        if !closedStopNames.isEmpty {
            let names = closedStopNames.joined(separator: ", ")
            gaps.append(TripGap(
                id: "\(dayId)-needs-hours-check",
                type: .needsHoursCheck,
                dayId: dayId,
                severity: .medium,
                message: outputLanguage.localized(
                    english: "\(names): closed at the planned time on some weekdays — check hours before committing.",
                    traditionalChinese: "\(names)：在排定時段有些日子沒營業，確認行程前先查一下營業時間。"
                )
            ))
        }

        var updatedDay = day.replacingStops(stops)
        updatedDay.health = TripHealth.scored(
            strengths: health.strengths,
            warnings: warnings,
            gaps: gaps
        )
        return updatedDay
    }

    // MARK: - Fetch

    private func fetchHours(for places: [Place]) async -> [String: SavePlaceOpeningHours] {
        await withTaskGroup(of: (String, SavePlaceOpeningHours)?.self) { group in
            for place in places {
                group.addTask {
                    let hours = await withTimeout(fetchTimeoutNanoseconds) {
                        await hoursProvider.openingHours(for: place)
                    }
                    guard let hours else { return nil }
                    return (place.id.uuidString, hours)
                }
            }
            var result: [String: SavePlaceOpeningHours] = [:]
            for await entry in group {
                if let (id, hours) = entry { result[id] = hours }
            }
            return result
        }
    }

    /// Parses the planner's fixed "h:mm AM/PM" clock strings into minutes
    /// since midnight. Anything else (missing, localized, model-invented) is
    /// unparseable → the stop stays unverified.
    private func parseClockMinutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let trimmed = time.trimmingCharacters(in: .whitespaces).uppercased()
        let isPM = trimmed.hasSuffix("PM")
        let isAM = trimmed.hasSuffix("AM")
        guard isPM || isAM else { return nil }
        let clock = trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)
        let parts = clock.split(separator: ":")
        guard parts.count == 2,
              let rawHour = Int(parts[0]), (1...12).contains(rawHour),
              let minute = Int(parts[1]), (0...59).contains(minute) else {
            return nil
        }
        var hour = rawHour % 12
        if isPM { hour += 12 }
        return hour * 60 + minute
    }
}

// MARK: - Helpers

private func withTimeout<T: Sendable>(
    _ nanoseconds: UInt64,
    _ operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: nanoseconds)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

private extension Sequence {
    func uniqued<ID: Hashable>(by key: (Element) -> ID) -> [Element] {
        var seen = Set<ID>()
        return filter { seen.insert(key($0)).inserted }
    }
}

extension SaveAIResponse {
    func replacingItineraryDays(_ days: [ItineraryDay], tripHealth: TripHealth?) -> SaveAIResponse {
        SaveAIResponse(
            componentType: componentType,
            title: title,
            placeIds: placeIds,
            navigationPlaceId: navigationPlaceId,
            transportMode: transportMode,
            itineraryDays: days,
            tripHealth: tripHealth,
            messageText: messageText,
            mapAction: mapAction,
            aiMessage: aiMessage,
            followUpChoices: followUpChoices,
            travelLegs: travelLegs
        )
    }
}
