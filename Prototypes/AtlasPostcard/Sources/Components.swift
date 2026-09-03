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
/// that canvas to whatever device it lands on). It deliberately floats inside
/// the canvas instead of rendering as a full-width slab. The selection pill is
/// derived from the compact slot width so adding destinations cannot make it
/// collide with its neighbours.
///
/// The pill is therefore derived from the slot, never fixed.
enum AtlasTabBarMetrics {
    static let width: CGFloat = 338
    static let height: CGFloat = 62
    static let leadingInset: CGFloat = (AtlasMetrics.width - width) / 2
    static let standardY: CGFloat = AtlasMetrics.height - height - 12
    static let mapY: CGFloat = standardY + 2
    static let horizontalPadding: CGFloat = 4
    static let itemHeight: CGFloat = 54
    static let selectionHeight: CGFloat = 46
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
}

struct AtlasTabBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let selection: Item
    let title: KeyPath<Item, String>
    let icon: KeyPath<Item, String>
    let accessibilityPrefix: String
    var isRaisedControl: (Item) -> Bool = { _ in false }
    let onSelect: (Item) -> Void

    private var pillWidth: CGFloat {
        AtlasTabBarMetrics.pillWidth(itemCount: items.count)
    }

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
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.42), lineWidth: 0.8)
                                }
                                .shadow(color: AtlasPalette.ink.opacity(0.15), radius: 8, y: 3)
                                .offset(y: -6)
                        } else if selection == item {
                            Capsule()
                                .fill(AtlasPalette.mint.opacity(0.62))
                                .frame(
                                    width: pillWidth,
                                    height: AtlasTabBarMetrics.selectionHeight
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.36), lineWidth: 0.8)
                                }
                        }

                        VStack(spacing: isRaisedControl(item) ? 1 : 2) {
                            Image(systemName: item[keyPath: icon])
                                .font(.system(
                                    size: isRaisedControl(item) ? 20 : 21,
                                    weight: isRaisedControl(item) ? .semibold : .regular
                                ))
                                .frame(height: 24)

                            Text(item[keyPath: title])
                                .font(AtlasType.display(isRaisedControl(item) ? 9 : 11))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(isRaisedControl(item) ? .white : AtlasPalette.ink)
                        .offset(y: isRaisedControl(item) ? -6 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: AtlasTabBarMetrics.itemHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item[keyPath: title])
                .accessibilityIdentifier(
                    "\(accessibilityPrefix).\(item[keyPath: title].lowercased())"
                )
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, AtlasTabBarMetrics.horizontalPadding)
        .frame(width: AtlasTabBarMetrics.width, height: AtlasTabBarMetrics.height)
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            tabItems
                .glassEffect(
                    .regular.tint(AtlasPalette.paper.opacity(0.14)),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.30), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.10), radius: 12, y: 5)
        } else {
            tabItems
                .background(.ultraThinMaterial, in: Capsule())
                .background(AtlasPalette.paper.opacity(0.22), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.08), radius: 10, y: 4)
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
                Text(text)
                    .font(AtlasType.strong(17))
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

struct ScallopedRectangle: Shape {
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

private struct SealShape: Shape {
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
