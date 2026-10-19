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

struct SavePostageSealAvatar: View {
    var name: String
    var systemImage: String = "person.fill"
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            SavePostcardSealShape()
                .fill(SaveAtlasPalette.paper)
                .overlay {
                    SavePostcardSealShape()
                        .stroke(SaveAtlasPalette.kraft, lineWidth: 1.4)
                }
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityLabel(name)
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

/// Pixelify Sans (Latin) + Fusion Pixel (CJK) for Savvy and page titles.
/// Stamp names stay `SaveAtlasType` until the shared stamp PR. Body copy stays SF.
struct SavePixelDisplayText: View {
    let text: String
    var pointSize: CGFloat = 22
    var relativeTo: Font.TextStyle = .title

    var body: some View {
        Text(text)
            .font(SavePixelType.display(pointSize, relativeTo: relativeTo))
            .foregroundStyle(SaveAtlasPalette.forest)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }
}

enum SaveFriendLastAt {
    struct Row: Identifiable, Equatable {
        var id: String { authorID }
        let authorID: String
        let authorName: String
        let lastPost: SharedPlacePost
    }

    static func rows(from posts: [SharedPlacePost]) -> [Row] {
        var latest: [String: SharedPlacePost] = [:]
        for post in posts {
            if let existing = latest[post.author_id] {
                if post.shared_at > existing.shared_at {
                    latest[post.author_id] = post
                }
            } else {
                latest[post.author_id] = post
            }
        }
        return latest.values
            .sorted { lhs, rhs in
                if lhs.shared_at != rhs.shared_at { return lhs.shared_at > rhs.shared_at }
                return lhs.author_name.localizedCaseInsensitiveCompare(rhs.author_name) == .orderedAscending
            }
            .map { post in
                Row(authorID: post.author_id, authorName: post.author_name, lastPost: post)
            }
    }
}
