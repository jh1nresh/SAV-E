import CoreLocation
import Foundation

/// Drawer chips that filter confirmed Map Stamps without adding park amenities.
enum SaveMapDrawerIntent: String, Hashable, CaseIterable, Identifiable {
    case wantToGo
    case visited
    case nearby

    var id: String { rawValue }

    var accessibilityIdentifier: String {
        "drawer.filter.\(rawValue)"
    }

    var systemImage: String {
        switch self {
        case .wantToGo:
            return "bookmark"
        case .visited:
            return "figure.walk"
        case .nearby:
            return "location"
        }
    }

    func chipLabel(language: AppLanguage) -> String {
        switch self {
        case .wantToGo:
            return language.localized(english: "Want to try", traditionalChinese: "想去")
        case .visited:
            return language.localized(english: "Visited", traditionalChinese: "去過")
        case .nearby:
            return language.localized(english: "Nearby", traditionalChinese: "附近")
        }
    }
}

enum SaveMapIntentFilter {
    static let nearbyRadiusMeters: CLLocationDistance = 2_000

    static func places(
        _ places: [Place],
        categories: Set<PlaceCategory>,
        intents: Set<SaveMapDrawerIntent>,
        nearbyAnchor: CLLocationCoordinate2D?
    ) -> [Place] {
        places.filter { place in
            matches(
                place,
                categories: categories,
                intents: intents,
                nearbyAnchor: nearbyAnchor
            )
        }
    }

    static func matches(
        _ place: Place,
        categories: Set<PlaceCategory>,
        intents: Set<SaveMapDrawerIntent>,
        nearbyAnchor: CLLocationCoordinate2D?
    ) -> Bool {
        if !categories.isEmpty, !categories.contains(place.category) {
            return false
        }

        let statusIntents = intents.intersection([.wantToGo, .visited])
        if !statusIntents.isEmpty {
            let matchesWantToGo = statusIntents.contains(.wantToGo) && place.status == .wantToGo
            let matchesVisited = statusIntents.contains(.visited) && place.status == .visited
            if !matchesWantToGo && !matchesVisited {
                return false
            }
        }

        if intents.contains(.nearby) {
            guard let nearbyAnchor, place.isMapKitMappable else { return false }
            let distance = CLLocation(latitude: nearbyAnchor.latitude, longitude: nearbyAnchor.longitude)
                .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
            if distance > nearbyRadiusMeters {
                return false
            }
        }

        return true
    }
}
