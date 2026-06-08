import Foundation

struct SavePlanAroundRequest: Hashable {
    var anchorResultID: String
    var duration: SavePlanDuration
    var intent: SavePlanIntent
    var planIntent: SavePlanIntentContract

    init(
        anchorResultID: String,
        duration: SavePlanDuration,
        intent: SavePlanIntent,
        planIntent: SavePlanIntentContract = SavePlanIntentContract()
    ) {
        self.anchorResultID = anchorResultID
        self.duration = duration
        self.intent = intent
        var resolvedPlanIntent = planIntent
        if resolvedPlanIntent.duration == nil {
            resolvedPlanIntent.duration = duration
        }
        self.planIntent = resolvedPlanIntent
    }
}

struct SavePlanIntentContract: Hashable {
    var cityOrRegion: String?
    var duration: SavePlanDuration?
    var dateText: String?
    var timeWindow: String?
    var transportMode: SaveAIResponse.TransportMode?
    var pace: ItineraryPace
    var mustIncludeResultIDs: Set<String>
    var avoidResultIDs: Set<String>
    var categoryGoals: [PlaceCategory]
    var vibe: String?
    var budget: String?
    var mealPreferences: [String]
    var allowedPublicFillerSlots: [SavePlanFillerSlot]

    init(
        cityOrRegion: String? = nil,
        duration: SavePlanDuration? = nil,
        dateText: String? = nil,
        timeWindow: String? = nil,
        transportMode: SaveAIResponse.TransportMode? = nil,
        pace: ItineraryPace = .balanced,
        mustIncludeResultIDs: Set<String> = [],
        avoidResultIDs: Set<String> = [],
        categoryGoals: [PlaceCategory] = [],
        vibe: String? = nil,
        budget: String? = nil,
        mealPreferences: [String] = [],
        allowedPublicFillerSlots: [SavePlanFillerSlot] = SavePlanFillerSlot.allCases
    ) {
        self.cityOrRegion = cityOrRegion
        self.duration = duration
        self.dateText = dateText
        self.timeWindow = timeWindow
        self.transportMode = transportMode
        self.pace = pace
        self.mustIncludeResultIDs = mustIncludeResultIDs
        self.avoidResultIDs = avoidResultIDs
        self.categoryGoals = categoryGoals
        self.vibe = vibe
        self.budget = budget
        self.mealPreferences = mealPreferences
        self.allowedPublicFillerSlots = allowedPublicFillerSlots
    }
}

enum SavePlanFillerSlot: String, CaseIterable, Hashable {
    case breakfast
    case coffee
    case viewpoint
    case museum
    case walkableActivity = "walkable_activity"
    case dinner
    case lateNight = "late_night"

    var displayName: String {
        switch self {
        case .breakfast: return "breakfast"
        case .coffee: return "coffee"
        case .viewpoint: return "viewpoint"
        case .museum: return "museum"
        case .walkableActivity: return "walkable activity"
        case .dinner: return "dinner"
        case .lateNight: return "late-night stop"
        }
    }

    var preferredCategories: Set<PlaceCategory> {
        switch self {
        case .breakfast, .dinner:
            return [.food]
        case .coffee:
            return [.cafe]
        case .viewpoint, .museum, .walkableActivity:
            return [.attraction, .shopping]
        case .lateNight:
            return [.bar, .food]
        }
    }
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

    var sourceLabel: String {
        switch self {
        case .anchor, .userSaved:
            return "From your SAV-E"
        case .pendingCandidate:
            return "Review candidate"
        case .unsavedMapCandidate:
            return "New recommendation"
        }
    }
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
    var evidence: [String]
    var fillerSlot: SavePlanFillerSlot?

    var sourceLabel: String {
        source.sourceLabel
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        source: SavePlanStopSource,
        category: PlaceCategory?,
        distanceMeters: Double?,
        distanceLabel: String?,
        reason: String,
        latitude: Double?,
        longitude: Double?,
        evidence: [String] = [],
        fillerSlot: SavePlanFillerSlot? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.category = category
        self.distanceMeters = distanceMeters
        self.distanceLabel = distanceLabel
        self.reason = reason
        self.latitude = latitude
        self.longitude = longitude
        self.evidence = evidence
        self.fillerSlot = fillerSlot
    }
}

struct SavePlanRetrievalReceipt: Hashable {
    var sourceBoundary: String
    var querySelector: String
    var candidateCount: Int
    var filterRule: String
    var scoreRule: String
    var skippedReasons: [String]
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
    var unfilledGaps: [SavePlanFillerSlot]
    var retrievalReceipt: SavePlanRetrievalReceipt
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
        unfilledGaps: [SavePlanFillerSlot] = [],
        retrievalReceipt: SavePlanRetrievalReceipt = SavePlanRetrievalReceipt(
            sourceBoundary: "Confirmed Map Stamps first; public recommendations stay unsaved.",
            querySelector: "No public recommendation query was run.",
            candidateCount: 0,
            filterRule: "No candidates evaluated.",
            scoreRule: "No candidates scored.",
            skippedReasons: []
        ),
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
        self.unfilledGaps = unfilledGaps
        self.retrievalReceipt = retrievalReceipt
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
