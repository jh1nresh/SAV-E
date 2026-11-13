import XCTest
import SpriteKit
import SwiftUI
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityPinTransitionTests: XCTestCase {
    func testSelectionReleaseAndInterruptedReversalKeepTheDisplayedDiameter() throws {
        for browse: CGFloat in [42, 58] {
            let overlay = CityScenePins()
            overlay.update([pin(selected: false, diameter: browse)], viewport: viewport, night: false, reduceMotion: false)
            let head = try XCTUnwrap(overlay.scene.childNode(withName: "transition-photo") as? SKSpriteNode)
            let position = head.position
            let anchor = head.anchorPoint
            assertIntrinsicCanvas(head)
            let beforeSelection = displayedDiameter(head, rasterDiameter: browse)

            overlay.update([pin(selected: true, diameter: browse)], viewport: viewport, night: false, reduceMotion: false)
            XCTAssertEqual(head.xScale * 62, browse, accuracy: 0.0001)
            assertIntrinsicCanvas(head)
            XCTAssertEqual(displayedDiameter(head, rasterDiameter: 62), beforeSelection, accuracy: 0.0001)
            XCTAssertEqual(head.position, position)
            XCTAssertEqual(head.anchorPoint, anchor)
            XCTAssertTrue(overlay.isAnimating)

            // Sample an interrupted spring without requiring a renderer clock.
            // The release must use this presentation scale, not nominal 62pt.
            head.setScale(1.035)
            let beforeRelease = displayedDiameter(head, rasterDiameter: 62)
            overlay.update([pin(selected: false, diameter: browse)], viewport: viewport, night: false, reduceMotion: false)
            XCTAssertEqual(head.xScale * browse, 62 * 1.035, accuracy: 0.0001)
            assertIntrinsicCanvas(head)
            XCTAssertEqual(displayedDiameter(head, rasterDiameter: browse), beforeRelease, accuracy: 0.0001)
            XCTAssertEqual(head.position, position)
            XCTAssertEqual(head.anchorPoint, anchor)
            XCTAssertTrue(overlay.isAnimating, "Release must settle instead of snapping to the smaller raster")

            head.setScale(1.17)
            let beforeReversal = displayedDiameter(head, rasterDiameter: browse)
            overlay.update([pin(selected: true, diameter: browse)], viewport: viewport, night: false, reduceMotion: false)
            XCTAssertEqual(head.xScale * 62, browse * 1.17, accuracy: 0.0001)
            assertIntrinsicCanvas(head)
            XCTAssertEqual(displayedDiameter(head, rasterDiameter: 62), beforeReversal, accuracy: 0.0001)
            XCTAssertEqual(head.position, position)
            XCTAssertEqual(head.anchorPoint, anchor)
        }
    }

    func testSameSelectionNightTextureChangePreservesAnActiveScaleAndCanvas() throws {
        let overlay = CityScenePins()
        let selected = pin(selected: true, diameter: 58)
        // Exercise a real selection transition, not a renderer mount.
        overlay.update([pin(selected: false, diameter: 58)], viewport: viewport, night: false, reduceMotion: false)
        overlay.update([selected], viewport: viewport, night: false, reduceMotion: false)
        let head = try XCTUnwrap(overlay.scene.childNode(withName: "transition-photo") as? SKSpriteNode)
        XCTAssertTrue(overlay.isAnimating)
        head.setScale(0.91)
        let before = displayedDiameter(head, rasterDiameter: 62)
        let position = head.position
        let anchor = head.anchorPoint
        overlay.update([selected], viewport: viewport, night: true, reduceMotion: false)
        XCTAssertEqual(head.xScale, 0.91, accuracy: 0.0001)
        XCTAssertEqual(head.yScale, 0.91, accuracy: 0.0001)
        assertIntrinsicCanvas(head)
        XCTAssertEqual(displayedDiameter(head, rasterDiameter: 62), before, accuracy: 0.0001)
        XCTAssertEqual(head.position, position)
        XCTAssertEqual(head.anchorPoint, anchor)
        XCTAssertTrue(overlay.isAnimating, "A raster-only update must not cancel or restart the current spring")
    }

    func testSelectedPhotoOwnerHandoffKeepsFinalSizeWithoutAnotherEntrance() throws {
        for browse: CGFloat in [36, 42, 58] {
            let overlay = CityScenePins()
            let selected = pin(selected: true, diameter: browse)
            for _ in 0..<2 {
                overlay.update([selected], viewport: viewport, night: false, reduceMotion: false)
                let head = try XCTUnwrap(overlay.scene.childNode(withName: "transition-photo") as? SKSpriteNode)
                XCTAssertEqual(displayedDiameter(head, rasterDiameter: 62), 62, accuracy: 0.001)
                XCTAssertEqual(head.xScale, 1)
                XCTAssertFalse(overlay.isAnimating, "Ownership changes must not replay selection")
                assertIntrinsicCanvas(head)
                overlay.update([], viewport: viewport, night: false, reduceMotion: false)
                XCTAssertNil(overlay.scene.childNode(withName: "transition-photo"))
            }
        }
    }

    func testSelectedSwiftUIFallbackMountRendersTheFullPhotoWithoutOnAppear() throws {
        let artwork = CityPinArtwork(id: "landmark-101", title: "Taipei 101", symbol: "photo",
                                    saved: false, selected: true, contactOpacity: 1,
                                    browsePhotoDiameter: 36, rasterReduceMotion: false)
        let renderer = ImageRenderer(content: artwork.frame(width: 140, height: 92).environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        XCTAssertTrue(rendered)
        var columns: [Int] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                if bytes[offset] > 118 && bytes[offset] < 160 && bytes[offset+1] > 185
                    && bytes[offset+1] < 224 && bytes[offset+2] > 240 { columns.append(x) }
            }
        }
        let width = try XCTUnwrap(columns.max()) - XCTUnwrap(columns.min()) + 1
        XCTAssertGreaterThanOrEqual(width, 60)
        XCTAssertLessThanOrEqual(width, 64)
    }

    func testRasterRoundingAndRevealScaleParticipateInContinuity() throws {
        let browse = try XCTUnwrap(CityPinRaster.photoMetrics(selected: false, browseDiameter: 42.4,
                                                             reveal: 0.336, reduceMotion: false))
        let selected = try XCTUnwrap(CityPinRaster.photoMetrics(selected: true, browseDiameter: 42.4,
                                                               reveal: 0.336, reduceMotion: false))
        XCTAssertEqual(browse.diameter, 42)
        XCTAssertEqual(browse.revealScale, 0.901, accuracy: 0.000001) // reveal quantizes to 0.34
        XCTAssertEqual(selected.renderedDiameter, 62 * 0.901, accuracy: 0.000001)
        let start = try XCTUnwrap(CityPinPhotoTransition.startScale(
            previousDiameter: browse.renderedDiameter, currentScale: 0.79,
            nextDiameter: selected.renderedDiameter, reduceMotion: false))
        XCTAssertEqual(start * selected.renderedDiameter, browse.renderedDiameter * 0.79, accuracy: 0.000001)
    }

    func testInvalidDimensionsNeverProduceAnAnimationScale() {
        for bad: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(CityPinPhotoTransition.startScale(previousDiameter: bad, currentScale: 1, nextDiameter: 62, reduceMotion: false))
            XCTAssertNil(CityPinPhotoTransition.startScale(previousDiameter: 42, currentScale: bad, nextDiameter: 62, reduceMotion: false))
            XCTAssertNil(CityPinPhotoTransition.startScale(previousDiameter: 42, currentScale: 1, nextDiameter: bad, reduceMotion: false))
            XCTAssertNil(CityPinRaster.photoMetrics(selected: false, browseDiameter: bad, reveal: 1, reduceMotion: false))
        }
        for bad: Double in [.nan, .infinity, -.infinity] {
            XCTAssertNil(CityPinRaster.photoMetrics(selected: true, browseDiameter: 42, reveal: bad, reduceMotion: false))
        }
        XCTAssertNil(CityPinPhotoTransition.startScale(previousDiameter: .greatestFiniteMagnitude,
                                                      currentScale: .greatestFiniteMagnitude, nextDiameter: 1, reduceMotion: false))
    }

    func testEnablingReduceMotionCancelsAnAlreadyRunningPhotoSpring() throws {
        let overlay = CityScenePins()
        overlay.update([pin(selected: false, diameter: 58)], viewport: viewport, night: false, reduceMotion: false)
        overlay.update([pin(selected: true, diameter: 58)], viewport: viewport, night: false, reduceMotion: false)
        let head = try XCTUnwrap(overlay.scene.childNode(withName: "transition-photo") as? SKSpriteNode)
        XCTAssertTrue(overlay.isAnimating)
        head.setScale(0.94)
        // No selection change: the accessibility preference alone cancels it.
        overlay.update([pin(selected: true, diameter: 58)], viewport: viewport, night: false, reduceMotion: true)
        XCTAssertEqual(head.xScale, 1)
        XCTAssertFalse(overlay.isAnimating)
        overlay.update([pin(selected: false, diameter: 58)], viewport: viewport, night: false, reduceMotion: true)
        XCTAssertEqual(head.xScale, 1)
        XCTAssertFalse(overlay.isAnimating)
    }

    func testSelectedCategoryMountDoesNotPretendToBeANewSelection() throws {
        let overlay = CityScenePins()
        var glyph = pin(selected: false, diameter: 42)
        glyph = CityScenePin(id: glyph.id, contextID: nil, title: glyph.title, symbol: glyph.symbol,
                             saved: false, selected: true, placement: glyph.placement, reveal: glyph.reveal,
                             photoDiameter: glyph.photoDiameter, titleOpacity: glyph.titleOpacity, titleAbove: false)
        overlay.update([glyph], viewport: viewport, night: false, reduceMotion: false)
        let head = try XCTUnwrap(overlay.scene.childNode(withName: "transition-photo") as? SKSpriteNode)
        XCTAssertEqual(head.xScale, 1, accuracy: 0.0001)
        XCTAssertFalse(overlay.isAnimating)
    }

    private func displayedDiameter(_ head: SKSpriteNode, rasterDiameter: CGFloat) -> CGFloat {
        // size is in parent coordinates: include the actual canvas extent,
        // not only xScale, so a texture replacement cannot hide a size snap.
        head.size.width / 140 * rasterDiameter
    }

    private func assertIntrinsicCanvas(_ head: SKSpriteNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(head.size.width / head.xScale, 140, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(head.size.height / head.yScale, 92, accuracy: 0.0001, file: file, line: line)
    }

    private let viewport = CGSize(width: 393, height: 852)
    private func pin(selected: Bool, diameter: CGFloat) -> CityScenePin {
        CityScenePin(id: "transition-photo", contextID: "landmark-101", title: "Taipei 101", symbol: "photo",
                     saved: false, selected: selected, placement: .init(point: .init(x: 160, y: 200), contactOpacity: 1),
                     reveal: 1, photoDiameter: diameter, titleOpacity: 1, titleAbove: false)
    }
}
