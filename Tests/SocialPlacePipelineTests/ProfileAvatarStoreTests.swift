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
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Legacy private clue"))
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "A clue", ownerSubject: "account-a"))
        let before = try Data(contentsOf: url)
        var requests = 0
        let model = deletionModel(vault: vault, currentOwner: { "account-a" }) {
            requests += 1
            throw ProfileUpdateTestError.offline
        }
        let deleted = await model.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertTrue(model.errorMessage?.contains("Offline") == true)
        XCTAssertTrue(try vault.recentRecords(belongingTo: nil).isEmpty)
        XCTAssertTrue(try vault.recentRecords(belongingTo: "account-a").isEmpty)
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .awaitingRemoteResult)
        XCTAssertFalse(model.isDeletingAccount)
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
        defer { auth.authState = oldAuth }
        let url = directory.appendingPathComponent("vault.json")
        let vault = SaveLocalVaultService(overrideVaultURL: url)
        let b = SaveMemoryRecord(state: .sourceOnly, title: "B clue", ownerSubject: "account-b")
        try vault.append(SaveMemoryRecord(state: .sourceOnly, title: "Old legacy"))
        try vault.append(b)
        let prepared = try vault.prepareAccountDeletion(belongingTo: "account-a")
        _ = try vault.recordRemoteAccountDeletionSuccess(intentID: prepared.id)
        // A fresh VM must recover using disk, without a usable A session.
        auth.authState = .authenticated(userId: "account-b")
        var requests = 0
        let fresh = deletionModel(vault: SaveLocalVaultService(overrideVaultURL: url), currentOwner: { "account-b" }) {
            requests += 1
        }
        let result = await fresh.deleteAccount()
        XCTAssertFalse(result, "A cleanup must not claim B was deleted")
        XCTAssertEqual(fresh.errorMessage, "Previous account’s local cleanup is complete. Retry to delete this account.")
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(auth.currentUserId, "account-b")
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
        XCTAssertEqual(try Data(contentsOf: url), before, "Remote failure retains physical data")
        XCTAssertEqual(try vault.pendingAccountDeletionIntent()?.remoteOutcome, .awaitingRemoteResult)
        // The lease ends with the request. The explicitly authorized local scope
        // is recoverable after failure, without sending a B deletion or claiming success.
        await fresh.loadProfile()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(fresh.errorMessage?.contains("remote account deletion result could not be confirmed") == true)
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

    @MainActor
    private func deletionModel(
        vault: SaveLocalVaultService,
        currentOwner: @escaping () -> String?,
        delete: @escaping @MainActor () async throws -> Void
    ) -> ProfileViewModel {
        ProfileViewModel(
            supabaseService: SupabaseService(apiBaseURL: nil),
            accountDeletionService: ClosureAccountDeletionService(action: delete),
            avatarStore: ProfileAvatarStore(baseDirectory: directory.appendingPathComponent("avatars")),
            saveLocalVaultService: vault,
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
