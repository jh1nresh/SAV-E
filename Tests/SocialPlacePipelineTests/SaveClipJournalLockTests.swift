import XCTest

final class SaveClipJournalLockTests: XCTestCase {
    func testAppClipUsesDoodleJournalChromeAndKeepsShareLinks() throws {
        let clip = try source(at: "SAV-EClip/ClipContentView.swift")
        let theme = try source(at: "SAV-EClip/ClipDoodleTheme.swift")
        let clipPayload = try source(at: "SAV-EClip/SharedTripData.swift")
        let appPayload = try source(at: "SAV-E/Models/SharedTripData.swift")

        XCTAssertTrue(theme.contains("enum ClipJournalPalette"))
        XCTAssertTrue(theme.contains("enum ClipDisplayType"))
        XCTAssertTrue(theme.contains("struct ClipDoodlePin"))
        XCTAssertTrue(theme.contains("Iansui-SavvySubset.ttf (3.48 MB)"))
        XCTAssertTrue(theme.contains("static var wordmark"))
        XCTAssertFalse(theme.contains("SavvyLogo"))
        XCTAssertTrue(clip.contains("ClipJournalPalette"))
        XCTAssertTrue(clip.contains("ClipDoodlePin"))
        XCTAssertTrue(clip.contains("mapStyle(.standard)"))
        XCTAssertTrue(clip.contains("SharedPlaceData.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.isListLink(url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.resolve(from: url)"))
        XCTAssertTrue(clip.contains("func isPlaceLink"))
        XCTAssertTrue(clip.contains("clip.error.retry"))
        XCTAssertTrue(clip.contains("pendingFriendShareURL"))
        XCTAssertFalse(clip.contains("coming soon") || clip.contains("Coming Soon"))
        XCTAssertFalse(clip.contains("PLACE POSTCARD"))
        XCTAssertFalse(clip.contains("TRIP POSTCARD"))
        XCTAssertFalse(clip.contains("SHARED LIST PREVIEW"))
        XCTAssertFalse(clip.contains("OPENING SHARED MEMORY"))
        XCTAssertFalse(clip.contains("DELIVERED FOR REVIEW"))
        XCTAssertFalse(clip.contains("ClipScallopedRectangle"))
        XCTAssertFalse(clip.contains("ClipPostmark"))
        XCTAssertFalse(clip.contains("ClipAirmailDivider"))
        XCTAssertFalse(clip.contains("ClipAtlasPalette"))
        XCTAssertFalse(clip.contains("ClipAtlasType"))
        XCTAssertFalse(clip.contains("AsyncImage"))
        XCTAssertFalse(clip.contains("item.photoURLs"))
        XCTAssertFalse(clip.contains("mappin.circle.fill"))
        XCTAssertFalse(clip.contains("ClipJournalPalette.forest"))
        XCTAssertFalse(clip.contains("free 50") || clip.contains("Free 50"))
        XCTAssertFalse(clip.contains("save all") || clip.contains("Save all") || clip.contains("Save All"))
        XCTAssertFalse(clip.contains("ClipGooglePhoto"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("SAV-EClip/ClipGooglePhotoView.swift").path))
        XCTAssertFalse(clipPayload.contains("var photoAttribution"))
        XCTAssertFalse(clipPayload.contains("journalGooglePhoto"))
        XCTAssertFalse(appPayload.contains("var photoAttribution"))
        XCTAssertFalse(appPayload.contains("journalGooglePhoto"))
        XCTAssertTrue(appPayload.contains("isGooglePlacesPhotoURL"))
        XCTAssertTrue(try source(at: "SAV-EClip/Localizable.xcstrings").contains("clip.place.save"))
    }

    func testClipDoesNotShipMainCatalogOrIansuiSubset() {
        let project = try? String(
            contentsOf: repositoryRoot.appendingPathComponent("SAV-E.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertNotNil(project)
        XCTAssertFalse((project ?? "").contains("DisplayFont in SAVEClip Resources"))
        XCTAssertTrue((project ?? "").contains("Caveat-SemiBold.ttf in SAVEClip Resources"))
        XCTAssertTrue((project ?? "").contains("\"Caveat-SemiBold.ttf\""))
        let iansui = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/Iansui-SavvySubset.ttf")
        XCTAssertGreaterThan((try? iansui.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, 3_000_000)
        let caveat = repositoryRoot.appendingPathComponent("SAV-E/Resources/DisplayFont/Caveat-SemiBold.ttf")
        XCTAssertLessThan((try? caveat.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, 400_000)
    }

    func testClipTargetDeploymentTargetIsSeventeen() throws {
        let project = try source(at: "SAV-E.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 17.0;"))
        XCTAssertFalse(project.contains("com.apple.developer.nfc"))
        XCTAssertFalse(project.contains("NFCReaderUsageDescription"))
        let entitlements = try source(at: "SAV-EClip/SAV-EClip.entitlements")
        XCTAssertTrue(entitlements.contains("appclips:sav-e-app.vercel.app"))
        XCTAssertTrue(entitlements.contains("group.com.wanderly.app"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
