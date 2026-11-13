#if SAVVY_CITY_MVP
import Foundation

/// Literal local retrieval of unsigned recommendations, never a ranking or fact check.
@MainActor
enum CityMVPRecommendationSearch {
    nonisolated struct Match: Equatable, Sendable, Identifiable {
        let placeID: UUID
        let matchingRecordIDs: [String]
        /// Sources needed to satisfy the query beyond venue fields. Empty for venue-only/browse matches.
        let sourceMatchedRecordIDs: [String]
        var id: UUID { placeID }
    }

    private struct Venue: Equatable {
        let id: UUID
        let savedIDs: Set<UUID>
        let fields: [String]
    }

    static func matches(_ query: String, places: [Place],
                        records: [CityMVPRecommendationStore.Record]) -> [Match] {
        guard query.count <= 240 else { return [] }
        let browsing = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tokens = CityMVPAgentSearch.terms(query)
        guard browsing || !tokens.isEmpty else { return [] }

        // Index source identity first. Identical copies are harmless; contradictory
        // copies cannot decide attribution based on whichever happened to arrive last.
        var unique: [String: CityMVPRecommendationStore.Record] = [:]
        var conflictingSources = Set<String>()
        for record in records {
            if let existing = unique[record.id], existing != record { conflictingSources.insert(record.id) }
            else { unique[record.id] = record }
        }
        var bySavedID: [UUID: [CityMVPRecommendationStore.Record]] = [:]
        for (id, record) in unique where !conflictingSources.contains(id) {
            bySavedID[record.savedPlaceID, default: []].append(record)
        }

        var venues: [UUID: Venue] = [:]
        var conflictingPlaces = Set<UUID>()
        for place in places {
            let venue = Venue(id: place.id, savedIDs: place.savedIDs,
                fields: [place.name, place.address, place.category.rawValue, place.category.displayName])
            if let existing = venues[place.id], existing != venue { conflictingPlaces.insert(place.id) }
            else { venues[place.id] = venue }
        }

        var results: [Match] = []
        for (id, venue) in venues where !conflictingPlaces.contains(id) {
            let sources = venue.savedIDs.flatMap { bySavedID[$0] ?? [] }.sorted { $0.id < $1.id }
            guard !sources.isEmpty else { continue }
            let venueMatches = browsing || contains(tokens, in: venue.fields)
            let matchedIDs: [String]
            if venueMatches { matchedIDs = sources.map(\.id) }
            else {
                matchedIDs = sources.filter {
                    contains(tokens, in: venue.fields + [$0.senderLabel, $0.reason])
                }.map(\.id)
            }
            guard !matchedIDs.isEmpty else { continue }
            results.append(Match(placeID: id, matchingRecordIDs: matchedIDs,
                sourceMatchedRecordIDs: venueMatches ? [] : matchedIDs))
        }
        // Identity order is stable and deliberately conveys no quality or freshness rank.
        return results.sorted { $0.placeID.uuidString < $1.placeID.uuidString }
    }

    private static func contains(_ tokens: [String], in fields: [String]) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let locale = Locale(identifier: "en_US_POSIX")
        return tokens.allSatisfy { token in
            fields.contains { $0.range(of: token, options: options, locale: locale) != nil }
        }
    }
}
#endif
