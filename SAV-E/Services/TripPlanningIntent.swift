import Foundation

/// What the user asked for, separated from how it was phrased.
///
/// `DeterministicTripPlanner` used to parse the raw message itself at three
/// points — day count by regex, place filters by tokenizing, pace by keyword —
/// which made planning fail on wording rather than on substance. Four bugs in
/// one day came from that: "my stamps" searched for a place named *stamps*,
/// "one day" searched for one named *one*, a two-character CJK region was
/// dropped below a Latin length floor, and any phrasing without an explicit
/// day count was refused outright.
///
/// Splitting intent from phrasing lets a smarter extractor (an LLM that knows
/// "somewhere chill with my parents" means a relaxed pace) fill the same struct
/// the deterministic parser fills, without touching selection, routing, or
/// scheduling — the parts that must stay deterministic so a plan can only ever
/// contain places the user actually saved.
struct TripPlanningIntent: Equatable {
    /// Days requested, or `nil` to let the planner size the trip from what is
    /// available. Nil is not a failure: "plan a Taipei trip from my stamps" is
    /// a perfectly clear request.
    var days: Int?

    /// Terms a place must match to be treated as specifically requested,
    /// already stripped of product vocabulary and filler.
    ///
    /// Empty means "no specific ask" — plan from everything nearby. That is
    /// different from a term that matches nothing, which must still refuse
    /// rather than quietly plan somewhere else.
    var searchTerms: [String]

    /// The original request, still needed for pace and meal-window parsing.
    var rawMessage: String

    /// Whether the user named something specific that a place has to match.
    var hasSpecificRequest: Bool { !searchTerms.isEmpty }

    /// Days to actually plan, given how many places are available.
    ///
    /// Sized so a day is neither a single stop nor a forced march, and capped
    /// at a week the way an explicit request is.
    func resolvedDays(availablePlaceCount: Int, maxStopsPerDay: Int) -> Int {
        if let days { return max(1, min(days, Self.maximumDays)) }
        guard availablePlaceCount > 0 else { return 1 }
        let comfortable = max(2, min(maxStopsPerDay, Self.comfortableStopsPerDay))
        let inferred = Int(ceil(Double(availablePlaceCount) / Double(comfortable)))
        return max(1, min(inferred, Self.maximumInferredDays))
    }

    static let maximumDays = 7
    /// An inferred trip stays short: guessing a week from a big vault would be
    /// planning something the user never asked for.
    static let maximumInferredDays = 3
    static let comfortableStopsPerDay = 4
}

/// What a trip-intent extraction is given.
///
/// Privacy: the query plus area labels the user already saved places in —
/// the same city/area granularity `GroundedAnswerContext` uses. No notes,
/// no full addresses, no coordinates.
struct TripIntentParseRequest: Equatable {
    let query: String
    var savedAreaHints: [String] = []
}

/// Clamps a model-produced intent down to something the planner can trust.
///
/// The planner selects only from saved places, so a bad `searchTerms` value
/// cannot inject a place — but it can still make a plan refuse by matching
/// nothing, or bloat scoring with dozens of terms. Both are bounded here.
struct TripIntentJSONValidator {
    static let maxSearchTerms = 6
    static let maxTermLength = 24

    func parse(_ json: String, rawQuery: String) throws -> TripPlanningIntent {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SaveSearchIntentValidationError.malformedJSON
        }

        var days: Int?
        if let raw = object["days"] as? Int {
            days = max(1, min(raw, TripPlanningIntent.maximumDays))
        } else if let raw = object["days"] as? Double {
            days = max(1, min(Int(raw), TripPlanningIntent.maximumDays))
        }

        let rawTerms = (object["searchTerms"] as? [Any])?.compactMap { $0 as? String } ?? []
        let terms = rawTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count <= Self.maxTermLength }
            .reduce(into: [String]()) { result, term in
                guard !result.contains(term) else { return }
                result.append(term)
            }
            .prefix(Self.maxSearchTerms)

        return TripPlanningIntent(days: days, searchTerms: Array(terms), rawMessage: rawQuery)
    }
}

/// Conversation answers are explicit slots. Unrecognized destination changes
/// clear the selected area; missing/invalid answers never acquire defaults.
struct SavePlanConversationConditions {
    // Sentence endings and known trip conditions can follow LA; another place
    // word (La Jolla), hyphen, or an internal period (La.Jolla) cannot.
    private static let losAngelesShorthand = #"la(?=$|[。！？；，：]|[.!?,;:](?=\s|$)|\s+(?:trip|travel|for|relaxed|easy|slow|balanced|packed|busy|start|end|arrival|departure)\b|\s*[0-9一二兩两三四五六七八九十]+\s*(?:天|日|days?\b)|\s+(?:(?:a|one|two|three|four|five|six|seven|eight|nine|ten)\s+days?|day\s+trip)\b|\s*(?:行程|旅行|旅遊|輕鬆|適中|緊湊))"#
    private(set) var area: String?
    private(set) var days: Int?
    private(set) var pace: ItineraryPace?
    private(set) var arrivalMinutes: Int?
    private(set) var departureMinutes: Int?
    private(set) var requests: [String] = []
    private(set) var unmatchedDestination: String?
    private(set) var unsupportedDays: Int?
    private(set) var needsFollowUpClarification = false
    private(set) var ambiguousDestinationPrefix: String?
    private(set) var arrivalAnswered = false
    private(set) var departureAnswered = false

    mutating func receive(_ message: String, areas: [String]) {
        let hadArea = area != nil
        needsFollowUpClarification = false
        let wasAskingPace = area != nil && days != nil && pace == nil
        let wasAskingDays = unsupportedDays != nil || (area != nil && days == nil)
        requests.append(message)
        if requests.count > 12 { requests.removeFirst() }
        let text = Self.normalized(message)
        let noWindow = text.range(of: #"^(?:none|no|no(?: time)? (?:constraints?|restrictions?|limits?)|no preference|any time|不用(?:時間)?(?:限制)?|沒有(?:時間)?(?:限制)?|没有(?:时间)?(?:限制)?|無(?:時間)?(?:限制)?|都可以)(?:[。.!！ ]*)$"#, options: .regularExpression) != nil || text.range(of: #"沒有時間限制|没有时间限制|不限時間|no time (?:constraints?|limits?|restrictions?)"#, options: .regularExpression) != nil
        let proposedChange = Self.capture(text, pattern: #"(?:改去|改到|改成|換去|換成|换成|前往|想去|switch to|change to|instead go to)\s*(.+)$"#)
        let conditionPrefix = #"^(?:[0-9]|[一二兩两三四五六七八九十]+天|開始|結束|抵達|離開|天數|步調|輕鬆|適中|普通|緊湊|多排|排滿|start|end|arriv|depart|relaxed|easy|slow|balanced|packed|busy)"#
        let proposedDestination = proposedChange.flatMap { $0.range(of: conditionPrefix, options: .regularExpression) == nil ? $0 : nil }
        // English destinations can follow the duration, not just lead it.
        let followsTrip = Self.dayCount(text, allowBareNumber: false) != nil
            || text.range(of: #"\b(?:plan|trip|travel)\b"#, options: .regularExpression) != nil
        let trailingDestination = followsTrip ? Self.capture(text, pattern: #"\b(?:in|to)\s+([\p{L}][\p{L} .'-]{0,39}?)(?=\s+(?:for|with|relaxed|easy|slow|balanced|packed|busy|[0-9])\b|[,;.!?]|$)"#) : nil
        let destinationChange = proposedDestination ?? trailingDestination.flatMap {
            $0.range(of: conditionPrefix, options: .regularExpression) == nil && !["a", "an", "the"].contains($0) ? $0 : nil
        }
        let retainedDestination = Self.capture(text, pattern: #"^(?:keep\s+|保留\s*|保持\s*)(.+)$"#)
        let planningDestination = Self.capture(text, pattern: #"^(?:(?:請|请|幫我|帮我|please\b|help me\b)\s*)*(?:規劃|规划|plan\b)\s*(.+)$"#)
        let destinationText = destinationChange ?? retainedDestination ?? planningDestination ?? text
        // A trip descriptor alone does not identify a destination. Require the
        // duration boundary, including "Kyoto for 2 days" and "京都旅行6天".
        let destinationWithDuration = Self.capture(text, pattern: #"^([\p{L} .'-]{1,40}?)(?:(?:旅行|旅遊|行程|\btrip\b|\btravel\b)\s*)?(?:\bfor\s+)?[0-9一二兩两三四五六七八九十]{1,3}\s*(?:天|日|days?\b)"#)
        let matchingAreas = areas.filter { area in
            let aliases = Self.areaAliases(area)
            let conversationAliases = aliases.contains("los angeles") ? aliases + ["la"] : aliases
            return conversationAliases.contains { alias in
                // LA is a destination shorthand, not the first word of La Jolla.
                if alias == "la" {
                    let negated = #"(?:不要|不去|不是|\bnot)\s*"# + Self.losAngelesShorthand
                    guard destinationText.range(of: negated, options: .regularExpression) == nil else { return false }
                    return destinationText.range(of: "^" + Self.losAngelesShorthand, options: .regularExpression) != nil
                }
                let negated = #"(?:不要|不去|不是|not)\s*"# + NSRegularExpression.escapedPattern(for: alias)
                guard destinationText.range(of: negated, options: .regularExpression) == nil else { return false }
                if alias.range(of: #"^[a-z ]+$"#, options: .regularExpression) != nil {
                    return destinationText.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: alias) + #"\b"#, options: .regularExpression) != nil
                }
                return destinationText.contains(alias)
            }
        }
        let distinct = Dictionary(grouping: matchingAreas, by: Self.areaKey)
        if distinct.count == 1, let matched = matchingAreas.first {
            area = matched
            unmatchedDestination = nil
            ambiguousDestinationPrefix = nil
        } else if distinct.count > 1 || destinationChange != nil {
            area = nil
            unmatchedDestination = distinct.isEmpty ? destinationText : nil
        } else if area == nil && Self.isBareDestination(destinationText) && !Self.paceAnswer(text).mentioned && !noWindow {
            area = nil
            unmatchedDestination = destinationText
        } else if text.range(of: #"(?:不要|不去|不是|not)"#, options: .regularExpression) != nil,
                  areas.contains(where: { label in
                      let aliases = Self.areaAliases(label)
                      let rejected = aliases.contains(where: text.contains)
                          || (aliases.contains("los angeles") && text.range(
                              of: #"(?:不要|不去|不是|\bnot)\s*"# + Self.losAngelesShorthand,
                              options: .regularExpression) != nil)
                      guard rejected else { return false }
                      // Keep Taipei when the user rejects still-offered LA.
                      // A leftover Taipei must not survive 不要東京 when Tokyo
                      // is the only saved area this turn.
                      guard let area else { return true }
                      let currentStillOffered = areas.contains { Self.areaKey($0) == Self.areaKey(area) }
                      return !currentStillOffered || Self.areaKey(label) == Self.areaKey(area)
                  }) {
            area = nil
            unmatchedDestination = nil
        }

        if area == nil { ambiguousDestinationPrefix = nil }

        // An unknown prefix can be a city or a preference ("Kyoto for 2 days",
        // "beach trip 2 days"). Keep confirmed context until the user clarifies.
        if area != nil, distinct.isEmpty, destinationChange == nil,
           let prefix = destinationWithDuration,
           !["改成", "改為", "改为", "安排", "規劃", "plan", "plan a", "for", "我想要", "第一", "最後", "最后", "第"].contains(prefix) {
            ambiguousDestinationPrefix = prefix
        }

        if let count = Self.dayCount(text, allowBareNumber: wasAskingDays) {
            unsupportedDays = (1...TripPlanningIntent.maximumDays).contains(count) ? nil : count
            days = unsupportedDays == nil ? count : nil
        } else if text.range(of: #"\d+\.\d+\s*(?:天|日|days?\b)"#, options: .regularExpression) != nil {
            days = nil
            unsupportedDays = nil
        }
        let noPacePreference = wasAskingPace && text.range(
            of: #"^(?:都可以|都行|隨意|随意|沒差|没差|any|either|no preference)(?:[。.!！ ]*)$"#,
            options: .regularExpression
        ) != nil
        let parsedPace: (mentioned: Bool, value: ItineraryPace?) = noPacePreference
            ? (true, .balanced) : Self.paceAnswer(text)
        if parsedPace.mentioned { pace = parsedPace.value }

        let awaitingArrivalOnly = !arrivalAnswered && departureAnswered
        let awaitingDepartureOnly = arrivalAnswered && (!departureAnswered || (days == 1 && (departureMinutes ?? 1440) <= (arrivalMinutes ?? -1)))
        let arrival = Self.clockAnswer(text, roles: #"(?:arriv(?:e|al)|start(?:ing)?(?: at)?|抵達|到達|開始|第一天)"#)
        let departure = Self.clockAnswer(text, roles: #"(?:depart(?:ure)?|leave|end by|finish by|離開|返程|結束|最後一天|最后一天)"#)
        if arrival.mentioned { arrivalMinutes = arrival.minutes; arrivalAnswered = arrival.minutes != nil }
        if departure.mentioned { departureMinutes = departure.minutes; departureAnswered = departure.minutes != nil }
        if text.range(of: #"^\d{1,2}:\d{2}(?:\s*(?:am|pm))?$"#, options: .regularExpression) != nil {
            let clock = Self.clockAnswer("time " + text, roles: "time")
            if awaitingArrivalOnly { arrivalMinutes = clock.minutes; arrivalAnswered = clock.minutes != nil }
            if awaitingDepartureOnly { departureMinutes = clock.minutes; departureAnswered = clock.minutes != nil }
        }

        if noWindow, !noPacePreference, area != nil, days != nil, pace != nil {
            // A reply to the remaining clock question keeps the clock already
            // supplied. An explicit reset after both answers clears both.
            if arrivalAnswered && departureAnswered {
                arrivalMinutes = nil; departureMinutes = nil
            }
            arrivalAnswered = true
            departureAnswered = true
        }
        // An established conversation may contain preferences or edit requests,
        // not another city answer. Never silently redraft an unhandled request.
        needsFollowUpClarification = hadArea && area != nil && distinct.isEmpty
            && destinationChange == nil && (ambiguousDestinationPrefix != nil || (Self.dayCount(text, allowBareNumber: wasAskingDays) == nil
            && !parsedPace.mentioned && !arrival.mentioned && !departure.mentioned && !noWindow
            && text.range(of: #"^\d{1,2}:\d{2}(?:\s*(?:am|pm))?$"#, options: .regularExpression) == nil))
    }

    func clarification(language: AppLanguage) -> String? {
        if let unsupportedDays {
            return language.localized(english: "You asked for \(unsupportedDays) days. This draft supports 1–7 days. How many days should this draft cover?", traditionalChinese: "你說的是 \(unsupportedDays) 天；目前一份草稿支援 1–7 天。這份草稿想先安排幾天？")
        }
        if let prefix = ambiguousDestinationPrefix {
            return language.localized(
                english: "Does ‘\(prefix)’ name a different destination or describe a trip preference? I’ve kept your city and draft. Say ‘switch to …’ or ‘keep \(area ?? "this city")’. Other preferences are not applied automatically yet.",
                traditionalChinese: "「\(prefix)」是新的目的地，還是旅行偏好？原本城市和草稿都保留著。請說「改去⋯」或「保留 \(area ?? "原本城市")」。其他偏好目前不會自動套用。"
            )
        }
        if needsFollowUpClarification {
            return language.localized(
                english: "I’ve kept your conditions and draft. I can change the city, days, pace or clock limits, or remove a confirmed stop by its exact name. Which would you like? For a new city, say ‘switch to …’. Other preferences are not applied automatically yet.",
                traditionalChinese: "條件和草稿都保留著。目前可以改城市、天數、步調或時間，或用完整名稱移除已確認的站點。想改哪一項？換城市可說「改去⋯」。其他偏好目前不會自動套用。"
            )
        }
        if area == nil {
            if let unmatchedDestination {
                return language.localized(
                    english: "I can’t match \(unmatchedDestination) to an area with saved places yet. Save places there, or tell me another city or area. I’ve kept your other answers and draft.",
                    traditionalChinese: "目前還找不到「\(unmatchedDestination)」對應的已存地點。可以先存那裡的地點，或告訴我另一個城市／區域；其他條件和草稿都還留著。"
                )
            }
            return language.localized(
                english: days.map { "Got it, \($0) days. Which city or area would you like to plan from your saved places?" }
                    ?? "Which city or area would you like to plan from your saved places?",
                traditionalChinese: days.map { "記下 \($0) 天了。這次想安排哪個城市或區域？我會使用你在那裡已存的地點。" }
                    ?? "這次想安排哪個城市或區域？我會使用你在那裡已存的地點。"
            )
        }
        if days == nil {
            return language.localized(english: "How many days do you have?", traditionalChinese: "這次有幾天可以玩？")
        }
        if pace == nil {
            return language.localized(english: "What pace would you like: relaxed, balanced, or packed?", traditionalChinese: "想輕鬆逛、步調適中，還是緊湊多排一些地點？")
        }
        if !arrivalAnswered || !departureAnswered {
            if arrivalAnswered {
                return language.localized(english: "What time must the last day end? Use HH:mm, or say none if there’s no limit.", traditionalChinese: "最後一天需要幾點結束？請用 HH:mm；沒有限制可以說「不用」。")
            }
            if departureAnswered {
                return language.localized(english: "What time can the first day start? Use HH:mm, or say none if there’s no limit.", traditionalChinese: "第一天幾點可以開始？請用 HH:mm；沒有限制可以說「不用」。")
            }
            return language.localized(english: "Any first-day start or last-day end limits? For example, start 14:00, end by 19:00; or say none.", traditionalChinese: "第一天幾點可開始、最後一天幾點前要結束？例如「開始 14:00，結束 19:00」；沒有限制可以說「不用」。")
        }
        if days == 1, let arrivalMinutes, let departureMinutes, departureMinutes <= arrivalMinutes {
            return language.localized(english: "For one day, the end must be later than the start. What time should it end?", traditionalChinese: "一天的行程需要在開始之後才結束。想改成幾點結束？")
        }
        return nil
    }

    func request(language: AppLanguage) -> SavePlanRequest? {
        guard ambiguousDestinationPrefix == nil, !needsFollowUpClarification, let area, let days, let pace, arrivalAnswered, departureAnswered else { return nil }
        if days == 1, let arrivalMinutes, let departureMinutes, departureMinutes <= arrivalMinutes { return nil }
        return SavePlanRequest(area: area, days: days, pace: pace, arrivalMinutes: arrivalMinutes, departureMinutes: departureMinutes, language: language, usesFlightBuffers: false)
    }

    /// Local recovery only. The live Plan path sends every turn to the model first.
    /// Defaults are provisional and must be disclosed, never described as user answers.
    func provisionalRequest(language: AppLanguage) -> SavePlanRequest? {
        guard area != nil, ambiguousDestinationPrefix == nil, unmatchedDestination == nil,
              unsupportedDays == nil, !needsFollowUpClarification else { return nil }
        var value = self
        value.days = days ?? 1
        value.pace = pace ?? .balanced
        // Invalid explicit clocks cannot turn into unlimited time through a default.
        let last = requests.last?.lowercased() ?? ""
        if !arrivalAnswered && last.range(of: #"start|arriv|開始|抵達|到達"#, options: .regularExpression) != nil { return nil }
        if !departureAnswered && last.range(of: #"end by|depart|結束|離開"#, options: .regularExpression) != nil { return nil }
        value.arrivalAnswered = true
        value.departureAnswered = true
        return value.request(language: language)
    }

    mutating func acceptAgentRequest(_ request: SavePlanRequest) {
        area = request.area
        days = request.days
        pace = request.pace
        arrivalMinutes = request.arrivalMinutes
        departureMinutes = request.departureMinutes
        arrivalAnswered = true
        departureAnswered = true
        unmatchedDestination = nil
        unsupportedDays = nil
        needsFollowUpClarification = false
        ambiguousDestinationPrefix = nil
    }

    static func areaAliases(_ area: String) -> [String] {
        let label = normalized(area)
        let short = label.hasSuffix("市") ? String(label.dropLast()) : label
        if ["taipei", "taipei city", "台北", "台北市"].contains(label) { return ["taipei", "台北"] }
        if ["tokyo", "tokyo city", "東京", "東京都"].contains(label) { return ["tokyo", "東京"] }
        // Keep the short LA token out of free-text candidate/address matching.
        if ["los angeles", "la", "洛杉磯", "洛杉矶"].contains(short) { return ["los angeles", "洛杉磯", "洛杉矶"] }
        return (label == short ? [label] : [label, short]).filter { !$0.isEmpty }
    }

    private static func areaKey(_ area: String) -> String {
        areaAliases(area).first ?? normalized(area)
    }

    private static func isBareDestination(_ text: String) -> Bool {
        guard text.count <= 40, !text.isEmpty,
              text.range(of: #"[0-9]|旅行|行程|天|夜|小時|輕鬆|緊湊|不用|plan|trip|days?|relaxed|packed|none"#, options: .regularExpression) == nil else { return false }
        return text.range(of: #"^[\p{L}][\p{L} .'-]*$"#, options: .regularExpression) != nil
    }

    private static func dayCount(_ text: String, allowBareNumber: Bool) -> Int? {
        if allowBareNumber, text.range(of: #"^\d+$"#, options: .regularExpression) != nil { return Int(text) }
        if let value = capture(text, pattern: #"(?<![0-9.])(?<!第)(?<!最後)(?<!最后)(-?\d+)\s*(?:天|日|days?\b)"#) { return Int(value) }
        if let number = capture(text, pattern: #"(?<!第)(?<!最後)(?<!最后)([一二兩两三四五六七八九十]{1,3})(?:天|日)"#) {
            let digits: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
            if let ten = number.firstIndex(of: "十") {
                let tens = number[..<ten].first.flatMap { digits[$0] } ?? 1
                let ones = number[number.index(after: ten)...].first.flatMap { digits[$0] } ?? 0
                return tens * 10 + ones
            }
            return number.count == 1 ? number.first.flatMap { digits[$0] } : nil
        }
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        for (index, word) in words.enumerated() {
            if text.range(of: #"\b"# + word + #" days?\b"#, options: .regularExpression) != nil { return index + 1 }
        }
        if text.range(of: #"\b(?:a day|day trip)\b"#, options: .regularExpression) != nil { return 1 }
        return nil
    }

    private static func paceAnswer(_ text: String) -> (mentioned: Bool, value: ItineraryPace?) {
        let groups: [(ItineraryPace, String)] = [
            (.relaxed, #"輕鬆|轻松|放鬆|慢慢|不要太趕|\b(?:relaxed|easy|slow|slower|not too packed)\b"#),
            (.balanced, #"適中|适中|普通|\bbalanced\b"#),
            (.packed, #"緊湊|紧凑|多排|排滿|排满|多一點|多一点|多一些|\b(?:packed|busy|more stops|more places)\b"#)
        ]
        let sanitized = text.replacingOccurrences(of: "not too packed", with: "relaxed")
            .replacingOccurrences(of: #"(?:不要|不想|別|not)\s*(?:太)?(?:輕鬆|放鬆|緊湊|排滿|多一點|多一点|多一些|more stops|more places|relaxed|packed)"#, with: "", options: .regularExpression)
        let values = groups.filter { sanitized.range(of: $0.1, options: .regularExpression) != nil }.map(\.0)
        let mentioned = groups.contains { text.range(of: $0.1, options: .regularExpression) != nil }
        return (mentioned, values.count == 1 ? values.first : nil)
    }

    private static func clockAnswer(_ text: String, roles: String) -> (mentioned: Bool, minutes: Int?) {
        let mentioned = text.range(of: roles, options: .regularExpression) != nil
        guard mentioned else { return (false, nil) }
        let clock = #"(\d{1,2}):(\d{2})(?:\s*(am|pm))?"#
        for pattern in [roles + #"[^0-9\n,，]{0,12}"# + clock, clock + #"\s*"# + roles] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let h = Range(match.range(at: 1), in: text), let m = Range(match.range(at: 2), in: text),
                  var hour = Int(text[h]), let minute = Int(text[m]), (0...23).contains(hour), (0...59).contains(minute) else { continue }
            if let meridiem = Range(match.range(at: 3), in: text) {
                guard (1...12).contains(hour) else { continue }
                hour = hour % 12 + (text[meridiem] == "pm" ? 12 : 0)
            }
            return (true, hour * 60 + minute)
        }
        return (true, nil)
    }

    private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "臺", with: "台").lowercased()
    }
}
