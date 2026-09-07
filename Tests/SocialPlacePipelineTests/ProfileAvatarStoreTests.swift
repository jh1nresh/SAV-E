import Foundation
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
}
