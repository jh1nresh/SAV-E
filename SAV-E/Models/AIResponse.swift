import Foundation
import MapKit

// MARK: - AI Response (domain model)

struct SaveAIResponse: Equatable {
    let componentType: ComponentType
    let title: String?
    let placeIds: [String]
    let navigationPlaceId: String?
    let transportMode: TransportMode
    let itineraryDays: [ItineraryDay]
    var tripHealth: TripHealth? = nil
    let messageText: String?
    let mapAction: MapActionData?
    let aiMessage: String?
    var followUpChoices: [SaveSearchFollowUpChoice] = []

    enum ComponentType: String, Codable, Equatable {
        case placeList, navigationCard, tripItinerary, message
    }

    enum TransportMode: String, Codable, Equatable, Hashable {
        case walking, transit, driving

        var mapsKey: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            }
        }
    }
}

// MARK: - Map Action

struct MapActionData: Codable, Equatable {
    let type: ActionType
    let placeIds: [String]?
    let lat: Double?
    let lng: Double?
    let span: Double?

    enum ActionType: String, Codable, Equatable {
        case filterPins, focusRegion, showRoute, resetPins
    }
}

// MARK: - Itinerary

struct ItineraryDay: Identifiable, Equatable {
    let dayNumber: Int
    let label: String?
    let stops: [ItineraryStop]
    var health: TripHealth? = nil
    var id: Int { dayNumber }
}

struct ItineraryStop: Identifiable, Equatable {
    let id: UUID
    let placeId: String?
    var placeState: ItineraryPlaceState? = nil
    let placeName: String
    let time: String?
    let duration: Int?
    let note: String?
    var sourceSummary: String? = nil
    var risks: [TripRisk] = []
}

enum TripKmlExportSelectionError: Error, Equatable {
    case noConfirmedMapStamps
    case tooManyConfirmedMapStamps(Int)
}

struct TripCanvasDraft: Equatable {
    private(set) var days: [ItineraryDay]
    private(set) var approvedExternalStopIDs: Set<UUID>
    private(set) var skippedStopIDs: Set<UUID>

    init(
        days: [ItineraryDay],
        approvedExternalStopIDs: Set<UUID> = [],
        skippedStopIDs: Set<UUID> = []
    ) {
        self.days = days
        self.approvedExternalStopIDs = approvedExternalStopIDs
        self.skippedStopIDs = skippedStopIDs
    }

    var visibleDays: [ItineraryDay] {
        days.map { day in
            day.replacingStops(day.stops.filter { !skippedStopIDs.contains($0.id) })
        }
    }

    func kmlExportPlaceIDs(availablePlaces: [Place]) throws -> [UUID] {
        let availablePlaceIDs = Set(availablePlaces.map(\.id))
        var seenPlaceIDs = Set<UUID>()
        let placeIDs = visibleDays
            .flatMap(\.stops)
            .compactMap { stop -> UUID? in
                guard stop.placeState == .confirmedMapStamp,
                      let rawPlaceID = stop.placeId,
                      let placeID = UUID(uuidString: rawPlaceID),
                      availablePlaceIDs.contains(placeID),
                      seenPlaceIDs.insert(placeID).inserted else {
                    return nil
                }
                return placeID
            }

        guard !placeIDs.isEmpty else {
            throw TripKmlExportSelectionError.noConfirmedMapStamps
        }
        guard placeIDs.count <= 100 else {
            throw TripKmlExportSelectionError.tooManyConfirmedMapStamps(placeIDs.count)
        }
        return placeIDs
    }

    mutating func approveExternalStop(_ stopID: UUID) {
        guard stop(with: stopID)?.placeState == .externalSuggestion else { return }
        skippedStopIDs.remove(stopID)
        approvedExternalStopIDs.insert(stopID)
    }

    mutating func skipStop(_ stopID: UUID) {
        guard stop(with: stopID) != nil else { return }
        approvedExternalStopIDs.remove(stopID)
        skippedStopIDs.insert(stopID)
    }

    mutating func moveStopEarlier(_ stopID: UUID) {
        guard let location = location(of: stopID), location.stopIndex > 0 else { return }
        moveStop(stopID, toDayNumber: days[location.dayIndex].dayNumber, at: location.stopIndex - 1)
    }

    mutating func moveStopLater(_ stopID: UUID) {
        guard let location = location(of: stopID) else { return }
        let day = days[location.dayIndex]
        guard location.stopIndex < day.stops.count - 1 else { return }
        moveStop(stopID, toDayNumber: day.dayNumber, at: location.stopIndex + 1)
    }

    mutating func insertExternalSuggestion(
        title: String,
        dayNumber: Int,
        note: String,
        sourceSummary: String
    ) {
        guard let index = days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        let suggestion = ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeState: .externalSuggestion,
            placeName: title,
            time: nil,
            duration: 60,
            note: note,
            sourceSummary: sourceSummary,
            risks: [.externalSuggestion, .hoursUnknown, .bookingUnknown]
        )
        var stops = days[index].stops
        stops.append(suggestion)
        days[index] = days[index].replacingStops(stops)
    }

    mutating func insertGapSuggestion(
        _ option: GapSuggestionOption,
        dayNumber: Int,
        note: String
    ) {
        guard option.action != .skip,
              let index = days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        let placeState: ItineraryPlaceState
        let risks: [TripRisk]
        switch option.source {
        case .confirmedSaved:
            placeState = .confirmedMapStamp
            risks = [.hoursUnknown, .bookingUnknown]
        case .reviewCandidate:
            placeState = .reviewCandidate
            risks = [.needsReview, .hoursUnknown, .bookingUnknown]
        case .sourceClue:
            placeState = .sourceOnly
            risks = [.sourceWeak, .needsReview]
        case .externalSuggestion:
            placeState = .externalSuggestion
            risks = [.externalSuggestion, .hoursUnknown, .bookingUnknown]
        }
        let suggestion = ItineraryStop(
            id: UUID(),
            placeId: option.placeId,
            placeState: placeState,
            placeName: option.title,
            time: nil,
            duration: 60,
            note: note,
            sourceSummary: option.reason,
            risks: risks
        )
        var stops = days[index].stops
        stops.append(suggestion)
        days[index] = days[index].replacingStops(stops)
    }

    func isApprovedExternalStop(_ stopID: UUID) -> Bool {
        approvedExternalStopIDs.contains(stopID)
    }

    private mutating func moveStop(_ stopID: UUID, toDayNumber dayNumber: Int, at insertionIndex: Int) {
        guard let source = location(of: stopID),
              let targetDayIndex = days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        var sourceStops = days[source.dayIndex].stops
        let stop = sourceStops.remove(at: source.stopIndex)
        days[source.dayIndex] = days[source.dayIndex].replacingStops(sourceStops)

        var targetStops = days[targetDayIndex].stops
        let boundedIndex = min(max(insertionIndex, 0), targetStops.count)
        targetStops.insert(stop, at: boundedIndex)
        days[targetDayIndex] = days[targetDayIndex].replacingStops(targetStops)
    }

    private func stop(with id: UUID) -> ItineraryStop? {
        days.flatMap(\.stops).first { $0.id == id }
    }

    private func location(of id: UUID) -> (dayIndex: Int, stopIndex: Int)? {
        for dayIndex in days.indices {
            if let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == id }) {
                return (dayIndex, stopIndex)
            }
        }
        return nil
    }
}

extension ItineraryDay {
    func replacingStops(_ stops: [ItineraryStop]) -> ItineraryDay {
        ItineraryDay(dayNumber: dayNumber, label: label, stops: stops, health: health)
    }
}

enum ItineraryPlaceState: String, Codable, Equatable, Hashable {
    case sourceOnly
    case reviewCandidate
    case confirmedMapStamp
    case externalSuggestion
}

enum TripRisk: String, Codable, Equatable, Hashable {
    case hoursUnknown = "hours_unknown"
    case bookingUnknown = "booking_unknown"
    case needsReview = "needs_review"
    case externalSuggestion = "external_suggestion"
    case tooFarFromPrevious = "too_far_from_previous"
    case sourceWeak = "source_weak"
}

struct TripHealth: Codable, Equatable, Hashable {
    let score: Int
    let strengths: [String]
    let warnings: [TripWarning]
    let gaps: [TripGap]
}

struct TripWarning: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let type: WarningType
    let severity: Severity
    let message: String
    var affectedBlockIds: [String] = []

    enum WarningType: String, Codable, Equatable, Hashable {
        case tooManyStops = "too_many_stops"
        case tooManyAreas = "too_many_areas"
        case hoursUnknown = "hours_unknown"
        case bookingUnknown = "booking_unknown"
        case tooManyUnconfirmedPlaces = "too_many_unconfirmed_places"
        case lowMemoryCoverage = "low_memory_coverage"
        case notEnoughBuffer = "not_enough_buffer"
    }
}

struct TripGap: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let type: GapType
    let dayId: String
    var area: String? = nil
    let severity: Severity
    let message: String

    enum GapType: String, Codable, Equatable, Hashable {
        case missingBreakfast = "missing_breakfast"
        case missingLunch = "missing_lunch"
        case missingDinner = "missing_dinner"
        case missingCoffeeBreak = "missing_coffee_break"
        case missingAfternoonActivity = "missing_afternoon_activity"
        case missingEveningPlan = "missing_evening_plan"
        case needsAreaCluster = "needs_area_cluster"
        case needsRainBackup = "needs_rain_backup"
        case needsHoursCheck = "needs_hours_check"
    }
}

struct GapSuggestion: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var gapId: String
    var dayId: String
    var message: String
    var options: [GapSuggestionOption]
    var requiresUserApproval: Bool
}

struct GapSuggestionOption: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var source: GapSuggestionSource
    var placeId: String?
    var reviewCandidateId: String?
    var mapCandidateId: String?
    var reason: String
    var confidence: ConfidenceLevel
    var action: GapSuggestionAction
}

enum GapSuggestionSource: String, Codable, Equatable, Hashable {
    case confirmedSaved
    case reviewCandidate
    case sourceClue
    case externalSuggestion
}

enum GapSuggestionAction: String, Codable, Equatable, Hashable {
    case addToPlan
    case reviewThenAdd
    case resolveThenAdd
    case addExternalWithApproval
    case skip
}

enum ConfidenceLevel: String, Codable, Equatable, Hashable {
    case low
    case medium
    case high
}

enum Severity: String, Codable, Equatable, Hashable {
    case low
    case medium
    case high
}

// MARK: - Codable DTOs (what Gemini actually returns)

struct SaveAIResponseDTO: Codable {
    let componentType: String
    let title: String?
    let placeIds: [String]?
    let navigationPlaceId: String?
    let transportMode: String?
    let itineraryDays: [ItineraryDayDTO]?
    let tripHealth: TripHealth?
    let messageText: String?
    let mapAction: MapActionData?
    let aiMessage: String?

    func toResponse() -> SaveAIResponse {
        SaveAIResponse(
            componentType: SaveAIResponse.ComponentType(rawValue: componentType) ?? .message,
            title: title,
            placeIds: placeIds ?? [],
            navigationPlaceId: navigationPlaceId,
            transportMode: SaveAIResponse.TransportMode(rawValue: transportMode ?? "walking") ?? .walking,
            itineraryDays: (itineraryDays ?? []).map { $0.toModel() },
            tripHealth: tripHealth,
            messageText: messageText,
            mapAction: mapAction,
            aiMessage: aiMessage,
            followUpChoices: []
        )
    }
}

struct ItineraryDayDTO: Codable {
    let dayNumber: Int
    let label: String?
    let stops: [ItineraryStopDTO]
    let health: TripHealth?

    func toModel() -> ItineraryDay {
        ItineraryDay(dayNumber: dayNumber, label: label, stops: stops.map { $0.toModel() }, health: health)
    }
}

struct ItineraryStopDTO: Codable {
    let placeId: String?
    let placeState: ItineraryPlaceState?
    let placeName: String
    let time: String?
    let duration: Int?
    let note: String?
    let sourceSummary: String?
    let risks: [TripRisk]?

    func toModel() -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: placeId,
            placeState: placeState,
            placeName: placeName,
            time: time,
            duration: duration,
            note: note,
            sourceSummary: sourceSummary,
            risks: risks ?? []
        )
    }
}
