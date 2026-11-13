#if SAVVY_CITY_MVP
import SwiftUI

/// Map-first navigation. Search and capture remain actions outside the tab track.
struct CityMVPBottomBar: View {
    static let height: CGFloat = 72
    static let horizontalInset: CGFloat = 20
    static let bottomClearance: CGFloat = 32

    let selection: SaveRootTab
    let onSelect: (SaveRootTab) -> Void
    let onSearch: () -> Void
    let onCapture: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragPosition: CGFloat?

    private static let destinations: [SaveRootTab] = [.home, .map, .profile]
    private var selectedIndex: Int { Self.destinations.firstIndex(of: selection) ?? 2 }
    private var position: CGFloat { dragPosition ?? CGFloat(selectedIndex) }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 8) { controls }
            } else {
                controls
            }
        }
        .frame(height: Self.height)
        .foregroundStyle(CityMVPStyle.ink)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            action("magnifyingglass", title: "搜尋 Search", action: onSearch)
            GeometryReader { geometry in
                ZStack {
                    // A single lens travels over a fixed track. The glyphs grow
                    // continuously under it instead of swapping selected circles.
                    CityMVPDockLens(position: position, isDragging: dragPosition != nil,
                                    reduceMotion: reduceMotion)
                        .animation(reduceMotion || dragPosition != nil ? nil : CityMVPDockMotion.settle,
                                   value: position)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    HStack(spacing: 0) {
                        destination(.home, index: 0, english: "Saved", chinese: "收藏")
                        destination(.map, index: 1, english: "Map", chinese: "地圖")
                        destination(.profile, index: 2, english: "Passport", chinese: "護照")
                    }
                }
                .contentShape(Capsule())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .updating($dragPosition) { value, position, _ in
                            position = boundedPosition(value.location.x, width: geometry.size.width)
                        }
                        .onEnded { value in
                            let index = Int(boundedPosition(value.location.x, width: geometry.size.width).rounded())
                            onSelect(Self.destinations[index])
                        }
                )
            }
            .frame(height: Self.height)
            action("plus", title: "新增收藏 Add place", action: onCapture)
        }
    }

    private func boundedPosition(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(2, max(0, x / max(1, width / 3) - 0.5))
    }

    private func destination(_ tab: SaveRootTab, index: Int, english: String, chinese: String) -> some View {
        let active = selectedIndex == index
        return Button { onSelect(tab) } label: {
            // Visual glyphs belong to the lens's common animation clock. Keep
            // these native buttons independent for VoiceOver and full-size hits.
            Color.clear.frame(maxWidth: .infinity).frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.localized(english: english, traditionalChinese: chinese))
        .accessibilityIdentifier("cityMVP.tab.\(english.lowercased())")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func action(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium))
                .frame(width: 60, height: 60)
                .contentShape(Circle())
                .modifier(CityMVPDockGlass(shape: Circle(), tint: .clear))
        }
        .buttonStyle(CityMVPDockPressStyle()).accessibilityLabel(title)
    }
}

private enum CityMVPDockMotion {
    static let settle = Animation.spring(response: 0.26, dampingFraction: 0.82)
}

/// One animatable value drives the lens, magnification and emphasis together.
private struct CityMVPDockLens: View, Animatable {
    var position: CGFloat
    let isDragging: Bool
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let slot = geometry.size.width / 3
            let center = slot * (position + 0.5)
            ZStack {
                Capsule().fill(reduceTransparency ? AnyShapeStyle(CityMVPStyle.surface) : AnyShapeStyle(.thinMaterial))
                    .overlay(Capsule().fill(CityMVPStyle.panel.opacity(0.5)))
                    .overlay(Capsule().strokeBorder(CityMVPStyle.rim.opacity(0.65), lineWidth: 1))
                    .frame(height: 60)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                glyphs
                // Glass samples siblings behind it. Put the sharp magnified
                // glyphs inside its foreground content, not behind its filter.
                glyphs
                    .frame(width: geometry.size.width, height: 72)
                    .offset(x: geometry.size.width / 2 - center)
                    .frame(width: max(44, slot - 4), height: 66)
                    .clipped()
                    .modifier(CityMVPDockGlass(shape: Capsule(), tint: CityMVPStyle.selected.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.08), .white.opacity(0.38)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: .white.opacity(isDragging ? 0.55 : 0.25), radius: 5)
                    .shadow(color: CityMVPStyle.blue.opacity(isDragging ? 0.35 : 0.20),
                            radius: isDragging ? 14 : 9)
                    .scaleEffect(x: isDragging && !reduceMotion ? 1.06 : 1,
                                 y: isDragging && !reduceMotion ? 1.04 : 1)
                    .animation(reduceMotion ? nil : CityMVPDockMotion.settle, value: isDragging)
                    .position(x: center, y: 36)
            }
            .frame(height: 72)
        }
    }

    private var glyphs: some View {
        HStack(spacing: 0) {
            glyph("tray.fill", index: 0)
            glyph("globe", index: 1)
            glyph("book.closed.fill", index: 2)
        }
    }

    private func glyph(_ symbol: String, index: Int) -> some View {
        let proximity = max(0, 1 - abs(position - CGFloat(index)))
        return Image(systemName: symbol)
            .font(.system(size: 25, weight: .medium))
            .foregroundStyle(CityMVPStyle.ink.opacity(0.52 + 0.48 * proximity))
            .scaleEffect(reduceMotion ? 1 : 1 + 0.18 * proximity)
            .offset(y: reduceMotion ? 0 : -1.5 * proximity)
            .frame(maxWidth: .infinity).frame(height: 72)
    }
}

private struct CityMVPDockGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(CityMVPStyle.surface, in: shape)
                .overlay(shape.strokeBorder(CityMVPStyle.rim, lineWidth: 1))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .background(tint, in: shape)
                .overlay(shape.strokeBorder(CityMVPStyle.rim.opacity(0.72), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
    }
}

private struct CityMVPDockPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : CityMVPDockMotion.settle, value: configuration.isPressed)
    }
}
#endif
