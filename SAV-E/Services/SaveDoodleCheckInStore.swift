import Combine
import Foundation

/// Manual "I've been here / 我來過了" visits for Doodle Map (HoP D1).
/// One check-in per place per calendar day; today's visit can be undone.
/// A successful check-in is a visit: the Map sheet colours the sticker and
/// the caller persists `Place.status = .visited`.
@MainActor
final class SaveDoodleCheckInStore: ObservableObject {
    @Published private(set) var visits: [UUID: [Date]] = [:]

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        visits = Self.load(from: defaults)
    }

    func visitCount(for placeID: UUID) -> Int {
        visits[placeID, default: []].count
    }

    func hasCheckedInToday(placeID: UUID) -> Bool {
        let today = now()
        return visits[placeID, default: []].contains { calendar.isDate($0, inSameDayAs: today) }
    }

    func canCheckIn(placeID: UUID) -> Bool {
        !hasCheckedInToday(placeID: placeID)
    }

    @discardableResult
    func checkIn(placeID: UUID) -> Bool {
        guard canCheckIn(placeID: placeID) else { return false }
        visits[placeID, default: []].append(now())
        persist()
        return true
    }

    @discardableResult
    func undoTodaysCheckIn(placeID: UUID) -> Bool {
        let today = now()
        let existing = visits[placeID, default: []]
        let remaining = existing.filter { !calendar.isDate($0, inSameDayAs: today) }
        guard remaining.count != existing.count else { return false }
        if remaining.isEmpty {
            visits[placeID] = nil
        } else {
            visits[placeID] = remaining
        }
        persist()
        return true
    }

    private func persist() {
        let payload = visits.reduce(into: [String: [Double]]()) { result, item in
            result[item.key.uuidString] = item.value.map(\.timeIntervalSince1970)
        }
        defaults.set(payload, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [UUID: [Date]] {
        guard let payload = defaults.dictionary(forKey: storageKey) as? [String: [Double]] else {
            return [:]
        }
        var result: [UUID: [Date]] = [:]
        for (key, values) in payload {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = values.map { Date(timeIntervalSince1970: $0) }
        }
        return result
    }

    private static var suiteSuffix: String {
        ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"] ?? "default"
    }

    static var storageKey: String { "save.doodle.checkins.\(suiteSuffix)" }
}
