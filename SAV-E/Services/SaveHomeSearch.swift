import Foundation

/// Local, deterministic matching for confirmed saved places shown on Home.
///
/// This intentionally works only with the `Place` values already in memory. It
/// does not ask a provider to complete a query or turn a clue into a place.
struct SaveHomeSearch {
    var filters: [String] = []
    var draft: String = ""

    var isActive: Bool {
        !filters.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func commitDraft() {
        let chunks = Self.chips(from: draft)
        defer { draft = "" }

        for chunk in chunks where !filters.contains(where: { Self.equivalent($0, chunk) }) {
            filters.append(chunk)
        }
    }

    mutating func removeFilter(_ filter: String) {
        guard let index = filters.firstIndex(where: { Self.equivalent($0, filter) }) else { return }
        filters.remove(at: index)
    }

    mutating func clear() {
        filters = []
        draft = ""
    }

    /// Metro-level city for D2 switching. Prefers recognized aliases so
    /// "Shibuya City, Tokyo" and "Dusit, Bangkok" resolve to Tokyo / Bangkok.
    /// Shared country recognition for metro matching and fallback city grouping.
    static func countryToken(in address: String) -> String? {
        addressCountryToken(address)
    }

    static func metroKey(in address: String) -> String? {
        for city in City.ordered where city.matches(address: address) && city.hasLocalityComponent(in: address) {
            return city.rawValue
        }
        return nil
    }

    static func metroName(in address: String, traditionalChinese: Bool) -> String? {
        guard let key = metroKey(in: address) else { return nil }
        return cityLabel(for: key, traditionalChinese: traditionalChinese)
    }

    static func cityLabel(for value: String, traditionalChinese: Bool) -> String? {
        guard let city = City(rawValue: value) else { return nil }
        let labels: (String, String)
        switch city {
        case .taipei: labels = ("Taipei", "台北")
        case .newTaipei: labels = ("New Taipei", "新北")
        case .taoyuan: labels = ("Taoyuan", "桃園")
        case .taichung: labels = ("Taichung", "台中")
        case .tainan: labels = ("Tainan", "台南")
        case .kaohsiung: labels = ("Kaohsiung", "高雄")
        case .keelung: labels = ("Keelung", "基隆")
        case .hsinchu: labels = ("Hsinchu", "新竹")
        case .chiayi: labels = ("Chiayi", "嘉義")
        case .tokyo: labels = ("Tokyo", "東京")
        case .losAngeles: labels = ("Los Angeles", "洛杉磯")
        case .bangkok: labels = ("Bangkok", "曼谷")
        case .kyoto: labels = ("Kyoto", "京都")
        case .osaka: labels = ("Osaka", "大阪")
        case .newYork: labels = ("New York", "紐約")
        case .sanFrancisco: labels = ("San Francisco", "舊金山")
        case .seoul: labels = ("Seoul", "首爾")
        case .singapore: labels = ("Singapore", "新加坡")
        case .hongKong: labels = ("Hong Kong", "香港")
        case .paris: labels = ("Paris", "巴黎")
        case .london: labels = ("London", "倫敦")
        case .shanghai: labels = ("Shanghai", "上海")
        case .beijing: labels = ("Beijing", "北京")
        case .guangzhou: labels = ("Guangzhou", "廣州")
        case .shenzhen: labels = ("Shenzhen", "深圳")
        case .chengdu: labels = ("Chengdu", "成都")
        }
        return traditionalChinese ? labels.1 : labels.0
    }

    func matchingPlaces(in places: [Place]) -> [Place] {
        let activeQueries = filters + [draft]
        let constraints = activeQueries.flatMap(Self.constraints(from:))
        guard !constraints.isEmpty else { return places }

        return places.filter { place in
            constraints.allSatisfy { $0.matches(place) }
        }
    }

    /// Parity fixtures have no live `Place`. Prefer `matchingPlaces(in:)` when
    /// the row still carries the confirmed place.
    func matchesLibraryPlace(name: String, address: String, note: String = "") -> Bool {
        let constraints = (filters + [draft]).flatMap(Self.constraints(from:))
        guard !constraints.isEmpty else { return true }
        let haystack = Self.normalize([name, address, note].joined(separator: " "))
        return constraints.allSatisfy { constraint in
            switch constraint {
            case let .category(category):
                return (Self.categoryAliases[category] ?? []).contains {
                    Self.contains(alias: $0, in: haystack)
                }
            case let .city(city):
                return city.matches(address: address) || city.matches(address: haystack)
            case let .text(term):
                return haystack.contains(term)
            }
        }
    }

    func matches(_ place: AtlasPlacePresentation) -> Bool {
        if let searchPlace = place.searchPlace {
            return !matchingPlaces(in: [searchPlace]).isEmpty
        }
        return matchesLibraryPlace(
            name: place.name,
            address: [place.area, place.region].compactMap { $0 }.joined(separator: " "),
            note: place.note
        )
    }
}

enum SaveHomeReviewQueue {
    static func isSourceClue(_ candidate: PlaceReviewCandidate) -> Bool {
        candidate.status.lowercased() == "source_only" || !candidate.hasSavableLocation
    }

    static func isHomePreview(_ candidate: PlaceReviewCandidate) -> Bool {
        let status = candidate.status.lowercased()
        if ["failed", "rejected"].contains(status) { return false }
        if isSourceClue(candidate) { return true }
        return candidate.hasSavableLocation
            && ["review", "confirmed", "needs_more_evidence"].contains(status)
    }

    /// Review Candidates stay first so a Source Clue never hides an actionable match.
    static func previewIDs(in candidates: [PlaceReviewCandidate]) -> [String] {
        candidates
            .filter(isHomePreview)
            .sorted { lhs, rhs in
                let lhsSource = isSourceClue(lhs)
                let rhsSource = isSourceClue(rhs)
                if lhsSource != rhsSource { return !lhsSource }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id.uuidString)
    }
}

/// Same distinction shown by the existing Saves queue.
struct SaveHomeReviewCounts: Equatable {
    let candidates: Int
    let sources: Int
    var total: Int { candidates + sources }

    init(_ items: [PlaceReviewCandidate]) {
        sources = items.filter(SaveHomeReviewQueue.isSourceClue).count
        candidates = items.count - sources
    }

    init(from items: [AtlasReviewPresentation]) {
        sources = items.filter { $0.kind == .sourceOnly }.count
        candidates = items.count - sources
    }
}

private extension SaveHomeSearch {
    enum Constraint: Hashable {
        case category(PlaceCategory)
        case city(City)
        case text(String)

        func matches(_ place: Place) -> Bool {
            switch self {
            case let .category(category):
                return place.category == category
            case let .city(city):
                return city.matches(address: place.address)
            case let .text(term):
                return Self.searchableMetadata(for: place).contains(term)
            }
        }

        private static func searchableMetadata(for place: Place) -> String {
            let values = [
                place.name,
                place.address,
                place.note ?? "",
                place.category.displayName,
            ] +
                (place.vibeTags ?? []) +
                (place.placeHighlights ?? []) +
                (place.accessNotes ?? []) +
                place.savedRecommendedItems.map(\.name)

            return SaveHomeSearch.normalize(values.joined(separator: " "))
        }
    }

    enum City: String, CaseIterable, Hashable {
        case taipei
        case newTaipei
        case taoyuan
        case taichung
        case tainan
        case kaohsiung
        case keelung
        case hsinchu
        case chiayi
        case tokyo
        case losAngeles
        case bangkok
        case kyoto
        case osaka
        case newYork
        case sanFrancisco
        case seoul
        case singapore
        case hongKong
        case paris
        case london
        case shanghai
        case beijing
        case guangzhou
        case shenzhen
        case chengdu

        static let ordered = allCases.sorted {
            if $0.longestAliasLength != $1.longestAliasLength {
                return $0.longestAliasLength > $1.longestAliasLength
            }
            return $0.rawValue < $1.rawValue
        }

        private var longestAliasLength: Int {
            aliases.map { SaveHomeSearch.normalize($0).count }.max() ?? 0
        }

        var aliasesByLength: [String] {
            aliases.sorted {
                let lhsLength = SaveHomeSearch.normalize($0).count
                let rhsLength = SaveHomeSearch.normalize($1).count
                if lhsLength != rhsLength { return lhsLength > rhsLength }
                return $0 < $1
            }
        }

        var aliases: [String] {
            switch self {
            case .taipei: return ["taipei city", "taipeicity", "taipei", "台北市", "臺北市", "台北", "臺北"]
            case .newTaipei: return ["new taipei city", "new taipei", "newtaipei", "新北市", "新北"]
            case .taoyuan: return ["taoyuan", "桃園", "桃园"]
            case .taichung: return ["taichung", "台中", "臺中"]
            case .tainan: return ["tainan", "台南", "臺南"]
            case .kaohsiung: return ["kaohsiung", "高雄"]
            case .keelung: return ["keelung", "基隆"]
            case .hsinchu: return ["hsinchu", "新竹"]
            case .chiayi: return ["chiayi", "嘉義", "嘉义"]
            case .tokyo: return ["tokyo", "東京都", "东京都", "東京", "东京"]
            case .losAngeles: return ["los angeles", "losangeles", "洛杉磯", "洛杉矶"]
            case .bangkok: return ["bangkok", "曼谷"]
            case .kyoto: return ["kyoto", "京都"]
            case .osaka: return ["osaka", "大阪"]
            case .newYork: return ["new york city", "new york", "newyork", "紐約市", "纽约市", "紐約", "纽约"]
            case .sanFrancisco: return ["san francisco", "sanfrancisco", "舊金山", "旧金山"]
            case .seoul: return ["seoul", "首爾", "首尔"]
            case .singapore: return ["singapore", "新加坡"]
            case .hongKong: return ["hong kong", "hongkong", "香港"]
            case .paris: return ["paris", "巴黎"]
            case .london: return ["london", "倫敦", "伦敦"]
            case .shanghai: return ["shanghai", "上海"]
            case .beijing: return ["beijing", "北京"]
            case .guangzhou: return ["guangzhou", "廣州", "广州"]
            case .shenzhen: return ["shenzhen", "深圳"]
            case .chengdu: return ["chengdu", "成都"]
            }
        }

        func matches(address: String) -> Bool {
            let normalizedAddress = SaveHomeSearch.normalize(address)
            let aliasHit: Bool
            switch self {
            case .taipei:
                aliasHit = aliases.contains { alias in
                    SaveHomeSearch.contains(alias: alias, in: normalizedAddress) &&
                        !SaveHomeSearch.contains(alias: "new taipei", in: normalizedAddress) &&
                        !normalizedAddress.contains("新北")
                }
            case .kyoto:
                // 東京都 contains 京都 as a substring, but is a Tokyo address.
                guard !normalizedAddress.contains("東京都"), !normalizedAddress.contains("东京都") else { return false }
                aliasHit = aliases.contains { SaveHomeSearch.contains(alias: $0, in: normalizedAddress) }
            default:
                aliasHit = aliases.contains { SaveHomeSearch.contains(alias: $0, in: normalizedAddress) }
            }
            return aliasHit && fitsAdministrativeRegion(address)
        }

        /// A street named London Road is not evidence that its city is London.
        /// Keep free-text search matching separate from structured city grouping.
        func hasLocalityComponent(in address: String) -> Bool {
            let components = address.split(separator: ",").map {
                SaveHomeSearch.normalize(SaveDoodleHomeCatalog.strippingPostalCode(from: String($0)))
            }
            return components.contains { component in
                aliases.contains { alias in
                    let normalizedAlias = SaveHomeSearch.normalize(alias)
                    if component == normalizedAlias { return true }
                    // Compact East Asian addresses begin with their municipality:
                    // 台北市大安區 / 東京都渋谷区 / 大阪府大阪市.
                    guard normalizedAlias.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return false }
                    var locality = component
                    for country in ["台灣", "臺灣", "台湾", "日本", "中國", "中国"] where locality.hasPrefix(country) {
                        locality.removeFirst(country.count)
                    }
                    locality = String(locality.drop(while: { $0.isNumber || $0 == "-" || $0.isWhitespace }))
                    guard locality.hasPrefix(normalizedAlias) else { return false }
                    let suffix = locality.dropFirst(normalizedAlias.count)
                    if self == .hongKong {
                        // Hong Kong has no 市 marker. Accept explicit locality
                        // prefixes, not streets such as 香港路 in another city.
                        return ["中環", "中环", "中西區", "中西区", "灣仔", "湾仔", "九龍", "九龙", "新界"].contains {
                            suffix.hasPrefix($0)
                        }
                    }
                    return normalizedAlias.last.map { "市都府縣县".contains($0) } == true
                        || suffix.first.map { "市都府縣县".contains($0) } == true
                }
            }
        }

        /// Allowlisted aliases stay canonical unless the address names a
        /// different country or a US state (Paris, TX vs Paris, France).
        private func fitsAdministrativeRegion(_ address: String) -> Bool {
            if SaveHomeSearch.addressSignalsUnitedStates(address), !isUnitedStatesMetro {
                return false
            }
            guard let country = SaveHomeSearch.addressCountryToken(address),
                  let home = homeCountryTokens
            else { return true }
            return home.contains(country)
        }

        private var isUnitedStatesMetro: Bool {
            switch self {
            case .losAngeles, .newYork, .sanFrancisco: return true
            default: return false
            }
        }

        private var homeCountryTokens: Set<String>? {
            switch self {
            case .losAngeles, .newYork, .sanFrancisco:
                return ["usa", "us", "united states", "united states of america"]
            case .taipei, .newTaipei, .taoyuan, .taichung, .tainan, .kaohsiung,
                 .keelung, .hsinchu, .chiayi:
                return ["taiwan"]
            case .tokyo, .kyoto, .osaka:
                return ["japan"]
            case .bangkok:
                return ["thailand"]
            case .seoul:
                return ["korea", "south korea"]
            case .singapore:
                return ["singapore"]
            case .hongKong:
                return ["hong kong", "china"]
            case .paris:
                return ["france"]
            case .london:
                return ["uk", "u.k.", "united kingdom", "england", "britain"]
            case .shanghai, .beijing, .guangzhou, .shenzhen, .chengdu:
                return ["china"]
            }
        }
    }

    static func chips(from value: String) -> [String] {
        let constraints = constraints(from: value)
        guard !constraints.isEmpty else { return [] }

        return constraints.map { constraint in
            switch constraint {
            case let .category(category): return category.rawValue
            case let .city(city): return city.rawValue
            case let .text(term): return term
            }
        }
    }

    static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        constraints(from: lhs) == constraints(from: rhs)
    }

    static func constraints(from rawValue: String) -> [Constraint] {
        var remaining = normalize(rawValue)
        guard !remaining.isEmpty else { return [] }

        var result: [Constraint] = []
        for city in City.ordered where city.matches(address: remaining) {
            result.append(.city(city))
            city.aliasesByLength.forEach { remaining = removing(alias: $0, from: remaining) }
        }

        for category in PlaceCategory.allCases {
            let aliases = categoryAliases[category] ?? []
            guard aliases.contains(where: { contains(alias: $0, in: remaining) }) else { continue }
            result.append(.category(category))
            aliases
                .sorted { normalize($0).count > normalize($1).count }
                .forEach { remaining = removing(alias: $0, from: remaining) }
        }

        let residual = remaining
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && (result.isEmpty || !["in", "at"].contains($0)) }
        result.append(contentsOf: residual.map(Constraint.text))
        return result
    }

    static let categoryAliases: [PlaceCategory: [String]] = [
        .food: ["food", "restaurant", "restaurants", "美食", "餐廳", "餐厅"],
        .cafe: ["coffee shops", "coffee shop", "coffee", "cafes", "café", "cafe", "咖啡店", "咖啡"],
        .bar: ["bars", "bar", "酒吧"],
        .attraction: ["attraction", "attractions", "景點", "景点"],
        .stay: ["stay", "hotel", "hotels", "住宿", "飯店", "饭店"],
        .shopping: ["shopping", "shop", "shops", "購物", "购物"],
    ]

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "臺", with: "台")
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contains(alias: String, in value: String) -> Bool {
        let normalizedAlias = normalize(alias)
        guard !normalizedAlias.isEmpty else { return false }
        if isASCIIPhrase(normalizedAlias) {
            return firstWordSequence(of: normalizedAlias, in: value) != nil
        }
        return value.contains(normalizedAlias)
    }

    static func removing(alias: String, from value: String) -> String {
        let normalizedAlias = normalize(alias)
        guard !normalizedAlias.isEmpty else { return value }
        if isASCIIPhrase(normalizedAlias) {
            var words = value.split(separator: " ").map(String.init)
            let needle = normalizedAlias.split(separator: " ").map(String.init)
            while let start = firstWordSequence(of: needle, in: words) {
                words.removeSubrange(start..<(start + needle.count))
            }
            return words.joined(separator: " ")
        }
        return value.replacingOccurrences(of: normalizedAlias, with: " ")
    }

    static func isASCIIPhrase(_ value: String) -> Bool {
        let words = value.split(separator: " ")
        return !words.isEmpty && words.allSatisfy { word in
            word.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) ||
                (65...90).contains(scalar.value) ||
                (97...122).contains(scalar.value)
            }
        }
    }

    static func firstWordSequence(of alias: String, in value: String) -> Int? {
        firstWordSequence(
            of: alias.split(separator: " ").map(String.init),
            in: value.split(separator: " ").map(String.init)
        )
    }

    static func firstWordSequence(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        return (0...(haystack.count - needle.count)).first { start in
            Array(haystack[start..<(start + needle.count)]) == needle
        }
    }

    /// `Paris, TX 75460, USA` and `Paris, Texas` are US; `Paris, France` is not.
    static func addressSignalsUnitedStates(_ address: String) -> Bool {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let last = parts.last, countryTokens.contains(normalize(last)),
           ["usa", "us", "united states", "united states of america"].contains(normalize(last)) {
            return true
        }
        return parts.contains { isUnitedStatesStatePart($0) }
    }

    static func addressCountryToken(_ address: String) -> String? {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        let token = normalize(last)
        return countryTokens.contains(token) ? token : localizedCountryTokens[token]
    }

    private static func isUnitedStatesStatePart(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = normalize(trimmed)
        if usStateNames.contains(folded) { return true }
        if folded.range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil {
            return usStateCodes.contains(folded)
        }
        if let match = folded.range(of: #"^[a-z]{2}(?=\s)"#, options: .regularExpression) {
            return usStateCodes.contains(String(folded[match]))
        }
        return false
    }

    // Use the platform's full region catalogue, not a handful of supported
    // metros' countries: Los Ángeles in Chile must never become California.
    private static let localizedCountryTokens: [String: String] = {
        let english = Locale(identifier: "en_US_POSIX")
        let locales = [english, Locale(identifier: "zh_Hant"), Locale(identifier: "zh_Hans")]
        var tokens: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            guard let name = english.localizedString(forRegionCode: region.identifier) else { continue }
            let canonical = region.identifier == "HK" ? "hong kong" : normalize(name)
            for locale in locales {
                if let name = locale.localizedString(forRegionCode: region.identifier) {
                    tokens[normalize(name)] = canonical
                }
            }
        }
        return tokens
    }()

    private static let countryTokens: Set<String> = [
        "usa", "us", "united states", "united states of america",
        "uk", "u.k.", "united kingdom", "england", "britain",
        "taiwan", "japan", "china", "canada", "australia", "france",
        "germany", "italy", "spain", "korea", "south korea", "thailand",
        "singapore", "hong kong",
    ]

    private static let usStateCodes: Set<String> = [
        "al", "ak", "az", "ar", "ca", "co", "ct", "de", "fl", "ga", "hi",
        "id", "il", "in", "ia", "ks", "ky", "la", "me", "md", "ma", "mi",
        "mn", "ms", "mo", "mt", "ne", "nv", "nh", "nj", "nm", "ny", "nc",
        "nd", "oh", "ok", "or", "pa", "ri", "sc", "sd", "tn", "tx", "ut",
        "vt", "va", "wa", "wv", "wi", "wy", "dc",
    ]

    private static let usStateNames: Set<String> = [
        "alabama", "alaska", "arizona", "arkansas", "california", "colorado",
        "connecticut", "delaware", "florida", "georgia", "hawaii", "idaho",
        "illinois", "indiana", "iowa", "kansas", "kentucky", "louisiana",
        "maine", "maryland", "massachusetts", "michigan", "minnesota",
        "mississippi", "missouri", "montana", "nebraska", "nevada",
        "new hampshire", "new jersey", "new mexico", "new york",
        "north carolina", "north dakota", "ohio", "oklahoma", "oregon",
        "pennsylvania", "rhode island", "south carolina", "south dakota",
        "tennessee", "texas", "utah", "vermont", "virginia", "washington",
        "west virginia", "wisconsin", "wyoming", "district of columbia",
    ]
}
