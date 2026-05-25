import Foundation

enum SaveSearchObjectType: String, Codable, CaseIterable, Hashable {
    case savedPlace = "saved_place"
    case pendingCandidate = "pending_candidate"
    case sourceOnlyClue = "source_only_clue"
    case triedMemory = "tried_memory"
    case review = "review"
    case tripStop = "trip_stop"
    case mapVisibleUnsavedPlace = "map_visible_unsaved_place"
    case newRecommendation = "new_recommendation"

    var displayName: String {
        switch self {
        case .savedPlace: return "Memory card"
        case .pendingCandidate: return "Review clue"
        case .sourceOnlyClue: return "Source clue"
        case .triedMemory: return "Tried memory"
        case .review: return "Private review"
        case .tripStop: return "Trip stop"
        case .mapVisibleUnsavedPlace: return "Map place"
        case .newRecommendation: return "New recommendation"
        }
    }
}

enum SaveSearchPrimaryAction: String, Codable, Hashable {
    case openSource = "open_source"
    case runRecovery = "run_recovery"
    case savePlace = "save_place"
    case planAround = "plan_around"
    case addToTrip = "add_to_trip"
    case markTried = "mark_tried"
    case addReview = "add_review"
    case addProof = "add_proof"
    case showNearby = "show_nearby"
    case none = "none"

    var displayName: String {
        switch self {
        case .openSource: return "Open source"
        case .runRecovery: return "Find exact place"
        case .savePlace: return "Save this place"
        case .planAround: return "Plan around this"
        case .addToTrip: return "Add to trip"
        case .markTried: return "Mark as tried"
        case .addReview: return "Add private review"
        case .addProof: return "Add proof"
        case .showNearby: return "Show nearby"
        case .none: return "No action"
        }
    }

    var systemImage: String {
        switch self {
        case .openSource: return "link"
        case .runRecovery: return "sparkle.magnifyingglass"
        case .savePlace: return "bookmark.badge.plus"
        case .planAround: return "wand.and.stars"
        case .addToTrip: return "plus.square.on.square"
        case .markTried: return "checkmark.seal"
        case .addReview: return "text.bubble"
        case .addProof: return "receipt"
        case .showNearby: return "location.magnifyingglass"
        case .none: return "circle"
        }
    }
}

struct SaveAgentDrawerAction: Identifiable, Hashable {
    var kind: SaveSearchPrimaryAction
    var label: String
    var systemImage: String

    var id: SaveSearchPrimaryAction { kind }

    init(kind: SaveSearchPrimaryAction, label: String? = nil) {
        self.kind = kind
        self.label = label ?? kind.displayName
        self.systemImage = kind.systemImage
    }
}

struct SaveAgentActionDrawerModel: Hashable {
    var heading: String
    var contextLine: String
    var primaryAction: SaveAgentDrawerAction
    var secondaryActions: [SaveAgentDrawerAction]
    var evidenceSummary: String
    var missingInfo: [String]

    init(result: SaveSearchResult) {
        heading = Self.heading(for: result)
        contextLine = Self.contextLine(for: result)
        primaryAction = SaveAgentDrawerAction(kind: Self.primaryAction(for: result))
        secondaryActions = Self.secondaryActions(for: result, excluding: primaryAction.kind)
        evidenceSummary = Self.evidenceSummary(for: result)
        missingInfo = result.missingInfo
    }

    private static func heading(for result: SaveSearchResult) -> String {
        switch result.objectType {
        case .sourceOnlyClue: return "Recover exact place"
        case .pendingCandidate: return "Confirm candidate"
        case .mapVisibleUnsavedPlace: return "Collect map place"
        case .savedPlace: return "Plan from memory"
        case .triedMemory: return "Capture tried memory"
        case .review: return "Upgrade review proof"
        case .tripStop: return "Use trip stop"
        case .newRecommendation: return "Search outside SAV-E"
        }
    }

    private static func contextLine(for result: SaveSearchResult) -> String {
        switch result.objectType {
        case .sourceOnlyClue:
            return "SAV-E has a source clue but still needs a confirmed map match."
        case .pendingCandidate:
            return "SAV-E found a likely place; confirm it before it becomes a memory card."
        case .mapVisibleUnsavedPlace:
            return "This place is visible on the map but is not saved to your SAV-E yet."
        case .savedPlace:
            return "Use this saved place as an anchor for nearby plans and trips."
        case .triedMemory:
            return "Turn the visit into a private review or proof-backed memory."
        case .review:
            return "Keep the review private by default and add proof only when useful."
        case .tripStop:
            return "Reuse this stop in a route or guide."
        case .newRecommendation:
            return "Search new places without mixing them into saved memories."
        }
    }

    private static func primaryAction(for result: SaveSearchResult) -> SaveSearchPrimaryAction {
        switch result.objectType {
        case .sourceOnlyClue: return .runRecovery
        case .pendingCandidate, .mapVisibleUnsavedPlace: return .savePlace
        case .savedPlace, .tripStop: return .planAround
        case .triedMemory: return .addReview
        case .review: return .addProof
        case .newRecommendation: return result.primaryAction
        }
    }

    private static func secondaryActions(for result: SaveSearchResult, excluding primary: SaveSearchPrimaryAction) -> [SaveAgentDrawerAction] {
        var actions: [SaveSearchPrimaryAction] = []

        switch result.objectType {
        case .sourceOnlyClue:
            actions = [.openSource]
        case .pendingCandidate:
            actions = [.openSource, .runRecovery]
        case .mapVisibleUnsavedPlace:
            actions = [.planAround, .openSource, .showNearby]
        case .savedPlace:
            actions = [.openSource, .addToTrip, .showNearby, .markTried]
        case .triedMemory:
            actions = [.addProof, .planAround, .addToTrip]
        case .review:
            actions = [.openSource, .planAround]
        case .tripStop:
            actions = [.addToTrip, .showNearby]
        case .newRecommendation:
            actions = []
        }

        if !hasValidHTTPSourceURL(result.sourceURL) {
            actions.removeAll { $0 == .openSource }
        }
        actions.removeAll { $0 == primary || $0 == .none }

        var seen = Set<SaveSearchPrimaryAction>()
        return actions.compactMap { action in
            guard seen.insert(action).inserted else { return nil }
            return SaveAgentDrawerAction(kind: action)
        }
    }

    private static func hasValidHTTPSourceURL(_ sourceURL: String?) -> Bool {
        guard
            let rawValue = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host?.isEmpty == false
        else {
            return false
        }
        return true
    }

    private static func evidenceSummary(for result: SaveSearchResult) -> String {
        if !result.missingInfo.isEmpty {
            return "Missing: \(result.missingInfo.prefix(3).joined(separator: ", "))"
        }
        if result.objectType == .mapVisibleUnsavedPlace {
            return "Evidence: \(result.evidence.first ?? "Visible on map; not saved yet")"
        }
        if let sourcePlatform = result.sourcePlatform {
            return "Evidence: \(sourcePlatform.displayName) source linked"
        }
        if let first = result.evidence.first {
            return "Evidence: \(first)"
        }
        return "Evidence: no source attached yet"
    }
}

struct SaveMapCandidate: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var category: PlaceCategory?
    var rating: Double?
    var reviewCount: Int?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var evidence: [String]
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory? = nil,
        rating: Double? = nil,
        reviewCount: Int? = nil,
        sourceURL: String? = nil,
        sourcePlatform: SourcePlatform? = nil,
        evidence: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.rating = rating
        self.reviewCount = reviewCount
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

enum SaveSearchUserState: String, Codable, CaseIterable, Hashable {
    case wantToGo = "want_to_go"
    case waitingReview = "waiting_review"
    case sourceOnly = "source_only"
    case visited = "visited"
    case reviewed = "reviewed"
    case unsaved = "unsaved"

    var displayName: String {
        switch self {
        case .wantToGo: return "Want to go"
        case .waitingReview: return "Needs review"
        case .sourceOnly: return "Needs one more clue"
        case .visited: return "Visited"
        case .reviewed: return "Reviewed"
        case .unsaved: return "Unsaved"
        }
    }
}

enum SaveReviewVisibility: String, Codable, Hashable {
    case privateOnly = "private"
    case shareableSnapshot = "shareable_snapshot"
}

enum SaveReceiptProofKind: String, Codable, Hashable {
    case sourceLink = "source_link"
    case mapConfirmed = "map_confirmed"
    case visitMarked = "visit_marked"
    case receiptCommitment = "receipt_commitment"
}

struct SaveReceiptProofRef: Codable, Hashable {
    var kind: SaveReceiptProofKind
    var label: String
    var url: String?
    var commitmentHash: String?
}

struct SavePrivateReviewDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var placeId: UUID
    var rating: Double?
    var tags: [String]
    var note: String
    var visitDate: Date
    var visibility: SaveReviewVisibility
    var proofRefs: [SaveReceiptProofRef]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        placeId: UUID,
        rating: Double? = nil,
        tags: [String] = [],
        note: String = "",
        visitDate: Date = Date(),
        visibility: SaveReviewVisibility = .privateOnly,
        proofRefs: [SaveReceiptProofRef] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.placeId = placeId
        self.rating = rating
        self.tags = tags
        self.note = note
        self.visitDate = visitDate
        self.visibility = visibility
        self.proofRefs = proofRefs
        self.createdAt = createdAt
    }
}

struct SaveSearchResult: Identifiable, Hashable {
    var id: String
    var objectType: SaveSearchObjectType
    var userState: SaveSearchUserState
    var title: String
    var subtitle: String
    var statusLabel: String
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var category: PlaceCategory?
    var cityOrArea: String?
    var latitude: Double?
    var longitude: Double?
    var rating: Double?
    var reviewCount: Int?
    var confidence: Double?
    var missingInfo: [String]
    var evidence: [String]
    var createdAt: Date
    var canRunRecovery: Bool
    var isRecommendationShell: Bool
    var primaryAction: SaveSearchPrimaryAction

    var searchText: String {
        [
            title,
            subtitle,
            statusLabel,
            sourceURL,
            sourcePlatform?.displayName,
            category?.displayName,
            cityOrArea,
            rating.map { "rating \($0)" },
            reviewCount.map { "reviews \($0)" },
            missingInfo.joined(separator: " "),
            evidence.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var agentDrawer: SaveAgentActionDrawerModel {
        SaveAgentActionDrawerModel(result: self)
    }
}

struct SaveSearchSection: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var results: [SaveSearchResult]
    var emptyMessage: String?
}

struct SaveSearchResponse: Equatable {
    var query: String
    var fromYourSave: SaveSearchSection
    var newRecommendations: SaveSearchSection
}
