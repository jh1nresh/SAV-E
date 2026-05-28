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

struct SaveSearchIntentParser {
    func parse(_ rawText: String) -> SaveSearchIntent? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = Self.normalize(trimmed)
        let categoryMatch = Self.categoryMatch(in: normalized)
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
        categoryMatch: (category: PlaceCategory, needles: [String])?
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

    private static func categoryMatch(in normalized: String) -> (category: PlaceCategory, needles: [String])? {
        let specs: [(PlaceCategory, [String])] = [
            (.cafe, ["milk tea", "boba", "bubble tea", "coffee", "cafe", "coffee shop", "tea shop", "奶茶", "珍奶", "珍珠奶茶", "咖啡", "咖啡廳", "咖啡厅"]),
            (.food, ["food", "restaurant", "restaurants", "dinner", "lunch", "sushi", "ramen", "餐廳", "餐厅", "晚餐", "午餐", "吃飯", "吃饭", "美食"]),
            (.bar, ["bar", "cocktail", "drink", "drinks", "酒吧", "喝酒", "調酒", "调酒"]),
            (.attraction, ["attraction", "museum", "gallery", "exhibition", "spot", "景點", "景点", "展覽", "展览", "美術館", "美术馆", "博物館", "博物馆"]),
            (.stay, ["hotel", "stay", "住宿", "飯店", "酒店"]),
            (.shopping, ["shopping", "shop", "shops", "mall", "購物", "购物", "商場", "商场"])
        ]
        return specs.first { _, needles in
            needles.contains { normalized.contains($0) }
        }
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
