import Foundation

enum SaveMemoryState: String, Codable, CaseIterable {
    case sourceOnly = "source_only"
    case reviewCandidate = "review_candidate"
    case confirmedPlace = "confirmed_place"

    var displayName: String {
        switch self {
        case .sourceOnly: return "Source only"
        case .reviewCandidate: return "Review candidate"
        case .confirmedPlace: return "Confirmed place"
        }
    }
}

struct SaveMemoryRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var state: SaveMemoryState
    var sourceURL: String?
    var sourceText: String?
    var title: String
    var placeName: String?
    var address: String?
    var evidence: [String]
    var evidenceDiagnostic: SocialPlaceEvidenceDiagnostic?
    var placeHighlights: [String]
    var recommendedItems: [RecommendedItem]
    var vibeTags: [String]
    var accessNotes: [String]
    var sourceHandle: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory?
    var status: PlaceStatus?
    var rating: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        state: SaveMemoryState,
        sourceURL: String? = nil,
        sourceText: String? = nil,
        title: String,
        placeName: String? = nil,
        address: String? = nil,
        evidence: [String] = [],
        evidenceDiagnostic: SocialPlaceEvidenceDiagnostic? = nil,
        placeHighlights: [String] = [],
        recommendedItems: [RecommendedItem] = [],
        vibeTags: [String] = [],
        accessNotes: [String] = [],
        sourceHandle: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        category: PlaceCategory? = nil,
        status: PlaceStatus? = nil,
        rating: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.state = state
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.title = title
        self.placeName = placeName
        self.address = address
        self.evidence = evidence
        self.evidenceDiagnostic = evidenceDiagnostic
        let extracted = SocialPlaceStructuredHighlights.extracted(from: evidence, sourceURL: sourceURL)
        self.placeHighlights = placeHighlights.isEmpty ? extracted.placeHighlights : placeHighlights
        self.recommendedItems = recommendedItems.isEmpty ? extracted.recommendedItems : recommendedItems
        self.vibeTags = vibeTags.isEmpty ? extracted.vibeTags : vibeTags
        self.accessNotes = accessNotes.isEmpty ? extracted.accessNotes : accessNotes
        self.sourceHandle = sourceHandle ?? extracted.sourceHandle
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.status = status
        self.rating = rating
        self.createdAt = createdAt
    }

    var displayTitle: String {
        if let placeName, !placeName.isEmpty { return placeName }
        if !title.isEmpty { return title }
        return sourceURL ?? "Untitled source"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case state
        case sourceURL
        case sourceText
        case title
        case placeName
        case address
        case evidence
        case evidenceDiagnostic
        case placeHighlights
        case recommendedItems
        case vibeTags
        case accessNotes
        case sourceHandle
        case latitude
        case longitude
        case category
        case status
        case rating
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        state = try container.decode(SaveMemoryState.self, forKey: .state)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        title = try container.decode(String.self, forKey: .title)
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        evidenceDiagnostic = try container.decodeIfPresent(SocialPlaceEvidenceDiagnostic.self, forKey: .evidenceDiagnostic)
        let extracted = SocialPlaceStructuredHighlights.extracted(from: evidence + [sourceText ?? ""], sourceURL: sourceURL)
        placeHighlights = try container.decodeIfPresent([String].self, forKey: .placeHighlights) ?? extracted.placeHighlights
        recommendedItems = try container.decodeIfPresent([RecommendedItem].self, forKey: .recommendedItems) ?? extracted.recommendedItems
        vibeTags = try container.decodeIfPresent([String].self, forKey: .vibeTags) ?? extracted.vibeTags
        accessNotes = try container.decodeIfPresent([String].self, forKey: .accessNotes) ?? extracted.accessNotes
        sourceHandle = try container.decodeIfPresent(String.self, forKey: .sourceHandle) ?? extracted.sourceHandle
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        category = try container.decodeIfPresent(PlaceCategory.self, forKey: .category)
        status = try container.decodeIfPresent(PlaceStatus.self, forKey: .status)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
