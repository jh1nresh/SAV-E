import SwiftUI

enum AtlasMetrics {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
    static let statusBarHeight: CGFloat = 48
}

enum AtlasSpacing {
    static let tight: CGFloat = 4
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let content: CGFloat = 16
    static let section: CGFloat = 24
}

enum AtlasElevation {
    static let cardOpacity = 0.09
    static let cardRadius: CGFloat = 12
    static let cardY: CGFloat = 5
}

// Light-only mirror of the production light column in `SaveAtlasPalette`
// (SAV-E/Extensions/Color+Theme.swift). Per DESIGN.md, production wins on
// any mismatch — keep these hex values byte-identical to production.
enum AtlasPalette {
    static let canvas = Color(atlasHex: 0xFDF8F3)
    static let paper = Color(atlasHex: 0xFFFDF7)
    static let forest = Color(atlasHex: 0x0E4A33)
    static let ink = Color(atlasHex: 0x2E2117)
    static let muted = Color(atlasHex: 0x62594F)
    static let coral = Color(atlasHex: 0xF26B4A)
    static let mint = Color(atlasHex: 0xD6E8C4)
    static let sky = Color(atlasHex: 0xB5E3F5)
    static let lavender = Color(atlasHex: 0xE3D6F7)
    static let kraft = Color(atlasHex: 0xF0CFA1)
    static let honey = Color(atlasHex: 0xFFCC4F)
    /// Prototype-only route stroke; no production twin.
    static let routeInk = Color(atlasHex: 0x403B33)
    static let line = Color(atlasHex: 0xA68F78)
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
        ZStack {
            AtlasPalette.canvas
            Image("PaperTexture")
                .resizable(resizingMode: .tile)
                .opacity(0.04)
        }
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
