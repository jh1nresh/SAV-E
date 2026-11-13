#if SAVVY_CITY_MVP
import Foundation

/// Immutable ownership when Guide opens. A queued handoff carries no private Place.
struct CityMVPGuideSession: Equatable {
    let authGeneration: Int
    let mapGeneration: Int

    @MainActor
    func resolve(placeID: UUID, currentAuthGeneration: Int, currentMapGeneration: Int,
                 hasIncomingReceipt: Bool = false, places: [Place]) -> Place? {
        guard !hasIncomingReceipt, authGeneration == currentAuthGeneration,
              mapGeneration == currentMapGeneration else { return nil }
        let matches = places.filter { $0.id == placeID }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
/// Resume the newest request after UIKit's dismissal turn, not the earlier snapshot.
@MainActor
enum CityMVPChromeResume {
    static func next<Value>(initial: Value, latest: () -> Value?, clear: () -> Void,
                            afterYield: () async -> Void = { await Task.yield() }) async -> Value {
        await afterYield()
        let next = latest() ?? initial
        clear()
        return next
    }
}
#endif
