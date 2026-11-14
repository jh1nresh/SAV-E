#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import XCTest
@testable import SAVE

@MainActor
final class LiveOutingModelTests: XCTestCase {
    func testMixedServerPayloadsKeepTeamAndCountOnlyUnusableItems() async throws {
        let entries = [
            OutingFixtures.entry(1, payload: OutingFixtures.payload()),
            OutingFixtures.entry(2, payload: #"{"legacy":"unlocated clue"}"#),
            OutingFixtures.entry(3, payload: OutingFixtures.payload(latitude: 0, longitude: 0)),
            OutingFixtures.entry(4, payload: OutingFixtures.payload(system: "GCJ-02", provider: "amap")),
        ].joined(separator: ",")
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(items: entries)])
        let model = makeModel(backend)

        await model.selectList(OutingFixtures.a)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertEqual(model.lists.first?.itemCount, 4)
        XCTAssertEqual(model.members.count, 2)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.unmappedItemCount, 2)
        XCTAssertEqual(model.items.last?.coordinateSystem, .gcj02)
        XCTAssertEqual(model.items.first?.addedByDisplayName, "實際分享者")
        XCTAssertNil(model.items.first?.note)
        XCTAssertNil(model.items.first?.rating)
        XCTAssertNil(model.items.first?.sourceURL)
        XCTAssertEqual(model.items.first?.photoURLs, [])
        XCTAssertEqual(model.items.first?.source, .mapCandidate)
        XCTAssertNotEqual(model.items.first?.sourceID, "PRIVATE-SAVED-ID")
    }

    func testFeedFailureClearsOldPostsWithoutLosingVerifiedTeam() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        backend.feed = try OutingFixtures.feed()
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        XCTAssertEqual(model.posts.count, 1)

        backend.feedFailure = SupabaseError.apiError(403, "Share revoked")
        await model.refresh()

        XCTAssertNil(model.error)
        XCTAssertNotNil(model.feedError)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertEqual(model.members.count, 2)
        XCTAssertTrue(model.canInviteSelected)
        XCTAssertFalse(model.isLoading)
    }

    func testCreateSucceedsEvenWhenOptionalFeedTimesOut() async throws {
        let backend = try OutingFakeBackend(rows: [])
        backend.feedFailure = URLError(.timedOut)
        let model = makeModel(backend)

        await model.createList(title: "一起出遊")

        XCTAssertEqual(backend.createdIDs.count, 1)
        XCTAssertEqual(model.selectedListID, backend.createdIDs.first)
        XCTAssertEqual(model.members.count, 2)
        XCTAssertNil(model.error)
        XCTAssertNil(model.notice)
        XCTAssertNotNil(model.feedError)
        XCTAssertFalse(model.isWorking)
        XCTAssertTrue(backend.scopes.allSatisfy { $0.0 == "fixture-subject" && $0.1 == 9 })
    }

    func testRevokedMemberReadClearsListRosterItemsPostsAndInvite() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(items: OutingFixtures.entry(1, payload: OutingFixtures.payload()))])
        backend.feed = try OutingFixtures.feed()
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        await model.makeInvite()
        XCTAssertNotNil(model.shareURL)
        XCTAssertFalse(model.posts.isEmpty)
        XCTAssertFalse(model.items.isEmpty)

        backend.memberFailure = SupabaseError.apiError(404, "List not found")
        await model.refresh()

        assertEmpty(model)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.canEditSelected)
        XCTAssertFalse(model.canInviteSelected)
    }

    func testDelayedOldListCannotReplaceNewSelection() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(), OutingFixtures.row(id: OutingFixtures.b, title: "另一份清單")])
        let gate = OutingReadGate()
        backend.memberGate = (OutingFixtures.a, gate)
        let model = makeModel(backend)
        let old = Task { await model.selectList(OutingFixtures.a) }
        await fulfillment(of: [gate.entered], timeout: 2)

        await model.selectList(OutingFixtures.b)
        XCTAssertEqual(model.selectedListID, OutingFixtures.b)
        gate.release()
        await old.value

        XCTAssertEqual(model.selectedListID, OutingFixtures.b)
        XCTAssertEqual(model.selectedTitle, "另一份清單")
        XCTAssertNil(model.error)
    }

    func testDelayedResultDoesNotPublishAfterSessionChanges() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let gate = OutingReadGate()
        backend.memberGate = (OutingFixtures.a, gate)
        let session = OutingSession()
        let model = makeModel(backend, session: session)
        let request = Task { await model.selectList(OutingFixtures.a) }
        await fulfillment(of: [gate.entered], timeout: 2)
        session.isCurrent = false
        gate.release()
        await request.value

        assertEmpty(model)
        XCTAssertNil(model.error)
        XCTAssertNil(model.notice)
        XCTAssertEqual(backend.feedReads, 0)
    }

    func testCancellationAndLeavingInvalidateDelayedResponse() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let gate = OutingReadGate()
        backend.memberGate = (OutingFixtures.a, gate)
        let model = makeModel(backend)
        let request = Task { await model.selectList(OutingFixtures.a) }
        await fulfillment(of: [gate.entered], timeout: 2)
        model.deactivate()
        request.cancel()
        gate.release()
        await request.value

        assertEmpty(model)
        XCTAssertNil(model.error)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.isLoading)
    }

    func testAcknowledgedCreateReloadFailureRetriesReadWithoutAnotherCreate() async throws {
        let backend = try OutingFakeBackend(rows: [])
        backend.failReadsAfterCreate = true
        let model = makeModel(backend)

        await model.createList(title: "週末")
        XCTAssertEqual(backend.createdIDs.count, 1)
        assertEmpty(model)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.notice?.contains("已提交") == true)

        // Even an explicit repeat of Create must only read an acknowledged ID.
        backend.listFailure = nil
        backend.failReadsAfterCreate = false
        await model.createList(title: "週末")
        XCTAssertEqual(backend.createdIDs.count, 1)
        XCTAssertEqual(backend.rows.count, 1)
        XCTAssertEqual(model.selectedListID, backend.createdIDs.first)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.error)
    }

    func testWriteAcknowledgementAfterSessionChangeCannotPublish() async throws {
        let backend = try OutingFakeBackend(rows: [])
        let gate = OutingReadGate()
        backend.createGate = gate
        let session = OutingSession()
        let model = makeModel(backend, session: session)
        let request = Task { await model.createList(title: "週末") }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertEqual(backend.createdIDs.count, 1)
        session.isCurrent = false
        gate.release()
        await request.value

        assertEmpty(model)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.error)
        XCTAssertEqual(backend.listReads, 0)
    }

    func testDelayedOldFeedCannotReplaceNewListFeed() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(), OutingFixtures.row(id: OutingFixtures.b)])
        backend.feed = try OutingFixtures.feed()
        let gate = OutingReadGate()
        backend.feedGate = gate
        let model = makeModel(backend)
        let old = Task { await model.selectList(OutingFixtures.a) }
        await fulfillment(of: [gate.entered], timeout: 2)
        // The list is already useful while its independent feed is pending.
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertEqual(model.members.count, 2)
        backend.feed = SharedPlacePostsPage(items: [], nextCursor: nil)
        await model.selectList(OutingFixtures.b)
        gate.release()
        await old.value

        XCTAssertEqual(model.selectedListID, OutingFixtures.b)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertNil(model.feedError)
    }

    func testUnknownCreateResultUsesSameIdempotencyIDOnExplicitRetry() async throws {
        let backend = try OutingFakeBackend(rows: [])
        backend.createResponseFailure = URLError(.networkConnectionLost)
        let model = makeModel(backend)

        await model.createList(title: "週末")
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(backend.createdIDs.count, 1)
        // The fake committed before losing its response, as a real network can.
        XCTAssertEqual(backend.rows.count, 1)

        backend.createResponseFailure = nil
        await model.createList(title: "週末")
        XCTAssertEqual(backend.createdIDs.count, 2)
        XCTAssertEqual(Set(backend.createdIDs).count, 1)
        XCTAssertEqual(backend.rows.count, 1)
        XCTAssertEqual(model.selectedListID, backend.createdIDs.first)
        XCTAssertNil(model.error)
    }

    func testAcknowledgedAddReloadFailureStaysSubmittedAndRefreshNeverRewrites() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        backend.failReadsAfterAdd = true
        let payload = try JSONDecoder().decode(SaveListItem.self, from: Data(OutingFixtures.payload().utf8))

        await model.add(payload)

        XCTAssertEqual(backend.added.count, 1)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.notice?.contains("已提交") == true)
        let sent = try XCTUnwrap(backend.added.first)
        XCTAssertNil(sent.note)
        XCTAssertNil(sent.sourceURL)
        XCTAssertNil(sent.rating)
        XCTAssertTrue(sent.photoURLs.isEmpty)
        XCTAssertEqual(sent.source, .mapCandidate)
        XCTAssertNotEqual(sent.sourceID, payload.sourceID)

        backend.listFailure = nil
        await model.refresh()
        XCTAssertEqual(backend.added.count, 1)
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertNil(model.notice)
    }

    func testJoinAcknowledgementSurvivesFollowupReadFailure() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        backend.failReadsAfterJoin = true
        let model = makeModel(backend)
        await model.join(code: "realCode123")
        XCTAssertEqual(backend.joinWrites, 1)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.notice?.contains("已提交") == true)
        backend.listFailure = nil
        await model.refresh()
        XCTAssertEqual(backend.joinWrites, 1)
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
    }

    func testUnconfiguredAndViewerCannotWrite() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(role: "viewer")])
        backend.isConfigured = false
        let model = makeModel(backend)
        await model.createList(title: "不應寫入")
        XCTAssertNotNil(model.error)
        XCTAssertTrue(backend.createdIDs.isEmpty)
        XCTAssertEqual(backend.listReads, 0)

        backend.isConfigured = true
        await model.selectList(OutingFixtures.a)
        XCTAssertFalse(model.canEditSelected)
        await model.makeInvite()
        XCTAssertEqual(backend.inviteWrites, 0)
        XCTAssertNotNil(model.error)
    }

    private func makeModel(_ backend: OutingFakeBackend, session: OutingSession? = nil) -> LiveOutingModel {
        let session = session ?? OutingSession()
        return LiveOutingModel(ownerSubject: "fixture-subject", sessionGeneration: 9, backend: backend,
                               sessionIsCurrent: { session.isCurrent })
    }

    private func assertEmpty(_ model: LiveOutingModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(model.lists.isEmpty, file: file, line: line)
        XCTAssertTrue(model.items.isEmpty, file: file, line: line)
        XCTAssertTrue(model.members.isEmpty, file: file, line: line)
        XCTAssertTrue(model.posts.isEmpty, file: file, line: line)
        XCTAssertNil(model.selectedListID, file: file, line: line)
        XCTAssertNil(model.shareURL, file: file, line: line)
        XCTAssertEqual(model.unmappedItemCount, 0, file: file, line: line)
    }
}

@MainActor
private final class OutingSession {
    var isCurrent = true
}

/// A deterministic suspension at the actual backend boundary, not a sleep race.
@MainActor
private final class OutingReadGate {
    let entered = XCTestExpectation(description: "Backend request reached its suspension")
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func pause() async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class OutingFakeBackend: LiveOutingBackend {
    var isConfigured = true
    var rows: [SaveCollaborativeListServerRow]
    var roster: [SaveListMemberRow]
    var feed = SharedPlacePostsPage(items: [], nextCursor: nil)
    var listFailure: Error?
    var memberFailure: Error?
    var feedFailure: Error?
    var createResponseFailure: Error?
    var failReadsAfterCreate = false
    var failReadsAfterAdd = false
    var failReadsAfterJoin = false
    var memberGate: (UUID, OutingReadGate)?
    var createGate: OutingReadGate?
    var feedGate: OutingReadGate?
    var createdIDs: [UUID] = []
    var added: [SaveListItem] = []
    var joinWrites = 0
    var inviteWrites = 0
    var listReads = 0
    var feedReads = 0
    var scopes: [(String?, Int?)] = []

    init(rows: [SaveCollaborativeListServerRow]) throws {
        self.rows = rows
        self.roster = try OutingFixtures.roster()
    }

    private func recordScope() {
        let scope = SAVEPendingImportSessionScope.current
        scopes.append((scope?.owner, scope?.generation))
    }

    func fetchCollaborativeListRows() async throws -> [SaveCollaborativeListServerRow] {
        recordScope()
        listReads += 1
        if let listFailure { throw listFailure }
        return rows
    }

    func fetchListMembers(listID: UUID) async throws -> [SaveListMemberRow] {
        recordScope()
        if let memberFailure { throw memberFailure }
        let result = roster
        if let (id, gate) = memberGate, id == listID {
            memberGate = nil
            await gate.pause()
        }
        return result
    }

    func fetchSharedPosts(mine: Bool, filter: SharedPostFilter, cursor: String?) async throws -> SharedPlacePostsPage {
        recordScope()
        feedReads += 1
        if let feedFailure { throw feedFailure }
        let result = feed
        if let gate = feedGate {
            feedGate = nil
            await gate.pause()
        }
        return result
    }

    func createCollaborativeListRow(id: UUID, title: String, note: String?) async throws {
        recordScope()
        createdIDs.append(id)
        if !rows.contains(where: { UUID(uuidString: $0.id) == id }) {
            rows.append(try OutingFixtures.row(id: id, title: title))
        }
        if failReadsAfterCreate { listFailure = SupabaseError.apiError(503, "Read unavailable") }
        if let gate = createGate {
            createGate = nil
            await gate.pause()
        }
        if let createResponseFailure { throw createResponseFailure }
    }

    func joinCollaborativeList(code: String) async throws -> SaveCollaborativeListServerRow {
        recordScope()
        joinWrites += 1
        let row = try XCTUnwrap(rows.first)
        if failReadsAfterJoin { listFailure = SupabaseError.apiError(503, "Read unavailable") }
        return row
    }

    func createListShareCode(listID: UUID, role: SaveListRole) async throws -> (code: String, url: URL) {
        recordScope()
        inviteWrites += 1
        return ("fixtureCode", try XCTUnwrap(URL(string: "https://example.invalid/list?c=fixtureCode")))
    }

    func addCollaborativeListItem(listID: UUID, payload: SaveListItem) async throws {
        recordScope()
        added.append(payload)
        if failReadsAfterAdd { listFailure = SupabaseError.apiError(503, "Read unavailable") }
    }
}

/// Redacted wire JSON decoded by the real production DTOs. No account is seeded.
@MainActor
private enum OutingFixtures {
    static let a = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let b = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    static func row(id: UUID = a, title: String = "共同清單", role: String = "owner", items: String = "") throws -> SaveCollaborativeListServerRow {
        let data = Data("""
        {"id":"\(id.uuidString)","title":"\(title)","owner_id":"profile-owner","viewer_role":"\(role)","items":[\(items)],"created_at":"2026-11-14T00:00:00Z","updated_at":"2026-11-14T00:00:00Z"}
        """.utf8)
        return try JSONDecoder.supabase.decode(SaveCollaborativeListServerRow.self, from: data)
    }

    static func roster() throws -> [SaveListMemberRow] {
        try JSONDecoder.supabase.decode([SaveListMemberRow].self, from: Data(#"[{"user_id":"profile-owner","role":"owner","display_name":"實際分享者","created_at":"2026-11-14T00:00:00Z"},{"user_id":"profile-editor","role":"editor","display_name":null,"created_at":"2026-11-14T00:00:00Z"}]"#.utf8))
    }

    static func entry(_ index: Int, payload: String) -> String {
        """
        {"id":"33333333-3333-4333-8333-\(String(format: "%012d", index))","payload":\(payload),"added_by":"profile-owner","created_at":"2026-11-14T00:00:00Z"}
        """
    }

    static func payload(latitude: Double = 25.03, longitude: Double = 121.54, system: String = "WGS84", provider: String = "apple_maps") -> String {
        """
        {"id":"44444444-4444-4444-8444-444444444444","source":"savedPlace","sourceID":"PRIVATE-SAVED-ID","title":"分享店家","subtitle":"公開地址","latitude":\(latitude),"longitude":\(longitude),"category":"cafe","rating":5,"sourceURL":"https://example.invalid/private-source","photoURLs":["https://example.invalid/private-photo"],"note":"PRIVATE-NOTE","addedByDisplayName":"FORGED-AUTHOR","addedAt":0,"coordinateSystem":"\(system)","locationProvider":"\(provider)"}
        """
    }

    static func feed() throws -> SharedPlacePostsPage {
        try JSONDecoder().decode(SharedPlacePostsPage.self, from: Data(#"{"items":[{"id":"55555555-5555-4555-8555-555555555555","name":"已分享店家","address":"公開地址","latitude":25.03,"longitude":121.54,"coordinate_system":"WGS84","category":"cafe","status":"wantToGo","caption":"明確分享的內容","shared_at":"2026-11-14T00:00:00Z","author_id":"profile-owner","author_name":"實際分享者","visible_to_followers":true}],"nextCursor":null}"#.utf8))
    }
}
#endif
