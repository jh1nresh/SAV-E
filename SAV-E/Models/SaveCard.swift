import Foundation

struct SaveCard: Codable, Hashable, Identifiable {
    static let schemaVersion = "save.card.v0"

    var schema: String
    var cardType: SaveCardType
    var id: String
    var title: String
    var createdAt: Date
    var createdBy: String
    var visibility: SaveCardVisibility
    var source: SaveCardSource
    var places: [SaveCardPlace]
    var humanSummary: String
    var agentInstructions: [String]
    var redactions: [SaveCardRedaction]
    var actions: [SaveCardAction]

    var isValidSchema: Bool {
        schema == Self.schemaVersion
    }
}

enum SaveCardType: String, Codable, Hashable {
    case placeCard = "place_card"
    case recommendationCard = "recommendation_card"
    case itineraryCard = "itinerary_card"
    case reviewCard = "review_card"
}

enum SaveCardVisibility: String, Codable, Hashable {
    case `private`
    case publicLink = "public_link"
    case friends
    case agentReadable = "agent_readable"
}

struct SaveCardSource: Codable, Hashable {
    var kind: SaveCardSourceKind
    var url: String?
}

enum SaveCardSourceKind: String, Codable, Hashable {
    case instagram
    case luma
    case googleMaps = "google_maps"
    case appleMaps = "apple_maps"
    case manual
    case other
}

struct SaveCardPlace: Codable, Hashable {
    var name: String
    var address: String
    var geo: SaveCardGeo?
    var status: SaveCardPlaceStatus
    var confidence: Double?
    var proofLevel: SaveCardProofLevel
    var evidence: [String]
    var missingInfo: [String]
    var placeHighlights: [String] = []
    var recommendedItems: [RecommendedItem] = []
    var vibeTags: [String] = []
    var accessNotes: [String] = []
    var sourceHandle: String? = nil
}

extension SaveCardPlace {
    private enum CodingKeys: String, CodingKey {
        case name
        case address
        case geo
        case status
        case confidence
        case proofLevel
        case evidence
        case missingInfo
        case placeHighlights
        case recommendedItems
        case vibeTags
        case accessNotes
        case sourceHandle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        geo = try container.decodeIfPresent(SaveCardGeo.self, forKey: .geo)
        status = try container.decode(SaveCardPlaceStatus.self, forKey: .status)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        proofLevel = try container.decode(SaveCardProofLevel.self, forKey: .proofLevel)
        evidence = try container.decode([String].self, forKey: .evidence)
        missingInfo = try container.decode([String].self, forKey: .missingInfo)
        let extracted = SocialPlaceStructuredHighlights.extracted(from: evidence)
        placeHighlights = try container.decodeIfPresent([String].self, forKey: .placeHighlights) ?? extracted.placeHighlights
        recommendedItems = try container.decodeIfPresent([RecommendedItem].self, forKey: .recommendedItems) ?? extracted.recommendedItems
        vibeTags = try container.decodeIfPresent([String].self, forKey: .vibeTags) ?? extracted.vibeTags
        accessNotes = try container.decodeIfPresent([String].self, forKey: .accessNotes) ?? extracted.accessNotes
        sourceHandle = try container.decodeIfPresent(String.self, forKey: .sourceHandle) ?? extracted.sourceHandle
    }
}

struct SaveCardGeo: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

enum SaveCardPlaceStatus: String, Codable, Hashable {
    case sourceOnly = "source_only"
    case reviewCandidate = "review_candidate"
    case confirmedPlace = "confirmed_place"
    case visited
}

enum SaveCardProofLevel: String, Codable, Hashable {
    case sourceLink = "source_link"
    case mapConfirmed = "map_confirmed"
    case visited
    case receiptBacked = "receipt_backed"
    case paymentBacked = "payment_backed"
}

struct SaveCardRedaction: Codable, Hashable {
    var field: String
    var reason: String
}

enum SaveCardAction: String, Codable, Hashable {
    case save
    case openMaps = "open_maps"
    case askAgent = "ask_agent"
    case `import`
}
