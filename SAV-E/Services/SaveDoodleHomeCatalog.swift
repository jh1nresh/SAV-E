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
        self = storageValue == "nearYou" ? .nearYou : .city(SaveDoodleHomeCatalog.canonicalCityID(storageValue))
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

/// Shared Eat/Go + city selection for Home. Map does not follow this
/// filter: Home has no mini-map (founder option B, 2026-10-24).
/// Place-detail "View on map" may focus one stamp; two-way filter
/// sharing stays with #298.
@MainActor
final class SaveDoodleSession: ObservableObject {
    @Published var lens: SaveDoodleLens {
        didSet { defaults.set(lens.rawValue, forKey: Self.lensKey) }
    }

    @Published var city: SaveDoodleCitySelection {
        didSet { defaults.set(city.storageValue, forKey: Self.cityKey) }
    }

    /// One-shot Home detail → Map focus. Not persisted; not MiniMapHandoff.
    @Published var pendingShowOnMapPlaceID: UUID?

    /// Map Eat/Go chips can follow Home's current lens + city. Opening the
    /// Map tab leaves this false so the default Saved/Nearby/Friends set
    /// stays unfiltered (#290). Not a mini-map handoff.
    @Published var mapFollowsHomeFilter = false

    /// A fresh command entering Map owns its camera even if Home filters changed.
    var pendingExplicitMapEntry = false
    /// An empty loading fallback is not a completed collection fit. Keep this
    /// across tab mounts, without publishing camera-ownership bookkeeping.
    var mapHasEstablishedViewport = false
    private var lastMapFilters: (lens: SaveDoodleLens, city: SaveDoodleCitySelection)?

    enum MapEntry: Equatable {
        case explicitCommand
        case changedFilters
        case restoreViewport
    }

    func recordMapFilters() {
        lastMapFilters = (lens, city)
    }

    func shouldFitMapCollection(hasVisibleRegion: Bool) -> Bool {
        !mapHasEstablishedViewport || !hasVisibleRegion
    }

    func consumeMapEntry() -> MapEntry {
        defer {
            pendingExplicitMapEntry = false
            recordMapFilters()
        }
        if pendingExplicitMapEntry { return .explicitCommand }
        if let lastMapFilters,
           lastMapFilters.lens != lens || lastMapFilters.city != city {
            return .changedFilters
        }
        return .restoreViewport
    }

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
    }

    private static var suiteSuffix: String {
        ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"] ?? "default"
    }

    static var lensKey: String { "save.doodle.lens.\(suiteSuffix)" }
    static var cityKey: String { "save.doodle.city.\(suiteSuffix)" }
}

/// DEBUG-only injectable clock for UI tests. Production always uses `Date()`.
/// Pass `--uitest-fixed-now=yyyy-MM-dd'T'HH:mm:ss` (device-local, not UTC).
enum SaveUITestClock {
    static var now: Date {
#if DEBUG
        if let injected = injectedNow { return injected }
#endif
        return Date()
    }

    /// Device-local `yyyy-MM-dd'T'HH:mm:ss`. Not UTC.
    static func parseLocal(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

#if DEBUG
    static var injectedNow: Date? {
        let prefix = "--uitest-fixed-now="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
        else { return nil }
        return parseLocal(String(argument.dropFirst(prefix.count)))
    }
#endif
}

enum SaveDoodleHomeCatalog {
    /// Walking-scale "near you" radius. Empty state uses the same bound.
    static let nearbyRadius: CLLocationDistance = 3_000

    /// Preserve an existing city selection when its country spelling changes
    /// to the shared canonical qualifier. Administrative-region IDs stay intact.
    static func canonicalCityID(_ id: String) -> String {
        SaveAddressLocality.canonicalCityID(id)
    }

    static func lens(for category: PlaceCategory) -> SaveDoodleLens {
        switch category {
        case .food, .cafe, .bar:
            return .eat
        case .attraction, .stay, .shopping:
            return .go
        }
    }

    static func cityID(for place: Place) -> String? {
        SaveAddressLocality.resolve(place.address)?.cityID
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
        SaveAddressLocality.resolve(address)?.label
    }

    /// Postal prefixes and trailing numeric/UK/Canadian postcodes are not city names.
    static func strippingPostalCode(from token: String) -> String {
        SaveAddressLocality.strippingPostalCode(from: token)
    }

    /// Admin region or country after the locality. Display stays the city.
    static func regionQualifier(in address: String) -> String? {
        guard let resolved = SaveAddressLocality.resolve(address) else { return nil }
        return resolved.region ?? resolved.country
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
    /// or the city of the most recent save. A `.city` whose last save
    /// disappeared (delete or address edit) falls back the same way.
    static func resolvedSelection(
        _ selection: SaveDoodleCitySelection,
        places: [Place],
        locationDenied: Bool
    ) -> SaveDoodleCitySelection {
        if case .city(let id) = selection {
            if places.contains(where: { cityID(for: $0) == id }) {
                return selection
            }
            if !locationDenied {
                return .nearYou
            }
            return newestResolvableCity(in: places) ?? .nearYou
        }
        guard locationDenied, case .nearYou = selection else { return selection }
        // Coordinate-only imports have no locality. Walk recency until a
        // save actually resolves, so denied Near you does not stay empty.
        return newestResolvableCity(in: places) ?? selection
    }

    /// Cold launch starts with an empty collection. That empty list is not
    /// "the selected city's last save disappeared" — wait until the initial
    /// load has produced places before persisting a replacement.
    static func persistedCityAfterCollectionChange(
        current: SaveDoodleCitySelection,
        places: [Place],
        locationDenied: Bool,
        collectionReady: Bool
    ) -> SaveDoodleCitySelection {
        guard collectionReady else { return current }
        let resolved = resolvedSelection(current, places: places, locationDenied: locationDenied)
        guard current != resolved, case .city = current else { return current }
        return resolved
    }

    private static func newestResolvableCity(in places: [Place]) -> SaveDoodleCitySelection? {
        guard let match = places.sorted(by: moreRecent).first(where: { cityID(for: $0) != nil }),
              let id = cityID(for: match)
        else { return nil }
        return .city(id)
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

    /// Home Eat/Go + city rows. Map may pass `including` so a one-shot
    /// View-on-map focus still renders when that stamp is outside the
    /// current lens or city. Home chrome stays on the current filter.
    static func listedPlaces(
        from places: [Place],
        lens: SaveDoodleLens,
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool,
        including focused: Place? = nil
    ) -> [SaveDoodleListedPlace] {
        var listed = visiblePlaces(
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
        if let focused,
           places.contains(where: { $0.id == focused.id }),
           !listed.contains(where: { $0.id == focused.id }) {
            listed.append(
                SaveDoodleListedPlace(
                    place: focused,
                    index: listed.count + 1,
                    distance: location.flatMap { distance(from: $0, to: focused) }
                )
            )
        }
        return listed
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

    /// Row subtitle: `<distance or neighborhood> · <visit status>`.
    static func rowMetaText(
        distance: CLLocationDistance?,
        place: Place,
        visitedAt: Date? = nil,
        now: Date = Date(),
        language: AppLanguage
    ) -> String {
        let location = distance.map(distanceText)
            ?? neighborhoodText(for: place, language: language)
        let status = visitStatusText(
            status: place.status,
            visitedAt: place.status == .visited ? visitedAt : nil,
            now: now,
            language: language
        )
        if let location, !location.isEmpty {
            return "\(location) · \(status)"
        }
        return status
    }

    static func visitStatusText(
        status: PlaceStatus,
        visitedAt: Date?,
        now: Date = Date(),
        language: AppLanguage
    ) -> String {
        switch status {
        case .wantToGo:
            return language.localized(english: "saved, not yet", traditionalChinese: "已存，還沒去")
        case .visited:
            guard let reference = visitedAt else {
                return language.localized(english: "visited", traditionalChinese: "已去過")
            }
            let days = max(0, Calendar.current.dateComponents([.day], from: reference, to: now).day ?? 0)
            if days == 0 {
                return language.localized(english: "visited today", traditionalChinese: "今天去過")
            }
            return language.localized(
                english: "visited \(days)d ago",
                traditionalChinese: "\(days) 天前去過"
            )
        }
    }

    /// District when the address names one; otherwise the city label.
    static func neighborhoodText(for place: Place, language: AppLanguage) -> String? {
        if let district = cjkDistrict(in: place.address) ?? englishDistrict(in: place.address) {
            return district
        }
        return cityDisplayName(for: place, language: language)
    }

    private static func cjkDistrict(in address: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fff]{1,2}[區区]") else {
            return nil
        }
        let range = NSRange(address.startIndex..., in: address)
        return regex.matches(in: address, range: range).last.flatMap { match in
            Range(match.range, in: address).map { String(address[$0]) }
        }
    }

    private static func englishDistrict(in address: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b[\w'’.-]+(?:\s+[\w'’.-]+)?\s+District\b"#
        ) else {
            return nil
        }
        let range = NSRange(address.startIndex..., in: address)
        return regex.matches(in: address, range: range).last.flatMap { match in
            Range(match.range, in: address).map { String(address[$0]) }
        }
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

/// Home hint-row greeting and clue copy. Cutoffs and strings live here.
enum SaveDoodleHomeHint {
    enum Period: Equatable {
        case morning, afternoon, evening
    }

    struct Copy: Equatable {
        let greeting: String
        let leadingFull: String
        let leadingShort: String
        let review: String?
        let spoken: String
    }

    static func period(at date: Date, calendar: Calendar = .current) -> Period {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minutes = hour * 60 + minute
        switch minutes {
        case (5 * 60)..<(12 * 60):
            return .morning
        case (12 * 60)..<(18 * 60):
            return .afternoon
        default:
            return .evening
        }
    }

    static func greeting(_ period: Period, language: AppLanguage) -> String {
        switch period {
        case .morning:
            return language.localized(english: "Good morning", traditionalChinese: "早安")
        case .afternoon:
            return language.localized(english: "Good afternoon", traditionalChinese: "午安")
        case .evening:
            return language.localized(english: "Good evening", traditionalChinese: "晚安")
        }
    }

    static func displayCount(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    static func copy(
        clueCount: Int,
        at date: Date,
        language: AppLanguage,
        calendar: Calendar = .current
    ) -> Copy {
        let greetingText = Self.greeting(period(at: date, calendar: calendar), language: language)
        guard clueCount > 0 else {
            return Copy(
                greeting: greetingText,
                leadingFull: greetingText,
                leadingShort: greetingText,
                review: nil,
                spoken: greetingText
            )
        }
        let n = displayCount(clueCount)
        let fullPhrase: String
        let shortPhrase: String
        switch language {
        case .english:
            if clueCount == 1 {
                fullPhrase = "1 clue waiting"
                shortPhrase = "1 clue"
            } else {
                fullPhrase = "\(n) clues waiting"
                shortPhrase = "\(n) clues"
            }
        case .traditionalChinese:
            fullPhrase = "\(n) 條線索待看"
            shortPhrase = fullPhrase
        }
        let review = language.localized(english: "Review ›", traditionalChinese: "去看看 ›")
        // Trailing ` ·` stays in the muted leading text so ViewThatFits and
        // the coral Review / 去看看 control both keep the DESIGN separator.
        let leadingFull = "\(greetingText) · \(fullPhrase) ·"
        let leadingShort = "\(greetingText) · \(shortPhrase) ·"
        return Copy(
            greeting: greetingText,
            leadingFull: leadingFull,
            leadingShort: leadingShort,
            review: review,
            spoken: "\(leadingFull) \(review)"
        )
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

    func latestVisit(for id: UUID) -> Date? {
        dates(for: id).max()
    }

    /// A render-scoped snapshot avoids decoding the whole defaults dictionary
    /// for every row. Read afresh on every call so record/undo/restore and
    /// writes from other surfaces remain immediately visible.
    func latestVisits(for ids: [UUID]) -> [UUID: Date] {
        guard !ids.isEmpty else { return [:] }
        let payload = visitPayload
        var latest: [UUID: Date] = [:]
        for id in ids {
            if let timestamp = payload[id.uuidString]?.max() {
                latest[id] = Date(timeIntervalSince1970: timestamp)
            }
        }
        return latest
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

/// Only Home's Collected entry carries a city scope. Other owner Passport
/// presentations retain the full collection and saved/goal progress.
enum SavePassportCollectionMode {
    case collection
    case homeCollected

    func places(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation?,
        locationDenied: Bool
    ) -> [Place] {
        guard self == .homeCollected else { return places }
        return SaveDoodleHomeProgressCatalog.cityPlaces(
            from: places, selection: selection, location: location,
            locationDenied: locationDenied
        )
    }

    func progress(in places: [Place]) -> (completed: Int, total: Int) {
        switch self {
        case .collection:
            return (places.count, SaveTileTownProductLock.passportGoal(for: places.count))
        case .homeCollected:
            let count = SaveDoodleHomeProgressCatalog.progress(in: places)
            return (count.visited, count.saved)
        }
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
