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

    func plan(for message: String, places: [Place], outputLanguage: AppLanguage = .english) -> SaveAIResponse? {
        guard isItineraryRequest(message), !places.isEmpty else { return nil }

        let days = requestedDayCount(from: message, placeCount: places.count)
        let selectedPlaces = selectedPlaces(for: message, places: places, days: days)
        guard !selectedPlaces.isEmpty else { return nil }

        let orderedPlaces = nearestNeighborOrder(selectedPlaces)
        let groupedPlaces = groups(orderedPlaces, requestedDays: days)
        let itineraryDays = groupedPlaces.enumerated().map { index, places in
            let scheduled = schedule(places, outputLanguage: outputLanguage)
            return ItineraryDay(
                dayNumber: index + 1,
                label: dayLabel(index + 1, outputLanguage: outputLanguage),
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
        return SaveAIResponse(
            componentType: .tripItinerary,
            title: title(for: message, dayCount: itineraryDays.count, outputLanguage: outputLanguage),
            placeIds: placeIds,
            navigationPlaceId: nil,
            transportMode: selectedPlaces.count > 3 ? .driving : .walking,
            itineraryDays: itineraryDays,
            messageText: nil,
            mapAction: MapActionData(type: .showRoute, placeIds: placeIds, lat: nil, lng: nil, span: nil),
            aiMessage: planningMessage(for: message, selectedPlaces: selectedPlaces, outputLanguage: outputLanguage)
        )
    }

    func isItineraryRequest(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let keywords = [
            "plan", "itinerary", "trip", "route", "schedule", "organize",
            "weekend", "行程", "規劃", "规划", "旅程", "路線", "路线", "安排",
            "怎麼排", "怎么排"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    // MARK: - Intent

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

        let chineseDayCounts: [(String, Int)] = [
            ("一天", 1), ("一日", 1),
            ("兩天", 2), ("两天", 2), ("二天", 2), ("二日", 2),
            ("三天", 3), ("三日", 3),
            ("四天", 4), ("四日", 4),
            ("五天", 5), ("五日", 5),
            ("六天", 6), ("六日", 6),
            ("七天", 7), ("七日", 7)
        ]
        if let count = chineseDayCounts.first(where: { normalized.contains($0.0) })?.1 {
            return count
        }

        return max(1, min(3, Int(ceil(Double(placeCount) / 4.0))))
    }

    // MARK: - Selection

    private func selectedPlaces(for message: String, places: [Place], days: Int) -> [Place] {
        let candidates = places.map { Candidate(place: $0, score: relevanceScore(for: $0, message: message)) }
        let positive = candidates.filter { $0.score > 0 }
        if positive.isEmpty, hasSpecificPlanningConstraint(message) {
            return []
        }
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

    private func hasSpecificPlanningConstraint(_ message: String) -> Bool {
        !tokens(from: normalize(message)).isEmpty
    }

    private func relevanceScore(for place: Place, message: String) -> Int {
        let normalized = normalize(message)
        let searchable = normalize("\(place.name) \(place.address) \(place.category.rawValue) \(place.category.displayName)")
        let tokens = tokens(from: normalized)
        var score = 0

        for token in tokens where searchable.contains(token) {
            score += place.name.lowercased().contains(token) ? 5 : 3
        }

        score += locationAliasScore(for: searchable, tokens: tokens)

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
            .filter { token in
                let shortLocationTokens: Set<String> = ["la", "oc", "ny", "sf", "sd"]
                return (token.count >= 3 || shortLocationTokens.contains(token))
                    && !stopWords.contains(token)
                    && Int(token) == nil
            }
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func locationAliasScore(for searchable: String, tokens: [String]) -> Int {
        let aliases: [String: [String]] = [
            "la": ["los angeles"],
            "oc": ["orange county", "irvine", "anaheim", "costa mesa", "newport beach", "westminster"],
            "ny": ["new york"],
            "sf": ["san francisco"],
            "sd": ["san diego"]
        ]

        return tokens.reduce(0) { score, token in
            guard let expansions = aliases[token],
                  expansions.contains(where: { searchable.contains($0) }) else {
                return score
            }
            return score + 4
        }
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

    private func schedule(_ places: [Place], outputLanguage: AppLanguage) -> [ScheduledPlace] {
        var foodCount = 0
        return places.enumerated().map { index, place in
            let previous = index > 0 ? places[index - 1] : nil
            let slot = timeSlot(for: place, index: index, count: places.count, foodCount: foodCount, outputLanguage: outputLanguage)
            if place.category == .food { foodCount += 1 }

            return ScheduledPlace(
                place: place,
                time: slot.time,
                duration: slot.duration,
                note: note(for: place, previous: previous, defaultNote: slot.note, outputLanguage: outputLanguage)
            )
        }
    }

    private func timeSlot(
        for place: Place,
        index: Int,
        count: Int,
        foodCount: Int,
        outputLanguage: AppLanguage
    ) -> (time: String, duration: Int, note: String) {
        switch place.category {
        case .cafe:
            return index <= 1
                ? ("9:00 AM", 60, outputLanguage.localized(english: "Good morning or coffee stop.", traditionalChinese: "適合早上開始或中途喝杯咖啡。"))
                : ("2:30 PM", 45, outputLanguage.localized(english: "Good reset stop between bigger plans.", traditionalChinese: "適合放在兩個主要行程之間休息。"))
        case .food:
            return foodCount == 0 && index < max(2, count - 1)
                ? ("12:30 PM", 90, outputLanguage.localized(english: "Meal slot based on saved food memory.", traditionalChinese: "依照你存過的美食記憶安排成午餐。"))
                : ("6:30 PM", 105, outputLanguage.localized(english: "Dinner slot based on saved food memory.", traditionalChinese: "依照你存過的美食記憶安排成晚餐。"))
        case .bar:
            return ("8:30 PM", 90, outputLanguage.localized(english: "Evening stop.", traditionalChinese: "適合放在晚上收尾。"))
        case .attraction:
            return index <= 1
                ? ("10:30 AM", 90, outputLanguage.localized(english: "Anchor activity.", traditionalChinese: "可以當作這天的主要行程。"))
                : ("3:30 PM", 90, outputLanguage.localized(english: "Afternoon activity.", traditionalChinese: "適合排在下午的活動。"))
        case .shopping:
            return ("3:00 PM", 75, outputLanguage.localized(english: "Flexible afternoon stop.", traditionalChinese: "適合排成彈性的下午停留點。"))
        case .stay:
            return index == 0
                ? ("9:30 AM", 30, outputLanguage.localized(english: "Start from this stay or base.", traditionalChinese: "可以從住宿或集合點開始。"))
                : ("4:00 PM", 30, outputLanguage.localized(english: "Check-in or reset stop.", traditionalChinese: "適合作為入住或休息點。"))
        }
    }

    private func note(for place: Place, previous: Place?, defaultNote: String, outputLanguage: AppLanguage) -> String {
        guard let previous else { return defaultNote }
        let kilometers = distance(from: previous, to: place) / 1_000
        if kilometers >= 80 {
            return defaultNote + " " + outputLanguage.localized(
                english: "Far from the previous stop; check driving or transit before committing.",
                traditionalChinese: "跟上一站距離較遠，出發前先確認開車或大眾運輸時間。"
            )
        }
        if kilometers >= 25 {
            return defaultNote + " " + outputLanguage.localized(
                english: "Build in extra travel time from the previous stop.",
                traditionalChinese: "跟上一站有一段距離，記得預留交通時間。"
            )
        }
        return defaultNote
    }

    private func distance(from lhs: Place, to rhs: Place) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func dayLabel(_ dayNumber: Int, outputLanguage: AppLanguage) -> String {
        outputLanguage.localized(
            english: "Day \(dayNumber)",
            traditionalChinese: "第 \(dayNumber) 天"
        )
    }

    private func title(for message: String, dayCount: Int, outputLanguage: AppLanguage) -> String {
        if dayCount == 1 {
            return outputLanguage.localized(
                english: "SAV-E Day Plan",
                traditionalChinese: "SAV-E 一日行程"
            )
        }
        return outputLanguage.localized(
            english: "SAV-E \(dayCount)-Day Plan",
            traditionalChinese: "SAV-E \(dayCount) 天行程"
        )
    }

    private func planningMessage(for message: String, selectedPlaces: [Place], outputLanguage: AppLanguage) -> String {
        var notes = [
            outputLanguage.localized(
                english: "I drafted this from your saved Map Stamps first.",
                traditionalChinese: "我先用你已確認的地圖章排出一版行程。"
            )
        ]
        if !hasExplicitDayCount(message) {
            notes.append(outputLanguage.localized(
                english: "Tell me how many days and your style if you want me to reshape it.",
                traditionalChinese: "如果要我重排，可以告訴我天數和想要的風格。"
            ))
        }
        let categories = Set(selectedPlaces.map(\.category))
        if categories.isSubset(of: [.food, .cafe, .bar]) {
            notes.append(outputLanguage.localized(
                english: "You mostly saved food/drink stops, so add public attractions nearby only after you choose the trip vibe.",
                traditionalChinese: "你目前多半存的是吃喝點；要不要我再依照行程風格補附近景點？"
            ))
        } else if !categories.contains(.attraction) {
            notes.append(outputLanguage.localized(
                english: "You do not have saved attractions in this draft yet; public discovery should stay separate until you pick what to add.",
                traditionalChinese: "這版還沒有已存景點；我會先把公開探索跟你的地圖章分開。"
            ))
        }
        return notes.joined(separator: " ")
    }

    private func hasExplicitDayCount(_ message: String) -> Bool {
        let normalized = message.lowercased()
        if normalized.contains("weekend") { return true }
        let patterns = [
            #"(\d+)\s*[- ]?\s*days?"#,
            #"(\d+)\s*[- ]?\s*day"#,
            #"(\d+)\s*[天日]"#
        ]
        if patterns.contains(where: { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)) != nil
        }) {
            return true
        }
        return [
            "一天", "一日", "兩天", "两天", "二天", "二日", "三天", "三日",
            "四天", "四日", "五天", "五日", "六天", "六日", "七天", "七日"
        ].contains { normalized.contains($0) }
    }
}
