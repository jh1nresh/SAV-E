#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW && SAVVY_CITY_MVP && targetEnvironment(simulator)
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LivePlanningReviewFixtureTests: XCTestCase {
    func testRequestRequiresBothExactFlagsAndValidNamespace() {
        let flags = ["--uitest-live-review-rail", "--uitest-review-demo-offline"]
        let id = UUID()
        let env = ["SAVE_UI_TEST_STORAGE_ID": id.uuidString]
        XCTAssertEqual(LivePlanningReviewFixture.requestedNamespace(arguments: flags, environment: env), id)
        for args in [[], Array(flags.prefix(1)), Array(flags.suffix(1)),
                     ["--uitest-live-review-rail-extra", flags[1]]] {
            XCTAssertNil(LivePlanningReviewFixture.requestedNamespace(arguments: args, environment: env))
        }
        for raw in ["", "not-a-uuid", "../outside", id.uuidString + "/outside", " " + id.uuidString] {
            XCTAssertNil(LivePlanningReviewFixture.requestedNamespace(arguments: flags, environment: ["SAVE_UI_TEST_STORAGE_ID": raw]))
        }
        XCTAssertNil(LivePlanningReviewFixture.requestedNamespace(arguments: flags, environment: [:]))
        for conflict in ["--uitest-reset-account-gate", "--uitest-reset-onboarding", "--uitest-complete-onboarding",
                         "--uitest-reset-review-demo-storage", "--uitest-show-paywall", "--uitest-unknown"] {
            XCTAssertTrue(LivePlanningReviewFixture.hasLaunchIntent(arguments: flags + [conflict]))
            XCTAssertNil(LivePlanningReviewFixture.requestedNamespace(arguments: flags + [conflict], environment: env))
        }
        XCTAssertTrue(LivePlanningReviewFixture.hasLaunchIntent(arguments: [flags[0]]),
                      "Invalid fixture requests must still suppress unrelated legacy startup mutations")
    }

    func testActiveIdentityRejectsContextConstructionWithoutClaimingStoredAccountAbsence() {
        XCTAssertTrue(LivePlanningReviewFixture.canConstruct(currentUserID: nil, isAuthenticated: false))
        XCTAssertFalse(LivePlanningReviewFixture.canConstruct(currentUserID: "fixture-account", isAuthenticated: false))
        XCTAssertFalse(LivePlanningReviewFixture.canConstruct(currentUserID: nil, isAuthenticated: true))
        XCTAssertFalse(LivePlanningReviewFixture.canConstruct(currentUserID: "fixture-account", isAuthenticated: true))
    }

    func testRealLocalCaptureProducesTwoNewCluesAndRetainsOwnerlessOlderClue() async throws {
        let fixture = try makeFixture()
        let auth = PrivyAuthService.shared
        let userBefore = auth.currentUserId, generationBefore = auth.sessionGeneration
        let vm = fixture.mapViewModel
        await vm.loadPlaces()
        XCTAssertNil(fixture.initializationError)
        XCTAssertTrue(vm.places.isEmpty)
        XCTAssertEqual(vm.reviewCandidates.map(\.name), ["Earlier fixture clue"])
        let ids = try await vm.importSharedTextAsReviewCandidates(LivePlanningReviewFixture.captureText)
        XCTAssertEqual(ids.count, 2, "Freeze the actual capture parser contract before claiming a two-result UI rail")
        let batch = vm.reviewCandidates.filter { ids.contains($0.id) }
        XCTAssertEqual(Set(batch.map(\.name)), Set(["Harbor Oven Pizza", "Fixture Tea House"]))
        XCTAssertTrue(vm.reviewCandidates.contains { $0.name == "Earlier fixture clue" })
        XCTAssertTrue(vm.reviewCandidates.allSatisfy { $0.ownerSubject == nil && !$0.hasReliableCoordinates })
        XCTAssertTrue(batch.allSatisfy { Place.from($0).sourceUrl == nil })
        XCTAssertTrue(vm.places.isEmpty, "Capture must never be counted as a confirmed save")
        XCTAssertEqual(LiveLibraryReviewProjection(candidates: vm.reviewCandidates, batchIDs: ids, query: "").matches.count, 2)
        XCTAssertEqual(LiveLibraryReviewProjection(candidates: vm.reviewCandidates, batchIDs: nil, query: "").matches.count, 3)
        XCTAssertEqual(auth.currentUserId, userBefore)
        XCTAssertEqual(auth.sessionGeneration, generationBefore)
    }

    func testIndependentNamespacesNeverSeeEachOthersClueOrDefaults() async throws {
        let first = try makeFixture(), second = try makeFixture()
        XCTAssertNotEqual(first.ownerSubject, second.ownerSubject)
        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        first.defaults.set("synthetic-only", forKey: "fixture.isolation.probe")
        XCTAssertNil(second.defaults.string(forKey: "fixture.isolation.probe"))
        _ = try await first.mapViewModel.importSharedTextAsReviewCandidates(LivePlanningReviewFixture.captureText)
        await second.mapViewModel.loadPlaces()
        XCTAssertEqual(second.mapViewModel.reviewCandidates.map(\.name), ["Earlier fixture clue"])
        XCTAssertTrue(second.mapViewModel.places.isEmpty)
    }

    func testExactSearchUsesDeterministicUnsavedResultWithoutMutatingCollection() async throws {
        let fixture = try makeFixture()
        let vm = fixture.mapViewModel
        await vm.loadPlaces()
        await vm.searchMapPlaces("Harbor Oven Pizza Los Angeles")
        let result = try XCTUnwrap(vm.mapCandidates.first)
        XCTAssertEqual(result.id, "review-map-result-fixture")
        XCTAssertEqual(result.title, "Harbor Oven Pizza — corrected branch")
        XCTAssertEqual(result.latitude, 33.741)
        XCTAssertEqual(result.longitude, -118.281)
        XCTAssertTrue(vm.places.isEmpty)
        XCTAssertEqual(vm.reviewCandidates.map(\.name), ["Earlier fixture clue"])
    }

    private func makeFixture() throws -> LivePlanningReviewFixture {
        guard LivePlanningReviewFixture.hasNoActiveIdentity else {
            throw XCTSkip("This ownerless fixture requires no active identity in the native test host; never change its auth state")
        }
        let id = UUID(), suite = "live-planning-review-unit.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("live-planning-review-unit-\(id.uuidString)", isDirectory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { @MainActor in
            // Only artifacts this test owns; never ReviewDemoStorage or another namespace.
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        return LivePlanningReviewFixture(namespace: id, directoryURL: directory, defaults: defaults, isCurrent: { true })
    }
}
#endif
