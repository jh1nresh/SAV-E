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

    /// Persist the place update after the local visit. A failed write must
    /// not leave today's check-in on a place that is still want-to-go.
    @discardableResult
    func applyCheckIn(
        placeID: UUID,
        priorStatus: PlaceStatus = .wantToGo,
        persist: () async throws -> Void
    ) async -> Bool {
        history.rememberPriorStatus(priorStatus, for: placeID)
        guard checkIn(placeID: placeID) else { return false }
        do {
            try await persist()
            return true
        } catch {
            _ = undoTodaysCheckIn(placeID: placeID)
            return false
        }
    }

    /// Remove today's visit, then persist the restored place status. A failed
    /// write must put today's history back so the sheet cannot show visited
    /// with an empty record.
    @discardableResult
    func applyUndo(
        placeID: UUID,
        persist: (PlaceStatus) async throws -> Void
    ) async -> Bool {
        guard hasCheckedInToday(placeID: placeID) else { return false }
        let restoreStatus = history.previousStatus(for: placeID)
            ?? (visitCount(for: placeID) > 1 ? .visited : .wantToGo)
        let snapshot = history.snapshot(for: placeID)
        guard undoTodaysCheckIn(placeID: placeID) else { return false }
        do {
            try await persist(restoreStatus)
            history.clearPriorStatus(for: placeID)
            return true
        } catch {
            history.restore(snapshot)
            objectWillChange.send()
            return false
        }
    }

    static var storageKey: String { SaveDoodleVisitStore.datesKey }
}
