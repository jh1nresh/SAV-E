import SwiftUI

enum AtlasMetrics {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
    static let statusBarHeight: CGFloat = 48
}

// Light-only mirror of the production light column in `SaveAtlasPalette`
// (SAV-E/Extensions/Color+Theme.swift). Per DESIGN.md, production wins on
// any mismatch — keep these hex values byte-identical to production.
enum AtlasPalette {
    static let canvas = Color(atlasHex: 0xFFF8EE)
    static let paper = Color(atlasHex: 0xFFFDF7)
    static let forest = Color(atlasHex: 0x174E37)
    static let ink = Color(atlasHex: 0x3F281A)
    static let muted = Color(atlasHex: 0x80664F)
    static let coral = Color(atlasHex: 0xF27D5C)
    static let mint = Color(atlasHex: 0xD9EACB)
    static let sky = Color(atlasHex: 0xCDEDF4)
    static let lavender = Color(atlasHex: 0xE8DEF7)
    static let kraft = Color(atlasHex: 0xEFD0A5)
    static let honey = Color(atlasHex: 0xFFCC4F)
    /// Prototype-only route stroke; no production twin.
    static let routeInk = Color(atlasHex: 0x4D4339)
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
        .custom("AvenirNextCondensed-DemiBold", size: size)
    }

    static func strong(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-Bold", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-Medium", size: size)
    }

    static func regular(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-Regular", size: size)
    }

    static func editorial(_ size: CGFloat) -> Font {
        .custom("Georgia-Italic", size: size)
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
                color: shadow ? AtlasPalette.ink.opacity(0.075) : .clear,
                radius: shadow ? 7 : 0,
                y: shadow ? 3 : 0
            )
    }

    func placed(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
    }
}
