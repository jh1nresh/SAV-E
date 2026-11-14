#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Foundation

struct LiveOutingChoice: Identifiable {
    let id: UUID
    let title: String
    let role: SaveListRole
    let itemCount: Int
}

struct LiveOutingMember: Identifiable {
    let id: String
    let displayName: String
    let role: SaveListRole
}

/// Narrow server boundary, injectable without touching a real account in tests.
@MainActor
protocol LiveOutingBackend {
    var isConfigured: Bool { get }
    func fetchCollaborativeListRows() async throws -> [SaveCollaborativeListServerRow]
    func fetchListMembers(listID: UUID) async throws -> [SaveListMemberRow]
    func fetchSharedPosts(mine: Bool, filter: SharedPostFilter, cursor: String?) async throws -> SharedPlacePostsPage
    func createCollaborativeListRow(id: UUID, title: String, note: String?) async throws
    func joinCollaborativeList(code: String) async throws -> SaveCollaborativeListServerRow
    func createListShareCode(listID: UUID, role: SaveListRole) async throws -> (code: String, url: URL)
    func addCollaborativeListItem(listID: UUID, payload: SaveListItem) async throws
}

extension SupabaseService: LiveOutingBackend {}

/// Ephemeral, account-bound server projections. This model never confirms a save,
/// votes for another person, reads a friend's location, or persists shared content.
@MainActor
final class LiveOutingModel: ObservableObject {
    @Published private(set) var lists: [LiveOutingChoice] = []
    @Published private(set) var selectedListID: UUID?
    @Published private(set) var items: [SaveListItem] = []
    @Published private(set) var members: [LiveOutingMember] = []
    @Published private(set) var posts: [SharedPlacePost] = []
    @Published private(set) var unmappedItemCount = 0
    @Published private(set) var feedError: String?
    @Published private(set) var notice: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var shareURL: URL?

    private let ownerSubject: String
    private let sessionGeneration: Int
    private let service: any LiveOutingBackend
    private let currentSession: @MainActor () -> Bool
    private var revision: UInt64 = 0
    private var requestedListID: UUID?
    private var activeMutation: UUID?
    private var acknowledgedRevision: UInt64?
    private var pendingReloadListID: UUID?
    private struct PendingCreate {
        let title: String
        let id: UUID
        var acknowledged = false
    }
    private var pendingCreate: PendingCreate?
    private var authObservation: AnyCancellable?

    convenience init(ownerSubject: String, sessionGeneration: Int) {
        self.init(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration,
                  backend: SupabaseService.shared) {
            let auth = PrivyAuthService.shared
            guard case .authenticated(let owner) = auth.authState else { return false }
            return owner == ownerSubject && auth.currentUserId == ownerSubject
                && auth.sessionGeneration == sessionGeneration
        }
        observeAuthentication()
    }

    init(ownerSubject: String, sessionGeneration: Int, backend: any LiveOutingBackend,
         sessionIsCurrent: @escaping @MainActor () -> Bool) {
        self.ownerSubject = ownerSubject
        self.sessionGeneration = sessionGeneration
        self.service = backend
        self.currentSession = sessionIsCurrent
    }

    private func observeAuthentication() {
        // Published auth values are inspected directly because Combine delivers
        // them before the corresponding property's stored value changes.
        let auth = PrivyAuthService.shared
        authObservation = Publishers.CombineLatest(auth.$authState, auth.$sessionGeneration)
            .sink { [weak self] state, generation in
                guard case .authenticated(let owner) = state,
                      owner == self?.ownerSubject, generation == self?.sessionGeneration else {
                    self?.deactivate()
                    return
                }
            }
    }

    var selectedTitle: String {
        lists.first(where: { $0.id == selectedListID })?.title ?? "選擇共同清單"
    }

    var canEditSelected: Bool {
        sessionIsCurrent && lists.first(where: { $0.id == selectedListID })?.role.canEdit == true
    }

    var canInviteSelected: Bool {
        sessionIsCurrent && lists.first(where: { $0.id == selectedListID })?.role == .owner
    }

    func refresh() async {
        let selected = requestedListID
        await run(working: false) { ticket in
            try await self.snapshot(selected: selected, ticket: ticket)
        }
    }

    func selectList(_ id: UUID?) async {
        if id != requestedListID { pendingReloadListID = nil }
        requestedListID = id
        await run(working: false) { ticket in
            try await self.snapshot(selected: id, ticket: ticket)
        }
    }

    /// Explicit UI action only. No list or membership is created during refresh.
    func createList(title: String) async {
        await run(working: true) { ticket in
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 120 else {
                throw OutingError.message("請輸入 1–120 字的清單名稱。")
            }
            if self.pendingCreate?.title != title {
                self.pendingCreate = PendingCreate(title: title, id: UUID())
            }
            guard let pending = self.pendingCreate else { throw OutingError.invalidServerData }
            let id = pending.id
            self.requestedListID = id
            try self.check(ticket)
            // The same explicit retry reuses the UUID after an unknown response.
            // Once acknowledged, retries are reads only until confirmation.
            if !pending.acknowledged {
                try await self.service.createCollaborativeListRow(id: id, title: title, note: nil)
                try self.check(ticket)
                self.pendingCreate?.acknowledged = true
            }
            self.acknowledgedRevision = ticket
            self.pendingReloadListID = id
            try self.check(ticket)
            return try await self.snapshot(selected: id, ticket: ticket)
        }
    }

    func join(code: String) async {
        await run(working: true) { ticket in
            let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.range(of: "^[A-Za-z0-9_-]{6,32}$", options: .regularExpression) != nil else {
                throw OutingError.message("請輸入有效的清單邀請碼。")
            }
            try self.check(ticket)
            let row = try await self.service.joinCollaborativeList(code: code)
            try self.check(ticket)
            self.acknowledgedRevision = ticket
            guard let id = UUID(uuidString: row.id) else { throw OutingError.invalidServerData }
            self.requestedListID = id
            self.pendingReloadListID = id
            return try await self.snapshot(selected: id, ticket: ticket)
        }
    }

    func makeInvite() async {
        let selected = selectedListID
        await run(working: true) { ticket in
            guard let selected else { throw OutingError.chooseList }
            var result = try await self.snapshot(selected: selected, ticket: ticket)
            guard result.choices.first(where: { $0.id == selected })?.role == .owner else {
                throw OutingError.message("只有清單擁有者可以邀請成員。")
            }
            try self.check(ticket)
            let grant = try await self.service.createListShareCode(listID: selected, role: .editor)
            try self.check(ticket)
            self.acknowledgedRevision = ticket
            self.pendingReloadListID = selected
            // Revalidate access after minting as well. An invalidated operation
            // never exposes its capability URL in a later list or session.
            result = try await self.snapshot(selected: selected, ticket: ticket)
            guard result.choices.first(where: { $0.id == selected })?.role == .owner else {
                throw OutingError.message("清單權限已變更，請重新載入。")
            }
            result.invite = grant.url
            return result
        }
    }

    func add(_ payload: SaveListItem) async {
        let selected = selectedListID
        await run(working: true) { ticket in
            guard let selected else { throw OutingError.chooseList }
            let before = try await self.snapshot(selected: selected, ticket: ticket)
            guard before.choices.first(where: { $0.id == selected })?.role.canEdit == true else {
                throw OutingError.message("這份清單只能檢視，無法加入地點。")
            }
            // This ID belongs to a list candidate, never to an owned TripStop.
            let id = UUID()
            let safe = try Self.venueOnly(payload, id: id, addedBy: "成員", addedAt: Date())
            try self.check(ticket)
            try await self.service.addCollaborativeListItem(listID: selected, payload: safe)
            try self.check(ticket)
            self.acknowledgedRevision = ticket
            self.requestedListID = selected
            self.pendingReloadListID = selected
            return try await self.snapshot(selected: selected, ticket: ticket)
        }
    }

    /// Call when leaving this surface. In-flight requests lose publication
    /// authority immediately; existing server mutations are not silently undone.
    func deactivate() {
        revision &+= 1
        requestedListID = nil
        pendingCreate = nil
        pendingReloadListID = nil
        clearSharedData()
        isLoading = false
        isWorking = false
        error = nil
        notice = nil
    }

    private struct Snapshot {
        let choices: [LiveOutingChoice]
        let selected: UUID?
        let items: [SaveListItem]
        let members: [LiveOutingMember]
        let unmappedItemCount: Int
        var invite: URL?
    }

    private var sessionIsCurrent: Bool {
        currentSession()
    }

    private func check(_ ticket: UInt64) throws {
        try Task.checkCancellation()
        guard ticket == revision, sessionIsCurrent else { throw CancellationError() }
        guard service.isConfigured else {
            throw OutingError.message("共同清單服務尚未設定，目前無法連線。")
        }
    }

    private func run(working: Bool, operation: (UInt64) async throws -> Snapshot) async {
        // Reads may supersede a pending write's UI, but cannot cause a second
        // mutation to overlap a request that has already reached the server.
        let mutation = working ? UUID() : nil
        if let mutation {
            guard activeMutation == nil else { return }
            activeMutation = mutation
        }
        defer { if let mutation, activeMutation == mutation { activeMutation = nil } }
        revision &+= 1
        let ticket = revision
        clearSharedData()
        error = nil
        notice = nil
        acknowledgedRevision = nil
        isLoading = !working
        isWorking = working
        do {
            try check(ticket)
            // The service also checks this scope after token-provider suspension,
            // immediately before network I/O, and after the response. Lists are
            // otherwise outside its built-in social-request session fence.
            let result = try await SAVEPendingImportSessionScope.$current.withValue(
                (generation: sessionGeneration, owner: ownerSubject)
            ) {
                try await operation(ticket)
            }
            try check(ticket)
            requestedListID = result.selected
            lists = result.choices
            selectedListID = result.selected
            items = result.items
            members = result.members
            unmappedItemCount = result.unmappedItemCount
            shareURL = result.invite
            if let pending = pendingCreate, result.choices.contains(where: { $0.id == pending.id }) {
                pendingCreate = nil
            }
            if result.selected == pendingReloadListID { pendingReloadListID = nil }
            isLoading = false
            isWorking = false
            if let mutation, activeMutation == mutation { activeMutation = nil }
            // Feed availability is independent of list/membership availability.
            // Publish the verified team before waiting for this optional read.
            await refreshFeed(ticket: ticket)
        } catch {
            guard ticket == revision else { return }
            clearSharedData()
            isLoading = false
            isWorking = false
            guard sessionIsCurrent, !Task.isCancelled, !(error is CancellationError) else {
                requestedListID = nil
                self.error = nil
                return
            }
            if acknowledgedRevision == ticket || pendingReloadListID != nil {
                self.notice = "已提交，重新載入失敗；請重試讀取，不必再次提交。"
            } else if let pending = pendingCreate, requestedListID == pending.id {
                self.notice = pending.acknowledged
                    ? "已提交，重新載入失敗；請重試讀取，不必再次提交。"
                    : "建立結果尚未確認，請先重試讀取；再次建立相同名稱會沿用同一識別碼。"
                self.error = error.localizedDescription
            } else {
                requestedListID = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func refreshFeed(ticket: UInt64) async {
        do {
            try check(ticket)
            let page = try await SAVEPendingImportSessionScope.$current.withValue(
                (generation: sessionGeneration, owner: ownerSubject)
            ) {
                try await service.fetchSharedPosts(mine: false, filter: .all, cursor: nil)
            }
            try check(ticket)
            posts = page.items
            feedError = nil
        } catch {
            guard ticket == revision else { return }
            posts = []
            if !sessionIsCurrent || Task.isCancelled || error is CancellationError {
                requestedListID = nil
                clearSharedData()
                return
            }
            feedError = error.localizedDescription
        }
    }

    private func snapshot(selected: UUID?, ticket: UInt64) async throws -> Snapshot {
        try check(ticket)
        let rows = try await service.fetchCollaborativeListRows()
        try check(ticket)
        var choices: [LiveOutingChoice] = []
        for row in rows {
            guard let id = UUID(uuidString: row.id),
                  let role = row.viewer_role.flatMap(SaveListRole.init(rawValue:)),
                  let entries = row.items, !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !choices.contains(where: { $0.id == id }) else { throw OutingError.invalidServerData }
            choices.append(LiveOutingChoice(id: id, title: row.title, role: role, itemCount: entries.count))
        }

        var roster: [LiveOutingMember] = []
        var venues: [SaveListItem] = []
        var unmapped = 0
        if let selected {
            guard let row = rows.first(where: { UUID(uuidString: $0.id) == selected }),
                  let owner = row.owner_id, !owner.isEmpty else { throw OutingError.chooseList }
            try check(ticket)
            let memberRows = try await service.fetchListMembers(listID: selected)
            try check(ticket)
            for member in memberRows {
                guard !member.user_id.isEmpty,
                      let role = member.role.flatMap(SaveListRole.init(rawValue:)),
                      !roster.contains(where: { $0.id == member.user_id }) else { throw OutingError.invalidServerData }
                let name = member.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                roster.append(LiveOutingMember(id: member.user_id, displayName: name.isEmpty ? "成員" : name, role: role))
            }
            guard roster.filter({ $0.role == .owner }).count == 1,
                  roster.contains(where: { $0.id == owner && $0.role == .owner }) else { throw OutingError.invalidServerData }
            for entry in row.items ?? [] {
                guard let id = entry.id.flatMap(UUID.init(uuidString:)), let payload = entry.payload,
                      let addedAt = SaveCollaborativeList.serverDate(entry.created_at),
                      !venues.contains(where: { $0.id == id }) else {
                    unmapped += 1
                    continue
                }
                // Server membership supplies attribution, not client-authored names.
                let name = roster.first(where: { $0.id == entry.added_by })?.displayName ?? "成員"
                guard let venue = try? Self.venueOnly(payload, id: id, addedBy: name, addedAt: addedAt) else {
                    unmapped += 1
                    continue
                }
                venues.append(venue)
            }
        }
        try check(ticket)
        return Snapshot(choices: choices, selected: selected, items: venues, members: roster, unmappedItemCount: unmapped)
    }

    private static func venueOnly(_ payload: SaveListItem, id: UUID, addedBy: String, addedAt: Date) throws -> SaveListItem {
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, payload.latitude.isFinite, payload.longitude.isFinite,
              (-90...90).contains(payload.latitude), (-180...180).contains(payload.longitude),
              payload.latitude != 0 || payload.longitude != 0 else {
            throw OutingError.message("這個地點尚未提供可靠座標，無法加入地圖清單。")
        }
        guard payload.coordinateSystem != nil ||
                (payload.locationProvider != .amap && payload.locationProvider != .baidu) else {
            throw OutingError.message("這個地點的座標系統尚未確認，無法加入地圖清單。")
        }
        return SaveListItem(
            id: id, source: .mapCandidate, sourceID: "outing:\(id.uuidString)",
            title: title, subtitle: payload.subtitle,
            latitude: payload.latitude, longitude: payload.longitude, category: payload.category,
            rating: nil, reviewCount: nil, sourceURL: nil, photoURLs: [], note: nil,
            addedByDisplayName: addedBy, addedAt: addedAt,
            coordinateSystem: payload.coordinateSystem ?? .wgs84
        )
    }

    private func clearSharedData() {
        lists = []
        selectedListID = nil
        items = []
        members = []
        posts = []
        unmappedItemCount = 0
        feedError = nil
        shareURL = nil
    }

    private enum OutingError: LocalizedError {
        case message(String)
        case chooseList
        case invalidServerData

        var errorDescription: String? {
            switch self {
            case .message(let message): return message
            case .chooseList: return "清單不存在或存取權已變更，請重新選擇。"
            case .invalidServerData: return "共同清單資料格式不完整，無法確認成員與權限。"
            }
        }
    }
}
#endif
