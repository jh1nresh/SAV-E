import XCTest
@testable import SAVE

#if DEBUG
@MainActor
final class DebugLegacyMigratorTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testCopiesOnlyRecordsMissingFromCurrent() throws {
        let legacy = data(#"[{"id":"a","name":"Old Cafe"},{"id":"b","name":"Kept"},{"id":"c","name":"New One"}]"#)
        let current = data(#"[{"id":"b","name":"Kept"}]"#)

        let pending = try DebugLegacyMigrator.recordsToMigrate(legacy: legacy, current: current)

        XCTAssertEqual(pending.map { $0["id"] as? String }, ["a", "c"])
    }

    func testRerunAfterFullCopyMovesNothing() throws {
        let legacy = data(#"[{"id":"a"},{"id":"b"}]"#)
        let current = data(#"[{"id":"a"},{"id":"b"},{"id":"post-rebuild"}]"#)

        XCTAssertTrue(try DebugLegacyMigrator.recordsToMigrate(legacy: legacy, current: current).isEmpty)
    }

    func testRecordsWithoutUsableIdNeverMigrate() throws {
        // Without an id the run cannot be idempotent — a second pass would
        // duplicate the record — so these are skipped, not guessed at.
        let legacy = data(#"[{"name":"no id"},{"id":"","name":"empty id"},{"id":42,"name":"numeric id"},{"id":"ok"}]"#)
        let current = data("[]")

        let pending = try DebugLegacyMigrator.recordsToMigrate(legacy: legacy, current: current)

        XCTAssertEqual(pending.map { $0["id"] as? String }, ["ok"])
    }

    func testRejectsNonArrayPayloadInsteadOfMigratingGarbage() {
        XCTAssertThrowsError(try DebugLegacyMigrator.recordsToMigrate(
            legacy: data(#"{"error":"Missing bearer token"}"#),
            current: data("[]")
        ))
    }

    func testCountsRecords() throws {
        XCTAssertEqual(try DebugLegacyMigrator.recordCount(data(#"[{"id":"a"},{"id":"b"}]"#)), 2)
    }
}
#endif
