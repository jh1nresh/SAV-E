#if !SAVVY_MAIN_APP || (DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW)
import Foundation
import Observation

enum DemoParticipant: String, CaseIterable, Identifiable, Hashable, Sendable {
    case you, an
    var id: String { rawValue }
}

struct DemoPlace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let emoji: String
    let latitude: Double
    let longitude: Double
    let category: String
    let recommendedBy: DemoParticipant?
    let note: String
    let durationMinutes: Int
    let isOutdoor: Bool
}

struct DemoStop: Identifiable, Equatable, Sendable {
    let id: String
    let placeID: String
    let arrivalMinutes: Int
    let departureMinutes: Int
    /// Illustrative walking minutes before this stop; never live directions.
    let travelMinutes: Int
}

/// Independent local fixtures. Choosing together never confirms a save or visit.
@Observable @MainActor
final class DatePlanStore {
    let places: [DemoPlace] = [
        DemoPlace(id: "coffee", name: "午後小室", detail: "大安・虛構咖啡館", emoji: "☕️",
            latitude: 25.0294, longitude: 121.5426, category: "咖啡", recommendedBy: .an,
            note: "想一起坐窗邊聊聊，先從一杯咖啡開始。", durationMinutes: 60, isOutdoor: false),
        DemoPlace(id: "park", name: "綠蔭散步點", detail: "大安・虛構散步地點", emoji: "🌿",
            latitude: 25.0271, longitude: 121.5368, category: "散步", recommendedBy: nil,
            note: "沿著綠蔭慢慢走，不急著趕下一站。", durationMinutes: 70, isOutdoor: true),
        DemoPlace(id: "dinner", name: "暖光餐桌", detail: "大安・虛構晚餐餐廳", emoji: "🍽️",
            latitude: 25.0256, longitude: 121.5429, category: "晚餐", recommendedBy: nil,
            note: "室內休息，留一點時間好好吃晚餐。", durationMinutes: 90, isOutdoor: false),
        DemoPlace(id: "dessert", name: "甜點備案", detail: "大安・虛構甜點店", emoji: "🍰",
            latitude: 25.0311, longitude: 121.5456, category: "甜點", recommendedBy: nil,
            note: "想提早坐下休息時，可以改選這個備案。", durationMinutes: 45, isOutdoor: false),
    ]
    private(set) var candidateIDs = ["coffee", "park", "dinner"]
    private(set) var votes: [String: Set<DemoParticipant>] = [
        "coffee": [.an], "park": [.an], "dinner": [.an],
    ]
    private(set) var savedIDs: Set<String> = ["park", "dessert"]
    var activeParticipant: DemoParticipant = .you
    private(set) var startsAtMinutes = 14 * 60
    private(set) var planIDs: [String] = []
    private(set) var started = false
    /// Equals planIDs.count when this explicitly advanced demo outing is complete.
    private(set) var currentStopIndex = 0
    private var generatedSharedIDs: Set<String>?

    var sharedIDs: [String] {
        places.compactMap { place in
            candidateIDs.contains(place.id) && votes[place.id, default: []].contains(.you)
                && votes[place.id, default: []].contains(.an) ? place.id : nil
        }
    }

    var hasPlan: Bool { !planIDs.isEmpty }
    var budget: DemoBudgetTotals { .fixtures(for: planIDs) }

    /// Reordering and start-time edits do not change the agreed choice snapshot.
    var isPlanStale: Bool {
        guard let generatedSharedIDs else { return false }
        return generatedSharedIDs != Set(sharedIDs)
    }

    var timeline: [DemoStop] {
        var result: [DemoStop] = []
        var previous: DemoPlace?
        var departure = startsAtMinutes
        for id in planIDs {
            guard let place = self.place(id) else { continue }
            let travel = previous.map { Self.walkingEstimate(from: $0, to: place) } ?? 0
            let arrival = departure + travel
            departure = arrival + place.durationMinutes
            result.append(DemoStop(id: id, placeID: id, arrivalMinutes: arrival,
                                   departureMinutes: departure, travelMinutes: travel))
            previous = place
        }
        return result
    }

    func place(_ id: String) -> DemoPlace? { places.first { $0.id == id } }

    func toggleCandidate(_ id: String) {
        guard place(id) != nil else { return }
        if candidateIDs.contains(id) {
            candidateIDs.removeAll { $0 == id }
            votes.removeValue(forKey: id)
        } else {
            let selected = Set(candidateIDs + [id])
            candidateIDs = places.filter { selected.contains($0.id) }.map(\.id)
        }
    }

    func toggleVote(_ id: String, participant: DemoParticipant) {
        guard candidateIDs.contains(id), place(id) != nil else { return }
        var choice = votes[id, default: []]
        if choice.contains(participant) { choice.remove(participant) }
        else { choice.insert(participant) }
        votes[id] = choice
    }

    /// The only operation allowed to change this demo's confirmed-save fixtures.
    func setSaved(_ id: String, _ value: Bool) {
        guard place(id) != nil else { return }
        if value { savedIDs.insert(id) }
        else { savedIDs.remove(id) }
    }

    @discardableResult
    func generatePlan() -> Bool {
        let shared = sharedIDs
        guard !shared.isEmpty else { return false }
        planIDs = shared
        generatedSharedIDs = Set(shared)
        started = false
        currentStopIndex = 0
        return true
    }

    func moveStop(_ id: String, offset: Int) {
        guard !started, offset == -1 || offset == 1, let index = planIDs.firstIndex(of: id),
              planIDs.indices.contains(index + offset) else { return }
        planIDs.swapAt(index, index + offset)
    }

    func setStartMinutes(_ value: Int) {
        guard !started else { return }
        startsAtMinutes = min(18 * 60, max(10 * 60, value))
    }

    func startDate() {
        guard hasPlan, !isPlanStale, !started else { return }
        started = true
        currentStopIndex = 0
    }

    func advanceStop() {
        guard started, !isPlanStale, currentStopIndex < planIDs.count else { return }
        currentStopIndex += 1
    }

    static func clock(_ minutes: Int) -> String {
        let value = (minutes % (24 * 60) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func walkingEstimate(from: DemoPlace, to: DemoPlace) -> Int {
        let meanLatitude = (from.latitude + to.latitude) / 2 * .pi / 180
        let east = (to.longitude - from.longitude) * 111_195 * cos(meanLatitude)
        let north = (to.latitude - from.latitude) * 111_195
        // Straight-line local fixture estimate at 70m/min; no route/service lookup.
        return min(25, max(5, Int((hypot(east, north) / 70).rounded(.up))))
    }
}

#endif
