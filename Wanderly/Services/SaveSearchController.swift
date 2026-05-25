import Foundation

struct SaveSearchController {
    func search(
        query rawQuery: String,
        places: [Place],
        localRecords: [SaveMemoryRecord]
    ) -> SaveSearchResponse {
        let query = SaveSearchQuery(rawValue: rawQuery)
        let placeResults = places.map(makePlaceResult)
        let recordResults = localRecords.map(makeRecordResult)
        let localResults = (placeResults + recordResults)
            .filter { query.matches($0) }
            .sorted { lhs, rhs in
                let lhsScore = query.score(lhs)
                let rhsScore = query.score(rhs)
                if lhsScore == rhsScore { return lhs.createdAt > rhs.createdAt }
                return lhsScore > rhsScore
            }

        let recommendationResults = query.wantsNewRecommendations
            ? [makeRecommendationShell(for: query)]
            : []

        return SaveSearchResponse(
            query: rawQuery,
            fromYourSave: SaveSearchSection(
                id: "from-your-save",
                title: "From your SAV-E",
                subtitle: "Saved places, review clues, sources, and tried memories.",
                results: localResults,
                emptyMessage: "No matching memory yet. Try a city, category, source, or place name."
            ),
            newRecommendations: SaveSearchSection(
                id: "new-recommendations",
                title: "New recommendations",
                subtitle: "Unsaved suggestions stay separate until you choose one.",
                results: recommendationResults,
                emptyMessage: "Type “recommend new cafe in LA” to search outside your SAV-E."
            )
        )
    }

    private func makePlaceResult(_ place: Place) -> SaveSearchResult {
        let isVisited = place.status == .visited
        return SaveSearchResult(
            id: "place-\(place.id.uuidString)",
            objectType: isVisited ? .triedMemory : .savedPlace,
            userState: isVisited ? .visited : .wantToGo,
            title: place.name,
            subtitle: place.address,
            statusLabel: isVisited ? "Tried memory" : place.status.memoryCardLabel,
            sourceURL: place.sourceUrl,
            sourcePlatform: place.sourcePlatform,
            category: place.category,
            cityOrArea: cityOrArea(from: place.address),
            confidence: nil,
            missingInfo: [],
            evidence: placeEvidence(place),
            createdAt: place.createdAt,
            canRunRecovery: false,
            isRecommendationShell: false
        )
    }

    private func makeRecordResult(_ record: SaveMemoryRecord) -> SaveSearchResult {
        let objectType: SaveSearchObjectType
        let userState: SaveSearchUserState
        let statusLabel: String

        switch record.state {
        case .sourceOnly:
            objectType = .sourceOnlyClue
            userState = .sourceOnly
            statusLabel = "Needs one more clue"
        case .reviewCandidate:
            objectType = .pendingCandidate
            userState = .waitingReview
            statusLabel = "Needs review"
        case .confirmedPlace:
            objectType = .savedPlace
            userState = .wantToGo
            statusLabel = "Memory card"
        }

        return SaveSearchResult(
            id: "record-\(record.id.uuidString)",
            objectType: objectType,
            userState: userState,
            title: record.displayTitle,
            subtitle: record.address ?? sourceSubtitle(from: record.sourceURL),
            statusLabel: statusLabel,
            sourceURL: record.sourceURL,
            sourcePlatform: sourcePlatform(from: record.sourceURL),
            category: nil,
            cityOrArea: record.address.flatMap(cityOrArea),
            confidence: nil,
            missingInfo: record.evidenceDiagnostic?.missingFields ?? [],
            evidence: record.evidence,
            createdAt: record.createdAt,
            canRunRecovery: record.state == .sourceOnly,
            isRecommendationShell: false
        )
    }

    private func makeRecommendationShell(for query: SaveSearchQuery) -> SaveSearchResult {
        SaveSearchResult(
            id: "new-recommendation-shell-\(query.stableIDFragment)",
            objectType: .newRecommendation,
            userState: .unsaved,
            title: "Search new places for “\(query.rawValue)”",
            subtitle: "SAV-E will keep recommendations separate from your memory cards.",
            statusLabel: "New recommendation · unsaved",
            sourceURL: nil,
            sourcePlatform: nil,
            category: query.categories.first,
            cityOrArea: nil,
            confidence: nil,
            missingInfo: ["Choose a result before it becomes a review clue or memory card"],
            evidence: ["Recommendation shell only; no map pin or saved place was created"],
            createdAt: Date(),
            canRunRecovery: false,
            isRecommendationShell: true
        )
    }

    private func placeEvidence(_ place: Place) -> [String] {
        var evidence: [String] = []
        if let sourceUrl = place.sourceUrl {
            evidence.append("Source: \(sourceUrl)")
        }
        if let note = place.note, !note.isEmpty {
            evidence.append("Note: \(note)")
        }
        if let rating = place.rating {
            evidence.append("Your rating: \(rating)")
        }
        return evidence
    }

    private func sourceSubtitle(from sourceURL: String?) -> String {
        guard let sourceURL, let url = URL(string: sourceURL), let host = url.host else {
            return "Saved source"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func sourcePlatform(from sourceURL: String?) -> SourcePlatform? {
        guard let host = sourceURL.flatMap(URL.init(string:))?.host?.lowercased() else { return nil }
        if host.contains("instagram") { return .instagram }
        if host.contains("threads") { return .threads }
        if host.contains("xiaohongshu") || host.contains("xhslink") { return .xiaohongshu }
        if host.contains("google") || host.contains("maps") { return .googleMaps }
        return .other
    }

    private func cityOrArea(from address: String) -> String? {
        let pieces = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard pieces.count >= 2 else { return pieces.first }
        return pieces[pieces.count - 2]
    }
}

private struct SaveSearchQuery {
    let rawValue: String
    let normalizedRaw: String
    let terms: [String]
    let categories: Set<PlaceCategory>
    let platforms: Set<SourcePlatform>
    let states: Set<SaveSearchUserState>
    let wantsNewRecommendations: Bool
    let stableIDFragment: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedRaw = Self.normalize(rawValue)
        categories = Self.parseCategories(from: normalizedRaw)
        platforms = Self.parsePlatforms(from: normalizedRaw)
        states = Self.parseStates(from: normalizedRaw)
        wantsNewRecommendations = Self.containsAny(
            normalizedRaw,
            keywords: ["recommend", "recommendation", "new", "discover", "nearby", "suggest", "推薦", "新的", "附近", "找新"]
        )
        stableIDFragment = Self.makeStableIDFragment(from: normalizedRaw)
        terms = Self.parseTerms(from: normalizedRaw)
    }

    func matches(_ result: SaveSearchResult) -> Bool {
        if !categories.isEmpty, let category = result.category, !categories.contains(category) {
            return false
        }
        if !categories.isEmpty, result.category == nil {
            return false
        }
        if !platforms.isEmpty, let sourcePlatform = result.sourcePlatform, !platforms.contains(sourcePlatform) {
            return false
        }
        if !platforms.isEmpty, result.sourcePlatform == nil {
            return false
        }
        if !states.isEmpty, !states.contains(result.userState) {
            return false
        }
        guard !terms.isEmpty else {
            return !categories.isEmpty || !platforms.isEmpty || !states.isEmpty || normalizedRaw.isEmpty
        }
        let haystack = Self.normalize(result.searchText)
        return terms.allSatisfy { Self.term($0, matches: haystack) }
    }

    func score(_ result: SaveSearchResult) -> Int {
        let haystack = Self.normalize(result.searchText)
        var value = 0
        for term in terms where Self.term(term, matches: haystack) {
            value += result.title.lowercased().contains(term) ? 12 : 5
        }
        if let category = result.category, categories.contains(category) { value += 8 }
        if let sourcePlatform = result.sourcePlatform, platforms.contains(sourcePlatform) { value += 6 }
        if states.contains(result.userState) { value += 6 }
        switch result.objectType {
        case .savedPlace, .triedMemory: value += 4
        case .pendingCandidate: value += 3
        case .sourceOnlyClue: value += 2
        case .review, .tripStop, .newRecommendation: value += 1
        }
        return value
    }

    private static func parseTerms(from value: String) -> [String] {
        let stopwords: Set<String> = [
            "my", "your", "save", "saved", "place", "places", "memory", "memories",
            "card", "cards", "review", "source", "only", "want", "to", "go", "visited",
            "tried", "recommend", "recommendation", "new", "discover", "nearby", "suggest",
            "找", "我的", "儲存", "地點", "記憶", "推薦", "附近", "新的", "待確認"
        ]
        return value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) }
            .filter { token in
                PlaceCategory.allCases.allSatisfy { $0.rawValue != token && $0.displayName.lowercased() != token } &&
                    SourcePlatform.allCases.allSatisfy { $0.rawValue.lowercased() != token && $0.displayName.lowercased() != token }
            }
    }

    private static func parseCategories(from value: String) -> Set<PlaceCategory> {
        Set(PlaceCategory.allCases.filter { category in
            containsAny(value, keywords: [category.rawValue, category.displayName.lowercased(), categoryKeyword(category)])
        })
    }

    private static func parsePlatforms(from value: String) -> Set<SourcePlatform> {
        var result = Set<SourcePlatform>()
        if containsAny(value, keywords: ["instagram", "ig"]) { result.insert(.instagram) }
        if value.contains("threads") { result.insert(.threads) }
        if containsAny(value, keywords: ["xiaohongshu", "xhs", "小紅書", "小红书"]) { result.insert(.xiaohongshu) }
        if containsAny(value, keywords: ["google maps", "googlemaps", "maps", "地圖", "地图"]) { result.insert(.googleMaps) }
        return result
    }

    private static func parseStates(from value: String) -> Set<SaveSearchUserState> {
        var result = Set<SaveSearchUserState>()
        if containsAny(value, keywords: ["visited", "tried", "去過", "去过", "吃過", "吃过"]) { result.insert(.visited) }
        if containsAny(value, keywords: ["review", "pending", "waiting", "待確認", "待确认"]) { result.insert(.waitingReview) }
        if containsAny(value, keywords: ["source only", "source-only", "clue", "線索", "线索"]) { result.insert(.sourceOnly) }
        if containsAny(value, keywords: ["want to go", "want", "想去"]) { result.insert(.wantToGo) }
        return result
    }

    private static func categoryKeyword(_ category: PlaceCategory) -> String {
        switch category {
        case .food: return "restaurant"
        case .cafe: return "coffee"
        case .bar: return "drink"
        case .attraction: return "spot"
        case .stay: return "hotel"
        case .shopping: return "shop"
        }
    }

    private static func containsAny(_ value: String, keywords: [String]) -> Bool {
        keywords.contains { value.contains($0.lowercased()) }
    }

    private static func term(_ term: String, matches haystack: String) -> Bool {
        if haystack.contains(term) { return true }
        if term == "la", haystack.contains("los angeles") { return true }
        if term == "sf", haystack.contains("san francisco") { return true }
        if term == "nyc", haystack.contains("new york") { return true }
        return false
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func makeStableIDFragment(from value: String) -> String {
        let fragment = value
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return fragment.isEmpty ? "empty-query" : fragment
    }
}
