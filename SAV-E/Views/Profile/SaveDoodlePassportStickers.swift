import SwiftUI
import UIKit

/// Passport-only chrome. Do not replace `SaveAtlasPalette.kraft` globally —
/// other screens still use the locked kraft pair.
enum SaveDoodlePassportChrome {
    static let panelFill = Color(
        light: SaveDoodlePassportCatalog.panelFillLightHex,
        dark: SaveDoodlePassportCatalog.panelFillDarkHex
    )
    static let panelStroke = Color(
        light: SaveDoodlePassportCatalog.panelStrokeLightHex,
        dark: SaveDoodlePassportCatalog.panelStrokeDarkHex
    )
    static let discFill = Color(
        light: SaveDoodlePassportCatalog.discFillLightHex,
        dark: SaveDoodlePassportCatalog.discFillDarkHex
    )
    static let stampBase = Color(
        light: SaveDoodlePassportCatalog.stampBaseLightHex,
        dark: SaveDoodlePassportCatalog.stampBaseDarkHex
    )
    static let stampRed = Color(
        light: SaveDoodlePassportCatalog.stampRingRedHex,
        dark: "E0675C"
    )
    static let stampGold = Color(
        light: SaveDoodlePassportCatalog.stampRingGoldHex,
        dark: "D9B45A"
    )
    static let legendSwatch = Color(
        light: SaveDoodlePassportCatalog.legendSwatchHex,
        dark: "E0675C"
    )
}

/// DESIGN color rasters for the 8 unvisited discs. One asset-name-keyed
/// lookup. Until DESIGN drops the imagesets, `resolvedImageName` is nil
/// and the slot keeps today's line art (official coffee outline or
/// `SaveDoodlePassportUniqueGlyph`). Do not draw those illustrations here.
enum SaveDoodlePassportUnvisitedArt {
    static let assetNames: [SaveDoodleStickerKind: String] = [
        .coffee: "DoodlePassportArtCoffee",
        .hill: "DoodlePassportArtHill",
        .bridge: "DoodlePassportArtBridge",
        .baozi: "DoodlePassportArtBaozi",
        .tea: "DoodlePassportArtTea",
        .bookstore: "DoodlePassportArtBookstore",
        .bicycle: "DoodlePassportArtBicycle",
        .ferris: "DoodlePassportArtFerris",
    ]

    static func assetName(for kind: SaveDoodleStickerKind) -> String? {
        assetNames[kind]
    }

    /// Nil when the imageset is not in the catalog yet.
    @MainActor
    static func resolvedImageName(for kind: SaveDoodleStickerKind) -> String? {
        guard let name = assetName(for: kind), UIImage(named: name) != nil else { return nil }
        return name
    }
}

/// Official DESIGN stickers when the kind has a unique asset. Extra kinds
/// keep their own glyph so unvisited cells do not collapse to five repeats.
/// Number stamps overlay the visited sticker. Do not wrap a shrunken icon in
/// a filled circle.
struct SaveDoodlePassportSticker: View {
    let kind: SaveDoodleStickerKind
    let visited: Bool

    var body: some View {
        if visited, kind.usesOfficialAsset {
            Image(kind.officialSticker.imageName(
                visited: true,
                pointSize: SaveDoodlePassportCatalog.visitedStickerSize.width
            ))
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(
                width: SaveDoodlePassportCatalog.visitedStickerSize.width,
                height: SaveDoodlePassportCatalog.visitedStickerSize.height
            )
            .accessibilityHidden(true)
        } else if let colorArt = SaveDoodlePassportUnvisitedArt.resolvedImageName(for: kind) {
            Image(colorArt)
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .scaledToFit()
                .frame(
                    width: SaveDoodlePassportCatalog.unvisitedArtSize,
                    height: SaveDoodlePassportCatalog.unvisitedArtSize
                )
                .accessibilityHidden(true)
        } else if kind.usesOfficialAsset {
            Image(kind.officialSticker.imageName(
                visited: false,
                pointSize: SaveDoodlePassportCatalog.unvisitedArtSize
            ))
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(
                width: SaveDoodlePassportCatalog.unvisitedArtSize,
                height: SaveDoodlePassportCatalog.unvisitedArtSize
            )
            .accessibilityHidden(true)
        } else {
            SaveDoodlePassportUniqueGlyph(kind: kind)
                .frame(
                    width: SaveDoodlePassportCatalog.unvisitedArtSize,
                    height: SaveDoodlePassportCatalog.unvisitedArtSize
                )
                .accessibilityHidden(true)
        }
    }
}

struct SaveDoodlePassportNumberStamp: View {
    let number: Int
    var rank: SavePassportStampRank = .single

    var body: some View {
        let ring = rank == .gold
            ? SaveDoodlePassportChrome.stampGold
            : SaveDoodlePassportChrome.stampRed
        ZStack {
            Circle()
                .fill(SaveDoodlePassportChrome.stampBase)
            if rank == .double {
                Circle()
                    .stroke(ring, lineWidth: 1.25)
                    .padding(3.5)
            }
            Circle()
                .stroke(ring, lineWidth: 2)
            Text("\(number)")
                .font(SaveDisplayType.fixed(14))
                .foregroundStyle(ring)
        }
        .frame(
            width: SaveDoodlePassportCatalog.stampDiameter,
            height: SaveDoodlePassportCatalog.stampDiameter
        )
        .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportSlotView: View {
    let slot: SaveDoodlePassportSlot
    var isStamping: Bool = false

    var body: some View {
        ZStack {
            if showsCard {
                Circle()
                    .stroke(
                        SaveDoodle.pencil,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .background(
                        SaveDoodlePassportChrome.discFill
                            .clipShape(Circle())
                    )
                    .frame(
                        width: SaveDoodlePassportCatalog.unvisitedDiscSize,
                        height: SaveDoodlePassportCatalog.unvisitedDiscSize
                    )
            }
            switch slot.content {
            case let .place(_, kind, rank):
                SaveDoodlePassportSticker(kind: kind, visited: rank != .none)
            case .empty:
                EmptyView()
            }
            if let number = slot.stampNumber {
                SaveDoodlePassportNumberStamp(number: number, rank: stampRank)
                    .offset(
                        x: SaveDoodlePassportCatalog.stampOffset.width,
                        y: SaveDoodlePassportCatalog.stampOffset.height
                    )
            }
        }
        .frame(
            width: SaveDoodlePassportCatalog.cardHeight,
            height: SaveDoodlePassportCatalog.cardHeight
        )
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

    private var stampRank: SavePassportStampRank {
        if case let .place(_, _, rank) = slot.content { return rank }
        return .single
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
                .font(.system(size: 22, weight: .light))
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
