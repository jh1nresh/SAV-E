import Combine
import Foundation

/// Map observes mutations while the shared history remains authoritative.
@MainActor
final class SaveDoodleCheckInStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private let history: SaveDoodleVisitStore

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        history = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: now)
    }

    func visitCount(for placeID: UUID) -> Int { history.count(for: placeID) }
    func hasCheckedInToday(placeID: UUID) -> Bool { history.hasVisitedToday(placeID) }
    func canCheckIn(placeID: UUID) -> Bool { !hasCheckedInToday(placeID: placeID) }

    @discardableResult
    func checkIn(placeID: UUID) -> Bool {
        guard canCheckIn(placeID: placeID) else { return false }
        objectWillChange.send()
        return history.recordVisit(for: placeID)
    }

    @discardableResult
    func undoTodaysCheckIn(placeID: UUID) -> Bool {
        guard hasCheckedInToday(placeID: placeID) else { return false }
        objectWillChange.send()
        return history.undoToday(for: placeID)
    }

    static var storageKey: String { SaveDoodleVisitStore.datesKey }
}
