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

    /// Prior Map-tab residue: selected pin, expanded search drawer, or a
    /// header that only mounted on the first `onAppear`. Mini-map bumps this
    /// so Map remounts Eat/Go instead of keeping the wordmark-only chrome.
    @Published private(set) var mapVisitResidueID = UUID()

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

    /// Mini-map tap. Sets follow, drops leftover Map-tab chrome, and gives
    /// Map a new identity so Eat/Go remounts on a reused view.
    func beginMiniMapHandoff() {
        pendingMiniMapHandoff = true
        mapFollowsHomeFilter = true
        mapSurfaceID = UUID()
        mapVisitResidueID = UUID()
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
        guard let area = localityLabel(in: place.address) else { return nil }
        let locality = normalizedCityToken(area)
        guard !locality.isEmpty else { return nil }
        // Locality alone merges Springfield IL with Springfield MA.
        // Keep the displayed name as the city; qualify the stable ID.
        if let qualifier = regionQualifier(in: place.address) {
            return "\(locality),\(qualifier)"
        }
        return locality
    }

    static func cityDisplayName(for place: Place, language: AppLanguage) -> String? {
        if let key = SaveHomeSearch.metroKey(in: place.address),
           let label = SaveHomeSearch.cityLabel(
            for: key,
            traditionalChinese: language == .traditionalChinese
           ) {
            return label
        }
        return localityLabel(in: place.address)
    }

    /// Locality for Home city scope. Do not reuse `shareAreaLabel` — that
    /// takes the second-to-last comma part and turns
    /// `Berkeley, CA 94704, USA` into `CA 94704`, splitting one city by ZIP.
    static func localityLabel(in address: String) -> String? {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        if let cjk = cjkLocality(in: address) { return cjk }

        var local = parts
        if let last = local.last, Self.countryTokens.contains(last.lowercased()) {
            local.removeLast()
        }
        while let last = local.last, isPostalOrAdminRegion(last) {
            local.removeLast()
        }
        guard let city = local.last, !city.isEmpty else { return nil }
        return stripLeadingPostalCode(from: city)
    }

    private static let countryTokens: Set<String> = [
        "usa", "us", "united states", "united states of america",
        "uk", "u.k.", "united kingdom", "taiwan", "japan", "china",
        "canada", "australia", "france", "germany", "italy", "spain",
        "korea", "south korea", "thailand", "singapore",
        "switzerland", "schweiz", "suisse", "svizzera",
        "austria", "österreich", "osterreich",
        "netherlands", "nederland", "holland",
        "belgium", "belgie", "belgië", "belgique",
        "portugal", "ireland", "sweden", "norway", "denmark", "finland",
        "poland", "hungary", "greece", "romania", "mexico", "brazil",
        "india", "new zealand", "czech republic", "czechia", "south africa",
    ]

    /// `8001 Zürich` / `69001 Lyon` — postcode is a prefix, not the city.
    private static func stripLeadingPostalCode(from token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(
            of: #"^\d{4,6}\s+"#,
            options: .regularExpression
        ) else { return trimmed }
        let name = trimmed[match.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : String(name)
    }

    private static func normalizedCityToken(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Admin region or country after the locality. Display stays the city.
    static func regionQualifier(in address: String) -> String? {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var local = parts
        var country: String?
        if let last = local.last, countryTokens.contains(last.lowercased()) {
            country = normalizedCityToken(last)
            local.removeLast()
        }
        var admin: String?
        while let last = local.last, isPostalOrAdminRegion(last) {
            if admin == nil, let code = adminRegionCode(in: last) {
                admin = code
            }
            local.removeLast()
        }
        return admin ?? country
    }

    private static func adminRegionCode(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z]{2}$"#, options: .regularExpression) != nil {
            return trimmed.lowercased()
        }
        if let match = trimmed.range(of: #"^[A-Za-z]{2}(?=\s)"#, options: .regularExpression) {
            return String(trimmed[match]).lowercased()
        }
        return nil
    }

    private static func isPostalOrAdminRegion(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z]{2}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(
            of: #"^[A-Za-z]{2}\s+\d{5}(?:-\d{4})?$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.range(of: #"^\d{5}(?:-\d{4})?$"#, options: .regularExpression) != nil {
            return true
        }
        // Canada: "BC V8W 1P6" or "V8W 1P6" — not the city.
        if trimmed.range(
            of: #"^[A-Za-z]{2}\s+[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.range(
            of: #"^[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        // UK outward+inward: "SW1A 1AA", "M1 1AE".
        if trimmed.range(
            of: #"^[A-Za-z]{1,2}\d[A-Za-z\d]?\s*\d[A-Za-z]{2}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        // Australia / generic 4-digit postcode.
        if trimmed.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func cjkLocality(in address: String) -> String? {
        guard address.contains(where: {
            $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }) else { return nil }
        for marker in ["市", "縣", "县"] {
            guard let end = address.range(of: marker) else { continue }
            let head = address[address.startIndex..<end.upperBound]
            let city = String(head.drop { $0.isNumber })
                .replacingOccurrences(of: "台灣", with: "")
                .replacingOccurrences(of: "臺灣", with: "")
                .replacingOccurrences(of: "中國", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if city.count >= 2 { return city }
        }
        return nil
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
        // Coordinate-only imports have no locality. Walk recency until a
        // save actually resolves, so denied Near you does not stay empty.
        if let match = places.sorted(by: moreRecent).first(where: { cityID(for: $0) != nil }),
           let id = cityID(for: match) {
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
            // Unknown location is not worldwide nearby. Fresh install,
            // undetermined authorization, and a transient fix failure must
            // return no rows so Home can prompt instead of plotting every city.
            guard let location else { return [] }
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
        // Home labels this “Latest save”. Recency wins; distance is metadata.
        guard let newest = remaining.sorted(by: moreRecent).first else { return nil }
        return (newest, location.flatMap { distance(from: $0, to: newest) })
    }

    /// All saved places in the current city, every category. Independent of
    /// the Eat/Go list. Near you uses the city of the nearest nearby save.
    static func collectedScopePlaces(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool
    ) -> [Place] {
        switch resolvedSelection(selection, places: places, locationDenied: locationDenied) {
        case .nearYou:
            guard let id = nearYouCityID(from: places, location: location) else { return [] }
            return places.filter { cityID(for: $0) == id }
        case .city(let id):
            return places.filter { cityID(for: $0) == id }
        }
    }

    static func nearYouCityID(from places: [Place], location: CLLocation?) -> String? {
        guard let place = nearYouCityPlace(from: places, location: location) else { return nil }
        return cityID(for: place)
    }

    /// Nearest nearby save across every category. Header, Collected, and
    /// Passport must share this city — not the nearest Eat/Go row.
    static func nearYouCityPlace(from places: [Place], location: CLLocation?) -> Place? {
        guard let location else { return nil }
        let nearby = places.filter { distance(from: location, to: $0).map { $0 <= nearbyRadius } ?? false }
        // An addressless closest pin must not hide Collected when another
        // nearby save has a resolvable city.
        return nearby
            .filter { cityID(for: $0) != nil }
            .sorted { closer($0, $1, to: location) }
            .first
    }

    static func nearYouCityName(
        from places: [Place],
        location: CLLocation?,
        language: AppLanguage
    ) -> String? {
        guard let place = nearYouCityPlace(from: places, location: location) else { return nil }
        return cityDisplayName(for: place, language: language)
    }

    static func cityCollectedCount(in places: [Place]) -> (visited: Int, saved: Int) {
        (places.filter { $0.status == .visited }.count, places.count)
    }

    static func collectedProgress(in places: [Place]) -> (visited: Int, saved: Int, goal: Int) {
        let count = cityCollectedCount(in: places)
        return (count.visited, count.saved, count.saved)
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

/// Shared manual-visit history for Map and Passport. Reuses both pre-existing
/// keys so adopting the common store never discards either surface's history.
/// Read through defaults on every operation: separate view instances see writes
/// made by the other surface without retaining stale snapshots.
@MainActor
final class SaveDoodleVisitStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    func count(for id: UUID) -> Int {
        max(defaults.integer(forKey: Self.countKey(id)), dates(for: id).count)
    }

    func hasVisitedToday(_ id: UUID) -> Bool {
        let today = now()
        return dates(for: id).contains { calendar.isDate($0, inSameDayAs: today) }
    }

    @discardableResult
    func recordVisit(for id: UUID) -> Bool {
        guard !hasVisitedToday(id) else { return false }
        let total = count(for: id) + 1
        var payload = visitPayload
        payload[id.uuidString, default: []].append(now().timeIntervalSince1970)
        defaults.set(payload, forKey: Self.datesKey)
        defaults.set(total, forKey: Self.countKey(id))
        return true
    }

    /// Production "I've been here" / Mark visited path. Records today's
    /// check-in and promotes the place to a Map Stamp. Home Collected and
    /// Passport both read `status == .visited` after this write.
    func markIveBeenHere(_ place: Place) -> Place {
        recordVisit(for: place.id)
        var updated = place
        updated.status = .visited
        return updated
    }

    @discardableResult
    func undoToday(for id: UUID) -> Bool {
        let today = now()
        let dates = dates(for: id)
        let remaining = dates.filter { !calendar.isDate($0, inSameDayAs: today) }
        let removed = dates.count - remaining.count
        guard removed > 0 else { return false }
        let total = max(0, count(for: id) - removed)
        var payload = visitPayload
        payload[id.uuidString] = remaining.isEmpty ? nil : remaining.map(\.timeIntervalSince1970)
        defaults.set(payload, forKey: Self.datesKey)
        defaults.set(total, forKey: Self.countKey(id))
        return true
    }

    struct Snapshot: Equatable {
        let id: UUID
        let dates: [Double]
        let count: Int
    }

    func snapshot(for id: UUID) -> Snapshot {
        Snapshot(id: id, dates: visitPayload[id.uuidString] ?? [], count: count(for: id))
    }

    func restore(_ snapshot: Snapshot) {
        var payload = visitPayload
        payload[snapshot.id.uuidString] = snapshot.dates.isEmpty ? nil : snapshot.dates
        defaults.set(payload, forKey: Self.datesKey)
        defaults.set(snapshot.count, forKey: Self.countKey(snapshot.id))
    }

    func previousStatus(for id: UUID) -> PlaceStatus? {
        defaults.string(forKey: Self.priorStatusKey(id)).flatMap(PlaceStatus.init(rawValue:))
    }

    func rememberPriorStatus(_ status: PlaceStatus, for id: UUID) {
        defaults.set(status.rawValue, forKey: Self.priorStatusKey(id))
    }

    func clearPriorStatus(for id: UUID) {
        defaults.removeObject(forKey: Self.priorStatusKey(id))
    }

    private func dates(for id: UUID) -> [Date] {
        (visitPayload[id.uuidString] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    private var visitPayload: [String: [Double]] {
        defaults.dictionary(forKey: Self.datesKey) as? [String: [Double]] ?? [:]
    }

    private static var suiteSuffix: String {
        ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"] ?? "default"
    }

    static var datesKey: String { "save.doodle.checkins.\(suiteSuffix)" }

    static func countKey(_ id: UUID) -> String {
        "save.doodle.passport.visits.\(suiteSuffix).\(id.uuidString)"
    }

    static func priorStatusKey(_ id: UUID) -> String {
        "save.doodle.checkin.priorStatus.\(suiteSuffix).\(id.uuidString)"
    }
}

/// City-scope X/Y for Home Collected and the Passport progress this PR
/// wires. PR #295 already owns SaveDoodlePassportCatalog in
/// SaveDoodlePassportCatalog.swift for stamp-grid layout (pageSize,
/// columns). After #290 merges, #295 keeps that type and should call
/// SaveDoodleHomeProgressCatalog for city visited/saved numbers — do
/// not declare SaveDoodlePassportCatalog in this file.
enum SaveDoodleHomeProgressCatalog {
    static func cityPlaces(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation? = nil,
        locationDenied: Bool
    ) -> [Place] {
        SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
        .sorted(by: SaveDoodleHomeCatalog.moreRecent)
    }

    static func progress(in places: [Place]) -> (visited: Int, saved: Int) {
        SaveDoodleHomeCatalog.cityCollectedCount(in: places)
    }

    static func visitedCount(in places: [Place]) -> Int {
        progress(in: places).visited
    }
}
