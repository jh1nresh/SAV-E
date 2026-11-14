#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LivePublicGuideModelTests: XCTestCase {
    func testPrepareOnlyReadsListsAndExplicitAddSharesVenueOnlyAfterFreshACL() async throws {
        let backend = try PublicGuideBackendFixture()
        let context = PublicGuideContext()
        let model = try model(backend, context)
        await model.prepare()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.lists.count, 1)
        XCTAssertEqual(backend.addCalls, 0)
        XCTAssertEqual(backend.feedReads, 0, "Explore's chooser does not read the private friends feed")
        await model.add(to: PublicGuideFixtures.a)
        XCTAssertEqual(backend.addCalls, 1)
        XCTAssertEqual(backend.transmitted.count, 1)
        XCTAssertEqual(model.completedListID, PublicGuideFixtures.a)
        XCTAssertTrue(model.attemptedWrite)
        XCTAssertTrue(model.writeAcknowledged)
        XCTAssertFalse(model.hasExistingVenue)
        let payload = try XCTUnwrap(backend.transmitted.first)
        XCTAssertEqual(payload.title, "Fixture Cafe")
        XCTAssertEqual(payload.subtitle, "1 Fixture Street")
        XCTAssertEqual(payload.coordinateSystem, .wgs84)
        XCTAssertEqual(payload.source, .mapCandidate)
        XCTAssertNil(payload.note); XCTAssertNil(payload.sourceURL)
        XCTAssertNil(payload.rating); XCTAssertNil(payload.reviewCount)
        XCTAssertTrue(payload.photoURLs.isEmpty)
        XCTAssertTrue(payload.addedByDisplayName.isEmpty)
        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        for privateField in ["POST-CAPTION", "POST-AUTHOR", "cdninstagram", "threads.com"] { XCTAssertFalse(wire.contains(privateField)) }
        XCTAssertTrue(backend.scopes.allSatisfy { $0.0 == "fixture-subject" && $0.1 == 7 })
        XCTAssertGreaterThanOrEqual(backend.memberReads, 2, "Fresh ACL before add and fresh read after acknowledgement")
        model.deactivate()
    }

    func testReadOnlyChoiceAndFreshMembershipChangeCannotWrite() async throws {
        for revokedAfterPrepare in [false, true] {
            let backend = try PublicGuideBackendFixture(role: revokedAfterPrepare ? "editor" : "viewer")
            let model = try model(backend)
            await model.prepare()
            if revokedAfterPrepare { backend.rows = [try PublicGuideFixtures.row(role: "viewer")] }
            await model.add(to: PublicGuideFixtures.a)
            XCTAssertFalse(model.attemptedWrite)
            XCTAssertNil(model.completedListID)
            XCTAssertEqual(backend.addCalls, 0)
            model.deactivate()
        }
        let backend = try PublicGuideBackendFixture()
        let model = try model(backend)
        await model.prepare()
        backend.memberFailure = SupabaseError.apiError(404, "Membership unavailable")
        await model.add(to: PublicGuideFixtures.a)
        XCTAssertTrue(model.lists.isEmpty)
        XCTAssertEqual(backend.addCalls, 0)
        XCTAssertNil(model.completedListID)
        model.deactivate()
    }

    func testCanonicalExistingVenueCompletesWithoutAnyPostOrSave() async throws {
        let backend = try PublicGuideBackendFixture()
        let venue = try PublicGuideFixtures.venue()
        let pin = try XCTUnwrap(LiveMapPlace.discovery(venue))
        try backend.commit(pin.listPayload)
        let model = try model(backend)
        await model.prepare()
        await model.add(to: PublicGuideFixtures.a)
        XCTAssertTrue(model.hasExistingVenue)
        XCTAssertFalse(model.attemptedWrite)
        XCTAssertEqual(model.completedListID, PublicGuideFixtures.a)
        XCTAssertEqual(backend.addCalls, 0)
        model.deactivate()
    }

    func testLostAcknowledgementCanOnlyReconcileAndNeverResend() async throws {
        let backend = try PublicGuideBackendFixture()
        backend.responseFailure = URLError(.networkConnectionLost)
        let model = try model(backend)
        await model.prepare()
        await model.add(to: PublicGuideFixtures.a)
        XCTAssertEqual(model.state, .unconfirmed)
        XCTAssertTrue(model.attemptedWrite)
        XCTAssertFalse(model.writeAcknowledged)
        XCTAssertNil(model.completedListID)
        await model.add(to: PublicGuideFixtures.a)
        await model.add(to: UUID())
        XCTAssertEqual(backend.addCalls, 1)
        await model.reconcile()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.completedListID, PublicGuideFixtures.a)
        XCTAssertFalse(model.hasExistingVenue, "A post-response read cannot claim it existed before the attempt")
        XCTAssertFalse(model.writeAcknowledged, "Read confirmation does not fabricate a received acknowledgement")
        XCTAssertEqual(backend.addCalls, 1)
        model.deactivate()
    }

    func testAcknowledgedWriteWithFailedFollowupReadStaysUnconfirmedUntilReadOnlyRecovery() async throws {
        let backend = try PublicGuideBackendFixture()
        backend.failReadAfterWrite = true
        let model = try model(backend)
        await model.prepare(); await model.add(to: PublicGuideFixtures.a)
        XCTAssertTrue(model.writeAcknowledged)
        XCTAssertEqual(model.state, .unconfirmed)
        XCTAssertNil(model.completedListID)
        XCTAssertTrue(model.lists.isEmpty)
        backend.memberFailure = nil
        await model.reconcile()
        XCTAssertEqual(model.completedListID, PublicGuideFixtures.a)
        XCTAssertEqual(backend.addCalls, 1)
        model.deactivate()
    }

    func testUncommittedFailureNeverRetriesEvenWhenLaterReadsFindNothing() async throws {
        let backend = try PublicGuideBackendFixture()
        backend.commitBeforeResponse = false
        backend.responseFailure = URLError(.timedOut)
        let model = try model(backend)
        await model.prepare(); await model.add(to: PublicGuideFixtures.a)
        await model.reconcile(); await model.add(to: PublicGuideFixtures.a); await model.prepare()
        XCTAssertEqual(model.state, .unconfirmed)
        XCTAssertNil(model.completedListID)
        XCTAssertEqual(backend.addCalls, 1)
        XCTAssertTrue(backend.transmitted.isEmpty)
        model.deactivate()
    }

    func testHeldPreflightRejectsAccountExpiryCancellationAndDeactivationWithoutWrite() async throws {
        for invalidation in 0..<4 {
            let backend = try PublicGuideBackendFixture()
            let context = PublicGuideContext()
            let model = try model(backend, context)
            await model.prepare()
            let gate = PublicGuideGate(); backend.memberGate = gate
            let task = Task { await model.add(to: PublicGuideFixtures.a) }
            await fulfillment(of: [gate.entered], timeout: 2)
            switch invalidation {
            case 0: context.current = false
            case 1: context.now = context.now.addingTimeInterval(61)
            case 2: task.cancel()
            default: model.deactivate()
            }
            gate.release(); await task.value
            XCTAssertEqual(backend.addCalls, 0)
            XCTAssertFalse(model.attemptedWrite)
            XCTAssertNil(model.completedListID)
            XCTAssertTrue(model.lists.isEmpty)
            XCTAssertFalse(model.isLoading); XCTAssertFalse(model.isWorking)
            model.deactivate()
        }
    }

    func testHeldTokenLikeWriteKeepsAttemptLockAndCancellationBlocksTransport() async throws {
        let backend = try PublicGuideBackendFixture()
        let gate = PublicGuideGate(); backend.writeGate = gate
        let model = try model(backend)
        await model.prepare()
        let task = Task { await model.add(to: PublicGuideFixtures.a) }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertTrue(model.attemptedWrite)
        await model.add(to: PublicGuideFixtures.a)
        XCTAssertEqual(backend.addCalls, 1)
        task.cancel()
        model.deactivate()
        await model.prepare(); await model.reconcile(); await model.add(to: PublicGuideFixtures.a)
        XCTAssertEqual(backend.addCalls, 1)
        gate.release(); await task.value
        XCTAssertTrue(backend.transmitted.isEmpty, "Actual transport point checks cancellation after token-like suspension")
        XCTAssertNil(model.completedListID)
        XCTAssertEqual(model.state, .inactive)
    }

    func testRealDeadlineCancelsHeldWriteBeforeTransportAndRejectsLateCompletion() async throws {
        let backend = try PublicGuideBackendFixture()
        let gate = PublicGuideGate(); backend.writeGate = gate
        let model = LivePublicGuideModel(venue: try PublicGuideFixtures.venue(), expiresAt: Date().addingTimeInterval(0.5),
            ownerSubject: "fixture-subject", sessionGeneration: 7, backend: backend, sessionIsCurrent: { true })
        let expired = expectation(description: "Owned deadline invalidates the pending write")
        let observer = model.$state.filter { $0 == .unavailable }.prefix(1).sink { _ in expired.fulfill() }
        await model.prepare()
        let task = Task { await model.add(to: PublicGuideFixtures.a) }
        await fulfillment(of: [gate.entered, expired], timeout: 3, enforceOrder: true)
        gate.release(); await task.value
        XCTAssertTrue(model.attemptedWrite)
        XCTAssertTrue(backend.transmitted.isEmpty)
        XCTAssertNil(model.completedListID)
        XCTAssertEqual(model.state, .unavailable)
        withExtendedLifetime(observer) {}
        model.deactivate()
    }

    private func model(_ backend: PublicGuideBackendFixture, _ context: PublicGuideContext? = nil) throws -> LivePublicGuideModel {
        let context = context ?? PublicGuideContext()
        return LivePublicGuideModel(venue: try PublicGuideFixtures.venue(), expiresAt: context.now.addingTimeInterval(60),
            ownerSubject: "fixture-subject", sessionGeneration: 7, backend: backend,
            sessionIsCurrent: { context.current }, now: { context.now })
    }
}

@MainActor
private final class PublicGuideContext {
    var current = true
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
private final class PublicGuideGate {
    let entered = XCTestExpectation(description: "Real backend boundary suspended")
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class PublicGuideBackendFixture: LiveOutingBackend {
    var isConfigured = true
    var rows: [SaveCollaborativeListServerRow]
    var memberFailure: Error?
    var responseFailure: Error?
    var commitBeforeResponse = true
    var failReadAfterWrite = false
    var memberGate: PublicGuideGate?
    var writeGate: PublicGuideGate?
    var addCalls = 0
    var memberReads = 0
    var feedReads = 0
    var transmitted: [SaveListItem] = []
    var scopes: [(String?, Int?)] = []
    init(role: String = "editor") throws { rows = [try PublicGuideFixtures.row(role: role)] }
    private func recordScope() {
        let scope = SAVEPendingImportSessionScope.current; scopes.append((scope?.owner, scope?.generation))
    }
    func fetchCollaborativeListRows() async throws -> [SaveCollaborativeListServerRow] { recordScope(); return rows }
    func fetchListMembers(listID: UUID) async throws -> [SaveListMemberRow] {
        recordScope(); memberReads += 1
        if let gate = memberGate { memberGate = nil; await gate.pause() }
        if let memberFailure { throw memberFailure }
        return try JSONDecoder().decode([SaveListMemberRow].self, from: Data(#"[{"user_id":"profile-owner","role":"owner","display_name":null},{"user_id":"profile-editor","role":"editor","display_name":null}]"#.utf8))
    }
    func fetchSharedPosts(mine: Bool, filter: SharedPostFilter, cursor: String?) async throws -> SharedPlacePostsPage {
        feedReads += 1; XCTFail("Chooser must not query the friend feed"); return .init(items: [], nextCursor: nil)
    }
    func addCollaborativeListItem(listID: UUID, payload: SaveListItem) async throws {
        recordScope(); addCalls += 1
        if let gate = writeGate { writeGate = nil; await gate.pause() }
        try Task.checkCancellation() // Same post-token cancellation boundary as the real scoped Supabase request.
        if commitBeforeResponse { transmitted.append(payload); try commit(payload) }
        if failReadAfterWrite { memberFailure = URLError(.timedOut) }
        if let responseFailure { throw responseFailure }
    }
    func commit(_ payload: SaveListItem) throws {
        // Server-assigned row ID deliberately differs from the client payload ID.
        rows[0].items = (rows[0].items ?? []) + [.init(id: UUID().uuidString, payload: payload,
            added_by: "profile-editor", created_at: "2026-11-15T00:00:00Z")]
    }
    func createCollaborativeListRow(id: UUID, title: String, note: String?) async throws { XCTFail("No list creation"); throw URLError(.unsupportedURL) }
    func joinCollaborativeList(code: String) async throws -> SaveCollaborativeListServerRow { XCTFail("No automatic join"); throw URLError(.unsupportedURL) }
    func createListShareCode(listID: UUID, role: SaveListRole) async throws -> (code: String, url: URL) { XCTFail("No invite creation"); throw URLError(.unsupportedURL) }
}

@MainActor
private enum PublicGuideFixtures {
    static let a = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static func row(role: String) throws -> SaveCollaborativeListServerRow {
        try JSONDecoder().decode(SaveCollaborativeListServerRow.self, from: Data("""
        {"id":"\(a.uuidString)","title":"Fixture shared list","owner_id":"profile-owner","viewer_role":"\(role)","items":[]}
        """.utf8))
    }
    static func venue() throws -> LivePublicDiscoveryVenue {
        let json = #"{"schemaVersion":1,"indexRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generatedAt":"2026-11-14T12:00:00.000Z","expiresAt":"2026-11-14T12:05:00.000Z","coverage":[{"platform":"instagram","status":"not_connected","indexedPostCount":0},{"platform":"threads","status":"connected","indexedPostCount":1},{"platform":"xiaohongshu","status":"not_connected","indexedPostCount":0}],"posts":[{"id":"threads:FixtureA","platform":"threads","sourceURL":"https://www.threads.com/@fixture/post/FixtureA","authorName":"POST-AUTHOR","authorHandle":"fixture","title":"POST-CAPTION","publishedAt":null,"verifiedAt":"2026-11-14T12:00:00.000Z","visibility":"public","locationEvidence":"reviewed_match","cover":{"url":"https://scontent.cdninstagram.com/fixture.jpg","expiresAt":"2026-11-14T12:05:00.000Z","permission":"author"},"place":{"provider":"apple_maps","providerPlaceID":"fixture-venue","name":"Fixture Cafe","address":"1 Fixture Street","latitude":25.03,"longitude":121.54,"coordinateSystem":"WGS84","category":"cafe"}}],"nextCursor":null}"#
        let page = try JSONDecoder().decode(LivePublicDiscoveryPage.self, from: Data(json.utf8))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z"))
        return try XCTUnwrap(page.validated(at: now).venues.first)
    }
}
#endif
