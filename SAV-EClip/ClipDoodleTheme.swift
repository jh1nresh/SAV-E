import CoreText
import SwiftUI
import UIKit

/// Clip Doodle v3.1 tokens. Catalog colors are the source.
/// Coral stays `#F26B4A` in light and dark (`ClipCoral`).
enum ClipJournalPalette {
    static let canvas = Color("ClipCanvas")
    static let card = Color("ClipCard")
    static let paper = canvas
    static let ink = Color("ClipInk")
    static let muted = Color("ClipMuted")
    static let line = Color("ClipLine")
    static let kraft = Color("ClipKraft")
    static let coral = Color("ClipCoral")
    static let cream = Color("ClipCream")
    static let forest = Color("ClipForest")
    static let cardRadius: CGFloat = 16
    nonisolated static let strokeWidth: CGFloat = 1.6
}

enum ClipJournalLayout {
    static let screenMargin: CGFloat = 24
    static let heroWidth: CGFloat = 393
    static let heroHeight: CGFloat = 470
    static let heroHeightRatio: CGFloat = 0.55
    static let heroCircle: CGFloat = 236
    static let heroSticker: CGFloat = 128
    static let wordmarkHeight: CGFloat = 34
    static let wordmarkPlateHeight: CGFloat = 40
    static let chipHeight: CGFloat = 32
    static let avatar: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let stickerCanvas: CGFloat = 48
    static let stickerImage: CGFloat = 40
    static let minTap: CGFloat = 44
    static let buttonHeight: CGFloat = 54
    static let buttonGap: CGFloat = 12
    static let buttonGroupBottom: CGFloat = 28
    static let stateCircle: CGFloat = 120
    static let stateSticker: CGFloat = 84
    static let stateBadge: CGFloat = 40
    static let stateTitleGap: CGFloat = 24
    static let stateBodyGap: CGFloat = 12
    static let stateBodyMaxWidth: CGFloat = 300
    static let namePointLatin: CGFloat = 38
    static let namePointCJK: CGFloat = 34
    static let listTitlePoint: CGFloat = 22
    static let noteRotation: Double = -1.2
    static let dotGridStep: CGFloat = 14
}

enum ClipJournalType {
    static func system(
        _ size: CGFloat,
        weight: UIFont.Weight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: font))
    }
}

enum ClipDisplayType {
    static let latinName = "Caveat-SemiBold"
    static let cjkName = "Iansui-Regular"

    private static let register: Void = {
        let files = [
            ("Caveat-SemiBold", "ttf"),
            ("Iansui-ClipTitles", "ttf"),
        ]
        for (name, ext) in files {
            let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "DisplayFont")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// Caveat (Latin) / Iansui (zh) for place names, list titles, and state titles.
    /// Ship Iansui-ClipTitles.ttf, not Iansui-SavvySubset.ttf (3.48 MB).
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        _ = register
        if ClipCopy.usesTraditionalChinese {
            let cjk = UIFont(name: cjkName, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .semibold)
            return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: cjk))
        }
        let latin = UIFont(name: latinName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: latin))
    }

    static var placeName: Font {
        title(
            ClipCopy.usesTraditionalChinese ? ClipJournalLayout.namePointCJK : ClipJournalLayout.namePointLatin,
            relativeTo: .title
        )
    }

    /// Forest handwritten wordmark. Fixed 34pt — not Dynamic Type scaled.
    static var wordmark: Font {
        _ = register
        let font = UIFont(name: latinName, size: ClipJournalLayout.wordmarkHeight)
            ?? UIFont.systemFont(ofSize: ClipJournalLayout.wordmarkHeight, weight: .semibold)
        return Font(font)
    }
}

enum ClipCopy {
    static var usesTraditionalChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("zh-Hant")
            || preferred.hasPrefix("zh-TW")
            || preferred.hasPrefix("zh-HK")
            || preferred.hasPrefix("zh_Hant")
            || preferred.hasPrefix("zh_TW")
            || preferred.hasPrefix("zh_HK")
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: String(localized: String.LocalizationValue(stringLiteral: key)), arguments: arguments)
    }
}

struct ClipWordmark: View {
    var body: some View {
        Text("Savvy")
            .font(ClipDisplayType.wordmark)
            .foregroundStyle(ClipJournalPalette.forest)
            .lineLimit(1)
            .fixedSize()
            .frame(height: ClipJournalLayout.wordmarkHeight, alignment: .center)
            .accessibilityHidden(true)
    }
}

struct ClipWordmarkPlate: View {
    var body: some View {
        ClipWordmark()
            .padding(.horizontal, 12)
            .frame(height: ClipJournalLayout.wordmarkPlateHeight)
            .background(ClipJournalPalette.cream, in: Capsule())
            .overlay {
                ClipJitterCapsule(seed: 19)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
    }
}

struct ClipDisplayTitle: View {
    let text: String
    var pointSize: CGFloat = 28
    var relativeTo: Font.TextStyle = .title
    var color: Color = ClipJournalPalette.forest

    var body: some View {
        Text(text)
            .font(ClipDisplayType.title(pointSize, relativeTo: relativeTo))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ClipDottedBackground: View {
    var body: some View {
        ClipJournalPalette.canvas
            .overlay {
                Canvas { context, size in
                    let step = ClipJournalLayout.dotGridStep
                    let dot = ClipJournalPalette.line.opacity(0.22)
                    var x: CGFloat = 7
                    while x < size.width {
                        var y: CGFloat = 7
                        while y < size.height {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                                with: .color(dot)
                            )
                            y += step
                        }
                        x += step
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

nonisolated struct ClipJitterRoundedRect: Shape {
    var radius: CGFloat
    var seed: UInt64 = 1

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: radius, seed: seed)
    }
}

nonisolated struct ClipJitterCapsule: Shape {
    var seed: UInt64 = 2

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: min(rect.width, rect.height) / 2, seed: seed)
    }
}

nonisolated struct ClipJitterCircle: Shape {
    var seed: UInt64 = 4

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: min(rect.width, rect.height) / 2, seed: seed)
    }
}

nonisolated struct ClipTornPaperEdge: Shape {
    var seed: UInt64 = 21

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 14))
        var x = rect.maxX
        var index = 0
        while x > rect.minX {
            let next = max(x - 18, rect.minX)
            let wave = sin(Double(index) * 1.7 + Double(seed) * 0.31)
            let y = rect.maxY - 10 + CGFloat(wave) * 6
            path.addLine(to: CGPoint(x: next, y: y))
            x = next
            index += 1
        }
        path.closeSubpath()
        return path
    }
}

nonisolated private func jitteredPath(in rect: CGRect, cornerRadius: CGFloat, seed: UInt64) -> Path {
    let inset = ClipJournalPalette.strokeWidth / 2
    let bounds = rect.insetBy(dx: inset, dy: inset)
    let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
    let base = Path(roundedRect: bounds, cornerRadius: radius)
    var jittered = Path()
    var index = 0
    base.trimmedPath(from: 0, to: 1).forEach { element in
        switch element {
        case .move(let point):
            jittered.move(to: jitter(point, index: index, seed: seed, in: bounds))
        case .line(let point):
            jittered.addLine(to: jitter(point, index: index, seed: seed, in: bounds))
        case .quadCurve(let point, let control):
            jittered.addQuadCurve(
                to: jitter(point, index: index, seed: seed, in: bounds),
                control: jitter(control, index: index &+ 17, seed: seed, in: bounds)
            )
        case .curve(let point, let control1, let control2):
            jittered.addCurve(
                to: jitter(point, index: index, seed: seed, in: bounds),
                control1: jitter(control1, index: index &+ 11, seed: seed, in: bounds),
                control2: jitter(control2, index: index &+ 23, seed: seed, in: bounds)
            )
        case .closeSubpath:
            jittered.closeSubpath()
        }
        index += 1
    }
    if jittered.isEmpty {
        return base
    }
    return jittered
}

nonisolated private func jitter(_ point: CGPoint, index: Int, seed: UInt64, in bounds: CGRect) -> CGPoint {
    let wave = sin(Double(index) * 1.7 + Double(seed) * 0.37)
    let offset = CGFloat(wave) * 0.85
    let x = min(max(point.x + offset, bounds.minX - 1), bounds.maxX + 1)
    let y = min(max(point.y + CGFloat(cos(Double(index) * 1.3 + Double(seed))) * 0.7, bounds.minY - 1), bounds.maxY + 1)
    return CGPoint(x: x, y: y)
}

enum ClipStickerKind: String {
    case noodle, coffee, lantern, place, seal

    static func forHero(_ raw: String?) -> ClipStickerKind {
        let value = (raw ?? "").lowercased()
        if value.contains("cafe") || value.contains("coffee") || value.contains("咖啡") {
            return .coffee
        }
        if value.contains("food") || value.contains("restaurant") || value.contains("noodle")
            || value.contains("餐") || value.contains("麵") || value.contains("面") {
            return .noodle
        }
        return .place
    }
}

struct ClipStickerDrawing: View {
    let kind: ClipStickerKind
    var lineArtPin: Bool = false

    var body: some View {
        Canvas { context, size in
            let ink = ClipJournalPalette.ink
            let coral = ClipJournalPalette.coral
            let cream = ClipJournalPalette.cream
            let kraft = ClipJournalPalette.kraft
            let forest = ClipJournalPalette.forest
            switch kind {
            case .noodle:
                drawNoodleBowl(context: context, size: size, ink: ink, coral: coral, cream: cream, kraft: kraft)
            case .coffee:
                drawCoffeeCup(context: context, size: size, ink: ink, coral: coral, cream: cream, kraft: kraft)
            case .lantern:
                drawLantern(context: context, size: size, ink: ink, coral: coral, cream: cream)
            case .seal:
                drawPostageStamp(context: context, size: size, ink: ink, coral: coral, cream: cream, kraft: kraft, forest: forest)
            case .place:
                drawMapPin(
                    context: context,
                    size: size,
                    ink: ink,
                    coral: coral,
                    cream: cream,
                    lineArt: lineArtPin
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// DESIGN v3.1: restaurant = noodle bowl + plate (not a temple or duck).
    private func drawNoodleBowl(
        context: GraphicsContext,
        size: CGSize,
        ink: Color,
        coral: Color,
        cream: Color,
        kraft: Color
    ) {
        var plate = Path()
        plate.addEllipse(in: CGRect(x: size.width * 0.06, y: size.height * 0.58, width: size.width * 0.88, height: size.height * 0.30))
        context.fill(plate, with: .color(kraft))
        context.stroke(plate, with: .color(ink), lineWidth: 1.4)

        var bowl = Path()
        bowl.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.42))
        bowl.addQuadCurve(
            to: CGPoint(x: size.width * 0.82, y: size.height * 0.42),
            control: CGPoint(x: size.width * 0.50, y: size.height * 0.28)
        )
        bowl.addQuadCurve(
            to: CGPoint(x: size.width * 0.74, y: size.height * 0.72),
            control: CGPoint(x: size.width * 0.88, y: size.height * 0.62)
        )
        bowl.addQuadCurve(
            to: CGPoint(x: size.width * 0.26, y: size.height * 0.72),
            control: CGPoint(x: size.width * 0.50, y: size.height * 0.84)
        )
        bowl.addQuadCurve(
            to: CGPoint(x: size.width * 0.18, y: size.height * 0.42),
            control: CGPoint(x: size.width * 0.12, y: size.height * 0.62)
        )
        context.fill(bowl, with: .color(coral))
        context.stroke(bowl, with: .color(ink), lineWidth: 1.6)

        var broth = Path()
        broth.addEllipse(in: CGRect(x: size.width * 0.24, y: size.height * 0.36, width: size.width * 0.52, height: size.height * 0.18))
        context.fill(broth, with: .color(cream.opacity(0.35)))

        for (start, control, end) in [
            (CGPoint(x: size.width * 0.30, y: size.height * 0.40), CGPoint(x: size.width * 0.48, y: size.height * 0.18), CGPoint(x: size.width * 0.70, y: size.height * 0.44)),
            (CGPoint(x: size.width * 0.28, y: size.height * 0.50), CGPoint(x: size.width * 0.52, y: size.height * 0.30), CGPoint(x: size.width * 0.68, y: size.height * 0.56)),
            (CGPoint(x: size.width * 0.34, y: size.height * 0.58), CGPoint(x: size.width * 0.56, y: size.height * 0.40), CGPoint(x: size.width * 0.64, y: size.height * 0.64)),
        ] {
            var noodle = Path()
            noodle.move(to: start)
            noodle.addQuadCurve(to: end, control: control)
            context.stroke(noodle, with: .color(cream), lineWidth: 2.4)
        }

        var chopstickA = Path()
        chopstickA.move(to: CGPoint(x: size.width * 0.58, y: size.height * 0.10))
        chopstickA.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.46))
        var chopstickB = Path()
        chopstickB.move(to: CGPoint(x: size.width * 0.66, y: size.height * 0.08))
        chopstickB.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.42))
        context.stroke(chopstickA, with: .color(ink), lineWidth: 2.0)
        context.stroke(chopstickB, with: .color(ink), lineWidth: 2.0)
    }

    /// DESIGN v3.1: cafe = coffee cup + saucer. Not a rounded-rect block.
    private func drawCoffeeCup(
        context: GraphicsContext,
        size: CGSize,
        ink: Color,
        coral: Color,
        cream: Color,
        kraft: Color
    ) {
        var saucer = Path()
        saucer.addEllipse(in: CGRect(x: size.width * 0.10, y: size.height * 0.64, width: size.width * 0.80, height: size.height * 0.22))
        context.fill(saucer, with: .color(kraft))
        context.stroke(saucer, with: .color(ink), lineWidth: 1.4)
        var well = Path()
        well.addEllipse(in: CGRect(x: size.width * 0.28, y: size.height * 0.70, width: size.width * 0.44, height: size.height * 0.10))
        context.stroke(well, with: .color(ink.opacity(0.45)), lineWidth: 1.0)

        var cup = Path()
        cup.move(to: CGPoint(x: size.width * 0.26, y: size.height * 0.30))
        cup.addQuadCurve(
            to: CGPoint(x: size.width * 0.70, y: size.height * 0.30),
            control: CGPoint(x: size.width * 0.48, y: size.height * 0.24)
        )
        cup.addQuadCurve(
            to: CGPoint(x: size.width * 0.64, y: size.height * 0.68),
            control: CGPoint(x: size.width * 0.74, y: size.height * 0.52)
        )
        cup.addQuadCurve(
            to: CGPoint(x: size.width * 0.32, y: size.height * 0.68),
            control: CGPoint(x: size.width * 0.48, y: size.height * 0.76)
        )
        cup.addQuadCurve(
            to: CGPoint(x: size.width * 0.26, y: size.height * 0.30),
            control: CGPoint(x: size.width * 0.22, y: size.height * 0.52)
        )
        context.fill(cup, with: .color(coral))
        context.stroke(cup, with: .color(ink), lineWidth: 1.6)

        var lip = Path()
        lip.addEllipse(in: CGRect(x: size.width * 0.26, y: size.height * 0.26, width: size.width * 0.44, height: size.height * 0.12))
        context.fill(lip, with: .color(cream.opacity(0.28)))
        context.stroke(lip, with: .color(ink), lineWidth: 1.2)

        var handle = Path()
        handle.addArc(
            center: CGPoint(x: size.width * 0.76, y: size.height * 0.46),
            radius: size.width * 0.13,
            startAngle: .degrees(-80),
            endAngle: .degrees(85),
            clockwise: false
        )
        context.stroke(handle, with: .color(ink), lineWidth: 2.4)

        for (x, controlX) in [(0.36, 0.32), (0.48, 0.50), (0.60, 0.64)] {
            var steam = Path()
            steam.move(to: CGPoint(x: size.width * x, y: size.height * 0.26))
            steam.addQuadCurve(
                to: CGPoint(x: size.width * x, y: size.height * 0.08),
                control: CGPoint(x: size.width * controlX, y: size.height * 0.16)
            )
            context.stroke(steam, with: .color(ink.opacity(0.7)), lineWidth: 1.4)
        }
    }

    private func drawLantern(
        context: GraphicsContext,
        size: CGSize,
        ink: Color,
        coral: Color,
        cream: Color
    ) {
        var cap = Path(roundedRect: CGRect(x: size.width * 0.34, y: size.height * 0.10, width: size.width * 0.32, height: size.height * 0.10), cornerRadius: 3)
        context.fill(cap, with: .color(ink.opacity(0.85)))

        var body = Path()
        body.addEllipse(in: CGRect(x: size.width * 0.22, y: size.height * 0.18, width: size.width * 0.56, height: size.height * 0.58))
        context.fill(body, with: .color(coral))
        context.stroke(body, with: .color(ink), lineWidth: 1.6)
        for factor in [0.32, 0.44, 0.56] {
            var ridge = Path()
            ridge.addEllipse(in: CGRect(x: size.width * 0.26, y: size.height * factor, width: size.width * 0.48, height: size.height * 0.06))
            context.stroke(ridge, with: .color(cream.opacity(0.55)), lineWidth: 1.2)
        }

        var tassel = Path()
        tassel.move(to: CGPoint(x: size.width * 0.50, y: size.height * 0.74))
        tassel.addQuadCurve(
            to: CGPoint(x: size.width * 0.50, y: size.height * 0.92),
            control: CGPoint(x: size.width * 0.58, y: size.height * 0.84)
        )
        context.stroke(tassel, with: .color(ink), lineWidth: 1.6)
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.46, y: size.height * 0.90, width: size.width * 0.08, height: size.height * 0.07)),
            with: .color(coral)
        )
    }

    /// Official Clip stamp: scalloped postage + coral map pin
    /// (`design-assets/app-store/app-clip-header-1800x1200.png`). Not a '#' ring.
    private func drawPostageStamp(
        context: GraphicsContext,
        size: CGSize,
        ink: Color,
        coral: Color,
        cream: Color,
        kraft: Color,
        forest: Color
    ) {
        let stamp = ClipScallopedStamp().path(in: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.06, dy: size.height * 0.06))
        context.fill(stamp, with: .color(kraft))
        context.stroke(stamp, with: .color(ink), lineWidth: 1.6)

        // Official header: small coral postage + cream paper-airplane, then cancel ring.
        let mini = CGRect(x: size.width * 0.62, y: size.height * 0.14, width: size.width * 0.22, height: size.height * 0.20)
        let miniStamp = ClipScallopedStamp().path(in: mini)
        context.fill(miniStamp, with: .color(coral))
        drawPaperAirplane(context: context, in: mini.insetBy(dx: mini.width * 0.22, dy: mini.height * 0.22), cream: cream)
        context.stroke(
            Path(ellipseIn: CGRect(x: size.width * 0.54, y: size.height * 0.16, width: size.width * 0.24, height: size.height * 0.24)),
            with: .color(ink.opacity(0.40)),
            lineWidth: 1.0
        )

        drawMapPin(
            context: context,
            size: CGSize(width: size.width * 0.70, height: size.height * 0.70),
            ink: ink,
            coral: coral,
            cream: cream,
            lineArt: false,
            origin: CGPoint(x: size.width * 0.12, y: size.height * 0.18)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: size.width * 0.16, y: size.height * 0.74, width: size.width * 0.22, height: size.height * 0.08)),
            with: .color(forest.opacity(0.45)),
            lineWidth: 1.0
        )
    }

    private func drawPaperAirplane(context: GraphicsContext, in rect: CGRect, cream: Color) {
        var plane = Path()
        plane.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22))
        plane.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.50))
        plane.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY))
        plane.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.56))
        plane.closeSubpath()
        context.fill(plane, with: .color(cream))
        var fold = Path()
        fold.move(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.56))
        fold.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.42))
        context.stroke(fold, with: .color(cream.opacity(0.55)), lineWidth: 0.8)
    }

    private func drawMapPin(
        context: GraphicsContext,
        size: CGSize,
        ink: Color,
        coral: Color,
        cream: Color,
        lineArt: Bool,
        origin: CGPoint = .zero
    ) {
        var pin = Path()
        let radius = size.width * 0.28
        let center = CGPoint(x: origin.x + size.width * 0.5, y: origin.y + size.height * 0.36)
        pin.addArc(center: center, radius: radius, startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: false)
        pin.addQuadCurve(
            to: CGPoint(x: origin.x + size.width * 0.5, y: origin.y + size.height * 0.92),
            control: CGPoint(x: origin.x + size.width * 0.86, y: origin.y + size.height * 0.62)
        )
        pin.addQuadCurve(
            to: CGPoint(x: center.x - radius * 0.78, y: center.y + radius * 0.42),
            control: CGPoint(x: origin.x + size.width * 0.14, y: origin.y + size.height * 0.62)
        )
        pin.closeSubpath()
        let hole = Path(ellipseIn: CGRect(
            x: origin.x + size.width * 0.42,
            y: origin.y + size.height * 0.26,
            width: size.width * 0.16,
            height: size.height * 0.16
        ))
        if lineArt {
            // Cream circle / kraft disk: ink line-art stays visible.
            // DESIGN “cream line-art pin” is the cream-circle illustration, not
            // a cream stroke on cream.
            context.stroke(pin, with: .color(ink), lineWidth: 2.2)
            context.stroke(hole, with: .color(ink), lineWidth: 1.6)
        } else {
            context.fill(pin, with: .color(coral))
            context.stroke(pin, with: .color(ink), lineWidth: 1.4)
            context.fill(hole, with: .color(cream))
        }
    }
}

nonisolated struct ClipScallopedStamp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pitch: CGFloat = 7
        let depth: CGFloat = 3
        path.move(to: CGPoint(x: rect.minX + depth, y: rect.minY))
        var x = rect.minX + depth
        var flip = false
        while x < rect.maxX - depth {
            let next = min(x + pitch, rect.maxX - depth)
            path.addQuadCurve(
                to: CGPoint(x: next, y: rect.minY),
                control: CGPoint(x: (x + next) / 2, y: rect.minY + (flip ? depth : -depth))
            )
            x = next
            flip.toggle()
        }
        var y = rect.minY + depth
        flip = false
        while y < rect.maxY - depth {
            let next = min(y + pitch, rect.maxY - depth)
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: next),
                control: CGPoint(x: rect.maxX + (flip ? depth : -depth), y: (y + next) / 2)
            )
            y = next
            flip.toggle()
        }
        x = rect.maxX - depth
        flip = false
        while x > rect.minX + depth {
            let next = max(x - pitch, rect.minX + depth)
            path.addQuadCurve(
                to: CGPoint(x: next, y: rect.maxY),
                control: CGPoint(x: (x + next) / 2, y: rect.maxY + (flip ? depth : -depth))
            )
            x = next
            flip.toggle()
        }
        y = rect.maxY - depth
        flip = false
        while y > rect.minY + depth {
            let next = max(y - pitch, rect.minY + depth)
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: next),
                control: CGPoint(x: rect.minX - (flip ? depth : -depth), y: (y + next) / 2)
            )
            y = next
            flip.toggle()
        }
        path.closeSubpath()
        return path
    }
}

struct ClipHeroSticker: View {
    let kind: ClipStickerKind

    var body: some View {
        ZStack {
            ClipJournalPalette.cream
            ClipJitterCircle(seed: 9)
                .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            ClipStickerDrawing(kind: kind, lineArtPin: kind == .place)
                .frame(width: ClipJournalLayout.heroSticker, height: ClipJournalLayout.heroSticker)
        }
        .frame(width: ClipJournalLayout.heroCircle, height: ClipJournalLayout.heroCircle)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ClipSharerChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(ClipJournalPalette.kraft)
                Text(String(name.prefix(1)))
                    .font(ClipJournalType.system(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(ClipJournalPalette.ink)
            }
            .frame(width: ClipJournalLayout.avatar, height: ClipJournalLayout.avatar)
            Text(ClipCopy.format("clip.from", name))
                .font(ClipJournalType.system(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(ClipJournalPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: ClipJournalLayout.chipHeight)
        .background(ClipJournalPalette.cream, in: Capsule())
        .overlay {
            ClipJitterCapsule(seed: 3)
                .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
        }
        .accessibilityLabel(ClipCopy.format("clip.from", name))
    }
}

struct ClipWashiNote: View {
    let text: String
    var attribution: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(ClipJournalType.system(16, weight: .regular, relativeTo: .body))
                .foregroundStyle(ClipJournalPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution, !attribution.isEmpty {
                Text(ClipCopy.format("clip.noteBy", attribution))
                    .font(ClipJournalType.system(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(ClipJournalPalette.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ClipWashiStrip()
                .fill(ClipJournalPalette.kraft)
        }
        .rotationEffect(.degrees(ClipJournalLayout.noteRotation))
    }
}

nonisolated struct ClipWashiStrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tooth: CGFloat = 7
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 3))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let next = min(x + tooth, rect.maxX)
            path.addLine(to: CGPoint(x: next, y: up ? rect.minY : rect.minY + 5))
            x = next
            up.toggle()
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        x = rect.maxX
        up = true
        while x > rect.minX {
            let next = max(x - tooth, rect.minX)
            path.addLine(to: CGPoint(x: next, y: up ? rect.maxY : rect.maxY - 5))
            x = next
            up.toggle()
        }
        path.closeSubpath()
        return path
    }
}

struct ClipJournalPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(ClipJournalPalette.cream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
                .background(ClipJournalPalette.coral, in: Capsule())
                .overlay {
                    ClipJitterCapsule(seed: 11)
                        .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .frame(minHeight: ClipJournalLayout.minTap)
    }
}

struct ClipJournalSecondaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(ClipJournalPalette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
                .background(ClipJournalPalette.card, in: Capsule())
                .overlay {
                    ClipJitterCapsule(seed: 13)
                        .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .frame(minHeight: ClipJournalLayout.minTap)
    }
}

struct ClipDashedInkLine: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(ClipJournalPalette.ink),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3.5, 4.5])
            )
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct ClipListSaveCountTable: View {
    let counts: ClipListSaveCounts

    var body: some View {
        VStack(spacing: 0) {
            row(ClipCopy.string("clip.listSaved.row.new"), counts.newlySaved, highlight: false)
            ClipDashedInkLine()
            row(ClipCopy.string("clip.listSaved.row.already"), counts.alreadySaved, highlight: false)
            ClipDashedInkLine()
            row(ClipCopy.string("clip.listSaved.row.over"), counts.overCap, highlight: counts.overCap > 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background {
            ClipJitterRoundedRect(radius: 14, seed: 21)
                .fill(ClipJournalPalette.card)
        }
        .overlay {
            ClipJitterRoundedRect(radius: 14, seed: 21)
                .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
        }
        .accessibilityIdentifier("clip.list.counts")
    }

    private func row(_ title: String, _ value: Int, highlight: Bool) -> some View {
        HStack {
            Text(title)
                .font(ClipJournalType.system(15, weight: .regular, relativeTo: .body))
                .foregroundStyle(highlight ? ClipJournalPalette.coral : ClipJournalPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text("\(value)")
                .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(highlight ? ClipJournalPalette.coral : ClipJournalPalette.ink)
                .accessibilityIdentifier(highlight ? "clip.list.counts.over" : "clip.list.counts.value")
        }
        .padding(.vertical, 12)
    }
}

struct ClipStateIllustration: View {
    let sticker: ClipStickerKind
    let badge: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(ClipJournalPalette.kraft)
                .frame(width: ClipJournalLayout.stateCircle, height: ClipJournalLayout.stateCircle)
            ClipJitterCircle(seed: 15)
                .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
                .frame(width: ClipJournalLayout.stateCircle, height: ClipJournalLayout.stateCircle)
            ClipStickerDrawing(kind: sticker)
                .frame(width: ClipJournalLayout.stateSticker, height: ClipJournalLayout.stateSticker)
            if !badge.isEmpty {
                ZStack {
                    Circle()
                        .fill(ClipJournalPalette.paper)
                    ClipJitterCircle(seed: 16)
                        .stroke(ClipJournalPalette.ink, lineWidth: 1.5)
                    Text(badge)
                        .font(ClipJournalType.system(16, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(ClipJournalPalette.coral)
                }
                .frame(width: ClipJournalLayout.stateBadge, height: ClipJournalLayout.stateBadge)
                .offset(x: 8, y: -4)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClipLoadingDots: View {
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ClipJournalPalette.cream)
                    .frame(width: 8, height: 8)
                    .opacity(reduceMotion ? 1 : 0.35 + Double((index + 1) % 3) * 0.3)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClipMapsTextLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClipJournalType.system(15, weight: .semibold, relativeTo: .subheadline))
                .underline()
                .foregroundStyle(ClipJournalPalette.coral)
                .frame(minHeight: ClipJournalLayout.minTap)
        }
        .buttonStyle(.plain)
    }
}

struct ClipOwnedPhoto: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ClipJournalPalette.coral
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClipPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? ClipJournalPalette.cream : ClipJournalPalette.cream.opacity(0.35))
                    .frame(width: 5, height: index == current ? 16 : 5)
            }
        }
        .accessibilityHidden(true)
    }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        if self == .largeTitle { return .largeTitle }
        if self == .title { return .title1 }
        if self == .title2 { return .title2 }
        if self == .title3 { return .title3 }
        if self == .headline { return .headline }
        if self == .subheadline { return .subheadline }
        if self == .callout { return .callout }
        if self == .footnote { return .footnote }
        if self == .caption { return .caption1 }
        if self == .caption2 { return .caption2 }
        return .body
    }
}
