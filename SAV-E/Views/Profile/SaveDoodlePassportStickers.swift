import SwiftUI

/// Hand-drawn Passport stickers. Outline (pencil) for saved-not-visited;
/// color + ink for a visit. Rank rings overlay in `SaveDoodlePassportStamp`.
struct SaveDoodlePassportSticker: View {
    let kind: SaveDoodleStickerKind
    let visited: Bool

    var body: some View {
        SaveDoodlePassportStickerArt(kind: kind, visited: visited)
            .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportStamp: View {
    let rank: SavePassportStampRank
    let seed: String

    var body: some View {
        Group {
            switch rank {
            case .none:
                EmptyView()
            case .single:
                Circle()
                    .stroke(SaveDoodle.stampRed, lineWidth: 2)
            case .double:
                ZStack {
                    Circle().stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                    Circle()
                        .stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                        .padding(4)
                }
            case .gold:
                Circle()
                    .stroke(SaveDoodle.stampGold, lineWidth: 2.5)
            }
        }
        .rotationEffect(.degrees(SaveDoodlePassportCatalog.rotationDegrees(for: seed)))
        .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportSlotView: View {
    let slot: SaveDoodlePassportSlot
    var isStamping: Bool = false

    var body: some View {
        ZStack {
            switch slot.content {
            case let .place(_, kind, rank):
                if rank == .none {
                    Circle()
                        .stroke(
                            SaveDoodle.pencil,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
                SaveDoodlePassportSticker(kind: kind, visited: rank != .none)
                    .padding(SaveSpace.tight)
                SaveDoodlePassportStamp(rank: rank, seed: slot.id)
            case .empty:
                Circle()
                    .stroke(
                        SaveDoodle.pencil,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
        }
        .frame(
            width: SaveDoodlePassportCatalog.slotSize,
            height: SaveDoodlePassportCatalog.slotSize
        )
        .scaleEffect(isStamping ? 1.08 : 1)
        .animation(SaveTheme.Motion.stampSpring, value: isStamping)
    }
}

private struct SaveDoodlePassportStickerArt: View {
    let kind: SaveDoodleStickerKind
    let visited: Bool

    var body: some View {
        Canvas { context, size in
            let ink = visited ? SaveAtlasPalette.ink : SaveDoodle.pencil
            let path = glyph(in: CGRect(origin: .zero, size: size))
            if visited {
                context.fill(path, with: .color(fillColor.opacity(0.92)))
            }
            context.stroke(
                path,
                with: .color(ink),
                style: StrokeStyle(lineWidth: visited ? 1.5 : 1.2, lineCap: .round, lineJoin: .round)
            )
            if visited {
                extraColor(in: size).forEach { extra in
                    context.fill(extra.path, with: .color(extra.color.opacity(0.9)))
                    context.stroke(
                        extra.path,
                        with: .color(Color(ink)),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var fillColor: Color {
        switch kind {
        case .duck: return Color(red: 0.72, green: 0.38, blue: 0.22)
        case .noodles: return Color(red: 0.93, green: 0.78, blue: 0.42)
        case .coffee, .tea: return Color(red: 0.62, green: 0.42, blue: 0.28)
        case .baozi, .dessert: return Color(red: 0.96, green: 0.86, blue: 0.70)
        case .wine, .hotpot: return SaveDoodle.stampRed
        case .beer: return Color(red: 0.90, green: 0.72, blue: 0.28)
        case .temple, .lantern: return SaveDoodle.stampRed
        case .tree: return SaveDoodle.washGreen
        case .hill: return Color(red: 0.62, green: 0.58, blue: 0.42)
        case .bridge, .bicycle, .ferris, .camera, .museum, .bookstore:
            return Color(red: 0.55, green: 0.58, blue: 0.62)
        case .bag: return Color(red: 0.86, green: 0.62, blue: 0.38)
        case .beach: return SaveDoodle.washBlue
        case .pin: return SaveAtlasPalette.coral
        }
    }

    private struct Extra {
        let path: Path
        let color: Color
    }

    private func extraColor(in size: CGSize) -> [Extra] {
        let rect = CGRect(origin: .zero, size: size)
        switch kind {
        case .noodles:
            var waves = Path()
            waves.move(to: CGPoint(x: rect.w(0.32), y: rect.h(0.42)))
            waves.addQuadCurve(
                to: CGPoint(x: rect.w(0.70), y: rect.h(0.40)),
                control: CGPoint(x: rect.w(0.50), y: rect.h(0.30))
            )
            waves.move(to: CGPoint(x: rect.w(0.30), y: rect.h(0.52)))
            waves.addQuadCurve(
                to: CGPoint(x: rect.w(0.72), y: rect.h(0.50)),
                control: CGPoint(x: rect.w(0.50), y: rect.h(0.60))
            )
            return [Extra(path: waves, color: Color(red: 0.93, green: 0.82, blue: 0.42))]
        case .lantern:
            var tassel = Path()
            tassel.addEllipse(in: CGRect(
                x: rect.w(0.44), y: rect.h(0.78), width: rect.w(0.12), height: rect.h(0.12)
            ))
            return [Extra(path: tassel, color: Color(SaveDoodle.stampGold))]
        default:
            return []
        }
    }

    private func glyph(in rect: CGRect) -> Path {
        switch kind {
        case .duck: return duck(in: rect)
        case .noodles: return bowl(in: rect)
        case .coffee, .tea: return cup(in: rect, tea: kind == .tea)
        case .baozi: return bun(in: rect)
        case .dessert: return cake(in: rect)
        case .wine: return wine(in: rect)
        case .beer: return mug(in: rect)
        case .temple: return temple(in: rect)
        case .tree: return tree(in: rect)
        case .hill: return hill(in: rect)
        case .lantern: return lantern(in: rect)
        case .museum: return museum(in: rect)
        case .bag: return bag(in: rect)
        case .bookstore: return books(in: rect)
        case .beach: return beach(in: rect)
        case .bridge: return bridge(in: rect)
        case .camera: return camera(in: rect)
        case .hotpot: return pot(in: rect)
        case .pin: return pin(in: rect)
        case .bicycle: return bicycle(in: rect)
        case .ferris: return ferris(in: rect)
        }
    }

    private func duck(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.18), y: r.h(0.38), width: r.w(0.58), height: r.h(0.40)))
        p.addEllipse(in: CGRect(x: r.w(0.52), y: r.h(0.18), width: r.w(0.30), height: r.h(0.28)))
        p.move(to: CGPoint(x: r.w(0.80), y: r.h(0.30)))
        p.addLine(to: CGPoint(x: r.w(0.96), y: r.h(0.34)))
        p.addLine(to: CGPoint(x: r.w(0.80), y: r.h(0.40)))
        p.move(to: CGPoint(x: r.w(0.32), y: r.h(0.74)))
        p.addLine(to: CGPoint(x: r.w(0.28), y: r.h(0.88)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.76)))
        p.addLine(to: CGPoint(x: r.w(0.52), y: r.h(0.90)))
        return p
    }

    private func bowl(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.16), y: r.h(0.42)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.84), y: r.h(0.42)), control: CGPoint(x: r.w(0.50), y: r.h(0.18)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.16), y: r.h(0.42)), control: CGPoint(x: r.w(0.50), y: r.h(0.92)))
        p.move(to: CGPoint(x: r.w(0.28), y: r.h(0.38)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.48), y: r.h(0.22)), control: CGPoint(x: r.w(0.30), y: r.h(0.18)))
        p.move(to: CGPoint(x: r.w(0.40), y: r.h(0.40)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.66), y: r.h(0.20)), control: CGPoint(x: r.w(0.58), y: r.h(0.14)))
        return p
    }

    private func cup(in r: CGRect, tea: Bool) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: r.w(0.26), y: r.h(0.30), width: r.w(0.44), height: r.h(0.38)),
            cornerSize: CGSize(width: 6, height: 6)
        )
        p.addEllipse(in: CGRect(x: r.w(0.22), y: r.h(0.70), width: r.w(0.52), height: r.h(0.12)))
        p.addEllipse(in: CGRect(x: r.w(0.66), y: r.h(0.38), width: r.w(0.18), height: r.h(0.22)))
        if tea {
            p.move(to: CGPoint(x: r.w(0.40), y: r.h(0.18)))
            p.addQuadCurve(to: CGPoint(x: r.w(0.58), y: r.h(0.16)), control: CGPoint(x: r.w(0.48), y: r.h(0.04)))
        } else {
            p.move(to: CGPoint(x: r.w(0.36), y: r.h(0.16)))
            p.addQuadCurve(to: CGPoint(x: r.w(0.40), y: r.h(0.28)), control: CGPoint(x: r.w(0.28), y: r.h(0.22)))
            p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.14)))
            p.addQuadCurve(to: CGPoint(x: r.w(0.54), y: r.h(0.28)), control: CGPoint(x: r.w(0.60), y: r.h(0.18)))
        }
        return p
    }

    private func bun(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.18), y: r.h(0.28), width: r.w(0.64), height: r.h(0.50)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.32)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.70)))
        p.move(to: CGPoint(x: r.w(0.34), y: r.h(0.40)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.50), y: r.h(0.52)), control: CGPoint(x: r.w(0.38), y: r.h(0.58)))
        p.move(to: CGPoint(x: r.w(0.66), y: r.h(0.40)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.50), y: r.h(0.52)), control: CGPoint(x: r.w(0.62), y: r.h(0.58)))
        return p
    }

    private func cake(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.18)))
        p.addLine(to: CGPoint(x: r.w(0.84), y: r.h(0.78)))
        p.addLine(to: CGPoint(x: r.w(0.16), y: r.h(0.78)))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.w(0.28), y: r.h(0.58)))
        p.addLine(to: CGPoint(x: r.w(0.72), y: r.h(0.58)))
        return p
    }

    private func wine(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.32), y: r.h(0.16)))
        p.addLine(to: CGPoint(x: r.w(0.68), y: r.h(0.16)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.50), y: r.h(0.58)), control: CGPoint(x: r.w(0.78), y: r.h(0.40)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.32), y: r.h(0.16)), control: CGPoint(x: r.w(0.22), y: r.h(0.40)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.58)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.82)))
        p.move(to: CGPoint(x: r.w(0.34), y: r.h(0.84)))
        p.addLine(to: CGPoint(x: r.w(0.66), y: r.h(0.84)))
        return p
    }

    private func mug(in r: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: r.w(0.22), y: r.h(0.22), width: r.w(0.46), height: r.h(0.56)),
            cornerSize: CGSize(width: 8, height: 8)
        )
        p.addEllipse(in: CGRect(x: r.w(0.64), y: r.h(0.38), width: r.w(0.20), height: r.h(0.28)))
        return p
    }

    private func temple(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.12), y: r.h(0.42)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.16)))
        p.addLine(to: CGPoint(x: r.w(0.88), y: r.h(0.42)))
        p.addLine(to: CGPoint(x: r.w(0.12), y: r.h(0.42)))
        p.addRect(CGRect(x: r.w(0.22), y: r.h(0.42), width: r.w(0.56), height: r.h(0.40)))
        p.move(to: CGPoint(x: r.w(0.38), y: r.h(0.42)))
        p.addLine(to: CGPoint(x: r.w(0.38), y: r.h(0.82)))
        p.move(to: CGPoint(x: r.w(0.62), y: r.h(0.42)))
        p.addLine(to: CGPoint(x: r.w(0.62), y: r.h(0.82)))
        return p
    }

    private func tree(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.22), y: r.h(0.14), width: r.w(0.56), height: r.h(0.52)))
        p.addRect(CGRect(x: r.w(0.46), y: r.h(0.58), width: r.w(0.08), height: r.h(0.28)))
        return p
    }

    private func hill(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.08), y: r.h(0.78)))
        p.addLine(to: CGPoint(x: r.w(0.38), y: r.h(0.28)))
        p.addLine(to: CGPoint(x: r.w(0.62), y: r.h(0.52)))
        p.addLine(to: CGPoint(x: r.w(0.78), y: r.h(0.34)))
        p.addLine(to: CGPoint(x: r.w(0.94), y: r.h(0.78)))
        p.closeSubpath()
        return p
    }

    private func lantern(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.28), y: r.h(0.22), width: r.w(0.44), height: r.h(0.56)))
        p.addRect(CGRect(x: r.w(0.40), y: r.h(0.12), width: r.w(0.20), height: r.h(0.12)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.78)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.90)))
        return p
    }

    private func museum(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.16), y: r.h(0.40)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.16)))
        p.addLine(to: CGPoint(x: r.w(0.84), y: r.h(0.40)))
        p.closeSubpath()
        p.addRect(CGRect(x: r.w(0.22), y: r.h(0.40), width: r.w(0.56), height: r.h(0.42)))
        p.move(to: CGPoint(x: r.w(0.34), y: r.h(0.52)))
        p.addLine(to: CGPoint(x: r.w(0.34), y: r.h(0.82)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.52)))
        p.addLine(to: CGPoint(x: r.w(0.50), y: r.h(0.82)))
        p.move(to: CGPoint(x: r.w(0.66), y: r.h(0.52)))
        p.addLine(to: CGPoint(x: r.w(0.66), y: r.h(0.82)))
        return p
    }

    private func bag(in r: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: r.w(0.24), y: r.h(0.36), width: r.w(0.52), height: r.h(0.46)),
            cornerSize: CGSize(width: 6, height: 6)
        )
        p.move(to: CGPoint(x: r.w(0.34), y: r.h(0.36)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.66), y: r.h(0.36)), control: CGPoint(x: r.w(0.50), y: r.h(0.12)))
        return p
    }

    private func books(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: r.w(0.22), y: r.h(0.28), width: r.w(0.28), height: r.h(0.50)))
        p.addRect(CGRect(x: r.w(0.50), y: r.h(0.22), width: r.w(0.28), height: r.h(0.56)))
        return p
    }

    private func beach(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.18), y: r.h(0.16), width: r.w(0.28), height: r.h(0.28)))
        p.move(to: CGPoint(x: r.w(0.12), y: r.h(0.62)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.50), y: r.h(0.70)), control: CGPoint(x: r.w(0.30), y: r.h(0.50)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.90), y: r.h(0.64)), control: CGPoint(x: r.w(0.70), y: r.h(0.86)))
        return p
    }

    private func bridge(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.08), y: r.h(0.70)))
        p.addLine(to: CGPoint(x: r.w(0.92), y: r.h(0.70)))
        p.move(to: CGPoint(x: r.w(0.16), y: r.h(0.70)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.50), y: r.h(0.70)), control: CGPoint(x: r.w(0.33), y: r.h(0.28)))
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.70)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.84), y: r.h(0.70)), control: CGPoint(x: r.w(0.67), y: r.h(0.28)))
        p.move(to: CGPoint(x: r.w(0.20), y: r.h(0.70)))
        p.addLine(to: CGPoint(x: r.w(0.20), y: r.h(0.84)))
        p.move(to: CGPoint(x: r.w(0.80), y: r.h(0.70)))
        p.addLine(to: CGPoint(x: r.w(0.80), y: r.h(0.84)))
        return p
    }

    private func camera(in r: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: r.w(0.16), y: r.h(0.32), width: r.w(0.68), height: r.h(0.42)),
            cornerSize: CGSize(width: 8, height: 8)
        )
        p.addEllipse(in: CGRect(x: r.w(0.38), y: r.h(0.38), width: r.w(0.26), height: r.h(0.26)))
        p.addRect(CGRect(x: r.w(0.28), y: r.h(0.22), width: r.w(0.18), height: r.h(0.12)))
        return p
    }

    private func pot(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.18), y: r.h(0.38), width: r.w(0.64), height: r.h(0.44)))
        p.addRect(CGRect(x: r.w(0.28), y: r.h(0.32), width: r.w(0.44), height: r.h(0.10)))
        p.move(to: CGPoint(x: r.w(0.38), y: r.h(0.18)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.42), y: r.h(0.32)), control: CGPoint(x: r.w(0.28), y: r.h(0.24)))
        p.move(to: CGPoint(x: r.w(0.56), y: r.h(0.16)))
        p.addQuadCurve(to: CGPoint(x: r.w(0.60), y: r.h(0.32)), control: CGPoint(x: r.w(0.70), y: r.h(0.22)))
        return p
    }

    private func pin(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.88)))
        p.addCurve(
            to: CGPoint(x: r.w(0.22), y: r.h(0.38)),
            control1: CGPoint(x: r.w(0.20), y: r.h(0.62)),
            control2: CGPoint(x: r.w(0.18), y: r.h(0.48))
        )
        p.addArc(
            center: CGPoint(x: r.w(0.50), y: r.h(0.34)),
            radius: r.w(0.28),
            startAngle: .degrees(200),
            endAngle: .degrees(-20),
            clockwise: false
        )
        p.addCurve(
            to: CGPoint(x: r.w(0.50), y: r.h(0.88)),
            control1: CGPoint(x: r.w(0.82), y: r.h(0.48)),
            control2: CGPoint(x: r.w(0.80), y: r.h(0.62))
        )
        p.addEllipse(in: CGRect(x: r.w(0.40), y: r.h(0.24), width: r.w(0.20), height: r.h(0.20)))
        return p
    }

    private func bicycle(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.10), y: r.h(0.46), width: r.w(0.32), height: r.h(0.32)))
        p.addEllipse(in: CGRect(x: r.w(0.58), y: r.h(0.46), width: r.w(0.32), height: r.h(0.32)))
        p.move(to: CGPoint(x: r.w(0.26), y: r.h(0.62)))
        p.addLine(to: CGPoint(x: r.w(0.46), y: r.h(0.34)))
        p.addLine(to: CGPoint(x: r.w(0.74), y: r.h(0.62)))
        p.move(to: CGPoint(x: r.w(0.46), y: r.h(0.34)))
        p.addLine(to: CGPoint(x: r.w(0.38), y: r.h(0.28)))
        return p
    }

    private func ferris(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.w(0.16), y: r.h(0.12), width: r.w(0.68), height: r.h(0.68)))
        p.addEllipse(in: CGRect(x: r.w(0.44), y: r.h(0.40), width: r.w(0.12), height: r.h(0.12)))
        for angle in stride(from: 0.0, to: 360.0, by: 45) {
            let radians = angle * .pi / 180
            p.move(to: CGPoint(x: r.w(0.50), y: r.h(0.46)))
            p.addLine(to: CGPoint(
                x: r.w(0.50) + cos(radians) * r.w(0.32),
                y: r.h(0.46) + sin(radians) * r.h(0.32)
            ))
        }
        p.move(to: CGPoint(x: r.w(0.36), y: r.h(0.78)))
        p.addLine(to: CGPoint(x: r.w(0.22), y: r.h(0.92)))
        p.move(to: CGPoint(x: r.w(0.64), y: r.h(0.78)))
        p.addLine(to: CGPoint(x: r.w(0.78), y: r.h(0.92)))
        return p
    }
}

private extension CGRect {
    func w(_ unit: CGFloat) -> CGFloat { minX + width * unit }
    func h(_ unit: CGFloat) -> CGFloat { minY + height * unit }
}
