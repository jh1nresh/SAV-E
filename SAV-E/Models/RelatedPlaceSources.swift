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

    fileprivate func validatedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let rawHost = url.host?.lowercased()
        else { return nil }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if self == .threads {
            guard url.user == nil, url.password == nil, url.port == nil, allowedHosts.contains(host),
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.percentEncodedPath.range(of: #"^/@[A-Za-z0-9._]{1,100}/post/[A-Za-z0-9_-]{1,100}(?:/[^/]+)?/?$"#,
                                                       options: .regularExpression) != nil else { return nil }
            let path = components.percentEncodedPath.split(separator: "/")
            components.percentEncodedPath = "/\(path[0].lowercased())/post/\(path[2])"
            components.percentEncodedQuery = nil
            components.percentEncodedFragment = nil
            return components.url
        }
        return allowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") } ? url : nil
    }

    private var allowedHosts: [String] {
        switch self {
        case .instagram: return ["instagram.com"]
        case .tiktok: return ["tiktok.com"]
        case .youtube: return ["youtube.com", "youtu.be"]
        case .xiaohongshu: return ["xiaohongshu.com", "xhslink.com"]
        case .douyin: return ["douyin.com", "iesdouyin.com"]
        case .threads: return ["threads.com", "threads.net"]
        case .x: return ["x.com", "twitter.com"]
        }
    }
}

private enum InvalidThreadsSourceURL: Error {
    case invalidOriginal
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
    let requestedGooglePlaceId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case latitude
        case longitude
        case googlePlaceId = "google_place_id"
        case requestedGooglePlaceId = "requested_google_place_id"
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
        guard let url = platform.validatedURL(rawURL) else {
            if platform == .threads { throw InvalidThreadsSourceURL.invalidOriginal }
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
    fileprivate(set) var resultCount: Int
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
    fileprivate(set) var independentResultCount: Int
    fileprivate(set) var missing: [String]

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

struct RelatedSourcesStorage: Codable, Equatable, Sendable {
    let persistence: String
    let fetchedAt: String
    let staleAfter: String
    let isStale: Bool
    let querySet: [String]

    private enum CodingKeys: String, CodingKey {
        case persistence
        case fetchedAt = "fetched_at"
        case staleAfter = "stale_after"
        case isStale = "is_stale"
        case querySet = "query_set"
    }
}

struct RelatedPlaceSourcePack: Codable, Equatable, Sendable {
    let place: RelatedSourcePlaceIdentity
    let sources: [RelatedPlaceSource]
    let coverage: [RelatedSourceCoverage]
    let receipt: RelatedSourcesReceipt
    let storage: RelatedSourcesStorage?

    private enum CodingKeys: String, CodingKey {
        case place, sources, coverage, receipt, storage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        place = try container.decode(RelatedSourcePlaceIdentity.self, forKey: .place)
        var decodedCoverage = try container.decode([RelatedSourceCoverage].self, forKey: .coverage)
        var decodedReceipt = try container.decode(RelatedSourcesReceipt.self, forKey: .receipt)
        storage = try container.decodeIfPresent(RelatedSourcesStorage.self, forKey: .storage)
        var rows = try container.nestedUnkeyedContainer(forKey: .sources)
        var decodedSources: [RelatedPlaceSource] = []
        var threadOriginals = Set<String>()
        var filteredThreads = false
        while !rows.isAtEnd {
            let row = try rows.superDecoder()
            do {
                let source = try RelatedPlaceSource(from: row)
                if source.platform == .threads, !threadOriginals.insert(source.url.path).inserted {
                    filteredThreads = true
                    continue
                }
                decodedSources.append(source)
            } catch InvalidThreadsSourceURL.invalidOriginal {
                // An older backend can still serve cached non-post Threads links.
                filteredThreads = true
            }
        }
        if filteredThreads {
            if let index = decodedCoverage.firstIndex(where: { $0.platform == .threads }) {
                decodedCoverage[index].resultCount = threadOriginals.count
                let noSource = "threads: no same-place public source found"
                decodedReceipt.missing.removeAll { $0 == noSource }
                if threadOriginals.isEmpty, decodedCoverage[index].status != .failed {
                    decodedReceipt.missing.append(noSource)
                }
            }
            decodedReceipt.independentResultCount = decodedSources.count
        }
        sources = decodedSources
        coverage = decodedCoverage
        receipt = decodedReceipt
    }
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
