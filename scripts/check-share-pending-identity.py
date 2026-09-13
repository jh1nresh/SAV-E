#!/usr/bin/env python3
"""Run the actual extension Codable models and queue append functions on macOS.

Usage: python3 scripts/check-share-pending-identity.py
No simulator, application build, network, or copied model implementation is used.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "SAV-EShareExtension/ShareViewController.swift"


def between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def production_fixture(source: str) -> str:
    # Compile declarations verbatim, plus the exact coordinated decode/append/encode path.
    models = "private struct SocialPlaceEvidenceDiagnostic: Codable {" + between(
        source, "private struct SocialPlaceEvidenceDiagnostic: Codable {", "private struct ShareMemoryRecord: Codable {"
    )
    methods = "    private func appendPendingItems<Element: Codable>" + between(
        source, "    private func appendPendingItems<Element: Codable>", "    // MARK: - Helpers"
    )
    return "import Foundation\n" + models + "\nprivate final class QueueHarness {\nvar parseError: String?\n" + methods + r'''
    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "SharePendingIdentityFixture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    func run(at url: URL) throws {
        let id = UUID(uuidString: "AC53BFB7-C6D5-4DAC-9C3C-900D25D6870D")!
        let existing: [String: Any] = [
            "localVaultRecordID": id.uuidString,
            "candidateName": "Refined original", "address": "1 North Street", "category": "food",
            "latitude": 25.051, "longitude": 121.519,
            "sourceURL": "https://example.com/original", "sourceText": "Original caption",
            "evidence": ["Original refined location evidence"], "confidence": 0.8,
            "missingInfo": [], "savedAt": 1234, "isSourceOnly": false
        ]
        let legacy: [String: Any] = [
            "candidateName": "Legacy clue", "address": "", "category": "food",
            "sourceURL": "https://example.com/legacy", "evidence": [], "confidence": 0,
            "missingInfo": ["Exact place"], "savedAt": 1000, "isSourceOnly": true
        ]
        try JSONSerialization.data(withJSONObject: [existing, legacy]).write(to: url)
        let newShare = try JSONDecoder().decode(PendingReviewCandidate.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        for expectedCount in [3, 4] {
            try expect(appendPendingItems([newShare], to: url, as: PendingReviewCandidate.self), parseError ?? "Append failed")
            let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
            try expect(rows.count == expectedCount, "New shares must append without dropping old rows")
            try expect(rows[0]["localVaultRecordID"] as? String == id.uuidString, "Extension stripped pending retry identity")
            try expect(rows[0]["latitude"] as? Double == 25.051, "Existing coordinates changed")
            try expect(rows[0]["longitude"] as? Double == 121.519, "Existing coordinates changed")
            try expect(rows[0]["evidence"] as? [String] == ["Original refined location evidence"], "Existing evidence changed")
            try expect(rows.dropFirst().allSatisfy { $0["localVaultRecordID"] == nil }, "Legacy/new shares must not receive another candidate's identity")
        }
    }
}

let path = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    try QueueHarness().run(at: path)
    print("PASS: extension queue append retains retry UUID, coordinates, evidence, and legacy compatibility")
} catch {
    print("FAIL: \(error.localizedDescription)")
    exit(1)
}
'''


def main() -> None:
    source = SOURCE.read_text()
    with tempfile.TemporaryDirectory(prefix="save-share-pending-") as directory:
        root = Path(directory)
        swift = root / "fixture.swift"
        swift.write_text(production_fixture(source))
        subprocess.run(["swift", str(swift), str(root / "pending.json")], check=True, cwd=ROOT)


if __name__ == "__main__":
    main()
