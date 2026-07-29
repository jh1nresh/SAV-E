import SwiftUI

struct AtlasHomeHeroPresentation: Equatable {
    enum Source: Equatable {
        case referenceTokyo
        case currentRegion
        case savedPlace
        case neutral
    }

    enum Scene: Equatable {
        case tokyo
        case taipei
        case regionalMap
    }

    let source: Source
    let scene: Scene
    let title: String
    let subtitle: String
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?

    static let referenceTokyo = AtlasHomeHeroPresentation(
        source: .referenceTokyo,
        scene: .tokyo,
        title: "Tokyo",
        subtitle: "Illustrated city atlas",
        countryCode: "JP",
        latitude: nil,
        longitude: nil
    )

    static let neutral = AtlasHomeHeroPresentation(
        source: .neutral,
        scene: .regionalMap,
        title: "Your place atlas",
        subtitle: "Save a place or enable location to begin",
        countryCode: nil,
        latitude: nil,
        longitude: nil
    )

    static func currentRegion(
        title: String,
        subtitle: String,
        countryCode: String?,
        latitude: Double,
        longitude: Double
    ) -> AtlasHomeHeroPresentation {
        AtlasHomeHeroPresentation(
            source: .currentRegion,
            scene: scene(
                title: title,
                latitude: latitude,
                longitude: longitude
            ),
            title: title,
            subtitle: subtitle,
            countryCode: countryCode,
            latitude: coarse(latitude),
            longitude: coarse(longitude)
        )
    }

    static func savedPlace(
        title: String,
        subtitle: String,
        countryCode: String? = nil,
        latitude: Double,
        longitude: Double
    ) -> AtlasHomeHeroPresentation {
        AtlasHomeHeroPresentation(
            source: .savedPlace,
            scene: scene(
                title: title,
                latitude: latitude,
                longitude: longitude
            ),
            title: title,
            subtitle: subtitle,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude
        )
    }

    private static func coarse(_ value: Double) -> Double {
        (value * 20).rounded() / 20
    }

    private static func scene(
        title: String,
        latitude: Double,
        longitude: Double
    ) -> Scene {
        let normalizedTitle = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        if normalizedTitle.contains("taipei")
            || normalizedTitle.contains("台北")
            || (24.80...25.30).contains(latitude) && (121.30...121.80).contains(longitude) {
            return .taipei
        }

        if normalizedTitle.contains("tokyo")
            || normalizedTitle.contains("東京")
            || (35.45...35.90).contains(latitude) && (139.45...140.05).contains(longitude) {
            return .tokyo
        }

        return .regionalMap
    }
}

struct AtlasPlacePresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let area: String
    let relativeDay: String
    let note: String

    static let shibuyaBackstreets = AtlasPlacePresentation(
        id: "shibuya-backstreets",
        name: "Shibuya Backstreets",
        area: "Shibuya",
        relativeDay: "Today",
        note: "Laneways, tiny counters, and quiet corners."
    )

    static let koffeeMameya = AtlasPlacePresentation(
        id: "koffee-mameya",
        name: "Koffee Mameya",
        area: "Shibuya",
        relativeDay: "Yesterday",
        note: "Cozy coffee shop known for house blend and quiet corners."
    )
}

struct AtlasReviewPresentation: Identifiable, Equatable {
    enum Kind: Equatable {
        case candidate
        case sourceOnly
    }

    let id: String
    let kind: Kind
    let name: String
    let detail: String

    var eyebrow: String {
        kind == .sourceOnly ? "SOURCE CLUE" : "REVIEW CANDIDATE"
    }

    var actionTitle: String {
        kind == .sourceOnly ? "Find exact" : "Review"
    }

    var icon: String {
        kind == .sourceOnly ? "magnifyingglass" : "camera"
    }
}

struct AtlasStopPresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let time: String
    let note: String
    let imageName: String
    let imageHeight: CGFloat
}

struct AtlasTripSummaryPresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let city: String
    let dateRange: String
    let stopCount: Int
    let timing: String
}

struct AtlasPresentation: @unchecked Sendable {
    var homeHero: AtlasHomeHeroPresentation
    var reviewCount: Int
    var mapStampCount: Int
    var failedCount: Int
    var tripName: String
    var tripDayCount: Int
    var selectedDay: Int
    var tripCity: String
    var tripDateLabel: String
    var tripStops: [AtlasStopPresentation]
    var recentPlaces: [AtlasPlacePresentation]
    var reviewItems: [AtlasReviewPresentation]
    var selectedMapPlace: AtlasPlacePresentation
    var tripSummaries: [AtlasTripSummaryPresentation]
    var onCapture: () -> Void
    var onReviewAll: () -> Void
    var onOpenTrip: () -> Void
    var onOpenSaves: () -> Void
    var onOpenPlace: (String) -> Void
    var onOpenReview: (String) -> Void
    var onSelectReview: () -> Void
    var onSelectMapStamps: () -> Void
    var onSelectDay: (Int) -> Void
    var onOpenStop: (String) -> Void
    var onAddStop: () -> Void
    var onOpenTripID: (String) -> Void
    var onCreateTrip: () -> Void
    var onOpenAssistant: () -> Void

    static let reference = AtlasPresentation(
        homeHero: .referenceTokyo,
        reviewCount: 3,
        mapStampCount: 18,
        failedCount: 2,
        tripName: "Tokyo Weekend",
        tripDayCount: 3,
        selectedDay: 2,
        tripCity: "Tokyo",
        tripDateLabel: "TUESDAY, OCTOBER 13",
        tripStops: [
            AtlasStopPresentation(
                id: "tsukiji",
                name: "Tsukiji Outer Market",
                time: "9:00 AM",
                note: "Seafood stalls & breakfast",
                imageName: "TsukijiThumbnail",
                imageHeight: 78
            ),
            AtlasStopPresentation(
                id: "koffee-mameya",
                name: "Koffee Mameya",
                time: "11:30 AM",
                note: "Coffee & people watching",
                imageName: "KoffeeMameyaThumbnail",
                imageHeight: 82
            ),
            AtlasStopPresentation(
                id: "teamlab",
                name: "teamLab Borderless",
                time: "2:30 PM",
                note: "Immersive digital art",
                imageName: "TeamLabThumbnail",
                imageHeight: 83
            ),
            AtlasStopPresentation(
                id: "shibuya-sky",
                name: "Shibuya Sky",
                time: "6:30 PM",
                note: "Sunset city views",
                imageName: "ShibuyaSkyThumbnail",
                imageHeight: 84
            ),
        ],
        recentPlaces: [.shibuyaBackstreets, .koffeeMameya],
        reviewItems: [
            AtlasReviewPresentation(
                id: "tsukiji",
                kind: .candidate,
                name: "Tsukiji Outer Market",
                detail: "From Xiaohongshu"
            ),
            AtlasReviewPresentation(
                id: "koffee-mameya",
                kind: .candidate,
                name: "Koffee Mameya",
                detail: "From Instagram"
            ),
            AtlasReviewPresentation(
                id: "yasaka-pagoda",
                kind: .sourceOnly,
                name: "Yasaka Pagoda",
                detail: "Missing exact place"
            ),
        ],
        selectedMapPlace: .koffeeMameya,
        tripSummaries: [
            AtlasTripSummaryPresentation(
                id: "tokyo-weekend",
                name: "Tokyo Weekend",
                city: "Tokyo",
                dateRange: "Oct 12 – 14",
                stopCount: 4,
                timing: "CURRENT"
            ),
            AtlasTripSummaryPresentation(
                id: "kyoto-autumn",
                name: "Kyoto Autumn",
                city: "Kyoto",
                dateRange: "Nov 7 – 10",
                stopCount: 6,
                timing: "UPCOMING"
            ),
            AtlasTripSummaryPresentation(
                id: "taipei-night-notes",
                name: "Taipei Night Notes",
                city: "Taipei",
                dateRange: "Dates to decide",
                stopCount: 3,
                timing: "PLANNING"
            ),
        ],
        onCapture: {},
        onReviewAll: {},
        onOpenTrip: {},
        onOpenSaves: {},
        onOpenPlace: { _ in },
        onOpenReview: { _ in },
        onSelectReview: {},
        onSelectMapStamps: {},
        onSelectDay: { _ in },
        onOpenStop: { _ in },
        onAddStop: {},
        onOpenTripID: { _ in },
        onCreateTrip: {},
        onOpenAssistant: {}
    )
}

private struct AtlasPresentationKey: EnvironmentKey {
    static let defaultValue = AtlasPresentation.reference
}

extension EnvironmentValues {
    var atlasPresentation: AtlasPresentation {
        get { self[AtlasPresentationKey.self] }
        set { self[AtlasPresentationKey.self] = newValue }
    }
}
