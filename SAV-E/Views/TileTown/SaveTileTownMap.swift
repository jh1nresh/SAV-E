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
    /// Home hero town card. Matches the v5 mock: large, not a 168pt inset.
    static let homeHeroHeight: CGFloat = 320
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
    /// House footprints, then extra lots so pins past the house count do not stack.
    static var lots: [CGPoint] { SaveTileTownRaster.normalizedHouseAnchors() }

    static func lotIndex(for id: UUID) -> Int {
        var hasher = Hasher()
        hasher.combine(id)
        let value = hasher.finalize()
        let count = max(lots.count, 1)
        return abs(value) % count
    }

    static func assignments(for ids: [UUID]) -> [UUID: Int] {
        var used = Set<Int>()
        var result: [UUID: Int] = [:]
        let capacity = lots.count
        for (order, id) in ids.enumerated() {
            var index = capacity == 0 ? order : lotIndex(for: id)
            var attempts = 0
            while used.contains(index), attempts < capacity {
                index = (index + 1) % capacity
                attempts += 1
            }
            if used.contains(index) {
                index = capacity + order
            }
            used.insert(index)
            result[id] = index
        }
        return result
    }

    static func point(index: Int, anchors: [CGPoint]) -> CGPoint {
        if anchors.indices.contains(index) {
            return anchors[index]
        }
        let extra = index - anchors.count
        let columns = 6
        let row = extra / columns
        let column = extra % columns
        return CGPoint(
            x: 0.12 + CGFloat(column) * 0.14,
            y: 0.16 + CGFloat(row) * 0.12
        )
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
    @Environment(\.appLanguageSettings) private var languageSettings
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
                    .frame(width: size.width, height: size.height, alignment: .top)
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
        .accessibilityLabel(languageSettings.localized(
            english: "Tile-town map",
            traditionalChinese: "像素小鎮地圖"
        ))
    }

    private func pinsLayer(in size: CGSize) -> some View {
        let ids = pins.map(\.id)
        let assigned = SaveTileTownLayout.assignments(for: ids)
        let anchors = SaveTileTownRaster.normalizedHouseAnchors()
        let fill = SaveTileTownRaster.scaledToFillRect(viewSize: size)
        return ForEach(pins) { pin in
            let lot = SaveTileTownLayout.point(index: assigned[pin.id] ?? 0, anchors: anchors)
            let point = CGPoint(
                x: fill.minX + lot.x * fill.width,
                y: fill.minY + lot.y * fill.height
            )
            Button {
                onSelect(pin.id)
            } label: {
                SaveTileTownPinMark(isSelected: pin.isSelected)
                    .frame(width: 44, height: 44, alignment: .bottom)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pinLabel(for: pin))
            .accessibilityIdentifier("map.tilePin.\(pin.id.uuidString)")
            .position(point)
        }
    }

    private func pinLabel(for pin: SaveTileTownPin) -> String {
        if pin.isSelected {
            return languageSettings.localized(
                english: "Selected Map Stamp, \(pin.name)",
                traditionalChinese: "已選地圖章，\(pin.name)"
            )
        }
        return languageSettings.localized(
            english: "Map Stamp, \(pin.name)",
            traditionalChinese: "地圖章，\(pin.name)"
        )
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
    static let mapRows = 28
    static let tileW = 16
    static let tileH = 8
    static let baseWidth = 240
    static let baseHeight = 256
    static let columns = baseWidth
    static let rows = baseHeight
    private static let originX = 120
    private static let originY = 8

    enum Cell {
        case grass, grassDeep, water, waterDeep, sand, road
        case roofCoral, roofHoney, roofSky, roofForest
        case wall, wallDeep, window, door, tree, treeDeep, trunk
    }

    /// Thirty-two hashed lots spread down the island so pins do not stack.
    static let houses: [(column: Int, row: Int, roof: Cell)] = [
        (2, 1, .roofCoral), (5, 0, .roofHoney), (7, 2, .roofSky), (3, 3, .roofForest),
        (1, 5, .roofHoney), (6, 6, .roofCoral), (4, 8, .roofSky), (8, 7, .roofHoney),
        (2, 10, .roofSky), (5, 11, .roofCoral), (7, 13, .roofForest), (3, 14, .roofHoney),
        (1, 16, .roofCoral), (6, 17, .roofSky), (4, 19, .roofHoney), (8, 18, .roofForest),
        (2, 21, .roofHoney), (5, 22, .roofCoral), (7, 24, .roofSky), (3, 25, .roofForest),
        (1, 27, .roofSky), (6, 28, .roofHoney), (4, 30, .roofCoral), (8, 29, .roofSky),
        (2, 32, .roofForest), (5, 33, .roofHoney), (7, 35, .roofCoral), (3, 36, .roofSky),
        (1, 38, .roofHoney), (6, 39, .roofForest), (4, 42, .roofCoral), (7, 44, .roofSky),
    ]

    static func integerScale(for size: CGSize) -> Int {
        let x = size.width / CGFloat(baseWidth)
        let y = size.height / CGFloat(baseHeight)
        return max(1, Int(max(x, y)))
    }

    /// Same cover transform as `Image.scaledToFill` with top-center alignment,
    /// so pins sit on house lots after the raster is cropped. The taller
    /// bitmap fills Map; Home crops the south water, not the village.
    static func scaledToFillRect(
        viewSize: CGSize,
        imageSize: CGSize = CGSize(width: CGFloat(baseWidth), height: CGFloat(baseHeight))
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (viewSize.width - width) / 2,
            y: 0,
            width: width,
            height: height
        )
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

    @MainActor
    private static var imageCache: [Int: UIImage] = [:]

    @MainActor
    static func image(scale: Int) -> UIImage {
        let scale = max(1, scale)
        if let cached = imageCache[scale] {
            return cached
        }
        let rendered = render(scale: scale)
        imageCache[scale] = rendered
        return rendered
    }

    private static func render(scale: Int) -> UIImage {
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
        let maxRow = max(
            mapRows,
            Int(ceil((CGFloat(baseHeight) + CGFloat(tileH) - CGFloat(originY)) / CGFloat(tileH / 2)))
                + mapColumns
        )
        for depth in 0..<(mapColumns + maxRow) {
            for column in 0..<mapColumns {
                let row = depth - column
                guard row >= 0 else { continue }
                let origin = iso(column: column, row: row)
                if origin.y > CGFloat(baseHeight) + CGFloat(tileH) { continue }
                fillIsoTile(cg, column: column, row: row, cell: ground(column: column, row: row), scale: scale)
            }
        }
        for house in houses {
            blitIsoHouse(cg, column: house.column, row: house.row, roof: house.roof, scale: scale)
        }
        let trees = [
            (1, 2), (3, 1), (5, 2), (7, 1), (0, 5), (2, 6), (6, 7),
            (8, 5), (1, 9), (8, 9), (6, 4), (3, 8), (0, 12), (2, 13),
            (7, 14), (1, 16), (5, 15), (8, 18), (3, 19), (6, 20),
            (0, 22), (2, 24), (7, 23), (4, 26), (1, 28), (8, 27),
            (0, 31), (3, 34), (8, 32), (2, 37), (5, 40), (7, 41),
            (1, 43), (4, 46), (8, 45), (0, 48),
        ]
        for (column, row) in trees {
            blitIsoTree(cg, column: column, row: row, scale: scale)
        }
        blitIsoDock(cg, scale: scale)
    }

    private static func ground(column: Int, row: Int) -> Cell {
        if column >= 10 { return row % 3 == 0 ? .waterDeep : .water }
        if column == 9 { return .sand }
        if isRoad(column: column, row: row) { return .road }
        return (column + row) % 5 == 0 ? .grassDeep : .grass
    }

    private static func isRoad(column: Int, row: Int) -> Bool {
        column == 4
            || row % 8 == 4 && column <= 9
            || column == 7 && row % 11 < 8
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
        for row in [8, 16, 24, 32, 40] {
            for column in 9...12 {
                fillIsoTile(cg, column: column, row: row, cell: .road, scale: scale)
            }
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
            let cols = 7
            let rows = 10
            let unit = max(1, floor(min(size.width / CGFloat(cols), size.height / CGFloat(rows))))
            let originX = (size.width - CGFloat(cols) * unit) / 2
            let originY = size.height - CGFloat(rows) * unit
            let coral = Color(red: 0.949, green: 0.420, blue: 0.290)
            let paper = Color(red: 1, green: 0.973, blue: 0.925)
            let ink = Color(red: 0.184, green: 0.180, blue: 0.137)
            let body: [(Int, Int)] = [
                (2, 0), (3, 0), (4, 0),
                (1, 1), (2, 1), (3, 1), (4, 1), (5, 1),
                (1, 2), (2, 2), (3, 2), (4, 2), (5, 2),
                (1, 3), (2, 3), (3, 3), (4, 3), (5, 3),
                (1, 4), (2, 4), (3, 4), (4, 4), (5, 4),
                (2, 5), (3, 5), (4, 5),
                (3, 6),
                (3, 7),
                (3, 8),
            ]
            let outline: [(Int, Int)] = isSelected
                ? [(2, -1), (3, -1), (4, -1), (0, 2), (6, 2), (3, 9)]
                : []
            for (x, y) in outline where y >= 0 {
                fillPixel(context, x: x, y: y, unit: unit, originX: originX, originY: originY, color: ink)
            }
            for (x, y) in body {
                fillPixel(context, x: x, y: y, unit: unit, originX: originX, originY: originY, color: coral)
            }
            fillPixel(context, x: 3, y: 2, unit: unit, originX: originX, originY: originY, color: paper)
            fillPixel(context, x: 2, y: 2, unit: unit, originX: originX, originY: originY, color: paper)
            fillPixel(context, x: 4, y: 2, unit: unit, originX: originX, originY: originY, color: paper)
            fillPixel(context, x: 3, y: 3, unit: unit, originX: originX, originY: originY, color: paper)
        }
        .frame(width: isSelected ? 32 : 28, height: isSelected ? 40 : 34)
        .accessibilityHidden(true)
    }

    private func fillPixel(
        _ context: GraphicsContext,
        x: Int,
        y: Int,
        unit: CGFloat,
        originX: CGFloat,
        originY: CGFloat,
        color: Color
    ) {
        context.fill(
            Path(CGRect(
                x: originX + CGFloat(x) * unit,
                y: originY + CGFloat(y) * unit,
                width: unit,
                height: unit
            )),
            with: .color(color)
        )
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
