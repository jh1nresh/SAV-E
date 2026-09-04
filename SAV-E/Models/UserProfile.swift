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
    case markVisitedStamp = "mark_visited_stamp"
    case shareRecommendation = "share_recommendation"
    case inviteOrFollowFriend = "invite_or_follow_friend"

    var accessibilityIdentifier: String {
        switch self {
        case .confirmWaitingClue:
            return "profile.today.confirmWaitingClue"
        case .markVisitedStamp:
            return "profile.today.markVisitedStamp"
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

    /// Order is confirm → mark visited (return) → share → invite, capped at three.
    static func missions(
        waitingClues: Int,
        savedPlaces: [Place],
        followedFriends: [SaveFollowedFriend],
        hasSharedInvite: Bool,
        inviteURLAvailable: Bool
    ) -> [SavePassportTodayMission] {
        var result: [SavePassportTodayMission] = []
        if waitingClues >= 1 {
            result.append(SavePassportTodayMission(id: .confirmWaitingClue))
        }
        if firstVisitEligiblePlace(in: savedPlaces) != nil {
            result.append(SavePassportTodayMission(id: .markVisitedStamp))
        }
        if firstShareEligiblePlace(in: savedPlaces) != nil {
            result.append(SavePassportTodayMission(id: .shareRecommendation))
        }
        // Friends empty always qualifies. "Never shared invite" only
        // qualifies when an invite URL actually exists to share.
        if followedFriends.isEmpty || (!hasSharedInvite && inviteURLAvailable) {
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

    /// Prefer an unvisited Map Stamp so the return quest stays a real memory action.
    static func firstVisitEligiblePlace(in places: [Place]) -> Place? {
        places.first { $0.status == .wantToGo }
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


// MARK: - Field streak

/// Local consecutive-day ledger for real memory actions only:
/// confirm a waiting clue, save a Map Stamp, or mark Visited.
/// Not a login check-in, not XP, and not a grant path.
final class SavePassportFieldStreakStore {
    static let shared = SavePassportFieldStreakStore()

    private let storageKey = "save.passport.fieldStreak.days.v1"
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        // Keep the caller's calendar/time zone so tests can pin GMT and
        // production can keep the user's current calendar unchanged.
        self.calendar = calendar
    }

    /// Day keys are `yyyy-MM-dd` in the user's current calendar/time zone.
    private(set) var actionDayKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: storageKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: storageKey) }
    }

    var hasFieldActionToday: Bool {
        actionDayKeys.contains(dayKey(for: Date()))
    }

    /// Consecutive days ending today, or yesterday if today is still empty.
    var currentStreak: Int {
        let today = dayKey(for: Date())
        let keys = actionDayKeys
        guard !keys.isEmpty else { return 0 }

        let startKey: String
        if keys.contains(today) {
            startKey = today
        } else if let yesterday = dateOffset(-1), keys.contains(dayKey(for: yesterday)) {
            startKey = dayKey(for: yesterday)
        } else {
            return 0
        }

        var streak = 0
        var cursor = date(fromDayKey: startKey)
        while let cursor, keys.contains(dayKey(for: cursor)) {
            streak += 1
            cursor = dateOffset(-1, from: cursor)
        }
        return streak
    }

    @discardableResult
    func recordFieldAction(at date: Date = Date()) -> Bool {
        let key = dayKey(for: date)
        var keys = actionDayKeys
        let inserted = keys.insert(key).inserted
        if inserted {
            // Keep a bounded local history (about a year).
            let trimmed = keys.sorted().suffix(400)
            actionDayKeys = Set(trimmed)
        }
        return inserted
    }

    private func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func dateOffset(_ days: Int, from date: Date = Date()) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
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
