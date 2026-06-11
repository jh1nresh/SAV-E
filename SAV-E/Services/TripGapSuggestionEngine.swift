import Foundation

struct TripDestinationScope {
    let destination: String
    private let normalizedDestination: String

    init?(query: String? = nil, places: [Place]) {
        let destination = query.flatMap(Self.destinationHint(from:)) ?? Self.destinationHint(from: places)
        guard let destination else { return nil }
        self.destination = destination
        self.normalizedDestination = Self.normalize(destination)
    }

    func contains(place: Place) -> Bool {
        matches(text: "\(place.name) \(place.address) \(place.category.rawValue)")
    }

    func contains(reviewCandidate: PlaceReviewCandidate) -> Bool {
        let text = ([reviewCandidate.name, reviewCandidate.address, reviewCandidate.city].compactMap { $0 } + reviewCandidate.evidence)
            .joined(separator: " ")
        return matches(text: text)
    }

    func contains(mapCandidate: SaveMapCandidate) -> Bool {
        matches(text: "\(mapCandidate.title) \(mapCandidate.subtitle)")
    }

    static func destinationHint(from query: String) -> String? {
        let normalized = normalize(query)
        let padded = " \(normalized) "
        return knownDestinations.first { item in
            item.needles.contains { needle in
                let normalizedNeedle = normalize(needle)
                return padded.contains(" \(normalizedNeedle) ") || normalized.contains(normalizedNeedle)
            }
        }?.destination
    }

    static func destinationHint(from places: [Place]) -> String? {
        let joinedAddresses = places.map(\.address).joined(separator: " ")
        return destinationHint(from: joinedAddresses)
    }

    private func matches(text: String) -> Bool {
        let normalized = Self.normalize(text)
        if normalized.contains(normalizedDestination) {
            return true
        }
        return Self.knownDestinations
            .first { $0.destination == destination }?
            .needles
            .map(Self.normalize)
            .contains { normalized.contains($0) } == true
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static let knownDestinations: [(destination: String, needles: [String])] = [
        ("台北", ["台北", "臺北", "taipei"]),
        ("台南", ["台南", "臺南", "tainan"]),
        ("高雄", ["高雄", "kaohsiung"]),
        ("東京", ["東京", "tokyo"]),
        ("首爾", ["首爾", "seoul"]),
        ("Los Angeles", ["los angeles", " la ", "hollywood", "santa monica", "malibu", "beverly hills", "playa vista"]),
        ("Anaheim", ["anaheim", "disneyland"]),
        ("Orange County", ["orange county", "costa mesa", "newport beach", "westminster"]),
        ("Irvine", ["irvine"])
    ]
}

struct TripGapSuggestionEngine {
    func suggestions(
        for gaps: [TripGap],
        days: [ItineraryDay],
        savedPlaces: [Place],
        reviewCandidates: [PlaceReviewCandidate],
        mapCandidates: [SaveMapCandidate],
        outputLanguage: AppLanguage
    ) -> [GapSuggestion] {
        let usedPlaceIDs = Set(days.flatMap(\.stops).compactMap(\.placeId))
        let anchorPlaces = savedPlaces.filter { usedPlaceIDs.contains($0.id.uuidString) }
        let destinationScope = TripDestinationScope(places: anchorPlaces)

        return gaps.compactMap { gap -> GapSuggestion? in
            let categories = preferredCategories(for: gap.type)
            let savedOptions = savedPlaces
                .filter { categories.contains($0.category) && !usedPlaceIDs.contains($0.id.uuidString) }
                .filter { destinationScope?.contains(place: $0) ?? true }
                .prefix(3)
                .map { place in
                    GapSuggestionOption(
                        id: "saved-\(place.id.uuidString)-\(gap.id)",
                        title: place.name,
                        subtitle: nonEmpty(place.address),
                        source: .confirmedSaved,
                        placeId: place.id.uuidString,
                        reviewCandidateId: nil,
                        mapCandidateId: nil,
                        reason: localized(
                            english: "Confirmed saved Map Stamp fits this gap.",
                            traditionalChinese: "已確認地圖章，適合補這個缺口。",
                            language: outputLanguage
                        ),
                        confidence: place.latitude != 0 || place.longitude != 0 ? .high : .medium,
                        action: .addToPlan
                    )
                }

            let reviewOptions = reviewCandidates
                .filter { candidate in
                    categories.contains(PlaceCategory.inferred(from: ([candidate.name, candidate.address] + candidate.evidence).joined(separator: " ")))
                }
                .filter { destinationScope?.contains(reviewCandidate: $0) ?? true }
                .prefix(3)
                .map { candidate in
                    let hasCoordinates = candidate.hasReliableCoordinates
                    return GapSuggestionOption(
                        id: "review-\(candidate.id.uuidString)-\(gap.id)",
                        title: candidate.name,
                        subtitle: nonEmpty(candidate.address),
                        source: hasCoordinates ? .reviewCandidate : .sourceClue,
                        placeId: nil,
                        reviewCandidateId: candidate.id.uuidString,
                        mapCandidateId: nil,
                        reason: hasCoordinates
                            ? localized(
                                english: "Review Candidate has map evidence but still needs confirmation.",
                                traditionalChinese: "待確認候選已有地圖證據，但仍要你確認。",
                                language: outputLanguage
                            )
                            : localized(
                                english: "Source clue needs recovery before it can become a stop.",
                                traditionalChinese: "來源線索要先查證，不能直接變成行程點。",
                                language: outputLanguage
                            ),
                        confidence: hasCoordinates ? .medium : .low,
                        action: hasCoordinates ? .reviewThenAdd : .resolveThenAdd
                    )
                }

            let externalOptions = mapCandidates
                .filter { candidate in
                    guard let category = candidate.category else { return true }
                    return categories.contains(category)
                }
                .filter { destinationScope?.contains(mapCandidate: $0) ?? true }
                .prefix(3)
                .map { candidate in
                    GapSuggestionOption(
                        id: "external-\(candidate.id)-\(gap.id)",
                        title: candidate.title,
                        subtitle: nonEmpty(candidate.subtitle),
                        source: .externalSuggestion,
                        placeId: nil,
                        reviewCandidateId: nil,
                        mapCandidateId: candidate.id,
                        reason: localized(
                            english: "Public map candidate; approve before adding, and it will not be saved automatically.",
                            traditionalChinese: "公開地圖候選；加入前要先批准，而且不會自動存進記憶。",
                            language: outputLanguage
                        ),
                        confidence: candidate.latitude != 0 || candidate.longitude != 0 ? .medium : .low,
                        action: .addExternalWithApproval
                    )
                }

            let options: [GapSuggestionOption] = Array(savedOptions) + Array(reviewOptions) + Array(externalOptions)
            guard !options.isEmpty else { return nil }
            return GapSuggestion(
                id: "gap-suggestion-\(gap.id)",
                gapId: gap.id,
                dayId: gap.dayId,
                message: gap.message,
                options: options,
                requiresUserApproval: options.contains { $0.source == .externalSuggestion || $0.source == .reviewCandidate || $0.source == .sourceClue }
            )
        }
    }

    private func preferredCategories(for type: TripGap.GapType) -> Set<PlaceCategory> {
        switch type {
        case .missingBreakfast:
            return [.food, .cafe]
        case .missingLunch:
            return [.food]
        case .missingDinner:
            return [.food, .bar]
        case .missingCoffeeBreak:
            return [.cafe]
        case .missingAfternoonActivity:
            return [.attraction, .shopping, .cafe]
        case .missingEveningPlan:
            return [.bar, .food, .attraction]
        case .needsAreaCluster:
            return Set(PlaceCategory.allCases)
        case .needsRainBackup:
            return [.attraction, .shopping, .cafe]
        case .needsHoursCheck:
            return Set(PlaceCategory.allCases)
        }
    }

    private func localized(english: String, traditionalChinese: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return english
        case .traditionalChinese:
            return traditionalChinese
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
