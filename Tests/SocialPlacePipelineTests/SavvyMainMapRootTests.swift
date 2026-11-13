import Foundation
import XCTest
@testable import SAVE

final class SavvyMainMapRootTests: XCTestCase {
    func testAccountDirectoryIsStableAndDoesNotContainRawSubject() throws {
        let documents = URL(fileURLWithPath: "/synthetic-documents", isDirectory: true)
        let owner = "did:privy:owner-A/private details"
        let first = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: owner, documentsDirectory: documents))
        let second = SavvyMainMapNamespace.accountDirectory(ownerSubject: owner, documentsDirectory: documents)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent().path, "/synthetic-documents/Savvy/Accounts")
        XCTAssertEqual(first.lastPathComponent.count, 64)
        XCTAssertTrue(first.lastPathComponent.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertFalse(first.path.contains("privy"))
        XCTAssertFalse(first.path.contains("owner-A"))
        XCTAssertFalse(first.path.contains("private details"))
    }

    func testDifferentAccountsHaveDifferentDirectories() {
        let documents = URL(fileURLWithPath: "/synthetic-documents", isDirectory: true)
        XCTAssertNotEqual(
            SavvyMainMapNamespace.accountDirectory(ownerSubject: "owner-A", documentsDirectory: documents),
            SavvyMainMapNamespace.accountDirectory(ownerSubject: "owner-B", documentsDirectory: documents)
        )
    }

    func testMissingOwnerOrDocumentsCannotUseSharedFallbackDirectory() {
        let documents = URL(fileURLWithPath: "/synthetic-documents", isDirectory: true)
        for owner in ["", " \n\t"] {
            XCTAssertNil(SavvyMainMapNamespace.accountDirectory(ownerSubject: owner, documentsDirectory: documents))
        }
        XCTAssertNil(SavvyMainMapNamespace.accountDirectory(ownerSubject: "owner-A", documentsDirectory: nil))
        XCTAssertNil(SavvyMainMapNamespace.accountDirectory(
            ownerSubject: "owner-A", documentsDirectory: URL(string: "https://example.invalid/documents")
        ))
    }

    func testPathLikeOwnerRemainsOneHashedDirectoryComponent() throws {
        let documents = URL(fileURLWithPath: "/synthetic-documents", isDirectory: true)
        let directory = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(
            ownerSubject: "../../other-account/秘密", documentsDirectory: documents
        ))
        XCTAssertEqual(directory.pathComponents.count, documents.pathComponents.count + 3)
        XCTAssertFalse(directory.path.contains("other-account"))
        XCTAssertFalse(directory.path.contains("秘密"))
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "Accounts")
    }

    func testOnlyExactOwnerAndGenerationMatchDisplayedSession() {
        XCTAssertTrue(SavvyMainMapNamespace.matchesSession(
            ownerSubject: "A", sessionGeneration: 4, currentOwner: "A", currentGeneration: 4
        ))
        XCTAssertFalse(SavvyMainMapNamespace.matchesSession(
            ownerSubject: "A", sessionGeneration: 4, currentOwner: "B", currentGeneration: 4
        ))
        XCTAssertFalse(SavvyMainMapNamespace.matchesSession(
            ownerSubject: "A", sessionGeneration: 4, currentOwner: "A", currentGeneration: 5
        ))
        XCTAssertFalse(SavvyMainMapNamespace.matchesSession(
            ownerSubject: "A", sessionGeneration: 4, currentOwner: nil, currentGeneration: 4
        ))
        XCTAssertFalse(SavvyMainMapNamespace.matchesSession(
            ownerSubject: "", sessionGeneration: 4, currentOwner: "", currentGeneration: 4
        ))
    }

    func testPurgeRemovesOnlyExactOwnerAndIsIdempotent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: "A", documentsDirectory: root))
        let b = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: "B", documentsDirectory: root))
        for directory in [a, b] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("private fixture".utf8).write(to: directory.appendingPathComponent("sidecar.json"))
        }
        let legacy = root.appendingPathComponent("SavvyCityMVP", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.appendingPathComponent("sidecar.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertNoThrow(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testPurgeMissingNamespaceIsIdempotentButMissingDocumentsFails() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Savvy").path))
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(
            ownerSubject: "A", documentsDirectory: root.appendingPathComponent("missing-documents")
        )) {
            XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .documentsUnavailable)
        }
    }

    func testPurgeRejectsInvalidOwnerAndRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for owner in ["", " \n"] {
            XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: owner, documentsDirectory: root)) {
                XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .invalidOwner)
            }
        }
        for url in [nil, URL(string: "https://example.invalid/documents")] {
            XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: url)) {
                XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .documentsUnavailable)
            }
        }
        let file = root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: file)
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: file)) {
            XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .unsafeDirectory)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPurgeRejectsAccountSymlinkWithoutRemovingOtherOwner() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: "A", documentsDirectory: root))
        let b = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: "B", documentsDirectory: root))
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let marker = b.appendingPathComponent("sidecar.json")
        let contents = Data("B must survive".utf8)
        try contents.write(to: marker)
        try FileManager.default.createSymbolicLink(at: a, withDestinationURL: b)
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root)) {
            XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .unsafeDirectory)
        }
        XCTAssertEqual(try Data(contentsOf: marker), contents)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: a.path), b.path)
    }

    func testPurgeRejectsNamespaceAndDocumentsSymlinks() throws {
        let scratch = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let documents = scratch.appendingPathComponent("documents", isDirectory: true)
        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let marker = outside.appendingPathComponent("other-owner.json")
        try Data("other owner".utf8).write(to: marker)
        try FileManager.default.createSymbolicLink(at: documents.appendingPathComponent("Savvy"), withDestinationURL: outside)
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: documents)) {
            XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .unsafeDirectory)
        }
        let link = scratch.appendingPathComponent("linked-documents")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: documents)
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: link)) {
            XCTAssertEqual($0 as? SavvyMainMapNamespace.PurgeFailure, .unsafeDirectory)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testPurgeFailureCanRetryAfterObstructionIsRepaired() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = root.appendingPathComponent("Savvy", isDirectory: true)
        try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: true)
        let obstruction = namespace.appendingPathComponent("Accounts")
        try Data("blocked".utf8).write(to: obstruction)
        XCTAssertThrowsError(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: obstruction.path))
        try FileManager.default.removeItem(at: obstruction)
        let account = try XCTUnwrap(SavvyMainMapNamespace.accountDirectory(ownerSubject: "A", documentsDirectory: root))
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        XCTAssertNoThrow(try SavvyMainMapNamespace.purgeAccountSidecars(ownerSubject: "A", documentsDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: account.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savvy-sidecar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
