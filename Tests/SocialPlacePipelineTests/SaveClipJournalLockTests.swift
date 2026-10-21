import XCTest

final class SaveClipJournalLockTests: XCTestCase {
    func testAppClipUsesDoodleJournalChromeAndKeepsShareLinks() throws {
        let clip = try source(at: "SAV-EClip/ClipContentView.swift")
        let theme = try source(at: "SAV-EClip/ClipDoodleTheme.swift")
        let photo = try source(at: "SAV-EClip/ClipGooglePhotoView.swift")
        let clipPayload = try source(at: "SAV-EClip/SharedTripData.swift")
        let appPayload = try source(at: "SAV-E/Models/SharedTripData.swift")

        XCTAssertTrue(theme.contains("enum ClipJournalPalette"))
        XCTAssertTrue(theme.contains("enum ClipDisplayType"))
        XCTAssertTrue(theme.contains("FFF9EB"))
        XCTAssertTrue(theme.contains("1E1C19"))
        XCTAssertTrue(theme.contains("F26B4A"))
        XCTAssertTrue(theme.contains("static let minTap: CGFloat = 44"))
        XCTAssertTrue(clip.contains("ClipJournalPalette"))
        XCTAssertTrue(clip.contains("ClipDisplayTitle"))
        XCTAssertTrue(clip.contains("ClipGooglePhotoCard(photo: place.journalGooglePhoto)"))
        XCTAssertTrue(clip.contains("SharedPlaceData.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.isListLink(url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.from(url: url)"))
        XCTAssertTrue(clip.contains("SharedListPayload.resolve(from: url)"))
        XCTAssertTrue(clip.contains("func isPlaceLink"))
        XCTAssertFalse(clip.contains("coming soon") || clip.contains("Coming Soon"))
        XCTAssertFalse(clip.contains("PLACE POSTCARD"))
        XCTAssertFalse(clip.contains("TRIP POSTCARD"))
        XCTAssertFalse(clip.contains("ClipScallopedRectangle"))
        XCTAssertFalse(clip.contains("ClipPostmark"))
        XCTAssertFalse(clip.contains("ClipAirmailDivider"))
        XCTAssertFalse(clip.contains("ClipAtlasPalette"))
        XCTAssertFalse(clip.contains("AsyncImage"))
        XCTAssertFalse(clip.contains("item.photoURLs"))
        XCTAssertTrue(photo.contains("ClipGooglePhotoCard"))
        XCTAssertTrue(photo.contains("place.photo.attribution.author"))
        XCTAssertTrue(photo.contains("place.photo.attribution.logo"))
        XCTAssertTrue(photo.contains("GoogleMapsLogoOnImage"))
        XCTAssertTrue(photo.contains("minimumTapTarget: CGFloat = ClipJournalLayout.minTap"))
        XCTAssertTrue(photo.contains("ClipCoralPhotoFallback"))
        XCTAssertTrue(clipPayload.contains("var photoAttribution"))
        XCTAssertTrue(clipPayload.contains("var journalGooglePhoto"))
        XCTAssertTrue(appPayload.contains("var photoAttribution"))
        XCTAssertTrue(appPayload.contains("var journalGooglePhoto"))
    }

    func testAppClipHasOfficialGoogleMapsLogoAssets() {
        let onImage = repositoryRoot.appendingPathComponent(
            "SAV-EClip/Assets.xcassets/GoogleMapsLogoOnImage.imageset/GoogleMaps_Logo_WithLightOutline_2x.png"
        )
        let onPlain = repositoryRoot.appendingPathComponent(
            "SAV-EClip/Assets.xcassets/GoogleMapsLogoOnPlain.imageset/GoogleMaps_Logo_DarkGray_2x.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: onImage.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: onPlain.path))
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
