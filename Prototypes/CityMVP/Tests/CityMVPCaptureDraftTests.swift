import XCTest
import Foundation
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPCaptureDraftTests: XCTestCase {
    private func withDocuments(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-draft-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testValidDraftPersistsAcrossStoreInstancesWithoutBecomingAPlace() throws {
        try withDocuments { documents in
            let first = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertNil(first.failure); XCTAssertEqual(first.text, "")
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.fileURL).path))
            let clue = "想去這家咖啡\nhttps://example.com/public-clue"
            XCTAssertTrue(first.update(clue))
            let second = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertEqual(second.text, clue); XCTAssertNil(second.failure)
            let data = try Data(contentsOf: XCTUnwrap(second.fileURL))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), Set(["version", "text"]))
            XCTAssertEqual(payload["version"] as? Int, 1)
        }
    }

    func testCompletedImportEmptyBindingClearsStoredDraft() throws {
        try withDocuments { documents in
            let store = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertTrue(store.update("an unfinished clue"))
            XCTAssertTrue(store.update("")) // ContentView.onComplete clears this binding.
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL).path))
            let reloaded = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertEqual(reloaded.text, ""); XCTAssertNil(reloaded.failure)
            XCTAssertTrue(reloaded.update(""), "Clearing an already empty store is harmless")
        }
    }

    func testOversizedEditPreservesPreviousDiskDraftAndReportsUnsavedMemory() throws {
        try withDocuments { documents in
            let store = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertTrue(store.update("last durable clue"))
            let file = try XCTUnwrap(store.fileURL), original = try Data(contentsOf: file)
            let oversized = String(repeating: "a", count: CityMVPCaptureDraftStore.maximumBytes + 1)
            XCTAssertFalse(store.update(oversized)); XCTAssertEqual(store.failure, .oversized)
            XCTAssertEqual(store.text, oversized)
            XCTAssertEqual(try Data(contentsOf: file), original)
            // JSON escaping can exceed the encoded limit even when UTF-8 input fits.
            XCTAssertFalse(store.update(String(repeating: "\n", count: CityMVPCaptureDraftStore.maximumBytes / 2)))
            XCTAssertEqual(try Data(contentsOf: file), original)
            XCTAssertEqual(CityMVPCaptureDraftStore(documentsDirectory: documents).text, "last durable clue")
            XCTAssertTrue(store.update("shortened clue")); XCTAssertNil(store.failure)
        }
    }

    func testCorruptUnsupportedAndOversizedFilesAreNotResetOnLoadOrEmptyBinding() throws {
        try withDocuments { documents in
            let seed = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertTrue(seed.update("valid"))
            let file = try XCTUnwrap(seed.fileURL)
            for invalid in [Data("{not json".utf8), Data("{\"version\":2,\"text\":\"future\"}".utf8),
                            Data(repeating: 32, count: CityMVPCaptureDraftStore.maximumBytes + 1)] {
                try invalid.write(to: file, options: [.atomic, .completeFileProtection])
                let store = CityMVPCaptureDraftStore(documentsDirectory: documents)
                XCTAssertEqual(store.failure, .unreadable); XCTAssertEqual(store.text, "")
                XCTAssertFalse(store.update(""))
                store.dismissFailure()
                XCTAssertEqual(try Data(contentsOf: file), invalid)
                XCTAssertTrue(store.update("explicit new draft"))
                XCTAssertEqual(CityMVPCaptureDraftStore(documentsDirectory: documents).text, "explicit new draft")
            }
        }
    }

    func testPrototypeAndTestNamespacesStayInsideDocumentsAndDoNotCollide() throws {
        try withDocuments { documents in
            let ordinary = CityMVPCaptureDraftStore(documentsDirectory: documents)
            let first = CityMVPCaptureDraftStore(documentsDirectory: documents, storageID: "fixture-one")
            let other = CityMVPCaptureDraftStore(documentsDirectory: documents, storageID: "fixture-two")
            XCTAssertEqual(ordinary.fileURL, documents.appendingPathComponent("SavvyCityMVP/Capture/capture-draft-v1.json"))
            XCTAssertEqual(first.fileURL, documents.appendingPathComponent("SavvyCityMVP/Capture/test-fixture-one/capture-draft-v1.json"))
            XCTAssertTrue(ordinary.update("ordinary draft")); XCTAssertTrue(first.update("test draft"))
            XCTAssertEqual(other.text, "")
            XCTAssertEqual(CityMVPCaptureDraftStore(documentsDirectory: documents).text, "ordinary draft")
            let invalid = CityMVPCaptureDraftStore(documentsDirectory: documents, storageID: "../../outside")
            XCTAssertNil(invalid.fileURL); XCTAssertEqual(invalid.failure, .unreadable)
            XCTAssertFalse(invalid.update("must not escape"))
        }
    }

    func testUnavailableDirectoryReportsWriteFailureWithoutLosingInMemoryText() throws {
        try withDocuments { documents in
            // A file obstructs the store's own directory; no global permission changes.
            try Data("blocker".utf8).write(to: documents.appendingPathComponent("SavvyCityMVP"))
            let store = CityMVPCaptureDraftStore(documentsDirectory: documents)
            XCTAssertFalse(store.update("keep this unsaved edit"))
            XCTAssertEqual(store.failure, .writeFailed)
            XCTAssertEqual(store.text, "keep this unsaved edit")
        }
    }
}
