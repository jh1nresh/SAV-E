import SwiftUI

enum AtlasMetrics {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
    static let statusBarHeight: CGFloat = 48
}

enum AtlasPalette {
    static let canvas = Color(red: 0.992, green: 0.973, blue: 0.953)
    static let paper = Color(red: 1.00, green: 0.992, blue: 0.969)
    static let forest = Color(red: 0.055, green: 0.29, blue: 0.20)
    static let ink = Color(red: 0.18, green: 0.13, blue: 0.09)
    static let muted = Color(red: 0.38, green: 0.35, blue: 0.31)
    static let coral = Color(red: 0.949, green: 0.42, blue: 0.29)
    static let mint = Color(red: 0.84, green: 0.91, blue: 0.77)
    static let sky = Color(red: 0.71, green: 0.89, blue: 0.96)
    static let lavender = Color(red: 0.89, green: 0.84, blue: 0.97)
    static let kraft = Color(red: 0.94, green: 0.81, blue: 0.63)
    static let honey = Color(red: 1.00, green: 0.80, blue: 0.31)
    static let routeInk = Color(red: 0.25, green: 0.23, blue: 0.20)
    static let line = Color(red: 0.65, green: 0.56, blue: 0.47)
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
