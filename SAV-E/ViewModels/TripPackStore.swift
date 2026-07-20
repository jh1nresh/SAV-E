import Combine
import Foundation

enum TripPackTiming: Equatable {
    case current
    case upcoming
    case planning
    case past
}

enum TripPackStoreState: Equatable {
    case idle
    case loading
    case saving
    case saved
    case failed(String)
}

enum TripPackStoreError: LocalizedError {
    case tripNotFound
    case invalidDateRange
    case invalidMove

    var errorDescription: String? {
        switch self {
        case .tripNotFound:
            return "Choose or create a Trip Pack first."
        case .invalidDateRange:
            return "The trip end date must be on or after its start date."
        case .invalidMove:
            return "That stop cannot move any farther."
        }
    }
}

@MainActor
final class TripPackStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published var selectedTripID: UUID?
    @Published private(set) var state: TripPackStoreState = .idle

    private let userID: String
    private let persistence: any TripPersisting
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private var reviewerDemoSeedPlaces: [Place]
    private var reorderTail: Task<Bool, Never>?
    private var reorderGeneration = 0

    init(
        userID: String,
        persistence: any TripPersisting,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        reviewerDemoSeedPlaces: [Place] = []
    ) {
        self.userID = userID
        self.persistence = persistence
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.reviewerDemoSeedPlaces = reviewerDemoSeedPlaces
    }

    static func reviewerDemo(confirmedPlaces: [Place] = []) -> TripPackStore {
        TripPackStore(
            userID: ReviewDemo.userId,
            persistence: ReviewDemoTripPersistence(),
            reviewerDemoSeedPlaces: confirmedPlaces
        )
    }

    var selectedTrip: Trip? {
        guard let selectedTripID else { return nil }
        return trips.first { $0.id == selectedTripID }
    }

    var suggestedTrip: Trip? {
        currentTrips.first ?? upcomingTrips.first ?? planningTrips.first
    }

    var currentTrips: [Trip] {
        trips(in: .current)
    }

    var upcomingTrips: [Trip] {
        trips(in: .upcoming)
    }

    var planningTrips: [Trip] {
        trips(in: .planning)
    }

    var pastTrips: [Trip] {
        trips(in: .past)
    }

    var isLoading: Bool { state == .loading }
    var isSaving: Bool { state == .saving }

    var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    func load() async {
        state = .loading
        do {
            let loaded = try await persistence.fetchTrips(for: userID)
            trips = sortedTrips(loaded.map(Self.normalized))
            if trips.isEmpty, !reviewerDemoSeedPlaces.isEmpty {
                try await seedReviewerDemoTrips(from: reviewerDemoSeedPlaces)
            }
            restoreSelection()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func seedReviewerDemoIfNeeded(confirmedPlaces: [Place]) async {
        reviewerDemoSeedPlaces = confirmedPlaces
        guard trips.isEmpty, !confirmedPlaces.isEmpty else { return }

        state = .saving
        do {
            try await seedReviewerDemoTrips(from: confirmedPlaces)
            restoreSelection()
            state = .saved
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func createTrip(
        name: String,
        city: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> Trip? {
        guard Self.hasValidDateRange(startDate: startDate, endDate: endDate) else {
            fail(TripPackStoreError.invalidDateRange)
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = Trip(
            id: UUID(),
            name: trimmedName.isEmpty ? "Untitled Trip" : trimmedName,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate,
            places: [],
            isOptimized: false,
            createdAt: nowProvider()
        )

        state = .saving
        do {
            try await persistence.saveTrip(trip, userId: userID)
            trips.append(trip)
            trips = sortedTrips(trips)
            selectedTripID = trip.id
            state = .saved
            return trip
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func save(_ trip: Trip) async -> Bool {
        guard trips.contains(where: { $0.id == trip.id }) else {
            fail(TripPackStoreError.tripNotFound)
            return false
        }
        guard Self.hasValidDateRange(startDate: trip.startDate, endDate: trip.endDate) else {
            fail(TripPackStoreError.invalidDateRange)
            return false
        }
        return await persistUpdate(Self.normalized(trip))
    }

    @discardableResult
    func deleteTrip(_ tripID: UUID) async -> Bool {
        guard trips.contains(where: { $0.id == tripID }) else {
            fail(TripPackStoreError.tripNotFound)
            return false
        }

        state = .saving
        do {
            try await persistence.deleteTrip(tripID)
            trips.removeAll { $0.id == tripID }
            if selectedTripID == tripID {
                selectedTripID = suggestedTrip?.id
            }
            state = .saved
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func addConfirmedPlace(_ place: Place, to tripID: UUID? = nil) async -> Bool {
        guard let targetID = tripID ?? selectedTripID ?? suggestedTrip?.id,
              var trip = trips.first(where: { $0.id == targetID })
        else {
            fail(TripPackStoreError.tripNotFound)
            return false
        }
        guard !trip.places.contains(where: { $0.placeId == place.id }) else {
            selectedTripID = targetID
            return false
        }

        let nextOrder = trip.places
            .filter { $0.day == 1 }
            .map(\.orderIndex)
            .max()
            .map { $0 + 1 } ?? 0
        trip.places.append(TripStop(
            id: UUID(),
            placeId: place.id,
            placeName: place.name,
            day: 1,
            orderIndex: nextOrder,
            startTime: nil,
            duration: nil,
            note: nil
        ))
        selectedTripID = targetID
        return await persistUpdate(Self.normalized(trip))
    }

    @discardableResult
    func moveStop(_ stopID: UUID, in tripID: UUID, by offset: Int) async -> Bool {
        let previousReorder = reorderTail
        reorderGeneration += 1
        let generation = reorderGeneration
        let reorder = Task { @MainActor [weak self] in
            _ = await previousReorder?.value
            guard let self else { return false }
            return await self.performMoveStop(stopID, in: tripID, by: offset)
        }
        reorderTail = reorder
        let result = await reorder.value
        if generation == reorderGeneration {
            reorderTail = nil
        }
        return result
    }

    private func performMoveStop(_ stopID: UUID, in tripID: UUID, by offset: Int) async -> Bool {
        guard offset == -1 || offset == 1,
              var trip = trips.first(where: { $0.id == tripID }),
              let stop = trip.places.first(where: { $0.id == stopID })
        else {
            fail(TripPackStoreError.invalidMove)
            return false
        }

        trip = Self.normalized(trip)
        let dayIndices = trip.places.indices.filter { trip.places[$0].day == stop.day }
        guard let currentPosition = dayIndices.firstIndex(where: { trip.places[$0].id == stopID }) else {
            fail(TripPackStoreError.invalidMove)
            return false
        }
        let destinationPosition = currentPosition + offset
        guard dayIndices.indices.contains(destinationPosition) else { return false }

        trip.places.swapAt(dayIndices[currentPosition], dayIndices[destinationPosition])
        for (orderIndex, placeIndex) in dayIndices.enumerated() {
            trip.places[placeIndex].orderIndex = orderIndex
        }
        selectedTripID = tripID
        return await persistUpdate(Self.normalized(trip))
    }

    func selectTrip(_ tripID: UUID?) {
        guard let tripID else {
            selectedTripID = nil
            return
        }
        if trips.contains(where: { $0.id == tripID }) {
            selectedTripID = tripID
        }
    }

    func clearStatus() {
        state = .idle
    }

    func timing(for trip: Trip) -> TripPackTiming {
        Self.timing(for: trip, on: nowProvider(), calendar: calendar)
    }

    private func trips(in timing: TripPackTiming) -> [Trip] {
        sortedTrips(trips.filter { self.timing(for: $0) == timing })
    }

    private func persistUpdate(_ trip: Trip) async -> Bool {
        state = .saving
        do {
            try await persistence.updateTrip(trip)
            guard let index = trips.firstIndex(where: { $0.id == trip.id }) else {
                throw TripPackStoreError.tripNotFound
            }
            trips[index] = trip
            trips = sortedTrips(trips)
            state = .saved
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private func seedReviewerDemoTrips(from places: [Place]) async throws {
        let seeds = Self.reviewerDemoTrips(
            confirmedPlaces: places,
            now: nowProvider(),
            calendar: calendar
        )
        for trip in seeds {
            try await persistence.saveTrip(trip, userId: userID)
        }
        trips = sortedTrips(seeds)
    }

    private func restoreSelection() {
        if let selectedTripID, trips.contains(where: { $0.id == selectedTripID }) {
            return
        }
        selectedTripID = suggestedTrip?.id
    }

    private func sortedTrips(_ values: [Trip]) -> [Trip] {
        values.sorted { lhs, rhs in
            let lhsTiming = timing(for: lhs)
            let rhsTiming = timing(for: rhs)
            if lhsTiming != rhsTiming {
                return Self.timingRank(lhsTiming) < Self.timingRank(rhsTiming)
            }

            switch lhsTiming {
            case .current, .upcoming:
                let lhsDate = lhs.startDate ?? lhs.endDate ?? .distantFuture
                let rhsDate = rhs.startDate ?? rhs.endDate ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
            case .planning:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .past:
                let lhsDate = lhs.endDate ?? lhs.startDate ?? .distantPast
                let rhsDate = rhs.endDate ?? rhs.startDate ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func fail(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    private static func timing(for trip: Trip, on now: Date, calendar: Calendar) -> TripPackTiming {
        let today = calendar.startOfDay(for: now)
        let start = trip.startDate.map { calendar.startOfDay(for: $0) }
        let end = trip.endDate.map { calendar.startOfDay(for: $0) }

        if let start, let end, end < start { return .planning }
        if let end, end < today { return .past }
        if let start, start > today { return .upcoming }
        if let start, start <= today {
            return .current
        }
        return .planning
    }

    private static func timingRank(_ timing: TripPackTiming) -> Int {
        switch timing {
        case .current: return 0
        case .upcoming: return 1
        case .planning: return 2
        case .past: return 3
        }
    }

    private static func hasValidDateRange(startDate: Date?, endDate: Date?) -> Bool {
        guard let startDate, let endDate else { return true }
        return endDate >= startDate
    }

    private static func normalized(_ trip: Trip) -> Trip {
        var normalized = trip
        let sortedStops = trip.places.sorted { lhs, rhs in
            let lhsDay = max(1, lhs.day)
            let rhsDay = max(1, rhs.day)
            if lhsDay != rhsDay { return lhsDay < rhsDay }
            if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var nextOrderByDay: [Int: Int] = [:]
        normalized.places = sortedStops.map { stop in
            var stop = stop
            stop.day = max(1, stop.day)
            stop.orderIndex = nextOrderByDay[stop.day, default: 0]
            nextOrderByDay[stop.day, default: 0] += 1
            return stop
        }
        return normalized
    }

    private static func reviewerDemoTrips(
        confirmedPlaces: [Place],
        now: Date,
        calendar: Calendar
    ) -> [Trip] {
        guard !confirmedPlaces.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let tokyoPlaces = confirmedPlaces.filter { place in
            "\(place.name) \(place.address)".localizedCaseInsensitiveContains("Tokyo")
        }
        let taipeiPlaces = confirmedPlaces.filter { place in
            let searchable = "\(place.name) \(place.address)"
            return searchable.localizedCaseInsensitiveContains("Taipei") || searchable.contains("台北")
        }
        let usesCityGroups = !tokyoPlaces.isEmpty && !taipeiPlaces.isEmpty
        let splitIndex = max(1, (confirmedPlaces.count + 1) / 2)
        let currentPlaces = usesCityGroups ? tokyoPlaces : Array(confirmedPlaces.prefix(splitIndex))
        let upcomingPlaces = usesCityGroups ? taipeiPlaces : Array(confirmedPlaces.dropFirst(splitIndex))

        func stops(from places: [Place]) -> [TripStop] {
            places.enumerated().map { index, place in
                TripStop(
                    id: UUID(),
                    placeId: place.id,
                    placeName: place.name,
                    day: 1,
                    orderIndex: index,
                    startTime: nil,
                    duration: nil,
                    note: nil
                )
            }
        }

        let current = Trip(
            id: UUID(),
            name: usesCityGroups ? "Tokyo Weekend" : "This Weekend",
            city: usesCityGroups ? "Tokyo" : "",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 2, to: today),
            places: stops(from: currentPlaces),
            isOptimized: false,
            createdAt: now
        )
        let upcoming = Trip(
            id: UUID(),
            name: usesCityGroups ? "Taipei Escape" : "Next Escape",
            city: usesCityGroups ? "Taipei" : "",
            startDate: calendar.date(byAdding: .day, value: 14, to: today),
            endDate: calendar.date(byAdding: .day, value: 17, to: today),
            places: stops(from: upcomingPlaces),
            isOptimized: false,
            createdAt: now
        )
        return [current, upcoming]
    }
}
