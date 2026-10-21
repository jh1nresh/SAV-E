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
    static let slotSize: CGFloat = SaveLayout.passportSlot
    static let columnStride: CGFloat = 80
    static let rowGap: CGFloat = SaveSpace.md
    static let minColumnGap: CGFloat = SaveSpace.md
    static let panelPadding: CGFloat = SaveSpace.lg
    static let pageSize = 12

    /// Spec §7.3: `columns = floor((availableGridWidth + 16) / 80)`,
    /// clamped to 1...4. 375/390pt → 3; 402/430pt → 4.
    static func columnCount(availableGridWidth: CGFloat) -> Int {
        let raw = Int(floor((availableGridWidth + minColumnGap) / columnStride))
        return min(maxColumnCount, max(minColumnCount, raw))
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
                content: .place(place, item.2, item.3)
            )
        }
    }

    static func goal(for savedCount: Int) -> Int {
        SaveTileTownProductLock.passportGoal(for: savedCount)
    }

    static func cityPlaces(
        from places: [Place],
        selection: SaveDoodleCitySelection,
        location: CLLocation? = nil,
        locationDenied: Bool
    ) -> [Place] {
        SaveDoodleHomeProgressCatalog.cityPlaces(
            from: places,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
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
        let city = cityPlaces(
            from: places,
            selection: selection,
            location: location,
            locationDenied: locationDenied
        )
        let goal = Self.goal(for: max(city.count, 1))
        let visible = Array(city.prefix(goal))
        var result: [SaveDoodlePassportSlot] = visible.enumerated().map { index, place in
            let kind = stickerKind(for: place, index: index)
            let rank = visitStore.rank(for: place.id, visited: place.status == .visited)
            return SaveDoodlePassportSlot(
                id: place.id.uuidString,
                content: .place(place, kind, rank)
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

    static func stickerKind(for place: Place, index: Int = 0) -> SaveDoodleStickerKind {
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
        let value = stableHash(place.id.uuidString, place.name, "\(index)")
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
