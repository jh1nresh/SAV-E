import XCTest
import UIKit
@testable import SAVE

/// Doodle v1 Capture + paywall visual lock. Logic, product IDs, and the
/// purchase boundary stay; AI / itinerary / collectible extras stay off the wall.
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
        XCTAssertTrue(capture.contains("if isGoogleTakeoutPresented"))
        XCTAssertTrue(capture.contains("captureStack"))
        XCTAssertTrue(capture.contains("GoogleTakeoutImportView("))
        XCTAssertTrue(capture.contains("onClose: { isGoogleTakeoutPresented = false }"))
        XCTAssertTrue(capture.contains(".accessibilityIdentifier(\"capture.flow\")"))
        XCTAssertTrue(capture.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(capture.contains("ai.quotaExhausted"))
        XCTAssertTrue(capture.contains("isAIQuotaExhausted"))
        XCTAssertTrue(capture.contains("entitlements.decideAIAssist()"))
        XCTAssertTrue(capture.contains("await entitlements.refresh()"))
        XCTAssertTrue(capture.contains("canSubmitDraft"))
        XCTAssertTrue(capture.contains("draftLooksLikeLink"))
        XCTAssertTrue(capture.contains("SaveSourceHandle.looksLikeURL"))
        XCTAssertFalse(capture.contains("shouldPresentPaywall"))
        XCTAssertFalse(capture.contains("onOpenGoogleTakeout"))
        XCTAssertFalse(capture.contains(".fullScreenCover(isPresented: $isGoogleTakeoutPresented)"))
        XCTAssertFalse(capture.contains(".sheet(isPresented: $isGoogleTakeoutPresented)"))
        XCTAssertFalse(capture.contains(".navigationDestination(isPresented: $isGoogleTakeoutPresented)"))
        let takeout = try source(at: "SAV-E/Views/Import/GoogleTakeoutImportView.swift")
        XCTAssertTrue(takeout.contains(".accessibilityIdentifier(\"takeout.import.chooseFile\")"))
        XCTAssertTrue(takeout.contains(".accessibilityIdentifier(\"takeout.import.folder\")"))
        XCTAssertTrue(takeout.contains(".accessibilityIdentifier(\"takeout.import.root\")"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("takeout.import.chooseFile"))
        XCTAssertTrue(rail.contains("takeout.import.folder"))
        XCTAssertFalse(rail.contains("[\"takeout.import.root\"]"))
        XCTAssertTrue(capture.contains("\\(count) places saved"))
        XCTAssertTrue(capture.contains("已收藏 \\(count) 個地點"))
        XCTAssertFalse(capture.contains("existingPlaces.first"))
        XCTAssertFalse(capture.contains("min(existingPlaces.count, 50)"))
        XCTAssertFalse(capture.contains("SaveTileTown"))
        XCTAssertFalse(capture.contains("SavePixel"))
        XCTAssertFalse(capture.contains("Find the place"))
        XCTAssertFalse(capture.contains("Save a place clue"))
    }

    func testPaywallIsFullScreenDoodleModalWithOneBenefit() throws {
        let paywall = try source(at: "SAV-E/Views/Profile/SaveProPaywallView.swift")
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
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
        XCTAssertTrue(paywall.contains("Yearly"))
        XCTAssertTrue(paywall.contains("Monthly"))
        XCTAssertTrue(paywall.contains("Best value"))
        XCTAssertTrue(paywall.contains("Unlimited saved places"))
        XCTAssertTrue(paywall.contains("收藏地點不設限"))
        XCTAssertTrue(paywall.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(paywall.contains("已存 50 個地點，繼續存下去"))
        XCTAssertTrue(paywall.contains("paywall.savedNote"))
        XCTAssertTrue(paywall.contains("paywall.retry"))
        XCTAssertFalse(paywall.contains("paywall.retryLoad"))
        XCTAssertFalse(paywall.contains("ai.quotaExhausted"))
        XCTAssertTrue(paywall.contains("Upgrade to Savvy Pro"))
        XCTAssertTrue(paywall.contains("升級 Savvy Pro"))
        XCTAssertEqual(
            SaveProPaywallCopy.savedNote(for: .savedPlacesCap, english: true),
            "You've saved 50 places. Keep going."
        )
        XCTAssertEqual(
            SaveProPaywallCopy.savedNote(for: .savedPlacesCap, english: false),
            "已存 50 個地點，繼續存下去"
        )
        XCTAssertEqual(
            SaveProPaywallCopy.savedNote(for: .settings, english: true),
            "Upgrade to Savvy Pro"
        )
        XCTAssertEqual(
            SaveProPaywallCopy.savedNote(for: .settings, english: false),
            "升級 Savvy Pro"
        )
        XCTAssertFalse(paywall.contains("Keep saving the places you love."))
        XCTAssertFalse(paywall.contains("繼續收藏你喜歡的地方。"))
        XCTAssertTrue(paywall.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(paywall.contains("已存 50 個地點，繼續存下去"))
        XCTAssertTrue(paywall.contains("ScrollView"))
        XCTAssertTrue(paywall.contains("scrollBounceBehavior(.basedOnSize)"))
        XCTAssertTrue(paywall.contains("paywall.scroll"))
        XCTAssertFalse(paywall.contains("aiAssistExhausted"))
        XCTAssertFalse(paywall.contains("$6.99"))
        XCTAssertFalse(paywall.contains("$39.99"))
        XCTAssertFalse(paywall.contains("fallback:"))
        XCTAssertFalse(paywall.contains("fallbackOffers"))
        XCTAssertTrue(paywall.contains("SaveDisplayTitle"))
        XCTAssertTrue(paywall.contains("pointSize: 34"))
        XCTAssertTrue(paywall.contains("frame(height: 200)"))
        XCTAssertTrue(paywall.contains("SaveDoodleOfficialSticker"))
        XCTAssertTrue(paywall.contains("sticker(.temple"))
        XCTAssertTrue(paywall.contains("sticker(.lantern"))
        XCTAssertTrue(paywall.contains("sticker: .noodle"))
        XCTAssertTrue(paywall.contains("sticker: .coffee"))
        XCTAssertTrue(paywall.contains("accessibilityElement(children: .combine)"))
        XCTAssertTrue(paywall.contains("paywall.benefit.unlimited"))
        XCTAssertFalse(paywall.contains("takeoutbag.and.cup.and.straw"))
        XCTAssertFalse(paywall.contains("sticker(system:"))
        XCTAssertTrue(paywall.contains("frame(height: 52)"))
        XCTAssertTrue(paywall.contains("renewalDescription(for: id, products: products)"))
        XCTAssertTrue(paywall.contains("paywall.renewal.\\(id)"))
        XCTAssertTrue(paywall.contains("frame(minHeight: SaveLayout.rowMinHeight)"))
        XCTAssertTrue(paywall.contains("renewalDescription"))
        XCTAssertTrue(paywall.contains("Auto-renews every"))
        XCTAssertTrue(paywall.contains("Cancel anytime."))
        XCTAssertTrue(paywall.contains("自動續訂"))
        XCTAssertTrue(paywall.contains("可隨時取消"))
        XCTAssertTrue(paywall.contains("Pro isn't on sale yet"))
        XCTAssertTrue(paywall.contains("paywall.notForSale"))
        XCTAssertTrue(paywall.contains("paywall.unavailable"))
        XCTAssertTrue(paywall.contains("paywall.retry"))
        XCTAssertTrue(paywall.contains("Plans are unavailable right now."))
        XCTAssertTrue(profile.contains(".fullScreenCover(isPresented: $showProPaywall)"))
        XCTAssertTrue(profile.contains("SaveProPaywallView(trigger: .settings)"))
        XCTAssertFalse(profile.contains(".sheet(isPresented: $showProPaywall)"))
        XCTAssertFalse(paywall.contains("presentationDetents"))
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

        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("--uitest-show-paywall"))
        XCTAssertTrue(content.contains("--uitest-show-paywall-cap"))
        XCTAssertTrue(content.contains("hidesRootTabBarForPaywallUITest"))
        XCTAssertTrue(content.contains(".savedPlacesCap"))
        XCTAssertTrue(content.contains(".settings"))
        XCTAssertFalse(content.contains("aiAssistExhausted"))
        XCTAssertTrue(content.contains(".fullScreenCover(isPresented: .constant("))
        XCTAssertTrue(content.contains("Same outermost fullScreenCover as production Passport"))
        XCTAssertTrue(content.contains("showsRootTabBar"))
        XCTAssertTrue(content.contains("if showsRootTabBar"))

        let storeKit = try source(at: "SAV-E/Services/SaveStoreKitService.swift")
        XCTAssertTrue(storeKit.contains("Product.products(for: SAVEProAccessPolicy.ProductID.all)"))
        XCTAssertFalse(storeKit.contains("Products do not exist in App Store Connect yet"))
        let entitlement = try source(at: "SAV-E/Services/SaveEntitlementStore.swift")
        XCTAssertTrue(entitlement.contains("AI quota never opens the places paywall"))
        XCTAssertTrue(entitlement.contains("return false"))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Upgrade to Savvy Pro"))
        XCTAssertTrue(design.contains("You've saved 50 places. Keep going."))
        XCTAssertTrue(design.contains("never a hardcoded $6.99"))
        XCTAssertTrue(design.contains("ai.quotaExhausted"))

        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testDoodleCaptureParity"))
        XCTAssertTrue(rail.contains("func testAIQuotaExhaustedStaysOffThePaywall"))
        XCTAssertTrue(rail.contains("--uitest-ai-quota-exhausted"))
        XCTAssertTrue(rail.contains("ai.quotaExhausted"))
        XCTAssertTrue(rail.contains("func testPR295PaywallLargeTypeEvidence"))
        XCTAssertTrue(rail.contains("func testPR295SEEvidence"))
        XCTAssertTrue(rail.contains("pr295-paywall-light"))
        XCTAssertTrue(rail.contains("pr295-paywall-large-type-light"))
        XCTAssertTrue(rail.contains("pr295-paywall-se-light"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-face"))
        XCTAssertTrue(rail.contains("--uitest-location-allowed"))
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(parity.contains("--ignore-rects"))
        XCTAssertTrue(parity.contains("24,132,354,176;24,444,354,22;24,698,354,50"))
        XCTAssertTrue(parity.contains("${#extra_args[@]} -gt 0"))
        XCTAssertTrue(parity.contains("${#mask_args[@]} -gt 0"))
        XCTAssertFalse(parity.contains("0,432,402,104"))
        XCTAssertFalse(parity.contains("0,728,402,146"))
        XCTAssertFalse(parity.contains("24,548,354,44;48,610,306,24;24,662,354,64"))
        let visualParity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        XCTAssertTrue(visualParity.contains("--ignore-rects"))

        let targets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Prototypes/AtlasPostcard/Reference/ProductionTargets")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: targets.appendingPathComponent("paywall.png").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: targets.appendingPathComponent("paywall-dark.png").path)
        )
    }

    func testProductIdentifiersComeFromTheSharedPolicy() {
        XCTAssertFalse(SAVEProAccessPolicy.ProductID.annual.isEmpty)
        XCTAssertFalse(SAVEProAccessPolicy.ProductID.monthly.isEmpty)
        XCTAssertNotEqual(SAVEProAccessPolicy.ProductID.annual, SAVEProAccessPolicy.ProductID.monthly)
        XCTAssertEqual(
            SAVEProAccessPolicy.ProductID.all,
            [SAVEProAccessPolicy.ProductID.annual, SAVEProAccessPolicy.ProductID.monthly]
        )
        XCTAssertFalse(SAVEProAccessPolicy.purchasingIsAvailable)
    }

    func testPhotoTextRejectsInvalidImage() {
        XCTAssertThrowsError(try SaveCapturePhotoText.recognize(Data("not an image".utf8))) {
            XCTAssertTrue($0 is SaveCapturePhotoText.Failure)
        }
    }

    @MainActor
    func testPhotoTextReadsUserSelectedImageWithoutSavingAPlace() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 250))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 250))
            ("Grey Cafe Taipei" as NSString).draw(
                at: CGPoint(x: 50, y: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 60), .foregroundColor: UIColor.black]
            )
        }
        let text = try SaveCapturePhotoText.recognize(XCTUnwrap(image.pngData())).lowercased()
        for word in ["grey", "cafe", "taipei"] { XCTAssertTrue(text.contains(word), text) }
    }

    @MainActor
    func testPhotoWithoutTextDoesNotInventAClue() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        XCTAssertThrowsError(try SaveCapturePhotoText.recognize(XCTUnwrap(image.pngData()))) {
            guard case SaveCapturePhotoText.Failure.noText = $0 else {
                return XCTFail("Expected noText, got \($0)")
            }
        }
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
