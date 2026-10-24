import Foundation
import UIKit
import XCTest
@testable import SAVE

final class ProfileAvatarStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileAvatarStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testAvatarPersistsAcrossStoreReloadForSameAccount() throws {
        let avatar = Data([0x01, 0x02, 0x03])
        let firstStore = ProfileAvatarStore(baseDirectory: directory)

        try firstStore.save(avatar, for: "account-a")

        let reloadedStore = ProfileAvatarStore(baseDirectory: directory)
        XCTAssertEqual(reloadedStore.load(for: "account-a"), avatar)
    }

    @MainActor
    func testAvatarDoesNotCrossAccountBoundary() throws {
        let store = ProfileAvatarStore(baseDirectory: directory)
        try store.save(Data([0x0A]), for: "account-a")
        try store.save(Data([0x0B]), for: "account-b")

        XCTAssertEqual(store.load(for: "account-a"), Data([0x0A]))
        XCTAssertEqual(store.load(for: "account-b"), Data([0x0B]))
    }

    @MainActor
    func testRemovingOneAccountAvatarPreservesAnother() throws {
        let store = ProfileAvatarStore(baseDirectory: directory)
        try store.save(Data([0x0A]), for: "account-a")
        try store.save(Data([0x0B]), for: "account-b")

        try store.remove(for: "account-a")

        XCTAssertNil(store.load(for: "account-a"))
        XCTAssertEqual(store.load(for: "account-b"), Data([0x0B]))
    }

    @MainActor
    func testMigratesOnlyTheExactLegacyAppOwnedAvatarPath() throws {
        let store = ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("Profile/Avatars"))
        let legacyData = Data([0x0C, 0x0D])
        try FileManager.default.createDirectory(
            at: store.legacyAvatarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyData.write(to: store.legacyAvatarURL)

        let migrated = try store.migrateLegacyAvatarIfNeeded(
            from: store.legacyAvatarURL.absoluteString,
            for: "account-a"
        )

        XCTAssertEqual(migrated, legacyData)
        XCTAssertEqual(store.load(for: "account-a"), legacyData)
        XCTAssertEqual(try Data(contentsOf: store.legacyAvatarURL), legacyData)
    }

    @MainActor
    func testLegacyMigrationNeverOverwritesAnAccountAvatarOrUsesAnotherFileURL() throws {
        let store = ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("Profile/Avatars"))
        try FileManager.default.createDirectory(
            at: store.legacyAvatarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x0C]).write(to: store.legacyAvatarURL)
        try store.save(Data([0x0A]), for: "account-a")

        let existing = try store.migrateLegacyAvatarIfNeeded(
            from: store.legacyAvatarURL.absoluteString,
            for: "account-a"
        )
        XCTAssertEqual(existing, Data([0x0A]))
        XCTAssertEqual(store.load(for: "account-a"), Data([0x0A]))

        let otherFile = directory.appendingPathComponent("untrusted-avatar.jpg")
        try Data([0x0B]).write(to: otherFile)
        XCTAssertNil(try store.migrateLegacyAvatarIfNeeded(
            from: otherFile.absoluteString,
            for: "account-b"
        ))
        XCTAssertNil(store.load(for: "account-b"))
    }

    @MainActor
    func testUnconfiguredRemoteProfileUpdateRejectsInsteadOfReportingSuccess() async {
        do {
            try await SupabaseService(apiBaseURL: nil).updateProfile(profile(named: "Changed"))
            XCTFail("Missing API configuration must not report a persisted name")
        } catch SupabaseError.notConfigured {
            // Expected: the view model can report the real partial-save result.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testPhotoOnlyUpdatePersistsLocallyWithoutCallingProfileAPI() async {
        var updateCalls = 0
        let store = ProfileAvatarStore(baseDirectory: directory)
        let model = makeProfileViewModel(
            avatarStore: store,
            updateProfileRemotely: { _ in updateCalls += 1 }
        )
        model.profile = profile(named: "Original")

        let saved = await model.updateProfile(displayName: "Original", avatarData: avatarData())

        XCTAssertTrue(saved)
        XCTAssertEqual(updateCalls, 0)
        XCTAssertNotNil(store.load(for: "account-a"))
        XCTAssertNotNil(model.localAvatarData)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testNameAndPhotoRemoteFailureKeepsPhotoAndRevertsName() async {
        let store = ProfileAvatarStore(baseDirectory: directory)
        let model = makeProfileViewModel(
            avatarStore: store,
            updateProfileRemotely: { _ in throw ProfileUpdateTestError.offline }
        )
        model.profile = profile(named: "Original")

        let saved = await model.updateProfile(displayName: "Changed", avatarData: avatarData())

        XCTAssertTrue(saved)
        XCTAssertEqual(model.profile.displayName, "Original")
        XCTAssertNotNil(store.load(for: "account-a"))
        XCTAssertNotNil(model.localAvatarData)
        XCTAssertTrue(model.errorMessage?.contains("Photo saved on this device") == true)
        XCTAssertTrue(model.errorMessage?.contains("Offline") == true)
    }

    @MainActor
    func testNameOnlyRemoteFailureReturnsFalseAndRestoresName() async {
        let model = makeProfileViewModel(
            avatarStore: ProfileAvatarStore(baseDirectory: directory),
            updateProfileRemotely: { _ in throw ProfileUpdateTestError.offline }
        )
        model.profile = profile(named: "Original")

        let saved = await model.updateProfile(displayName: "Changed", avatarData: nil)

        XCTAssertFalse(saved)
        XCTAssertEqual(model.profile.displayName, "Original")
        XCTAssertEqual(model.errorMessage, "Offline")
    }

    @MainActor
    func testDeleteAccountRemovesOnlyTheDeletingOwnerVaultRecords() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        defer { PrivyAuthService.shared.authState = previousAuth }

        let vaultURL = directory.appendingPathComponent("delete-account-vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: vaultURL)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A stays", ownerSubject: "did:privy:a"))
        try vault.append(SaveMemoryRecord(state: .confirmedPlace, title: "B goes", ownerSubject: "did:privy:b"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, sourceText: "Legacy private note", title: "Legacy clue"))

        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: StubAccountDeletionService(),
            avatarStore: ProfileAvatarStore(baseDirectory: directory),
            saveLocalVaultService: vault,
            pendingPlaceImportService: PendingPlaceImportService(overrideContainerURL: directory),
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { "did:privy:b" },
            reviewerDemoProvider: { false }
        )

        let deleted = await model.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertEqual(try vault.recentRecords(limit: 10).map(\.title), ["A stays"])
        XCTAssertEqual(try vault.recentRecords(limit: 10, belongingTo: "did:privy:a").map(\.title), ["A stays"])
        XCTAssertTrue(try vault.recentRecords(limit: 10, belongingTo: "did:privy:b").isEmpty)
    }

    @MainActor
    func testAccountDeletionCleansCapturedScopeAfterSwitchWithoutSigningOutB() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        var currentOwner: String? = "account-a"
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        let a = SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a")
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        let legacy = SaveMemoryRecord(state: .sourceOnly, sourceText: "Old private note", title: "Old clue")
        let later = SaveMemoryRecord(state: .sourceOnly, title: "New ownerless clue")
        for record in [a, b, legacy] { try vault.append(record) }
        let store = ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars"))
        try store.save(Data([1]), for: "account-a")
        try store.save(Data([2]), for: "account-b")
        var requests = 0
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService {
                requests += 1
                await Task.yield()
                currentOwner = "account-b"
                auth.authState = .authenticated(userId: "account-b")
                try vault.append(later)
            },
            avatarStore: store, saveLocalVaultService: vault,
            pendingPlaceImportService: PendingPlaceImportService(overrideContainerURL: directory),
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { currentOwner }, reviewerDemoProvider: { false }
        )
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(auth.currentUserId, "account-b")
        XCTAssertEqual(Set(try vault.recentRecords().map(\.id)), [b.id, later.id])
        XCTAssertEqual(try vault.recentRecords(belongingTo: nil).map(\.id), [later.id])
        XCTAssertEqual(try vault.recentRecords(belongingTo: "account-b").map(\.id), [b.id])
        XCTAssertNil(store.load(for: "account-a"))
        XCTAssertEqual(store.load(for: "account-b"), Data([2]))
    }

    @MainActor
    func testAccountDeletionRemoteFailureDoesNotPurgeLocalData() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private clue"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { "account-a" }) {
            requests += 1
            throw ProfileUpdateTestError.offline
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(auth.currentUserId, "account-a", "unknown outcome keeps A signed in")
        XCTAssertTrue(model.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertTrue(try vault.recentRecords().isEmpty)
        XCTAssertTrue(try vault.recentRecords(belongingTo: nil).isEmpty)
        XCTAssertTrue(try vault.recentRecords(belongingTo: "account-a").isEmpty)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertFalse(model.isDeletingAccount)
    }

    /// P1 4366314370: a live DELETE throw must still quarantine both Share
    /// queues while A stays signed in. Recovery is no longer the only path
    /// that reaches `purgeAccountDeletionItems`.
    @MainActor
    func testLiveRemoteDeleteThrowQuarantinesBothShareQueuesAndKeepsUserSignedIn() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A pending"),
            pendingDeletionPlace(owner: "account-b", name: "B pending"),
            pendingDeletionPlace(owner: nil, name: "Legacy pending"),
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A review"),
            pendingDeletionReview(owner: "account-b", name: "B review"),
            pendingDeletionReview(owner: nil, name: "Legacy review"),
        ])
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { "account-a" }) {
            requests += 1
            throw ProfileUpdateTestError.offline
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(auth.currentUserId, "account-a", "unknown outcome keeps A signed in")
        XCTAssertTrue(model.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B pending"])
        XCTAssertFalse(
            remainingPlaces.contains { $0.ownerSubject == "account-a" || $0.name == "Legacy pending" },
            "A-owned and snapshotted ownerless pending places must be quarantined on live DELETE throw"
        )
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B review"])
        XCTAssertFalse(
            remainingReviews.contains { $0.ownerSubject == "account-a" || $0.candidateName == "Legacy review" },
            "A-owned and snapshotted ownerless pending reviews must be quarantined on live DELETE throw"
        )
    }

    @MainActor
    func testAccountDeletionWithNoLocalVaultStillCallsRemoteDeletion() async {
        var owner: String? = "account-a"
        var requests = 0
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("absent-vault.json"))
        let model = deletionModel(vault: vault, currentOwner: { owner }) {
            requests += 1
            owner = nil
        }
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testAccountDeletionSnapshotReadFailureDoesNotDeleteRemoteAccount() async throws {
        let url = directory.appendingPathComponent("vault.json")
        // An existing directory cannot be read as the JSON vault file.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var requests = 0
        let model = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { "account-a" }) {
            requests += 1
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(requests, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDeletingAccount)
    }

    @MainActor
    func testAccountDeletionPurgeReadFailureRetainsScopeForSignedOutRetry() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let backup = directory.appendingPathComponent("backup.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old legacy clue"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        var currentOwner: String? = "account-a"
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { currentOwner }) {
            requests += 1
            await Task.yield()
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertTrue(model.errorMessage?.contains("Account deleted, but local data cleanup failed") == true)
        XCTAssertEqual(requests, 1)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: backup, to: url)
        let later = SaveMemoryRecord(state: .sourceOnly, title: "Later ownerless clue")
        try vault.append(later)
        currentOwner = nil
        let retried = await model.deleteAccount()
        XCTAssertTrue(retried)
        XCTAssertEqual(requests, 1, "Deleted identity must not be needed again to finish cleanup")
        XCTAssertEqual(try vault.recentRecords().map(\.id), [later.id])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testAccountDeletionPurgeWriteFailureCannotReportSuccessOrReuseScopeForB() async throws {
        let previousAuth = PrivyAuthService.shared.authState
        defer { PrivyAuthService.shared.authState = previousAuth }
        let parent = directory.appendingPathComponent("storage")
        let backup = directory.appendingPathComponent("storage-backup")
        let vault = SaveLocalVaultService(overrideVaultURL: parent.appendingPathComponent("vault.json"))
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old ownerless clue"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        try vault.append(b)
        var currentOwner: String? = "account-a"
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { currentOwner }) {
            requests += 1
            await Task.yield()
            if requests == 1 {
                try FileManager.default.moveItem(at: parent, to: backup)
                // A file at the directory path deterministically prevents the coordinated write.
                try Data([1]).write(to: parent)
            }
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertTrue(model.errorMessage?.contains("Account deleted, but local data cleanup failed") == true)
        XCTAssertFalse(model.isDeletingAccount)
        currentOwner = "account-b"
        PrivyAuthService.shared.authState = .authenticated(userId: "account-b")
        let stillUnavailableRetry = await model.deleteAccount()
        XCTAssertFalse(stillUnavailableRetry)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(model.errorMessage?.contains("could not be completed") == true)
        XCTAssertEqual(PrivyAuthService.shared.currentUserId, "account-b")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: backup, to: parent)
        let later = SaveMemoryRecord(state: .sourceOnly, title: "Later ownerless clue")
        try vault.append(later)
        let cleanupRetried = await model.deleteAccount()
        XCTAssertFalse(cleanupRetried, "Finishing A cleanup must not claim that B was deleted")
        XCTAssertTrue(model.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(PrivyAuthService.shared.currentUserId, "account-b")
        XCTAssertEqual(Set(try vault.recentRecords().map(\.id)), [b.id, later.id])
        // Only a subsequent explicit B deletion is a new request with a fresh snapshot.
        let bDeleted = await model.deleteAccount()
        XCTAssertTrue(bDeleted)
        XCTAssertEqual(requests, 2)
        XCTAssertTrue(try vault.recentRecords().isEmpty)
    }

    @MainActor
    func testFreshProfileLoadRecoversUnknownDeletionWhileSignedOutWithoutRemoteRequest() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let old = SaveMemoryRecord(state: .sourceOnly, sourceText: "Old private note", title: "Old legacy clue")
        let a = SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a")
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        for row in [old, a, b] { try vault.append(row) }
        let prepared = try vault.prepareAccountDeletion(belongingTo: "account-a")
        // Simulate crash after the request may have succeeded, before its receipt.
        XCTAssertEqual(prepared.remoteOutcome, .awaitingRemoteResult)
        let later = SaveMemoryRecord(state: .sourceOnly, title: "New ownerless clue")
        try vault.append(later)
        let reloadedVault = SaveLocalVaultService(overrideVaultURL: url)
        XCTAssertEqual(try reloadedVault.recentRecords(belongingTo: nil).map(\.id), [later.id])
        var remoteRequests = 0
        let freshModel = deletionModel(vault: reloadedVault, currentOwner: { nil }) { remoteRequests += 1 }
        await freshModel.loadProfile()
        XCTAssertEqual(remoteRequests, 0)
        XCTAssertTrue(freshModel.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertNil(try reloadedVault.pendingAccountDeletionIntent())
        XCTAssertEqual(Set(try reloadedVault.recentRecords().map(\.id)), [b.id, later.id])
    }

    @MainActor
    func testFreshProfileRecoversSuccessfulRemoteReceiptAndPreservesB() async throws {
        let auth = PrivyAuthService.shared
        let oldAuth = auth.authState
        let oldDefaults = SavePlaceLimitHandoff.testDefaults
        let suite = "known-deleted-a-current-b-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = oldAuth
            SavePlaceLimitHandoff.testDefaults = oldDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old legacy"))
        try vault.append(b)
        let prepared = try vault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try vault.recordRemoteAccountDeletionSuccess(intentID: prepared.id)
        // A fresh VM must recover using disk, without a usable A session.
        auth.authState = .authenticated(userId: "account-b")
        SavePlaceLimitHandoff.syncActiveOwner("account-b")
        var requests = 0
        let fresh = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { "account-b" }) {
            requests += 1
        }
        let result = await fresh.deleteAccount()
        XCTAssertFalse(result, "A cleanup must not claim B was deleted")
        XCTAssertEqual(fresh.errorMessage, "Previous account’s local cleanup is complete. Retry to delete this account.")
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(auth.currentUserId, "account-b")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), "account-b")
        XCTAssertEqual(try vault.recentRecords().map(\.id), [b.id])
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
    }

    @MainActor
    func testDeletionIntentPersistenceFailureBlocksRemoteRequestAndPreservesRecords() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Private legacy"))
        let before = try Data(contentsOf: url)
        // A directory at the receipt path is an actual unreadable/unwritable receipt.
        try FileManager.default.createDirectory(at: url.appendingPathExtension("account-deletion.json"), withIntermediateDirectories: true)
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { "account-a" }) { requests += 1 }
        let result = await model.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertThrowsError(try vault.recentRecords(belongingTo: nil), "Unreadable receipt must fail closed")
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testLiveDeletionCannotBeConsumedOrResentBySameOrFreshProfile() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old legacy"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let before = try Data(contentsOf: url)
        var requests = 0
        var original: ProfileViewModel!
        var fresh: ProfileViewModel!
        defer { original = nil; fresh = nil }
        original = deletionModel(vault: vault, currentOwner: { "account-a" }) {
            requests += 1
            await Task.yield()
            let intent = try XCTUnwrap(vault.pendingAccountDeletionIntent())
            await original.loadProfile()
            fresh = self.deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { "account-b" }) {
                XCTFail("Another Profile must not send DELETE during A's live request")
            }
            await fresh.loadProfile()
            let duplicate = await fresh.deleteAccount()
            XCTAssertFalse(duplicate)
            XCTAssertTrue(fresh.errorMessage?.contains("already in progress") == true)
            XCTAssertEqual(try vault.pendingAccountDeletionIntent(), intent)
            XCTAssertEqual(try Data(contentsOf: url), before, "Neither live recovery path may purge before HTTP finishes")
            throw ProfileUpdateTestError.offline
        }
        let result = await original.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(original.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertTrue(try vault.recentRecords().isEmpty)
        // The lease ends with the request. Live unknown-outcome cleanup already
        // finished; a later Profile must not send another DELETE.
        await fresh.loadProfile()
        XCTAssertEqual(requests, 1)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertTrue(try vault.recentRecords().isEmpty)
    }

    @MainActor
    func testFreshProfileLoadFinishesOnlyKnownDeletedSessionAndPreservesUnknownOrOtherOwner() async throws {
        let auth = PrivyAuthService.shared
        let originalAuth = auth.authState
        defer { auth.authState = originalAuth }
        for (currentOwner, remoteSucceeded) in [("account-a", true), ("account-b", true), ("account-a", false)] {
            let url = directory.appendingPathComponent(currentOwner + String(remoteSucceeded) + ".json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old legacy"))
            let intent = try vault.prepareAccountDeletion(belongingTo: "account-a")
            if remoteSucceeded { _ = try vault.recordRemoteAccountDeletionSuccess(intentID: intent.id) }
            auth.authState = .authenticated(userId: currentOwner)
            let fresh = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) {
                XCTFail("Known successful receipt requires no remote request")
            }
            await fresh.loadProfile()
            XCTAssertNil(try vault.pendingAccountDeletionIntent())
            if remoteSucceeded { XCTAssertEqual(fresh.errorMessage, "Previous account’s local cleanup is complete.") }
            else { XCTAssertTrue(fresh.errorMessage?.contains("remote account deletion result could not be confirmed") == true) }
            if currentOwner == "account-a" && remoteSucceeded { XCTAssertNil(auth.currentUserId) }
            else { XCTAssertEqual(auth.currentUserId, currentOwner) }
        }
    }

    @MainActor
    func testIntentWriteFailurePreventsRemoteDelete() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Private legacy"))
        let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { "account-a" }) { requests += 1 }
        let result = await model.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
    }

    @MainActor
    func testAvatarCleanupFailureKeepsDurableReceiptUntilFreshProfileRecovery() async throws {
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private clue"))
        let avatars = directory.appendingPathComponent("avatars")
        let store = ProfileAvatarStore(fileManager: FailingAvatarRemovalFileManager(), baseDirectory: avatars)
        try store.save(Data([1]), for: "account-a")
        var requests = 0
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService { requests += 1 },
            avatarStore: store, saveLocalVaultService: vault,
            pendingPlaceImportService: PendingPlaceImportService(overrideContainerURL: directory),
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { "account-a" }, reviewerDemoProvider: { false }
        )
        let result = await model.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
        XCTAssertNotNil(store.load(for: "account-a"))
        let fresh = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { nil }) {
            XCTFail("Fresh Profile must recover locally")
        }
        await fresh.loadProfile()
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertNil(ProfileAvatarStore(baseDirectory: avatars).load(for: "account-a"))
        XCTAssertEqual(fresh.errorMessage, "Previous account’s local cleanup is complete.")
    }

    /// P1 4365736452: queue purge runs before fallible avatar removal so a
    /// protected-storage failure cannot leave A-owned or snapshotted ownerless
    /// Share rows consumable while the deletion receipt stays.
    @MainActor
    func testAvatarCleanupFailureStillPurgesPendingQueues() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A pending"),
            pendingDeletionPlace(owner: "account-b", name: "B pending"),
            pendingDeletionPlace(owner: nil, name: "Legacy")
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A review"),
            pendingDeletionReview(owner: "account-b", name: "B review"),
            pendingDeletionReview(owner: nil, name: "Legacy")
        ])
        let avatars = directory.appendingPathComponent("avatars")
        let store = ProfileAvatarStore(fileManager: FailingAvatarRemovalFileManager(), baseDirectory: avatars)
        try store.save(Data([1]), for: "account-a")
        var requests = 0
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService { requests += 1 },
            avatarStore: store, saveLocalVaultService: vault,
            pendingPlaceImportService: queue,
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { "account-a" }, reviewerDemoProvider: { false }
        )
        let result = await model.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
        XCTAssertNotNil(store.load(for: "account-a"))
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B pending"])
        XCTAssertFalse(remainingPlaces.contains { $0.name == "Legacy" || $0.ownerSubject == "account-a" })
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B review"])
        XCTAssertFalse(remainingReviews.contains { $0.candidateName == "Legacy" || $0.ownerSubject == "account-a" })
    }

    /// P1 4366239479: a failed vault-record purge after remote delete must
    /// not leave the deleted session able to consume either Share queue.
    @MainActor
    func testVaultRecordPurgeFailureStillQuarantinesPendingQueues() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        vault.purgeAccountDeletionRecordsError = SaveLocalVaultError.storageUnavailable
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A private clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A pending"),
            pendingDeletionPlace(owner: "account-b", name: "B pending"),
            pendingDeletionPlace(owner: nil, name: "Legacy")
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A review"),
            pendingDeletionReview(owner: "account-b", name: "B review"),
            pendingDeletionReview(owner: nil, name: "Legacy")
        ])
        var requests = 0
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService { requests += 1 },
            avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
            saveLocalVaultService: vault,
            pendingPlaceImportService: queue,
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { "account-a" },
            reviewerDemoProvider: { false }
        )
        let result = await model.deleteAccount()
        XCTAssertFalse(result)
        XCTAssertEqual(requests, 1)
        XCTAssertNil(auth.currentUserId, "deleted owner must be signed out before the vault purge fails")
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B pending"])
        XCTAssertFalse(remainingPlaces.contains { $0.name == "Legacy" || $0.ownerSubject == "account-a" })
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B review"])
        XCTAssertFalse(remainingReviews.contains { $0.candidateName == "Legacy" || $0.ownerSubject == "account-a" })
        XCTAssertTrue(model.errorMessage?.contains("Account deleted, but local data cleanup failed") == true)
    }

    @MainActor
    func testDeletionAndKnownSuccessRecoveryKeepQuarantineThroughLogout() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-quarantine-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        for recovering in [false, true] {
            auth.authState = .authenticated(userId: "account-a")
            SavePlaceLimitHandoff.syncActiveOwner("account-a")
            let snapshot = ShareOwnerSnapshot(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner())
            let url = directory.appendingPathComponent("quarantine-\(recovering).json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            let b = SaveMemoryRecord(state: .sourceOnly, title: "B stays", ownerSubject: "account-b")
            try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private clue"))
            try vault.append(b)
            if recovering {
                let intent = try vault.prepareAccountDeletion(belongingTo: "account-a")
                _ = try vault.recordRemoteAccountDeletionSuccess(intentID: intent.id)
            }
            var remoteRequests = 0
            var suspensionCalls = 0
            var shareWriteRejected = false
            var coalescedSignOut: Task<Void, Never>?
            var coalescedSignOutFinished = false
            auth.signOutSuspension = {
                suspensionCalls += 1
                coalescedSignOut = Task {
                    await auth.signOut()
                    coalescedSignOutFinished = true
                }
                await Task.yield()
                XCTAssertFalse(coalescedSignOutFinished, "A second caller must wait for the existing logout")
                do {
                    XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
                    XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
                    let fresh = self.deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { auth.currentUserId }) {
                        XCTFail("A concurrent recovery must not send DELETE")
                    }
                    await fresh.loadProfile()
                    let duplicate = await fresh.deleteAccount()
                    XCTAssertFalse(duplicate)
                    XCTAssertTrue(fresh.errorMessage?.contains("already in progress") == true)
                    var coordinationError: NSError?
                    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                        do {
                            // Same production binding used by the Share writer after
                            // its coordinated lock is granted, with no analysis token.
                            try snapshot.validate(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(), credential: nil)
                            let row = ["state": "source_only", "ownerSubject": "account-a", "sourceText": "Must not append"]
                            try SaveMemoryVaultAppender.appending(row, to: Data(contentsOf: coordinatedURL)).write(to: coordinatedURL)
                            XCTFail("An open A Share must reject during logout")
                        } catch ShareAnalysisError.sessionChanged { shareWriteRejected = true }
                        catch { XCTFail("Unexpected error: \(error)") }
                    }
                    XCTAssertNil(coordinationError)
                    // A previously admitted writer may complete late. The retained
                    // intent hides it, and completion must re-purge after the await.
                    try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Late A", ownerSubject: "account-a"))
                    XCTAssertTrue(try vault.recentRecords(belongingTo: "account-a").isEmpty)
                } catch { XCTFail("Unexpected error: \(error)") }
            }
            let model = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) { remoteRequests += 1 }
            if recovering { await model.loadProfile() }
            else {
                let deleted = await model.deleteAccount()
                XCTAssertTrue(deleted)
            }
            await coalescedSignOut?.value
            XCTAssertTrue(coalescedSignOutFinished)
            XCTAssertEqual(suspensionCalls, 1)
            XCTAssertTrue(shareWriteRejected)
            XCTAssertEqual(remoteRequests, recovering ? 0 : 1)
            XCTAssertNil(auth.currentUserId)
            XCTAssertNil(try vault.pendingAccountDeletionIntent())
            XCTAssertEqual(try vault.recentRecords().map(\.id), [b.id])
        }
    }

    @MainActor
    func testSwitchToBDuringDeletionLogoutKeepsBSessionCacheAndNewRows() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-switch-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("switch.json"))
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B private", ownerSubject: "account-b")
        let later = SaveMemoryRecord(state: .sourceOnly, title: "New ownerless")
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Initial ownerless"))
        try vault.append(b)
        auth.signOutSuspension = {
            await Task.yield()
            XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
            auth.authState = .authenticated(userId: "account-b")
            SavePlaceLimitHandoff.syncActiveOwner("account-b")
            do { try vault.append(later) } catch { XCTFail("Unexpected error: \(error)") }
        }
        let model = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) {}
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted, "The completed request deleted A")
        XCTAssertEqual(auth.currentUserId, "account-b")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), "account-b")
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertEqual(Set(try vault.recentRecords().map(\.id)), [b.id, later.id])
    }

    @MainActor
    func testFinalCleanupFailureAfterLogoutRetainsReceiptForFreshSignedOutRecovery() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-final-failure-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")
        let url = directory.appendingPathComponent("failure.json")
        let backup = directory.appendingPathComponent("failure-backup.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private"))
        auth.signOutSuspension = {
            await Task.yield()
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch { XCTFail("Unexpected error: \(error)") }
        }
        var remoteRequests = 0
        let model = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) { remoteRequests += 1 }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertNil(auth.currentUserId)
        XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
        XCTAssertTrue(model.errorMessage?.contains("Account deleted, but local data cleanup failed") == true)
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: backup, to: url)
        auth.signOutSuspension = { XCTFail("Signed-out recovery must not log out a new session") }
        let fresh = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { auth.currentUserId }) {
            remoteRequests += 1
            XCTFail("Recovery must not retry remote DELETE")
        }
        await fresh.loadProfile()
        XCTAssertEqual(remoteRequests, 1)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertTrue(try vault.recentRecords().isEmpty)
    }

    @MainActor
    func testUnknownDeletionRecoveryKeepsCurrentOwnerCacheAndDoesNotLogout() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-unknown-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("unknown.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private"))
        _ = try vault.prepareAccountDeletion(belongingTo: "account-a")
        auth.signOutSuspension = { XCTFail("Unknown remote outcome must not log out A") }
        let fresh = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) {
            XCTFail("Unknown receipt recovery must not send DELETE")
        }
        await fresh.loadProfile()
        XCTAssertEqual(auth.currentUserId, "account-a")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), "account-a")
        XCTAssertTrue(fresh.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
    }

    /// P2 4366334143: signed-out recovery after a recorded successful DELETE
    /// must clear the stale Keychain binding before the receipt is removed.
    /// A replacement account's binding stays.
    @MainActor
    func testSignedOutSuccessfulDeletionRecoveryClearsStaleAccountBinding() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        let deletedRef = "save_account_" + String(repeating: "A", count: 43)
        let replacementRef = "save_account_" + String(repeating: "B", count: 43)

        let signedOutStore = InMemoryAccountReferenceStore(value: deletedRef)
        let signedOutVault = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("signed-out-binding.json")
        )
        try signedOutVault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let signedOutIntent = try signedOutVault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try signedOutVault.recordRemoteAccountDeletionSuccess(intentID: signedOutIntent.id)
        auth.authState = .unauthenticated
        let signedOut = deletionModel(
            vault: signedOutVault,
            currentOwner: { auth.currentUserId },
            accountReferenceStore: signedOutStore
        ) { XCTFail("Signed-out recovery must not send DELETE") }
        await signedOut.loadProfile()
        XCTAssertNil(auth.currentUserId)
        XCTAssertNil(signedOutStore.value, "stale deleted-account binding must not survive receipt removal")
        XCTAssertEqual(signedOutStore.clearCount, 1)
        XCTAssertNil(try signedOutVault.pendingAccountDeletionIntent())

        let replacementStore = InMemoryAccountReferenceStore(value: replacementRef)
        let replacementVault = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("replacement-binding.json")
        )
        try replacementVault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        try replacementVault.append(SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b"))
        let replacementIntent = try replacementVault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try replacementVault.recordRemoteAccountDeletionSuccess(intentID: replacementIntent.id)
        auth.authState = .authenticated(userId: "account-b")
        let replacement = deletionModel(
            vault: replacementVault,
            currentOwner: { auth.currentUserId },
            accountReferenceStore: replacementStore
        ) { XCTFail("B recovery must not send DELETE") }
        await replacement.loadProfile()
        XCTAssertEqual(auth.currentUserId, "account-b")
        XCTAssertEqual(replacementStore.value, replacementRef, "B's binding must survive A's cleanup")
        XCTAssertEqual(replacementStore.clearCount, 0)
        XCTAssertNil(try replacementVault.pendingAccountDeletionIntent())
    }

    /// P2 PRRT_kwDOTYZUp86v3Mrb: signed-out recovery must keep the durable
    /// receipt when Keychain clear throws, then finish on retry.
    @MainActor
    func testSignedOutDeletionKeepsReceiptWhenBindingClearFailsThenRetryCompletes() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        let deletedRef = "save_account_" + String(repeating: "A", count: 43)
        let store = InMemoryAccountReferenceStore(value: deletedRef)
        store.clearError = ProfileUpdateTestError.offline
        let vault = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("signed-out-clear-fail.json")
        )
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let intent = try vault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try vault.recordRemoteAccountDeletionSuccess(intentID: intent.id)
        auth.authState = .unauthenticated
        XCTAssertNil(auth.currentUserId)

        let model = deletionModel(
            vault: vault,
            currentOwner: { auth.currentUserId },
            accountReferenceStore: store
        ) { XCTFail("Signed-out recovery must not send DELETE") }

        let first = await model.deleteAccount()
        XCTAssertFalse(first)
        XCTAssertTrue(
            model.errorMessage?.localizedCaseInsensitiveContains("retry to finish") == true,
            model.errorMessage ?? "missing error"
        )
        let kept = try XCTUnwrap(vault.pendingAccountDeletionIntent())
        XCTAssertEqual(kept.id, intent.id)
        XCTAssertEqual(kept.remoteOutcome, .succeeded)
        XCTAssertEqual(store.value, deletedRef)
        XCTAssertEqual(store.clearCount, 0)

        store.clearError = nil
        let retry = await model.deleteAccount()
        XCTAssertTrue(retry)
        XCTAssertNil(store.value)
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertNil(auth.currentUserId)
    }

    /// P2 PRRT_kwDOTYZUp86v3W8L: signed-in clear failure must still sign out
    /// and keep the receipt so signed-out retry can finish the binding.
    @MainActor
    func testSignedInDeletionSignsOutAndKeepsReceiptWhenBindingClearFailsThenRetryCompletes() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let suite = "delete-signed-in-clear-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        let deletedRef = "save_account_" + String(repeating: "A", count: 43)
        let store = InMemoryAccountReferenceStore(value: deletedRef)
        store.clearError = ProfileUpdateTestError.offline
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vault = SaveLocalVaultService(
            overrideVaultURL: directory.appendingPathComponent("signed-in-clear-fail.json")
        )
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A pending"),
            pendingDeletionPlace(owner: "account-b", name: "B pending")
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A review"),
            pendingDeletionReview(owner: "account-b", name: "B review")
        ])
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")

        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService {},
            avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
            saveLocalVaultService: vault,
            pendingPlaceImportService: queue,
            accountReferenceStore: store,
            currentUserIDProvider: { auth.currentUserId },
            reviewerDemoProvider: { false }
        )

        let first = await model.deleteAccount()
        XCTAssertFalse(first)
        XCTAssertNil(auth.currentUserId)
        XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
        XCTAssertTrue(
            model.errorMessage?.localizedCaseInsensitiveContains("retry to finish") == true,
            model.errorMessage ?? "missing error"
        )
        let kept = try XCTUnwrap(vault.pendingAccountDeletionIntent())
        XCTAssertEqual(kept.remoteOutcome, .succeeded)
        XCTAssertEqual(store.value, deletedRef)
        XCTAssertEqual(store.clearCount, 0)
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B pending"])
        XCTAssertFalse(remainingPlaces.contains { $0.ownerSubject == "account-a" })
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B review"])
        XCTAssertFalse(remainingReviews.contains { $0.ownerSubject == "account-a" })

        store.clearError = nil
        let retry = await model.deleteAccount()
        XCTAssertTrue(retry)
        XCTAssertNil(store.value)
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        XCTAssertNil(auth.currentUserId)
    }

    @MainActor
    func testBothPendingQueuesPurgeAdmittedLateWritersBeforeClearingIntent() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-pending-writer-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        let release = DispatchSemaphore(value: 0)
        defer {
            release.signal(); release.signal()
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")
        let snapshot = ShareOwnerSnapshot(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner())
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("pending-vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A private", ownerSubject: "account-a"))
        // Pre-deletion ownerless rows are snapshotted and purged with A.
        // B and later ownerless rows stay (see the dedicated ownerless test).
        let retained: [[String: String]] = [
            ["ownerSubject": "account-b", "futureField": "B preserved"]
        ]
        let original = try JSONEncoder().encode(retained + [
            ["futureField": "Pre-deletion ownerless"]
        ])
        let late = ["ownerSubject": "account-a", "futureField": "Late A admitted before invalidation"]
        let admittedData = try SaveMemoryVaultAppender.appending(late, to: original)
        let urls = [SAVEProductionConfig.pendingPlacesFileName, SAVEProductionConfig.pendingReviewCandidatesFileName]
            .map { directory.appendingPathComponent($0) }
        var writers: [Task<Void, Error>] = []
        for url in urls {
            try original.write(to: url)
            // The writer has passed its final owner check, then is paused while
            // holding exactly the per-queue lock used by Share append.
            try snapshot.validate(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(), credential: nil)
            let (events, ready) = AsyncStream<Void>.makeStream()
            let writer = Task.detached {
                defer { ready.finish() }
                var coordinationError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                    ready.yield(())
                    guard release.wait(timeout: .now() + 15) == .success else {
                        writeError = CocoaError(.fileWriteUnknown)
                        return
                    }
                    do { try admittedData.write(to: coordinatedURL, options: .atomic) }
                    catch { writeError = error }
                }
                if let coordinationError { throw coordinationError }
                if let writeError { throw writeError }
            }
            writers.append(writer)
            var iterator = events.makeAsyncIterator()
            let readyValue = await iterator.next()
            XCTAssertNotNil(readyValue)
        }
        auth.signOutSuspension = {
            await Task.yield()
            XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
            auth.authState = .authenticated(userId: "account-b")
            SavePlaceLimitHandoff.syncActiveOwner("account-b")
            release.signal(); release.signal()
        }
        let model = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) {}
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted)
        for writer in writers { try await writer.value }
        XCTAssertEqual(auth.currentUserId, "account-b")
        XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), "account-b")
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        for url in urls {
            XCTAssertEqual(try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url)), retained)
            // A writer admitted only after cleanup sees B under the same lock
            // and cannot recreate the deleted A queue entry.
            var rejected = false
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { coordinatedURL in
                do {
                    try snapshot.validate(cachedActiveOwner: SavePlaceLimitHandoff.cachedActiveOwner(), credential: nil)
                    try admittedData.write(to: coordinatedURL, options: .atomic)
                } catch ShareAnalysisError.sessionChanged { rejected = true }
                catch { XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertNil(error)
            XCTAssertTrue(rejected)
            XCTAssertEqual(try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url)), retained)
        }
    }

    @MainActor
    func testPendingQueueCorruptionOrWriteFailureRetainsReceiptUntilRetry() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let suite = "delete-pending-failure-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        for corrupt in [true, false] {
            let container = directory.appendingPathComponent("queue-failure-\(corrupt)")
            let url = container.appendingPathComponent("vault.json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy"))
            let pending = PendingPlaceImportService(overrideContainerURL: container)
            let queueURLs = [SAVEProductionConfig.pendingPlacesFileName, SAVEProductionConfig.pendingReviewCandidatesFileName]
                .map { container.appendingPathComponent($0) }
            let queue = queueURLs[corrupt ? 1 : 0]
            let rows = [["ownerSubject": "account-a", "futureField": "A"], ["ownerSubject": "account-b", "futureField": "B"]]
            let valid = try JSONEncoder().encode(rows)
            for queueURL in queueURLs { try valid.write(to: queueURL) }
            if corrupt { try Data("broken-json".utf8).write(to: queue) }
            auth.authState = .authenticated(userId: "account-a")
            SavePlaceLimitHandoff.syncActiveOwner("account-a")
            auth.signOutSuspension = {
                if !corrupt {
                    do { try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: container.path) }
                    catch { XCTFail("Unexpected error: \(error)") }
                }
            }
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path) }
            var requests = 0
            let model = ProfileViewModel(
                supabaseService: SupabaseService(apiBaseURL: nil),
                accountDeletionService: ClosureAccountDeletionService { requests += 1 },
                avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
                saveLocalVaultService: vault, pendingPlaceImportService: pending,
                accountReferenceStore: InMemoryAccountReferenceStore(),
                currentUserIDProvider: { auth.currentUserId }, reviewerDemoProvider: { false })
            let deleted = await model.deleteAccount()
            XCTAssertFalse(deleted)
            XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
            XCTAssertNil(SavePlaceLimitHandoff.cachedActiveOwner())
            XCTAssertEqual(requests, 1)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path)
            if corrupt { try valid.write(to: queue) }
            auth.authState = .authenticated(userId: "account-b")
            SavePlaceLimitHandoff.syncActiveOwner("account-b")
            let fresh = ProfileViewModel(
                supabaseService: SupabaseService(apiBaseURL: nil),
                accountDeletionService: ClosureAccountDeletionService { XCTFail("Retry must not delete B remotely") },
                avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
                saveLocalVaultService: SaveLocalVaultService(overrideVaultURL: url), pendingPlaceImportService: pending,
                accountReferenceStore: InMemoryAccountReferenceStore(),
                currentUserIDProvider: { auth.currentUserId }, reviewerDemoProvider: { false })
            await fresh.loadProfile()
            XCTAssertNil(try vault.pendingAccountDeletionIntent())
            XCTAssertEqual(auth.currentUserId, "account-b")
            XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), "account-b")
            for queueURL in queueURLs {
                XCTAssertEqual(try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: queueURL)), [rows[1]])
            }
        }
    }

    @MainActor
    func testSDKOwnerMismatchRetainsDeletionReceiptUntilSignedOutOrBRecovery() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let previousSDKProvider = auth.signOutSDKUserIDProvider
        let suite = "delete-sdk-owner-mismatch-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            auth.signOutSDKUserIDProvider = previousSDKProvider
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        for recoveryOwner in [nil, "account-b"] as [String?] {
            let url = directory.appendingPathComponent("sdk-mismatch-\(recoveryOwner ?? "signedout").json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            let b = SaveMemoryRecord(state: .sourceOnly, title: "B private", ownerSubject: "account-b")
            try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Initial legacy"))
            try vault.append(b)
            auth.authState = .authenticated(userId: "account-a")
            SavePlaceLimitHandoff.syncActiveOwner("account-a")
            var lookups = 0
            var logoutCalls = 0
            auth.signOutSDKUserIDProvider = {
                await Task.yield()
                lookups += 1
                // The SDK has B while its auth-state stream still reports A.
                return "account-b"
            }
            auth.signOutSuspension = { logoutCalls += 1 }
            var remoteRequests = 0
            let model = deletionModel(vault: vault, currentOwner: { auth.currentUserId }) { remoteRequests += 1 }
            let deleted = await model.deleteAccount()
            XCTAssertFalse(deleted)
            XCTAssertEqual(lookups, 1)
            XCTAssertEqual(logoutCalls, 0, "The shared production identity guard must not log out SDK B")
            XCTAssertEqual(auth.currentUserId, "account-a")
            XCTAssertTrue(model.errorMessage?.contains("session is still active") == true)
            XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .succeeded)
            let late = SaveMemoryRecord(state: .sourceOnly, title: "Late A remains quarantined", ownerSubject: "account-a")
            try vault.append(late)
            XCTAssertTrue(try vault.recentRecords(belongingTo: "account-a").isEmpty)
            XCTAssertTrue(try SaveLocalVaultService(overrideVaultURL: url).recentRecords(belongingTo: nil).isEmpty)
            // Recover locally once the real app session has caught up. Neither
            // missing A credentials nor a current B account requires another DELETE.
            auth.authState = recoveryOwner.map { .authenticated(userId: $0) } ?? .unauthenticated
            SavePlaceLimitHandoff.syncActiveOwner(recoveryOwner)
            let fresh = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { auth.currentUserId }) {
                remoteRequests += 1
                XCTFail("Recovery must not repeat remote DELETE")
            }
            await fresh.loadProfile()
            XCTAssertEqual(remoteRequests, 1)
            XCTAssertEqual(lookups, 1)
            XCTAssertEqual(logoutCalls, 0)
            XCTAssertEqual(auth.currentUserId, recoveryOwner)
            XCTAssertEqual(SavePlaceLimitHandoff.cachedActiveOwner(), recoveryOwner)
            XCTAssertNil(try vault.pendingAccountDeletionIntent())
            XCTAssertEqual(try vault.recentRecords().map(\.id), [b.id])
        }
    }

    /// P1 4365127940: aborting logout must not leave Share seeing a signed-out
    /// owner while the app session is still A.
    @MainActor
    func testAbortedSDKLogoutKeepsShareOwnerCache() async throws {
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        let previousDefaults = SavePlaceLimitHandoff.testDefaults
        let previousSuspension = auth.signOutSuspension
        let previousSDKProvider = auth.signOutSDKUserIDProvider
        let suite = "abort-logout-owner-cache-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SavePlaceLimitHandoff.testDefaults = defaults
        defer {
            auth.authState = previousAuth
            auth.signOutSuspension = previousSuspension
            auth.signOutSDKUserIDProvider = previousSDKProvider
            SavePlaceLimitHandoff.testDefaults = previousDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        auth.authState = .authenticated(userId: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-a")
        var logoutCalls = 0
        auth.signOutSDKUserIDProvider = {
            await Task.yield()
            return "account-b"
        }
        auth.signOutSuspension = { logoutCalls += 1 }
        await auth.signOut()
        XCTAssertEqual(logoutCalls, 0, "An SDK owner mismatch must abort before logout")
        XCTAssertEqual(auth.currentUserId, "account-a")
        XCTAssertEqual(
            SavePlaceLimitHandoff.cachedActiveOwner(),
            "account-a",
            "Share must still see A when logout aborts and the app stays signed in as A"
        )
    }

    @MainActor
    func testConsumedBatchesCannotRestoreDeletedOwnerButNewSameOwnerBatchCan() throws {
        let container = directory.appendingPathComponent("consumed-batches")
        let vault = SaveLocalVaultService(overrideVaultURL: container.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A private", ownerSubject: "account-a"))
        let service = PendingPlaceImportService(overrideContainerURL: container)
        let placeA = pendingDeletionPlace(owner: "account-a", name: "A")
        let placeB = pendingDeletionPlace(owner: "account-b", name: "B")
        let placeLegacy = pendingDeletionPlace(owner: nil, name: "Legacy")
        let reviewA = pendingDeletionReview(owner: "account-a", name: "A")
        let reviewB = pendingDeletionReview(owner: "account-b", name: "B")
        let reviewLegacy = pendingDeletionReview(owner: nil, name: "Legacy")
        service.restorePendingPlaces([placeA, placeB, placeLegacy])
        service.restorePendingReviewCandidates([reviewA, reviewB, reviewLegacy])
        let oldToken = try XCTUnwrap(service.restorationToken(consumingOwner: "account-a"))
        let consumedPlaces = service.consumePendingPlaces(ownerSubject: "account-a") + service.consumePendingPlaces(ownerSubject: "account-b")
        let consumedReviews = service.consumePendingReviewCandidates(ownerSubject: "account-a") + service.consumePendingReviewCandidates(ownerSubject: "account-b")
        let intent = try vault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try vault.recordRemoteAccountDeletionSuccess(intentID: intent.id)
        try service.purgeAccountDeletionItems(belongingTo: "account-a")
        try vault.purgeAccountDeletionRecords(intentID: intent.id)
        try vault.completeAccountDeletionCleanup(intentID: intent.id)
        // A different service object and a canonical-equivalent path must share
        // invalidation; the old batch outlives both disk purge and intent removal.
        let fresh = PendingPlaceImportService(overrideContainerURL: container.appendingPathComponent("../consumed-batches"))
        fresh.restorePendingPlaces(consumedPlaces, restorationToken: oldToken)
        fresh.restorePendingReviewCandidates(consumedReviews, restorationToken: oldToken)
        XCTAssertTrue(fresh.consumePendingPlaces(ownerSubject: "account-a").isEmpty)
        XCTAssertTrue(fresh.consumePendingReviewCandidates(ownerSubject: "account-a").isEmpty)
        XCTAssertEqual(fresh.consumePendingPlaces(ownerSubject: "account-b").map(\.name), ["B"])
        XCTAssertEqual(fresh.consumePendingReviewCandidates(ownerSubject: "account-b").map(\.candidateName), ["B"])
        // A later account recreation/new batch, even with identical payloads,
        // captures the new epoch and is not permanently blacklisted.
        fresh.restorePendingPlaces([placeA])
        fresh.restorePendingReviewCandidates([reviewA])
        let newToken = try XCTUnwrap(fresh.restorationToken())
        let newPlaces = fresh.consumePendingPlaces(ownerSubject: "account-a")
        let newReviews = fresh.consumePendingReviewCandidates(ownerSubject: "account-a")
        fresh.restorePendingPlaces(newPlaces, restorationToken: newToken)
        fresh.restorePendingReviewCandidates(newReviews, restorationToken: newToken)
        XCTAssertEqual(fresh.consumePendingPlaces(ownerSubject: "account-a").map(\.name), ["A"])
        XCTAssertEqual(fresh.consumePendingReviewCandidates(ownerSubject: "account-a").map(\.candidateName), ["A"])
    }

    @MainActor
    func testOrdinaryAccountSwitchAndDifferentContainerDoNotInvalidateConsumedBatches() throws {
        let suite = "pending-normal-switch-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = directory.appendingPathComponent("normal")
        let service = PendingPlaceImportService(overrideContainerURL: container)
        service.restorePendingPlaces([pendingDeletionPlace(owner: "account-a", name: "A")])
        service.restorePendingReviewCandidates([pendingDeletionReview(owner: "account-a", name: "A")])
        SavePlaceLimitHandoff.syncActiveOwner("account-a", defaults: defaults)
        let token = try XCTUnwrap(service.restorationToken())
        let places = service.consumePendingPlaces(ownerSubject: "account-a")
        let reviews = service.consumePendingReviewCandidates(ownerSubject: "account-a")
        SavePlaceLimitHandoff.syncActiveOwner("account-b", defaults: defaults)
        let otherContainer = directory.appendingPathComponent("independent")
        try FileManager.default.createDirectory(at: otherContainer, withIntermediateDirectories: true)
        try PendingPlaceImportService(overrideContainerURL: otherContainer).purgeAccountDeletionItems(belongingTo: "account-a")
        service.restorePendingPlaces(places, restorationToken: token)
        service.restorePendingReviewCandidates(reviews, restorationToken: token)
        XCTAssertEqual(service.consumePendingPlaces(ownerSubject: "account-a").map(\.name), ["A"])
        XCTAssertEqual(service.consumePendingReviewCandidates(ownerSubject: "account-a").map(\.candidateName), ["A"])
    }

    /// P1 4365399819: restart with `.awaitingRemoteResult` must still purge
    /// A-owned pending queues before the quarantine receipt is removed.
    @MainActor
    func testRestartAwaitingRemoteResultPurgesAOwnedPendingQueues() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A pending"),
            pendingDeletionPlace(owner: "account-b", name: "B pending")
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A review"),
            pendingDeletionReview(owner: "account-b", name: "B review")
        ])
        let prepared = try vault.prepareAccountDeletion(
            belongingTo: "account-a",
            initialOwnerlessQueueItemKeys: try queue.ownerlessItemKeysForAccountDeletion()
        )
        XCTAssertEqual(prepared.remoteOutcome, .awaitingRemoteResult)
        var remoteRequests = 0
        let fresh = deletionModel(
            vault: SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json")),
            currentOwner: { "account-a" }
        ) { remoteRequests += 1 }
        await fresh.loadProfile()
        XCTAssertEqual(remoteRequests, 0)
        XCTAssertEqual(auth.currentUserId, "account-a", "unknown outcome keeps A signed in")
        XCTAssertTrue(fresh.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B pending"])
        XCTAssertFalse(
            remainingPlaces.contains { $0.ownerSubject == "account-a" },
            "A-owned pending places, including private source text, must not become consumable"
        )
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B review"])
        XCTAssertFalse(remainingReviews.contains { $0.ownerSubject == "account-a" })
    }

    /// P1 4365547382: pre-deletion ownerless Share rows are snapshotted like
    /// vault IDs. Later ownerless rows and other owners stay.
    @MainActor
    func testAccountDeletionPurgesPreDeletionOwnerlessQueueItemsAndPreservesLaterAndOthers() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        queue.restorePendingPlaces([
            pendingDeletionPlace(owner: "account-a", name: "A"),
            pendingDeletionPlace(owner: "account-b", name: "B"),
            pendingDeletionPlace(owner: nil, name: "Legacy")
        ])
        queue.restorePendingReviewCandidates([
            pendingDeletionReview(owner: "account-a", name: "A"),
            pendingDeletionReview(owner: "account-b", name: "B"),
            pendingDeletionReview(owner: nil, name: "Legacy")
        ])
        var currentOwner: String? = "account-a"
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { currentOwner }) {
            requests += 1
            currentOwner = nil
            queue.restorePendingPlaces([self.pendingDeletionPlace(owner: nil, name: "Later")])
            queue.restorePendingReviewCandidates([self.pendingDeletionReview(owner: nil, name: "Later")])
        }
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted)
        XCTAssertEqual(requests, 1)
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingPlaces.map(\.name)), ["B", "Later"])
        XCTAssertFalse(remainingPlaces.contains { $0.name == "Legacy" || $0.ownerSubject == "account-a" })
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(Set(remainingReviews.map(\.candidateName)), ["B", "Later"])
        XCTAssertFalse(remainingReviews.contains { $0.candidateName == "Legacy" || $0.ownerSubject == "account-a" })
    }

    @MainActor
    func testFailedKnownSuccessQueuePurgeStillInvalidatesPreviouslyConsumedBatch() throws {
        let service = PendingPlaceImportService(overrideContainerURL: directory)
        service.restorePendingPlaces([pendingDeletionPlace(owner: "account-a", name: "A")])
        service.restorePendingReviewCandidates([pendingDeletionReview(owner: "account-a", name: "A")])
        let token = try XCTUnwrap(service.restorationToken())
        let places = service.consumePendingPlaces(ownerSubject: "account-a")
        let reviews = service.consumePendingReviewCandidates(ownerSubject: "account-a")
        let corruptQueue = directory.appendingPathComponent(SAVEProductionConfig.pendingReviewCandidatesFileName)
        try Data("broken-json".utf8).write(to: corruptQueue)
        XCTAssertThrowsError(try service.purgeAccountDeletionItems(belongingTo: "account-a"))
        try Data("[]".utf8).write(to: corruptQueue)
        let fresh = PendingPlaceImportService(overrideContainerURL: directory)
        fresh.restorePendingPlaces(places, restorationToken: token)
        fresh.restorePendingReviewCandidates(reviews, restorationToken: token)
        XCTAssertTrue(fresh.consumePendingPlaces(ownerSubject: "account-a").isEmpty)
        XCTAssertTrue(fresh.consumePendingReviewCandidates(ownerSubject: "account-a").isEmpty)
    }

    /// P1 4365736453: ownerless rows consumed by the deleting session cannot
    /// restore after that owner's generation advances. B's in-flight ownerless
    /// batch is bound to B and still restores.
    @MainActor
    func testConsumedOwnerlessBatchCannotRestoreAfterDeletingAccount() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = PendingPlaceImportService(overrideContainerURL: directory)
        service.restorePendingPlaces([
            pendingDeletionPlace(owner: nil, name: "Legacy"),
            pendingDeletionPlace(owner: "account-b", name: "B")
        ])
        service.restorePendingReviewCandidates([
            pendingDeletionReview(owner: nil, name: "Legacy"),
            pendingDeletionReview(owner: "account-b", name: "B")
        ])
        let tokenA = try XCTUnwrap(service.restorationToken(consumingOwner: "account-a"))
        let consumedByAPlaces = service.consumePendingPlaces(ownerSubject: "account-a")
        let consumedByAReviews = service.consumePendingReviewCandidates(ownerSubject: "account-a")
        XCTAssertEqual(consumedByAPlaces.map(\.name), ["Legacy"])
        XCTAssertEqual(consumedByAReviews.map(\.candidateName), ["Legacy"])
        try service.purgeAccountDeletionItems(belongingTo: "account-a")
        service.restorePendingPlaces(consumedByAPlaces, restorationToken: tokenA)
        service.restorePendingReviewCandidates(consumedByAReviews, restorationToken: tokenA)
        XCTAssertTrue(service.consumePendingPlaces(ownerSubject: "account-a").isEmpty)
        XCTAssertTrue(service.consumePendingReviewCandidates(ownerSubject: "account-a").isEmpty)
        XCTAssertEqual(service.consumePendingPlaces(ownerSubject: "account-b").map(\.name), ["B"])
        XCTAssertEqual(service.consumePendingReviewCandidates(ownerSubject: "account-b").map(\.candidateName), ["B"])

        service.restorePendingPlaces([pendingDeletionPlace(owner: nil, name: "Later")])
        service.restorePendingReviewCandidates([pendingDeletionReview(owner: nil, name: "Later")])
        let tokenB = try XCTUnwrap(service.restorationToken(consumingOwner: "account-b"))
        let consumedByBPlaces = service.consumePendingPlaces(ownerSubject: "account-b")
        let consumedByBReviews = service.consumePendingReviewCandidates(ownerSubject: "account-b")
        try service.purgeAccountDeletionItems(belongingTo: "account-a")
        service.restorePendingPlaces(consumedByBPlaces, restorationToken: tokenB)
        service.restorePendingReviewCandidates(consumedByBReviews, restorationToken: tokenB)
        XCTAssertEqual(service.consumePendingPlaces(ownerSubject: "account-b").map(\.name), ["Later"])
        XCTAssertEqual(service.consumePendingReviewCandidates(ownerSubject: "account-b").map(\.candidateName), ["Later"])
    }

    /// P1 4365825794: unreadable queues must not block remote DELETE. Mark them
    /// on the intent; once readable, purge every ownerless row in those files
    /// and keep B. Receipt stays if the file is still unreadable.
    @MainActor
    func testUnreadableQueueSnapshotDeletesRemotelyAndPurgesOwnerlessWhenReadable() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = PrivyAuthService.shared
        let previousAuth = auth.authState
        defer { auth.authState = previousAuth }
        auth.authState = .authenticated(userId: "account-a")
        let vault = SaveLocalVaultService(overrideVaultURL: directory.appendingPathComponent("vault.json"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let queue = PendingPlaceImportService(overrideContainerURL: directory)
        let places: [PendingSharedPlace] = [
            pendingDeletionPlace(owner: "account-a", name: "A"),
            pendingDeletionPlace(owner: "account-b", name: "B"),
            pendingDeletionPlace(owner: nil, name: "Legacy")
        ]
        let reviews: [PendingReviewCandidate] = [
            pendingDeletionReview(owner: "account-a", name: "A"),
            pendingDeletionReview(owner: "account-b", name: "B"),
            pendingDeletionReview(owner: nil, name: "Legacy")
        ]
        queue.restorePendingPlaces(places)
        queue.restorePendingReviewCandidates(reviews)
        let placeURL = directory.appendingPathComponent(SAVEProductionConfig.pendingPlacesFileName)
        let reviewURL = directory.appendingPathComponent(SAVEProductionConfig.pendingReviewCandidatesFileName)
        try Data("broken-json".utf8).write(to: placeURL)
        try Data("broken-json".utf8).write(to: reviewURL)
        let snapshot = try queue.ownerlessQueueSnapshotForAccountDeletion()
        XCTAssertTrue(snapshot.ownerlessItemKeys.isEmpty)
        XCTAssertEqual(
            snapshot.unreadableFileNames,
            [
                SAVEProductionConfig.pendingPlacesFileName,
                SAVEProductionConfig.pendingReviewCandidatesFileName
            ]
        )
        var requests = 0
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService {
                requests += 1
                try JSONEncoder().encode(places).write(to: placeURL, options: .atomic)
                try JSONEncoder().encode(reviews).write(to: reviewURL, options: .atomic)
            },
            avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
            saveLocalVaultService: vault,
            pendingPlaceImportService: queue,
            accountReferenceStore: InMemoryAccountReferenceStore(),
            currentUserIDProvider: { "account-a" }, reviewerDemoProvider: { false }
        )
        let deleted = await model.deleteAccount()
        XCTAssertTrue(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertNil(try vault.pendingAccountDeletionIntent())
        let remainingPlaces = queue.consumePendingPlaces(ownerSubject: "account-a")
            + queue.consumePendingPlaces(ownerSubject: "account-b")
        XCTAssertEqual(remainingPlaces.map(\.name), ["B"])
        XCTAssertFalse(remainingPlaces.contains { $0.name == "Legacy" || $0.ownerSubject == "account-a" })
        let remainingReviews = queue.consumePendingReviewCandidates(ownerSubject: "account-a")
            + queue.consumePendingReviewCandidates(ownerSubject: "account-b")
        XCTAssertEqual(remainingReviews.map(\.candidateName), ["B"])
        XCTAssertFalse(remainingReviews.contains { $0.candidateName == "Legacy" || $0.ownerSubject == "account-a" })
    }

    @MainActor
    private func pendingDeletionPlace(owner: String?, name: String) -> PendingSharedPlace {
        PendingSharedPlace(ownerSubject: owner, name: name, address: "Fixture address", category: "cafe",
            latitude: 25, longitude: 121, dishes: [], priceRange: nil,
            sourceURL: "https://example.test/fixture", sourceText: "Private clue", savedAt: Date())
    }

    @MainActor
    private func pendingDeletionReview(owner: String?, name: String) -> PendingReviewCandidate {
        PendingReviewCandidate(ownerSubject: owner, candidateName: name, address: "", category: "other",
            sourceURL: "https://example.test/fixture", sourceText: "Private clue", evidence: [],
            confidence: 0, missingInfo: ["Address"], savedAt: Date())
    }

    @MainActor
    private func deletionModel(
        vault: SaveLocalVaultService,
        currentOwner: @escaping () -> String?,
        accountReferenceStore: AccountReferenceStoring = InMemoryAccountReferenceStore(),
        delete: @escaping @MainActor () async throws -> Void
    ) -> ProfileViewModel {
        ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService(action: delete),
            avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
            saveLocalVaultService: vault,
            pendingPlaceImportService: PendingPlaceImportService(overrideContainerURL: directory),
            accountReferenceStore: accountReferenceStore,
            currentUserIDProvider: currentOwner, reviewerDemoProvider: { false }
        )
    }

    @MainActor
    func testAccountChangeAfterPhotoPersistenceDoesNotPublishOldAccountState() async {
        var currentUserID = "account-a"
        let store = ProfileAvatarStore(baseDirectory: directory)
        let model = ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            avatarStore: store,
            updateProfileRemotely: { _ in currentUserID = "account-b" },
            currentUserIDProvider: { currentUserID },
            reviewerDemoProvider: { false }
        )
        model.profile = profile(named: "Original")

        let saved = await model.updateProfile(displayName: "Changed", avatarData: avatarData())

        XCTAssertFalse(saved)
        XCTAssertEqual(model.profile.id, UserProfile.empty.id)
        XCTAssertNil(model.localAvatarData)
        XCTAssertNotNil(store.load(for: "account-a"))
        XCTAssertNil(store.load(for: "account-b"))
    }

    @MainActor
    private func makeProfileViewModel(
        avatarStore: ProfileAvatarStore,
        updateProfileRemotely: @escaping (UserProfile) async throws -> Void
    ) -> ProfileViewModel {
        ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            avatarStore: avatarStore,
            updateProfileRemotely: updateProfileRemotely,
            currentUserIDProvider: { "account-a" },
            reviewerDemoProvider: { false }
        )
    }

    private func profile(named displayName: String) -> UserProfile {
        UserProfile(
            id: "account-a",
            displayName: displayName,
            email: nil,
            avatarUrl: nil,
            savedCount: 0,
            visitedCount: 0,
            citiesCount: 0,
            isPremium: false,
            collections: [],
            createdAt: Date()
        )
    }

    private func avatarData() -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 1)!
    }
}

private enum ProfileUpdateTestError: LocalizedError {
    case offline

    var errorDescription: String? { "Offline" }
}

private final class FailingAvatarRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws { throw ProfileUpdateTestError.offline }
}

private struct ClosureAccountDeletionService: AccountDeletionProviding {
    let action: @MainActor () async throws -> Void
    func deleteAccount() async throws { try await action() }
}

private struct StubAccountDeletionService: AccountDeletionProviding {
    func deleteAccount() async throws {}
}

@MainActor
final class SharedRestaurantRatingsTests: XCTestCase {
    func testListsEverySharedRatingAndWithdrawsOnlySelectedRating() async {
        let shared = (0..<8).map { _ in OwnRestaurantRating(place_id: UUID(), stars: 4.5, shared: true) }
        let privateRating = OwnRestaurantRating(place_id: UUID(), stars: 3, shared: false)
        var withdrawn: [UUID] = []
        let model = SharedRestaurantRatingsViewModel(
            fetch: { shared + [privateRating] },
            withdraw: { withdrawn.append($0) },
            currentSession: { 1 }
        )
        await model.load()
        XCTAssertEqual(model.ratings.map(\.place_id), shared.map(\.place_id),
                       "Owner shares must not depend on local place count or visibility.")
        await model.stopSharing(shared[6].place_id)
        XCTAssertEqual(withdrawn, [shared[6].place_id])
        XCTAssertEqual(model.ratings.count, 7)
        XCTAssertFalse(model.ratings.contains { $0.place_id == shared[6].place_id })
    }

    func testFailedWithdrawalRetainsRatingForRetry() async {
        let rating = OwnRestaurantRating(place_id: UUID(), stars: 4, shared: true)
        var attempts = 0
        let model = SharedRestaurantRatingsViewModel(fetch: { [rating] }, withdraw: { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
        }, currentSession: { 1 })
        await model.load()
        await model.stopSharing(rating.place_id)
        XCTAssertTrue(model.hasError)
        XCTAssertEqual(model.ratings.count, 1)
        XCTAssertNil(model.withdrawingID)
        await model.stopSharing(rating.place_id)
        XCTAssertFalse(model.hasError)
        XCTAssertTrue(model.ratings.isEmpty)
    }

    func testSessionChangeDiscardsFetchAndBlocksStaleWithdrawal() async {
        let rating = OwnRestaurantRating(place_id: UUID(), stars: 4, shared: true)
        var session: Int? = 1
        var calls = 0
        let model = SharedRestaurantRatingsViewModel(fetch: {
            session = 2
            return [rating]
        }, withdraw: { _ in calls += 1 }, currentSession: { session })
        await model.load()
        XCTAssertTrue(model.ratings.isEmpty)
        await model.stopSharing(rating.place_id)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(model.hasError)
    }

    func testLogoutAfterLoadingCannotWithdrawWithNewSession() async {
        let rating = OwnRestaurantRating(place_id: UUID(), stars: 4, shared: true)
        var session: Int? = 1
        var calls = 0
        let model = SharedRestaurantRatingsViewModel(fetch: { [rating] },
            withdraw: { _ in calls += 1 }, currentSession: { session })
        await model.load()
        session = nil
        await model.stopSharing(rating.place_id)
        XCTAssertEqual(calls, 0)
        model.invalidate()
        XCTAssertTrue(model.ratings.isEmpty)
    }

    func testLateWithdrawalFailureCannotPopulateAnotherSession() async {
        let rating = OwnRestaurantRating(place_id: UUID(), stars: 4, shared: true)
        var session: Int? = 1
        let model = SharedRestaurantRatingsViewModel(fetch: { [rating] }, withdraw: { _ in
            session = 2
            throw URLError(.notConnectedToInternet)
        }, currentSession: { session })
        await model.load()
        await model.stopSharing(rating.place_id)
        XCTAssertTrue(model.ratings.isEmpty)
        XCTAssertFalse(model.hasError)
        XCTAssertNil(model.withdrawingID)
    }

    func testDismissalDiscardsPendingLoadAndAnonymousSessionDoesNotFetch() async {
        var model: SharedRestaurantRatingsViewModel!
        model = SharedRestaurantRatingsViewModel(fetch: {
            model.invalidate()
            return [OwnRestaurantRating(place_id: UUID(), stars: 4, shared: true)]
        }, currentSession: { 1 })
        await model.load()
        XCTAssertTrue(model.ratings.isEmpty)
        var calls = 0
        let anonymous = SharedRestaurantRatingsViewModel(fetch: { calls += 1; return [] }, currentSession: { nil })
        await anonymous.load()
        XCTAssertEqual(calls, 0)
    }
}
