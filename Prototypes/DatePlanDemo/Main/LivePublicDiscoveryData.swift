#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation

enum LivePublicDiscoveryValidationError: Error, Equatable {
    case invalidViewport, invalidPage, invalidPost, invalidPlace, inconsistentPlace, invalidContinuation
}

struct LivePublicDiscoveryViewport: Equatable, Sendable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    init(west: Double, south: Double, east: Double, north: Double) throws {
        guard [west, south, east, north].allSatisfy(\.isFinite),
              (-180...180).contains(west), (-180...180).contains(east),
              (-90...90).contains(south), (-90...90).contains(north),
              south < north else { throw LivePublicDiscoveryValidationError.invalidViewport }
        self.west = west == 0 ? 0 : west
        self.south = south == 0 ? 0 : south
        self.east = east == 0 ? 0 : east
        self.north = north == 0 ? 0 : north
    }

    var queryValue: String { [west, south, east, north].map { String($0) }.joined(separator: ",") }

    func contains(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite, (-180...180).contains(longitude),
              (south...north).contains(latitude) else { return false }
        func includes(_ longitude: Double) -> Bool {
            west <= east ? (west...east).contains(longitude) : longitude >= west || longitude <= east
        }
        return includes(longitude) || (abs(longitude) == 180 && includes(-longitude))
    }
}

struct LivePublicDiscoveryCoverage: Codable, Equatable, Sendable {
    let platform: String
    let status: String
    let indexedPostCount: Int
}

/// Public attribution only. This is never a saved Place or a business photograph.
struct LivePublicDiscoveryPost: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let platform: String
    let sourceURL: String
    let authorName: String?
    let authorHandle: String?
    let title: String
    let publishedAt: String?
    let verifiedAt: String
    let visibility: String
    let locationEvidence: String
    let cover: LivePublicDiscoveryCover?
    let place: LivePublicDiscoveryPlace

    var sourceLink: URL? { LivePublicDiscoveryPolicy.source(sourceURL, platform: platform)?.url }
}

struct LivePublicDiscoveryPlace: Codable, Equatable, Sendable {
    let provider: String
    let providerPlaceID: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let coordinateSystem: String
    let category: String

    var identity: String { "\(provider):\(providerPlaceID)" }

    fileprivate func normalized() throws -> Self {
        guard ["apple_maps", "amap"].contains(provider), coordinateSystem == "WGS84",
              LivePublicDiscoveryPolicy.text(providerPlaceID, limit: 200),
              LivePublicDiscoveryPolicy.text(name, limit: 80), LivePublicDiscoveryPolicy.text(address, limit: 500),
              LivePublicDiscoveryPolicy.text(category, limit: 80),
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude), latitude != 0 || longitude != 0 else {
            throw LivePublicDiscoveryValidationError.invalidPlace
        }
        return Self(provider: provider, providerPlaceID: providerPlaceID.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude == 0 ? 0 : latitude, longitude: longitude == 0 ? 0 : longitude,
            coordinateSystem: coordinateSystem, category: category.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct LivePublicDiscoveryCover: Codable, Equatable, Sendable {
    let url: String
    let expiresAt: String
    let permission: String

    /// Also checks redirect destinations; the caller still owns expiry, byte limits and cancellation.
    static func validatedURL(_ raw: String, platform: String? = nil) -> URL? {
        guard let components = LivePublicDiscoveryPolicy.webURL(raw),
              let host = components.host?.lowercased(), components.path != "", components.path != "/",
              !LivePublicDiscoveryPolicy.hasToken(components) else { return nil }
        let meta = ["cdninstagram.com", "fbcdn.net"].contains { host == $0 || host.hasSuffix("." + $0) }
        let xhs = host == "xhscdn.com" || host.hasSuffix(".xhscdn.com") || isXiaohongshuImageHost(host)
        guard (platform == nil && (meta || xhs))
            || (["instagram", "threads"].contains(platform ?? "") && meta)
            || (platform == "xiaohongshu" && xhs) else { return nil }
        return components.url
    }

    func previewURL(at now: Date, platform: String? = nil) -> URL? {
        guard ["author", "provider"].contains(permission),
              let expiry = LivePublicDiscoveryPolicy.date(expiresAt), expiry > now else { return nil }
        return Self.validatedURL(url, platform: platform)
    }

    private static func isXiaohongshuImageHost(_ host: String) -> Bool {
        guard host.hasSuffix(".xiaohongshu.com") else { return false }
        let label = String(host.dropLast(".xiaohongshu.com".count))
        return label.range(of: "^(?:ci|sns-(?:img|webpic)(?:-[a-z0-9]+)*)$", options: .regularExpression) != nil
    }
}

/// Wire-only input. Consumers must obtain the separate validated value before presenting records.
struct LivePublicDiscoveryPage: Codable, Sendable {
    let schemaVersion: Int
    let indexRevision: String
    let generatedAt: String
    let expiresAt: String
    let coverage: [LivePublicDiscoveryCoverage]
    let posts: [LivePublicDiscoveryPost]
    let nextCursor: String?

    func validated(at now: Date, viewport: LivePublicDiscoveryViewport? = nil,
                   limit: Int = 50) throws -> LivePublicDiscoveryValidatedPage {
        guard now.timeIntervalSince1970.isFinite, schemaVersion == 1,
              indexRevision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let generated = LivePublicDiscoveryPolicy.date(generatedAt),
              let expiry = LivePublicDiscoveryPolicy.date(expiresAt),
              generated <= now, now.timeIntervalSince(generated) < 86_400,
              expiry > now, expiry > generated, expiry.timeIntervalSince(now) <= 300,
              expiry.timeIntervalSince(generated) <= 86_400,
              (1...50).contains(limit), posts.count <= limit,
              nextCursor == nil || nextCursor!.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              coverage.count == 3, Set(coverage.map(\.platform)) == LivePublicDiscoveryPolicy.platforms,
              coverage.allSatisfy({ row in
                  ["connected", "not_connected"].contains(row.status) && (0...5_000).contains(row.indexedPostCount)
                    && (row.status == "connected" || row.indexedPostCount == 0)
              }), coverage.reduce(0, { $0 + $1.indexedPostCount }) <= 5_000 else {
            throw LivePublicDiscoveryValidationError.invalidPage
        }
        var validatedPosts: [LivePublicDiscoveryPost] = []
        var ids = Set<String>()
        var verificationDates: [String: Date] = [:]
        for post in posts {
            guard ids.insert(post.id).inserted,
                  let row = coverage.first(where: { $0.platform == post.platform }), row.status == "connected",
                  posts.filter({ $0.platform == post.platform }).count <= row.indexedPostCount,
                  post.visibility == "public", ["explicit_geotag", "reviewed_match"].contains(post.locationEvidence),
                  LivePublicDiscoveryPolicy.text(post.title, limit: 160, allowEmpty: true),
                  post.authorName == nil || LivePublicDiscoveryPolicy.text(post.authorName!, limit: 80, allowEmpty: true),
                  post.authorHandle == nil || LivePublicDiscoveryPolicy.text(post.authorHandle!, limit: 100, allowEmpty: true),
                  let source = LivePublicDiscoveryPolicy.source(post.sourceURL, platform: post.platform),
                  post.id == "\(post.platform):\(source.postID)",
                  let verified = LivePublicDiscoveryPolicy.date(post.verifiedAt), verified <= generated,
                  now.timeIntervalSince(verified) < 86_400,
                  expiry <= verified.addingTimeInterval(86_400),
                  post.publishedAt == nil || LivePublicDiscoveryPolicy.date(post.publishedAt!).map({ $0 <= verified }) == true else {
                throw LivePublicDiscoveryValidationError.invalidPost
            }
            let normalizedPlace = try post.place.normalized()
            verificationDates[post.id] = verified
            if let viewport, !viewport.contains(latitude: post.place.latitude, longitude: post.place.longitude) {
                throw LivePublicDiscoveryValidationError.invalidPlace
            }
            validatedPosts.append(LivePublicDiscoveryPost(id: post.id, platform: post.platform,
                sourceURL: source.url.absoluteString,
                authorName: LivePublicDiscoveryPolicy.optionalText(post.authorName), authorHandle: LivePublicDiscoveryPolicy.optionalText(post.authorHandle),
                title: post.title.trimmingCharacters(in: .whitespacesAndNewlines), publishedAt: post.publishedAt, verifiedAt: post.verifiedAt,
                visibility: post.visibility, locationEvidence: post.locationEvidence,
                cover: post.cover?.previewURL(at: now, platform: post.platform) == nil ? nil : post.cover, place: normalizedPlace))
        }
        validatedPosts.sort {
            let left = verificationDates[$0.id]!, right = verificationDates[$1.id]!
            return left == right ? $0.id < $1.id : left > right
        }
        let coverDeadline = validatedPosts.compactMap { $0.cover.flatMap { LivePublicDiscoveryPolicy.date($0.expiresAt) } }.min()
        return try LivePublicDiscoveryValidatedPage(indexRevision: indexRevision, generatedAt: generated,
            expiresAt: min(expiry, coverDeadline ?? expiry), coverage: coverage, posts: validatedPosts, nextCursor: nextCursor)
    }
}

struct LivePublicDiscoveryVenue: Identifiable, Equatable, Sendable {
    let id: String
    let place: LivePublicDiscoveryPlace
    let posts: [LivePublicDiscoveryPost]

    /// Call with validated pages only. Cross-page venue conflicts must also fail closed.
    fileprivate static func grouping(_ posts: [LivePublicDiscoveryPost]) throws -> [Self] {
        guard posts.count <= 5_000, Set(posts.map(\.id)).count == posts.count else {
            throw LivePublicDiscoveryValidationError.invalidPage
        }
        var places: [String: LivePublicDiscoveryPlace] = [:]
        var groups: [String: [LivePublicDiscoveryPost]] = [:]
        var order: [String] = []
        for post in posts {
            _ = try post.place.normalized()
            let id = post.place.identity
            if let previous = places[id], previous != post.place { throw LivePublicDiscoveryValidationError.inconsistentPlace }
            if places[id] == nil { order.append(id); places[id] = post.place }
            groups[id, default: []].append(post)
        }
        return order.map { Self(id: $0, place: places[$0]!, posts: groups[$0]!) }
    }
}

struct LivePublicDiscoveryValidatedPage: Sendable {
    let indexRevision: String
    let generatedAt: Date
    let expiresAt: Date
    let coverage: [LivePublicDiscoveryCoverage]
    let posts: [LivePublicDiscoveryPost]
    let nextCursor: String?
    let venues: [LivePublicDiscoveryVenue]
    private let consumedCursors: Set<String>

    fileprivate init(indexRevision: String, generatedAt: Date, expiresAt: Date,
                     coverage: [LivePublicDiscoveryCoverage], posts: [LivePublicDiscoveryPost], nextCursor: String?,
                     consumedCursors: Set<String> = []) throws {
        self.indexRevision = indexRevision; self.generatedAt = generatedAt; self.expiresAt = expiresAt
        self.coverage = coverage; self.posts = posts; self.nextCursor = nextCursor
        self.consumedCursors = consumedCursors
        venues = try LivePublicDiscoveryVenue.grouping(posts)
    }

    /// Opaque cursor binding is enforced by the server; local query/session revisions remain the caller's fence.
    func validateContinuation(from previous: Self, requestedCursor: String, at now: Date) throws {
        _ = try appending(to: previous, requestedCursor: requestedCursor, at: now)
    }

    func appending(to previous: Self, requestedCursor: String, at now: Date) throws -> Self {
        guard previous.nextCursor == requestedCursor, !requestedCursor.isEmpty,
              !previous.consumedCursors.contains(requestedCursor), nextCursor != requestedCursor,
              nextCursor == nil || !previous.consumedCursors.contains(nextCursor!),
              indexRevision == previous.indexRevision, generatedAt == previous.generatedAt,
              Set(coverage.map { "\($0.platform):\($0.status):\($0.indexedPostCount)" })
                == Set(previous.coverage.map { "\($0.platform):\($0.status):\($0.indexedPostCount)" }),
              expiresAt > now, previous.expiresAt > now else {
            throw LivePublicDiscoveryValidationError.invalidContinuation
        }
        var combined = previous.posts
        var byID = Dictionary(uniqueKeysWithValues: previous.posts.map { ($0.id, $0) })
        for post in posts {
            if let existing = byID[post.id] {
                guard existing == post else { throw LivePublicDiscoveryValidationError.invalidContinuation }
            } else {
                byID[post.id] = post
                combined.append(post)
            }
        }
        guard coverage.allSatisfy({ row in combined.filter { $0.platform == row.platform }.count <= row.indexedPostCount }) else {
            throw LivePublicDiscoveryValidationError.invalidContinuation
        }
        let dates = Dictionary(uniqueKeysWithValues: combined.map { ($0.id, LivePublicDiscoveryPolicy.date($0.verifiedAt)!) })
        combined.sort { dates[$0.id]! == dates[$1.id]! ? $0.id < $1.id : dates[$0.id]! > dates[$1.id]! }
        return try Self(indexRevision: indexRevision, generatedAt: generatedAt,
            expiresAt: min(expiresAt, previous.expiresAt), coverage: coverage,
            posts: combined, nextCursor: nextCursor, consumedCursors: previous.consumedCursors.union([requestedCursor]))
    }
}

private enum LivePublicDiscoveryPolicy {
    static let platforms: Set<String> = ["instagram", "threads", "xiaohongshu"]

    static func text(_ value: String, limit: Int, allowEmpty: Bool = false) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (allowEmpty || !clean.isEmpty) && clean.unicodeScalars.count <= limit
            && value.range(of: "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]", options: .regularExpression) == nil
    }

    static func optionalText(_ value: String?) -> String? {
        guard let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else { return nil }
        return clean
    }

    static func date(_ value: String) -> Date? {
        guard value.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?Z$", options: .regularExpression) != nil else { return nil }
        let pieces = value.dropLast().split(separator: ".")
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        let canonical = String(pieces[0]) + "." + fraction + String(repeating: "0", count: 3 - fraction.count) + "Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: canonical), formatter.string(from: date) == canonical else { return nil }
        return date
    }

    static func webURL(_ raw: String) -> URLComponents? {
        guard raw.count <= 4_096, raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let value = URLComponents(string: raw), value.scheme?.lowercased() == "https",
              value.user == nil, value.password == nil, value.port == nil || value.port == 443,
              let host = value.host, !host.isEmpty, !host.hasSuffix("."), value.url != nil else { return nil }
        return value
    }

    static func hasToken(_ value: URLComponents) -> Bool {
        let fragmentItems = value.fragment.map { URLComponents(string: "https://fragment.invalid/?" + $0)?.queryItems ?? [] } ?? []
        return ((value.queryItems ?? []) + fragmentItems).contains {
            $0.name.range(of: "token|auth|credential|password|passwd|cookie|session|secret|api[_-]?key|^key$",
                          options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func source(_ raw: String, platform: String) -> (url: URL, postID: String)? {
        guard raw.count <= 2_048, platforms.contains(platform), var value = webURL(raw), !hasToken(value),
              let host = value.host?.lowercased(), !value.percentEncodedPath.contains("%"), !value.path.contains("//") else { return nil }
        let parts = value.path.split(separator: "/").map(String.init)
        let postID: String
        switch platform {
        case "instagram":
            guard ["instagram.com", "www.instagram.com"].contains(host), parts.count == 2,
                  ["p", "reel", "reels", "tv"].contains(parts[0]) else { return nil }
            postID = parts[1]; value.host = "www.instagram.com"
            value.path = "/\(parts[0] == "reels" ? "reel" : parts[0])/\(postID)/"
        case "threads":
            guard ["threads.net", "www.threads.net", "threads.com", "www.threads.com"].contains(host),
                  parts.count == 3, parts[0].range(of: "^@[A-Za-z0-9_.]{1,100}$", options: .regularExpression) != nil,
                  parts[1] == "post" else { return nil }
            postID = parts[2]; value.host = "www.threads.com"
            value.path = "/" + parts.joined(separator: "/")
        default:
            guard ["xiaohongshu.com", "www.xiaohongshu.com"].contains(host),
                  (parts.count == 2 && parts[0] == "explore")
                    || (parts.count == 3 && parts[0] == "discovery" && parts[1] == "item") else { return nil }
            guard parts.last!.range(of: "^[A-Fa-f0-9]{24}$", options: .regularExpression) != nil else { return nil }
            postID = parts.last!.lowercased(); value.host = "www.xiaohongshu.com"
            value.path = "/explore/\(postID)"
        }
        guard postID.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil else { return nil }
        value.scheme = "https"; value.port = nil; value.query = nil; value.fragment = nil
        guard let url = value.url else { return nil }
        return (url, postID)
    }
}
#endif
