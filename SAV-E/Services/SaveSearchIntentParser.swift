import Foundation

struct SaveSearchIntent: Equatable {
    enum Kind: Equatable {
        case explicitPlaceSearch
        case categoryRecommendation
        case craving
        case tripPlanning
        case publicDiscovery
        case unknown
    }

    enum LocationMode: Equatable {
        case currentLocation(radiusMeters: Double)
        case mapRegion
        case namedArea(String)
        case savedAnywhere
        case unspecified
    }

    enum SourceScope: Equatable {
        case savedOnly
        case savedFirstAllowPublicFallback
        case publicOnly
    }

    let rawText: String
    let normalizedText: String
    let kind: Kind
    let requiredCategories: Set<PlaceCategory>
    let optionalCategories: Set<PlaceCategory>
    let locationMode: LocationMode
    let sourceScope: SourceScope
    let mustMatchCategory: Bool
    let mustMatchLocation: Bool
    let confidence: Double
    let unsupportedCategoryLabel: String?
    let categoryNeedles: [String]
}

struct SaveSearchIntentLexicon {
    enum EvidencePolicy: Equatable {
        case categoryOnly
        case specificEvidence
    }

    struct Entry: Equatable {
        let id: String
        let category: PlaceCategory
        let needles: [String]
        let publicSearchQuery: String?
        let recommendationLabel: String
        let localizedRecommendationLabel: String
        let evidencePolicy: EvidencePolicy

        var requiresSpecificEvidenceMatch: Bool {
            evidencePolicy == .specificEvidence
        }
    }

    static let entries: [Entry] = [
        Entry(
            id: "milk-tea",
            category: .cafe,
            needles: ["milk tea", "boba", "bubble tea", "tea shop", "奶茶", "珍奶", "珍珠奶茶"],
            publicSearchQuery: "boba milk tea",
            recommendationLabel: "boba / milk tea",
            localizedRecommendationLabel: "奶茶 / 珍奶",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "quiet-cafe",
            category: .cafe,
            needles: ["quiet cafe", "work cafe", "work-friendly cafe", "wifi cafe", "安靜咖啡", "安静咖啡", "適合工作", "适合工作"],
            publicSearchQuery: "quiet cafe wifi",
            recommendationLabel: "quiet cafe",
            localizedRecommendationLabel: "安靜咖啡廳",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "coffee",
            category: .cafe,
            needles: ["coffee", "cafe", "coffee shop", "咖啡", "咖啡廳", "咖啡厅"],
            publicSearchQuery: nil,
            recommendationLabel: "cafe",
            localizedRecommendationLabel: "咖啡廳",
            evidencePolicy: .categoryOnly
        ),
        Entry(
            id: "hot-pot",
            category: .food,
            needles: ["hot pot", "hotpot", "shabu", "shabu shabu", "火鍋", "火锅", "涮涮鍋", "涮涮锅"],
            publicSearchQuery: "hot pot",
            recommendationLabel: "hot pot",
            localizedRecommendationLabel: "火鍋",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "japanese",
            category: .food,
            needles: ["japanese", "japanese restaurant", "japanese food", "sushi", "ramen", "izakaya", "yakiniku", "sukiyaki", "日式", "日式餐廳", "日式餐厅", "日本料理", "日式料理", "壽司", "寿司", "拉麵", "拉面", "居酒屋", "燒肉", "烧肉", "壽喜燒", "寿喜烧"],
            publicSearchQuery: "japanese restaurant",
            recommendationLabel: "Japanese",
            localizedRecommendationLabel: "日式餐廳",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "korean",
            category: .food,
            needles: ["korean", "korean bbq", "kbbq", "韓式", "韩式", "韓國料理", "韩国料理", "韓式烤肉", "韩式烤肉", "部隊鍋", "部队锅"],
            publicSearchQuery: "korean restaurant",
            recommendationLabel: "Korean",
            localizedRecommendationLabel: "韓式餐廳",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "thai",
            category: .food,
            needles: ["thai", "thai food", "thai restaurant", "泰式", "泰國料理", "泰国料理"],
            publicSearchQuery: "thai restaurant",
            recommendationLabel: "Thai",
            localizedRecommendationLabel: "泰式餐廳",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "chinese",
            category: .food,
            needles: ["chinese", "chinese food", "chinese restaurant", "中式", "中餐", "中國菜", "中国菜", "川菜", "粵菜", "粤菜", "港式"],
            publicSearchQuery: "chinese restaurant",
            recommendationLabel: "Chinese",
            localizedRecommendationLabel: "中式餐廳",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "brunch",
            category: .food,
            needles: ["brunch", "breakfast", "早午餐", "早餐"],
            publicSearchQuery: "brunch",
            recommendationLabel: "brunch",
            localizedRecommendationLabel: "早午餐",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "dessert",
            category: .cafe,
            needles: ["dessert", "bakery", "cake", "patisserie", "甜點", "甜点", "蛋糕", "烘焙", "麵包", "面包"],
            publicSearchQuery: "dessert bakery",
            recommendationLabel: "dessert",
            localizedRecommendationLabel: "甜點",
            evidencePolicy: .specificEvidence
        ),
        Entry(
            id: "food",
            category: .food,
            needles: ["food", "restaurant", "restaurants", "dinner", "lunch", "餐廳", "餐厅", "晚餐", "午餐", "吃飯", "吃饭", "美食"],
            publicSearchQuery: nil,
            recommendationLabel: "food",
            localizedRecommendationLabel: "餐廳",
            evidencePolicy: .categoryOnly
        ),
        Entry(
            id: "bar",
            category: .bar,
            needles: ["bar", "cocktail", "drink", "drinks", "酒吧", "喝酒", "調酒", "调酒"],
            publicSearchQuery: nil,
            recommendationLabel: "bar",
            localizedRecommendationLabel: "酒吧",
            evidencePolicy: .categoryOnly
        ),
        Entry(
            id: "attraction",
            category: .attraction,
            needles: ["attraction", "museum", "gallery", "exhibition", "spot", "景點", "景点", "展覽", "展览", "美術館", "美术馆", "博物館", "博物馆"],
            publicSearchQuery: nil,
            recommendationLabel: "attraction",
            localizedRecommendationLabel: "景點",
            evidencePolicy: .categoryOnly
        ),
        Entry(
            id: "stay",
            category: .stay,
            needles: ["hotel", "stay", "住宿", "飯店", "酒店"],
            publicSearchQuery: nil,
            recommendationLabel: "stay",
            localizedRecommendationLabel: "住宿",
            evidencePolicy: .categoryOnly
        ),
        Entry(
            id: "shopping",
            category: .shopping,
            needles: ["shopping", "shop", "shops", "mall", "購物", "购物", "商場", "商场"],
            publicSearchQuery: nil,
            recommendationLabel: "shopping",
            localizedRecommendationLabel: "購物地點",
            evidencePolicy: .categoryOnly
        )
    ]

    static func match(in normalized: String) -> Entry? {
        entries.first { entry in
            entry.needles.contains { normalized.contains($0) }
        }
    }

    static func entry(matchingNeedles needles: [String]) -> Entry? {
        entries.first { entry in
            entry.needles.contains { needle in
                needles.contains(needle)
            }
        }
    }
}

struct SaveSearchIntentParser {
    func parse(_ rawText: String) -> SaveSearchIntent? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = Self.normalize(trimmed)
        let categoryMatch = SaveSearchIntentLexicon.match(in: normalized)
        let unsupportedCategory = Self.unsupportedCategory(in: normalized)
        let locationMode = Self.locationMode(in: normalized, categoryMatch: categoryMatch)
        let mustMatchLocation = {
            if case .currentLocation = locationMode { return true }
            return false
        }()
        let hasRecommendationLanguage = Self.containsAny(
            normalized,
            keywords: ["recommend", "suggest", "nearby", "nearest", "near me", "around here", "想", "想喝", "想吃", "推薦", "附近", "找"]
        )

        guard categoryMatch != nil || unsupportedCategory != nil || mustMatchLocation else {
            return nil
        }

        let kind: SaveSearchIntent.Kind
        if Self.containsAny(normalized, keywords: ["想", "想喝", "想吃", "craving", "feel like"]) {
            kind = .craving
        } else if hasRecommendationLanguage || categoryMatch != nil || unsupportedCategory != nil {
            kind = .categoryRecommendation
        } else {
            kind = .unknown
        }

        let sourceScope: SaveSearchIntent.SourceScope = Self.containsAny(
            normalized,
            keywords: ["new", "unsaved", "public", "新的", "沒存", "未儲存"]
        ) ? .publicOnly : .savedFirstAllowPublicFallback

        return SaveSearchIntent(
            rawText: trimmed,
            normalizedText: normalized,
            kind: kind,
            requiredCategories: categoryMatch.map { [$0.category] } ?? [],
            optionalCategories: [],
            locationMode: locationMode,
            sourceScope: sourceScope,
            mustMatchCategory: categoryMatch != nil || unsupportedCategory != nil,
            mustMatchLocation: mustMatchLocation,
            confidence: categoryMatch != nil || unsupportedCategory != nil ? 0.92 : 0.72,
            unsupportedCategoryLabel: unsupportedCategory,
            categoryNeedles: categoryMatch?.needles ?? []
        )
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func locationMode(
        in normalized: String,
        categoryMatch: SaveSearchIntentLexicon.Entry?
    ) -> SaveSearchIntent.LocationMode {
        if containsAny(normalized, keywords: ["walking", "walkable", "走路", "步行"]) {
            return .currentLocation(radiusMeters: 1_000)
        }
        if containsAny(normalized, keywords: ["nearby", "nearest", "near me", "around here", "附近", "周邊", "周边", "身邊", "身边"]) {
            return .currentLocation(radiusMeters: 2_000)
        }
        if let namedArea = namedArea(in: normalized) {
            return .namedArea(namedArea)
        }
        if categoryMatch != nil,
           containsAny(normalized, keywords: ["find", "search", "looking for", "找", "搜尋", "搜索"]) {
            return .currentLocation(radiusMeters: 2_000)
        }
        if categoryMatch != nil,
           containsAny(normalized, keywords: ["recommend", "suggest", "推薦"]) {
            return .currentLocation(radiusMeters: 2_000)
        }
        if containsAny(normalized, keywords: ["today", "tonight", "now", "right now", "今天", "今晚", "現在", "现在"]) {
            return .currentLocation(radiusMeters: 2_000)
        }
        return .savedAnywhere
    }

    private static func namedArea(in normalized: String) -> String? {
        if normalized.contains(" in la") || normalized.contains(" los angeles") { return "Los Angeles" }
        if normalized.contains(" irvine") { return "Irvine" }
        if normalized.contains(" taipei") || normalized.contains("台北") { return "Taipei" }
        if normalized.contains(" tokyo") || normalized.contains("東京") { return "Tokyo" }
        return nil
    }

    private static func unsupportedCategory(in normalized: String) -> String? {
        if containsAny(normalized, keywords: ["gym", "fitness", "workout", "健身房", "健身"]) {
            return "gym"
        }
        return nil
    }

    static func containsAny(_ value: String, keywords: [String]) -> Bool {
        keywords.contains { value.contains($0.lowercased()) }
    }
}

extension SaveSearchIntent {
    var requiresSpecificEvidenceMatch: Bool {
        SaveSearchIntentLexicon.entry(matchingNeedles: categoryNeedles)?.requiresSpecificEvidenceMatch == true
    }

    var recommendationLabel: String {
        if let entry = SaveSearchIntentLexicon.entry(matchingNeedles: categoryNeedles) {
            return entry.recommendationLabel
        }
        guard let category = requiredCategories.first else { return "places" }
        return category.displayName.lowercased()
    }

    var localizedRecommendationLabel: String {
        if let entry = SaveSearchIntentLexicon.entry(matchingNeedles: categoryNeedles) {
            return entry.localizedRecommendationLabel
        }
        guard let category = requiredCategories.first else { return "地點" }
        switch category {
        case .food: return "餐廳"
        case .cafe: return "咖啡廳"
        case .bar: return "酒吧"
        case .attraction: return "景點"
        case .stay: return "住宿"
        case .shopping: return "購物地點"
        }
    }

    func matchesSpecificEvidence(in text: String) -> Bool {
        let normalized = SaveSearchIntentParser.normalize(text)
        return categoryNeedles.contains { needle in
            normalized.contains(needle)
        }
    }
}

extension SaveSearchIntent {
    /// Low-confidence intent for natural-language queries the deterministic
    /// parser cannot classify. Keeps the grounded LLM answer available instead
    /// of falling back to a raw literal-match list.
    static func freeformFallback(rawText: String, confidence: Double = 0.5) -> SaveSearchIntent {
        SaveSearchIntent(
            rawText: rawText,
            normalizedText: SaveSearchIntentParser.normalize(rawText),
            kind: .unknown,
            requiredCategories: [],
            optionalCategories: [],
            locationMode: .unspecified,
            sourceScope: .savedFirstAllowPublicFallback,
            mustMatchCategory: false,
            mustMatchLocation: false,
            confidence: confidence,
            unsupportedCategoryLabel: nil,
            categoryNeedles: []
        )
    }
}

/// Decides when the deterministic classifier is good enough on its own and
/// when a query should be routed through the LLM intent-extraction step.
struct SaveSearchLLMRouter {
    static let deterministicConfidenceThreshold = 0.9

    /// High-confidence deterministic intents (explicit category needle hit) skip
    /// the LLM round trip: faster, cheaper, and the lexicon gates are stricter.
    static func shouldTrustDeterministicIntent(_ intent: SaveSearchIntent?) -> Bool {
        guard let intent else { return false }
        return intent.confidence >= deterministicConfidenceThreshold &&
            !intent.requiredCategories.isEmpty
    }

    /// Natural-language queries deserve an LLM answer even when no intent was
    /// classified. Short literal lookups (place names, addresses) do not.
    static func isNaturalLanguageQuery(_ query: String) -> Bool {
        let normalized = SaveSearchIntentParser.normalize(query)
        let markers = [
            "?", "？", "why", "how", "should", "which", "where", "what", "who",
            "recommend", "suggest", "worth", "best", "good for",
            "嗎", "吗", "呢", "哪", "什麼", "什么", "怎麼", "怎么", "推薦", "推荐", "想", "好不好", "值得"
        ]
        if markers.contains(where: { normalized.contains($0) }) { return true }
        let wordCount = normalized.split { $0.isWhitespace }.count
        return wordCount >= 4
    }
}

enum SaveSearchIntentValidationError: Error, Equatable {
    case malformedJSON
    case unknownCategory(String)
    case invalidLocationMode
    case invalidKind
    case invalidSourceScope
    case unsafeRadius
    case unsafeCategoryGate
    case unsafeLocationGate
}

struct SaveSearchIntentJSONValidator {
    private struct IntentDTO: Decodable {
        struct LocationModeDTO: Decodable {
            let type: String
            let radiusMeters: Double?
            let area: String?
        }

        let kind: String
        let requiredCategories: [String]?
        let optionalCategories: [String]?
        let locationMode: LocationModeDTO
        let sourceScope: String
        let mustMatchCategory: Bool
        let mustMatchLocation: Bool
        let confidence: Double
    }

    func parseIntentJSON(_ json: String, rawText: String) throws -> SaveSearchIntent {
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(IntentDTO.self, from: data) else {
            throw SaveSearchIntentValidationError.malformedJSON
        }

        let normalized = SaveSearchIntentParser.normalize(rawText)
        let deterministic = SaveSearchIntentParser().parse(rawText)
        let requiredCategories = try categories(from: dto.requiredCategories ?? [])
        let optionalCategories = try categories(from: dto.optionalCategories ?? [])
        let locationMode = try locationMode(from: dto.locationMode)
        let sourceScope = try sourceScope(from: dto.sourceScope)
        let kind = try kind(from: dto.kind)

        if deterministic?.mustMatchLocation == true, dto.mustMatchLocation == false {
            throw SaveSearchIntentValidationError.unsafeLocationGate
        }
        if deterministic?.mustMatchCategory == true, dto.mustMatchCategory == false {
            throw SaveSearchIntentValidationError.unsafeCategoryGate
        }

        return SaveSearchIntent(
            rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedText: normalized,
            kind: kind,
            requiredCategories: Set(requiredCategories),
            optionalCategories: Set(optionalCategories),
            locationMode: locationMode,
            sourceScope: sourceScope,
            mustMatchCategory: dto.mustMatchCategory,
            mustMatchLocation: dto.mustMatchLocation,
            confidence: min(max(dto.confidence, 0), 1),
            unsupportedCategoryLabel: deterministic?.unsupportedCategoryLabel,
            categoryNeedles: deterministic?.categoryNeedles ?? []
        )
    }

    private func categories(from values: [String]) throws -> [PlaceCategory] {
        try values.map { value in
            guard let category = PlaceCategory(rawValue: value) else {
                throw SaveSearchIntentValidationError.unknownCategory(value)
            }
            return category
        }
    }

    private func locationMode(from dto: IntentDTO.LocationModeDTO) throws -> SaveSearchIntent.LocationMode {
        switch dto.type {
        case "currentLocation":
            let radius = dto.radiusMeters ?? 2_000
            guard radius >= 500, radius <= 20_000 else {
                throw SaveSearchIntentValidationError.unsafeRadius
            }
            return .currentLocation(radiusMeters: radius)
        case "mapRegion":
            return .mapRegion
        case "namedArea":
            guard let area = dto.area?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty else {
                throw SaveSearchIntentValidationError.invalidLocationMode
            }
            return .namedArea(area)
        case "savedAnywhere":
            return .savedAnywhere
        case "unspecified":
            return .unspecified
        default:
            throw SaveSearchIntentValidationError.invalidLocationMode
        }
    }

    private func kind(from value: String) throws -> SaveSearchIntent.Kind {
        switch value {
        case "explicitPlaceSearch": return .explicitPlaceSearch
        case "categoryRecommendation": return .categoryRecommendation
        case "craving": return .craving
        case "tripPlanning": return .tripPlanning
        case "publicDiscovery": return .publicDiscovery
        case "unknown": return .unknown
        default: throw SaveSearchIntentValidationError.invalidKind
        }
    }

    private func sourceScope(from value: String) throws -> SaveSearchIntent.SourceScope {
        switch value {
        case "savedOnly": return .savedOnly
        case "savedFirstAllowPublicFallback": return .savedFirstAllowPublicFallback
        case "publicOnly": return .publicOnly
        default: throw SaveSearchIntentValidationError.invalidSourceScope
        }
    }
}
