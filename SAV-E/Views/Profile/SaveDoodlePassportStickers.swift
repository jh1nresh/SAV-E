import SwiftUI

/// Official DESIGN stickers when the kind has a unique asset. Extra kinds
/// keep their own glyph so unvisited cells do not collapse to five repeats.
/// Number stamps replace large rank rings. Do not wrap a shrunken icon in
/// a filled circle.
struct SaveDoodlePassportSticker: View {
    let kind: SaveDoodleStickerKind
    let visited: Bool

    var body: some View {
        if kind.usesOfficialAsset {
            Image(kind.officialSticker.imageName(visited: visited, pointSize: SaveLayout.passportSlot))
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: SaveLayout.passportSlot, height: SaveLayout.passportSlot)
                .accessibilityHidden(true)
        } else {
            SaveDoodlePassportUniqueGlyph(kind: kind)
                .frame(width: SaveLayout.passportSlot, height: SaveLayout.passportSlot)
                .accessibilityHidden(true)
        }
    }
}

struct SaveDoodlePassportNumberStamp: View {
    let number: Int
    let gold: Bool

    var body: some View {
        Text("\(number)")
            .font(SaveAtlasType.body(13))
            .foregroundStyle(gold ? SaveDoodle.stampGold : SaveDoodle.stampRed)
            .frame(width: SaveLayout.numberBadge, height: SaveLayout.numberBadge)
            .overlay {
                Circle()
                    .stroke(gold ? SaveDoodle.stampGold : SaveDoodle.stampRed, lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportSlotView: View {
    let slot: SaveDoodlePassportSlot
    var isStamping: Bool = false

    var body: some View {
        VStack(spacing: SaveSpace.tight) {
            ZStack {
                if showsCard {
                    Circle()
                        .stroke(
                            SaveDoodle.pencil,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .background(
                            SaveAtlasPalette.paper
                                .clipShape(Circle())
                        )
                }
                switch slot.content {
                case let .place(_, kind, rank):
                    SaveDoodlePassportSticker(kind: kind, visited: rank != .none)
                case .empty:
                    EmptyView()
                }
            }
            .frame(width: SaveDoodlePassportCatalog.slotSize, height: SaveDoodlePassportCatalog.cardHeight)

            if let number = slot.stampNumber {
                SaveDoodlePassportNumberStamp(
                    number: number,
                    gold: {
                        if case let .place(_, _, rank) = slot.content { return rank == .gold }
                        return false
                    }()
                )
            } else {
                Color.clear.frame(width: SaveLayout.numberBadge, height: SaveLayout.numberBadge)
            }
        }
        .scaleEffect(isStamping ? 1.08 : 1)
        .animation(SaveTheme.Motion.stampSpring, value: isStamping)
    }

    private var showsCard: Bool {
        switch slot.content {
        case let .place(_, _, rank):
            return rank == .none
        case .empty:
            return true
        }
    }
}

struct SaveDoodlePassportUniqueGlyph: View {
    let kind: SaveDoodleStickerKind

    var body: some View {
        if kind == .bridge {
            SaveDoodleBridgeGlyph()
        } else if kind == .baozi {
            SaveDoodleBaoziGlyph()
        } else if kind == .ferris {
            SaveDoodleFerrisGlyph()
        } else {
            Image(systemName: kind.systemImageName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SaveAtlasPalette.ink)
        }
    }
}

/// The system has no ferriswheel symbol; draw the wheel so this slot is never blank.
struct SaveDoodleFerrisGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            let radius = min(size.width, size.height) * 0.28
            var path = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            for spoke in 0..<8 {
                let angle = Double(spoke) * .pi / 4
                let end = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                path.move(to: center)
                path.addLine(to: end)
                path.addEllipse(in: CGRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4))
            }
            path.move(to: CGPoint(x: size.width * 0.3, y: size.height * 0.84))
            path.addLine(to: center)
            path.addLine(to: CGPoint(x: size.width * 0.7, y: size.height * 0.84))
            path.closeSubpath()
            context.stroke(path, with: .color(SaveAtlasPalette.ink), lineWidth: 1.2)
        }
    }
}

struct SaveDoodleBridgeGlyph: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let inset = size.width * 0.18
            let base = size.height * 0.62
            path.move(to: CGPoint(x: inset, y: base))
            path.addQuadCurve(
                to: CGPoint(x: size.width - inset, y: base),
                control: CGPoint(x: size.width / 2, y: size.height * 0.22)
            )
            path.addLine(to: CGPoint(x: size.width - inset, y: base + 6))
            path.addQuadCurve(
                to: CGPoint(x: inset, y: base + 6),
                control: CGPoint(x: size.width / 2, y: size.height * 0.30)
            )
            path.closeSubpath()
            context.stroke(
                path,
                with: .color(SaveAtlasPalette.ink),
                lineWidth: 1.5
            )
        }
    }
}

struct SaveDoodleBaoziGlyph: View {
    var body: some View {
        Canvas { context, size in
            let oval = CGRect(
                x: size.width * 0.18,
                y: size.height * 0.32,
                width: size.width * 0.64,
                height: size.height * 0.42
            )
            context.stroke(
                Path(ellipseIn: oval),
                with: .color(SaveAtlasPalette.ink),
                lineWidth: 1.5
            )
            for offset in [-8.0, 0.0, 8.0] {
                var steam = Path()
                let x = size.width / 2 + offset
                steam.move(to: CGPoint(x: x, y: size.height * 0.30))
                steam.addQuadCurve(
                    to: CGPoint(x: x + 3, y: size.height * 0.16),
                    control: CGPoint(x: x - 4, y: size.height * 0.23)
                )
                context.stroke(steam, with: .color(SaveAtlasPalette.ink), lineWidth: 1.2)
            }
        }
    }
}

extension SaveDoodleStickerKind {
    var usesOfficialAsset: Bool {
        switch self {
        case .duck, .noodles, .coffee, .temple, .lantern:
            return true
        default:
            return false
        }
    }

    var systemImageName: String {
        switch self {
        case .tea, .tree: return "leaf"
        case .hill: return "mountain.2"
        case .bookstore: return "book.closed"
        case .bicycle: return "bicycle"
        case .ferris: return "ferriswheel"
        case .museum: return "building.columns"
        case .wine: return "wineglass"
        case .beer: return "mug"
        case .bag: return "bag"
        case .dessert: return "birthday.cake"
        case .hotpot: return "flame"
        case .camera: return "camera"
        case .pin: return "mappin"
        case .beach: return "water.waves"
        case .duck, .noodles, .coffee, .temple, .lantern, .baozi, .bridge:
            return "circle"
        }
    }

    /// Place marks only. Extra catalog kinds map to the nearest official
    /// place sticker. Never returns `.elephant` — that mark is brand-only.
    var officialSticker: SaveDoodleOfficialSticker {
        let mapped: SaveDoodleOfficialSticker
        switch self {
        case .duck, .baozi, .dessert:
            mapped = .duck
        case .noodles, .hotpot:
            mapped = .noodle
        case .coffee, .tea:
            mapped = .coffee
        case .temple, .tree, .hill, .museum, .beach, .bridge, .camera, .bicycle, .ferris, .pin:
            mapped = .temple
        case .lantern, .wine, .beer, .bag, .bookstore:
            mapped = .lantern
        }
        return SaveDoodleOfficialSticker.placeCases.contains(mapped) ? mapped : .temple
    }
}
