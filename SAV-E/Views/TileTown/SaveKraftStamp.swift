import SwiftUI
import UIKit

/// One Map Stamp language for Home recent stamps and the Passport grid.
///
/// Two sizes of the same system, not two styles:
/// - Home recent: photo face + name
/// - Passport grid: photo or category glyph + name; locked slots show `???`
enum SaveKraftStampSize {
    case recent
    case grid

    var face: CGFloat {
        switch self {
        case .recent: return 52
        case .grid: return 72
        }
    }

    var title: CGFloat {
        switch self {
        case .recent: return 11
        case .grid: return 12
        }
    }
}

enum SaveKraftStampFace: Equatable {
    case photo(URL?)
    case glyph(String)
    case scene(SaveKraftStampScene)
    case locked
}

enum SaveKraftStampScene: String, CaseIterable {
    case harbor, pine, maple, cafe, mountain, lake, house

    static func from(name: String, category: String = "") -> SaveKraftStampScene {
        let haystack = "\(name) \(category)".lowercased()
        if haystack.contains("harbor") || haystack.contains("sea") || haystack.contains("水") { return .harbor }
        if haystack.contains("pine") || haystack.contains("forest") || haystack.contains("松") { return .pine }
        if haystack.contains("maple") || haystack.contains("autumn") || haystack.contains("楓") { return .maple }
        if haystack.contains("cafe") || haystack.contains("coffee") || haystack.contains("咖啡") { return .cafe }
        if haystack.contains("peak") || haystack.contains("mountain") || haystack.contains("山") { return .mountain }
        if haystack.contains("lake") || haystack.contains("mist") || haystack.contains("湖") { return .lake }
        var hasher = Hasher()
        hasher.combine(name)
        let index = abs(hasher.finalize()) % (allCases.count - 1)
        return allCases[index]
    }
}

struct SaveKraftStamp: View {
    let title: String
    let face: SaveKraftStampFace
    var size: SaveKraftStampSize = .grid
    var accessibilityIdentifier: String = "stamp.kraft"

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                    .fill(SaveAtlasPalette.paper)
                    .overlay {
                        SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                            .stroke(SaveAtlasPalette.kraft.opacity(0.86), lineWidth: 1.2)
                    }
                    .shadow(color: SaveAtlasPalette.ink.opacity(0.06), radius: 2, y: 1)

                SaveKraftStampFaceView(face: illustratedFace, glyph: fallbackGlyph)
                    .padding(5)
            }
            .frame(width: size.face, height: size.face)
            .accessibilityHidden(true)

            Text(visibleTitle)
                .font(SaveAtlasType.strong(size.title))
                .foregroundStyle(face == .locked ? SaveAtlasPalette.muted : SaveAtlasPalette.forest)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: size.face + 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(face == .locked ? "Locked stamp" : "Map Stamp, \(visibleTitle)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var visibleTitle: String {
        if case .locked = face { return "???" }
        return SaveSoftPixelAccentsLock.visibleStampText(title) ?? "Map Stamp"
    }

    private var fallbackGlyph: String {
        if case .glyph(let name) = face { return name }
        return "seal"
    }

    private var illustratedFace: SaveKraftStampFace {
        switch face {
        case .photo(let url) where url != nil:
            return face
        case .locked:
            return .locked
        case .scene:
            return face
        default:
            return .scene(SaveKraftStampScene.from(name: title))
        }
    }
}

struct SaveKraftStampFaceView: View {
    let face: SaveKraftStampFace
    var glyph: String = "seal"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SaveAtlasPalette.kraft.opacity(0.28))
            switch face {
            case .photo(let url):
                if let url {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            SaveKraftStampPixelArt(scene: SaveKraftStampScene.from(name: glyph))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    SaveKraftStampPixelArt(scene: SaveKraftStampScene.from(name: glyph))
                }
            case .glyph:
                SaveKraftStampPixelArt(scene: SaveKraftStampScene.from(name: glyph))
            case .scene(let scene):
                SaveKraftStampPixelArt(scene: scene)
            case .locked:
                Text("???")
                    .font(SaveAtlasType.strong(16))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}

/// 16×16 illustrated stamp faces, scaled with nearest-neighbor.
struct SaveKraftStampPixelArt: View {
    let scene: SaveKraftStampScene

    var body: some View {
        Image(uiImage: Self.image(for: scene))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private static func image(for scene: SaveKraftStampScene) -> UIImage {
        let cells = pixels(for: scene)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            for row in 0..<16 {
                for column in 0..<16 {
                    cg.setFillColor(cells[row][column].cgColor)
                    cg.fill(CGRect(x: column, y: row, width: 1, height: 1))
                }
            }
        }
    }

    private static func pixels(for scene: SaveKraftStampScene) -> [[UIColor]] {
        let paper = UIColor(red: 1, green: 0.973, blue: 0.910, alpha: 1)
        let grass = UIColor(red: 0.561, green: 0.749, blue: 0.416, alpha: 1)
        let water = UIColor(red: 0.494, green: 0.784, blue: 0.890, alpha: 1)
        let deep = UIColor(red: 0.310, green: 0.541, blue: 0.227, alpha: 1)
        let coral = UIColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1)
        let honey = UIColor(red: 0.910, green: 0.722, blue: 0.427, alpha: 1)
        let sky = UIColor(red: 0.494, green: 0.714, blue: 0.831, alpha: 1)
        let wall = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        let trunk = UIColor(red: 0.48, green: 0.33, blue: 0.20, alpha: 1)
        var grid = Array(repeating: Array(repeating: paper, count: 16), count: 16)
        func plot(_ x: Int, _ y: Int, _ color: UIColor) {
            guard (0..<16).contains(x), (0..<16).contains(y) else { return }
            grid[y][x] = color
        }
        func fill(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>, _ color: UIColor) {
            for y in ys { for x in xs { plot(x, y, color) } }
        }
        fill(0...15, 11...15, grass)
        switch scene {
        case .harbor:
            fill(8...15, 8...15, water)
            fill(3...7, 6...7, coral)
            fill(2...8, 8...10, wall)
            plot(5, 9, trunk)
        case .pine:
            fill(6...9, 4...5, deep)
            fill(5...10, 6...8, deep)
            fill(4...11, 9...10, deep)
            fill(7...8, 11...14, trunk)
        case .maple:
            fill(5...10, 4...6, coral)
            fill(4...11, 7...9, honey)
            fill(7...8, 10...14, trunk)
        case .cafe:
            fill(3...12, 5...6, coral)
            fill(3...12, 7...12, wall)
            fill(6...9, 9...12, trunk)
            plot(5, 8, sky)
            plot(10, 8, sky)
        case .mountain:
            fill(2...6, 8...10, sky)
            fill(7...13, 6...10, honey)
            fill(0...15, 11...15, grass)
        case .lake:
            fill(2...13, 8...13, water)
            fill(6...9, 5...7, deep)
        case .house:
            fill(5...10, 5...6, honey)
            fill(4...11, 7...12, wall)
            plot(7, 9, sky)
            plot(8, 11, trunk)
        }
        return grid
    }
}

/// Quiet 8×8 nearest-neighbor glyphs. Visible 44pt buttons, not SF Symbols.
enum SavePixelChromeIconKind: Equatable {
    case trips
    case saves
    case more
    case home
    case map
    case plus
    case friends
    case passport

    static func tab(iconName: String) -> SavePixelChromeIconKind {
        switch iconName {
        case "house": return .home
        case "map": return .map
        case "plus": return .plus
        case "person.2": return .friends
        case "book.closed": return .passport
        default: return .more
        }
    }
}

struct SavePixelChromeIcon: View {
    let kind: SavePixelChromeIconKind
    var pointSize: CGFloat = 16

    var body: some View {
        Image(uiImage: Self.image(for: kind, pointSize: pointSize))
            .renderingMode(.template)
            .interpolation(.none)
            .frame(width: pointSize, height: pointSize)
            .accessibilityHidden(true)
    }

    private static func bits(for kind: SavePixelChromeIconKind) -> [String] {
        switch kind {
        case .trips:
            return [
                "00100100",
                "01011010",
                "10000001",
                "01011010",
                "00100100",
                "00100100",
                "01111110",
                "00100100",
            ]
        case .saves:
            return [
                "01111110",
                "01000010",
                "01011010",
                "01011010",
                "01000010",
                "01011010",
                "01100110",
                "01111110",
            ]
        case .more:
            return [
                "00000000",
                "00000000",
                "00000000",
                "01010100",
                "01010100",
                "00000000",
                "00000000",
                "00000000",
            ]
        case .home:
            return [
                "00011000",
                "00111100",
                "01111110",
                "11000011",
                "10111101",
                "10100101",
                "10100101",
                "11111111",
            ]
        case .map:
            return [
                "01111110",
                "10000001",
                "10111101",
                "10000001",
                "10111101",
                "10000001",
                "10111101",
                "01111110",
            ]
        case .plus:
            return [
                "00011000",
                "00011000",
                "00011000",
                "11111111",
                "11111111",
                "00011000",
                "00011000",
                "00011000",
            ]
        case .friends:
            return [
                "01100110",
                "01100110",
                "00000000",
                "11100111",
                "10011001",
                "00011000",
                "00111100",
                "01111110",
            ]
        case .passport:
            return [
                "01111110",
                "01000010",
                "01011010",
                "01000010",
                "01011110",
                "01000010",
                "01111110",
                "00111100",
            ]
        }
    }

    private static func image(for kind: SavePixelChromeIconKind, pointSize: CGFloat) -> UIImage {
        let rows = bits(for: kind)
        let unit = max(1, Int(pointSize / 8))
        let edge = 8 * unit
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            cg.setFillColor(UIColor.black.cgColor)
            for (row, line) in rows.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    cg.fill(CGRect(x: column * unit, y: row * unit, width: unit, height: unit))
                }
            }
        }
    }
}

/// Stable pen contours: asymmetry is drawn into the path, never randomized
/// while rendering, so controls do not shimmer or move under a finger.
nonisolated struct SaveDoodleInkOval: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        }
        p.move(to: point(0.49, 0.015))
        p.addCurve(to: point(0.985, 0.50), control1: point(0.77, -0.01), control2: point(1.01, 0.23))
        p.addCurve(to: point(0.51, 0.985), control1: point(0.99, 0.78), control2: point(0.78, 1.01))
        p.addCurve(to: point(0.015, 0.51), control1: point(0.23, 1.00), control2: point(-0.01, 0.78))
        p.addCurve(to: point(0.49, 0.015), control1: point(0.00, 0.24), control2: point(0.22, 0.01))
        p.closeSubpath()
        return p
    }
}

/// A pill follows the same pen stroke as a seal, with full semicircular ends.
nonisolated struct SaveDoodleInkCapsule: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        let radius = min(r.width, r.height) / 2
        let left = r.minX + radius
        let right = r.maxX - radius
        let y = r.midY
        var p = Path()
        p.move(to: CGPoint(x: left, y: r.minY + 0.3))
        p.addQuadCurve(to: CGPoint(x: right, y: r.minY + 0.1), control: CGPoint(x: r.midX, y: r.minY - 0.4))
        p.addCurve(to: CGPoint(x: r.maxX - 0.2, y: y),
                   control1: CGPoint(x: right + radius * 0.56, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: y - radius * 0.55))
        p.addCurve(to: CGPoint(x: right, y: r.maxY - 0.2),
                   control1: CGPoint(x: r.maxX + 0.2, y: y + radius * 0.55),
                   control2: CGPoint(x: right + radius * 0.55, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: left, y: r.maxY), control: CGPoint(x: r.midX, y: r.maxY + 0.4))
        p.addCurve(to: CGPoint(x: r.minX + 0.1, y: y),
                   control1: CGPoint(x: left - radius * 0.56, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: y + radius * 0.54))
        p.addCurve(to: CGPoint(x: left, y: r.minY + 0.3),
                   control1: CGPoint(x: r.minX - 0.1, y: y - radius * 0.55),
                   control2: CGPoint(x: left - radius * 0.54, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Four gently cut edges rather than a regular rounded card or a wavy ribbon.
/// All ink remains inside the original 44pt collection hit target.
nonisolated struct SaveDoodlePaperStrip: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1.5, dy: 1.5)
        var p = Path()
        let horizontal = max(1, Int(r.width / 6))
        let vertical = max(1, Int(r.height / 6))
        let dx = r.width / CGFloat(horizontal)
        let dy = r.height / CGFloat(vertical)
        p.move(to: CGPoint(x: r.minX + 1, y: r.minY + 1))
        for i in 0..<horizontal {
            let x = r.minX + CGFloat(i) * dx
            let edge = i.isMultiple(of: 3) ? 0.2 : 0.8
            p.addQuadCurve(to: CGPoint(x: x + dx, y: r.minY + edge),
                           control: CGPoint(x: x + dx * 0.5, y: r.minY + 2.3))
        }
        for i in 0..<vertical {
            let y = r.minY + CGFloat(i) * dy
            p.addQuadCurve(to: CGPoint(x: r.maxX - 0.5, y: y + dy),
                           control: CGPoint(x: r.maxX - 2.3, y: y + dy * 0.5))
        }
        for i in 0..<horizontal {
            let x = r.maxX - CGFloat(i) * dx
            let edge = i.isMultiple(of: 3) ? 0.3 : 0.8
            p.addQuadCurve(to: CGPoint(x: x - dx, y: r.maxY - edge),
                           control: CGPoint(x: x - dx * 0.5, y: r.maxY - 2.3))
        }
        for i in 0..<vertical {
            let y = r.maxY - CGFloat(i) * dy
            p.addQuadCurve(to: CGPoint(x: r.minX + 0.5, y: y - dy),
                           control: CGPoint(x: r.minX + 2.3, y: y - dy * 0.5))
        }
        p.closeSubpath()
        return p
    }
}

/// Category ink inside a visit seal. These are marks, separate from place art.
nonisolated struct SaveDoodleCategorySeal: Shape {
    let category: PlaceCategory

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        func line(_ x: CGFloat, _ y: CGFloat, _ endX: CGFloat, _ endY: CGFloat) {
            p.move(to: point(x, y))
            p.addQuadCurve(to: point(endX, endY), control: point((x + endX) / 2 + 0.015, (y + endY) / 2))
        }
        switch category {
        case .food:
            p.move(to: point(0.08, 0.48))
            p.addQuadCurve(to: point(0.92, 0.47), control: point(0.50, 0.60))
            p.addCurve(to: point(0.12, 0.49), control1: point(0.80, 1.12), control2: point(0.24, 1.03))
            line(0.34, 0.91, 0.68, 0.91)
            line(0.39, 0.08, 0.50, 0.42)
            line(0.66, 0.05, 0.58, 0.42)
        case .cafe:
            p.move(to: point(0.12, 0.39))
            p.addQuadCurve(to: point(0.71, 0.40), control: point(0.43, 0.46))
            p.addCurve(to: point(0.18, 0.40), control1: point(0.74, 1.00), control2: point(0.17, 0.97))
            p.move(to: point(0.74, 0.46))
            p.addCurve(to: point(0.72, 0.72), control1: point(1.04, 0.33), control2: point(1.02, 0.84))
            p.move(to: point(0.05, 0.91))
            p.addQuadCurve(to: point(0.91, 0.91), control: point(0.48, 1.02))
            p.move(to: point(0.42, 0.28))
            p.addCurve(to: point(0.43, 0.02), control1: point(0.23, 0.18), control2: point(0.60, 0.13))
        case .bar:
            p.move(to: point(0.24, 0.06))
            p.addLine(to: point(0.76, 0.07))
            p.addCurve(to: point(0.24, 0.06), control1: point(0.86, 0.80), control2: point(0.16, 0.83))
            line(0.26, 0.32, 0.74, 0.32)
            line(0.50, 0.59, 0.51, 0.92)
            line(0.30, 0.94, 0.72, 0.94)
        case .attraction:
            p.move(to: point(0.06, 0.35))
            p.addQuadCurve(to: point(0.48, 0.07), control: point(0.37, 0.27))
            p.addQuadCurve(to: point(0.94, 0.35), control: point(0.68, 0.29))
            line(0.08, 0.38, 0.93, 0.39)
            line(0.20, 0.43, 0.20, 0.87)
            line(0.49, 0.44, 0.50, 0.87)
            line(0.80, 0.43, 0.80, 0.87)
            line(0.09, 0.92, 0.93, 0.92)
        case .stay:
            p.move(to: point(0.09, 0.40))
            p.addLine(to: point(0.49, 0.08))
            p.addLine(to: point(0.92, 0.41))
            line(0.20, 0.34, 0.20, 0.92)
            line(0.20, 0.92, 0.82, 0.91)
            line(0.81, 0.35, 0.82, 0.91)
            p.move(to: point(0.40, 0.90))
            p.addLine(to: point(0.40, 0.58))
            p.addLine(to: point(0.62, 0.58))
            p.addLine(to: point(0.62, 0.91))
        case .shopping:
            p.move(to: point(0.18, 0.33))
            p.addLine(to: point(0.82, 0.34))
            p.addLine(to: point(0.88, 0.92))
            p.addQuadCurve(to: point(0.12, 0.92), control: point(0.50, 1.00))
            p.closeSubpath()
            p.move(to: point(0.34, 0.42))
            p.addCurve(to: point(0.68, 0.42), control1: point(0.27, -0.10), control2: point(0.73, -0.09))
        }
        return p
    }
}

struct SaveDoodleNumberPin: View {
    let number: Int
    let visited: Bool

    var body: some View {
        let ink = visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral
        ZStack(alignment: .top) {
            SaveDoodlePinOutline().fill(SaveAtlasPalette.paper)
            SaveDoodlePinOutline().stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            Text("\(number)")
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(ink)
                .frame(width: 24, height: 23)
        }
        .frame(width: 24, height: 32)
        .accessibilityHidden(true)
    }
}

nonisolated struct SaveDoodlePinOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        p.move(to: point(0.51, 0.97))
        p.addCurve(to: point(0.05, 0.36), control1: point(0.35, 0.77), control2: point(0.05, 0.60))
        p.addCurve(to: point(0.49, 0.04), control1: point(0.03, 0.16), control2: point(0.23, 0.03))
        p.addCurve(to: point(0.95, 0.35), control1: point(0.77, 0.02), control2: point(0.96, 0.15))
        p.addCurve(to: point(0.51, 0.97), control1: point(0.98, 0.58), control2: point(0.65, 0.81))
        p.closeSubpath()
        return p
    }
}

/// Hand-drawn 24pt template tab icons. Coral when selected, muted when idle.
/// Stroke is 1.5pt; the tab bar supplies the template color.
enum SaveDoodleTabIconKind: Equatable {
    case home
    case map
    case plus
    case friends
    case passport

    static func tab(iconName: String) -> SaveDoodleTabIconKind {
        switch iconName {
        case "house": return .home
        case "map": return .map
        case "plus": return .plus
        case "person.2": return .friends
        case "book.closed": return .passport
        default: return .home
        }
    }
}

struct SaveDoodleTabIcon: View {
    let kind: SaveDoodleTabIconKind
    var pointSize: CGFloat = 24

    var body: some View {
        SaveDoodleTabIconShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: pointSize, height: pointSize)
            .accessibilityHidden(true)
    }
}

nonisolated struct SaveDoodleTabIconShape: Shape {
    let kind: SaveDoodleTabIconKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Deliberate, sub-point pen bends keep each icon legible at 24pt.
        func penLine(to end: CGPoint) {
            let start = path.currentPoint ?? end
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(1, hypot(dx, dy))
            path.addQuadCurve(to: end, control: CGPoint(
                x: (start.x + end.x) / 2 - dy / length * 0.45,
                y: (start.y + end.y) / 2 + dx / length * 0.45
            ))
        }
        switch kind {
        case .home:
            path.move(to: CGPoint(x: w * 0.12, y: h * 0.48))
            penLine(to: CGPoint(x: w * 0.50, y: h * 0.14))
            penLine(to: CGPoint(x: w * 0.88, y: h * 0.48))
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.42))
            penLine(to: CGPoint(x: w * 0.22, y: h * 0.86))
            penLine(to: CGPoint(x: w * 0.78, y: h * 0.86))
            penLine(to: CGPoint(x: w * 0.78, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.42, y: h * 0.86))
            penLine(to: CGPoint(x: w * 0.42, y: h * 0.62))
            penLine(to: CGPoint(x: w * 0.58, y: h * 0.62))
            penLine(to: CGPoint(x: w * 0.58, y: h * 0.86))
        case .map:
            path.move(to: CGPoint(x: w * 0.14, y: h * 0.28))
            penLine(to: CGPoint(x: w * 0.38, y: h * 0.18))
            penLine(to: CGPoint(x: w * 0.62, y: h * 0.30))
            penLine(to: CGPoint(x: w * 0.86, y: h * 0.20))
            penLine(to: CGPoint(x: w * 0.86, y: h * 0.72))
            penLine(to: CGPoint(x: w * 0.62, y: h * 0.82))
            penLine(to: CGPoint(x: w * 0.38, y: h * 0.70))
            penLine(to: CGPoint(x: w * 0.14, y: h * 0.80))
            path.closeSubpath()
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.18))
            penLine(to: CGPoint(x: w * 0.38, y: h * 0.70))
            path.move(to: CGPoint(x: w * 0.62, y: h * 0.30))
            penLine(to: CGPoint(x: w * 0.62, y: h * 0.82))
        case .plus:
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.16))
            penLine(to: CGPoint(x: w * 0.50, y: h * 0.84))
            path.move(to: CGPoint(x: w * 0.16, y: h * 0.50))
            penLine(to: CGPoint(x: w * 0.84, y: h * 0.50))
        case .friends:
            path.addPath(SaveDoodleInkOval().path(in: CGRect(x: w * 0.13, y: h * 0.09, width: w * 0.34, height: h * 0.34)))
            path.addPath(SaveDoodleInkOval().path(in: CGRect(x: w * 0.49, y: h * 0.13, width: w * 0.32, height: h * 0.32)))
            path.move(to: CGPoint(x: w * 0.10, y: h * 0.82))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.82),
                control: CGPoint(x: w * 0.30, y: h * 0.46)
            )
            path.move(to: CGPoint(x: w * 0.46, y: h * 0.86))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.90, y: h * 0.86),
                control: CGPoint(x: w * 0.70, y: h * 0.52)
            )
        case .passport:
            path.addRoundedRect(
                in: CGRect(x: w * 0.22, y: h * 0.10, width: w * 0.56, height: h * 0.80),
                cornerSize: CGSize(width: w * 0.08, height: h * 0.08)
            )
            path.move(to: CGPoint(x: w * 0.34, y: h * 0.10))
            penLine(to: CGPoint(x: w * 0.34, y: h * 0.90))
            path.addEllipse(in: CGRect(x: w * 0.46, y: h * 0.36, width: w * 0.22, height: h * 0.22))
        }
        return path
    }
}

/// Caveat (Latin) + Iansui (CJK subset) for Savvy and page titles.
/// Stamp names stay `SaveAtlasType` until the shared stamp PR. Body copy stays SF.
struct SaveDisplayTitle: View {
    let text: String
    var pointSize: CGFloat = 22
    var relativeTo: Font.TextStyle = .title
    /// Home wordmark (34) and city (20) lock the spec point size.
    var locksPointSize: Bool = false

    var body: some View {
        Text(text)
            .font(
                locksPointSize
                    ? SaveDisplayType.fixed(pointSize)
                    : SaveDisplayType.display(pointSize, relativeTo: relativeTo)
            )
            .foregroundStyle(SaveAtlasPalette.forest)
            .lineLimit(2)
            .minimumScaleFactor(locksPointSize ? 1 : 0.75)
            .fixedSize(horizontal: locksPointSize, vertical: locksPointSize)
    }
}
