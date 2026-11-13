#if SAVVY_CITY_MVP
import Foundation
import CoreGraphics

/// Resolves only map chrome. The selected photo/caption bounds, map camera and
/// pin coordinates are inputs, never values this layout changes.
enum CityMVPChromeLayout {
    struct Placement: Equatable {
        let compact: Bool
        let panelBottomInset: CGFloat
        let dockBottomInset: CGFloat
    }

    private static let dockHeight: CGFloat = 72
    private static let footer: CGFloat = 32
    private static let cardGap: CGFloat = 18
    private static let topChrome: CGFloat = 124
    private static let horizontalInset: CGFloat = 14
    private static let selectionPadding: CGFloat = 12

    static func resolve(viewport: CGSize, selectedBounds: CGRect?, expandedHeight: CGFloat,
                        compactHeight: CGFloat) -> Placement {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else {
            return placement(compact: true, dockBottomInset: footer)
        }
        let compact = finiteHeight(compactHeight)
        let expanded = max(compact, finiteHeight(expandedHeight))
        let bottomInset = min(footer, max(0, viewport.height - dockHeight))
        let availableBottom = viewport.height - bottomInset
        let expandedTop = availableBottom - groupHeight(card: expanded)
        let compactTop = availableBottom - groupHeight(card: compact)
        let width = max(0, viewport.width - 2 * horizontalInset)
        let selection = protectedSelection(selectedBounds, viewport: viewport)

        func intersects(cardHeight: CGFloat, groupBottom: CGFloat) -> Bool {
            guard let selection else { return false }
            return frames(cardHeight: cardHeight, groupBottom: groupBottom,
                          width: width).contains { $0.intersects(selection) }
        }

        if expandedTop >= topChrome, !intersects(cardHeight: expanded, groupBottom: availableBottom) {
            return placement(compact: false, dockBottomInset: bottomInset)
        }
        if compactTop >= topChrome, !intersects(cardHeight: compact, groupBottom: availableBottom) {
            return placement(compact: true, dockBottomInset: bottomInset)
        }
        if let selection {
            let restingDock = frames(cardHeight: compact, groupBottom: availableBottom, width: width)[1]
            // A card collision alone must not transport the navigation dock.
            // First give just the compact card a free position above the pin.
            let cardBottom = min(restingDock.minY - cardGap, selection.minY)
            if !restingDock.intersects(selection), cardBottom - compact >= topChrome {
                return Placement(compact: true, panelBottomInset: viewport.height - cardBottom,
                                 dockBottomInset: bottomInset)
            }
        }
        guard let selection else {
            // There is no feasible full-height group in an exceptionally short
            // viewport. Keep the footer and use the smaller card; this API does
            // not claim that unchanged fixed control heights can fit here.
            return placement(compact: true, dockBottomInset: bottomInset)
        }

        let height = groupHeight(card: compact)
        let aboveBottom = min(availableBottom, selection.minY)
        if aboveBottom - height >= topChrome {
            return placement(compact: true, dockBottomInset: viewport.height - aboveBottom)
        }
        let belowTop = max(topChrome, selection.maxY)
        if belowTop + height <= availableBottom {
            return placement(compact: true, dockBottomInset: viewport.height - belowTop - height)
        }

        // A large selection or short viewport can make clearance impossible.
        // Clamp candidates inside the available region when it can contain the
        // group, minimize actual card/dock overlap, and favor the usual bottom
        // position on ties. Camera/pin motion is never an escape hatch.
        guard compactTop >= topChrome else {
            return placement(compact: true, dockBottomInset: bottomInset)
        }
        let minimumBottom = topChrome + height
        let candidates = [availableBottom,
                          min(availableBottom, max(minimumBottom, aboveBottom)),
                          min(availableBottom, max(minimumBottom, belowTop + height))]
        var bestBottom = availableBottom
        var bestOverlap = CGFloat.infinity
        for candidate in candidates {
            let overlap = frames(cardHeight: compact, groupBottom: candidate, width: width).reduce(CGFloat.zero) { total, frame in
                let intersection = frame.intersection(selection)
                return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
            if overlap < bestOverlap {
                bestOverlap = overlap
                bestBottom = candidate
            }
        }
        return placement(compact: true, dockBottomInset: viewport.height - bestBottom)
    }

    static func prefersTitleAbove(captionBelow: CGRect, viewport: CGSize, compactHeight: CGFloat) -> Bool {
        let restingCardTop = viewport.height - footer - dockHeight - cardGap - finiteHeight(compactHeight)
        return captionBelow.maxY + selectionPadding >= restingCardTop
    }

    private static func placement(compact: Bool, dockBottomInset: CGFloat) -> Placement {
        Placement(compact: compact, panelBottomInset: dockBottomInset + dockHeight + cardGap,
                  dockBottomInset: dockBottomInset)
    }
    private static func groupHeight(card: CGFloat) -> CGFloat { card + cardGap + dockHeight }
    private static func finiteHeight(_ height: CGFloat) -> CGFloat {
        height.isFinite && height > 0 ? height : 0
    }
    private static func frames(cardHeight: CGFloat, groupBottom: CGFloat, width: CGFloat) -> [CGRect] {
        let dock = CGRect(x: horizontalInset, y: groupBottom - dockHeight, width: width, height: dockHeight)
        let card = CGRect(x: horizontalInset, y: dock.minY - cardGap - cardHeight, width: width, height: cardHeight)
        return [card, dock]
    }
    private static func protectedSelection(_ bounds: CGRect?, viewport: CGSize) -> CGRect? {
        guard let bounds, !bounds.isNull, !bounds.isInfinite, !bounds.isEmpty,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return nil }
        let visible = CGRect(origin: .zero, size: viewport)
        guard bounds.intersects(visible) else { return nil }
        return bounds.insetBy(dx: -selectionPadding, dy: -selectionPadding).intersection(visible)
    }
}
#endif
