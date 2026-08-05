import Foundation

/// A one-tap planning suggestion built entirely from places the user already
/// confirmed.
struct SavedPlaceTripRecommendation: Identifiable, Equatable {
    /// The area label the stamps cluster around ("Los Angeles", "大安區").
    let area: String
    let stampCount: Int
    /// Days the cluster can realistically fill, capped so a huge vault does not
    /// propose a week the user never asked for.
    let suggestedDays: Int
    /// Sample place names, for showing what the plan would be built from.
    let sampleNames: [String]

    var id: String { area }

    /// The query handed to `DeterministicTripPlanner`. Phrased the way the
    /// planner parses best: an explicit day count plus the area as the anchor.
    var planningQuery: String {
        suggestedDays == 1
            ? "Plan a day in \(area)"
            : "Plan \(suggestedDays) days in \(area)"
    }

    func title(language: AppLanguage) -> String {
        language.localized(
            english: suggestedDays == 1 ? "A day in \(area)" : "\(suggestedDays) days in \(area)",
            traditionalChinese: suggestedDays == 1 ? "在\(area)玩一天" : "在\(area)玩 \(suggestedDays) 天"
        )
    }

    func subtitle(language: AppLanguage) -> String {
        language.localized(
            english: "\(stampCount) Map Stamps ready",
            traditionalChinese: "\(stampCount) 個地圖章可用"
        )
    }
}

/// Turns confirmed Map Stamps into planning suggestions.
///
/// Trips previously waited for the user to think of a query. Everything needed
/// to propose one is already in the vault: places cluster by area, and an area
/// with enough confirmed stamps is a trip waiting to be arranged. This only
/// reads saved places — no external provider, no network.
struct SavedPlaceTripRecommender {
    /// Below this an "area" is one lunch, not a day worth planning.
    static let minimumStampsPerArea = 3
    static let maximumRecommendations = 3
    /// Roughly a comfortable day of stops; used to size multi-day suggestions.
    static let stampsPerDay = 4
    static let maximumSuggestedDays = 3

    func recommendations(
        from places: [Place],
        excludingAreasFrom trips: [Trip] = []
    ) -> [SavedPlaceTripRecommendation] {
        let plannable = places.filter(isPlannable)
        guard !plannable.isEmpty else { return [] }

        let plannedAreas = Set(
            trips
                .map { normalizedArea($0.city) }
                .filter { !$0.isEmpty }
        )

        var byArea: [String: [Place]] = [:]
        for place in plannable {
            guard let area = Self.areaLabel(for: place) else { continue }
            byArea[area, default: []].append(place)
        }

        return byArea
            .filter { $0.value.count >= Self.minimumStampsPerArea }
            // An area the user already has a trip for is not a recommendation.
            .filter { !plannedAreas.contains(normalizedArea($0.key)) }
            .map { area, places in
                SavedPlaceTripRecommendation(
                    area: area,
                    stampCount: places.count,
                    suggestedDays: min(
                        Self.maximumSuggestedDays,
                        max(1, places.count / Self.stampsPerDay)
                    ),
                    sampleNames: places
                        .sorted { $0.createdAt > $1.createdAt }
                        .prefix(3)
                        .map(\.name)
                )
            }
            .sorted { lhs, rhs in
                if lhs.stampCount != rhs.stampCount { return lhs.stampCount > rhs.stampCount }
                return lhs.area < rhs.area
            }
            .prefix(Self.maximumRecommendations)
            .map { $0 }
    }

    /// A city-level label people would actually say out loud.
    ///
    /// `shareAreaLabel` takes the second-to-last comma component, which is the
    /// city in US-style addresses but garbage in CJK ones: a Taipei address
    /// yields "110台灣臺北市信義區西村里…" — postal code, country, city,
    /// district and village in one run. Those also never cluster, because two
    /// restaurants on the same street produce different village suffixes.
    static func areaLabel(for place: Place) -> String? {
        let raw = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let cjkCity = cjkCityLabel(in: raw) { return cjkCity }
        // Drop a leading postal code ("90036 Los Angeles").
        let withoutPostcode = raw.drop { $0.isNumber || $0 == " " }
        let cleaned = String(withoutPostcode).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? raw : cleaned
    }

    /// Extracts the 市/縣 (city) segment from a CJK address, ignoring the
    /// district and anything after it so stamps in one city cluster together.
    private static func cjkCityLabel(in value: String) -> String? {
        guard value.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }) else {
            return nil
        }
        for marker in ["市", "縣", "县"] {
            guard let end = value.range(of: marker) else { continue }
            let head = value[value.startIndex..<end.upperBound]
            // Trim the leading postal code / country prefix.
            let trimmed = head.drop { $0.isNumber }
            let city = String(trimmed)
                .replacingOccurrences(of: "台灣", with: "")
                .replacingOccurrences(of: "臺灣", with: "")
                .replacingOccurrences(of: "中國", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if city.count >= 2 { return city }
        }
        return nil
    }

    private func isPlannable(_ place: Place) -> Bool {
        guard place.latitude != 0 || place.longitude != 0 else { return false }
        return !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedArea(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
