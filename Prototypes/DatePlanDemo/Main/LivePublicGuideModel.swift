#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Foundation

enum LivePublicGuideState: Equatable {
    case idle, loading, ready, adding, reconciling, completed, unconfirmed, unavailable, inactive
}

/// Explicit venue-to-list handoff only. No personal save, visit or Guide navigation occurs here.
@MainActor
final class LivePublicGuideModel: ObservableObject {
    @Published private(set) var lists: [LiveOutingChoice] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var completedListID: UUID?
    @Published private(set) var attemptedWrite = false
    @Published private(set) var hasExistingVenue = false
    @Published private(set) var writeAcknowledged = false
    @Published private(set) var state: LivePublicGuideState = .idle

    private let outing: LiveOutingModel
    private let backend: LivePublicGuideBackend
    private let authority: LivePublicGuideAuthority
    private let candidate: Place?
    private let payload: SaveListItem?
    private let ownerSubject: String
    private let sessionGeneration: Int
    private var targetListID: UUID?
    private var revision: UInt64 = 0
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var expiryTask: Task<Void, Never>?
    private var authObservation: AnyCancellable?

    convenience init(venue: LivePublicDiscoveryVenue, expiresAt: Date,
                     ownerSubject: String, sessionGeneration: Int) {
        self.init(venue: venue, expiresAt: expiresAt, ownerSubject: ownerSubject,
                  sessionGeneration: sessionGeneration, backend: SupabaseService.shared,
                  sessionIsCurrent: {
            let auth = PrivyAuthService.shared
            guard case .authenticated(let owner) = auth.authState else { return false }
            return owner == ownerSubject && auth.currentUserId == ownerSubject && auth.sessionGeneration == sessionGeneration
        })
        let auth = PrivyAuthService.shared
        authObservation = Publishers.CombineLatest(auth.$authState, auth.$sessionGeneration)
            .sink { [weak self] state, generation in
                guard case .authenticated(let owner) = state, owner == ownerSubject,
                      generation == sessionGeneration else { self?.deactivate(); return }
            }
    }

    init(venue: LivePublicDiscoveryVenue, expiresAt: Date, ownerSubject: String, sessionGeneration: Int,
         backend: any LiveOutingBackend, sessionIsCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = Date.init) {
        let authority = LivePublicGuideAuthority(expiresAt: expiresAt, sessionIsCurrent: sessionIsCurrent, now: now)
        let scoped = LivePublicGuideBackend(service: backend, authority: authority)
        self.authority = authority; self.backend = scoped
        self.ownerSubject = ownerSubject; self.sessionGeneration = sessionGeneration
        self.outing = LiveOutingModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
                                      backend: scoped, sessionIsCurrent: { authority.isCurrent })
        // Drop the public posts, captions, authors, source URLs and cover metadata at this boundary.
        let projection = LiveMapPlace.discovery(venue)
        self.candidate = projection?.place
        self.payload = projection?.listPayload
        startExpiryTimer()
    }

    deinit { expiryTask?.cancel(); operation?.cancel() }

    func prepare() async {
        if targetListID != nil, attemptedWrite || completedListID != nil { await reconcile(); return }
        await run(.loading) { ticket in
            let before = self.outing.snapshotRevision
            await self.outing.refresh()
            try self.checkSnapshot(ticket, after: before, selected: nil)
            self.lists = self.outing.lists
            self.state = .ready
        }
    }

    /// This is the only mutation entry. A lost acknowledgement never authorizes another POST.
    func add(to listID: UUID) async {
        guard !attemptedWrite, completedListID == nil else { return }
        await run(.adding) { ticket in
            guard self.lists.first(where: { $0.id == listID })?.role.canEdit == true else {
                throw LivePublicGuideFailure.chooseEditableList
            }
            let before = self.outing.snapshotRevision
            await self.outing.selectList(listID)
            try self.checkSnapshot(ticket, after: before, selected: listID)
            self.lists = self.outing.lists
            guard self.outing.canEditSelected else { throw LivePublicGuideFailure.chooseEditableList }
            self.targetListID = listID
            if self.containsVenue(in: listID) {
                self.hasExistingVenue = true
                self.completedListID = listID
                self.state = .completed
                return
            }
            guard var payload = self.payload else { throw LivePublicGuideFailure.invalidVenue }
            payload.id = UUID()
            payload.addedAt = self.authority.now()
            try self.check(ticket)
            self.attemptedWrite = true
            try await SAVEPendingImportSessionScope.$current.withValue(
                (generation: self.sessionGeneration, owner: self.ownerSubject)
            ) {
                try await self.backend.addCollaborativeListItem(listID: listID, payload: payload)
            }
            try self.check(ticket)
            self.writeAcknowledged = true
            await self.readConfirmation(listID, ticket: ticket)
        }
    }

    /// Read-only recovery, including after a POST whose response was lost.
    func reconcile() async {
        guard let listID = targetListID else { return }
        await run(.reconciling) { ticket in
            await self.readConfirmation(listID, ticket: ticket)
        }
    }

    func deactivate() {
        revision &+= 1
        authority.active = false
        operation?.cancel()
        expiryTask?.cancel()
        outing.deactivate()
        lists = []; completedListID = nil; error = nil
        isLoading = false; isWorking = false; state = .inactive
        // Keep the operation handle/attempt budget until the underlying request actually returns.
    }

    private func containsVenue(in listID: UUID) -> Bool {
        guard outing.selectedListID == listID else { return false }
        guard let candidate else { return false }
        return outing.items.contains {
            $0.asPlace(id: $0.id, createdAt: $0.addedAt, includeSenderMemory: false).matches(candidate)
        }
    }

    private func readConfirmation(_ listID: UUID, ticket: UInt64) async {
        let before = outing.snapshotRevision
        await outing.selectList(listID)
        do {
            try checkSnapshot(ticket, after: before, selected: listID)
            lists = outing.lists
            guard containsVenue(in: listID) else { throw LivePublicGuideFailure.unconfirmed }
            completedListID = listID
            error = nil; state = .completed
        } catch { handle(error, ticket: ticket) }
    }

    private func check(_ ticket: UInt64) throws {
        try Task.checkCancellation()
        guard revision == ticket else { throw CancellationError() }
        try authority.check()
        guard candidate != nil, payload != nil else { throw LivePublicGuideFailure.invalidVenue }
    }

    private func checkSnapshot(_ ticket: UInt64, after before: UInt64, selected: UUID?) throws {
        try check(ticket)
        guard outing.snapshotRevision > before, outing.selectedListID == selected else {
            throw LivePublicGuideFailure.listUnavailable
        }
    }

    private func run(_ phase: LivePublicGuideState, action: @escaping @MainActor (UInt64) async throws -> Void) async {
        guard operation == nil else { return }
        do { try authority.check(); try Task.checkCancellation() }
        catch { handle(error, ticket: revision); return }
        revision &+= 1
        let ticket = revision, id = UUID()
        operationID = id
        completedListID = nil; error = nil
        state = phase; isLoading = phase == .loading; isWorking = phase != .loading
        let task = Task { @MainActor in
            defer {
                if self.operationID == id {
                    self.operation = nil; self.operationID = nil
                    self.isLoading = false; self.isWorking = false
                }
            }
            do { try self.check(ticket); try await action(ticket) }
            catch { self.handle(error, ticket: ticket) }
        }
        operation = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    private func handle(_ failure: Error, ticket: UInt64) {
        guard ticket == revision else { return }
        if !authority.active || !authority.sessionIsCurrent() || Task.isCancelled || failure is CancellationError {
            deactivate(); return
        }
        lists = []; completedListID = nil
        if authority.now() >= authority.expiresAt {
            deactivate(); state = .unavailable; error = LivePublicGuideFailure.expired.localizedDescription
        } else if attemptedWrite {
            state = .unconfirmed
            error = writeAcknowledged
                ? "Submitted. The list could not be verified; recheck without submitting again."
                : "The submission result is not confirmed. Recheck the list; do not submit again."
        } else {
            state = .unavailable; error = failure.localizedDescription
        }
    }

    private func startExpiryTimer() {
        let seconds = authority.expiresAt.timeIntervalSince(authority.now())
        guard seconds.isFinite, seconds > 0 else { return }
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(seconds, 86_400) * 1_000_000_000)) }
            catch { return }
            guard let self else { return }
            self.deactivate()
            self.state = .unavailable; self.error = LivePublicGuideFailure.expired.localizedDescription
        }
    }
}

private enum LivePublicGuideFailure: LocalizedError {
    case expired, invalidVenue, chooseEditableList, listUnavailable, unconfirmed, unsupported
    var errorDescription: String? {
        switch self {
        case .expired: return "This public source has expired. Refresh Explore before continuing."
        case .invalidVenue: return "This venue cannot be added to a map list."
        case .chooseEditableList: return "Choose a list you can edit. Its current permission will be checked again."
        case .listUnavailable: return "The list or its current membership could not be verified."
        case .unconfirmed: return "The venue is not confirmed in the list. Recheck without submitting again."
        case .unsupported: return "This action is unavailable in the public venue chooser."
        }
    }
}

@MainActor
private final class LivePublicGuideAuthority {
    let expiresAt: Date
    let sessionIsCurrent: @MainActor () -> Bool
    let now: @MainActor () -> Date
    var active = true
    var isCurrent: Bool { active && sessionIsCurrent() && now() < expiresAt }
    init(expiresAt: Date, sessionIsCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date) {
        self.expiresAt = expiresAt; self.sessionIsCurrent = sessionIsCurrent; self.now = now
    }
    func check() throws {
        try Task.checkCancellation()
        guard active, sessionIsCurrent() else { throw CancellationError() }
        guard expiresAt.timeIntervalSince1970.isFinite, now() < expiresAt else { throw LivePublicGuideFailure.expired }
    }
}

/// Reuses the existing list/roster ACL mapper while excluding the unrelated optional friends feed.
@MainActor
private final class LivePublicGuideBackend: LiveOutingBackend {
    let service: any LiveOutingBackend
    let authority: LivePublicGuideAuthority
    var isConfigured: Bool { service.isConfigured }
    init(service: any LiveOutingBackend, authority: LivePublicGuideAuthority) { self.service = service; self.authority = authority }
    func fetchCollaborativeListRows() async throws -> [SaveCollaborativeListServerRow] {
        try authority.check(); let rows = try await service.fetchCollaborativeListRows(); try authority.check(); return rows
    }
    func fetchListMembers(listID: UUID) async throws -> [SaveListMemberRow] {
        try authority.check(); let rows = try await service.fetchListMembers(listID: listID); try authority.check(); return rows
    }
    func fetchSharedPosts(mine: Bool, filter: SharedPostFilter, cursor: String?) async throws -> SharedPlacePostsPage {
        try authority.check(); return SharedPlacePostsPage(items: [], nextCursor: nil)
    }
    func addCollaborativeListItem(listID: UUID, payload: SaveListItem) async throws {
        try authority.check()
        guard service.isConfigured else { throw SupabaseError.notConfigured }
        try await service.addCollaborativeListItem(listID: listID, payload: payload)
        try authority.check()
    }
    func createCollaborativeListRow(id: UUID, title: String, note: String?) async throws { throw LivePublicGuideFailure.unsupported }
    func joinCollaborativeList(code: String) async throws -> SaveCollaborativeListServerRow { throw LivePublicGuideFailure.unsupported }
    func createListShareCode(listID: UUID, role: SaveListRole) async throws -> (code: String, url: URL) { throw LivePublicGuideFailure.unsupported }
}
#endif
