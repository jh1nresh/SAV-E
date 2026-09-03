import CoreLocation
import Foundation

enum PlaceVisibility: String, Codable, CaseIterable, Hashable {
    case privateMemory = "private"
    case friends
    case publicLink = "public_link"
    case publicGuide = "public_guide"

    var displayName: String {
        switch self {
        case .privateMemory: return "Private"
        case .friends: return "Friends"
        case .publicLink: return "Public link"
        case .publicGuide: return "Public guide"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .privateMemory:
            return language.localized(english: "Private", traditionalChinese: "私人")
        case .friends:
            return language.localized(english: "Friends", traditionalChinese: "朋友")
        case .publicLink:
            return language.localized(english: "Public link", traditionalChinese: "公開連結")
        case .publicGuide:
            return language.localized(english: "Public guide", traditionalChinese: "公開指南")
        }
    }

    var systemImage: String {
        switch self {
        case .privateMemory: return "lock.fill"
        case .friends: return "person.2.fill"
        case .publicLink: return "link"
        case .publicGuide: return "globe.americas.fill"
        }
    }

    var detailText: String {
        switch self {
        case .privateMemory:
            return "Only you can see this memory."
        case .friends:
            return "Followers can see this as a friend signal."
        case .publicLink:
            return "Shareable by link, but not used for trending."
        case .publicGuide:
            return "Can appear in public guide and trending surfaces."
        }
    }

    func detailText(language: AppLanguage) -> String {
        switch self {
        case .privateMemory:
            return language.localized(english: "Only you can see this memory.", traditionalChinese: "只有你看得到這個記憶。")
        case .friends:
            return language.localized(english: "Followers can see this as a friend signal.", traditionalChinese: "追蹤你的朋友可以把它當成朋友推薦訊號。")
        case .publicLink:
            return language.localized(english: "Shareable by link, but not used for trending.", traditionalChinese: "可用連結分享，但不會進入熱門訊號。")
        case .publicGuide:
            return language.localized(english: "Can appear in public guide and trending surfaces.", traditionalChinese: "可出現在公開指南與熱門地點。")
        }
    }

    var allowsFriendSignal: Bool {
        self != .privateMemory
    }

    var allowsTrendingSignal: Bool {
        self == .publicGuide
    }
}

enum SaveFollowSource: String, Codable, Hashable {
    case manual
    case referral
    case appClipHandoff = "app_clip_handoff"
}

struct SaveFollowedFriend: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let handle: String?
    let avatarUrl: String?

    var handleLabel: String? {
        guard let handle, !handle.isEmpty else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}

struct SaveFollowedFriendsPage: Codable, Hashable {
    let items: [SaveFollowedFriend]
    let nextCursor: String?
}

enum SaveSocialLens: String, Codable, CaseIterable, Hashable {
    case forYou
    case friends
    case trending

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .friends: return "Friends"
        case .trending: return "Trending"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .forYou:
            return language.localized(english: "For You", traditionalChinese: "為你")
        case .friends:
            return language.localized(english: "Friends", traditionalChinese: "朋友")
        case .trending:
            return language.localized(english: "Trending", traditionalChinese: "熱門")
        }
    }

    var systemImage: String {
        switch self {
        case .forYou: return "sparkles"
        case .friends: return "person.2.fill"
        case .trending: return "flame.fill"
        }
    }
}

enum PlaceSocialSignalKind: String, Codable, Hashable {
    case friendSaved = "friend_saved"
    case trending
    case referralGuide = "referral_guide"

    var pinSystemImage: String {
        switch self {
        case .friendSaved: return "person.2.fill"
        case .trending: return "flame.fill"
        case .referralGuide: return "link"
        }
    }
}

struct PlaceSocialSignal: Codable, Hashable {
    var kind: PlaceSocialSignalKind
    var lens: SaveSocialLens
    var friendNames: [String]
    var friendCount: Int
    var saveCount: Int
    var trendingRank: Int?
    var categoryRank: Int?
    var sourceLabel: String
    var referrerId: String?
    var referralCode: String?

    var displayText: String {
        switch kind {
        case .friendSaved:
            let lead = friendNames.prefix(2).joined(separator: ", ")
            if friendCount <= 1, !lead.isEmpty { return "Saved by \(lead)" }
            if !lead.isEmpty { return "Saved by \(lead) + \(max(friendCount - friendNames.prefix(2).count, 0))" }
            return "\(friendCount) friends saved this"
        case .trending:
            if let trendingRank {
                return "#\(trendingRank) trending nearby"
            }
            return "\(saveCount) saves nearby"
        case .referralGuide:
            return "From \(sourceLabel)'s Savvy"
        }
    }

    var detailText: String {
        switch kind {
        case .friendSaved:
            return "Friend signal from your Savvy graph."
        case .trending:
            return "Trending signal from public Map Stamps in this category."
        case .referralGuide:
            return "Referral guide preview. Save it to make it your own memory."
        }
    }
}

enum SaveOriginOutcomeLabel: String, Codable, Sendable {
    case useful = "useful_recommendation"
    case irrelevant = "irrelevant_recommendation"
}

struct SaveRecommendationOutcome: Decodable, Equatable, Sendable {
    let recommendationId: String
    let labels: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
        case labels
        case createdAt = "created_at"
    }
}

struct SaveRecommendationOutcomeDraft: Encodable, Equatable, Sendable {
    let recommendationId: String
    let labels: [String]
    let labelSource: String

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
        case labels
        case labelSource = "label_source"
    }
}

/// Deterministic, account-local ranking for Origin's social food deck.
///
/// The server's friend/trending order remains the fallback. Personal signals
/// only move candidates when the user has explicit preferences, saved-place
/// history, or a durable swipe outcome.
enum SaveOriginPersonalization {
    private static let recommendationPrefix = "origin:"

    static func recommendationID(for placeID: UUID) -> String {
        recommendationPrefix + placeID.uuidString.lowercased()
    }

    static func rank(
        candidates: [Place],
        savedPlaces: [Place],
        preferences: [SaveMemoryPreference],
        outcomes: [SaveRecommendationOutcome]
    ) -> [Place] {
        let latestOutcomes = latestOriginOutcomes(outcomes)
        let categoryCounts = Dictionary(grouping: savedPlaces, by: \.category)
            .mapValues(\.count)
        let areaCounts = Dictionary(
            grouping: savedPlaces.compactMap(normalizedArea),
            by: { $0 }
        )
        .mapValues(\.count)
        let activePreferences = preferences.filter(\.isActiveForRanking)

        return candidates.enumerated()
            .compactMap { index, place -> RankedPlace? in
                let outcome = latestOutcomes[place.id]
                if outcome?.labels.contains(SaveOriginOutcomeLabel.irrelevant.rawValue) == true {
                    return nil
                }

                var score = min(categoryCounts[place.category] ?? 0, 5) * 4
                if let area = normalizedArea(place) {
                    score += min(areaCounts[area] ?? 0, 5) * 5
                }
                score += preferenceScore(for: place, preferences: activePreferences)
                if outcome?.labels.contains(SaveOriginOutcomeLabel.useful.rawValue) == true {
                    score += 30
                }
                return RankedPlace(place: place, score: score, originalIndex: index)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.originalIndex < rhs.originalIndex
            }
            .map(\.place)
    }

    private static func latestOriginOutcomes(
        _ outcomes: [SaveRecommendationOutcome]
    ) -> [UUID: SaveRecommendationOutcome] {
        var latest: [UUID: SaveRecommendationOutcome] = [:]
        for outcome in outcomes {
            guard outcome.recommendationId.hasPrefix(recommendationPrefix),
                  let placeID = UUID(uuidString: String(outcome.recommendationId.dropFirst(recommendationPrefix.count)))
            else { continue }
            if let current = latest[placeID], current.createdAt >= outcome.createdAt { continue }
            latest[placeID] = outcome
        }
        return latest
    }

    private static func preferenceScore(
        for place: Place,
        preferences: [SaveMemoryPreference]
    ) -> Int {
        let searchable = normalized([
            place.name,
            place.address,
            place.category.rawValue,
            place.category.displayName,
            categoryAliases(place.category),
            place.note ?? "",
            place.extractedDishes?.joined(separator: " ") ?? "",
            place.vibeTags?.joined(separator: " ") ?? "",
            place.priceRange ?? "",
        ].joined(separator: " "))

        return preferences.reduce(into: 0) { score, preference in
            let value = normalized(preference.normalizedValue)
            guard !value.isEmpty, searchable.contains(value) else { return }
            let confidence = max(0, min(preference.confidence, 1))
            switch preference.polarity {
            case .like:
                score += Int((32 * confidence).rounded())
            case .dislike:
                score -= Int((40 * confidence).rounded())
            case .constraint:
                score += Int((24 * confidence).rounded())
            }
        }
    }

    private static func normalizedArea(_ place: Place) -> String? {
        guard let area = SavedPlaceTripRecommender.areaLabel(for: place) else { return nil }
        let value = normalized(area)
        return value.isEmpty ? nil : value
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func categoryAliases(_ category: PlaceCategory) -> String {
        switch category {
        case .food: return "restaurant dining food 餐廳 美食 料理"
        case .cafe: return "cafe coffee tea 咖啡 茶"
        case .bar: return "bar drinks cocktail 酒吧 調酒"
        case .attraction: return "attraction sightseeing 景點"
        case .stay: return "hotel stay 住宿 飯店"
        case .shopping: return "shopping shop 購物 商店"
        }
    }

    private struct RankedPlace {
        let place: Place
        let score: Int
        let originalIndex: Int
    }
}

struct SaveReferralProfile: Codable, Hashable {
    var referrerId: String
    var handle: String
    var displayName: String
    var referralCode: String
    var lens: SaveSocialLens
    var featuredPlaces: [Place]

    var referralURL: URL? {
        URL(string: "https://sav-e-app.vercel.app/u/\(handle)?ref=\(referralCode)")
    }

    static func preview(handle: String?, code: String?, lens: SaveSocialLens = .friends) -> SaveReferralProfile {
        let resolvedCode = (code?.isEmpty == false ? code : handle) ?? "memo"
        let resolvedHandle = (handle?.isEmpty == false ? handle : "friend") ?? "friend"
        let display = resolvedHandle
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return SaveReferralProfile(
            referrerId: "ref_\(resolvedCode)",
            handle: resolvedHandle,
            displayName: display,
            referralCode: resolvedCode,
            lens: lens,
            featuredPlaces: Place.socialPreviewSeeds(referrerDisplayName: display, referralCode: resolvedCode)
        )
    }
}

struct SaveReferralTarget: Hashable {
    var referralCode: String?
    var handle: String?
    var lens: SaveSocialLens

    var isValid: Bool {
        referralCode?.isEmpty == false || handle?.isEmpty == false
    }

    var previewProfile: SaveReferralProfile {
        SaveReferralProfile.preview(handle: handle, code: referralCode, lens: lens)
    }
}

struct SaveReferralHandoff: Codable, Hashable {
    var referrerId: String
    var handle: String?
    var referralCode: String
    var lens: SaveSocialLens
    var createdAt: Date

    var completionMessage: String {
        "Follow \(handle.map { "@\($0)" } ?? "this Savvy guide") to unlock their starter map pack and first AI itinerary."
    }
}

enum SaveReferralLink {
    static func target(from rawValue: String) -> SaveReferralTarget? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let target = target(from: url) {
            return target
        }
        if !trimmed.contains("://"),
           let url = URL(string: "https://\(trimmed)"),
           let target = target(from: url) {
            return target
        }

        let code = trimmed
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r/"))
        guard !code.isEmpty else { return nil }
        return SaveReferralTarget(referralCode: code, handle: nil, lens: .friends)
    }

    static func target(from url: URL) -> SaveReferralTarget? {
        guard isReferralLink(url) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParts = url.path.split(separator: "/").map(String.init)
        let ref = components?.queryItems?.first(where: { $0.name == "ref" })?.value
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ref
        let lens = components?.queryItems?.first(where: { $0.name == "lens" })?.value.flatMap(SaveSocialLens.init(rawValue:)) ?? .friends

        if pathParts.first == "r", let pathCode = pathParts.dropFirst().first {
            return SaveReferralTarget(referralCode: pathCode, handle: nil, lens: lens)
        }
        if pathParts.first == "u", let handle = pathParts.dropFirst().first {
            return SaveReferralTarget(referralCode: code, handle: handle, lens: lens)
        }
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "referral" {
            let handle = components?.queryItems?.first(where: { $0.name == "handle" })?.value
            return SaveReferralTarget(referralCode: code, handle: handle, lens: lens)
        }
        return nil
    }

    static func profile(from url: URL) -> SaveReferralProfile? {
        target(from: url)?.previewProfile
    }

    static func handoffURL(for profile: SaveReferralProfile) -> URL? {
        var components = URLComponents()
        components.scheme = "wanderly"
        components.host = "referral"
        components.queryItems = [
            URLQueryItem(name: "code", value: profile.referralCode),
            URLQueryItem(name: "handle", value: profile.handle),
            URLQueryItem(name: "lens", value: profile.lens.rawValue),
        ]
        return components.url
    }

    static func isReferralLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "referral" { return true }
        guard url.scheme == "https", ["sav-e-app.vercel.app"].contains(url.host ?? "") else { return false }
        return url.path.hasPrefix("/r/") || url.path.hasPrefix("/u/")
    }
}

final class SaveReferralHandoffStore {
    static let shared = SaveReferralHandoffStore()

    private let storageKey = "save.referralHandoff.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ profile: SaveReferralProfile) {
        let handoff = SaveReferralHandoff(
            referrerId: profile.referrerId,
            handle: profile.handle,
            referralCode: profile.referralCode,
            lens: profile.lens,
            createdAt: Date()
        )
        guard let data = try? JSONEncoder().encode(handoff) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func load() -> SaveReferralHandoff? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(SaveReferralHandoff.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}

extension Place {
    var effectiveVisibility: PlaceVisibility {
        visibility ?? .privateMemory
    }

    var friendSignalText: String? {
        socialSignal?.displayText
    }

    static func socialPreviewSeeds(referrerDisplayName: String, referralCode: String) -> [Place] {
        [
            Place(
                id: UUID(),
                name: "Stereoscope Coffee",
                address: "4542 Beach Blvd, Buena Park, CA",
                latitude: 33.8937,
                longitude: -117.9992,
                category: .cafe,
                status: .wantToGo,
                rating: 4.7,
                note: "Starter map pack from \(referrerDisplayName)",
                sourcePlatform: .other,
                priceRange: "$$",
                recommender: referrerDisplayName,
                googleRating: 4.6,
                createdAt: Date(),
                visibility: .publicGuide,
                socialSignal: PlaceSocialSignal(
                    kind: .referralGuide,
                    lens: .friends,
                    friendNames: [referrerDisplayName],
                    friendCount: 1,
                    saveCount: 42,
                    trendingRank: nil,
                    categoryRank: nil,
                    sourceLabel: referrerDisplayName,
                    referrerId: "ref_\(referralCode)",
                    referralCode: referralCode
                )
            ),
            Place(
                id: UUID(),
                name: "Gem Dining",
                address: "10836 Warner Ave, Fountain Valley, CA",
                latitude: 33.7157,
                longitude: -117.9396,
                category: .food,
                status: .wantToGo,
                rating: 4.5,
                note: "Featured by \(referrerDisplayName)",
                sourcePlatform: .other,
                priceRange: "$$",
                recommender: referrerDisplayName,
                googleRating: 4.5,
                createdAt: Date(),
                visibility: .publicGuide,
                socialSignal: PlaceSocialSignal(
                    kind: .referralGuide,
                    lens: .friends,
                    friendNames: [referrerDisplayName],
                    friendCount: 1,
                    saveCount: 31,
                    trendingRank: nil,
                    categoryRank: nil,
                    sourceLabel: referrerDisplayName,
                    referrerId: "ref_\(referralCode)",
                    referralCode: referralCode
                )
            ),
        ]
    }
}
