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
        currentLocation: CLLocation?,
        outputLanguage: AppLanguage = .english
    ) -> SaveSearchResponse? {
        guard let intent = parser.parse(query) else {
            return nil
        }
        return recommendationSearchResponse(
            for: query,
            intent: intent,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            currentLocation: currentLocation,
            outputLanguage: outputLanguage
        )
    }

    func recommendationSearchResponse(
        for query: String,
        intent initialIntent: SaveSearchIntent,
        places: [Place],
        reviewCandidates: [PlaceReviewCandidate] = [],
        mapCandidates: [SaveMapCandidate] = [],
        currentLocation: CLLocation?,
        outputLanguage: AppLanguage = .english
    ) -> SaveSearchResponse? {
        guard initialIntent.kind == .categoryRecommendation || initialIntent.kind == .craving || initialIntent.mustMatchLocation else {
            return nil
        }
        var intent = initialIntent
        guard intent.sourceScope != .publicOnly else { return nil }
        let tasteProfile = SaveTasteProfile(places: places)
        if intent.requiredCategories.isEmpty, let frequentCategory = tasteProfile.mostSavedCategory {
            intent = intent.withRequiredCategory(frequentCategory)
        }

        if let unsupportedCategoryLabel = intent.unsupportedCategoryLabel {
            return emptyResponse(
                query: query,
                title: outputLanguage.localized(english: "Unsupported category", traditionalChinese: "尚未支援的類別"),
                message: outputLanguage.localized(
                    english: "SAV-E doesn't have a \(unsupportedCategoryLabel) category yet, so I won't map this to food or cafe by accident. You can search saved names/notes, or ask to search public nearby places.",
                    traditionalChinese: "SAV-E 還沒有「\(unsupportedCategoryLabel)」這個類別，所以我不會誤判成餐廳或咖啡廳。你可以搜尋已保存名稱/筆記，或另外搜尋附近公開地點。"
                ),
                outputLanguage: outputLanguage
            )
        }

        guard !intent.requiredCategories.isEmpty else { return nil }

        if intent.mustMatchLocation, currentLocation == nil {
            return emptyResponse(
                query: query,
                title: outputLanguage.localized(english: "Location needed", traditionalChinese: "需要位置"),
                message: outputLanguage.localized(
                    english: "I need your current location before I can answer nearby requests. Or ask for saved \(categoryLabel(for: intent)) anywhere.",
                    traditionalChinese: "我需要目前位置才能回答附近推薦。你也可以改問不限定附近的已保存\(localizedCategoryLabel(for: intent))。"
                ),
                outputLanguage: outputLanguage
            )
        }

        let categoryMatches = places.filter { place in
            intent.requiredCategories.contains(place.category) &&
                (!intent.requiresSpecificEvidenceMatch || intent.matchesSpecificEvidence(in: specificEvidenceText(for: place)))
        }
        let rankedCategoryMatches = rank(categoryMatches, for: intent, currentLocation: currentLocation, tasteProfile: tasteProfile)
        let categoryReviewCandidates = reviewCandidates.filter { candidate in
            intent.requiredCategories.contains(inferredCategory(for: candidate)) &&
                (!intent.requiresSpecificEvidenceMatch || intent.matchesSpecificEvidence(in: specificEvidenceText(for: candidate)))
        }
        let reviewMatches = rankReviewCandidates(
            categoryReviewCandidates,
            currentLocation: currentLocation
        )
        let mapMatches = rankMapCandidates(
            mapCandidates.filter { candidate in
                intent.requiredCategories.contains(inferredCategory(for: candidate)) &&
                    (!intent.requiresSpecificEvidenceMatch || intent.matchesSpecificEvidence(in: specificEvidenceText(for: candidate)))
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
            let nearbyReviewMatches = rankReviewCandidates(
                categoryReviewCandidates.filter { candidate in
                    guard let distance = distanceMeters(from: currentLocation, to: candidate) else {
                        return false
                    }
                    return distance <= radiusMeters
                },
                currentLocation: currentLocation
            )

            guard !nearby.isEmpty else {
                let farContext = far.isEmpty
                    ? ""
                    : outputLanguage.localized(
                        english: " You do have saved \(categoryLabel(for: intent)) places, but the closest one is outside the nearby radius.",
                        traditionalChinese: " 你有已保存\(localizedCategoryLabel(for: intent))，但最近的也超出目前附近範圍。"
                    )
                return sectionedResponse(
                    query: query,
                    message: outputLanguage.localized(
                        english: "I do not see a saved nearby \(categoryLabel(for: intent)) in your SAV-E. I did not recommend generic cafes or other categories because you asked for \(categoryLabel(for: intent)).\(farContext)",
                        traditionalChinese: "你的 SAV-E 裡附近沒有\(localizedCategoryLabel(for: intent))。你問的是\(localizedCategoryLabel(for: intent))，所以我不會拿泛用咖啡廳或其他類別亂推。\(farContext)"
                    ),
                    nearby: [],
                    far: far,
                    reviewCandidates: nearbyReviewMatches,
                    mapCandidates: mapMatches,
                    intent: intent,
                    currentLocation: currentLocation,
                    tasteProfile: tasteProfile,
                    outputLanguage: outputLanguage,
                    showFallbackAction: true
                )
            }

            return sectionedResponse(
                query: query,
                message: outputLanguage.localized(
                    english: "Found \(nearby.count) saved nearby \(categoryLabel(for: intent)) place\(nearby.count == 1 ? "" : "s") from your SAV-E.",
                    traditionalChinese: "從你的 SAV-E 找到 \(nearby.count) 個附近已保存\(localizedCategoryLabel(for: intent))。"
                ),
                nearby: nearby,
                far: far,
                reviewCandidates: nearbyReviewMatches,
                mapCandidates: mapMatches,
                intent: intent,
                currentLocation: currentLocation,
                tasteProfile: tasteProfile,
                outputLanguage: outputLanguage,
                showFallbackAction: false
            )
        }

        guard !rankedCategoryMatches.isEmpty else {
            if !reviewMatches.isEmpty || !mapMatches.isEmpty {
                return sectionedResponse(
                    query: query,
                    message: outputLanguage.localized(
                        english: "Your SAV-E does not have saved \(categoryLabel(for: intent)) places yet. Review candidates and public discovery stay separate until you choose what to save.",
                        traditionalChinese: "你的 SAV-E 還沒有已保存\(localizedCategoryLabel(for: intent))。待確認地點和公開探索會分開，等你決定要不要保存。"
                    ),
                    nearby: [],
                    far: [],
                    reviewCandidates: reviewMatches,
                    mapCandidates: mapMatches,
                    intent: intent,
                    currentLocation: currentLocation,
                    tasteProfile: tasteProfile,
                    outputLanguage: outputLanguage,
                    showFallbackAction: mapMatches.isEmpty
                )
            }
            return emptyResponse(
                query: query,
                title: outputLanguage.localized(english: "No saved \(categoryLabel(for: intent))", traditionalChinese: "沒有已保存\(localizedCategoryLabel(for: intent))"),
                message: outputLanguage.localized(
                    english: "Your SAV-E does not have saved \(categoryLabel(for: intent)) places yet.",
                    traditionalChinese: "你的 SAV-E 還沒有已保存\(localizedCategoryLabel(for: intent))。"
                ),
                outputLanguage: outputLanguage,
                showFallbackAction: true
            )
        }

        return sectionedResponse(
            query: query,
            message: outputLanguage.localized(
                english: "Showing saved \(categoryLabel(for: intent)) places from your SAV-E.",
                traditionalChinese: "顯示你 SAV-E 裡已保存的\(localizedCategoryLabel(for: intent))。"
            ),
            nearby: rankedCategoryMatches,
            far: [],
            reviewCandidates: reviewMatches,
            mapCandidates: mapMatches,
            intent: intent,
            currentLocation: currentLocation,
            tasteProfile: tasteProfile,
            outputLanguage: outputLanguage,
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
        let outputLanguage = inferredOutputLanguage(for: query)
        guard let response = recommendationSearchResponse(
            for: query,
            places: places,
            reviewCandidates: reviewCandidates,
            mapCandidates: mapCandidates,
            currentLocation: currentLocation,
            outputLanguage: outputLanguage
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

            let lhsTasteScore = tasteProfile.rankingSignals(for: lhs).score
            let rhsTasteScore = tasteProfile.rankingSignals(for: rhs).score
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
            let lhsQuality = mapCandidateQualityScore(lhs)
            let rhsQuality = mapCandidateQualityScore(rhs)
            if lhsQuality != rhsQuality { return lhsQuality > rhsQuality }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private func mapCandidateQualityScore(_ candidate: SaveMapCandidate) -> Int {
        var score = 0
        if let rating = candidate.rating {
            score += Int((rating * 10).rounded())
            if rating >= 4.5 { score += 20 }
            else if rating >= 4.0 { score += 10 }
            else if rating < 3.8 { score -= 30 }
        }
        if let reviewCount = candidate.reviewCount {
            score += min(reviewCount / 25, 20)
        }
        if let distance = candidate.distanceMeters {
            score -= min(Int(distance / 500), 8)
        }
        return score
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

    private func specificEvidenceText(for place: Place) -> String {
        [
            place.name,
            place.note ?? "",
            place.extractedDishes?.joined(separator: " ") ?? "",
            place.recommender ?? ""
        ]
        .joined(separator: " ")
    }

    private func specificEvidenceText(for candidate: PlaceReviewCandidate) -> String {
        ([candidate.name, candidate.address, candidate.city ?? ""] + candidate.evidence)
            .joined(separator: " ")
    }

    private func specificEvidenceText(for candidate: SaveMapCandidate) -> String {
        let evidence = candidate.evidence.filter { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: "search:", options: [.caseInsensitive, .anchored]) == nil
        }
        return ([candidate.title, candidate.subtitle] + evidence)
            .joined(separator: " ")
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
        outputLanguage: AppLanguage,
        showFallbackAction: Bool
    ) -> SaveSearchResponse {
        let mapResults = searchResults(for: mapCandidates)
        let canSearchNearby = showFallbackAction && mapResults.isEmpty
        let nearbyResults = searchResults(for: nearby, intent: intent, currentLocation: currentLocation, isNearby: true, tasteProfile: tasteProfile, outputLanguage: outputLanguage)
        let reviewResults = searchResults(for: reviewCandidates, currentLocation: currentLocation)
        let farResults = searchResults(for: Array(far.prefix(5)), intent: intent, currentLocation: currentLocation, isNearby: false, tasteProfile: tasteProfile, outputLanguage: outputLanguage)
        let nearbySection = SaveSearchSection(
                id: "from-your-save-nearby",
                label: "FROM YOUR SAV-E",
                title: outputLanguage.localized(english: "From your SAV-E nearby", traditionalChinese: "來自 SAV-E 的附近記憶"),
                subtitle: message,
                results: nearbyResults,
                emptyMessage: nearby.isEmpty ? message : nil,
                showsNearbySearchAction: false
        )

        var additional: [SaveSearchSection] = []
        if !reviewResults.isEmpty {
            additional.append(SaveSearchSection(
                id: "review-candidates",
                label: "REVIEW CANDIDATES",
                title: outputLanguage.localized(english: "Waiting in Review Nest", traditionalChinese: "待確認清單裡的可能地點"),
                subtitle: outputLanguage.localized(
                    english: "Possible matches from your Review queue. Confirm one before it becomes a Map Stamp.",
                    traditionalChinese: "這些來自待確認清單；確認後才會變成地圖章。"
                ),
                results: reviewResults,
                emptyMessage: nil
            ))
        }

        if !far.isEmpty {
            additional.append(SaveSearchSection(
                id: "saved-but-not-nearby",
                label: "SAVED, FAR",
                title: outputLanguage.localized(english: "Saved but not nearby", traditionalChinese: "已保存但不在附近"),
                subtitle: outputLanguage.localized(
                    english: "Same category, outside the current nearby radius. Not used as a primary recommendation.",
                    traditionalChinese: "同類別，但超出目前附近範圍；不會當成主要推薦。"
                ),
                results: farResults,
                emptyMessage: nil
            ))
        }

        return SaveSearchResponse(
            query: query,
            assistantMessage: assistantMessage(
                categoryLabel: outputLanguage.localized(
                    english: categoryLabel(for: intent),
                    traditionalChinese: localizedCategoryLabel(for: intent)
                ),
                savedResults: nearbyResults,
                reviewResults: reviewResults,
                unsavedResults: mapResults,
                outputLanguage: outputLanguage,
                fallbackAvailable: canSearchNearby
            ),
            fromYourSave: nearbySection,
            additionalSections: additional,
            newRecommendations: SaveSearchSection(
                id: "nearby-unsaved-candidates",
                label: "PUBLIC DISCOVERY",
                title: outputLanguage.localized(english: "Public nearby options", traditionalChinese: "附近公開探索"),
                subtitle: outputLanguage.localized(
                    english: "Public discovery stays separate until you explicitly save one.",
                    traditionalChinese: "公開探索會分開顯示；只有你手動保存後才會進 SAV-E 記憶。"
                ),
                results: mapResults,
                emptyMessage: canSearchNearby ? outputLanguage.localized(
                    english: "Search public nearby options only if you want places outside your SAV-E memory.",
                    traditionalChinese: "如果想看 SAV-E 記憶以外的附近地點，可以搜尋公開探索。"
                ) : nil,
                showsNearbySearchAction: canSearchNearby
            )
        )
    }

    private func emptyResponse(query: String, title: String, message: String, outputLanguage: AppLanguage, showFallbackAction: Bool = false) -> SaveSearchResponse {
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
                title: outputLanguage.localized(english: "Public nearby options", traditionalChinese: "附近公開探索"),
                subtitle: outputLanguage.localized(
                    english: "Public discovery is explicit fallback only.",
                    traditionalChinese: "公開探索只會作為明確 fallback。"
                ),
                results: [],
                emptyMessage: showFallbackAction ? outputLanguage.localized(
                    english: "Search public nearby options only if you want places outside your SAV-E memory.",
                    traditionalChinese: "如果想看 SAV-E 記憶以外的附近地點，可以搜尋公開探索。"
                ) : nil,
                showsNearbySearchAction: showFallbackAction
            )
        )
    }

    private func searchResults(
        for places: [Place],
        intent: SaveSearchIntent,
        currentLocation: CLLocation?,
        isNearby: Bool,
        tasteProfile: SaveTasteProfile,
        outputLanguage: AppLanguage
    ) -> [SaveSearchResult] {
        places.map { place in
            let reasons = reasons(for: place, intent: intent, currentLocation: currentLocation, isNearby: isNearby, tasteProfile: tasteProfile, outputLanguage: outputLanguage)
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
                primaryAction: SavePlaceActionResolution(place: place).kind
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
                primaryAction: candidate.hasReliableCoordinates ? .confirmMapStamp : .runRecovery,
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
        outputLanguage: AppLanguage,
        fallbackAvailable: Bool
    ) -> String {
        if outputLanguage == .traditionalChinese {
            return assistantMessageTraditionalChinese(
                categoryLabel: categoryLabel,
                savedResults: savedResults,
                reviewResults: reviewResults,
                unsavedResults: unsavedResults,
                fallbackAvailable: fallbackAvailable
            )
        }
        if let top = savedResults.first {
            return agentAnswer(
                lead: "I’d start with \(top.title) because it is already in your SAV-E memory, not a random Google result.",
                reason: reasonLine(for: top, fallback: "It is already a Saved Map Stamp in your place memory.", outputLanguage: outputLanguage),
                caveat: "\(supportingSummary(reviewResults: reviewResults, unsavedResults: [], outputLanguage: outputLanguage))Public discovery stays separate below. If you want, tell me budget, cuisine, or quick vs sit-down and I’ll narrow it."
            )
        }

        if let top = reviewResults.first {
            return agentAnswer(
                lead: "I would not promote an unconfirmed place as a saved recommendation; start by reviewing \(top.title).",
                reason: reasonLine(for: top, fallback: "It is waiting in Review, so SAV-E has a clue but still needs confirmation.", outputLanguage: outputLanguage),
                caveat: "Confirm it into a Map Stamp, or add a clue before trusting it as the recommendation."
            )
        }

        if !unsavedResults.isEmpty {
            let top = unsavedResults[0]
            let topReason = reasonLine(
                for: top,
                fallback: "it has the strongest public quality signals in this result set",
                outputLanguage: outputLanguage
            )
            return agentAnswer(
                lead: "I do not see a saved nearby \(categoryLabel) in your SAV-E yet.",
                reason: "I found \(unsavedResults.count) public nearby option\(unsavedResults.count == 1 ? "" : "s") below; the first one to inspect is \(top.title) because \(topReason)",
                caveat: "Pick one to save if it looks right, or tell me budget, vibe, or quick vs sit-down and I’ll narrow the list."
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
        "\(lead) \(reason). \(caveat)"
    }

    private func assistantMessageTraditionalChinese(
        categoryLabel: String,
        savedResults: [SaveSearchResult],
        reviewResults: [SaveSearchResult],
        unsavedResults: [SaveSearchResult],
        fallbackAvailable: Bool
    ) -> String {
        if let top = savedResults.first {
            return agentAnswer(
                lead: "我會先推 \(top.title)，因為它已經在你的 SAV-E 記憶裡，不是隨機 Google 結果。",
                reason: reasonLine(for: top, fallback: "它已經是 SAV-E 裡的地圖章", outputLanguage: .traditionalChinese),
                caveat: "\(supportingSummary(reviewResults: reviewResults, unsavedResults: [], outputLanguage: .traditionalChinese))公開探索會分開列在下面。你可以再補預算、想坐一下或外帶，我再幫你縮小。"
            )
        }

        if let top = reviewResults.first {
            return agentAnswer(
                lead: "我不會直接亂推未確認地點；可以先看 \(top.title)。",
                reason: reasonLine(for: top, fallback: "它還在待確認清單裡，需要確認後才會變成地圖章", outputLanguage: .traditionalChinese),
                caveat: "先確認成地圖章，或再補一個線索後再信任它。"
            )
        }

        if !unsavedResults.isEmpty {
            let top = unsavedResults[0]
            let topReason = reasonLine(
                for: top,
                fallback: "它在這批公開結果裡的公開品質訊號最強",
                outputLanguage: .traditionalChinese
            )
            return agentAnswer(
                lead: "你的 SAV-E 記憶裡還沒有附近已保存\(categoryLabel)。",
                reason: "下面找到 \(unsavedResults.count) 個附近公開選項；如果要先看一家，我會先看 \(top.title)，原因是 \(topReason)",
                caveat: "你可以挑一個保存，或補預算、氛圍、想外帶還是坐一下，我再幫你縮小清單。"
            )
        }

        var parts: [String] = []
        if !savedResults.isEmpty {
            parts.append("\(savedResults.count) 個已保存地圖章")
        }
        if !reviewResults.isEmpty {
            parts.append("\(reviewResults.count) 個待確認地點")
        }
        if !unsavedResults.isEmpty {
            parts.append("\(unsavedResults.count) 個附近公開選項")
        }
        if parts.isEmpty {
            return fallbackAvailable
                ? "我目前沒有看到附近已保存\(categoryLabel)。可以接著搜尋公開探索；這些地點會維持未保存，直到你選擇保存。"
                : "我目前沒有看到附近已保存\(categoryLabel)。"
        }
        return "我目前沒有找到附近已保存\(categoryLabel)。我找到 \(parts.joined(separator: "、"))；待確認地點和公開探索會分開，讓你自己決定要不要保存。"
    }

    private func supportingSummary(reviewResults: [SaveSearchResult], unsavedResults: [SaveSearchResult], outputLanguage: AppLanguage) -> String {
        var parts: [String] = []
        if !reviewResults.isEmpty {
            parts.append(outputLanguage.localized(
                english: "\(reviewResults.count) Review candidate\(reviewResults.count == 1 ? "" : "s")",
                traditionalChinese: "\(reviewResults.count) 個待確認地點"
            ))
        }
        if !unsavedResults.isEmpty {
            parts.append(outputLanguage.localized(
                english: "\(unsavedResults.count) unsaved nearby option\(unsavedResults.count == 1 ? "" : "s")",
                traditionalChinese: "\(unsavedResults.count) 個附近公開選項"
            ))
        }
        return parts.isEmpty ? "" : outputLanguage.localized(
            english: "I also found \(parts.joined(separator: ", ")); they stay separate. ",
            traditionalChinese: "我也找到 \(parts.joined(separator: "、"))；它們會分開顯示。"
        )
    }

    private func reasonLine(for result: SaveSearchResult, fallback: String, outputLanguage: AppLanguage) -> String {
        var reasons: [String] = []
        switch result.objectType {
        case .savedPlace, .triedMemory:
            reasons.append(outputLanguage.localized(english: "Saved Map Stamp", traditionalChinese: "已保存地圖章"))
        case .pendingCandidate, .sourceOnlyClue:
            reasons.append(outputLanguage.localized(english: "Review Candidate", traditionalChinese: "待確認地點"))
        case .mapVisibleUnsavedPlace, .newRecommendation:
            reasons.append(outputLanguage.localized(english: "unsaved public result", traditionalChinese: "未保存公開結果"))
        case .review:
            reasons.append(outputLanguage.localized(english: "private review", traditionalChinese: "私人評價"))
        case .tripStop:
            reasons.append(outputLanguage.localized(english: "trip stop", traditionalChinese: "行程站點"))
        }
        if let distanceLabel = result.distanceLabel {
            reasons.append(distanceLabel)
        }
        if let rating = result.rating {
            reasons.append(outputLanguage.localized(
                english: String(format: "%.1f rating", rating),
                traditionalChinese: String(format: "評分 %.1f", rating)
            ))
        }
        if let reviewCount = result.reviewCount {
            reasons.append(outputLanguage.localized(english: "\(reviewCount) reviews", traditionalChinese: "\(reviewCount) 則評論"))
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

    private func reasons(for place: Place, intent: SaveSearchIntent, currentLocation: CLLocation?, isNearby: Bool, tasteProfile: SaveTasteProfile, outputLanguage: AppLanguage) -> [String] {
        var values = [outputLanguage.localized(
            english: "\(place.category.displayName) Map Stamp",
            traditionalChinese: "\(categoryDisplayName(place.category, outputLanguage: outputLanguage))地圖章"
        )]
        let signals = tasteProfile.rankingSignals(for: place)
        if !intent.categoryNeedles.isEmpty, evidenceScore(place, needles: intent.categoryNeedles) > 0 {
            values.append(outputLanguage.localized(
                english: "Saved evidence matches \(intent.categoryNeedles.prefix(2).joined(separator: " / "))",
                traditionalChinese: "已保存線索符合 \(intent.categoryNeedles.prefix(2).joined(separator: " / "))"
            ))
        }
        if signals.isPositiveVisited {
            values.append(outputLanguage.localized(english: "Visited place you rated well", traditionalChinese: "你去過且評價不錯"))
        } else if signals.hasVisitedTasteMatch {
            values.append(outputLanguage.localized(english: "Taste match from places you visited", traditionalChinese: "符合你去過地點的偏好"))
        }
        if let highRating = signals.highRating {
            values.append(outputLanguage.localized(
                english: String(format: "High rating %.1f", highRating),
                traditionalChinese: String(format: "高評分 %.1f", highRating)
            ))
        }
        if !signals.matchingPreferredTerms.isEmpty {
            values.append(outputLanguage.localized(
                english: "Taste tags match \(signals.matchingPreferredTerms.prefix(2).joined(separator: " / "))",
                traditionalChinese: "偏好標籤符合 \(signals.matchingPreferredTerms.prefix(2).joined(separator: " / "))"
            ))
        }
        if let priceRange = signals.preferredPriceRange {
            values.append(outputLanguage.localized(
                english: "Price matches places you liked (\(priceRange))",
                traditionalChinese: "價位符合你喜歡的地點（\(priceRange)）"
            ))
        }
        if signals.frequentCategoryCount >= SaveTasteProfile.frequentCategoryThreshold {
            values.append(outputLanguage.localized(english: "Category matches places you often save", traditionalChinese: "符合你常保存的類別"))
        }
        if let currentLocation {
            let meters = distanceMeters(from: currentLocation, to: place)
            values.append(outputLanguage.localized(
                english: isNearby ? "\(distanceLabel(meters)) away" : "\(distanceLabel(meters)) away, outside nearby radius",
                traditionalChinese: isNearby ? "距離 \(distanceLabel(meters))" : "距離 \(distanceLabel(meters))，超出附近範圍"
            ))
        }
        if place.sourceUrl != nil {
            values.append(outputLanguage.localized(english: "Has source receipt", traditionalChinese: "有來源憑證"))
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
        intent.recommendationLabel
    }

    private func localizedCategoryLabel(for intent: SaveSearchIntent) -> String {
        intent.localizedRecommendationLabel
    }

    private func categoryDisplayName(_ category: PlaceCategory, outputLanguage: AppLanguage) -> String {
        category.displayName(language: outputLanguage)
    }

    private func inferredOutputLanguage(for query: String) -> AppLanguage {
        query.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        } ? .traditionalChinese : .english
    }

    private func rawPlaceId(from resultId: String) -> String? {
        guard resultId.hasPrefix("place-") else { return nil }
        return String(resultId.dropFirst("place-".count))
    }
}

private struct SaveTasteProfile {
    static let frequentCategoryThreshold = 3

    private let preferredTerms: Set<String>
    private let preferredPriceRanges: Set<String>
    private let savedCategoryCounts: [PlaceCategory: Int]

    init(places: [Place]) {
        let positiveVisited = places.filter(Self.isPositiveVisitedPlace)
        preferredTerms = Set(positiveVisited.flatMap(Self.tagLikeTasteTerms))
        preferredPriceRanges = Set(positiveVisited.compactMap { Self.clean($0.priceRange) })
        savedCategoryCounts = Dictionary(grouping: places, by: \.category)
            .mapValues { $0.count }
    }

    func rankingSignals(for place: Place) -> SaveTasteRankingSignals {
        let priceRange = Self.clean(place.priceRange)
        return SaveTasteRankingSignals(
            isPositiveVisited: Self.isPositiveVisitedPlace(place),
            highRating: Self.highRating(for: place),
            matchingPreferredTerms: matchingPreferredTerms(for: place).sorted(),
            preferredPriceRange: priceRange.flatMap { preferredPriceRanges.contains($0) ? $0 : nil },
            frequentCategoryCount: savedCategoryCounts[place.category] ?? 0
        )
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
        Set(Self.tagLikeTasteTerms(for: place)).intersection(preferredTerms)
    }

    private static func isPositiveVisitedPlace(_ place: Place) -> Bool {
        guard place.status == .visited else { return false }
        let rating = place.rating ?? place.googleRating
        return rating == nil || rating.map { $0 >= 4.0 } == true
    }

    private static func highRating(for place: Place) -> Double? {
        guard let rating = place.rating ?? place.googleRating, rating >= 4.0 else {
            return nil
        }
        return rating
    }

    private static func tagLikeTasteTerms(for place: Place) -> [String] {
        let text = [
            place.note ?? "",
            place.extractedDishes?.joined(separator: " ") ?? "",
            place.recommender ?? ""
        ]
        .joined(separator: " ")

        return SaveSearchIntentParser.normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !genericTasteTerms.contains($0) }
    }

    private static let genericTasteTerms: Set<String> = [
        "restaurant", "restaurants", "food", "cafe", "coffee", "place", "places",
        "saved", "memory", "liked", "loved", "recommend", "recommended",
        "los", "angeles", "irvine", "california", "taipei", "tokyo"
    ]

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct SaveTasteRankingSignals {
    let isPositiveVisited: Bool
    let highRating: Double?
    let matchingPreferredTerms: [String]
    let preferredPriceRange: String?
    let frequentCategoryCount: Int

    var hasVisitedTasteMatch: Bool {
        isPositiveVisited || !matchingPreferredTerms.isEmpty || preferredPriceRange != nil
    }

    var score: Int {
        var value = 0
        if isPositiveVisited {
            value += 6
        }
        if let highRating {
            value += ratingScore(highRating)
        }
        value += min(matchingPreferredTerms.count, 4) * 2
        if preferredPriceRange != nil {
            value += 2
        }
        if frequentCategoryCount >= SaveTasteProfile.frequentCategoryThreshold {
            value += min(frequentCategoryCount, 3)
        }
        return value
    }

    private func ratingScore(_ rating: Double) -> Int {
        if rating >= 4.8 { return 4 }
        if rating >= 4.5 { return 3 }
        return 2
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
