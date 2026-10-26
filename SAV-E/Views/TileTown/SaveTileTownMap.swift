import CoreGraphics
import Foundation

/// Founder lock 2026-10-14: product Map base is full-pixel tile-town.
/// MapKit remains for Trip navigation maps and Apple Maps handoff only.
/// Pixel canvas / lens / raster / peek views were unreachable leftovers and
/// were removed. Passport goal math and chrome height stay here.
nonisolated enum SaveTileTownProductLock: Sendable {
    static let productMapBaseIsTileTown = true
    static let homeShowsMapFilterChips = false
    static let mapShowsNearbySavedFriendsChips = true
    /// Wordmark + Nearby/Saved/Friends rail below the 48pt status band.
    static let mapChromeHeight: CGFloat = 136
    /// Lets root-tab lists scroll stamp labels and bios above the tab bar.
    static let rootTabScrollClearance: CGFloat = 150

    /// Collection page size used by Passport progress (4/12 in the lock frames).
    static func passportGoal(for savedCount: Int) -> Int {
        max(12, ((max(savedCount, 0) + 11) / 12) * 12)
    }
}

nonisolated enum SaveTileTownLayout: Sendable {
    /// Normalized lots along the village roads. Pins hash here so the town
    /// stays a memory map, not a silent GPS re-projection.
    static let lots: [CGPoint] = [
        CGPoint(x: 0.18, y: 0.22),
        CGPoint(x: 0.38, y: 0.16),
        CGPoint(x: 0.58, y: 0.24),
        CGPoint(x: 0.78, y: 0.18),
        CGPoint(x: 0.14, y: 0.42),
        CGPoint(x: 0.34, y: 0.38),
        CGPoint(x: 0.54, y: 0.44),
        CGPoint(x: 0.72, y: 0.36),
        CGPoint(x: 0.22, y: 0.62),
        CGPoint(x: 0.44, y: 0.58),
        CGPoint(x: 0.64, y: 0.64),
        CGPoint(x: 0.82, y: 0.52),
        CGPoint(x: 0.28, y: 0.80),
        CGPoint(x: 0.50, y: 0.78),
        CGPoint(x: 0.70, y: 0.82),
        CGPoint(x: 0.86, y: 0.70),
    ]

    static func lotIndex(for id: UUID) -> Int {
        var hasher = Hasher()
        hasher.combine(id)
        let value = hasher.finalize()
        return abs(value) % lots.count
    }

    static func assignments(for ids: [UUID]) -> [UUID: Int] {
        var used = Set<Int>()
        var result: [UUID: Int] = [:]
        for id in ids {
            var index = lotIndex(for: id)
            var attempts = 0
            while used.contains(index), attempts < lots.count {
                index = (index + 1) % lots.count
                attempts += 1
            }
            used.insert(index)
            result[id] = index
        }
        return result
    }
}

