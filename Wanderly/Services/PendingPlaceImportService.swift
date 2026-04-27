import Foundation

enum WanderlySharedStorage {
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let pendingPlacesKey = "pendingPlaces"
}

struct PendingSharedPlace: Codable {
    var name: String
    var address: String
    var category: String
    var latitude: Double
    var longitude: Double
    var dishes: [String]
    var priceRange: String?
    var sourceURL: String?
    var sourceText: String?
    var savedAt: Date
}

final class PendingPlaceImportService {
    static let shared = PendingPlaceImportService()

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: WanderlySharedStorage.appGroupSuiteName)) {
        self.defaults = defaults
    }

    func consumePendingPlaces() -> [PendingSharedPlace] {
        guard let defaults else { return [] }
        let pending = loadPendingPlaces()
        defaults.removeObject(forKey: WanderlySharedStorage.pendingPlacesKey)
        return pending
    }

    func restorePendingPlaces(_ places: [PendingSharedPlace]) {
        guard !places.isEmpty else { return }
        let existing = loadPendingPlaces()
        save(existing + places)
    }

    private func loadPendingPlaces() -> [PendingSharedPlace] {
        guard let defaults else { return [] }
        guard let data = defaults.data(forKey: WanderlySharedStorage.pendingPlacesKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingSharedPlace].self, from: data)) ?? []
    }

    private func save(_ places: [PendingSharedPlace]) {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: WanderlySharedStorage.pendingPlacesKey)
    }
}
