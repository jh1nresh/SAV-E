import CoreLocation
import SwiftUI

/// Founder lock 2026-10-14: product Map base is full-pixel tile-town.
/// MapKit remains for Trip navigation maps and Apple Maps handoff only.
nonisolated enum SaveTileTownProductLock: Sendable {
    static let productMapBaseIsTileTown = true
    static let homeShowsMapFilterChips = false
    static let mapShowsNearbySavedFriendsChips = true

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
    var onSelect: (UUID) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                townBase
                houses(in: size)
                trees(in: size)
                if showsPins {
                    pinsLayer(in: size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.tileTown")
        .accessibilityLabel("Tile-town map")
    }

    private var townBase: some View {
        Canvas { context, size in
            let grass = Rectangle().path(in: CGRect(origin: .zero, size: size))
            context.fill(grass, with: .color(SaveTileTownPalette.grass))

            var water = Path()
            water.move(to: CGPoint(x: size.width * 0.62, y: 0))
            water.addCurve(
                to: CGPoint(x: size.width * 0.58, y: size.height),
                control1: CGPoint(x: size.width * 0.78, y: size.height * 0.28),
                control2: CGPoint(x: size.width * 0.52, y: size.height * 0.62)
            )
            water.addLine(to: CGPoint(x: size.width, y: size.height))
            water.addLine(to: CGPoint(x: size.width, y: 0))
            water.closeSubpath()
            context.fill(water, with: .color(SaveTileTownPalette.water))

            var shoreline = Path()
            shoreline.move(to: CGPoint(x: size.width * 0.62, y: 0))
            shoreline.addCurve(
                to: CGPoint(x: size.width * 0.58, y: size.height),
                control1: CGPoint(x: size.width * 0.78, y: size.height * 0.28),
                control2: CGPoint(x: size.width * 0.52, y: size.height * 0.62)
            )
            context.stroke(
                shoreline,
                with: .color(SaveTileTownPalette.waterDeep.opacity(0.55)),
                lineWidth: 3
            )

            var road = Path()
            road.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.18))
            road.addQuadCurve(
                to: CGPoint(x: size.width * 0.52, y: size.height * 0.42),
                control: CGPoint(x: size.width * 0.28, y: size.height * 0.08)
            )
            road.addQuadCurve(
                to: CGPoint(x: size.width * 0.22, y: size.height * 0.88),
                control: CGPoint(x: size.width * 0.70, y: size.height * 0.70)
            )
            context.stroke(
                road,
                with: .color(SaveTileTownPalette.road),
                style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
            )

            var cross = Path()
            cross.move(to: CGPoint(x: size.width * 0.04, y: size.height * 0.58))
            cross.addQuadCurve(
                to: CGPoint(x: size.width * 0.56, y: size.height * 0.32),
                control: CGPoint(x: size.width * 0.26, y: size.height * 0.48)
            )
            context.stroke(
                cross,
                with: .color(SaveTileTownPalette.road),
                style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func houses(in size: CGSize) -> some View {
        let roofs = [
            SaveTileTownPalette.roofCoral,
            SaveTileTownPalette.roofHoney,
            SaveTileTownPalette.roofSky,
            SaveAtlasPalette.forest,
        ]
        let spots: [CGPoint] = [
            CGPoint(x: 0.16, y: 0.20), CGPoint(x: 0.32, y: 0.14),
            CGPoint(x: 0.48, y: 0.22), CGPoint(x: 0.22, y: 0.36),
            CGPoint(x: 0.40, y: 0.40), CGPoint(x: 0.58, y: 0.34),
            CGPoint(x: 0.18, y: 0.56), CGPoint(x: 0.36, y: 0.62),
            CGPoint(x: 0.52, y: 0.58), CGPoint(x: 0.26, y: 0.76),
            CGPoint(x: 0.46, y: 0.80), CGPoint(x: 0.64, y: 0.72),
        ]
        return ForEach(spots.indices, id: \.self) { index in
            let spot = spots[index]
            SaveTileTownHouse(roof: roofs[index % roofs.count])
                .frame(width: 28, height: 26)
                .position(x: spot.x * size.width, y: spot.y * size.height)
                .accessibilityHidden(true)
        }
    }

    private func trees(in size: CGSize) -> some View {
        let spots: [CGPoint] = [
            CGPoint(x: 0.10, y: 0.30), CGPoint(x: 0.27, y: 0.26),
            CGPoint(x: 0.43, y: 0.30), CGPoint(x: 0.12, y: 0.70),
            CGPoint(x: 0.33, y: 0.50), CGPoint(x: 0.55, y: 0.48),
            CGPoint(x: 0.41, y: 0.72), CGPoint(x: 0.60, y: 0.84),
        ]
        return ForEach(spots.indices, id: \.self) { index in
            Circle()
                .fill(index.isMultiple(of: 2) ? SaveTileTownPalette.tree : SaveTileTownPalette.treeDeep)
                .frame(width: 11, height: 11)
                .position(x: spots[index].x * size.width, y: spots[index].y * size.height)
                .accessibilityHidden(true)
        }
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pin.isSelected ? "Selected Map Stamp, \(pin.name)" : "Map Stamp, \(pin.name)")
            .accessibilityIdentifier("map.tilePin.\(pin.id.uuidString)")
            .position(x: lot.x * size.width, y: lot.y * size.height)
        }
    }
}

private struct SaveTileTownHouse: View {
    let roof: Color

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(roof)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(SaveTileTownPalette.housePaper)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(SaveAtlasPalette.ink.opacity(0.18), lineWidth: 0.6)
                }
                .frame(height: 14)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct SaveTileTownPinMark: View {
    var isSelected = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(SaveAtlasPalette.coral)
                .frame(width: isSelected ? 16 : 12, height: isSelected ? 22 : 18)
            Circle()
                .fill(SaveAtlasPalette.paper)
                .frame(width: isSelected ? 7 : 5, height: isSelected ? 7 : 5)
                .offset(y: -3)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.18), radius: 1, y: 1)
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
