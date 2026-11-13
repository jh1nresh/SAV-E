import XCTest
import UIKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityChineseCaptureTests: XCTestCase {
    func testPhotoReaderPreservesSimplifiedChineseNameAddressAndBranch() throws {
        let text = try SaveCapturePhotoText.recognize(imageData(
            "街角咖啡 静安寺店\n上海市静安区愚园路 18 号\n静安寺站 2 号口"))
        attach(text)
        XCTAssertTrue(text.contains("街角咖啡"))
        XCTAssertTrue(text.contains("静安寺"))
        XCTAssertTrue(text.contains("愚园路"))
        XCTAssertTrue(text.contains("18"))
        XCTAssertTrue(text.components(separatedBy: .newlines).contains {
            $0.contains("街角咖啡") && $0.contains("静安寺店")
        }, "The venue line must preserve the branch; the station line alone is insufficient")
        let stems = SocialLinkReviewCandidateService(captionVenueExtractor: nil)
            .reviewCandidatesOrSourceOnly(fromEvidenceText: text, sourceURL: "")
        let stem = try XCTUnwrap(stems.first { $0.candidateName.contains("街角咖啡") })
        XCTAssertTrue(stem.candidateName.contains("静安寺"))
        XCTAssertTrue(stem.address.contains("愚园路"))
        XCTAssertNil(stem.latitude); XCTAssertNil(stem.longitude)
    }

    func testPhotoReaderPreservesTraditionalChineseNameAndAddress() throws {
        let text = try SaveCapturePhotoText.recognize(imageData(
            "弄堂生煎 南昌路店\n上海市徐匯區南昌路 18 號\n陝西南路站 3 號口"))
        attach(text)
        XCTAssertTrue(text.contains("弄堂生煎"))
        XCTAssertTrue(text.contains("南昌路"))
        XCTAssertTrue(text.contains("18"))
        XCTAssertTrue(text.components(separatedBy: .newlines).contains {
            $0.contains("弄堂生煎") && $0.contains("南昌路店")
        }, "The branch must survive in the venue line, not just the address")
    }

    func testChineseCaptionKeepsBranchAndAddressWithoutInventingAMapStamp() throws {
        let parser = SocialLinkReviewCandidateService(captionVenueExtractor: nil)
        let source = "https://www.xiaohongshu.com/explore/aaaaaaaaaaaaaaaaaaaaaaaa"
        let candidates = parser.reviewCandidatesOrSourceOnly(fromEvidenceText:
            "📍街角咖啡（静安寺店）\n地址：上海市静安区愚园路18号\n地铁：静安寺站2号口", sourceURL: source)
        XCTAssertEqual(candidates.count, 1)
        let stem = try XCTUnwrap(candidates.first)
        XCTAssertTrue(stem.candidateName.contains("街角咖啡"))
        XCTAssertTrue(stem.candidateName.contains("静安寺"))
        XCTAssertTrue(stem.address.contains("愚园路"))
        XCTAssertNil(stem.latitude); XCTAssertNil(stem.longitude)
        XCTAssertEqual(stem.sourceURL, source)
        let review = PlaceReviewCandidate(id: UUID(), captureId: nil, name: stem.candidateName,
            address: stem.address, city: nil, latitude: stem.latitude, longitude: stem.longitude,
            evidence: stem.evidence, confidence: stem.confidence, missingInfo: stem.missingInfo,
            status: "review", createdAt: stem.savedAt)
        XCTAssertFalse(review.hasSavableLocation)
        XCTAssertFalse(SavePlaceActionResolution(candidate: review).confirmsMapStamp)
    }

    func testUnreadShortLinkRemainsASourceClueWithoutAnInventedVenue() throws {
        let parser = SocialLinkReviewCandidateService(captionVenueExtractor: nil)
        let source = "https://xhslink.com/a/synthetic-clue"
        let candidates = parser.reviewCandidatesOrSourceOnly(fromEvidenceText: source, sourceURL: source)
        XCTAssertEqual(candidates.count, 1)
        let clue = try XCTUnwrap(candidates.first)
        XCTAssertTrue(clue.isSourceOnly)
        XCTAssertNil(clue.latitude); XCTAssertNil(clue.longitude)
        XCTAssertEqual(clue.sourceURL, source)
        XCTAssertFalse(clue.candidateName.contains("街角咖啡"))
    }

    private func imageData(_ text: String) throws -> Data {
        // Synthetic OCR fixture, no photograph or real venue claim.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 600), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1500, height: 600))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 30
            (text as NSString).draw(in: CGRect(x: 60, y: 80, width: 1380, height: 460), withAttributes: [
                .font: UIFont.systemFont(ofSize: 62, weight: .medium),
                .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
        }
        return try XCTUnwrap(image.pngData())
    }

    private func attach(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "actual-local-Vision-output"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
