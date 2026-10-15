import CoreLocation
import SwiftUI
import UIKit

/// Founder lock 2026-10-14: product Map base is full-pixel tile-town.
/// MapKit remains for Trip navigation maps and Apple Maps handoff only.
nonisolated enum SaveTileTownProductLock: Sendable {
    static let productMapBaseIsTileTown = true
    static let homeShowsMapFilterChips = false
    static let mapShowsNearbySavedFriendsChips = true
    /// Wordmark + Nearby/Saved/Friends rail below the 48pt status band.
    static let mapChromeHeight: CGFloat = 136
    /// Lets root-tab lists scroll stamp labels and bios above the tab bar.
    static let rootTabScrollClearance: CGFloat = 150

    /// Collection page size used by Passport progress (4/12 in the lock frames).
    static func passportGoal(for savedCount: Int) -> Int {
        max(12, ((max(savedCount, 0) + 11) / 12) * 12)
    }
}

enum SaveTileTownMapLens: String, CaseIterable, Identifiable {
    case nearby
    case saved
    case friends

    var id: String { rawValue }

    var accessibilityIdentifier: String {
        "map.lens.\(rawValue)"
    }

    var systemImage: String {
        switch self {
        case .nearby: return "mappin"
        case .saved: return "star"
        case .friends: return "leaf"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .nearby:
            return language.localized(english: "Nearby", traditionalChinese: "附近")
        case .saved:
            return language.localized(english: "Saved", traditionalChinese: "已存")
        case .friends:
            return language.localized(english: "Friends", traditionalChinese: "朋友")
        }
    }
}

nonisolated enum SaveTileTownLayout: Sendable {
    /// Normalized lots along the village roads. Pins hash here so the town
    /// stays a memory map, not a silent GPS re-projection.
    static let lots: [CGPoint] = [
        CGPoint(x: 0.18, y: 0.22),
        CGPoint(x: 0.38, y: 0.16),
        CGPoint(x: 0.58, y: 0.24),
        CGPoint(x: 0.78, y: 0.18),
        CGPoint(x: 0.14, y: 0.42),
        CGPoint(x: 0.34, y: 0.38),
        CGPoint(x: 0.54, y: 0.44),
        CGPoint(x: 0.72, y: 0.36),
        CGPoint(x: 0.22, y: 0.62),
        CGPoint(x: 0.44, y: 0.58),
        CGPoint(x: 0.64, y: 0.64),
        CGPoint(x: 0.82, y: 0.52),
        CGPoint(x: 0.28, y: 0.80),
        CGPoint(x: 0.50, y: 0.78),
        CGPoint(x: 0.70, y: 0.82),
        CGPoint(x: 0.86, y: 0.70),
    ]

    static func lotIndex(for id: UUID) -> Int {
        var hasher = Hasher()
        hasher.combine(id)
        let value = hasher.finalize()
        return abs(value) % lots.count
    }

    static func assignments(for ids: [UUID]) -> [UUID: Int] {
        var used = Set<Int>()
        var result: [UUID: Int] = [:]
        for id in ids {
            var index = lotIndex(for: id)
            var attempts = 0
            while used.contains(index), attempts < lots.count {
                index = (index + 1) % lots.count
                attempts += 1
            }
            used.insert(index)
            result[id] = index
        }
        return result
    }
}

struct SaveTileTownPin: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isSelected: Bool
}

struct SaveTileTownCanvas: View {
    var pins: [SaveTileTownPin] = []
    var showsPins = true
    var clipsToPaper = true
    var allowsPan = false
    var onSelect: (UUID) -> Void = { _ in }
    @State private var pan = CGSize.zero
    @State private var panAnchor = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = SaveTileTownRaster.integerScale(for: size)
            ZStack {
                Image(uiImage: SaveTileTownRaster.image(scale: scale))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if allowsPan {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(panGesture(in: size))
                        .accessibilityIdentifier("map.tileTown.pan")
                }
                if showsPins {
                    pinsLayer(in: size)
                }
            }
            .offset(pan)
            .clipShape(RoundedRectangle(cornerRadius: clipsToPaper ? 18 : 0, style: .continuous))
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.tileTown")
        .accessibilityLabel("Tile-town map")
    }

    private func pinsLayer(in size: CGSize) -> some View {
        let ids = pins.map(\.id)
        let assigned = SaveTileTownLayout.assignments(for: ids)
        return ForEach(pins) { pin in
            let lot = SaveTileTownLayout.lots[assigned[pin.id] ?? 0]
            Button {
                onSelect(pin.id)
            } label: {
                SaveTileTownPinMark(isSelected: pin.isSelected)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pin.isSelected ? "Selected Map Stamp, \(pin.name)" : "Map Stamp, \(pin.name)")
            .accessibilityIdentifier("map.tilePin.\(pin.id.uuidString)")
            .position(x: lot.x * size.width, y: lot.y * size.height)
        }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                pan = clamped(CGSize(
                    width: panAnchor.width + value.translation.width,
                    height: panAnchor.height + value.translation.height
                ), in: size)
            }
            .onEnded { value in
                pan = clamped(CGSize(
                    width: panAnchor.width + value.translation.width,
                    height: panAnchor.height + value.translation.height
                ), in: size)
                panAnchor = pan
            }
    }

    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let limitX = max(24, size.width * 0.35)
        let limitY = max(24, size.height * 0.35)
        return CGSize(
            width: min(limitX, max(-limitX, proposed.width)),
            height: min(limitY, max(-limitY, proposed.height))
        )
    }
}

/// Nearest-neighbor tile-town. Drawn at a fixed cell grid, then scaled by an
/// integer factor with interpolation disabled. No anti-aliased curves.
enum SaveTileTownRaster {
    static let columns = 48
    static let rows = 32

    enum Cell: UInt8 {
        case grass, grassDeep, water, waterDeep, sand, road
        case roofCoral, roofHoney, roofSky, roofForest
        case wall, window, door, tree, treeDeep, trunk
    }

    static func integerScale(for size: CGSize) -> Int {
        let x = Int(size.width / CGFloat(columns))
        let y = Int(size.height / CGFloat(rows))
        return max(1, min(x, y))
    }

    static func image(scale: Int) -> UIImage {
        let scale = max(1, scale)
        let width = columns * scale
        let height = rows * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            let grid = paint()
            for row in 0..<rows {
                for column in 0..<columns {
                    cg.setFillColor(color(for: Cell(rawValue: grid[row][column]) ?? .grass).cgColor)
                    cg.fill(CGRect(
                        x: column * scale,
                        y: row * scale,
                        width: scale,
                        height: scale
                    ))
                }
            }
        }
    }

    private static func paint() -> [[UInt8]] {
        var grid = (0..<rows).map { row in
            (0..<columns).map { column -> UInt8 in
                ((row + column) % 7 == 0) ? Cell.grassDeep.rawValue : Cell.grass.rawValue
            }
        }
        for row in 0..<rows {
            let shore = 30 + (row / 6) % 3
            for column in shore..<columns {
                grid[row][column] = (column == shore ? Cell.sand : (row % 5 == 0 ? Cell.waterDeep : Cell.water)).rawValue
            }
        }
        paintRoad(&grid, from: (2, 6), to: (28, 12), width: 2)
        paintRoad(&grid, from: (28, 12), to: (18, 28), width: 2)
        paintRoad(&grid, from: (1, 18), to: (26, 10), width: 2)
        paintRoad(&grid, from: (8, 2), to: (8, 28), width: 2)
        paintRoad(&grid, from: (20, 4), to: (20, 26), width: 2)
        let houses: [(Int, Int, Cell)] = [
            (4, 3, .roofCoral), (12, 2, .roofHoney), (22, 4, .roofSky),
            (6, 10, .roofForest), (16, 11, .roofCoral), (24, 9, .roofHoney),
            (5, 17, .roofSky), (14, 18, .roofCoral), (23, 16, .roofForest),
            (9, 23, .roofHoney), (18, 24, .roofSky), (26, 21, .roofCoral),
        ]
        for (x, y, roof) in houses {
            blitHouse(&grid, x: x, y: y, roof: roof)
        }
        let trees = [
            (2, 8), (10, 7), (18, 8), (3, 21), (13, 15), (25, 14), (17, 22), (27, 26),
            (11, 26), (21, 20),
        ]
        for (x, y) in trees {
            blitTree(&grid, x: x, y: y)
        }
        return grid
    }

    private static func paintRoad(_ grid: inout [[UInt8]], from: (Int, Int), to: (Int, Int), width: Int) {
        var x = from.0
        var y = from.1
        while x != to.0 || y != to.1 {
            stampRoad(&grid, x: x, y: y, width: width)
            if x != to.0 { x += x < to.0 ? 1 : -1 }
            if y != to.1 { y += y < to.1 ? 1 : -1 }
        }
        stampRoad(&grid, x: to.0, y: to.1, width: width)
    }

    private static func stampRoad(_ grid: inout [[UInt8]], x: Int, y: Int, width: Int) {
        for dy in 0..<width {
            for dx in 0..<width {
                plot(&grid, x: x + dx, y: y + dy, cell: .road)
            }
        }
    }

    private static func blitHouse(_ grid: inout [[UInt8]], x: Int, y: Int, roof: Cell) {
        let sprite: [[Cell]] = [
            [.grass, roof, roof, roof, .grass],
            [roof, roof, roof, roof, roof],
            [.wall, .window, .door, .window, .wall],
            [.wall, .wall, .door, .wall, .wall],
        ]
        for (row, line) in sprite.enumerated() {
            for (column, cell) in line.enumerated() where cell != .grass {
                plot(&grid, x: x + column, y: y + row, cell: cell)
            }
        }
    }

    private static func blitTree(_ grid: inout [[UInt8]], x: Int, y: Int) {
        plot(&grid, x: x + 1, y: y, cell: .tree)
        plot(&grid, x: x, y: y + 1, cell: .treeDeep)
        plot(&grid, x: x + 1, y: y + 1, cell: .tree)
        plot(&grid, x: x + 2, y: y + 1, cell: .treeDeep)
        plot(&grid, x: x + 1, y: y + 2, cell: .trunk)
    }

    private static func plot(_ grid: inout [[UInt8]], x: Int, y: Int, cell: Cell) {
        guard y >= 0, y < rows, x >= 0, x < columns else { return }
        grid[y][x] = cell.rawValue
    }

    private static func color(for cell: Cell) -> UIColor {
        switch cell {
        case .grass: return UIColor(red: 0.561, green: 0.749, blue: 0.416, alpha: 1)
        case .grassDeep: return UIColor(red: 0.435, green: 0.627, blue: 0.306, alpha: 1)
        case .water: return UIColor(red: 0.494, green: 0.784, blue: 0.890, alpha: 1)
        case .waterDeep: return UIColor(red: 0.310, green: 0.659, blue: 0.784, alpha: 1)
        case .sand: return UIColor(red: 0.933, green: 0.855, blue: 0.667, alpha: 1)
        case .road: return UIColor(red: 0.957, green: 0.902, blue: 0.784, alpha: 1)
        case .roofCoral: return UIColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1)
        case .roofHoney: return UIColor(red: 0.910, green: 0.722, blue: 0.427, alpha: 1)
        case .roofSky: return UIColor(red: 0.494, green: 0.714, blue: 0.831, alpha: 1)
        case .roofForest: return UIColor(red: 0.290, green: 0.455, blue: 0.333, alpha: 1)
        case .wall: return UIColor(red: 1.000, green: 0.973, blue: 0.910, alpha: 1)
        case .window: return UIColor(red: 0.420, green: 0.620, blue: 0.760, alpha: 1)
        case .door: return UIColor(red: 0.557, green: 0.369, blue: 0.247, alpha: 1)
        case .tree: return UIColor(red: 0.310, green: 0.541, blue: 0.227, alpha: 1)
        case .treeDeep: return UIColor(red: 0.227, green: 0.420, blue: 0.173, alpha: 1)
        case .trunk: return UIColor(red: 0.482, green: 0.333, blue: 0.200, alpha: 1)
        }
    }
}

struct SaveTileTownPinMark: View {
    var isSelected = false

    var body: some View {
        Canvas { context, size in
            let unit = max(1, floor(size.width / 5))
            let coral = Color(red: 0.949, green: 0.420, blue: 0.290)
            let paper = Color(red: 1, green: 0.973, blue: 0.925)
            let pin: [(Int, Int)] = isSelected
                ? [(2, 0), (1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (3, 2), (2, 3), (2, 4)]
                : [(2, 0), (1, 1), (2, 1), (3, 1), (2, 2), (2, 3)]
            for (x, y) in pin {
                context.fill(
                    Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)),
                    with: .color(coral)
                )
            }
            context.fill(
                Path(CGRect(x: 2 * unit, y: unit, width: unit, height: unit)),
                with: .color(paper)
            )
        }
        .frame(width: isSelected ? 15 : 12, height: isSelected ? 18 : 15)
        .accessibilityHidden(true)
    }
}

struct SaveTileTownPeekCard: View {
    let title: String
    var subtitle: String? = nil
    var photoURL: URL? = nil
    var accessibilityNameID: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            SaveKraftStampFaceView(face: .photo(photoURL), glyph: "photo")
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SaveAtlasType.strong(16))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(accessibilityNameID ?? "map.peek.name")
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SaveAtlasType.regular(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("map.peek.subtitle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.kraft.opacity(0.72), lineWidth: 1)
        }
        .clipped()
    }
}
