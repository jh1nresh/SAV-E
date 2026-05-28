import Foundation

struct SaveSearchController {
    func shouldPrepareMapCandidates(for rawQuery: String) -> Bool {
        SaveSearchQuery(rawValue: rawQuery).wantsMapCandidatePreparation
    }

    func shouldSearchNearbyUnsavedCandidatesImmediately(for rawQuery: String) -> Bool {
        SaveSearchQuery(rawValue: rawQuery).wantsPublicDiscovery
    }

    func mapCandidateCategories(for rawQuery: String) -> Set<PlaceCategory> {
        SaveSearchQuery(rawValue: rawQuery).categories
    }

    func makeSaveDraft(from result: SaveSearchResult) -> SavePlaceDraft? {
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            result.objectType == .mapVisibleUnsavedPlace,
            !title.isEmpty,
            result.latitude != nil,
            result.longitude != nil
        else {
            return nil
        }

        return SavePlaceDraft(
            title: title,
            address: result.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            latitude: result.latitude,
            longitude: result.longitude,
            category: result.category,
            sourceURL: result.sourceURL,
            sourcePlatform: result.sourcePlatform,
            evidence: result.evidence,
            externalRating: result.rating,
            externalReviewCount: result.reviewCount
        )
    }

    func makeSavedPlace(from draft: SavePlaceDraft, createdAt: Date = Date()) throws -> Place {
        guard let latitude = draft.latitude, let longitude = draft.longitude else {
            throw SavePlaceDraftError.missingCoordinates
        }

        let address = draft.address ?? ""
        var noteLines = draft.evidence
        if let externalReviewCount = draft.externalReviewCount {
            noteLines.append("External reviews: \(externalReviewCount)")
        }

        return Place(
            id: UUID(),
            name: draft.title,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: draft.category ?? .inferred(from: "\(draft.title) \(address)"),
            status: .wantToGo,
            rating: nil,
            note: noteLines.isEmpty ? nil : noteLines.joined(separator: "\n"),
            sourceUrl: draft.sourceURL,
            sourcePlatform: draft.sourcePlatform ?? .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: draft.externalRating,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt
        )
    }

    func saveMapCandidate(_ draft: SavePlaceDraft) async throws -> Place {
        try makeSavedPlace(from: draft)
    }

    func search(
        query rawQuery: String,
        places: [Place],
        localRecords: [SaveMemoryRecord],
        mapCandidates: [SaveMapCandidate] = []
    ) -> SaveSearchResponse {
        let query = SaveSearchQuery(rawValue: rawQuery)
        let placeResults = places.map(makePlaceResult)
        let recordResults = localRecords.map(makeRecordResult)
        let localResults = (placeResults + recordResults)
            .filter { query.matches($0) }
            .sorted { lhs, rhs in
                let lhsScore = query.score(lhs)
                let rhsScore = query.score(rhs)
                if lhsScore == rhsScore {
                    if let lhsDistance = lhs.distanceMeters, let rhsDistance = rhs.distanceMeters, lhsDistance != rhsDistance {
                        return lhsDistance < rhsDistance
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return lhsScore > rhsScore
            }
        let mapRecommendationResults = mapCandidates
            .map(makeMapCandidateResult)
            .filter { result in
                if !query.categories.isEmpty, let category = result.category {
                    return query.categories.contains(category)
                }
                return query.matches(result) || query.terms.isEmpty
            }
            .sorted { lhs, rhs in
                let lhsScore = query.score(lhs)
                let rhsScore = query.score(rhs)
                if lhsScore == rhsScore { return lhs.createdAt > rhs.createdAt }
                return lhsScore > rhsScore
            }

        let recommendationResults = !mapRecommendationResults.isEmpty
            ? mapRecommendationResults
            : (query.wantsPublicDiscovery && localResults.isEmpty ? [makeRecommendationShell(for: query)] : [])

        return SaveSearchResponse(
            query: rawQuery,
            fromYourSave: SaveSearchSection(
                id: "from-your-save",
                title: "Spatial memory canvas",
                subtitle: "Map Stamps are confirmed saved memories. Review Candidates and clues stay labeled separately.",
                results: localResults,
                emptyMessage: "No matching Map Stamp yet. Try a city, category, source, or place name."
            ),
            newRecommendations: SaveSearchSection(
                id: "new-recommendations",
                title: "Recommendations",
                subtitle: "Contextual answers from SAV-E. Unsaved candidates stay separate from Map Stamps.",
                results: recommendationResults,
                emptyMessage: "Type “recommend new cafe in LA” to ask the drawer for a contextual answer."
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
            statusLabel: isVisited ? "Visited Map Stamp" : place.status.memoryCardLabel,
            sourceURL: place.sourceUrl,
            sourcePlatform: place.sourcePlatform,
            category: place.category,
            cityOrArea: cityOrArea(from: place.address),
            latitude: place.latitude,
            longitude: place.longitude,
            rating: place.googleRating ?? place.rating,
            reviewCount: nil,
            confidence: nil,
            missingInfo: [],
            evidence: placeEvidence(place),
            recoveryQueries: [],
            createdAt: place.createdAt,
            canRunRecovery: false,
            isRecommendationShell: false,
            primaryAction: place.sourceUrl == nil ? .planAround : .openSource
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
            statusLabel = "Clue · needs exact place"
        case .reviewCandidate:
            objectType = .pendingCandidate
            userState = .waitingReview
            statusLabel = "Review Candidate"
        case .confirmedPlace:
            objectType = .savedPlace
            userState = .wantToGo
            statusLabel = "Map Stamp"
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
            latitude: nil,
            longitude: nil,
            rating: nil,
            reviewCount: nil,
            confidence: nil,
            missingInfo: record.evidenceDiagnostic?.missingFields ?? [],
            evidence: record.evidence,
            recoveryQueries: recoveryQueries(from: record.evidenceDiagnostic),
            createdAt: record.createdAt,
            canRunRecovery: record.state == .sourceOnly,
            isRecommendationShell: false,
            primaryAction: record.state == .sourceOnly ? .runRecovery : .openSource
        )
    }

    private func makeRecommendationShell(for query: SaveSearchQuery) -> SaveSearchResult {
        SaveSearchResult(
            id: "new-recommendation-shell-\(query.stableIDFragment)",
            objectType: .newRecommendation,
            userState: .unsaved,
            title: "Search new places for “\(query.rawValue)”",
            subtitle: "SAV-E will keep recommendations separate from confirmed Map Stamps.",
            statusLabel: "Recommendation · unsaved",
            sourceURL: nil,
            sourcePlatform: nil,
            category: query.categories.first,
            cityOrArea: nil,
            latitude: nil,
            longitude: nil,
            rating: nil,
            reviewCount: nil,
            confidence: nil,
            missingInfo: ["Choose a concrete place before it becomes a Review Candidate or Map Stamp"],
            evidence: ["Recommendation only; no map pin or saved memory was created"],
            recoveryQueries: [],
            createdAt: Date(),
            canRunRecovery: false,
            isRecommendationShell: true,
            primaryAction: .none
        )
    }

    private func makeMapCandidateResult(_ candidate: SaveMapCandidate) -> SaveSearchResult {
        SaveSearchResult(
            id: "map-candidate-\(candidate.id)",
            objectType: .mapVisibleUnsavedPlace,
            userState: .unsaved,
            title: candidate.title,
            subtitle: candidate.subtitle,
            statusLabel: "Unsaved Candidate · not memory",
            sourceURL: candidate.sourceURL,
            sourcePlatform: candidate.sourcePlatform,
            category: candidate.category,
            cityOrArea: cityOrArea(from: candidate.subtitle),
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            rating: candidate.rating,
            reviewCount: candidate.reviewCount,
            confidence: nil,
            missingInfo: [],
            evidence: candidate.evidence.isEmpty ? ["Visible on map; not a Map Stamp yet"] : candidate.evidence,
            recoveryQueries: [],
            createdAt: candidate.createdAt,
            canRunRecovery: false,
            isRecommendationShell: false,
            primaryAction: .savePlace,
            distanceMeters: candidate.distanceMeters,
            photoURL: candidate.photoURL,
            businessPhotoURLs: candidate.businessPhotoURLs
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
        if let dishes = place.extractedDishes, !dishes.isEmpty {
            evidence.append("Saved clues: \(dishes.joined(separator: ", "))")
        }
        if let rating = place.rating {
            evidence.append("Your rating: \(rating)")
        }
        return evidence
    }

    private func recoveryQueries(from diagnostic: SocialPlaceEvidenceDiagnostic?) -> [String] {
        guard let diagnostic else { return [] }
        if let suggestedSearchQueries = diagnostic.suggestedSearchQueries, !suggestedSearchQueries.isEmpty {
            return suggestedSearchQueries
        }
        return diagnostic.nextBestClue.isEmpty ? [] : [diagnostic.nextBestClue]
    }

    private func sourceSubtitle(from sourceURL: String?) -> String {
        guard let sourceURL, let url = URL(string: sourceURL), let host = url.host else {
            return "Saved source"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func sourcePlatform(from sourceURL: String?) -> SourcePlatform? {
        guard let host = sourceURL.flatMap(URL.init(string:))?.host?.lowercased().removingWWWPrefix else { return nil }
        if host.matchesDomain("instagram.com") { return .instagram }
        if host.matchesDomain("threads.net") || host.matchesDomain("threads.com") { return .threads }
        if host.matchesDomain("xiaohongshu.com") || host.matchesDomain("xhslink.com") { return .xiaohongshu }
        if host.matchesDomain("google.com") || host.matchesDomain("goo.gl") || host.matchesDomain("maps.app.goo.gl") {
            return .googleMaps
        }
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingWWWPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }

    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}

private struct SaveSearchQuery {
    let rawValue: String
    let normalizedRaw: String
    let terms: [String]
    let categories: Set<PlaceCategory>
    let platforms: Set<SourcePlatform>
    let states: Set<SaveSearchUserState>
    let intent: SaveIntentQuery?
    let wantsNewRecommendations: Bool
    let wantsPublicDiscovery: Bool
    let wantsMapCandidatePreparation: Bool
    let stableIDFragment: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedRaw = Self.normalize(rawValue)
        intent = SaveIntentQuery.parse(from: normalizedRaw)
        categories = Self.parseCategories(from: normalizedRaw).union(intent?.categories ?? [])
        platforms = Self.parsePlatforms(from: normalizedRaw)
        states = Self.parseStates(from: normalizedRaw)
        let containsRecommendationKeyword = Self.containsAny(
            normalizedRaw,
            keywords: ["recommend", "recommendation", "new", "discover", "nearby", "nearest", "suggest", "search", "looking for", "推薦", "新的", "附近", "找", "找新"]
        )
        let containsCravingIntent = intent != nil && Self.containsAny(
            normalizedRaw,
            keywords: ["want", "craving", "feel like", "想", "想喝", "想吃", "喝", "吃"]
        )
        wantsPublicDiscovery = Self.containsAny(
            normalizedRaw,
            keywords: [
                "unsaved", "public", "discover", "search nearby unsaved",
                "new cafe", "new cafes", "new restaurant", "new restaurants",
                "new place", "new places", "new spot", "new spots",
                "new recommendation", "recommend new", "find new", "search new",
                "新的", "沒存", "未儲存", "找新"
            ]
        )
        let containsPlaceSearchLanguage = Self.containsAny(
            normalizedRaw,
            keywords: ["find", "search", "looking for", "nearby", "nearest", "near me", "around here", "找", "搜尋", "搜索", "附近"]
        )
        wantsMapCandidatePreparation = wantsPublicDiscovery ||
            (intent != nil && (containsPlaceSearchLanguage || !categories.isEmpty))
        wantsNewRecommendations = containsRecommendationKeyword || containsCravingIntent
        stableIDFragment = Self.makeStableIDFragment(from: normalizedRaw)
        terms = Self.parseTerms(from: normalizedRaw, intent: intent)
    }

    func matches(_ result: SaveSearchResult) -> Bool {
        let intentMatches = intent?.matches(result) ?? false
        let intentCategoryMatches = intent?.categoryMatches(result) ?? false
        if !categories.isEmpty, let category = result.category, !categories.contains(category) {
            return false
        }
        if !categories.isEmpty, result.category == nil, !intentMatches {
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
            return !categories.isEmpty || !platforms.isEmpty || !states.isEmpty || normalizedRaw.isEmpty || intentMatches || intentCategoryMatches
        }
        let haystack = Self.normalize(result.searchText)
        let termMatches = terms.allSatisfy { Self.term($0, matches: haystack) }
        if intent != nil {
            return termMatches && (intentMatches || intentCategoryMatches)
        }
        return termMatches
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
        value += intent?.score(result) ?? 0
        if wantsNewRecommendations {
            value += Int((result.rating ?? 0) * 2)
            value += min(result.reviewCount ?? 0, 5_000) / 500
        }
        switch result.objectType {
        case .savedPlace, .triedMemory: value += 4
        case .pendingCandidate, .mapVisibleUnsavedPlace: value += 3
        case .sourceOnlyClue: value += 2
        case .review, .tripStop, .newRecommendation: value += 1
        }
        return value
    }

    private static func parseTerms(from value: String, intent: SaveIntentQuery?) -> [String] {
        let stopwords: Set<String> = [
            "my", "your", "save", "saved", "place", "places", "memory", "memories",
            "card", "cards", "review", "source", "only", "want", "to", "go", "visited",
            "tried", "recommend", "recommendation", "new", "discover", "nearby", "suggest",
            "today", "tonight", "now", "找", "我的", "儲存", "地點", "記憶", "推薦", "附近", "新的", "待確認",
            "今天", "今晚", "想", "想要", "喝", "吃", "店"
        ]
        return value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) }
            .filter { token in intent?.isIntentToken(token) != true }
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

    fileprivate static func term(_ term: String, matches haystack: String) -> Bool {
        if haystack.contains(term) { return true }
        if term == "la", haystack.contains("los angeles") { return true }
        if term == "sf", haystack.contains("san francisco") { return true }
        if term == "nyc", haystack.contains("new york") { return true }
        return false
    }

    fileprivate static func normalize(_ value: String) -> String {
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

private struct SaveIntentQuery {
    let id: String
    let categories: Set<PlaceCategory>
    let needles: [String]

    static func parse(from normalizedQuery: String) -> SaveIntentQuery? {
        let specs: [SaveIntentQuery] = [
            SaveIntentQuery(
                id: "milk-tea",
                categories: [.cafe],
                needles: ["milk tea", "boba", "bubble tea", "奶茶", "珍奶", "珍珠奶茶"]
            ),
            SaveIntentQuery(
                id: "coffee",
                categories: [.cafe],
                needles: ["coffee", "cafe", "咖啡"]
            ),
            SaveIntentQuery(
                id: "food",
                categories: [.food],
                needles: ["food", "restaurant", "dinner", "lunch", "餐廳", "餐厅", "吃飯", "吃饭", "美食"]
            ),
            SaveIntentQuery(
                id: "bar",
                categories: [.bar],
                needles: ["bar", "cocktail", "drink", "喝酒", "酒吧", "調酒", "调酒"]
            ),
            SaveIntentQuery(
                id: "attraction",
                categories: [.attraction],
                needles: ["museum", "gallery", "exhibition", "展覽", "展览", "美術館", "美术馆", "博物館", "博物馆"]
            ),
            SaveIntentQuery(
                id: "stay",
                categories: [.stay],
                needles: ["hotel", "stay", "住宿", "飯店", "酒店"]
            )
        ]
        return specs.first { spec in
            spec.needles.contains { normalizedQuery.contains($0) }
        }
    }

    func matches(_ result: SaveSearchResult) -> Bool {
        let haystack = SaveSearchQuery.normalize(result.searchText)
        return needles.contains { SaveSearchQuery.term($0, matches: haystack) }
    }

    func categoryMatches(_ result: SaveSearchResult) -> Bool {
        guard let category = result.category else { return false }
        return categories.contains(category)
    }

    func score(_ result: SaveSearchResult) -> Int {
        if matches(result) { return 40 }
        if categoryMatches(result) { return 10 }
        return 0
    }

    func isIntentToken(_ token: String) -> Bool {
        needles.contains { needle in
            token == needle || token.contains(needle) || needle.contains(token)
        }
    }
}
