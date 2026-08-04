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
        case newYork
        case shanghai
        case beijing
        case guangzhou
        case shenzhen
        case chengdu
        case chongqing
        case tianjin
        case hangzhou
        case nanjing
        case wuhan
        case xian
        case suzhou
        case qingdao
        case xiamen
        case changsha
        case seoul
        case southernCalifornia
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

        if normalizedTitle.contains("new york")
            || normalizedTitle.contains("nyc")
            || normalizedTitle.contains("紐約")
            || normalizedTitle.contains("纽约")
            || (40.45...40.95).contains(latitude) && (-74.30 ... -73.65).contains(longitude) {
            return .newYork
        }

        if normalizedTitle.contains("suzhou")
            || normalizedTitle.contains("蘇州")
            || normalizedTitle.contains("苏州")
            || (30.95...31.65).contains(latitude) && (120.40...120.85).contains(longitude) {
            return .suzhou
        }

        if normalizedTitle.contains("shanghai")
            || normalizedTitle.contains("上海")
            || (30.85...31.55).contains(latitude) && (120.85...121.95).contains(longitude) {
            return .shanghai
        }

        if normalizedTitle.contains("beijing")
            || normalizedTitle.contains("peking")
            || normalizedTitle.contains("北京")
            || (39.45...40.35).contains(latitude) && (115.70...117.40).contains(longitude) {
            return .beijing
        }

        if normalizedTitle.contains("guangzhou")
            || normalizedTitle.contains("canton")
            || normalizedTitle.contains("廣州")
            || normalizedTitle.contains("广州")
            || (22.95...23.55).contains(latitude) && (113.15...113.70).contains(longitude) {
            return .guangzhou
        }

        if normalizedTitle.contains("shenzhen")
            || normalizedTitle.contains("深圳")
            || (22.35...22.85).contains(latitude) && (113.75...114.65).contains(longitude) {
            return .shenzhen
        }

        if normalizedTitle.contains("chengdu")
            || normalizedTitle.contains("成都")
            || (30.20...31.00).contains(latitude) && (103.60...104.60).contains(longitude) {
            return .chengdu
        }

        if normalizedTitle.contains("chongqing")
            || normalizedTitle.contains("重慶")
            || normalizedTitle.contains("重庆")
            || (29.25...30.10).contains(latitude) && (106.15...107.10).contains(longitude) {
            return .chongqing
        }

        if normalizedTitle.contains("tianjin")
            || normalizedTitle.contains("天津")
            || (38.55...39.40).contains(latitude) && (116.70...117.90).contains(longitude) {
            return .tianjin
        }

        if normalizedTitle.contains("hangzhou")
            || normalizedTitle.contains("杭州")
            || (29.85...30.55).contains(latitude) && (119.80...120.60).contains(longitude) {
            return .hangzhou
        }

        if normalizedTitle.contains("nanjing")
            || normalizedTitle.contains("南京")
            || (31.65...32.45).contains(latitude) && (118.30...119.25).contains(longitude) {
            return .nanjing
        }

        if normalizedTitle.contains("wuhan")
            || normalizedTitle.contains("武漢")
            || normalizedTitle.contains("武汉")
            || (30.25...30.95).contains(latitude) && (113.75...114.90).contains(longitude) {
            return .wuhan
        }

        if normalizedTitle.contains("xi'an")
            || normalizedTitle.contains("xi’an")
            || normalizedTitle.contains("xian")
            || normalizedTitle.contains("西安")
            || (33.75...34.60).contains(latitude) && (108.45...109.50).contains(longitude) {
            return .xian
        }

        if normalizedTitle.contains("qingdao")
            || normalizedTitle.contains("青島")
            || normalizedTitle.contains("青岛")
            || (35.75...36.45).contains(latitude) && (119.70...120.80).contains(longitude) {
            return .qingdao
        }

        if normalizedTitle.contains("xiamen")
            || normalizedTitle.contains("廈門")
            || normalizedTitle.contains("厦门")
            || (24.20...24.85).contains(latitude) && (117.75...118.55).contains(longitude) {
            return .xiamen
        }

        if normalizedTitle.contains("changsha")
            || normalizedTitle.contains("長沙")
            || normalizedTitle.contains("长沙")
            || (27.85...28.55).contains(latitude) && (112.55...113.35).contains(longitude) {
            return .changsha
        }

        if normalizedTitle.contains("seoul")
            || normalizedTitle.contains("서울")
            || normalizedTitle.contains("首爾")
            || normalizedTitle.contains("首尔")
            || (37.35...37.75).contains(latitude) && (126.75...127.25).contains(longitude) {
            return .seoul
        }

        if normalizedTitle.contains("los angeles")
            || normalizedTitle.contains("orange county")
            || normalizedTitle.contains("tustin")
            || normalizedTitle.contains("irvine")
            || normalizedTitle.contains("anaheim")
            || normalizedTitle.contains("santa ana")
            || normalizedTitle.contains("newport beach")
            || normalizedTitle.contains("costa mesa")
            || normalizedTitle.contains("huntington beach")
            || normalizedTitle.contains("laguna beach")
            || normalizedTitle.contains("long beach")
            || normalizedTitle.contains("洛杉磯")
            || normalizedTitle.contains("洛杉矶")
            || normalizedTitle.contains("橙縣")
            || normalizedTitle.contains("橙县")
            || (33.25...34.35).contains(latitude) && (-118.95 ... -117.30).contains(longitude) {
            return .southernCalifornia
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

struct AtlasHomePriorityPresentation: Equatable {
    enum Kind: Equatable {
        case currentTrip
        case upcomingTrip
        case planFromStamps
        case capture
    }

    let kind: Kind
    let eyebrow: String
    let title: String
    let detail: String
    let badge: String?
    let systemName: String
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
    var homePriority: AtlasHomePriorityPresentation
    var recentPlaces: [AtlasPlacePresentation]
    var reviewItems: [AtlasReviewPresentation]
    var selectedMapPlace: AtlasPlacePresentation
    var tripSummaries: [AtlasTripSummaryPresentation]
    var onCapture: () -> Void
    var onReviewAll: () -> Void
    var onOpenHomeHero: () -> Void
    var onOpenHomePriority: () -> Void
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
    var onOpenPassport: () -> Void
    // Trips P1: the ask entry is a real input; submit carries the typed
    // question into the expanding ask surface.
    var onAskSubmit: (String) -> Void = { _ in }

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
        homePriority: AtlasHomePriorityPresentation(
            kind: .currentTrip,
            eyebrow: "CONTINUE TODAY",
            title: "Tokyo Weekend",
            detail: "Next stop: Tsukiji Outer Market · 9:00 AM",
            badge: "Day 2 of 3",
            systemName: "point.3.connected.trianglepath.dotted"
        ),
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
        onOpenHomeHero: {},
        onOpenHomePriority: {},
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
        onOpenAssistant: {},
        onOpenPassport: {}
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
