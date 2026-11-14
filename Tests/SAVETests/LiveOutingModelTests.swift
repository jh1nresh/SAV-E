#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import XCTest
import MapKit
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
        XCTAssertEqual(model.snapshotRevision, 2)
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
        XCTAssertEqual(model.snapshotRevision, 1)
        backend.feed = SharedPlacePostsPage(items: [], nextCursor: nil)
        await model.selectList(OutingFixtures.b)
        gate.release()
        await old.value

        XCTAssertEqual(model.selectedListID, OutingFixtures.b)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertNil(model.feedError)
        XCTAssertEqual(model.snapshotRevision, 2, "The stale optional feed must not publish another list snapshot")
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

    func testNavigationSuspensionClearsAllPayloadAndPreservesIntentIdempotently() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(items: OutingFixtures.entry(1, payload: OutingFixtures.payload()))])
        backend.feed = try OutingFixtures.feed()
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        await model.makeInvite()
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertFalse(model.posts.isEmpty)
        XCTAssertNotNil(model.shareURL)
        let verified = model.snapshotRevision

        model.suspendForNavigation()
        model.suspendForNavigation() // inactive followed by onDisappear
        assertEmpty(model)
        XCTAssertFalse(model.canEditSelected)
        XCTAssertFalse(model.canInviteSelected)
        XCTAssertFalse(model.isWorking)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.snapshotRevision, verified)

        model.resumeAfterNavigation()
        assertEmpty(model)
        await model.refresh()
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertEqual(model.snapshotRevision, verified + 1)
        XCTAssertEqual(backend.inviteWrites, 1, "Resuming must not recreate an invitation")
    }

    func testSuspensionRejectsPreviouslySuspendedBackendResponse() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        let verified = model.snapshotRevision
        let gate = OutingReadGate()
        backend.memberGate = (OutingFixtures.a, gate)
        let old = Task { await model.refresh() }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertEqual(model.snapshotRevision, verified, "Pre-clear is not a verified snapshot")

        model.suspendForNavigation()
        gate.release()
        await old.value // No Task cancellation: the model's own fence must reject it.
        assertEmpty(model)
        XCTAssertEqual(model.snapshotRevision, verified)
        XCTAssertFalse(model.isLoading)
    }

    func testResumeRevalidatesSameListAndPublishesFreshServerItemsOnlyAfterACLRead() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        let verified = model.snapshotRevision
        model.suspendForNavigation()
        backend.rows = [try OutingFixtures.row(items: OutingFixtures.entry(2, payload: OutingFixtures.payload()))]
        let gate = OutingReadGate()
        backend.memberGate = (OutingFixtures.a, gate)
        model.resumeAfterNavigation()
        let refresh = Task { await model.refresh() }
        await fulfillment(of: [gate.entered], timeout: 2)
        assertEmpty(model)
        XCTAssertFalse(model.canEditSelected)
        XCTAssertEqual(model.snapshotRevision, verified)

        gate.release()
        await refresh.value
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertTrue(model.items.first?.id.uuidString.hasSuffix("000000000002") == true)
        XCTAssertTrue(model.canEditSelected)
        XCTAssertEqual(model.snapshotRevision, verified + 1)
        XCTAssertEqual(backend.listReads, 2)
    }

    func testRevokedResumeNeverPublishesAndForgetsRejectedSelection() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        let verified = model.snapshotRevision
        model.suspendForNavigation()
        backend.memberFailure = SupabaseError.apiError(403, "Membership revoked")
        model.resumeAfterNavigation()
        await model.refresh()
        assertEmpty(model)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.snapshotRevision, verified)

        backend.memberFailure = nil
        await model.refresh()
        XCTAssertNil(model.selectedListID, "Restored access does not silently restore a rejected selection")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.snapshotRevision, verified + 1)
    }

    func testDeactivationForgetsSuspendedIntentAndRequiresExplicitResume() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        model.suspendForNavigation()
        model.deactivate()
        let reads = backend.listReads
        await model.refresh()
        XCTAssertEqual(backend.listReads, reads)
        model.resumeAfterNavigation()
        await model.refresh()
        XCTAssertNil(model.selectedListID)
        XCTAssertEqual(model.lists.count, 1)
        XCTAssertTrue(model.members.isEmpty)
    }

    func testInvalidSessionCannotResumeOrRestoreEarlierNavigationIntent() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row()])
        let session = OutingSession()
        let model = makeModel(backend, session: session)
        await model.selectList(OutingFixtures.a)
        model.suspendForNavigation()
        let reads = backend.listReads
        session.isCurrent = false
        model.resumeAfterNavigation()
        await model.refresh()
        assertEmpty(model)
        XCTAssertEqual(backend.listReads, reads)

        session.isCurrent = true
        model.resumeAfterNavigation()
        await model.refresh()
        XCTAssertNil(model.selectedListID)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testQueuedActionsWhileSuspendedNeitherReadWriteNorReplaceResumeIntent() async throws {
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(), OutingFixtures.row(id: OutingFixtures.b)])
        let model = makeModel(backend)
        await model.selectList(OutingFixtures.a)
        model.suspendForNavigation()
        let reads = backend.listReads
        let feeds = backend.feedReads
        let payload = try JSONDecoder().decode(SaveListItem.self, from: Data(OutingFixtures.payload().utf8))
        await model.selectList(OutingFixtures.b)
        await model.refresh()
        await model.createList(title: "不可排隊寫入")
        await model.join(code: "fixtureCode")
        await model.makeInvite()
        await model.add(payload)
        assertEmpty(model)
        XCTAssertEqual(backend.listReads, reads)
        XCTAssertEqual(backend.feedReads, feeds)
        XCTAssertTrue(backend.createdIDs.isEmpty)
        XCTAssertTrue(backend.added.isEmpty)
        XCTAssertEqual(backend.joinWrites, 0)
        XCTAssertEqual(backend.inviteWrites, 0)

        model.resumeAfterNavigation()
        await model.refresh()
        XCTAssertEqual(model.selectedListID, OutingFixtures.a)
    }

    func testNavigationRetainsMutationLockUntilOriginalWriteFinishesWithoutReplay() async throws {
        let backend = try OutingFakeBackend(rows: [])
        let gate = OutingReadGate()
        backend.createGate = gate
        let model = makeModel(backend)
        let original = Task { await model.createList(title: "原始操作") }
        await fulfillment(of: [gate.entered], timeout: 2)
        let created = try XCTUnwrap(backend.createdIDs.first)
        model.suspendForNavigation()
        model.resumeAfterNavigation()
        await model.createList(title: "不可重疊")
        XCTAssertEqual(backend.createdIDs.count, 1)
        await model.refresh()
        XCTAssertEqual(model.selectedListID, created)
        XCTAssertEqual(backend.createdIDs.count, 1)
        let verified = model.snapshotRevision
        gate.release()
        await original.value
        XCTAssertEqual(model.selectedListID, created)
        XCTAssertEqual(model.snapshotRevision, verified)
        await model.createList(title: "後續明確操作")
        XCTAssertEqual(backend.createdIDs.count, 2, "Only a later explicit action may start another write")
    }

    func testNewSameListSnapshotCannotRevealOldRouteBeforeReconciliation() async throws {
        let entries = [OutingFixtures.entry(1, payload: OutingFixtures.payload()),
                       OutingFixtures.entry(2, payload: OutingFixtures.payload(latitude: 25.031))].joined(separator: ",")
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(items: entries)])
        let outing = makeModel(backend)
        await outing.selectList(OutingFixtures.a)
        let plan = LiveRoutePlan(ownerSubject: "fixture-subject", sessionGeneration: 9,
                                 makeDirections: { _ in OutingRouteDirections() }, sessionIsCurrent: { true })
        let pins = outing.items.compactMap { LiveMapPlace.shared($0, listID: OutingFixtures.a) }
        await plan.build(pins, listID: OutingFixtures.a)
        var access = LiveGuideAccess()
        access.reconcile(plan: plan, outing: outing, places: pins)
        XCTAssertTrue(access.permits(plan: plan, outing: outing))

        backend.rows = [try OutingFixtures.row(items: entries.replacingOccurrences(of: "公開地址", with: "更新後的地址"))]
        let feedGate = OutingReadGate(); backend.feedGate = feedGate
        let refresh = Task { await outing.refresh() }
        await fulfillment(of: [feedGate.entered], timeout: 2)
        XCTAssertTrue(plan.isAccessValidated, "Old plan flag is deliberately still true until the view handles the snapshot")
        XCTAssertFalse(access.permits(plan: plan, outing: outing), "New snapshot revision cannot reuse old route authorization")
        access.reconcile(plan: plan, outing: outing, places: outing.items.compactMap { LiveMapPlace.shared($0, listID: OutingFixtures.a) })
        XCTAssertTrue(plan.stops.isEmpty)
        XCTAssertFalse(access.permits(plan: plan, outing: outing))
        feedGate.release(); await refresh.value
    }

    func testNavigationDuringOptionalFeedWaitRestoresOnlyAfterFreshListValidation() async throws {
        let entries = [OutingFixtures.entry(1, payload: OutingFixtures.payload()),
                       OutingFixtures.entry(2, payload: OutingFixtures.payload(latitude: 25.031))].joined(separator: ",")
        let backend = try OutingFakeBackend(rows: [OutingFixtures.row(items: entries)])
        let outing = makeModel(backend); await outing.selectList(OutingFixtures.a)
        let plan = LiveRoutePlan(ownerSubject: "fixture-subject", sessionGeneration: 9,
                                 makeDirections: { _ in OutingRouteDirections() }, sessionIsCurrent: { true })
        let pins = outing.items.compactMap { LiveMapPlace.shared($0, listID: OutingFixtures.a) }
        await plan.build(pins, listID: OutingFixtures.a); plan.start(); plan.advance()
        var access = LiveGuideAccess(); access.reconcile(plan: plan, outing: outing, places: pins)
        let gate = OutingReadGate(); backend.feedGate = gate
        let refresh = Task { await outing.refresh() }
        await fulfillment(of: [gate.entered], timeout: 2)
        access.reconcile(plan: plan, outing: outing, places: outing.items.compactMap { LiveMapPlace.shared($0, listID: OutingFixtures.a) })
        XCTAssertTrue(access.permits(plan: plan, outing: outing), "Verified lists do not depend on optional friend feed")
        access.invalidate(); plan.suspendForNavigation(); outing.suspendForNavigation()
        XCTAssertFalse(access.permits(plan: plan, outing: outing))
        XCTAssertTrue(outing.items.isEmpty)
        gate.release(); await refresh.value
        XCTAssertTrue(outing.items.isEmpty, "Old feed completion cannot restore shared payload")
        outing.resumeAfterNavigation()
        XCTAssertFalse(access.permits(plan: plan, outing: outing))
        await outing.refresh()
        XCTAssertFalse(access.permits(plan: plan, outing: outing), "Fresh ACL data still needs itinerary reconciliation")
        access.reconcile(plan: plan, outing: outing, places: outing.items.compactMap { LiveMapPlace.shared($0, listID: OutingFixtures.a) })
        XCTAssertTrue(access.permits(plan: plan, outing: outing))
        XCTAssertEqual(plan.currentIndex, 1)
        XCTAssertTrue(plan.started)
        XCTAssertEqual(plan.stops.map(\.id), pins.map(\.id))
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
private final class OutingRouteDirections: LiveWalkingDirections {
    func route() async throws -> MKRoute { MKRoute() }
    func cancel() {}
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
