import Foundation

@main
struct SocialOCRFixtureCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureDir = root.appendingPathComponent("fixtures/social-ocr", isDirectory: true)
        let ocrText = try String(contentsOf: fixtureDir.appendingPathComponent("dyzrjnztgud-ocr.txt"), encoding: .utf8)
        let ocrLines = ocrText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let result = SocialOCRCandidateHeuristics.candidate(from: ocrLines) else {
            fail("expected OCR fallback candidate")
        }

        expect(result.name == "TULA COFFEE", "expected TULA COFFEE, got \(result.name)")
        expect(result.name != "台南爆漿巴斯克", "product-only line must not become candidate")
        expect(result.confidence >= 0.35 && result.confidence <= 0.5, "OCR confidence should remain low-medium")

        print("DYZrjnzTGuD")
        print("name=\(result.name)")
        print("address=")
        print("category=cafe")
        print("source=ocr_fallback")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
