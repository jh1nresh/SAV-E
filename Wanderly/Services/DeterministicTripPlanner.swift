import CoreLocation
import Foundation

struct DeterministicTripPlanner {
    private struct Candidate {
        let place: Place
        let score: Int
    }

    private struct ScheduledPlace {
        let place: Place
        let time: String
        let duration: Int
        let note: String
    }

    func plan(for message: String, places: [Place]) -> WanderlyAIResponse? {
        guard isItineraryRequest(message), !places.isEmpty else { return nil }

        let days = requestedDayCount(from: message, placeCount: places.count)
        let selectedPlaces = selectedPlaces(for: message, places: places, days: days)
        guard !selectedPlaces.isEmpty else { return nil }

        let orderedPlaces = nearestNeighborOrder(selectedPlaces)
        let groupedPlaces = groups(orderedPlaces, requestedDays: days)
        let itineraryDays = groupedPlaces.enumerated().map { index, places in
            let scheduled = schedule(places)
            return ItineraryDay(
                dayNumber: index + 1,
                label: "Day \(index + 1)",
                stops: scheduled.map { item in
                    ItineraryStop(
                        id: UUID(),
                        placeId: item.place.id.uuidString,
                        placeName: item.place.name,
                        time: item.time,
                        duration: item.duration,
                        note: item.note
                    )
                }
            )
        }

        let placeIds = orderedPlaces.map { $0.id.uuidString }
        return WanderlyAIResponse(
            componentType: .tripItinerary,
            title: title(for: message, dayCount: itineraryDays.count),
            placeIds: placeIds,
            navigationPlaceId: nil,
            transportMode: selectedPlaces.count > 3 ? .driving : .walking,
            itineraryDays: itineraryDays,
            messageText: nil,
            mapAction: MapActionData(type: .showRoute, placeIds: placeIds, lat: nil, lng: nil, span: nil),
            aiMessage: "Built a deterministic draft from your saved places, ordered by distance with simple meal and time-slot rules."
        )
    }

    // MARK: - Intent

    private func isItineraryRequest(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let keywords = [
            "plan", "itinerary", "trip", "route", "schedule", "organize",
            "day", "days", "weekend", "行程", "規劃", "旅程", "路線", "天", "日"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private func requestedDayCount(from message: String, placeCount: Int) -> Int {
        let normalized = message.lowercased()
        let patterns = [
            #"(\d+)\s*[- ]?\s*days?"#,
            #"(\d+)\s*[- ]?\s*day"#,
            #"(\d+)\s*[天日]"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: normalized),
               let value = Int(normalized[range]) {
                return max(1, min(value, 7))
            }
        }

        if normalized.contains("weekend") {
            return 2
        }

        return max(1, min(3, Int(ceil(Double(placeCount) / 4.0))))
    }

    // MARK: - Selection

    private func selectedPlaces(for message: String, places: [Place], days: Int) -> [Place] {
        let candidates = places.map { Candidate(place: $0, score: relevanceScore(for: $0, message: message)) }
        let positive = candidates.filter { $0.score > 0 }
        let source = positive.isEmpty ? candidates : positive
        let maxStops = max(3, days * 5)

        return source
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.place.createdAt > rhs.place.createdAt
            }
            .prefix(maxStops)
            .map(\.place)
    }

    private func relevanceScore(for place: Place, message: String) -> Int {
        let normalized = normalize(message)
        let searchable = normalize("\(place.name) \(place.address) \(place.category.rawValue) \(place.category.displayName)")
        let tokens = tokens(from: normalized)
        var score = 0

        for token in tokens where searchable.contains(token) {
            score += place.name.lowercased().contains(token) ? 5 : 3
        }

        if categoryAliases(for: place.category).contains(where: { normalized.contains($0) }) {
            score += 4
        }

        if place.status == .visited {
            score -= 1
        }

        return score
    }

    private func tokens(from normalized: String) -> [String] {
        let stopWords: Set<String> = [
            "plan", "itinerary", "trip", "route", "schedule", "organize", "show",
            "my", "the", "a", "an", "to", "for", "from", "with", "and", "or",
            "day", "days", "weekend", "places", "spots", "saved"
        ]

        return normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) && Int($0) == nil }
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func categoryAliases(for category: PlaceCategory) -> [String] {
        switch category {
        case .food: return ["food", "restaurant", "restaurants", "eat", "eats", "lunch", "dinner", "美食", "餐廳"]
        case .cafe: return ["cafe", "coffee", "breakfast", "brunch", "咖啡"]
        case .bar: return ["bar", "drink", "drinks", "night", "cocktail", "酒吧"]
        case .attraction: return ["attraction", "attractions", "sight", "sights", "museum", "park", "景點"]
        case .stay: return ["stay", "hotel", "hotels", "resort", "住宿", "飯店"]
        case .shopping: return ["shopping", "shop", "shops", "market", "mall", "購物"]
        }
    }

    // MARK: - Grouping and ordering

    private func nearestNeighborOrder(_ places: [Place]) -> [Place] {
        guard places.count > 1 else { return places }

        var remaining = places
        let startIndex = remaining.indices.min { lhs, rhs in
            let left = remaining[lhs]
            let right = remaining[rhs]
            if left.longitude != right.longitude { return left.longitude < right.longitude }
            return left.latitude > right.latitude
        } ?? remaining.startIndex

        var ordered = [remaining.remove(at: startIndex)]
        while let current = ordered.last, !remaining.isEmpty {
            let nextIndex = remaining.indices.min { lhs, rhs in
                distance(from: current, to: remaining[lhs]) < distance(from: current, to: remaining[rhs])
            } ?? remaining.startIndex
            ordered.append(remaining.remove(at: nextIndex))
        }
        return ordered
    }

    private func groups(_ places: [Place], requestedDays: Int) -> [[Place]] {
        let dayCount = max(1, min(requestedDays, places.count))
        let chunkSize = Int(ceil(Double(places.count) / Double(dayCount)))
        return stride(from: 0, to: places.count, by: chunkSize).map { start in
            Array(places[start..<min(start + chunkSize, places.count)])
        }
    }

    // MARK: - Scheduling

    private func schedule(_ places: [Place]) -> [ScheduledPlace] {
        var foodCount = 0
        return places.enumerated().map { index, place in
            let previous = index > 0 ? places[index - 1] : nil
            let slot = timeSlot(for: place, index: index, count: places.count, foodCount: foodCount)
            if place.category == .food { foodCount += 1 }

            return ScheduledPlace(
                place: place,
                time: slot.time,
                duration: slot.duration,
                note: note(for: place, previous: previous, defaultNote: slot.note)
            )
        }
    }

    private func timeSlot(for place: Place, index: Int, count: Int, foodCount: Int) -> (time: String, duration: Int, note: String) {
        switch place.category {
        case .cafe:
            return index <= 1
                ? ("9:00 AM", 60, "Good morning or coffee stop.")
                : ("2:30 PM", 45, "Good reset stop between bigger plans.")
        case .food:
            return foodCount == 0 && index < max(2, count - 1)
                ? ("12:30 PM", 90, "Meal slot based on saved food memory.")
                : ("6:30 PM", 105, "Dinner slot based on saved food memory.")
        case .bar:
            return ("8:30 PM", 90, "Evening stop.")
        case .attraction:
            return index <= 1
                ? ("10:30 AM", 90, "Anchor activity.")
                : ("3:30 PM", 90, "Afternoon activity.")
        case .shopping:
            return ("3:00 PM", 75, "Flexible afternoon stop.")
        case .stay:
            return index == 0
                ? ("9:30 AM", 30, "Start from this stay or base.")
                : ("4:00 PM", 30, "Check-in or reset stop.")
        }
    }

    private func note(for place: Place, previous: Place?, defaultNote: String) -> String {
        guard let previous else { return defaultNote }
        let kilometers = distance(from: previous, to: place) / 1_000
        if kilometers >= 80 {
            return "\(defaultNote) Far from the previous stop; check driving or transit before committing."
        }
        if kilometers >= 25 {
            return "\(defaultNote) Build in extra travel time from the previous stop."
        }
        return defaultNote
    }

    private func distance(from lhs: Place, to rhs: Place) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func title(for message: String, dayCount: Int) -> String {
        if dayCount == 1 {
            return "SAV-E Day Plan"
        }
        return "SAV-E \(dayCount)-Day Plan"
    }
}
