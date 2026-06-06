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

    func exactMapCandidateQuery(for rawQuery: String) -> String? {
        SaveSearchQuery(rawValue: rawQuery).exactMapCandidateQuery
    }

    func specialtyMapCandidateQuery(for rawQuery: String) -> String? {
        SaveSearchQuery(rawValue: rawQuery).specialtyMapCandidateQuery
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
        reviewCandidates: [PlaceReviewCandidate] = [],
        mapCandidates: [SaveMapCandidate] = []
    ) -> SaveSearchResponse {
        let query = SaveSearchQuery(rawValue: rawQuery)
        let placeResults = places.map(makePlaceResult)
        let recordResults = localRecords.map(makeRecordResult)
        let reviewResults = reviewCandidates.map(makeReviewCandidateResult)
        let localResults = (placeResults + recordResults + reviewResults)
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
                    guard query.categories.contains(category) else { return false }
                    if query.intent?.requiresSpecificEvidenceMatch == true {
                        return query.matches(result)
                    }
                    return query.terms.isEmpty || query.matches(result)
                }
                return query.matches(result) || query.terms.isEmpty
            }
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

        let recommendationResults = !mapRecommendationResults.isEmpty
            ? mapRecommendationResults
            : (query.wantsPublicDiscovery && localResults.isEmpty ? [makeRecommendationShell(for: query)] : [])

        return SaveSearchResponse(
            query: rawQuery,
            assistantMessage: assistantMessage(
                for: query,
                savedCount: localResults.filter { $0.objectType == .savedPlace || $0.objectType == .triedMemory }.count,
                reviewCount: localResults.filter { $0.objectType == .pendingCandidate || $0.objectType == .sourceOnlyClue }.count,
                unsavedCount: mapRecommendationResults.count
            ),
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
            primaryAction: SavePlaceActionResolution(place: place).kind
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

        let resolvedPrimaryAction = primaryAction(for: record)
        return SaveSearchResult(
            id: "record-\(record.id.uuidString)",
            objectType: objectType,
            userState: userState,
            title: record.displayTitle,
            subtitle: record.address ?? sourceSubtitle(from: record.sourceURL),
            statusLabel: statusLabel,
            sourceURL: record.sourceURL,
            sourcePlatform: sourcePlatform(from: record.sourceURL),
            category: record.category,
            cityOrArea: record.address.flatMap(cityOrArea),
            latitude: record.latitude,
            longitude: record.longitude,
            rating: record.rating,
            reviewCount: nil,
            confidence: nil,
            missingInfo: record.evidenceDiagnostic?.missingFields ?? [],
            evidence: evidenceWithRecoveryReceipt(record.evidence, diagnostic: record.evidenceDiagnostic),
            recoveryQueries: recoveryQueries(from: record.evidenceDiagnostic),
            createdAt: record.createdAt,
            canRunRecovery: resolvedPrimaryAction == .runRecovery,
            isRecommendationShell: false,
            primaryAction: resolvedPrimaryAction
        )
    }

    private func makeReviewCandidateResult(_ candidate: PlaceReviewCandidate) -> SaveSearchResult {
        let category = PlaceCategory.inferred(from: ([candidate.name, candidate.address, candidate.city ?? ""] + candidate.evidence).joined(separator: " "))
        let isMapReady = candidate.hasReliableCoordinates
        return SaveSearchResult(
            id: "review-candidate-\(candidate.id.uuidString)",
            objectType: isMapReady ? .pendingCandidate : .sourceOnlyClue,
            userState: isMapReady ? .waitingReview : .sourceOnly,
            title: candidate.name,
            subtitle: candidate.address.isEmpty ? (candidate.city ?? "Needs address confirmation") : candidate.address,
            statusLabel: isMapReady ? "Review Candidate" : "Clue · needs exact place",
            sourceURL: nil,
            sourcePlatform: nil,
            category: category,
            cityOrArea: candidate.city,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            rating: nil,
            reviewCount: nil,
            confidence: candidate.confidence,
            missingInfo: candidate.missingInfo,
            evidence: candidate.evidence.isEmpty ? ["Waiting in Review"] : candidate.evidence,
            recoveryQueries: isMapReady ? [] : [candidate.refinementQuery].filter { !$0.isEmpty },
            createdAt: candidate.createdAt,
            canRunRecovery: !isMapReady,
            isRecommendationShell: false,
            primaryAction: isMapReady ? .confirmMapStamp : .runRecovery
        )
    }

    private func primaryAction(for record: SaveMemoryRecord) -> SaveSearchPrimaryAction {
        switch record.state {
        case .sourceOnly:
            return .runRecovery
        case .reviewCandidate:
            return canConfirmMapStamp(record) ? .confirmMapStamp : .runRecovery
        case .confirmedPlace:
            return .recommendOrder
        }
    }

    private func canConfirmMapStamp(_ record: SaveMemoryRecord) -> Bool {
        if record.evidenceDiagnostic?.canSaveAsMapStamp == true { return true }
        guard record.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              record.latitude != nil,
              record.longitude != nil
        else {
            return false
        }
        let missing = record.evidenceDiagnostic?.missingFields.map { $0.lowercased() } ?? []
        return !missing.contains { $0.contains("address") || $0.contains("coordinate") }
    }

    private func assistantMessage(
        for query: SaveSearchQuery,
        savedCount: Int,
        reviewCount: Int,
        unsavedCount: Int
    ) -> String? {
        guard query.wantsNewRecommendations || query.wantsMapCandidatePreparation else { return nil }
        let category = query.categories.first?.displayName.lowercased() ?? "places"
        var parts: [String] = []
        if savedCount > 0 {
            parts.append("\(savedCount) saved Map Stamp\(savedCount == 1 ? "" : "s")")
        }
        if reviewCount > 0 {
            parts.append("\(reviewCount) Review candidate\(reviewCount == 1 ? "" : "s")")
        }
        if unsavedCount > 0 {
            parts.append("\(unsavedCount) nearby unsaved option\(unsavedCount == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return "I do not see a Saved \(category) match yet. I can show nearby unsaved options, and they stay unsaved until you save one."
        }
        if savedCount > 0 {
            return "I found \(parts.joined(separator: ", ")). Start with the rows labeled Saved; Review and unsaved options stay separate until you choose one."
        }
        return "I found \(parts.joined(separator: ", ")). Review and unsaved options are listed separately so you can decide what becomes Saved."
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
        if let recoveryPlan = diagnostic.recoveryPlan, !recoveryPlan.queriesToTry.isEmpty {
            return recoveryPlan.queriesToTry
        }
        if let suggestedSearchQueries = diagnostic.suggestedSearchQueries, !suggestedSearchQueries.isEmpty {
            return suggestedSearchQueries
        }
        return diagnostic.nextBestClue.isEmpty ? [] : [diagnostic.nextBestClue]
    }

    private func evidenceWithRecoveryReceipt(_ evidence: [String], diagnostic: SocialPlaceEvidenceDiagnostic?) -> [String] {
        guard let diagnostic else { return evidence }
        var receipt = [
            "Recovery status: \(diagnostic.statusLabel)",
            "Next action: \(diagnostic.primaryActionLabel)"
        ]
        if let recoveryPlan = diagnostic.recoveryPlan {
            receipt.append("Recovery decision: \(recoveryPlan.decision.rawValue); direct save \(recoveryPlan.allowsDirectSave ? "allowed" : "blocked")")
            receipt.append(contentsOf: recoveryPlan.requiredEvidence.prefix(3).map { "Required proof: \($0)" })
            receipt.append(contentsOf: recoveryPlan.blockedResultHints.prefix(2).map { "Rejected clue type: \($0)" })
        }
        receipt.append(contentsOf: (diagnostic.rejectedEvidence ?? []).prefix(2).map { "Rejected evidence: \($0.value) — \($0.reason)" })
        var seen = Set<String>()
        return (evidence + receipt).filter { seen.insert($0).inserted }
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
        if host.matchesDomain("douyin.com") || host.matchesDomain("iesdouyin.com") { return .douyin }
        if host.matchesDomain("amap.com") { return .amap }
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
    let exactMapCandidateQuery: String?
    let specialtyMapCandidateQuery: String?
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
        wantsNewRecommendations = containsRecommendationKeyword || containsCravingIntent
        stableIDFragment = Self.makeStableIDFragment(from: normalizedRaw)
        terms = Self.parseTerms(from: normalizedRaw, intent: intent)
        specialtyMapCandidateQuery = intent?.publicSearchQuery
        exactMapCandidateQuery = Self.exactMapCandidateQuery(
            rawValue: self.rawValue,
            normalizedRaw: normalizedRaw,
            terms: terms,
            categories: categories,
            containsPlaceSearchLanguage: containsPlaceSearchLanguage
        )
        wantsMapCandidatePreparation = wantsPublicDiscovery ||
            exactMapCandidateQuery != nil ||
            (intent != nil && (containsPlaceSearchLanguage || !categories.isEmpty))
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
        if intent?.requiresSpecificEvidenceMatch == true {
            return intentMatches
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
        let intentMatches = intent?.matches(result) ?? false
        var value = 0
        for term in terms where Self.term(term, matches: haystack) {
            value += result.title.lowercased().contains(term) ? 12 : 5
        }
        if let category = result.category, categories.contains(category) { value += 8 }
        if let sourcePlatform = result.sourcePlatform, platforms.contains(sourcePlatform) { value += 6 }
        if states.contains(result.userState) { value += 6 }
        value += intent?.score(result) ?? 0
        if intent?.requiresSpecificEvidenceMatch == true, !intentMatches {
            value -= 20
        }
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

    private static func exactMapCandidateQuery(
        rawValue: String,
        normalizedRaw: String,
        terms: [String],
        categories: Set<PlaceCategory>,
        containsPlaceSearchLanguage: Bool
    ) -> String? {
        guard categories.isEmpty, !normalizedRaw.isEmpty else { return nil }
        guard !containsAny(normalizedRaw, keywords: ["http://", "https://"]) else { return nil }
        guard !containsAny(normalizedRaw, keywords: ["recommend", "recommendation", "date night", "tonight", "推薦", "今晚"]) else {
            return nil
        }

        let cleaned = cleanedExactMapQuery(rawValue)
        guard !cleaned.isEmpty else { return nil }

        if containsPlaceSearchLanguage, !terms.isEmpty {
            return cleaned
        }
        if looksLikeAddressQuery(rawValue: rawValue, normalizedRaw: normalizedRaw) {
            return cleaned
        }
        if looksLikeVenueName(rawValue: rawValue, terms: terms) {
            return cleaned
        }
        return nil
    }

    private static func cleanedExactMapQuery(_ rawValue: String) -> String {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "search nearby unsaved candidates for ",
            "search exact place for ",
            "find exact place for ",
            "search place for ",
            "search ",
            "find ",
            "looking for ",
            "找 ",
            "搜尋 ",
            "搜索 "
        ]
        var lowered = normalize(cleaned)
        var didStripPrefix = true
        while didStripPrefix {
            didStripPrefix = false
            for prefix in prefixes where lowered.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                lowered = normalize(cleaned)
                didStripPrefix = true
                break
            }
        }
        return cleaned
    }

    private static func looksLikeAddressQuery(rawValue: String, normalizedRaw: String) -> Bool {
        let hasNumber = rawValue.rangeOfCharacter(from: .decimalDigits) != nil
        guard hasNumber else { return false }
        return containsAny(
            normalizedRaw,
            keywords: [" no.", "no ", "號", "号", "路", "街", "rd", "road", "st", "street", "ave", "avenue", "district", "區", "区"]
        )
    }

    private static func looksLikeVenueName(rawValue: String, terms: [String]) -> Bool {
        guard terms.count >= 2 else { return false }
        let words = rawValue
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let titleCasedWords = words.filter { word in
            guard let first = word.unicodeScalars.first else { return false }
            return CharacterSet.uppercaseLetters.contains(first)
        }
        return words.count >= 3 && titleCasedWords.count >= 2
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
        if containsAny(value, keywords: ["douyin", "抖音"]) { result.insert(.douyin) }
        if containsAny(value, keywords: ["google maps", "googlemaps", "maps", "地圖", "地图"]) { result.insert(.googleMaps) }
        if containsAny(value, keywords: ["amap", "gaode", "高德", "高德地圖", "高德地图"]) { result.insert(.amap) }
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
    let publicSearchQuery: String?
    let requiresSpecificEvidenceMatch: Bool

    init(entry: SaveSearchIntentLexicon.Entry) {
        id = entry.id
        categories = [entry.category]
        needles = entry.needles
        publicSearchQuery = entry.publicSearchQuery
        requiresSpecificEvidenceMatch = entry.requiresSpecificEvidenceMatch
    }

    static func parse(from normalizedQuery: String) -> SaveIntentQuery? {
        SaveSearchIntentLexicon.match(in: normalizedQuery).map(SaveIntentQuery.init(entry:))
    }

    func matches(_ result: SaveSearchResult) -> Bool {
        let haystack = SaveSearchQuery.normalize(requiresSpecificEvidenceMatch ? specificEvidenceText(for: result) : result.searchText)
        return needles.contains { SaveSearchQuery.term($0, matches: haystack) }
    }

    func categoryMatches(_ result: SaveSearchResult) -> Bool {
        guard let category = result.category else { return false }
        return categories.contains(category)
    }

    func score(_ result: SaveSearchResult) -> Int {
        if matches(result) { return 40 }
        if !requiresSpecificEvidenceMatch, categoryMatches(result) { return 10 }
        return 0
    }

    func isIntentToken(_ token: String) -> Bool {
        needles.contains { needle in
            token == needle || token.contains(needle) || needle.contains(token)
        }
    }

    private func specificEvidenceText(for result: SaveSearchResult) -> String {
        let evidence = result.evidence.filter { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: "search:", options: [.caseInsensitive, .anchored]) == nil
        }
        return [
            result.title,
            result.subtitle,
            result.statusLabel,
            result.sourcePlatform?.displayName,
            result.cityOrArea,
            result.missingInfo.joined(separator: " "),
            evidence.joined(separator: " "),
            result.recoveryQueries.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
