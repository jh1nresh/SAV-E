import SwiftUI

struct MemoMark: View {
    let size: CGFloat

    var body: some View {
        Image("MemoMascot")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(1.6)
            .accessibilityLabel("Memo")
    }
}

struct BrandHeader<Trailing: View>: View {
    @Environment(\.atlasPresentation) private var presentation
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            Button(action: presentation.onOpenPassport) {
                HStack(spacing: 9) {
                    Image("SavvyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Savvy")
                        .font(AtlasType.strong(24))
                        .tracking(1.1)
                        .foregroundStyle(AtlasPalette.forest)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Savvy Passport")
            .accessibilityIdentifier("root.passport")

            Spacer()
            trailing()
        }
        .padding(.horizontal, 11)
    }
}

/// Layout math for `AtlasTabBar`, split out so it can be asserted without
/// rendering.
///
/// The bar lives on the fixed 402x874 Atlas canvas (`ReferenceViewport` scales
/// that canvas to whatever device it lands on). Founder lock 2026-10-15: a
/// flat full-width pixel bar, not a floating glass capsule. Slot math still
/// keeps the coral + inside its destination.
///
/// The pill is therefore derived from the slot, never fixed.
enum AtlasTabBarMetrics {
    static let width: CGFloat = AtlasMetrics.width
    static let height: CGFloat = 62
    static let leadingInset: CGFloat = 0
    static let standardY: CGFloat = AtlasMetrics.height - height
    static let mapY: CGFloat = standardY
    static let horizontalPadding: CGFloat = 16
    static let itemHeight: CGFloat = 54
    static let minimumHitTarget: CGFloat = 44
    static let selectionHeight: CGFloat = 46
    /// Hairline on the coral Save circle. Counted in the chrome-fit check
    /// because a centered stroke grows the optical disk past `diameter`.
    static let raisedControlStrokeWidth: CGFloat = 0.8
    /// #179 kept a 50pt disk inside the 62pt box (6pt geometric inset). The
    /// glass pill still reads smaller than that box, so 50pt bursts the
    /// visible chrome. Keep Save at or under the mint lozenge, minus stroke.
    static let raisedControlDiameter: CGFloat = 44
    static let raisedControlOffsetY: CGFloat = 0
    /// Same vertical inset as the mint selection lozenge, per side.
    static var raisedControlChromeInset: CGFloat { (height - selectionHeight) / 2 }
    /// Breathing room between the pill and the slot edge, per side.
    static let pillInset: CGFloat = 4
    /// The lozenge may shrink independently of the 44pt button target.
    static let minimumPillWidth: CGFloat = 48

    static func slotWidth(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return (width - horizontalPadding * 2) / CGFloat(itemCount)
    }

    static func pillWidth(itemCount: Int) -> CGFloat {
        max(minimumPillWidth, slotWidth(itemCount: itemCount) - pillInset * 2)
    }

    /// True when the pill sits inside its slot with no overlap. The four-item
    /// bar has always satisfied this by luck; five items only satisfies it
    /// because `pillWidth` is now derived.
    static func pillFitsSlot(itemCount: Int) -> Bool {
        pillWidth(itemCount: itemCount) <= slotWidth(itemCount: itemCount)
    }

    static var raisedControlFitsBar: Bool {
        let opticalHalf = (raisedControlDiameter + raisedControlStrokeWidth) / 2
        let centreY = height / 2 + raisedControlOffsetY
        let inset = raisedControlChromeInset
        return centreY - opticalHalf >= inset
            && centreY + opticalHalf <= height - inset
    }

    static func raisedControlFitsSlot(itemCount: Int) -> Bool {
        raisedControlDiameter <= slotWidth(itemCount: itemCount)
    }
}

struct AtlasTabBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let selection: Item
    let title: KeyPath<Item, String>
    let icon: KeyPath<Item, String>
    let accessibilityPrefix: String
    var displayTitle: ((Item) -> String)? = nil
    var isRaisedControl: (Item) -> Bool = { _ in false }
    let onSelect: (Item) -> Void

    private var tabItems: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    ZStack {
                        if isRaisedControl(item) {
                            Circle()
                                .fill(AtlasPalette.coral.opacity(0.94))
                                .frame(
                                    width: AtlasTabBarMetrics.raisedControlDiameter,
                                    height: AtlasTabBarMetrics.raisedControlDiameter
                                )
                                .overlay {
                                    Circle()
                                        .stroke(
                                            .white.opacity(0.42),
                                            lineWidth: AtlasTabBarMetrics.raisedControlStrokeWidth
                                        )
                                }
                                .offset(y: AtlasTabBarMetrics.raisedControlOffsetY)
                        }

                        VStack(spacing: isRaisedControl(item) ? 1 : 2) {
                            Image(systemName: item[keyPath: icon])
                                .font(.system(
                                    size: isRaisedControl(item) ? 20 : 18,
                                    weight: isRaisedControl(item) ? .semibold : .regular
                                ))
                                .frame(height: 24)

                            Text(displayTitle?(item) ?? item[keyPath: title])
                                .font(AtlasType.display(isRaisedControl(item) ? 9 : 11))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(
                            isRaisedControl(item)
                                ? Color.white
                                : selection == item
                                    ? AtlasPalette.coral
                                    : AtlasPalette.ink.opacity(0.52)
                        )
                        .offset(
                            y: isRaisedControl(item)
                                ? AtlasTabBarMetrics.raisedControlOffsetY
                                : 0
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: AtlasTabBarMetrics.itemHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayTitle?(item) ?? item[keyPath: title])
                .accessibilityIdentifier(
                    "\(accessibilityPrefix).\(item[keyPath: title].lowercased())"
                )
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, AtlasTabBarMetrics.horizontalPadding)
        .frame(width: AtlasTabBarMetrics.width, height: AtlasTabBarMetrics.height)
    }

    var body: some View {
        tabItems
            .background(AtlasPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AtlasPalette.line.opacity(0.35))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct RoundStamp: View {
    enum Style {
        case mapStamp
        case tripStop
    }

    let text: String
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .mapStamp:
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 35, height: 35)
                    .background(AtlasPalette.mint, in: Circle())
            case .tripStop:
                // M1: seals never show raw hex, debug IDs, or pipeline tokens.
                if let text = SaveSoftPixelAccentsLock.visibleStampText(text) {
                    Text(text)
                        .font(AtlasType.strong(17))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 38, height: 38)
                        .background(AtlasPalette.coral.opacity(0.90), in: Circle())
                        .overlay {
                            Circle().stroke(AtlasPalette.coral, lineWidth: 1)
                        }
                } else {
                    Image(systemName: "mappin")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 38, height: 38)
                        .background(AtlasPalette.coral.opacity(0.90), in: Circle())
                        .overlay {
                            Circle().stroke(AtlasPalette.coral, lineWidth: 1)
                        }
                }
            }
        }
    }
}

nonisolated struct ScallopedRectangle: Shape {
    var depth: CGFloat = 4
    var pitch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = pitch / 2
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + depth))

        var x = rect.minX + radius
        while x < rect.maxX - radius {
            path.addQuadCurve(
                to: CGPoint(x: x + pitch, y: rect.minY + depth),
                control: CGPoint(x: x + radius, y: rect.minY - depth)
            )
            x += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + radius))
        var y = rect.minY + radius
        while y < rect.maxY - radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - depth, y: y + pitch),
                control: CGPoint(x: rect.maxX + depth, y: y + radius)
            )
            y += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - depth))
        x = rect.maxX - radius
        while x > rect.minX + radius {
            path.addQuadCurve(
                to: CGPoint(x: x - pitch, y: rect.maxY - depth),
                control: CGPoint(x: x - radius, y: rect.maxY + depth)
            )
            x -= pitch
        }

        path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - radius))
        y = rect.maxY - radius
        while y > rect.minY + radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + depth, y: y - pitch),
                control: CGPoint(x: rect.minX - depth, y: y - radius)
            )
            y -= pitch
        }

        path.closeSubpath()
        return path
    }
}

struct PerforatedMedallion: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 52, height: 52)
            .background(tint, in: SealShape())
            .overlay {
                SealShape()
                    .stroke(AtlasPalette.ink.opacity(0.16), lineWidth: 1)
            }
    }
}

nonisolated private struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2 - 2
        let steps = 128
        var path = Path()

        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2 - .pi / 2
            let radius = baseRadius + cos(angle * 16) * 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
