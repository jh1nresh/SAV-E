import Foundation

enum RelatedSourcePlatform: String, Codable, CaseIterable, Equatable, Sendable {
    case instagram
    case tiktok
    case youtube
    case xiaohongshu
    case douyin
    case threads
    case x

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .xiaohongshu: return "Xiaohongshu"
        case .douyin: return "Douyin"
        case .threads: return "Threads"
        case .x: return "X"
        }
    }

    fileprivate func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let rawHost = url.host?.lowercased()
        else { return false }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        return allowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private var allowedHosts: [String] {
        switch self {
        case .instagram: return ["instagram.com"]
        case .tiktok: return ["tiktok.com"]
        case .youtube: return ["youtube.com", "youtu.be"]
        case .xiaohongshu: return ["xiaohongshu.com", "xhslink.com"]
        case .douyin: return ["douyin.com", "iesdouyin.com"]
        case .threads: return ["threads.net"]
        case .x: return ["x.com", "twitter.com"]
        }
    }
}

enum RelatedSourceRelation: String, Codable, Equatable, Sendable {
    case samePlace = "same_place"
    case mentionsPlace = "mentions_place"
}

enum RelatedSourceIdentityStatus: String, Codable, Equatable, Sendable {
    case candidate
}

enum RelatedSourceCoverageStatus: String, Codable, Equatable, Sendable {
    case searched
    case partial
    case failed
}

enum RelatedSourceSearchMethod: String, Codable, Equatable, Sendable {
    case publicIndex = "public_index"
}

enum RelatedSourceBlockedReason: String, Codable, Equatable, Sendable {
    case publicSearchFailed = "public_search_failed"
}

struct RelatedSourcePlaceIdentity: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let googlePlaceId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case latitude
        case longitude
        case googlePlaceId = "google_place_id"
    }
}

struct RelatedPlaceSource: Codable, Equatable, Identifiable, Sendable {
    let platform: RelatedSourcePlatform
    let url: URL
    let title: String
    let snippet: String?
    let query: String
    let relation: RelatedSourceRelation
    let identityStatus: RelatedSourceIdentityStatus
    let matchConfidence: Double

    var id: String {
        "\(platform.rawValue)|\(url.absoluteString)"
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case url
        case title
        case snippet
        case query
        case relation
        case identityStatus = "identity_status"
        case matchConfidence = "match_confidence"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let platform = try container.decode(RelatedSourcePlatform.self, forKey: .platform)
        let rawURL = try container.decode(String.self, forKey: .url)
        guard let url = URL(string: rawURL), platform.allows(url) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Related-source URL is not an allowlisted HTTPS platform URL"
            )
        }

        let confidence = try container.decode(Double.self, forKey: .matchConfidence)
        guard (0...1).contains(confidence) else {
            throw DecodingError.dataCorruptedError(
                forKey: .matchConfidence,
                in: container,
                debugDescription: "Related-source confidence must be between zero and one"
            )
        }

        self.platform = platform
        self.url = url
        self.title = try container.decode(String.self, forKey: .title)
        self.snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        self.query = try container.decode(String.self, forKey: .query)
        self.relation = try container.decode(RelatedSourceRelation.self, forKey: .relation)
        self.identityStatus = try container.decode(RelatedSourceIdentityStatus.self, forKey: .identityStatus)
        self.matchConfidence = confidence
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(snippet, forKey: .snippet)
        try container.encode(query, forKey: .query)
        try container.encode(relation, forKey: .relation)
        try container.encode(identityStatus, forKey: .identityStatus)
        try container.encode(matchConfidence, forKey: .matchConfidence)
    }
}

struct RelatedSourceCoverage: Codable, Equatable, Identifiable, Sendable {
    let platform: RelatedSourcePlatform
    let method: RelatedSourceSearchMethod
    let status: RelatedSourceCoverageStatus
    let queries: [String]
    let inspectedCount: Int
    let resultCount: Int
    let blockedReason: RelatedSourceBlockedReason?

    var id: RelatedSourcePlatform { platform }

    private enum CodingKeys: String, CodingKey {
        case platform
        case method
        case status
        case queries
        case inspectedCount = "inspected_count"
        case resultCount = "result_count"
        case blockedReason = "blocked_reason"
    }
}

struct RelatedSourcesReceipt: Codable, Equatable, Sendable {
    let sourceBoundary: String
    let privacy: String
    let checkedAt: String
    let requestedPlatforms: [RelatedSourcePlatform]
    let searchedPlatforms: [RelatedSourcePlatform]
    let failedPlatforms: [RelatedSourcePlatform]
    let rawResultCount: Int
    let independentResultCount: Int
    let missing: [String]

    private enum CodingKeys: String, CodingKey {
        case sourceBoundary = "source_boundary"
        case privacy
        case checkedAt = "checked_at"
        case requestedPlatforms = "requested_platforms"
        case searchedPlatforms = "searched_platforms"
        case failedPlatforms = "failed_platforms"
        case rawResultCount = "raw_result_count"
        case independentResultCount = "independent_result_count"
        case missing
    }
}

struct RelatedPlaceSourcePack: Codable, Equatable, Sendable {
    let place: RelatedSourcePlaceIdentity
    let sources: [RelatedPlaceSource]
    let coverage: [RelatedSourceCoverage]
    let receipt: RelatedSourcesReceipt
}

enum RelatedPlaceSourcesClientError: LocalizedError, Equatable {
    case invalidPlatforms
    case invalidMaxResults

    var errorDescription: String? {
        switch self {
        case .invalidPlatforms:
            return "Choose at least one supported source platform."
        case .invalidMaxResults:
            return "Related-source result limit must be between 1 and 5."
        }
    }
}
