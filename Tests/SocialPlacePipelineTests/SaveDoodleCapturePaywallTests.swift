import XCTest
@testable import SAVE

/// Doodle v1 Capture + paywall visual lock. Logic, product IDs, and the
/// 50-place copy stay; AI / Plan / sticker-pack benefits stay off the wall.
final class SaveDoodleCapturePaywallTests: XCTestCase {
    func testCaptureSheetUsesDoodleTokensAndKeepsAnalyzePipeline() throws {
        let capture = try source(at: "SAV-E/Views/Capture/SaveCaptureFlowView.swift")
        XCTAssertTrue(capture.contains("Save a place"))
        XCTAssertTrue(capture.contains("存一個地方"))
        XCTAssertTrue(capture.contains("SaveDisplayTitle"))
        XCTAssertTrue(capture.contains("pointSize: 28"))
        XCTAssertTrue(capture.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(capture.contains("SaveAtlasPalette.paper"))
        XCTAssertTrue(capture.contains("presentationDetents([.medium, .large], selection: $detent)"))
        XCTAssertFalse(capture.contains("SaveDottedBackground"))
        XCTAssertTrue(capture.contains("capture.input"))
        XCTAssertTrue(capture.contains("capture.paste"))
        XCTAssertTrue(capture.contains("capture.analyze"))
        XCTAssertTrue(capture.contains("capture.importGoogleTakeout"))
        XCTAssertTrue(capture.contains("capture.keyboardDone"))
        XCTAssertTrue(capture.contains("capture.flow"))
        XCTAssertTrue(capture.contains("Close capture"))
        XCTAssertTrue(capture.contains("Saved \\(count) / 50"))
        XCTAssertTrue(capture.contains("已存 \\(count) / 50"))
        XCTAssertFalse(capture.contains("SaveTileTown"))
        XCTAssertFalse(capture.contains("SavePixel"))
        XCTAssertFalse(capture.contains("Find the place"))
        XCTAssertFalse(capture.contains("Save a place clue"))
    }

    func testPaywallIsFullScreenDoodleModalWithOneBenefit() throws {
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        XCTAssertTrue(paywall.contains("paywall.root"))
        XCTAssertTrue(paywall.contains("paywall.close"))
        XCTAssertTrue(paywall.contains("paywall.restore"))
        XCTAssertTrue(paywall.contains("paywall.terms"))
        XCTAssertTrue(paywall.contains("paywall.privacy"))
        XCTAssertTrue(paywall.contains("paywall.continue"))
        XCTAssertTrue(paywall.contains("SAVEProAccessPolicy.ProductID.annual"))
        XCTAssertTrue(paywall.contains("SAVEProAccessPolicy.ProductID.monthly"))
        XCTAssertTrue(paywall.contains("Save every place you love"))
        XCTAssertTrue(paywall.contains("想去的地方，全部存下"))
        XCTAssertTrue(paywall.contains("Unlimited saved places"))
        XCTAssertTrue(paywall.contains("收藏地點不設限"))
        XCTAssertTrue(paywall.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(paywall.contains("已存 50 個地點，繼續存下去"))
        XCTAssertTrue(paywall.contains("SaveDisplayTitle"))
        XCTAssertTrue(paywall.contains("pointSize: 34"))
        XCTAssertTrue(paywall.contains("frame(height: 200)"))
        XCTAssertTrue(paywall.contains("presentationDetents([.large])"))
        XCTAssertTrue(paywall.contains("presentationDragIndicator(.hidden)"))
        XCTAssertTrue(paywall.contains("SaveAtlasPalette.coral"))
        XCTAssertFalse(paywall.contains("You've used this month's AI assists"))
        XCTAssertFalse(paywall.contains("More AI, same private map"))
        XCTAssertFalse(paywall.contains("Counts as an AI assist"))
        XCTAssertFalse(paywall.contains("Plan trips"))
        XCTAssertFalse(paywall.contains("sticker pack"))
        XCTAssertFalse(paywall.contains("Bonus sticker"))
        XCTAssertFalse(paywall.contains("Always free"))
        XCTAssertFalse(paywall.contains("SaveAtlasPalette.mint"))
        XCTAssertFalse(paywall.contains("SaveAtlasPalette.lavender"))
        XCTAssertFalse(paywall.contains("SaveAtlasPalette.honey"))
        XCTAssertFalse(paywall.contains("SaveTileTown"))
        XCTAssertFalse(paywall.contains("SavePixel"))
        XCTAssertFalse(paywall.contains("TabView"))
    }

    func testProductIdentifiersStayOnTheLegacyWanderlyIDs() {
        XCTAssertEqual(SAVEProAccessPolicy.ProductID.annual, "com.wanderly.app.pro.annual")
        XCTAssertEqual(SAVEProAccessPolicy.ProductID.monthly, "com.wanderly.app.pro.monthly")
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
