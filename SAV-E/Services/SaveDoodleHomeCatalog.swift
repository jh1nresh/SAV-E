import Combine
import CoreLocation
import Foundation

/// Eat / Go lens locked by HoP D3. Eat is food, cafe, and bar.
/// Go is attraction, stay, and shopping. The save's category is the source.
enum SaveDoodleLens: String, CaseIterable, Identifiable {
    case eat
    case go

    var id: String { rawValue }

    var accessibilityIdentifier: String { "home.\(rawValue)" }

    var mapAccessibilityIdentifier: String { "map.\(rawValue)" }

    func title(language: AppLanguage) -> String {
        switch self {
        case .eat:
            return language.localized(english: "Eat", traditionalChinese: "吃")
        case .go:
            return language.localized(english: "Go", traditionalChinese: "去")
        }
    }
}

enum SaveDoodleCitySelection: Equatable, Hashable {
    case nearYou
    case city(String)

    var storageValue: String {
        switch self {
        case .nearYou: return "nearYou"
        case .city(let id): return id
        }
    }

    init(storageValue: String) {
        self = storageValue == "nearYou" ? .nearYou : .city(storageValue)
    }
}

struct SaveDoodleCityGroup: Equatable, Identifiable {
    let id: String
    let englishName: String
    let chineseName: String
    let count: Int

    func displayName(language: AppLanguage) -> String {
        language == .traditionalChinese ? chineseName : englishName
    }
}

struct SaveDoodleListedPlace: Equatable, Identifiable {
    let place: Place
    let index: Int
    let distance: CLLocationDistance?

    var id: UUID { place.id }
}

/// Shared Eat/Go + city selection so Home's mini-map can open Map with the
/// same filter (IA Q5). Persisted per UI-test storage id so tests stay isolated.
@MainActor
final class SaveDoodleSession: ObservableObject {
    @Published var lens: SaveDoodleLens {
        didSet { defaults.set(lens.rawValue, forKey: Self.lensKey) }
    }

    @Published var city: SaveDoodleCitySelection {
        didSet { defaults.set(city.storageValue, forKey: Self.cityKey) }
    }

    /// Q5: Map applies Home's Eat/Go + city only after a mini-map open.
    /// Opening the Map tab directly leaves this false so Saved/Nearby stay
    /// unfiltered. Persisted so a tab switch cannot drop a just-set handoff.
    @Published var mapFollowsHomeFilter: Bool {
        didSet { defaults.set(mapFollowsHomeFilter, forKey: Self.followKey) }
    }

    /// In-memory handoff. A later `selectRootTab(.map)` default-false write
    /// cannot win while this is set; Map consumes it on appear.
    @Published private(set) var pendingMiniMapHandoff = false

    /// Bumped on mini-map open and on abandon so a reused Map tab identity
    /// cannot keep the unfiltered wordmark-only header.
    @Published private(set) var mapSurfaceID = UUID()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.lensKey),
           let stored = SaveDoodleLens(rawValue: raw) {
            lens = stored
        } else {
            lens = .eat
        }
        if let raw = defaults.string(forKey: Self.cityKey) {
            city = SaveDoodleCitySelection(storageValue: raw)
        } else {
            city = .nearYou
        }
        mapFollowsHomeFilter = defaults.bool(forKey: Self.followKey)
    }

    /// Mini-map tap. Sets follow + a fresh Map identity before the tab switch.
    func beginMiniMapHandoff() {
        pendingMiniMapHandoff = true
        mapFollowsHomeFilter = true
        mapSurfaceID = UUID()
    }

    /// Map appear. Re-applies follow if a tab-bar default-false write landed
    /// after `beginMiniMapHandoff`.
    func consumeMiniMapHandoff() {
        guard pendingMiniMapHandoff else { return }
        mapFollowsHomeFilter = true
        pendingMiniMapHandoff = false
    }

    /// Search / show-on-map / list handoffs drop a leftover Home filter.
    func abandonMiniMapHandoff() {
        pendingMiniMapHandoff = false
        if mapFollowsHomeFilter {
            mapSurfaceID = UUID()
        }
        mapFollowsHomeFilter = false
    }

    /// Tab-bar Map keeps the pending mini-map handoff; any other Map tab
    /// selection uses the requested follow flag.
    func applyMapTabSelection(followsHomeFilter: Bool) {
        if pendingMiniMapHandoff {
            mapFollowsHomeFilter = true
            return
        }
        if mapFollowsHomeFilter != followsHomeFilter {
            mapSurfaceID = UUID()
        }
        mapFollowsHomeFilter = followsHomeFilter
    }

    private static var suiteSuffix: String {
        ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"] ?? "default"
    }

    static var lensKey: String { "save.doodle.lens.\(suiteSuffix)" }
    static var cityKey: String { "save.doodle.city.\(suiteSuffix)" }
    static var followKey: String { "save.doodle.mapFollows.\(suiteSuffix)" }
}

enum SaveDoodleHomeCatalog {
    /// Walking-scale "near you" radius. Empty state uses the same bound.
    static let nearbyRadius: CLLocationDistance = 3_000

    static func lens(for category: PlaceCategory) -> SaveDoodleLens {
        switch category {
        case .food, .cafe, .bar:
            return .eat
        case .attraction, .stay, .shopping:
            return .go
        }
    }

    static func cityID(for place: Place) -> String? {
        if let key = SaveHomeSearch.metroKey(in: place.address) {
            return key
        }
        guard let area = SavedPlaceTripRecommender.areaLabel(for: place) else { return nil }
        return area
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func cityDisplayName(for place: Place, language: AppLanguage) -> String? {
        if let key = SaveHomeSearch.metroKey(in: place.address),
           let label = SaveHomeSearch.cityLabel(
            for: key,
            traditionalChinese: language == .traditionalChinese
           ) {
            return label
        }
        return SavedPlaceTripRecommender.areaLabel(for: place)
    }

    static func cityGroups(from places: [Place]) -> [SaveDoodleCityGroup] {
        var counts: [String: (english: String, chinese: String, count: Int)] = [:]
        for place in places {
            guard let id = cityID(for: place) else { continue }
            let english = cityDisplayName(for: place, language: .english) ?? id
            let chinese = cityDisplayName(for: place, language: .traditionalChinese) ?? english
            if var existing = counts[id] {
                existing.count += 1
                counts[id] = existing
            } else {
                counts[id] = (english, chinese, 1)
            }
        }
        return counts
            .map { SaveDoodleCityGroup(id: $0.key, englishName: $0.value.english, chineseName: $0.value.chinese, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.englishName.localizedCaseInsensitiveCompare($1.englishName) == .orderedAscending
            }
    }

    /// Location denied hides "Near you" and falls back to the last city,
    /// or the city of the most recent save.
    static func resolvedSelection(
        _ selection: SaveDoodleCitySelection,
        places: [Place],
        locationDenied: Bool
    ) -> SaveDoodleCitySelection {
        guard locationDenied, case .nearYou = selection else { return selection }
        let newest = places.sorted(by: moreRecent).first
        if let newest, let id = cityID(for: newest) {
            return .city(id)
        }
        return selection
    }

    static func visiblePlaces(
        from places: [Place],
        lens: SaveDoodleLens,
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool
    ) -> [Place] {
        let matching = places.filter { self.lens(for: $0.category) == lens }
        switch resolvedSelection(selection, places: places, locationDenied: locationDenied) {
        case .nearYou:
            guard let location else {
                return matching.sorted(by: moreRecent)
            }
            return matching
                .filter { distance(from: location, to: $0).map { $0 <= nearbyRadius } ?? false }
                .sorted { lhs, rhs in
                    closer(lhs, rhs, to: location)
                }
        case .city(let id):
            let inCity = matching.filter { cityID(for: $0) == id }
            if let location {
                return inCity.sorted { lhs, rhs in
                    closer(lhs, rhs, to: location)
                }
            }
            return inCity.sorted(by: moreRecent)
        }
    }

    static func listedPlaces(
        from places: [Place],
        lens: SaveDoodleLens,
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool
    ) -> [SaveDoodleListedPlace] {
        visiblePlaces(
            from: places,
            lens: lens,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
        .enumerated()
        .map { index, place in
            SaveDoodleListedPlace(
                place: place,
                index: index + 1,
                distance: location.flatMap { distance(from: $0, to: place) }
            )
        }
    }

    static func isNearbyEmpty(
        places: [Place],
        lens: SaveDoodleLens,
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool
    ) -> Bool {
        guard case .nearYou = selection, !locationDenied else { return false }
        guard location != nil else { return false }
        return visiblePlaces(
            from: places,
            lens: lens,
            selection: .nearYou,
            location: location,
            locationDenied: false
        ).isEmpty && places.contains { self.lens(for: $0.category) == lens }
    }

    static func nearestOtherSave(
        in places: [Place],
        excluding visible: [Place],
        location: CLLocation?
    ) -> (place: Place, distance: CLLocationDistance?)? {
        let excluded = Set(visible.map(\.id))
        let remaining = places.filter { !excluded.contains($0.id) }
        guard !remaining.isEmpty else { return nil }
        if let location {
            let ranked = remaining.compactMap { place -> (Place, CLLocationDistance)? in
                guard let meters = distance(from: location, to: place) else { return nil }
                return (place, meters)
            }.sorted { $0.1 < $1.1 }
            if let first = ranked.first {
                return (first.0, first.1)
            }
        }
        if let newest = remaining.sorted(by: moreRecent).first {
            return (newest, location.flatMap { distance(from: $0, to: newest) })
        }
        return nil
    }

    static func collectedProgress(in places: [Place]) -> (visited: Int, saved: Int, goal: Int) {
        let saved = places.count
        let visited = places.filter { $0.status == .visited }.count
        return (visited, saved, SaveTileTownProductLock.passportGoal(for: saved))
    }

    static func collectedStamps(in places: [Place], limit: Int = 3) -> [Place] {
        Array(places.filter { $0.status == .visited }.sorted(by: moreRecent).prefix(limit))
    }

    static func distance(
        from location: CLLocation,
        to place: Place
    ) -> CLLocationDistance? {
        guard place.isMapKitMappable else { return nil }
        return location.distance(
            from: CLLocation(latitude: place.latitude, longitude: place.longitude)
        )
    }

    static func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded()))m"
        }
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.1fkm", km)
        }
        return "\(Int(km.rounded()))km"
    }

    static func moreRecent(_ lhs: Place, _ rhs: Place) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func closer(_ lhs: Place, _ rhs: Place, to location: CLLocation) -> Bool {
        let left = distance(from: location, to: lhs) ?? .infinity
        let right = distance(from: location, to: rhs) ?? .infinity
        if left != right { return left < right }
        return moreRecent(lhs, rhs)
    }
}
