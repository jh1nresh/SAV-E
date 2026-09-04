import Foundation

struct UserProfile: Identifiable, Codable {
    let id: String
    var displayName: String
    var email: String?
    var avatarUrl: String?
    var savedCount: Int
    var visitedCount: Int
    var citiesCount: Int
    var isPremium: Bool
    var collections: [PlaceCollection]
    var createdAt: Date
}

struct PassportStats: Hashable {
    var savedCount: Int
    var visitedCount: Int
    var proofBackedCount: Int
    var citiesCount: Int
    var waitingClues: Int
    var cityNames: [String]
    var usesSavedPlaces: Bool

    init(profile: UserProfile, savedPlaces: [Place], waitingClues: Int) {
        self.waitingClues = waitingClues
        proofBackedCount = 0

        guard !savedPlaces.isEmpty else {
            savedCount = profile.savedCount
            visitedCount = profile.visitedCount
            citiesCount = profile.citiesCount
            cityNames = []
            usesSavedPlaces = false
            return
        }

        savedCount = savedPlaces.count
        visitedCount = savedPlaces.filter { $0.status == .visited }.count
        cityNames = Self.uniqueCityNames(from: savedPlaces)
        citiesCount = cityNames.count
        usesSavedPlaces = true
    }

    private static func uniqueCityNames(from places: [Place]) -> [String] {
        var seen = Set<String>()
        return places
            .compactMap(cityName)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func cityName(for place: Place) -> String? {
        if let value = cityLevelName(in: place.address) {
            return value
        }
        let value = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value
    }

    private static func cityLevelName(in address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let taiwanCities = [
            "臺北市", "台北市", "新北市", "桃園市", "臺中市", "台中市", "臺南市", "台南市", "高雄市",
            "基隆市", "新竹市", "嘉義市", "新竹縣", "苗栗縣", "彰化縣", "南投縣", "雲林縣", "嘉義縣",
            "屏東縣", "宜蘭縣", "花蓮縣", "臺東縣", "台東縣", "澎湖縣", "金門縣", "連江縣"
        ]
        return taiwanCities.first { value.contains($0) }
    }
}

struct PlaceCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var placeIds: [UUID]
    var emoji: String
}

// MARK: - Today on Savvy

/// Fixed mission catalog for the Passport "Today on Savvy" strip.
/// Live incomplete rows only. The strip hides when this list is empty.
enum SavePassportTodayMissionID: String, CaseIterable, Equatable {
    case confirmWaitingClue = "confirm_waiting_clue"
    case shareRecommendation = "share_recommendation"
    case inviteOrFollowFriend = "invite_or_follow_friend"

    var accessibilityIdentifier: String {
        switch self {
        case .confirmWaitingClue:
            return "profile.today.confirmWaitingClue"
        case .shareRecommendation:
            return "profile.today.shareRecommendation"
        case .inviteOrFollowFriend:
            return "profile.today.inviteFriend"
        }
    }
}

struct SavePassportTodayMission: Equatable, Identifiable {
    let id: SavePassportTodayMissionID
}

enum SavePassportTodayCatalog {
    static let missionCap = 3

    /// Order is confirm → share → invite, capped at three.
    static func missions(
        waitingClues: Int,
        savedPlaces: [Place],
        followedFriends: [SaveFollowedFriend],
        hasSharedInvite: Bool
    ) -> [SavePassportTodayMission] {
        var result: [SavePassportTodayMission] = []
        if waitingClues >= 1 {
            result.append(SavePassportTodayMission(id: .confirmWaitingClue))
        }
        if firstShareEligiblePlace(in: savedPlaces) != nil {
            result.append(SavePassportTodayMission(id: .shareRecommendation))
        }
        if followedFriends.isEmpty || !hasSharedInvite {
            result.append(SavePassportTodayMission(id: .inviteOrFollowFriend))
        }
        return Array(result.prefix(missionCap))
    }

    /// Prefer the first private Map Stamp; otherwise the first stamp that is
    /// not already in the Origin-consumed shareable-recommendation state.
    static func firstShareEligiblePlace(in places: [Place]) -> Place? {
        if let privateStamp = places.first(where: { $0.effectiveVisibility == .privateMemory }) {
            return privateStamp
        }
        return places.first { !$0.effectiveVisibility.allowsTrendingSignal }
    }
}

/// Local flag for "never shared invite". Not a grant path and not commerce.
final class SavePassportInviteShareStore {
    static let shared = SavePassportInviteShareStore()

    private let storageKey = "save.passport.inviteShared.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSharedInvite: Bool {
        defaults.bool(forKey: storageKey)
    }

    func markShared() {
        defaults.set(true, forKey: storageKey)
    }
}

// MARK: - Mock Data

extension UserProfile {
    static let empty = UserProfile(
        id: "local-user",
        displayName: "Savvy User",
        email: nil,
        avatarUrl: nil,
        savedCount: 0,
        visitedCount: 0,
        citiesCount: 0,
        isPremium: false,
        collections: [],
        createdAt: Date()
    )

    static let mock = UserProfile(
        id: "mock-user",
        displayName: "Savvy User",
        email: "user@example.com",
        avatarUrl: nil,
        savedCount: 42,
        visitedCount: 18,
        citiesCount: 7,
        isPremium: false,
        collections: PlaceCollection.mockList,
        createdAt: Date().addingTimeInterval(-86400 * 90)
    )
}

extension PlaceCollection {
    static let mockList: [PlaceCollection] = [
        PlaceCollection(id: UUID(), name: "Date Night", placeIds: [], emoji: "🌙"),
        PlaceCollection(id: UUID(), name: "Brunch Spots", placeIds: [], emoji: "🥞"),
        PlaceCollection(id: UUID(), name: "Hidden Gems", placeIds: [], emoji: "💎"),
    ]
}
