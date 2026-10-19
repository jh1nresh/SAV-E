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
        let anchors = SaveTileTownRaster.normalizedHouseAnchors()
        return ForEach(pins) { pin in
            let lotIndex = assigned[pin.id] ?? 0
            let lot = anchors.indices.contains(lotIndex)
                ? anchors[lotIndex]
                : SaveTileTownLayout.lots[lotIndex % SaveTileTownLayout.lots.count]
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

/// Nearest-neighbor isometric tile-town (founder lock 2026-10-19).
/// Drawn at a fixed pixel grid, then scaled by an integer factor with
/// interpolation disabled. Place-memory, not navigation. No anti-aliased curves.
enum SaveTileTownRaster {
    static let mapColumns = 14
    static let mapRows = 12
    static let tileW = 16
    static let tileH = 8
    static let baseWidth = 240
    static let baseHeight = 176
    static let columns = baseWidth
    static let rows = baseHeight
    private static let originX = 120
    private static let originY = 20

    enum Cell {
        case grass, grassDeep, water, waterDeep, sand, road
        case roofCoral, roofHoney, roofSky, roofForest
        case wall, wallDeep, window, door, tree, treeDeep, trunk
    }

    /// Sixteen hashed lots. Pins sit on these house footprints.
    static let houses: [(column: Int, row: Int, roof: Cell)] = [
        (2, 2, .roofCoral), (4, 1, .roofHoney), (6, 2, .roofSky), (3, 3, .roofForest),
        (1, 5, .roofHoney), (4, 4, .roofCoral), (6, 5, .roofSky), (8, 3, .roofHoney),
        (2, 7, .roofSky), (5, 6, .roofCoral), (7, 7, .roofForest), (3, 8, .roofHoney),
        (5, 9, .roofSky), (7, 8, .roofCoral), (8, 6, .roofHoney), (4, 7, .roofForest),
    ]

    static func integerScale(for size: CGSize) -> Int {
        let x = Int(size.width / CGFloat(baseWidth))
        let y = Int(size.height / CGFloat(baseHeight))
        return max(1, min(x, y))
    }

    static func normalizedHouseAnchors() -> [CGPoint] {
        houses.map { house in
            let point = iso(column: house.column, row: house.row)
            return CGPoint(
                x: CGFloat(point.x) / CGFloat(baseWidth),
                y: CGFloat(point.y - 12) / CGFloat(baseHeight)
            )
        }
    }

    static func image(scale: Int) -> UIImage {
        let scale = max(1, scale)
        let width = baseWidth * scale
        let height = baseHeight * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            cg.setFillColor(color(for: .waterDeep).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            paintIsometricTown(cg, scale: scale)
        }
    }

    private static func iso(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: originX + (column - row) * (tileW / 2),
            y: originY + (column + row) * (tileH / 2)
        )
    }

    private static func paintIsometricTown(_ cg: CGContext, scale: Int) {
        for depth in 0..<(mapColumns + mapRows) {
            for column in 0..<mapColumns {
                let row = depth - column
                guard row >= 0, row < mapRows else { continue }
                fillIsoTile(cg, column: column, row: row, cell: ground(column: column, row: row), scale: scale)
            }
        }
        for house in houses {
            blitIsoHouse(cg, column: house.column, row: house.row, roof: house.roof, scale: scale)
        }
        let trees = [
            (1, 3), (3, 1), (5, 3), (7, 2), (0, 6), (2, 6), (6, 8),
            (8, 5), (1, 8), (8, 8), (6, 4), (3, 5),
        ]
        for (column, row) in trees {
            blitIsoTree(cg, column: column, row: row, scale: scale)
        }
        blitIsoDock(cg, scale: scale)
    }

    private static func ground(column: Int, row: Int) -> Cell {
        let shore = 9 - (row / 4)
        if column > shore + 1 { return row % 4 == 0 ? .waterDeep : .water }
        if column == shore + 1 { return .sand }
        if isRoad(column: column, row: row) { return .road }
        return (column + row) % 5 == 0 ? .grassDeep : .grass
    }

    private static func isRoad(column: Int, row: Int) -> Bool {
        row == 4 && column <= 9
            || column == 4 && row <= 9
            || row == 7 && column >= 2 && column <= 8
            || column == 7 && row >= 3 && row <= 8
    }

    private static func fillIsoTile(
        _ cg: CGContext,
        column: Int,
        row: Int,
        cell: Cell,
        scale: Int
    ) {
        let origin = iso(column: column, row: row)
        fillDiamond(
            cg,
            x: Int(origin.x) * scale,
            y: Int(origin.y) * scale,
            tileW: tileW * scale,
            tileH: tileH * scale,
            color: color(for: cell)
        )
    }

    private static func fillDiamond(
        _ cg: CGContext,
        x: Int,
        y: Int,
        tileW: Int,
        tileH: Int,
        color: UIColor
    ) {
        cg.setFillColor(color.cgColor)
        for dy in 0..<tileH {
            let t = dy < tileH / 2 ? dy + 1 : tileH - dy
            let half = max(1, t * tileW / tileH)
            cg.fill(CGRect(x: x - half, y: y + dy, width: half * 2, height: 1))
        }
    }

    private static func blitIsoHouse(
        _ cg: CGContext,
        column: Int,
        row: Int,
        roof: Cell,
        scale: Int
    ) {
        let origin = iso(column: column, row: row)
        let x = Int(origin.x) * scale
        let y = Int(origin.y) * scale
        let wallH = 10 * scale
        let half = 8 * scale
        cg.setFillColor(color(for: .wallDeep).cgColor)
        for h in 0..<wallH {
            cg.fill(CGRect(x: x - half, y: y + 4 * scale - wallH + h, width: half, height: 1))
        }
        cg.setFillColor(color(for: .wall).cgColor)
        for h in 0..<wallH {
            cg.fill(CGRect(x: x, y: y + 4 * scale - wallH + h, width: half, height: 1))
        }
        cg.setFillColor(color(for: .window).cgColor)
        cg.fill(CGRect(x: x - 5 * scale, y: y + 6 * scale - wallH, width: 2 * scale, height: 3 * scale))
        cg.fill(CGRect(x: x + 3 * scale, y: y + 6 * scale - wallH, width: 2 * scale, height: 3 * scale))
        cg.setFillColor(color(for: .door).cgColor)
        cg.fill(CGRect(x: x - scale, y: y + 8 * scale - wallH, width: 2 * scale, height: 4 * scale))
        fillDiamond(
            cg,
            x: x,
            y: y - wallH,
            tileW: tileW * scale,
            tileH: tileH * scale,
            color: color(for: roof)
        )
    }

    private static func blitIsoTree(_ cg: CGContext, column: Int, row: Int, scale: Int) {
        let origin = iso(column: column, row: row)
        let x = Int(origin.x) * scale
        let y = Int(origin.y) * scale
        cg.setFillColor(color(for: .trunk).cgColor)
        cg.fill(CGRect(x: x - scale, y: y + 2 * scale, width: 2 * scale, height: 4 * scale))
        cg.setFillColor(color(for: .treeDeep).cgColor)
        cg.fill(CGRect(x: x - 3 * scale, y: y - 4 * scale, width: 6 * scale, height: 5 * scale))
        cg.setFillColor(color(for: .tree).cgColor)
        cg.fill(CGRect(x: x - 2 * scale, y: y - 6 * scale, width: 4 * scale, height: 4 * scale))
    }

    private static func blitIsoDock(_ cg: CGContext, scale: Int) {
        for column in 9...12 {
            fillIsoTile(cg, column: column, row: 8, cell: .road, scale: scale)
        }
    }

    private static func color(for cell: Cell) -> UIColor {
        // Light-column hexes from SaveTileTownPalette. Raw sRGB so this
        // raster stays off the main-actor Color bridge.
        switch cell {
        case .grass: return rgb(0x6BB34A)
        case .grassDeep: return rgb(0x4E9A32)
        case .water: return rgb(0x3DB5DC)
        case .waterDeep: return rgb(0x2A8FBE)
        case .sand: return rgb(0xE8D5A3)
        case .road: return rgb(0xE8D5A3)
        case .roofCoral: return rgb(0xD45A32)
        case .roofHoney: return rgb(0xE0A04A)
        case .roofSky: return rgb(0x4A8BB5)
        case .roofForest: return rgb(0x2C6A1E)
        case .wall: return rgb(0xF3E6C8)
        case .wallDeep: return rgb(0xDBC69E)
        case .window: return rgb(0x2A8FBE)
        case .door: return rgb(0x8F5E40)
        case .tree: return rgb(0x3D8A2C)
        case .treeDeep: return rgb(0x2C6A1E)
        case .trunk: return rgb(0x7A5433)
        }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
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
