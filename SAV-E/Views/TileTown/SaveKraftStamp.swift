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
    case bar, hotel, restaurant, noodle, shop

    static func from(name: String, category: String = "", detail: String = "") -> SaveKraftStampScene {
        let haystack = "\(name) \(category)".lowercased()
        // Category is existing user data; these are illustrative fallbacks,
        // never a claim about the real building or its surroundings.
        switch category.lowercased() {
        case "bar": return .bar
        case "stay": return .hotel
        case "shopping": return .shop
        case "cafe": return .cafe
        case "food":
            let foodDescription = "\(haystack) \(detail.lowercased())"
            return foodDescription.contains("ramen") || foodDescription.contains("拉麵") ? .noodle : .restaurant
        default: break
        }
        let words = Set(haystack.components(separatedBy: CharacterSet.alphanumerics.inverted))
        if words.contains("hotel") || haystack.contains("飯店") || haystack.contains("旅館") { return .hotel }
        if words.contains("bar") || haystack.contains("酒吧") { return .bar }
        if haystack.contains("harbor") || haystack.contains("sea") || haystack.contains("水") { return .harbor }
        if haystack.contains("pine") || haystack.contains("forest") || haystack.contains("松") { return .pine }
        if haystack.contains("maple") || haystack.contains("autumn") || haystack.contains("楓") { return .maple }
        if haystack.contains("cafe") || haystack.contains("coffee") || haystack.contains("咖啡") { return .cafe }
        if haystack.contains("peak") || haystack.contains("mountain") || haystack.contains("山") { return .mountain }
        if haystack.contains("lake") || haystack.contains("mist") || haystack.contains("湖") { return .lake }
        // Category fallback must stay identical across launches and screenshots.
        return .house
    }
}

struct SaveKraftStamp: View {
    let title: String
    let face: SaveKraftStampFace
    var category: String = ""
    var artworkDetail: String = ""
    var size: SaveKraftStampSize = .grid
    var accessibilityIdentifier: String = "stamp.kraft"
    @Environment(\.appLanguageSettings) private var language
    @ScaledMetric(relativeTo: .body) private var recentWidth: CGFloat = 164

    var body: some View {
        Group {
            if face == .locked {
                VStack(spacing: 8) {
                    Color.clear.aspectRatio(0.82, contentMode: .fit)
                    Color.clear.frame(height: 34)
                }
                .padding(9)
                .overlay {
                    Text("???")
                        .font(SaveAtlasType.strong(30))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            } else if size == .recent {
                HStack(spacing: 6) {
                    artwork
                        .frame(width: 34, height: 44)
                    stampTitle
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(width: recentWidth, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    artwork
                        .aspectRatio(0.82, contentMode: .fit)
                    stampTitle
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
                }
                .padding(9)
                .frame(maxWidth: .infinity)
            }
        }
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 9)
                .fill(SaveAtlasPalette.kraft.opacity(0.42))
                .overlay {
                    SavePostcardScallopedRectangle(depth: 3, pitch: 9)
                        .stroke(SaveAtlasPalette.line.opacity(0.8), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face == .locked
            ? language.localized(english: "Empty stamp slot", traditionalChinese: "空白地圖章欄位")
            : language.localized(english: "Map Stamp, \(visibleTitle)", traditionalChinese: "地圖章，\(visibleTitle)"))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var artwork: some View {
        SaveKraftStampFaceView(face: illustratedFace, glyph: fallbackGlyph, fallbackScene: fallbackScene)
            .clipped()
            .overlay {
                Rectangle().stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var stampTitle: some View {
        Text(visibleTitle)
            .font(SaveAtlasType.strong(size == .recent ? 12 : 14))
            .foregroundStyle(face == .locked ? SaveAtlasPalette.muted : SaveAtlasPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
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
            return .scene(fallbackScene)
        }
    }

    private var fallbackScene: SaveKraftStampScene {
        .from(name: title, category: category, detail: artworkDetail)
    }
}

struct SaveKraftStampFaceView: View {
    let face: SaveKraftStampFace
    var glyph: String = "seal"
    var fallbackScene: SaveKraftStampScene = .house

    var body: some View {
        ZStack {
            Rectangle()
                .fill(SaveAtlasPalette.kraft.opacity(0.28))
            switch face {
            case .photo(let url):
                if let url {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill().savePixelated(cellSize: 2)
                        default:
                            SaveKraftStampPixelArt(scene: fallbackScene)
                        }
                    }
                    .clipShape(Rectangle())
                } else {
                    SaveKraftStampPixelArt(scene: fallbackScene)
                }
            case .glyph:
                SaveKraftStampPixelArt(scene: fallbackScene)
            case .scene(let scene):
                SaveKraftStampPixelArt(scene: scene)
            case .locked:
                Text("???")
                    .font(SaveAtlasType.strong(16))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
        }
        .clipShape(Rectangle())
    }

}

/// 16×16 illustrated stamp faces, scaled with nearest-neighbor.
struct SaveKraftStampPixelArt: View {
    let scene: SaveKraftStampScene

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: Self.image(for: scene))
                .interpolation(.none)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .savePixelated(cellSize: 2)
        }
        .accessibilityHidden(true)
    }

    private static let atlas = UIImage(named: "SavvyStampArtwork")?.cgImage
    private static let illustratedFaces: [SaveKraftStampScene: UIImage] = {
        guard let atlas else { return [:] }
        let order: [SaveKraftStampScene] = [.harbor, .pine, .maple, .mountain, .lake, .cafe]
        let width = atlas.width / 3
        let height = atlas.height / 2
        var faces: [SaveKraftStampScene: UIImage] = [:]
        for (index, scene) in order.enumerated() {
            let rect = CGRect(x: (index % 3) * width, y: (index / 3) * height,
                              width: width, height: height)
            if let cropped = atlas.cropping(to: rect) { faces[scene] = UIImage(cgImage: cropped) }
        }
        if let categories = UIImage(named: "SavvyCategoryStampArtwork")?.cgImage {
            let categoryOrder: [SaveKraftStampScene] = [.bar, .hotel, .restaurant, .noodle, .shop, .house]
            let cellWidth = categories.width / 3
            let cellHeight = categories.height / 2
            for (index, scene) in categoryOrder.enumerated() {
                let rect = CGRect(x: (index % 3) * cellWidth, y: (index / 3) * cellHeight,
                                  width: cellWidth, height: cellHeight)
                if let cropped = categories.cropping(to: rect) { faces[scene] = UIImage(cgImage: cropped) }
            }
        }
        return faces
    }()

    static func image(for scene: SaveKraftStampScene) -> UIImage {
        if let illustration = illustratedFaces[scene] { return illustration }
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
        case .house, .bar, .hotel, .restaurant, .noodle, .shop:
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
    var authorID: String = ""
    var photoURL: URL? = nil
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                .fill(SaveAtlasPalette.kraft.opacity(0.35))
                .overlay {
                    SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                        .stroke(SaveAtlasPalette.line.opacity(0.75), lineWidth: 1)
                }
            Group {
                if let photoURL {
                    CachedAsyncImage(url: photoURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill().savePixelated(cellSize: 2)
                        } else {
                            portrait
                        }
                    }
                } else {
                    portrait
                }
            }
            .frame(width: size - 14, height: size - 14)
            .clipped()
            .savePixelated(cellSize: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityLabel(name)
    }

    private var portrait: some View {
        Image(uiImage: Self.portraitImage(for: authorID.isEmpty ? name : authorID))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
    }

    // Stable fictional artwork selected by opaque identity, not inferred
    // appearance. A supplied author avatar always takes precedence.
    static func portraitIndex(for identity: String) -> Int {
        let hash = identity.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Int((hash ^ (hash >> 16)) % 6)
    }

    static func portraitImage(for identity: String) -> UIImage {
        let index = portraitIndex(for: identity)
        return portraits.indices.contains(index) ? portraits[index] : UIImage(systemName: "person.fill") ?? UIImage()
    }

    private static let portraits: [UIImage] = {
        guard let atlas = UIImage(named: "SavvyFriendPortraits")?.cgImage else { return [] }
        let width = atlas.width / 3
        let height = atlas.height / 2
        return (0..<6).compactMap { index in
            atlas.cropping(to: CGRect(x: (index % 3) * width, y: (index / 3) * height,
                                     width: width, height: height)).map { UIImage(cgImage: $0) }
        }
    }()
}

/// Quiet 8×8 nearest-neighbor header glyphs. Visible 44pt buttons, not SF Symbols.
enum SavePixelChromeIconKind {
    case trips
    case saves
    case more
    case home, map, friends, passport, add

    static func rootSymbol(_ name: String) -> Self {
        switch name {
        case "house": .home
        case "map": .map
        case "person.2": .friends
        case "book.closed": .passport
        case "plus": .add
        default: .more
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
        case .home:
            return ["000001100000", "000011110000", "000110011000", "001100001100", "011000000110", "110000000011", "001000000100", "001001100100", "001001100100", "001001100100", "001111111100", "000000000000"]
        case .map:
            return ["000000000000", "001110001110", "011011011010", "010010110010", "010010010010", "010010010010", "010010010010", "010010010010", "010110010110", "011011011100", "000001110000", "000000000000"]
        case .friends:
            return ["000000000000", "001100011000", "010010100100", "010010100100", "001100011000", "000000000000", "001100011000", "010010100100", "100001000010", "100001000010", "111111111110", "000000000000"]
        case .passport:
            return ["000000000000", "001111111100", "010000000100", "010111100100", "010100100100", "010111100100", "010000000100", "010111100100", "010000000100", "011111111100", "001111111100", "000000000000"]
        case .add:
            return ["000000000000", "000001100000", "000001100000", "000001100000", "000001100000", "011111111110", "011111111110", "000001100000", "000001100000", "000001100000", "000001100000", "000000000000"]
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
        }
    }

    private static func image(for kind: SavePixelChromeIconKind, pointSize: CGFloat) -> UIImage {
        let rows = bits(for: kind)
        let unit = max(1, Int(pointSize / CGFloat(rows.count)))
        let edge = rows.count * unit
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            cg.setFillColor(UIColor(red: 0.18, green: 0.29, blue: 0.20, alpha: 1).cgColor)
            for (row, line) in rows.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    cg.fill(CGRect(x: column * unit, y: row * unit, width: unit, height: unit))
                }
            }
        }
    }
}

/// Localized pixel face with the same Dynamic Type behavior as body copy.
struct SavePixelDisplayText: View {
    let text: String
    var pointSize: CGFloat = 22

    var body: some View {
        Text(text)
            .font(SaveAtlasType.display(pointSize, relativeTo: .title))
            .foregroundStyle(SaveAtlasPalette.forest)
            .fixedSize(horizontal: false, vertical: true)
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

/// Quiet paper ticket for controls; perforations are reserved for Map Stamps.
nonisolated struct SaveKraftTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(6, min(rect.width, rect.height) / 4)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}
