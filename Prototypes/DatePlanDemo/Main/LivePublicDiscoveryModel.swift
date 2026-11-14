#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Foundation

@MainActor
protocol LivePublicDiscoveryBackend {
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage
}

extension SupabaseService: LivePublicDiscoveryBackend {}

@MainActor
final class LivePublicDiscoveryModel: ObservableObject {
    @Published private(set) var page: LivePublicDiscoveryValidatedPage?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var unavailable = false
    @Published private(set) var paginationFailed = false
    private let backend: any LivePublicDiscoveryBackend
    private let sessionIsCurrent: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private var viewport: LivePublicDiscoveryViewport?
    private var revision: UInt64 = 0
    private var expiryTask: Task<Void, Never>?
    private var authObservation: AnyCancellable?

    convenience init(ownerSubject: String, sessionGeneration: Int) {
        self.init(backend: SupabaseService.shared, sessionIsCurrent: {
            let auth = PrivyAuthService.shared
            guard case .authenticated(let owner) = auth.authState else { return false }
            return owner == ownerSubject && auth.currentUserId == ownerSubject
                && auth.sessionGeneration == sessionGeneration
        })
        let auth = PrivyAuthService.shared
        authObservation = Publishers.CombineLatest(auth.$authState, auth.$sessionGeneration)
            .sink { [weak self] state, generation in
                guard case .authenticated(let owner) = state,
                      owner == ownerSubject, generation == sessionGeneration else {
                    self?.clear(); return
                }
            }
    }

    init(backend: any LivePublicDiscoveryBackend, sessionIsCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.backend = backend; self.sessionIsCurrent = sessionIsCurrent; self.now = now
    }

    func clear() {
        revision &+= 1
        expiryTask?.cancel(); expiryTask = nil
        page = nil; viewport = nil; isLoading = false; isLoadingMore = false
        unavailable = false; paginationFailed = false
    }

    func refresh(_ viewport: LivePublicDiscoveryViewport) async {
        clear()
        guard sessionIsCurrent(), !Task.isCancelled else { return }
        self.viewport = viewport
        let ticket = revision
        isLoading = true
        defer { if revision == ticket { isLoading = false } }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let value = try await backend.fetchPublicDiscovery(viewport: viewport, cursor: nil)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let verified = try value.validated(at: now())
            guard verified.posts.allSatisfy({ viewport.contains(latitude: $0.place.latitude, longitude: $0.place.longitude) }) else {
                throw DiscoveryFailure.invalidViewport
            }
            publish(verified, ticket: ticket)
        } catch {
            guard ticket == revision else { return }
            guard sessionIsCurrent(), !Task.isCancelled else { clear(); return }
            page = nil; unavailable = true
        }
    }

    func loadMore() async {
        guard sessionIsCurrent(), !Task.isCancelled, !isLoading, !isLoadingMore,
              let previous = page, previous.expiresAt > now(),
              let cursor = previous.nextCursor, let viewport else { return }
        let ticket = revision
        isLoadingMore = true; paginationFailed = false
        defer { if ticket == revision { isLoadingMore = false } }
        do {
            let raw = try await backend.fetchPublicDiscovery(viewport: viewport, cursor: cursor)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let next = try raw.validated(at: now())
            let combined = try next.appending(to: previous, requestedCursor: cursor, at: now())
            guard combined.posts.allSatisfy({ viewport.contains(latitude: $0.place.latitude, longitude: $0.place.longitude) }) else {
                throw DiscoveryFailure.invalidViewport
            }
            publish(combined, ticket: ticket)
        } catch {
            guard ticket == revision else { return }
            guard sessionIsCurrent(), !Task.isCancelled else { clear(); return }
            // A replacement index may have withdrawn a post, so do not retain old pins.
            page = nil; unavailable = true; paginationFailed = true
            expiryTask?.cancel(); expiryTask = nil
        }
    }

    private func publish(_ value: LivePublicDiscoveryValidatedPage, ticket: UInt64) {
        page = value; unavailable = false
        expiryTask?.cancel()
        let delay = max(0, min(300, value.expiresAt.timeIntervalSince(now())))
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.revision == ticket else { return }
            self.clear(); self.unavailable = true
        }
    }

    private enum DiscoveryFailure: Error { case invalidViewport }
}
#endif
