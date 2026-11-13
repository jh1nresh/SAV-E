import XCTest
import CoreGraphics
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPChromeLayoutTests: XCTestCase {
    func testActualLowPhotoAndCaptionMoveOnlyCompactChromeAboveSelection() {
        let viewport = CGSize(width: 393, height: 852)
        let photo = CGRect(x: 240, y: 710.33, width: 64, height: 64)
        let caption = CGRect(x: 202, y: 680, width: 140, height: 26)
        let selected = photo.union(caption)
        let original = selected
        let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                   expandedHeight: 240, compactHeight: 66)
        XCTAssertTrue(placement.compact)
        XCTAssertEqual(placement.dockBottomInset, 184, accuracy: 0.001)
        XCTAssertEqual(placement.panelBottomInset, 274, accuracy: 0.001)
        assertContainedAndOrdered(placement, viewport: viewport, cardHeight: 66)
        assertClear(placement, viewport: viewport, cardHeight: 66, selected: selected)
        XCTAssertEqual(selected, original, "Layout must never change the geographic/presentation bounds")
    }

    func testUnselectedAndHighSelectionKeepTheExpandedBottomGroup() {
        let viewport = CGSize(width: 393, height: 852)
        let expected = CityMVPChromeLayout.Placement(compact: false, panelBottomInset: 122, dockBottomInset: 32)
        XCTAssertEqual(CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: nil,
                                                  expandedHeight: 240, compactHeight: 66), expected)
        XCTAssertEqual(CityMVPChromeLayout.resolve(viewport: viewport,
                                                  selectedBounds: CGRect(x: 164, y: 200, width: 64, height: 90),
                                                  expandedHeight: 240, compactHeight: 66), expected)
    }

    func testCompactingWithoutMovingIsPreferredWhenItClearsThePhoto() {
        let viewport = CGSize(width: 393, height: 852)
        let selected = CGRect(x: 164, y: 500, width: 64, height: 64)
        let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                   expandedHeight: 240, compactHeight: 66)
        XCTAssertEqual(placement, .init(compact: true, panelBottomInset: 122, dockBottomInset: 32))
        assertClear(placement, viewport: viewport, cardHeight: 66, selected: selected)
    }

    func testCardCollisionAloneKeepsNavigationAtTheBottom() {
        let viewport = CGSize(width: 393, height: 852)
        let selected = CGRect(x: 164, y: 578, width: 64, height: 103)
        let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                   expandedHeight: 240, compactHeight: 66)
        XCTAssertTrue(placement.compact)
        XCTAssertEqual(placement.dockBottomInset, 32)
        XCTAssertGreaterThan(placement.panelBottomInset, 122)
        assertContainedAndOrdered(placement, viewport: viewport, cardHeight: 66)
        assertClear(placement, viewport: viewport, cardHeight: 66, selected: selected)
    }

    func testCaptionFlipsBeforeItCanCauseNavigationToJump() {
        let viewport = CGSize(width: 393, height: 852)
        for anchorY in stride(from: CGFloat(610), through: 640, by: 0.5) {
            let below = CGRect(x: 164, y: anchorY + 4, width: 64, height: 26)
            let above = CityMVPChromeLayout.prefersTitleAbove(captionBelow: below, viewport: viewport, compactHeight: 66)
            let caption = above ? CGRect(x: 164, y: anchorY - 103, width: 64, height: 26) : below
            let photo = CGRect(x: 164, y: anchorY - 72, width: 64, height: 74)
            let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: photo.union(caption),
                                                       expandedHeight: 240, compactHeight: 66)
            XCTAssertEqual(placement.dockBottomInset, 32, "Caption flipping must not lift and restore the dock")
        }
    }

    func testPortraitSweepKeepsPhotoCaptionClearAndChromeInsideItsArea() {
        for viewport in [CGSize(width: 375, height: 812), CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)] {
            for y in stride(from: CGFloat(200), through: 790, by: 10) {
                let photo = CGRect(x: viewport.width / 2 - 32, y: y, width: 64, height: 64)
                let caption = CGRect(x: viewport.width / 2 - 70, y: y - 31, width: 140, height: 26)
                let selected = photo.union(caption)
                let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                           expandedHeight: 240, compactHeight: 66)
                let cardHeight: CGFloat = placement.compact ? 66 : 240
                assertContainedAndOrdered(placement, viewport: viewport, cardHeight: cardHeight)
                assertClear(placement, viewport: viewport, cardHeight: cardHeight, selected: selected)
                // If relocation is necessary it is an exceptional upward move;
                // ordinary bottom chrome never drifts below its footer.
                XCTAssertGreaterThanOrEqual(placement.dockBottomInset, 32)
            }
        }
    }

    func testEmptyOffscreenAndNonfiniteSelectionsDoNotRelocateChrome() {
        let viewport = CGSize(width: 393, height: 852)
        let expected = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: nil, expandedHeight: 240, compactHeight: 66)
        let invalid: [CGRect] = [.zero, .null, .infinite,
                                 CGRect(x: 400, y: 680, width: 64, height: 64),
                                 CGRect(x: 150, y: 900, width: 64, height: 64),
                                 CGRect(x: CGFloat.nan, y: 650, width: 64, height: 64)]
        for bounds in invalid {
            XCTAssertEqual(CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: bounds,
                                                      expandedHeight: 240, compactHeight: 66), expected)
        }
    }

    func testSelectionOutsideChromeHorizontallyDoesNotCauseVerticalMotion() {
        let viewport = CGSize(width: 393, height: 852)
        // The one-point visible edge remains outside x14 even after12pt padding.
        let selected = CGRect(x: -63, y: 680, width: 64, height: 64)
        let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                   expandedHeight: 240, compactHeight: 66)
        XCTAssertEqual(placement, .init(compact: false, panelBottomInset: 122, dockBottomInset: 32))
    }

    func testImpossibleLargeSelectionClampsWithoutClaimingClearance() {
        let viewport = CGSize(width: 393, height: 852)
        let selected = CGRect(x: 100, y: 150, width: 190, height: 660)
        let placement = CityMVPChromeLayout.resolve(viewport: viewport, selectedBounds: selected,
                                                   expandedHeight: 240, compactHeight: 66)
        XCTAssertTrue(placement.compact)
        assertContainedAndOrdered(placement, viewport: viewport, cardHeight: 66)
        let frames = chromeFrames(placement, viewport: viewport, cardHeight: 66)
        XCTAssertTrue(frames.card.intersects(selected) || frames.dock.intersects(selected),
                      "An impossible fixed-height layout must not be represented as proven clearance")
    }

    func testShortAndNonfiniteInputsAlwaysReturnFiniteInsets() {
        for viewport in [CGSize(width: 393, height: 180), .zero,
                         CGSize(width: CGFloat.nan, height: 852), CGSize(width: 393, height: CGFloat.infinity)] {
            let placement = CityMVPChromeLayout.resolve(viewport: viewport,
                                                       selectedBounds: CGRect(x: 150, y: 130, width: 64, height: 64),
                                                       expandedHeight: .infinity, compactHeight: .nan)
            XCTAssertTrue(placement.panelBottomInset.isFinite)
            XCTAssertTrue(placement.dockBottomInset.isFinite)
            XCTAssertGreaterThanOrEqual(placement.panelBottomInset, 0)
            XCTAssertGreaterThanOrEqual(placement.dockBottomInset, 0)
            XCTAssertEqual(placement.panelBottomInset - placement.dockBottomInset, 90)
        }
    }

    private func chromeFrames(_ placement: CityMVPChromeLayout.Placement, viewport: CGSize,
                              cardHeight: CGFloat) -> (card: CGRect, dock: CGRect) {
        let cardBottom = viewport.height - placement.panelBottomInset
        return (CGRect(x: 14, y: cardBottom - cardHeight, width: viewport.width - 28, height: cardHeight),
                CGRect(x: 14, y: viewport.height - placement.dockBottomInset - 72, width: viewport.width - 28, height: 72))
    }
    private func assertContainedAndOrdered(_ placement: CityMVPChromeLayout.Placement, viewport: CGSize,
                                          cardHeight: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let frames = chromeFrames(placement, viewport: viewport, cardHeight: cardHeight)
        XCTAssertGreaterThanOrEqual(frames.card.minY, 124 - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(frames.dock.maxY, viewport.height - 32 + 0.001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frames.dock.minY - frames.card.maxY, 18 - 0.001, file: file, line: line)
        XCTAssertEqual(frames.dock.height, 72, file: file, line: line)
    }
    private func assertClear(_ placement: CityMVPChromeLayout.Placement, viewport: CGSize, cardHeight: CGFloat,
                             selected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let frames = chromeFrames(placement, viewport: viewport, cardHeight: cardHeight)
        let protected = selected.insetBy(dx: -12, dy: -12).intersection(CGRect(origin: .zero, size: viewport))
        XCTAssertFalse(frames.card.intersects(protected), "Card covers selected photo/caption", file: file, line: line)
        XCTAssertFalse(frames.dock.intersects(protected), "Dock covers selected photo/caption", file: file, line: line)
    }
}
