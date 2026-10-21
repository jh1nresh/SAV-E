import SwiftUI

enum AtlasMetrics {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
    static let statusBarHeight: CGFloat = 48
}

enum AtlasSpacing {
    static let tight = SaveSpace.tight
    static let compact = SaveSpace.xs
    static let control = SaveSpace.sm
    static let content = SaveSpace.md
    static let section = SaveSpace.lg
}

enum AtlasElevation {
    static let cardOpacity = 0.09
    static let cardRadius: CGFloat = 12
    static let cardY: CGFloat = 5
}

// Adaptive tokens. The light column stays the locked production hexes
// Color(atlasHex: 0xFFF9EB) / 0x0E4A33 / 0xE95C3A / 0xB5E3F5 / 0x2F2E23 /
// 0x62594F / 0xD6E8C4 / 0xE3D6F7 / 0xEADDC6 / 0xF0E3CA / 0xFFCC4F / 0xDCCFB9.
// Home and Passport sit inside `ReferenceViewport`, which paints `canvas`,
// so a light-only mirror made dark-mode captures render cream.
enum AtlasPalette {
    static let canvas = SaveAtlasPalette.canvas
    static let paper = SaveAtlasPalette.paper
    static let forest = SaveAtlasPalette.forest
    static let ink = SaveAtlasPalette.ink
    static let muted = SaveAtlasPalette.muted
    static let cream = SaveAtlasPalette.cream
    static let coral = SaveAtlasPalette.coral
    static let coralStrong = SaveAtlasPalette.coralStrong
    static let brandCoral = SaveAtlasPalette.brandCoral
    static let mint = SaveAtlasPalette.mint
    static let sky = SaveAtlasPalette.sky
    static let lavender = SaveAtlasPalette.lavender
    static let kraft = SaveAtlasPalette.kraft
    static let kraftLight = SaveAtlasPalette.kraftLight
    static let honey = SaveAtlasPalette.honey
    /// Prototype-only route stroke; no production twin.
    static let routeInk = Color(atlasHex: 0x403B33)
    static let stroke = SaveAtlasPalette.stroke
    static let line = stroke
    static let cardRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 1
}

private extension Color {
    init(atlasHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum AtlasType {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func strong(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func regular(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func editorial(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .rounded).italic()
    }
}

struct ReferenceViewport<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / AtlasMetrics.width,
                proxy.size.height / AtlasMetrics.height
            )

            content()
                .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
                .background(AtlasPalette.canvas)
        }
        .ignoresSafeArea()
    }
}

struct AtlasCanvas: View {
    var body: some View {
        SaveDottedBackground()
            .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
            .allowsHitTesting(false)
    }
}

extension View {
    func atlasPaper(
        radius: CGFloat,
        border: Color = AtlasPalette.line.opacity(0.28),
        shadow: Bool = false
    ) -> some View {
        background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(
                color: shadow ? AtlasPalette.ink.opacity(AtlasElevation.cardOpacity) : .clear,
                radius: shadow ? AtlasElevation.cardRadius : 0,
                y: shadow ? AtlasElevation.cardY : 0
            )
    }

    func atlasCardShadow() -> some View {
        shadow(
            color: AtlasPalette.ink.opacity(AtlasElevation.cardOpacity),
            radius: AtlasElevation.cardRadius,
            y: AtlasElevation.cardY
        )
    }

    func placed(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
    }
}
