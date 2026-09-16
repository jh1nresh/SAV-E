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
            // Offline demo stays empty unless the dedicated screenshot fixture
            // is requested. It never reads or publishes real social records.
            if ReviewDemo.isOfflineUITestMode && ProcessInfo.processInfo.arguments.contains("--uitest-social-posts") {
                let items = Self.fixturePosts
                posts = items.filter { (route == .mine || $0.visible_to_followers) && (filter == .all || $0.status.rawValue == filter.rawValue) }
                counts = SocialProfileCounts(postCount: items.count, followingCount: 2, followerCount: 3)
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
            ("11111111-1111-4111-8111-111111111111", "週末的咖啡口袋", "台北 · 大安", "cafe", PlaceStatus.wantToGo),
            ("22222222-2222-4222-8222-222222222222", "一起看海", "新北 · 淡水", "attraction", .visited),
            ("33333333-3333-4333-8333-333333333333", "午後散步", "台北 · 中山", "shopping", .wantToGo)
        ].map { id, name, address, category, status in
            SharedPlacePost(id: UUID(uuidString: id)!, name: name, address: address, category: category, status: status,
                stars: nil, caption: status == .visited ? "留一點時間，慢慢走。" : nil,
                shared_at: "2026-09-16T00:00:00Z", author_id: "sample", author_name: "Alex · 範例",
                author_handle: "sample", author_avatar_url: nil, visible_to_followers: status != .visited)
        }
    }
}
