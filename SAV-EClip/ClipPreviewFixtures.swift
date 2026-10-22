import Foundation

enum ClipPreviewFixtures {
    static func requestedScreen() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--uitest-clip-screen"),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        return nil
    }

    static func samplePlace() -> SharedPlaceData {
        SharedPlaceData(
            id: "quarter-sheets-pizza-club",
            name: "Quarter Sheets Pizza Club",
            address: "1305 Portia St, Los Angeles, CA 90026",
            lat: 34.0779,
            lng: -118.2543,
            category: "Food",
            rating: 4.6,
            reviewCount: 412,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: "https://maps.apple.com/",
            photoURLs: [],
            note: "Save this for a slow dinner night"
        )
    }

    static func sampleList() -> SharedListData {
        SharedListData(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            title: "Tokyo cafes",
            note: nil,
            ownerDisplayName: "Mina",
            viewerRole: "viewer",
            items: [
                listItem(id: "1", source: "savedPlace", title: "Onibus Coffee", subtitle: "Nakameguro", category: "Cafe", lat: 35.644, lng: 139.699),
                listItem(id: "2", source: "savedPlace", title: "Katsu Midori", subtitle: "Shinjuku", category: "Food", lat: 35.690, lng: 139.700),
                listItem(id: "3", source: "mapCandidate", title: "Senso-ji", subtitle: "Asakusa", category: "Attraction", lat: 35.715, lng: 139.797),
                listItem(id: "4", source: "savedPlace", title: "Blue Bottle", subtitle: "Kiyosumi", category: "Cafe", lat: 35.682, lng: 139.798),
                listItem(id: "5", source: "savedPlace", title: "Tsukiji Outer Market", subtitle: "Tsukiji", category: "Food", lat: 35.665, lng: 139.770),
            ],
            createdAt: Date(timeIntervalSince1970: 812_505_600),
            updatedAt: Date(timeIntervalSince1970: 812_505_600)
        )
    }

    private static func listItem(
        id: String,
        source: String,
        title: String,
        subtitle: String,
        category: String,
        lat: Double,
        lng: Double
    ) -> SharedListItem {
        SharedListItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-11111111111\(id)") ?? UUID(),
            source: source,
            sourceID: "place\(id)",
            title: title,
            subtitle: subtitle,
            latitude: lat,
            longitude: lng,
            category: category,
            rating: nil,
            reviewCount: nil,
            sourceURL: nil,
            photoURLs: [],
            note: nil,
            addedByDisplayName: "Mina",
            addedAt: Date(timeIntervalSince1970: 812_505_600),
            coordinateSystem: nil,
            locationProvider: nil,
            providerMapUrl: nil
        )
    }
}
