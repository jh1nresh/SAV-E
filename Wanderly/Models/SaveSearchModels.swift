import Foundation

enum SaveSearchObjectType: String, Codable, CaseIterable, Hashable {
    case savedPlace = "saved_place"
    case pendingCandidate = "pending_candidate"
    case sourceOnlyClue = "source_only_clue"
    case triedMemory = "tried_memory"
    case review = "review"
    case tripStop = "trip_stop"
    case newRecommendation = "new_recommendation"

    var displayName: String {
        switch self {
        case .savedPlace: return "Memory card"
        case .pendingCandidate: return "Review clue"
        case .sourceOnlyClue: return "Source clue"
        case .triedMemory: return "Tried memory"
        case .review: return "Private review"
        case .tripStop: return "Trip stop"
        case .newRecommendation: return "New recommendation"
        }
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
    var confidence: Double?
    var missingInfo: [String]
    var evidence: [String]
    var createdAt: Date
    var canRunRecovery: Bool
    var isRecommendationShell: Bool

    var searchText: String {
        [
            title,
            subtitle,
            statusLabel,
            sourceURL,
            sourcePlatform?.displayName,
            category?.displayName,
            cityOrArea,
            missingInfo.joined(separator: " "),
            evidence.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
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
