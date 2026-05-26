import Foundation

struct SaveGuide: Identifiable, Hashable {
    var id: UUID
    var title: String
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var creatorLabel: String?
    var cityOrArea: String?
    var stops: [SaveGuideStop]
    var evidence: [String]

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: String? = nil,
        sourcePlatform: SourcePlatform? = nil,
        creatorLabel: String? = nil,
        cityOrArea: String? = nil,
        stops: [SaveGuideStop],
        evidence: [String] = []
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.creatorLabel = creatorLabel
        self.cityOrArea = cityOrArea
        self.stops = stops
        self.evidence = evidence
    }
}

struct SaveGuideStop: Identifiable, Hashable {
    var id: UUID
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var evidence: [String]
    var state: SaveGuideStopState

    init(
        id: UUID = UUID(),
        title: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        category: PlaceCategory? = nil,
        sourceURL: String? = nil,
        sourcePlatform: SourcePlatform? = nil,
        evidence: [String] = [],
        state: SaveGuideStopState = .guideOnly
    ) {
        self.id = id
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.evidence = evidence
        self.state = state
    }
}

enum SaveGuideStopState: String, Hashable {
    case guideOnly = "guide_only"
    case alreadySaved = "already_saved"
    case copiedToTrip = "copied_to_trip"
    case savedToMemory = "saved_to_memory"
    case needsRecovery = "needs_recovery"

    var displayName: String {
        switch self {
        case .guideOnly: return "Guide only"
        case .alreadySaved: return "Already saved"
        case .copiedToTrip: return "Copied to trip"
        case .savedToMemory: return "Saved to memory"
        case .needsRecovery: return "Needs recovery"
        }
    }
}

enum SaveGuidePlanStopOrigin: String, Hashable {
    case guideOnly = "guide_only"
    case userSaved = "user_saved"
    case needsRecovery = "needs_recovery"
    case newSuggestion = "new_suggestion"
}

struct SaveGuidePlanStop: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var origin: SaveGuidePlanStopOrigin
    var category: PlaceCategory?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var reason: String
    var placeId: UUID?
    var guideStopId: UUID?
}

struct SaveGuideCustomizationDraft: Hashable {
    var originalGuide: SaveGuide
    var keepStops: [SaveGuideStop]
    var swapInSavedPlaces: [SaveGuidePlanStop]
    var addNearbySuggestions: [SaveGuidePlanStop]
    var explanation: String
}
