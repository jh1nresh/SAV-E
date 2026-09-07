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
