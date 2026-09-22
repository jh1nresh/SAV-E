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
            switch self {
            case .taipei:
                return aliases.contains { alias in
                    SaveHomeSearch.contains(alias: alias, in: normalizedAddress) &&
                        !SaveHomeSearch.contains(alias: "new taipei", in: normalizedAddress) &&
                        !normalizedAddress.contains("新北")
                }
            case .kyoto:
                // 東京都 contains 京都 as a substring, but is a Tokyo address.
                guard !normalizedAddress.contains("東京都"), !normalizedAddress.contains("东京都") else { return false }
                return aliases.contains { SaveHomeSearch.contains(alias: $0, in: normalizedAddress) }
            default:
                return aliases.contains { SaveHomeSearch.contains(alias: $0, in: normalizedAddress) }
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
}
