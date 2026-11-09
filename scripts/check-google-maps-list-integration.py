#!/usr/bin/env python3
"""Execute the actual share/app list mappings on macOS, without UIKit or a simulator.

Only unrelated category/HTML helpers are stubbed. Models and mapping/privacy/
explanation methods are extracted verbatim, following check-share-pending-identity.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
share = (ROOT / 'SAV-EShareExtension/ShareViewController.swift').read_text()
app = (ROOT / 'SAV-E/Services/SocialLinkReviewCandidateService.swift').read_text()


def section(source, start, end):
    return start + source.split(start, 1)[1].split(end, 1)[0]


models = section(share, 'private struct SocialPlaceEvidenceDiagnostic: Codable {', 'private struct ShareMemoryRecord: Codable {')
metadata = section(share, 'private struct ShareMetadata {', 'private let shareMetadataHTMLByteLimit')
share_methods = section(share, '    private func googleMapsListReviewCandidates(', '    private func socialReviewCandidate(')
share_methods += section(share, '    private func publicMetadataEvidence(', '    private func firstPlaceName(')
share_methods += section(share, '    private func candidateExplanation(', '    private func candidateSubtitle(')
app_method = section(app, '    func googleMapsListReviewCandidates(', '    /// Only a concrete text identity')
source = 'import Foundation\n' + models + metadata + '''
private final class AppHarness {
    private func category(from text: String) -> String { "other" }
''' + app_method + '''
}
private final class ShareHarness {
    private func fallbackCategory(from text: String) -> String { "other" }
    private func cleanHTMLText(_ text: String) -> String { text }
''' + share_methods + r'''
    func run() throws {
        let sourceURL = "https://www.google.com/maps/placelists/list/fixture-list-123"
        let places = (0..<32).map { i in
            GoogleMapsListPlaceCandidate(name: "Same name cafe", address: "\(i + 1) Test Street",
                latitude: 25 + Double(i) / 1_000, longitude: 121 + Double(i) / 1_000,
                evidence: ["Structured public entry"])
        }
        let list = GoogleMapsListAnalysis(title: "Public list", candidates: places, notice: nil)
        var metadata = ShareMetadata(resolvedURL: sourceURL, title: "PRIVATE OWNER",
            description: "PRIVATE NOTE", htmlText: "PRIVATE PROFILE", publicListAnalysis: list)
        let reviews = googleMapsListReviewCandidates(from: metadata, sourceURLString: sourceURL,
            sharedTitle: "PRIVATE OWNER", sharedText: "PRIVATE NOTE")
        precondition(reviews.count == 32)
        precondition(reviews[1].latitude == 25.001 && reviews[1].longitude == 121.001)
        precondition(reviews[1].address == "2 Test Street")
        precondition(reviews.allSatisfy { !$0.isSourceOnly && $0.reviewState == "map_match_ready" })
        let pasted = AppHarness().googleMapsListReviewCandidates(list, sourceURL: sourceURL)
        precondition(pasted.map(\.candidateName) == reviews.map(\.candidateName))
        precondition(pasted.map(\.latitude) == reviews.map(\.latitude))
        precondition(pasted.map(\.address) == reviews.map(\.address))
        precondition(pasted.map(\.sourceURL) == reviews.map(\.sourceURL))
        metadata.publicListAnalysis = GoogleMapsListAnalysis(title: "Public list", candidates: [],
            notice: "List not fully read: 32 of 501 entries readable.")
        precondition(googleMapsListReviewCandidates(from: metadata, sourceURLString: sourceURL,
            sharedTitle: "PRIVATE OWNER", sharedText: "Cafe PRIVATE NOTE").isEmpty)
        let clue = googleMapsListSourceOnlyReviewCandidate(from: metadata, sourceURLString: sourceURL,
            sharedTitle: "PRIVATE OWNER", sharedText: "PRIVATE NOTE")
        precondition(clue.isSourceOnly && clue.latitude == nil && clue.confidence == 0)
        precondition(candidateExplanation(clue).contains("32 of 501"))
        let appClue = AppHarness().googleMapsListReviewCandidates(metadata.publicListAnalysis!, sourceURL: sourceURL)
        precondition(appClue.count == 1 && appClue[0].isSourceOnly)
        let encoded = String(decoding: try JSONEncoder().encode(reviews + pasted + [clue] + appClue), as: UTF8.self)
        precondition(!encoded.contains("PRIVATE"), "Raw metadata leaked around the public list whitelist")
        print("PASS: actual share/app list mappings retain 32 entries and coordinates, exclude metadata/notes, and show incomplete-list notice")
    }
}
@main
struct Check {
    static func main() throws { try ShareHarness().run() }
}
'''
with tempfile.TemporaryDirectory(prefix='save-google-list-integration-') as directory:
    output = Path(directory)
    swift = output / 'Check.swift'
    swift.write_text(source)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library',
                    str(ROOT / 'SAV-EShared/SocialPlaceEvidence.swift'),
                    str(ROOT / 'SAV-EShared/GoogleMapsListPlaceExtractor.swift'),
                    str(swift), '-o', str(output / 'check')], check=True)
    subprocess.run([str(output / 'check')], check=True)
