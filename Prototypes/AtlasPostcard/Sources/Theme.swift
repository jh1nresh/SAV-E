import SwiftUI

enum AtlasPalette {
    static let canvas = Color(red: 1.00, green: 0.973, blue: 0.933)
    static let paper = Color(red: 1.00, green: 0.992, blue: 0.969)
    static let forest = Color(red: 0.09, green: 0.306, blue: 0.216)
    static let ink = Color(red: 0.247, green: 0.157, blue: 0.102)
    static let muted = Color(red: 0.502, green: 0.40, blue: 0.31)
    static let coral = Color(red: 0.949, green: 0.49, blue: 0.361)
    static let mint = Color(red: 0.851, green: 0.918, blue: 0.796)
    static let sky = Color(red: 0.804, green: 0.929, blue: 0.957)
    static let lavender = Color(red: 0.91, green: 0.871, blue: 0.969)
    static let kraft = Color(red: 0.937, green: 0.816, blue: 0.647)
    static let honey = Color(red: 0.992, green: 0.835, blue: 0.47)
    static let water = Color(red: 0.70, green: 0.89, blue: 0.94)
    static let leaf = Color(red: 0.75, green: 0.89, blue: 0.68)
    static let routeInk = Color(red: 0.302, green: 0.263, blue: 0.224)
}

extension View {
    func atlasPaper(
        radius: CGFloat = 18,
        border: Color = AtlasPalette.ink.opacity(0.20),
        shadow: Bool = false
    ) -> some View {
        self
            .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(
                color: shadow ? AtlasPalette.ink.opacity(0.07) : .clear,
                radius: shadow ? 12 : 0,
                y: shadow ? 5 : 0
            )
    }
}

struct DottedCanvas: View {
    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2))
            for x in stride(from: 12.0, through: size.width, by: 24) {
                for y in stride(from: 12.0, through: size.height, by: 24) {
                    context.translateBy(x: x, y: y)
                    context.fill(dot, with: .color(AtlasPalette.ink.opacity(0.055)))
                    context.translateBy(x: -x, y: -y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
