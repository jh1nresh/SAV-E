#if SAVVY_MAIN_APP && ((DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW) || SAVVY_PUBLIC_DISCOVERY_BACKEND)
import Combine
import Foundation

@MainActor
protocol LivePublicDiscoveryBackend {
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?,
                              venue: LivePublicDiscoveryVenueKey?) async throws -> LivePublicDiscoveryPage
}

extension LivePublicDiscoveryBackend {
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?,
                              venue: LivePublicDiscoveryVenueKey?) async throws -> LivePublicDiscoveryPage {
        guard venue == nil else { throw URLError(.unsupportedURL) }
        return try await fetchPublicDiscovery(viewport: viewport, cursor: cursor)
    }
}

extension SupabaseService: LivePublicDiscoveryBackend {}

#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW && SAVVY_TAIPEI_SOURCE_SNAPSHOT
@MainActor
private final class BundledTaipeiPublicDiscoveryBackend: LivePublicDiscoveryBackend {
    static let shared = BundledTaipeiPublicDiscoveryBackend()
    private let snapshot: LivePublicDiscoveryLocalSnapshot?

    private init(bundle: Bundle = .main) {
        snapshot = bundle.url(forResource: "TaipeiPublicSourceSnapshot", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            .flatMap { try? LivePublicDiscoveryLocalSnapshot(data: $0) }
    }

    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage {
        try await fetchPublicDiscovery(viewport: viewport, cursor: cursor, venue: nil)
    }

    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?,
                              venue: LivePublicDiscoveryVenueKey?) async throws -> LivePublicDiscoveryPage {
        guard let snapshot else { throw LivePublicDiscoveryValidationError.invalidPage }
        return try snapshot.page(viewport: viewport, cursor: cursor, venue: venue, at: Date())
    }
}
#endif

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
    private var venue: LivePublicDiscoveryVenueKey?
    private var automaticContinuations = 0
    private var revision: UInt64 = 0
    private var expiryTask: Task<Void, Never>?
    private var authObservation: AnyCancellable?

    convenience init(ownerSubject: String, sessionGeneration: Int) {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW && SAVVY_TAIPEI_SOURCE_SNAPSHOT
        let backend: any LivePublicDiscoveryBackend = BundledTaipeiPublicDiscoveryBackend.shared
#else
        let backend: any LivePublicDiscoveryBackend = SupabaseService.shared
#endif
        self.init(backend: backend, sessionIsCurrent: {
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
        page = nil; viewport = nil; venue = nil; isLoading = false; isLoadingMore = false
        automaticContinuations = 0
        unavailable = false; paginationFailed = false
    }

    func refreshMap(_ viewport: LivePublicDiscoveryViewport) async {
        let longitudeSpan = viewport.east >= viewport.west
            ? viewport.east - viewport.west : 360 - viewport.west + viewport.east
        // Keep wide-area browsing to one initial request and keep manual continuation available.
        let isNeighborhood = longitudeSpan > 0 && longitudeSpan <= 0.01 && viewport.north - viewport.south <= 0.01
        await refresh(viewport, venue: nil, automaticContinuations: isNeighborhood ? 2 : 0)
    }

    func refresh(_ viewport: LivePublicDiscoveryViewport, venue: LivePublicDiscoveryVenueKey? = nil) async {
        await refresh(viewport, venue: venue, automaticContinuations: 0)
    }

    private func refresh(_ viewport: LivePublicDiscoveryViewport, venue: LivePublicDiscoveryVenueKey?,
                         automaticContinuations: Int) async {
        clear()
        guard sessionIsCurrent(), !Task.isCancelled else { return }
        self.viewport = viewport
        self.venue = venue
        self.automaticContinuations = automaticContinuations
        let ticket = revision
        isLoading = true
        defer { if revision == ticket { isLoading = false } }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let value = try await backend.fetchPublicDiscovery(viewport: viewport, cursor: nil, venue: venue)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let verified = try value.validated(at: now(), viewport: viewport, venue: venue)
            publish(verified, ticket: ticket)
        } catch {
            guard ticket == revision else { return }
            guard sessionIsCurrent(), !Task.isCancelled else { clear(); return }
            page = nil; unavailable = true
            return
        }
        // Publish the first page immediately, then use the same continuation checks as manual loading.
        isLoading = false
        for _ in 0..<automaticContinuations {
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled,
                  !isLoadingMore, !paginationFailed, page?.nextCursor != nil else { return }
            await loadMore(automatic: true)
        }
    }

    func loadMore() async {
        await loadMore(automatic: false)
    }

    private func loadMore(automatic: Bool) async {
        guard sessionIsCurrent(), !Task.isCancelled, !isLoading, !isLoadingMore,
              let previous = page, previous.expiresAt > now(),
              let cursor = previous.nextCursor, let viewport else { return }
        let ticket = revision
        isLoadingMore = true; paginationFailed = false
        defer { if ticket == revision { isLoadingMore = false } }
        do {
            let raw = try await backend.fetchPublicDiscovery(viewport: viewport, cursor: cursor, venue: venue)
            guard ticket == revision, sessionIsCurrent(), !Task.isCancelled else { return }
            let next = try raw.validated(at: now(), viewport: viewport, venue: venue)
            let combined = try next.appending(to: previous, requestedCursor: cursor, at: now())
            publish(combined, ticket: ticket)
        } catch {
            guard ticket == revision else { return }
            guard sessionIsCurrent(), !Task.isCancelled else { clear(); return }
            if automatic, previous.expiresAt > now(),
               let serviceError = error as? SupabaseError, case .networkError(let underlying) = serviceError,
               let transport = underlying as? URLError,
               [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(transport.code) {
                // The still-valid first page can remain visible and be continued manually.
                paginationFailed = true
                return
            }
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
            if let viewport = self.viewport, self.sessionIsCurrent() {
                // Revalidate the current view without keeping expired pins or post links.
                self.expiryTask = nil
                await self.refresh(viewport, venue: self.venue, automaticContinuations: self.automaticContinuations)
            } else {
                self.clear(); self.unavailable = true
            }
        }
    }

}
#endif
