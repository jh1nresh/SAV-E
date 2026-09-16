import Foundation

/// A live, revocable projection. Never persist an author's content in Place.
struct SharedPlacePost: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let category: String
    let status: PlaceStatus
    let stars: Double?
    let caption: String?
    let shared_at: String
    let author_id: String
    let author_name: String
    let author_handle: String?
    let author_avatar_url: String?
    let visible_to_followers: Bool

    var icon: String { PlaceCategory(rawValue: category)?.iconName ?? "mappin.and.ellipse" }
}

struct SharedPlacePostsPage: Decodable {
    let items: [SharedPlacePost]
    let nextCursor: String?
}

struct SocialProfileCounts: Decodable {
    let postCount: Int
    let followingCount: Int
    let followerCount: Int
}

struct SharedPassportPage: Decodable {
    struct Profile: Decodable {
        let id: String
        let displayName: String
        let handle: String?
        let avatarUrl: String?
        let postCount: Int
    }
    let profile: Profile
    let items: [SharedPlacePost]
    let nextCursor: String?
}

enum SharedPostFilter: String, CaseIterable, Identifiable {
    case all, wantToGo, visited
    var id: Self { self }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: language.localized(english: "All", traditionalChinese: "全部")
        case .wantToGo: language.localized(english: "Want to go", traditionalChinese: "想去")
        case .visited: language.localized(english: "Visited", traditionalChinese: "去過")
        }
    }
}

struct SharedPostDraft: Encodable {
    var status: PlaceStatus
    var stars: Double?
    var caption: String
    private enum CodingKeys: String, CodingKey { case status, stars, caption }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        if let stars { try container.encode(stars, forKey: .stars) }
        else { try container.encodeNil(forKey: .stars) }
        try container.encode(caption, forKey: .caption)
    }
    var isValid: Bool {
        caption.unicodeScalars.count <= 500 &&
        (stars == nil || (status == .visited && stars!.isFinite && (1...5).contains(stars!)))
    }
}
