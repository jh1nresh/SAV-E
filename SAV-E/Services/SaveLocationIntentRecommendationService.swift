import CoreLocation
import Foundation

struct SaveLocationIntentRecommendationService {
    private let parser: SaveSearchIntentParser

    init(parser: SaveSearchIntentParser = SaveSearchIntentParser()) {
        self.parser = parser
    }

    func requiresCurrentLocation(for query: String) -> Bool {
        guard let intent = parser.parse(query) else { return false }
        return intent.mustMatchLocation
    }

    func recommendationSearchResponse(
        for query: String,
        places: [Place],
        reviewCandidates: [PlaceReviewCandidate] = [],
        mapCandidates: [SaveMapCandidate] = [],
        currentLocation: CLLocation?
    ) -> SaveSearchResponse? {
        guard var intent = parser.parse(query),
              intent.kind == .categoryRecommendation || intent.kind == .craving || intent.mustMatchLocation else {
            return nil
        }
        guard intent.sourceScope != .publicOnly else { return nil }
        let tasteProfile = SaveTasteProfile(places: places)
        if intent.requiredCategories.isEmpty, let frequentCategory = tasteProfile.mostSavedCategory {
            intent = intent.withRequiredCategory(frequentCategory)
        }

        if let unsupportedCategoryLabel = intent.unsupportedCategoryLabel {
            return emptyResponse(
                query: query,
                title: "Unsupported category",
                message: "SAV-E doesn't have a \(unsupportedCategoryLabel) category yet, so I won't map this to food or cafe by accident. You can search saved names/notes, or ask to search public nearby places."
            )
        }

        guard !intent.requiredCategories.isEmpty else { return nil }

        if intent.mustMatchLocation, currentLocation == nil {
            return emptyResponse(
                query: query,
                title: "Location needed",
                message: "I need your current location before I can answer nearby requests. Or ask for saved \(categoryLabel(for: intent)) anywhere."
            )
        }

        let categoryMatches = places.filter { place in
            intent.requiredCategories.contains(place.category)
        }
        let rankedCategoryMatches = rank(categoryMatches, for: intent, currentLocation: currentLocation, tasteProfile: tasteProfile)
        let reviewMatches = rankReviewCandidates(
            reviewCandidates.filter { candidate in
                intent.requiredCategories.contains(inferredCategory(for: candidate))
            },
            currentLocation: currentLocation
        )
        let mapMatches = rankMapCandidates(
            mapCandidates.filter { candidate in
                intent.requiredCategories.contains(inferredCategory(for: candidate))
            }
        )

        if intent.mustMatchLocation,
           case .currentLocation(let radiusMeters) = intent.locationMode,
           let currentLocation {
            let nearby = rankedCategoryMatches.filter {
                distanceMeters(from: currentLocation, to: $0) <= radiusMeters
            }
            let far = rankedCategoryMatches.filter {
                distanceMeters(from: currentLocation, to: $0) > radiusMeters
            }

            guard !nearby.isEmpty else {
                let farContext = far.isEmpty
                    ? ""
                    : " You do have saved \(categoryLabel(for: intent)) places, but the closest one is outside the nearby radius."
                return sectionedResponse(
                    query: query,
                    message: "你的 SAV-E 裡附近沒有\(localizedCategoryLabel(for: intent))。I did not recommend other categories because you asked for \(categoryLabel(for: intent)).\(farContext)",
                    nearby: [],
                    far: far,
                    reviewCandidates: reviewMatches,
                    mapCandidates: mapMatches,
                    intent: intent,
                    currentLocation: currentLocation,
                    tasteProfile: tasteProfile,
                    showFallbackAction: true
                )
            }

            return sectionedResponse(
                query: query,
                message: "Found \(nearby.count) saved nearby \(categoryLabel(for: intent)) place\(nearby.count == 1 ? "" : "s") from your SAV-E.",
                nearby: nearby,
                far: far,
                reviewCandidates: reviewMatches,
                mapCandidates: mapMatches,
                intent: intent,
                currentLocation: currentLocation,
                tasteProfile: tasteProfile,
                showFallbackAction: false
            )
        }

        guard !rankedCategoryMatches.isEmpty else {
            if !reviewMatches.isEmpty || !mapMatches.isEmpty {
                return sectionedResponse(
                    query: query,
                    message: "Your SAV-E does not have saved \(categoryLabel(for: intent)) places yet. Review candidates and public discovery stay separate until you choose what to save.",
                    nearby: [],
                    far: [],
                    reviewCandidates: reviewMatches,
                    mapCandidates: mapMatches,
                    intent: intent,
                    currentLocation: currentLocation,
                    tasteProfile: tasteProfile,
                    showFallbackAction: mapMatches.isEmpty
                )
            }
            return emptyResponse(
                query: query,
                title: "No saved \(categoryLabel(for: intent))",
                message: "Your SAV-E does not have saved \(categoryLabel(for: intent)) places yet.",
                showFallbackAction: true
            )
        }

        return sectionedResponse(
            query: query,
            message: "Showing saved \(categoryLabel(for: intent)) places from your SAV-E.",
            nearby: rankedCategoryMatches,
            far: [],
            reviewCandidates: reviewMatches,
            mapCandidates: mapMatches,
            intent: intent,
            currentLocation: currentLocation,
            tasteProfile: tasteProfile,
            showFallbackAction: false
        )
    }

    func recommendationResponse(
        for query: String,
        places: [Place],
        reviewCandidates: [PlaceReviewCandidate] = [],
        mapCandidates: [SaveMapCandidate] = [],
        currentLocation: CLLocation?
    ) -> SaveAIResponse? {
        guard let response = recommendationSearchResponse(
            for: query,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            currentLocation: currentLocation
        ) else {
            return nil
        }
        let ids = response.fromYourSave.results.map { rawPlaceId(from: $0.id) }.compactMap { $0 }
        return SaveAIResponse(
            componentType: ids.isEmpty ? .message : .placeList,
            title: response.fromYourSave.title,
            placeIds: ids,
            navigationPlaceId: nil,
            transportMode: .walking,
            itineraryDays: [],
            messageText: response.fromYourSave.emptyMessage,
            mapAction: ids.isEmpty ? nil : MapActionData(type: .filterPins, placeIds: ids, lat: nil, lng: nil, span: nil),
            aiMessage: response.fromYourSave.subtitle
        )
    }

    private func rank(_ places: [Place], for intent: SaveSearchIntent, currentLocation: CLLocation?, tasteProfile: SaveTasteProfile) -> [Place] {
        places.sorted { lhs, rhs in
            let lhsNeedleScore = evidenceScore(lhs, needles: intent.categoryNeedles)
            let rhsNeedleScore = evidenceScore(rhs, needles: intent.categoryNeedles)
            if lhsNeedleScore != rhsNeedleScore { return lhsNeedleScore > rhsNeedleScore }

            let lhsTasteScore = tasteProfile.score(lhs)
            let rhsTasteScore = tasteProfile.score(rhs)
            if lhsTasteScore != rhsTasteScore { return lhsTasteScore > rhsTasteScore }

            if let currentLocation {
                return distanceMeters(from: currentLocation, to: lhs) < distanceMeters(from: currentLocation, to: rhs)
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func rankReviewCandidates(_ candidates: [PlaceReviewCandidate], currentLocation: CLLocation?) -> [PlaceReviewCandidate] {
        candidates.sorted { lhs, rhs in
            if let currentLocation,
               let lhsDistance = distanceMeters(from: currentLocation, to: lhs),
               let rhsDistance = distanceMeters(from: currentLocation, to: rhs),
               lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func rankMapCandidates(_ candidates: [SaveMapCandidate]) -> [SaveMapCandidate] {
        candidates.sorted { lhs, rhs in
            if let lhsDistance = lhs.distanceMeters, let rhsDistance = rhs.distanceMeters, lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if let lhsRating = lhs.rating, let rhsRating = rhs.rating, lhsRating != rhsRating {
                return lhsRating > rhsRating
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func evidenceScore(_ place: Place, needles: [String]) -> Int {
        guard !needles.isEmpty else { return 0 }
        let haystack = SaveSearchIntentParser.normalize(
            [
                place.name,
                place.address,
                place.note ?? "",
                place.extractedDishes?.joined(separator: " ") ?? ""
            ].joined(separator: " ")
        )
        return needles.reduce(0) { score, needle in
            haystack.contains(needle) ? score + 1 : score
        }
    }

    private func distanceMeters(from currentLocation: CLLocation, to place: Place) -> CLLocationDistance {
        currentLocation.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private func distanceMeters(from currentLocation: CLLocation, to candidate: PlaceReviewCandidate) -> CLLocationDistance? {
        guard let latitude = candidate.latitude, let longitude = candidate.longitude else { return nil }
        return currentLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    private func sectionedResponse(
        query: String,
        message: String,
        nearby: [Place],
        far: [Place],
        reviewCandidates: [PlaceReviewCandidate],
        mapCandidates: [SaveMapCandidate],
        intent: SaveSearchIntent,
        currentLocation: CLLocation?,
        tasteProfile: SaveTasteProfile,
        showFallbackAction: Bool
    ) -> SaveSearchResponse {
        let mapResults = searchResults(for: mapCandidates)
        let canSearchNearby = showFallbackAction && mapResults.isEmpty
        let nearbyResults = searchResults(for: nearby, intent: intent, currentLocation: currentLocation, isNearby: true, tasteProfile: tasteProfile)
        let reviewResults = searchResults(for: reviewCandidates, currentLocation: currentLocation)
        let farResults = searchResults(for: Array(far.prefix(5)), intent: intent, currentLocation: currentLocation, isNearby: false, tasteProfile: tasteProfile)
        let nearbySection = SaveSearchSection(
                id: "from-your-save-nearby",
                label: "FROM YOUR SAV-E",
                title: "From your SAV-E nearby",
                subtitle: message,
                results: nearbyResults,
                emptyMessage: nearby.isEmpty ? message : nil,
                showsNearbySearchAction: canSearchNearby
        )

        var additional: [SaveSearchSection] = []
        if !reviewResults.isEmpty {
            additional.append(SaveSearchSection(
                id: "review-candidates",
                label: "REVIEW CANDIDATES",
                title: "Waiting in Review Nest",
                subtitle: "Possible matches from your Review queue. Confirm one before it becomes a Map Stamp.",
                results: reviewResults,
                emptyMessage: nil
            ))
        }

        if !far.isEmpty {
            additional.append(SaveSearchSection(
                id: "saved-but-not-nearby",
                label: "SAVED, FAR",
                title: "Saved but not nearby",
                subtitle: "Same category, outside the current nearby radius. Not used as a primary recommendation.",
                results: farResults,
                emptyMessage: nil
            ))
        }

        return SaveSearchResponse(
            query: query,
            assistantMessage: assistantMessage(
                categoryLabel: categoryLabel(for: intent),
                savedResults: nearbyResults,
                reviewResults: reviewResults,
                unsavedResults: mapResults,
                fallbackAvailable: canSearchNearby
            ),
            fromYourSave: nearbySection,
            additionalSections: additional,
            newRecommendations: SaveSearchSection(
                id: "nearby-unsaved-candidates",
                label: "PUBLIC DISCOVERY",
                title: "Public nearby options",
                subtitle: "Public discovery stays separate until you explicitly save one.",
                results: mapResults,
                emptyMessage: canSearchNearby ? "Search public nearby options only if you want places outside your SAV-E memory." : nil,
                showsNearbySearchAction: canSearchNearby
            )
        )
    }

    private func emptyResponse(query: String, title: String, message: String, showFallbackAction: Bool = false) -> SaveSearchResponse {
        SaveSearchResponse(
            query: query,
            assistantMessage: message,
            fromYourSave: SaveSearchSection(
                id: "from-your-save-nearby",
                label: "FROM YOUR SAV-E",
                title: title,
                subtitle: message,
                results: [],
                emptyMessage: message
            ),
            newRecommendations: SaveSearchSection(
                id: "nearby-unsaved-candidates",
                label: "PUBLIC DISCOVERY",
                title: "Public nearby options",
                subtitle: "Public discovery is explicit fallback only.",
                results: [],
                emptyMessage: showFallbackAction ? "Search public nearby options only if you want places outside your SAV-E memory." : nil,
                showsNearbySearchAction: showFallbackAction
            )
        )
    }

    private func searchResults(
        for places: [Place],
        intent: SaveSearchIntent,
        currentLocation: CLLocation?,
        isNearby: Bool,
        tasteProfile: SaveTasteProfile
    ) -> [SaveSearchResult] {
        places.map { place in
            let reasons = reasons(for: place, intent: intent, currentLocation: currentLocation, isNearby: isNearby, tasteProfile: tasteProfile)
            return SaveSearchResult(
                id: "place-\(place.id.uuidString)",
                objectType: place.status == .visited ? .triedMemory : .savedPlace,
                userState: place.status == .visited ? .visited : .wantToGo,
                title: place.name,
                subtitle: place.address,
                statusLabel: place.status.memoryCardLabel,
                sourceURL: place.sourceUrl,
                sourcePlatform: place.sourcePlatform,
                category: place.category,
                cityOrArea: nil,
                latitude: place.latitude,
                longitude: place.longitude,
                rating: place.googleRating ?? place.rating,
                reviewCount: nil,
                confidence: nil,
                missingInfo: [],
                evidence: reasons,
                recoveryQueries: [],
                createdAt: place.createdAt,
                canRunRecovery: false,
                isRecommendationShell: false,
                primaryAction: place.sourceUrl == nil ? .planAround : .openSource
            )
        }
    }

    private func searchResults(
        for candidates: [PlaceReviewCandidate],
        currentLocation: CLLocation?
    ) -> [SaveSearchResult] {
        candidates.map { candidate in
            let category = inferredCategory(for: candidate)
            return SaveSearchResult(
                id: "review-candidate-\(candidate.id.uuidString)",
                objectType: candidate.hasReliableCoordinates ? .pendingCandidate : .sourceOnlyClue,
                userState: candidate.hasReliableCoordinates ? .waitingReview : .sourceOnly,
                title: candidate.name,
                subtitle: candidate.address.isEmpty ? (candidate.city ?? "Needs address confirmation") : candidate.address,
                statusLabel: candidate.hasReliableCoordinates ? "Review Candidate" : "Clue · needs exact place",
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
                evidence: candidateEvidence(candidate, currentLocation: currentLocation),
                recoveryQueries: candidate.hasReliableCoordinates ? [] : [candidate.refinementQuery].filter { !$0.isEmpty },
                createdAt: candidate.createdAt,
                canRunRecovery: !candidate.hasReliableCoordinates,
                isRecommendationShell: false,
                primaryAction: candidate.hasReliableCoordinates ? .savePlace : .runRecovery,
                distanceMeters: currentLocation.flatMap { distanceMeters(from: $0, to: candidate) }
            )
        }
    }

    private func searchResults(for candidates: [SaveMapCandidate]) -> [SaveSearchResult] {
        candidates.map { candidate in
            SaveSearchResult(
                id: "map-candidate-\(candidate.id)",
                objectType: .mapVisibleUnsavedPlace,
                userState: .unsaved,
                title: candidate.title,
                subtitle: candidate.subtitle,
                statusLabel: "Nearby unsaved candidate",
                sourceURL: candidate.sourceURL,
                sourcePlatform: candidate.sourcePlatform,
                category: inferredCategory(for: candidate),
                cityOrArea: nil,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                rating: candidate.rating,
                reviewCount: candidate.reviewCount,
                confidence: nil,
                missingInfo: [],
                evidence: candidate.evidence,
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
    }

    private func candidateEvidence(_ candidate: PlaceReviewCandidate, currentLocation: CLLocation?) -> [String] {
        var evidence = candidate.evidence.isEmpty ? ["Waiting in Review"] : candidate.evidence
        if let currentLocation, let distance = distanceMeters(from: currentLocation, to: candidate) {
            evidence.append("\(distanceLabel(distance)) away")
        }
        return evidence
    }

    private func inferredCategory(for candidate: PlaceReviewCandidate) -> PlaceCategory {
        PlaceCategory.inferred(from: ([candidate.name, candidate.address, candidate.city ?? ""] + candidate.evidence).joined(separator: " "))
    }

    private func inferredCategory(for candidate: SaveMapCandidate) -> PlaceCategory {
        candidate.category ?? PlaceCategory.inferred(from: ([candidate.title, candidate.subtitle] + candidate.evidence).joined(separator: " "))
    }

    private func assistantMessage(
        categoryLabel: String,
        savedResults: [SaveSearchResult],
        reviewResults: [SaveSearchResult],
        unsavedResults: [SaveSearchResult],
        fallbackAvailable: Bool
    ) -> String {
        if let top = savedResults.first {
            return agentAnswer(
                lead: "我會先推 \(top.title)。",
                reason: reasonLine(for: top, fallback: "It is already a Saved Map Stamp in your place memory."),
                caveat: "\(supportingSummary(reviewResults: reviewResults, unsavedResults: unsavedResults))If you want, tell me budget, cuisine, or quick vs sit-down and I’ll narrow it."
            )
        }

        if let top = reviewResults.first {
            return agentAnswer(
                lead: "我不會直接亂推一個未確認地點；先看 \(top.title)。",
                reason: reasonLine(for: top, fallback: "It is waiting in Review, so SAV-E has a clue but still needs confirmation."),
                caveat: "Confirm it into a Map Stamp, or add a clue before trusting it as the recommendation."
            )
        }

        if let top = unsavedResults.first {
            return agentAnswer(
                lead: "你的 SAV-E memory 裡還沒有 saved nearby \(categoryLabel)，但 public nearby 裡我會先看 \(top.title)。",
                reason: reasonLine(for: top, fallback: "It is a nearby public result, not saved memory yet."),
                caveat: "Tell me budget or food mood, or save it first so SAV-E can remember whether you liked it later."
            )
        }

        var parts: [String] = []
        if !savedResults.isEmpty {
            parts.append("\(savedResults.count) saved Map Stamp\(savedResults.count == 1 ? "" : "s")")
        }
        if !reviewResults.isEmpty {
            parts.append("\(reviewResults.count) Review candidate\(reviewResults.count == 1 ? "" : "s")")
        }
        if !unsavedResults.isEmpty {
            parts.append("\(unsavedResults.count) unsaved nearby option\(unsavedResults.count == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return fallbackAvailable
                ? "I do not see a saved nearby \(categoryLabel) in your memory yet. I can search public discovery next, and those places stay unsaved until you choose one."
                : "I do not see a Saved nearby \(categoryLabel) yet."
        }
        return "I did not find a saved nearby \(categoryLabel) in your memory yet. I found \(parts.joined(separator: ", ")); Review candidates and public discovery stay separate so you can choose what to save."
    }

    private func agentAnswer(lead: String, reason: String, caveat: String) -> String {
        "\(lead)\n\nWhy: \(reason)\n\nNext: \(caveat)"
    }

    private func supportingSummary(reviewResults: [SaveSearchResult], unsavedResults: [SaveSearchResult]) -> String {
        var parts: [String] = []
        if !reviewResults.isEmpty {
            parts.append("\(reviewResults.count) Review candidate\(reviewResults.count == 1 ? "" : "s")")
        }
        if !unsavedResults.isEmpty {
            parts.append("\(unsavedResults.count) unsaved nearby option\(unsavedResults.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "" : "I also found \(parts.joined(separator: ", ")); they stay separate. "
    }

    private func reasonLine(for result: SaveSearchResult, fallback: String) -> String {
        var reasons: [String] = []
        switch result.objectType {
        case .savedPlace, .triedMemory:
            reasons.append("Saved Map Stamp")
        case .pendingCandidate, .sourceOnlyClue:
            reasons.append("Review Candidate")
        case .mapVisibleUnsavedPlace, .newRecommendation:
            reasons.append("unsaved public result")
        case .review:
            reasons.append("private review")
        case .tripStop:
            reasons.append("trip stop")
        }
        if let distanceLabel = result.distanceLabel {
            reasons.append(distanceLabel)
        }
        if let rating = result.rating {
            reasons.append(String(format: "%.1f rating", rating))
        }
        if let reviewCount = result.reviewCount {
            reasons.append("\(reviewCount) reviews")
        }
        reasons.append(contentsOf: result.evidence.prefix(2))
        let cleaned = unique(reasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        return cleaned.isEmpty ? fallback : cleaned.joined(separator: " · ")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func reasons(for place: Place, intent: SaveSearchIntent, currentLocation: CLLocation?, isNearby: Bool, tasteProfile: SaveTasteProfile) -> [String] {
        var values = ["\(place.category.displayName) Map Stamp"]
        if !intent.categoryNeedles.isEmpty, evidenceScore(place, needles: intent.categoryNeedles) > 0 {
            values.append("Saved evidence matches \(intent.categoryNeedles.prefix(2).joined(separator: " / "))")
        }
        if tasteProfile.isPositiveVisited(place) {
            values.append("Visited place you rated well")
        } else if tasteProfile.hasVisitedTasteMatch(place) {
            values.append("Taste match from places you visited")
        }
        if tasteProfile.isFrequentCategory(place.category) {
            values.append("Category matches places you often save")
        }
        if let currentLocation {
            let meters = distanceMeters(from: currentLocation, to: place)
            values.append(isNearby ? "\(distanceLabel(meters)) away" : "\(distanceLabel(meters)) away, outside nearby radius")
        }
        if place.sourceUrl != nil {
            values.append("Has source receipt")
        }
        return values
    }

    private func distanceLabel(_ meters: CLLocationDistance) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func categoryLabel(for intent: SaveSearchIntent) -> String {
        guard let category = intent.requiredCategories.first else { return "places" }
        return category.displayName.lowercased()
    }

    private func localizedCategoryLabel(for intent: SaveSearchIntent) -> String {
        guard let category = intent.requiredCategories.first else { return "地點" }
        switch category {
        case .food: return "餐廳"
        case .cafe: return "咖啡廳"
        case .bar: return "酒吧"
        case .attraction: return "景點"
        case .stay: return "住宿"
        case .shopping: return "購物地點"
        }
    }

    private func rawPlaceId(from resultId: String) -> String? {
        guard resultId.hasPrefix("place-") else { return nil }
        return String(resultId.dropFirst("place-".count))
    }
}

private struct SaveTasteProfile {
    private let preferredTerms: Set<String>
    private let preferredPriceRanges: Set<String>
    private let savedCategoryCounts: [PlaceCategory: Int]

    init(places: [Place]) {
        let positiveVisited = places.filter(Self.isPositiveVisitedPlace)
        preferredTerms = Set(positiveVisited.flatMap(Self.tasteTerms))
        preferredPriceRanges = Set(positiveVisited.compactMap { Self.clean($0.priceRange) })
        savedCategoryCounts = Dictionary(grouping: places, by: \.category)
            .mapValues { $0.count }
    }

    func score(_ place: Place) -> Int {
        var score = 0
        if isPositiveVisited(place) {
            score += 4
        }

        let matchingTerms = matchingPreferredTerms(for: place)
        score += min(matchingTerms.count, 4)

        if preferredPriceRangeMatches(place) {
            score += 1
        }
        if isFrequentCategory(place.category) {
            score += min(savedCategoryCounts[place.category] ?? 0, 3)
        }

        return score
    }

    func isPositiveVisited(_ place: Place) -> Bool {
        Self.isPositiveVisitedPlace(place)
    }

    func isFrequentCategory(_ category: PlaceCategory) -> Bool {
        (savedCategoryCounts[category] ?? 0) >= 3
    }

    func hasVisitedTasteMatch(_ place: Place) -> Bool {
        isPositiveVisited(place) ||
            !matchingPreferredTerms(for: place).isEmpty ||
            preferredPriceRangeMatches(place)
    }

    var mostSavedCategory: PlaceCategory? {
        savedCategoryCounts
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .first?
            .key
    }

    private func matchingPreferredTerms(for place: Place) -> Set<String> {
        Set(Self.tasteTerms(for: place)).intersection(preferredTerms)
    }

    private func preferredPriceRangeMatches(_ place: Place) -> Bool {
        guard let priceRange = place.priceRange?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return preferredPriceRanges.contains(priceRange)
    }

    private static func isPositiveVisitedPlace(_ place: Place) -> Bool {
        guard place.status == .visited else { return false }
        let rating = place.rating ?? place.googleRating
        return rating == nil || rating.map { $0 >= 4.0 } == true
    }

    private static func tasteTerms(for place: Place) -> [String] {
        let text = [
            place.name,
            place.address,
            place.note ?? "",
            place.extractedDishes?.joined(separator: " ") ?? "",
            place.priceRange ?? ""
        ]
        .joined(separator: " ")

        return SaveSearchIntentParser.normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !genericTasteTerms.contains($0) }
    }

    private static let genericTasteTerms: Set<String> = [
        "restaurant", "restaurants", "food", "cafe", "coffee", "place", "places",
        "los", "angeles", "irvine", "california", "taipei", "tokyo"
    ]

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension SaveSearchIntent {
    func withRequiredCategory(_ category: PlaceCategory) -> SaveSearchIntent {
        SaveSearchIntent(
            rawText: rawText,
            normalizedText: normalizedText,
            kind: kind,
            requiredCategories: [category],
            optionalCategories: optionalCategories,
            locationMode: locationMode,
            sourceScope: sourceScope,
            mustMatchCategory: false,
            mustMatchLocation: mustMatchLocation,
            confidence: confidence,
            unsupportedCategoryLabel: unsupportedCategoryLabel,
            categoryNeedles: categoryNeedles
        )
    }
}
