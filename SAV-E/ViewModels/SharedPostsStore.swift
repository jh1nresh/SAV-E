import Foundation
import Combine

@MainActor
final class SharedPostsStore: ObservableObject {
    enum Route: Equatable { case feed, mine, author(String) }
    @Published private(set) var posts: [SharedPlacePost] = []
    @Published private(set) var counts: SocialProfileCounts?
    @Published private(set) var profile: SharedPassportPage.Profile?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var nextCursor: String?
    @Published var filter: SharedPostFilter = .all
    private var requestID = UUID()
    private var route: Route = .feed
    private let service = SupabaseService.shared

    var isDemo: Bool { PrivyAuthService.shared.isReviewerDemo }

    func refresh(_ route: Route) async {
        self.route = route
        requestID = UUID()
        posts = []; counts = nil; profile = nil; nextCursor = nil
        await load(append: false)
    }

    func loadMore() async {
        guard !isLoading, nextCursor != nil else { return }
        await load(append: true)
    }

    private func load(append: Bool) async {
        let ticket = requestID
        let account = PrivyAuthService.shared.currentUserId
        isLoading = true; error = nil
        defer { if ticket == requestID { isLoading = false } }
        if isDemo {
            // Offline demo stays empty unless a dedicated screenshot fixture
            // is requested. It never reads or publishes real social records.
            // Friends-town is the Doodle mock people list (Mia / Leo / Kai / Ana).
            // Social-posts keeps the Harbor Town UUID lock for passport tests.
            if ProcessInfo.processInfo.arguments.contains("--uitest-friends-town") {
                applyDemoFixture(items: Self.friendsTownPosts)
            } else if ProcessInfo.processInfo.arguments.contains("--uitest-social-posts") {
                applyDemoFixture(items: Self.fixturePosts)
            } else {
                posts = []
                counts = SocialProfileCounts(postCount: 0, followingCount: 0, followerCount: 0)
            }
            return
        }
        guard account != nil else { return }
        do {
            let page: SharedPlacePostsPage
            switch route {
            case .feed, .mine:
                page = try await service.fetchSharedPosts(mine: route == .mine, filter: filter, cursor: append ? nextCursor : nil)
            case .author(let id):
                let result = try await service.fetchSharedPassport(authorID: id, filter: filter, cursor: append ? nextCursor : nil)
                guard ticket == requestID, account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { return }
                profile = result.profile
                page = SharedPlacePostsPage(items: result.items, nextCursor: result.nextCursor)
            }
            guard ticket == requestID, account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { return }
            let existing = append ? posts : []
            let ids = Set(existing.map(\.id))
            posts = existing + page.items.filter { !ids.contains($0.id) }
            nextCursor = page.nextCursor
            if route == .mine {
                let result = try await service.fetchSocialProfileCounts()
                guard ticket == requestID, account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { return }
                counts = result
            }
        } catch {
            guard ticket == requestID, account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { return }
            // Don't retain stale social projections after a failed revalidation.
            if !append { posts = []; profile = nil }
            self.error = error.localizedDescription
        }
    }

    private func applyDemoFixture(items: [SharedPlacePost]) {
        let currentFilter = filter
        switch route {
        case .mine, .feed:
            posts = items.filter {
                (route == .mine || $0.visible_to_followers)
                    && (currentFilter == .all || $0.status.rawValue == currentFilter.rawValue)
            }
            counts = SocialProfileCounts(postCount: items.count, followingCount: 2, followerCount: 3)
        case .author(let id):
            let authored = items.filter {
                $0.author_id == id
                    && $0.visible_to_followers
                    && (currentFilter == .all || $0.status.rawValue == currentFilter.rawValue)
            }
            posts = authored
            if let first = items.first(where: { $0.author_id == id }) {
                profile = SharedPassportPage.Profile(
                    id: id,
                    displayName: first.author_name,
                    handle: first.author_handle,
                    avatarUrl: first.author_avatar_url,
                    postCount: authored.count
                )
            }
            counts = SocialProfileCounts(postCount: authored.count, followingCount: 0, followerCount: 0)
        }
    }

    func detail(_ post: SharedPlacePost) async throws -> SharedPlacePost {
        if isDemo { return post }
        let account = PrivyAuthService.shared.currentUserId
        let result = try await service.fetchSharedPost(id: post.id)
        guard account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { throw CancellationError() }
        return result
    }

    func publish(id: UUID, draft: SharedPostDraft) async throws {
        guard !isDemo else { throw SupabaseError.notAuthenticated }
        let account = PrivyAuthService.shared.currentUserId
        _ = try await service.putSharedPost(id: id, draft: draft)
        guard account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { throw CancellationError() }
        await refresh(route)
    }

    func withdraw(id: UUID) async throws {
        guard !isDemo else { throw SupabaseError.notAuthenticated }
        let account = PrivyAuthService.shared.currentUserId
        try await service.withdrawSharedPost(id: id)
        guard account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { throw CancellationError() }
        await refresh(route)
    }

    func save(id: UUID) async throws {
        guard !isDemo else { throw SupabaseError.notAuthenticated }
        let account = PrivyAuthService.shared.currentUserId
        _ = try await service.saveSharedPost(id: id)
        guard account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { throw CancellationError() }
    }

    private static var fixturePosts: [SharedPlacePost] {
        [
            ("11111111-1111-4111-8111-111111111111", "Harbor Town", "Water", "attraction", PlaceStatus.wantToGo, "alex", "Alex Last", true),
            ("22222222-2222-4222-8222-222222222222", "Pine View", "Forest", "attraction", .visited, "sample", "Alex · 範例", false),
            ("33333333-3333-4333-8333-333333333333", "Old Maple Cafe", "Town", "cafe", .wantToGo, "taylor", "Taylor Last", true),
            ("55555555-5555-4555-8555-555555555555", "Pine View", "Forest", "attraction", .wantToGo, "jordan", "Jordan Last", true),
        ].map { id, name, address, category, status, authorID, authorName, visible in
            post(
                id: id,
                name: name,
                address: address,
                category: category,
                status: status,
                authorID: authorID,
                authorName: authorName,
                visible: visible,
                sharedAt: "2026-10-12T10:00:00Z"
            )
        }
    }

    /// Doodle Friends mock people (Mia / Leo / Kai / Ana) with ages 2d / 5d / 1w / 2w.
    private static var friendsTownPosts: [SharedPlacePost] {
        [
            ("a1111111-1111-4111-8111-111111111111", "Grey Cafe", "Beijing", "cafe", PlaceStatus.wantToGo, "mia", "Mia", true, 2),
            ("a2222222-2222-4222-8222-222222222222", "Fangzhuanchang Noodles", "Beijing", "food", .visited, "leo", "Leo", true, 5),
            ("a3333333-3333-4333-8333-333333333333", "Temple of Heaven Park", "Beijing", "attraction", .visited, "kai", "Kai", true, 7),
            ("a4444444-4444-4444-8444-444444444444", "Jingshan Hill", "Beijing", "attraction", .wantToGo, "ana", "Ana", true, 14),
        ].map { id, name, address, category, status, authorID, authorName, visible, daysAgo in
            post(
                id: id,
                name: name,
                address: address,
                category: category,
                status: status,
                authorID: authorID,
                authorName: authorName,
                visible: visible,
                sharedAt: isoSharedAt(daysAgo: daysAgo)
            )
        }
    }

    private static func post(
        id: String,
        name: String,
        address: String,
        category: String,
        status: PlaceStatus,
        authorID: String,
        authorName: String,
        visible: Bool,
        sharedAt: String
    ) -> SharedPlacePost {
        SharedPlacePost(
            id: UUID(uuidString: id)!,
            name: name,
            address: address,
            category: category,
            status: status,
            stars: nil,
            caption: nil,
            shared_at: sharedAt,
            author_id: authorID,
            author_name: authorName,
            author_handle: authorID,
            author_avatar_url: nil,
            visible_to_followers: visible
        )
    }

    private static func isoSharedAt(daysAgo: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(
            from: Date().addingTimeInterval(-TimeInterval(daysAgo) * 86_400 - 3_600)
        )
    }
}
