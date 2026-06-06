import CoreLocation
import Foundation

enum ItineraryPace: String, Hashable {
    case relaxed
    case balanced
    case packed

    var maxStopsPerDay: Int {
        switch self {
        case .relaxed: return 3
        case .balanced: return 5
        case .packed: return 6
        }
    }
}

struct ItineraryConstraints: Hashable {
    var pace: ItineraryPace
    var transportMode: SaveAIResponse.TransportMode?
    var requestedStartTime: String?
    var requestedEndTime: String?

    static let balanced = ItineraryConstraints(
        pace: .balanced,
        transportMode: nil,
        requestedStartTime: nil,
        requestedEndTime: nil
    )
}

struct ItineraryPlannedStop: Hashable {
    let place: Place
    let time: String
    let duration: Int
    let note: String
}

struct ItineraryConstraintPlanner {
    func constraints(from message: String) -> ItineraryConstraints {
        let normalized = message.lowercased()
        var constraints = ItineraryConstraints.balanced

        if containsAny(normalized, ["relaxed", "easy pace", "slow", "slower", "not too packed", "不要太趕", "轻松", "輕鬆", "放鬆"]) {
            constraints.pace = .relaxed
        } else if containsAny(normalized, ["packed", "busy", "fit in", "as much as possible", "多排", "排滿", "排满"]) {
            constraints.pace = .packed
        }

        if containsAny(normalized, ["walk", "walking", "on foot", "步行", "走路"]) {
            constraints.transportMode = .walking
        } else if containsAny(normalized, ["transit", "subway", "metro", "train", "bus", "public transport", "大眾運輸", "大众运输", "捷運", "地鐵", "地铁", "公車", "公交"]) {
            constraints.transportMode = .transit
        } else if containsAny(normalized, ["drive", "driving", "car", "開車", "开车"]) {
            constraints.transportMode = .driving
        }

        constraints.requestedStartTime = firstTime(in: normalized, afterAnyOf: ["start at", "start around", "starting at", "starting around", "begin at", "begin around", "after", "from", "開始", "开始", "出發", "出发"])
        constraints.requestedEndTime = firstTime(in: normalized, afterAnyOf: ["end by", "finish by", "back by", "until", "結束", "结束", "回到"])
        return constraints
    }

    func schedule(
        _ places: [Place],
        constraints: ItineraryConstraints,
        outputLanguage: AppLanguage
    ) -> [ItineraryPlannedStop] {
        var foodCount = 0
        return places.enumerated().map { index, place in
            let previous = index > 0 ? places[index - 1] : nil
            var slot = timeSlot(for: place, index: index, count: places.count, foodCount: foodCount, outputLanguage: outputLanguage)
            if index == 0, let requestedStartTime = constraints.requestedStartTime {
                slot.time = requestedStartTime
                slot.note = slot.note + " " + outputLanguage.localized(
                    english: "Start time adjusted to your requested window.",
                    traditionalChinese: "已依照你指定的開始時間調整。"
                )
            }
            if place.category == .food { foodCount += 1 }
            return ItineraryPlannedStop(
                place: place,
                time: slot.time,
                duration: slot.duration,
                note: note(for: place, previous: previous, defaultNote: slot.note, constraints: constraints, outputLanguage: outputLanguage)
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

    private func note(
        for place: Place,
        previous: Place?,
        defaultNote: String,
        constraints: ItineraryConstraints,
        outputLanguage: AppLanguage
    ) -> String {
        var note = defaultNote
        if let transportMode = constraints.transportMode, previous != nil {
            switch transportMode {
            case .walking:
                note += " " + outputLanguage.localized(english: "Planned with walking in mind; verify sidewalks and exact route.", traditionalChinese: "已優先考慮步行；出發前請確認實際路線。")
            case .transit:
                note += " " + outputLanguage.localized(english: "Planned with public transit in mind; check live schedules before leaving.", traditionalChinese: "已優先考慮大眾運輸；出發前請確認即時班次。")
            case .driving:
                note += " " + outputLanguage.localized(english: "Planned with driving in mind; check parking and traffic before committing.", traditionalChinese: "已優先考慮開車；出發前請確認停車與路況。")
            }
        }
        guard let previous else { return note }
        let kilometers = distance(from: previous, to: place) / 1_000
        if kilometers >= 80 {
            return note + " " + outputLanguage.localized(english: "Far from the previous stop; check driving or transit before committing.", traditionalChinese: "跟上一站距離較遠，出發前先確認開車或大眾運輸時間。")
        }
        if kilometers >= 25 {
            return note + " " + outputLanguage.localized(english: "Build in extra travel time from the previous stop.", traditionalChinese: "跟上一站有一段距離，記得預留交通時間。")
        }
        return note
    }

    private func distance(from lhs: Place, to rhs: Place) -> Double {
        let dLat = lhs.latitude - rhs.latitude
        let dLon = lhs.longitude - rhs.longitude
        return sqrt(dLat * dLat + dLon * dLon) * 111_000
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func firstTime(in text: String, afterAnyOf prefixes: [String]) -> String? {
        for prefix in prefixes where text.contains(prefix) {
            guard let prefixRange = text.range(of: prefix) else { continue }
            let suffix = String(text[prefixRange.upperBound...])
            if let time = parseFirstTime(in: suffix) { return time }
        }
        return nil
    }

    private func parseFirstTime(in text: String) -> String? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let hourValue = Int(text[hourRange]) else {
            return nil
        }
        let minuteValue: String
        if match.range(at: 2).location != NSNotFound,
           let minuteRange = Range(match.range(at: 2), in: text) {
            minuteValue = String(text[minuteRange])
        } else {
            minuteValue = "00"
        }
        let meridiem: String
        if match.range(at: 3).location != NSNotFound,
           let meridiemRange = Range(match.range(at: 3), in: text) {
            meridiem = String(text[meridiemRange]).uppercased()
        } else {
            meridiem = hourValue >= 8 && hourValue <= 11 ? "AM" : "PM"
        }
        let displayHour = hourValue > 12 ? hourValue - 12 : hourValue
        return "\(displayHour):\(minuteValue) \(meridiem)"
    }
}

struct DeterministicTripPlanner {
    private struct Candidate {
        let place: Place
        let score: Int
    }


    func plan(for message: String, places: [Place], outputLanguage: AppLanguage = .english) -> SaveAIResponse? {
        guard isItineraryRequest(message), !places.isEmpty else { return nil }

        let constraintPlanner = ItineraryConstraintPlanner()
        let constraints = constraintPlanner.constraints(from: message)
        let days = requestedDayCount(from: message, placeCount: places.count)
        let selectedPlaces = selectedPlaces(
            for: message,
            places: places,
            days: days,
            maxStopsPerDay: constraints.pace.maxStopsPerDay
        )
        guard !selectedPlaces.isEmpty else { return nil }

        let orderedPlaces = nearestNeighborOrder(selectedPlaces)
        let groupedPlaces = groups(orderedPlaces, requestedDays: days)
        let itineraryDays = groupedPlaces.enumerated().map { index, places in
            let scheduled = constraintPlanner.schedule(
                places,
                constraints: constraints,
                outputLanguage: outputLanguage
            )
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
            transportMode: constraints.transportMode ?? (selectedPlaces.count > 3 ? .driving : .walking),
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

        let englishDayCounts: [(String, Int)] = [
            ("one day", 1), ("single day", 1), ("two days", 2), ("three days", 3),
            ("four days", 4), ("five days", 5), ("six days", 6), ("seven days", 7)
        ]
        if let count = englishDayCounts.first(where: { normalized.contains($0.0) })?.1 {
            return count
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

    private func selectedPlaces(
        for message: String,
        places: [Place],
        days: Int,
        maxStopsPerDay: Int = 5
    ) -> [Place] {
        let candidates = places.map { Candidate(place: $0, score: relevanceScore(for: $0, message: message)) }
        let positive = candidates.filter { $0.score > 0 }
        if positive.isEmpty, hasSpecificPlanningConstraint(message) {
            return []
        }
        let source = positive.isEmpty ? candidates : positive
        let maxStops = max(3, days * maxStopsPerDay)

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
