import Foundation

struct SavePlanAroundRequest: Hashable {
    var anchorResultID: String
    var duration: SavePlanDuration
    var intent: SavePlanIntent
}

enum SavePlanDuration: String, CaseIterable, Hashable {
    case quickStop = "quick_stop"
    case halfDay = "half_day"
    case fullDay = "full_day"

    var displayName: String {
        switch self {
        case .quickStop: return "Quick stop"
        case .halfDay: return "Half day"
        case .fullDay: return "Full day"
        }
    }

    var maxStops: Int {
        switch self {
        case .quickStop: return 3
        case .halfDay: return 5
        case .fullDay: return 8
        }
    }

    var maxDistanceMeters: Double {
        switch self {
        case .quickStop: return 3_000
        case .halfDay: return 8_000
        case .fullDay: return 16_000
        }
    }
}

enum SavePlanIntent: String, CaseIterable, Hashable {
    case balanced
    case food
    case coffee
    case culture
    case shopping

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .food: return "Food"
        case .coffee: return "Coffee"
        case .culture: return "Culture"
        case .shopping: return "Shopping"
        }
    }
}

enum SavePlanStopSource: String, Hashable {
    case anchor
    case userSaved
    case pendingCandidate
    case unsavedMapCandidate
}

struct SavePlanStop: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var source: SavePlanStopSource
    var category: PlaceCategory?
    var distanceMeters: Double?
    var distanceLabel: String?
    var reason: String
    var latitude: Double?
    var longitude: Double?
}

struct SavePlanAroundDraft: Identifiable, Hashable {
    var id: UUID
    var request: SavePlanAroundRequest
    var anchor: SavePlanStop
    var nearbySaved: [SavePlanStop]
    var newSuggestions: [SavePlanStop]
    var routeStops: [SavePlanStop]
    var routeNotes: [String]
    var explanation: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        request: SavePlanAroundRequest,
        anchor: SavePlanStop,
        nearbySaved: [SavePlanStop],
        newSuggestions: [SavePlanStop],
        routeStops: [SavePlanStop],
        routeNotes: [String],
        explanation: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.anchor = anchor
        self.nearbySaved = nearbySaved
        self.newSuggestions = newSuggestions
        self.routeStops = routeStops
        self.routeNotes = routeNotes
        self.explanation = explanation
        self.createdAt = createdAt
    }
}

struct SavePlanBlockedState: Hashable {
    var title: String
    var message: String
    var missingInfo: [String]
    var allowedActions: [SaveSearchPrimaryAction]
}

enum SavePlanAroundResult: Identifiable, Hashable {
    case draft(SavePlanAroundDraft)
    case blocked(SavePlanBlockedState)

    var id: String {
        switch self {
        case .draft(let draft): return "draft-\(draft.id.uuidString)"
        case .blocked(let state): return "blocked-\(state.title)-\(state.missingInfo.joined(separator: "-"))"
        }
    }
}
