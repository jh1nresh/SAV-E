import CoreLocation
import Foundation
import MapKit

/// Fetches public map candidates to offer against a trip's open slots.
///
/// A plan built only from saved places is capped by what the user already knew
/// about — a first visit to a city yields a thin day. `TripGapSuggestionEngine`
/// has always accepted `mapCandidates` and renders them as
/// `.externalSuggestion`: visually distinct, gated behind an explicit Approve,
/// and never written to the vault. That pipe was wired to an empty array, so
/// the capability existed with nothing feeding it.
///
/// This fills it, and nothing more: Savvy still decides nothing on the user's
/// behalf. A candidate becomes a stop only when the user approves it, and
/// becomes a Map Stamp only through the normal Review flow.
@MainActor
struct TripGapLocalOptionsService {
    /// Search radius around the day's anchors. Wide enough to find a
    /// neighbourhood's options, tight enough that nothing across town appears.
    static let searchSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    /// Above this the suggestion list stops being a choice and becomes a feed.
    static let maximumCandidates = 12

    private let searchService: MapCandidateSearchServiceProtocol

    init(searchService: MapCandidateSearchServiceProtocol = MapCandidateSearchService()) {
        self.searchService = searchService
    }

    /// Candidates near the plan's own stops, restricted to the categories the
    /// open gaps actually call for.
    ///
    /// Returns `[]` when the plan has no located stop to anchor on: proposing
    /// places near nothing would be guessing at the destination, which is the
    /// failure the "Need trip anchors" path already refuses.
    func candidates(
        forGaps gaps: [TripGap],
        days: [ItineraryDay],
        savedPlaces: [Place]
    ) async -> [SaveMapCandidate] {
        let categories = Self.categories(for: gaps)
        guard !categories.isEmpty else { return [] }
        guard let anchor = Self.anchorCoordinate(days: days, savedPlaces: savedPlaces) else { return [] }

        let candidates = await searchService.searchCandidates(
            near: anchor,
            span: Self.searchSpan,
            excluding: savedPlaces,
            categories: categories
        )
        return Self.diversify(candidates, requestedCategories: categories)
    }

    /// Turns a raw proximity list into a set of options worth choosing between.
    ///
    /// Nearby search returns by distance, and dense categories drown the rest:
    /// an "afternoon activity" gap wanting attraction/shopping/cafe came back
    /// as three cafés, two of them branches of the same chain. Neither is a
    /// choice — it is the same suggestion three times.
    static func diversify(
        _ candidates: [SaveMapCandidate],
        requestedCategories: Set<PlaceCategory>
    ) -> [SaveMapCandidate] {
        // Shortest name first, so "Starbucks" claims the brand before
        // "STARBUCKS Beining Shop" can register as a separate business.
        var seenBrands: [String] = []
        let deduped = candidates
            .enumerated()
            .sorted { lhs, rhs in
                let lhsKey = brandKey(for: lhs.element.title)
                let rhsKey = brandKey(for: rhs.element.title)
                if lhsKey.count != rhsKey.count { return lhsKey.count < rhsKey.count }
                return lhs.offset < rhs.offset
            }
            .filter { _, candidate in
                let key = brandKey(for: candidate.title)
                // A branch name extends its chain's name, so prefix matching
                // catches the Latin form the "店" rule cannot.
                guard !seenBrands.contains(where: { Self.isSameChain($0, key) }) else {
                    return false
                }
                seenBrands.append(key)
                return true
            }
            .sorted { $0.offset < $1.offset }
            .map(\.element)

        // Round-robin across the categories actually asked for, so a dense
        // category cannot take every slot.
        var byCategory: [PlaceCategory: [SaveMapCandidate]] = [:]
        var uncategorized: [SaveMapCandidate] = []
        for candidate in deduped {
            if let category = candidate.category, requestedCategories.contains(category) {
                byCategory[category, default: []].append(candidate)
            } else {
                uncategorized.append(candidate)
            }
        }

        var result: [SaveMapCandidate] = []
        // Stable order so the same plan does not reshuffle between renders.
        let orderedCategories = byCategory.keys.sorted { $0.rawValue < $1.rawValue }
        var round = 0
        while result.count < maximumCandidates {
            var addedThisRound = false
            for category in orderedCategories {
                guard let bucket = byCategory[category], round < bucket.count else { continue }
                result.append(bucket[round])
                addedThisRound = true
                if result.count >= maximumCandidates { break }
            }
            if !addedThisRound { break }
            round += 1
        }

        if result.count < maximumCandidates {
            result += uncategorized.prefix(maximumCandidates - result.count)
        }
        return result
    }

    /// Whether one brand key is the other plus a branch qualifier.
    ///
    /// The extension has to start at a word boundary. Raw prefix matching
    /// collapsed "Spot 1" and "Spot 10" into one business — numbering is not
    /// branching.
    static func isSameChain(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard longer.hasPrefix(shorter) else { return false }
        let remainder = longer.dropFirst(shorter.count)
        return remainder.first == " "
    }

    /// Collapses branches of one business to a single option. Taiwanese and
    /// Japanese branch suffixes (…光復店, …微風復興店, …本店) sit at the end of
    /// the name, so trimming them groups the chain.
    static func brandKey(for title: String) -> String {
        var name = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a parenthetical branch: "Blue Bottle (Shibuya)".
        if let open = name.firstIndex(of: "(") {
            name = String(name[name.startIndex..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Drop a CJK branch suffix: everything from the last 店/分店 marker.
        if let branch = name.range(of: "店", options: .backwards),
           name.distance(from: name.startIndex, to: branch.lowerBound) >= 2 {
            let head = String(name[name.startIndex..<branch.lowerBound])
            // Only treat it as a branch when something recognisable remains.
            if head.count >= 2 { name = head }
        }
        // Drop a trailing Latin branch word: "… Roasters Guangfu".
        return name
            .split(separator: " ")
            .prefix(3)
            .joined(separator: " ")
    }

    /// Categories worth searching for, union of what each open gap needs.
    /// Mirrors `TripGapSuggestionEngine.preferredCategories` — searching for
    /// categories the engine will then filter out just wastes a round trip.
    static func categories(for gaps: [TripGap]) -> Set<PlaceCategory> {
        gaps.reduce(into: Set<PlaceCategory>()) { result, gap in
            switch gap.type {
            case .missingBreakfast:
                result.formUnion([.food, .cafe])
            case .missingLunch:
                result.insert(.food)
            case .missingDinner:
                result.formUnion([.food, .bar])
            case .missingCoffeeBreak:
                result.insert(.cafe)
            case .missingAfternoonActivity:
                result.formUnion([.attraction, .shopping, .cafe])
            case .missingEveningPlan:
                result.formUnion([.bar, .food, .attraction])
            case .needsAreaCluster:
                result.formUnion(PlaceCategory.allCases)
            case .needsRainBackup:
                result.formUnion([.attraction, .shopping, .cafe])
            case .needsHoursCheck:
                // Not a missing-place gap: the stops exist, their hours are
                // unverified. Offering more places would answer a question the
                // user did not ask.
                break
            }
        }
    }

    /// The plan's centre of gravity: the stops the user already committed to.
    /// Falls back to nothing rather than to the user's current location — a
    /// trip being planned for Tokyo should not pull suggestions from Taipei
    /// because that is where the phone happens to be.
    static func anchorCoordinate(
        days: [ItineraryDay],
        savedPlaces: [Place]
    ) -> CLLocationCoordinate2D? {
        let placesByID = Dictionary(
            savedPlaces.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let located = days
            .flatMap(\.stops)
            .compactMap { $0.placeId.flatMap { placesByID[$0] } }
            .filter { $0.latitude != 0 || $0.longitude != 0 }

        guard !located.isEmpty else { return nil }
        let latitude = located.map(\.latitude).reduce(0, +) / Double(located.count)
        let longitude = located.map(\.longitude).reduce(0, +) / Double(located.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
