import CoreLocation
import Foundation
import SwiftUI

/// HoP 2026-10-19: Passport v1 is the sticker grid, city list, and Collected.
/// Today missions, field streak, and the stamp ledger stay compiled but off
/// the root. Connections and posts live on the Collected sub-page.
nonisolated enum SaveDoodlePassportFlags: Sendable {
    static let showTodayMissions = false
    static let showFieldStreak = false
    static let showStampLedger = false
}

enum SavePassportStampRank: Int, Comparable, CaseIterable {
    case none = 0
    case single = 1
    case double = 3
    case gold = 5

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(visitCount: Int) -> SavePassportStampRank {
        if visitCount >= 5 { return .gold }
        if visitCount >= 3 { return .double }
        if visitCount >= 1 { return .single }
        return .none
    }
}

/// Local visit counts so a «我來過了» tap can climb 1 → 3 → 5 without a
/// new Place field. Shared leftovers keep `Place.status == .visited`.
@MainActor
final class SavePassportVisitStore {
    static let shared = SavePassportVisitStore()

    private let history: SaveDoodleVisitStore

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        history = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: now)
    }

    func count(for id: UUID) -> Int { history.count(for: id) }

    @discardableResult
    func recordVisit(for id: UUID) -> Int {
        history.recordVisit(for: id)
        return count(for: id)
    }

    func rank(for id: UUID, visited: Bool) -> SavePassportStampRank {
        SavePassportStampRank.from(visitCount: max(count(for: id), visited ? 1 : 0))
    }

    static func key(_ id: UUID) -> String { SaveDoodleVisitStore.countKey(id) }
}

enum SaveDoodleStickerKind: String, CaseIterable, Equatable {
    case duck, noodles, coffee, tea, baozi, dessert
    case wine, beer, temple, tree, hill, lantern
    case museum, bag, bookstore, beach, bridge, camera, hotpot, pin
    case bicycle, ferris
}

struct SaveDoodlePassportSlot: Identifiable, Equatable {
    enum Content: Equatable {
        case place(Place, SaveDoodleStickerKind, SavePassportStampRank)
        case empty(index: Int)
    }

    let id: String
    let content: Content
    var stampNumber: Int? = nil

    var place: Place? {
        if case let .place(place, _, _) = content { return place }
        return nil
    }

    var isVisited: Bool {
        if case let .place(_, _, rank) = content { return rank != .none }
        return false
    }
}

enum SaveDoodlePassportCatalog {
    static let maxColumnCount = 4
    static let minColumnCount = 1
    static let pageSize = 12

    /// DESIGN target 402×874 (PR #297 diagnosis, 2026-10-25). Absolute
    /// canvas points. Founder chose the measured target over spec §7.3.
    static let screenMargin: CGFloat = 16
    static let panelLeading: CGFloat = 16
    static let panelWidth: CGFloat = 370
    static let panelHeight: CGFloat = 496
    static let panelTop: CGFloat = 158
    static let panelCornerRadius: CGFloat = 12
    static let panelStrokeWidth: CGFloat = 1
    static let panelPadding: CGFloat = 16
    static let unvisitedDiscSize: CGFloat = 75
    static let visitedStickerSize = CGSize(width: 80, height: 76)
    static let unvisitedArtSize: CGFloat = 44
    static let slotSize: CGFloat = unvisitedDiscSize
    static let cardHeight: CGFloat = 80
    static let columnCenters: [CGFloat] = [70.5, 158, 245.5, 331]
    static let rowCenters: [CGFloat] = [212, 336.5, 461]
    static let columnStride: CGFloat = 87.5
    static let rowStride: CGFloat = 124.5
    static let minColumnGap: CGFloat = 12.5
    static let rowGap: CGFloat = 49.5
    static let stampDiameter: CGFloat = 28
    static let stampOffset = CGSize(width: 22, height: 26.5)
    static let titleLeading: CGFloat = 24
    static let titleBaseline: CGFloat = 106
    static let titlePointSize: CGFloat = 64
    static let titleAscent: CGFloat = 61.44
    static let titleTopPadding: CGFloat = 44.56
    static let subtitleLeading: CGFloat = 28
    static let subtitleBaseline: CGFloat = 138
    static let subtitlePointSize: CGFloat = 22
    static let subtitleAscent: CGFloat = 21.12
    static let subtitleTopPadding: CGFloat = 116.88
    static let legendSwatchSize: CGFloat = 9

    static let panelFillLightHex = "E9DCC3"
    static let panelStrokeLightHex = "C9BBA2"
    static let panelFillDarkHex = "4A3F32"
    static let panelStrokeDarkHex = "5A5246"
    static let discFillLightHex = "F6F0E6"
    static let discFillDarkHex = "3A332A"
    static let stampBaseLightHex = "FAF7F1"
    static let stampBaseDarkHex = "2A2620"
    static let stampRingRedHex = "B3534A"
    static let stampRingGoldHex = "C19349"
    static let legendSwatchHex = "D85A3B"

    /// `columns = floor((availableGridWidth + 12.5) / 87.5)`, clamped 1...4.
    /// 375/390 physical → 3; 402/430 physical → 4.
    static func columnCount(availableGridWidth: CGFloat) -> Int {
        let raw = Int(floor((availableGridWidth + minColumnGap) / columnStride))
        return min(maxColumnCount, max(minColumnCount, raw))
    }

    /// ReferenceViewport always proposes the 402pt canvas. Width UI tests
    /// still boot real 375/390 devices and expect 3 columns, so clamp the
    /// measured canvas grid to the physical screen minus 16+16 insets.
    static func columnCount(measuredGridWidth: CGFloat, physicalScreenWidth: CGFloat) -> Int {
        let inset = screenMargin * 2 + panelPadding * 2
        let physicalGrid = physicalScreenWidth - inset
        let width: CGFloat
        if measuredGridWidth > 0 {
            width = min(measuredGridWidth, max(physicalGrid, 0))
        } else if physicalGrid > 0 {
            width = physicalGrid
        } else {
            width = panelWidth - panelPadding * 2
        }
        return columnCount(availableGridWidth: width)
    }

    static func columnCenterX(_ column: Int, columns: Int) -> CGFloat {
        if columns == maxColumnCount, column >= 0, column < columnCenters.count {
            return columnCenters[column]
        }
        return columnCenters[0] + CGFloat(column) * columnStride
    }

    static func rowCenterY(_ row: Int) -> CGFloat {
        rowCenters[0] + CGFloat(row) * rowStride
    }

    static func panelPoint(column: Int, row: Int, columns: Int) -> CGPoint {
        CGPoint(
            x: columnCenterX(column, columns: columns) - panelLeading,
            y: rowCenterY(row) - panelTop
        )
    }

    /// Isolated screenshot face for `five-tab-passport`. Production never
    /// sets this argument, so live Passport still reads the user's places.
    static var usesDoodleFace: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-doodle-passport-face")
#else
        false
#endif
    }

    static let doodleFaceCityTitle = "Beijing"
    static let doodleFaceVisitedLine = "4 of 12 visited"
    static let doodleFaceCitiesLine = "Cities: Beijing 23 · Tokyo 9"

    static func doodleFaceSlots() -> [SaveDoodlePassportSlot] {
        let items: [(String, PlaceCategory, SaveDoodleStickerKind, SavePassportStampRank)] = [
            ("Siji Minfu Roast Duck", .food, .duck, .single),
            ("Fangzhuangchang Noodles", .food, .noodles, .single),
            ("Temple of Heaven", .attraction, .temple, .double),
            ("Lantern Alley", .attraction, .lantern, .gold),
            ("Grey Cafe", .cafe, .coffee, .none),
            ("Jingshan", .attraction, .hill, .none),
            ("Houhai Bridge", .attraction, .bridge, .none),
            ("Baozi Shop", .food, .baozi, .none),
            ("Maliandao Tea", .cafe, .tea, .none),
            ("Page One", .shopping, .bookstore, .none),
            ("Houhai Bicycle", .attraction, .bicycle, .none),
            ("Chaoyang Park Wheel", .attraction, .ferris, .none),
        ]
        let stampNumbers: [Int?] = [1, 2, 3, 3, nil, nil, nil, nil, nil, nil, nil, nil]
        return items.enumerated().map { index, item in
            let id = UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!
            let place = Place(
                id: id,
                name: item.0,
                address: "Beijing, China",
                latitude: 39.88,
                longitude: 116.40,
                category: item.1,
                status: item.3 == .none ? .wantToGo : .visited,
                sourcePlatform: .other,
                createdAt: Date(timeIntervalSince1970: 1_724_000_000 - Double(index))
            )
            return SaveDoodlePassportSlot(
                id: id.uuidString,
                content: .place(place, item.2, item.3),
                stampNumber: stampNumbers[index]
            )
        }
    }

    static func goal(for savedCount: Int) -> Int {
        SaveTileTownProductLock.passportGoal(for: savedCount)
    }

    static func progress(
        in places: [Place], collectionMode: SavePassportCollectionMode
    ) -> (visited: Int, total: Int) {
        switch collectionMode {
        case .homeCollected:
            let progress = SaveDoodleHomeProgressCatalog.progress(in: places)
            return (progress.visited, progress.saved)
        case .collection:
            return (visitedCount(in: places), goal(for: max(places.count, 1)))
        }
    }

    /// An explicitly selected city remains selected after its final save is removed.
    /// Keep the label and picker aligned with the empty grid's scope.
    static func resolvedSelection(
        _ selection: SaveDoodleCitySelection,
        places: [Place],
        locationDenied: Bool
    ) -> SaveDoodleCitySelection {
        if case .city = selection { return selection }
        return SaveDoodleHomeCatalog.resolvedSelection(
            selection, places: places, locationDenied: locationDenied
        )
    }

    static func pickerCityGroups(
        from places: [Place],
        selection: SaveDoodleCitySelection
    ) -> [SaveDoodleCityGroup] {
        let groups = SaveDoodleHomeCatalog.cityGroups(from: places)
        guard case .city(let id) = selection,
              !groups.contains(where: { $0.id == id }) else { return groups }
        return groups + [SaveDoodleCityGroup(
            id: id,
            englishName: SaveHomeSearch.cityLabel(for: id, traditionalChinese: false) ?? id,
            chineseName: SaveHomeSearch.cityLabel(for: id, traditionalChinese: true) ?? id,
            count: 0
        )]
    }

    static func cityPlaces(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation? = nil,
        locationDenied: Bool
    ) -> [Place] {
        let scoped = SaveDoodleHomeProgressCatalog.cityPlaces(
            from: places,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
        // Home remaps a vanished city to the newest save. Passport must
        // keep an explicit empty city empty — never expand worldwide.
        if case .city(let id) = selection {
            return scoped.filter { SaveDoodleHomeCatalog.cityID(for: $0) == id }
        }
        return scoped
    }

    static func visitedCount(in places: [Place]) -> Int {
        SaveDoodleHomeProgressCatalog.visitedCount(in: places)
    }

    static func slots(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation? = nil,
        locationDenied: Bool,
        visitStore: SavePassportVisitStore
    ) -> [SaveDoodlePassportSlot] {
        let scoped = cityPlaces(
            from: places,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
        let city = scoped
        if city.isEmpty { return [] }
        let goal = Self.goal(for: max(city.count, 1))
        let visible = Array(city.prefix(goal))
        var result: [SaveDoodlePassportSlot] = visible.map { place in
            let kind = stickerKind(for: place)
            let rank = visitStore.rank(for: place.id, visited: place.status == .visited)
            return SaveDoodlePassportSlot(
                id: place.id.uuidString,
                content: .place(place, kind, rank),
                stampNumber: rank == .none ? nil : rank.rawValue
            )
        }
        if result.count < goal {
            for index in result.count..<goal {
                result.append(
                    SaveDoodlePassportSlot(id: "empty.\(index)", content: .empty(index: index))
                )
            }
        }
        return result
    }

    static func stickerKind(for place: Place) -> SaveDoodleStickerKind {
        if let hinted = kindHinted(by: place.name) {
            return hinted
        }
        let options: [SaveDoodleStickerKind]
        switch place.category {
        case .food:
            options = [.duck, .noodles, .baozi, .hotpot, .dessert]
        case .cafe:
            options = [.coffee, .tea]
        case .bar:
            options = [.wine, .beer]
        case .attraction:
            options = [.temple, .tree, .hill, .lantern, .bridge, .museum, .camera, .bicycle, .ferris, .beach]
        case .stay:
            options = [.temple, .pin, .hill]
        case .shopping:
            options = [.bag, .bookstore]
        }
        let value = stableHash(place.id.uuidString)
        return options[value % options.count]
    }

    static func kindHinted(by name: String) -> SaveDoodleStickerKind? {
        let lowered = name.lowercased()
        if lowered.contains("duck") || name.contains("鴨") { return .duck }
        if lowered.contains("noodle") || lowered.contains("ramen") || name.contains("麵") { return .noodles }
        if lowered.contains("bao") || name.contains("包") { return .baozi }
        if lowered.contains("hotpot") || name.contains("火鍋") { return .hotpot }
        if lowered.contains("coffee") || lowered.contains("cafe") { return .coffee }
        if lowered.contains("tea") || name.contains("茶") { return .tea }
        if lowered.contains("temple") || name.contains("寺") { return .temple }
        if lowered.contains("lantern") || name.contains("燈") { return .lantern }
        if lowered.contains("bridge") || name.contains("橋") { return .bridge }
        if lowered.contains("book") || name.contains("書") { return .bookstore }
        if lowered.contains("bike") || lowered.contains("bicycle") { return .bicycle }
        if lowered.contains("ferris") || lowered.contains("wheel") { return .ferris }
        if lowered.contains("park") || lowered.contains("tree") { return .tree }
        if lowered.contains("hill") || lowered.contains("mountain") { return .hill }
        return nil
    }

    static func rotationDegrees(for id: String) -> Double {
        Double(stableHash(id) % 13) - 6
    }

    /// Swift `Hasher` is randomly seeded per process. Stickers must keep
    /// the same glyph after relaunch, so hash the stable place identity.
    private static func stableHash(_ parts: String...) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for part in parts {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
            hash ^= 0xFF
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash & 0x7fff_ffff)
    }
}
