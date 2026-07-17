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
    var petPreset: SavePetPreset?
    var petName: String?
    var petXP: Int

    var petStage: SavePetStage {
        SavePetStage(xp: petXP)
    }
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

// MARK: - Mock Data

extension UserProfile {
    static let empty = UserProfile(
        id: "local-user",
        displayName: "SAV-E User",
        email: nil,
        avatarUrl: nil,
        savedCount: 0,
        visitedCount: 0,
        citiesCount: 0,
        isPremium: false,
        collections: [],
        createdAt: Date(),
        petPreset: nil,
        petName: nil,
        petXP: 0
    )

    static let mock = UserProfile(
        id: "mock-user",
        displayName: "SAV-E User",
        email: "user@example.com",
        avatarUrl: nil,
        savedCount: 42,
        visitedCount: 18,
        citiesCount: 7,
        isPremium: false,
        collections: PlaceCollection.mockList,
        createdAt: Date().addingTimeInterval(-86400 * 90),
        petPreset: .sprout,
        petName: "Memo",
        petXP: 40
    )
}

extension PlaceCollection {
    static let mockList: [PlaceCollection] = [
        PlaceCollection(id: UUID(), name: "Date Night", placeIds: [], emoji: "🌙"),
        PlaceCollection(id: UUID(), name: "Brunch Spots", placeIds: [], emoji: "🥞"),
        PlaceCollection(id: UUID(), name: "Hidden Gems", placeIds: [], emoji: "💎"),
    ]
}
