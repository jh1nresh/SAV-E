import CoreText
import SwiftUI
import UIKit

/// Clip Doodle v2 tokens. Catalog colors are the source; coral stays a token
/// because the landing-page value is still being decided.
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
    static let strokeWidth: CGFloat = 1.6
}

enum ClipJournalLayout {
    static let screenMargin: CGFloat = 24
    static let headerTop: CGFloat = 4
    static let headerBottom: CGFloat = 12
    static let wordmarkHeight: CGFloat = 34
    static let chipHeight: CGFloat = 32
    static let placeMapWidth: CGFloat = 345
    static let placeMapHeight: CGFloat = 300
    static let listMapHeight: CGFloat = 180
    static let cardPadding: CGFloat = 16
    static let stickerCanvas: CGFloat = 48
    static let stickerImage: CGFloat = 40
    static let rowMinHeight: CGFloat = 64
    static let numberCircle: CGFloat = 28
    static let numberToSticker: CGFloat = 8
    static let stickerToText: CGFloat = 12
    static let nameToMeta: CGFloat = 4
    static let minTap: CGFloat = 44
    static let buttonHeight: CGFloat = 50
    static let buttonGap: CGFloat = 12
    static let buttonGroupBottom: CGFloat = 34
    static let stateCircle: CGFloat = 120
    static let stateSticker: CGFloat = 84
    static let stateBadge: CGFloat = 40
    static let stateTitleGap: CGFloat = 24
    static let stateBodyGap: CGFloat = 12
    static let stateBodyMaxWidth: CGFloat = 300
    static let pinWidth: CGFloat = 30
    static let pinHeight: CGFloat = 38
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

    /// Caveat (Latin) / Iansui (zh) for titles only. Place names, addresses,
    /// buttons, meta, and body stay on the system font. The Clip ships
    /// Iansui-ClipTitles.ttf (title glyphs), not Iansui-SavvySubset.ttf (3.48 MB).
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

struct ClipSharedChip: View {
    var body: some View {
        Text(ClipCopy.string("clip.chip.shared"))
            .font(ClipJournalType.system(13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(ClipJournalPalette.ink)
            .padding(.horizontal, 12)
            .frame(height: ClipJournalLayout.chipHeight)
            .background(ClipJournalPalette.kraft, in: Capsule())
            .overlay {
                ClipJitterCapsule(seed: 3)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
            .accessibilityHidden(true)
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

/// Deterministic ink jitter for cards, buttons, chips, map frames, and state circles.
struct ClipJitterRoundedRect: Shape {
    var radius: CGFloat
    var seed: UInt64 = 1

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: radius, seed: seed)
    }
}

struct ClipJitterCapsule: Shape {
    var seed: UInt64 = 2

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: min(rect.width, rect.height) / 2, seed: seed)
    }
}

struct ClipJitterCircle: Shape {
    var seed: UInt64 = 4

    func path(in rect: CGRect) -> Path {
        jitteredPath(in: rect, cornerRadius: min(rect.width, rect.height) / 2, seed: seed)
    }
}

private func jitteredPath(in rect: CGRect, cornerRadius: CGFloat, seed: UInt64) -> Path {
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

private func jitter(_ point: CGPoint, index: Int, seed: UInt64, in bounds: CGRect) -> CGPoint {
    let wave = sin(Double(index) * 1.7 + Double(seed) * 0.37)
    let offset = CGFloat(wave) * 0.85
    let x = min(max(point.x + offset, bounds.minX - 1), bounds.maxX + 1)
    let y = min(max(point.y + CGFloat(cos(Double(index) * 1.3 + Double(seed))) * 0.7, bounds.minY - 1), bounds.maxY + 1)
    return CGPoint(x: x, y: y)
}

enum ClipStickerKind: String {
    case noodle, coffee, temple, duck, lantern, place

    static func forCategory(_ raw: String?) -> ClipStickerKind {
        let value = (raw ?? "").lowercased()
        if value.contains("cafe") || value.contains("coffee") || value.contains("咖啡") {
            return .coffee
        }
        if value.contains("food") || value.contains("restaurant") || value.contains("noodle")
            || value.contains("餐") || value.contains("麵") || value.contains("面") {
            return .noodle
        }
        if value.contains("temple") || value.contains("attraction") || value.contains("museum")
            || value.contains("寺") || value.contains("景") {
            return .temple
        }
        if value.contains("bar") || value.contains("stay") || value.contains("hotel")
            || value.contains("酒") || value.contains("宿") {
            return .lantern
        }
        if value.contains("shop") || value.contains("duck") || value.contains("購") {
            return .duck
        }
        return .place
    }
}

struct ClipCategorySticker: View {
    let kind: ClipStickerKind
    var canvas: CGFloat = ClipJournalLayout.stickerCanvas

    var body: some View {
        ZStack {
            if kind == .place {
                ClipJitterCircle(seed: 9)
                    .stroke(ClipJournalPalette.coral, style: StrokeStyle(lineWidth: 1.4, dash: [3, 2.4]))
            } else {
                ClipJournalPalette.kraft
                ClipJitterRoundedRect(radius: 12, seed: 8)
                    .stroke(ClipJournalPalette.ink, lineWidth: 1.2)
            }
            ClipStickerDrawing(kind: kind)
                .frame(width: ClipJournalLayout.stickerImage, height: ClipJournalLayout.stickerImage)
        }
        .frame(width: canvas, height: canvas)
        .accessibilityHidden(true)
    }
}

struct ClipStickerDrawing: View {
    let kind: ClipStickerKind

    var body: some View {
        Canvas { context, size in
            let ink = ClipJournalPalette.ink
            let coral = ClipJournalPalette.coral
            let cream = ClipJournalPalette.cream
            let kraft = ClipJournalPalette.kraft
            switch kind {
            case .noodle:
                var plate = Path()
                plate.addEllipse(in: CGRect(x: size.width * 0.08, y: size.height * 0.52, width: size.width * 0.84, height: size.height * 0.36))
                context.fill(plate, with: .color(kraft))
                context.stroke(plate, with: .color(ink), lineWidth: 1.2)
                var bowl = Path()
                bowl.addEllipse(in: CGRect(x: size.width * 0.18, y: size.height * 0.28, width: size.width * 0.64, height: size.height * 0.46))
                context.fill(bowl, with: .color(coral))
                var noodle = Path()
                noodle.move(to: CGPoint(x: size.width * 0.3, y: size.height * 0.36))
                noodle.addQuadCurve(to: CGPoint(x: size.width * 0.7, y: size.height * 0.42), control: CGPoint(x: size.width * 0.5, y: size.height * 0.12))
                noodle.addQuadCurve(to: CGPoint(x: size.width * 0.36, y: size.height * 0.52), control: CGPoint(x: size.width * 0.62, y: size.height * 0.64))
                context.stroke(noodle, with: .color(cream), lineWidth: 2.2)
            case .coffee:
                var saucer = Path()
                saucer.addEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.62, width: size.width * 0.76, height: size.height * 0.24))
                context.fill(saucer, with: .color(kraft))
                context.stroke(saucer, with: .color(ink), lineWidth: 1.2)
                var cup = Path(roundedRect: CGRect(x: size.width * 0.24, y: size.height * 0.2, width: size.width * 0.42, height: size.height * 0.46), cornerRadius: 6)
                context.fill(cup, with: .color(coral))
                var handle = Path()
                handle.addArc(center: CGPoint(x: size.width * 0.72, y: size.height * 0.42), radius: size.width * 0.12, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
                context.stroke(handle, with: .color(ink), lineWidth: 2.2)
            case .temple:
                var roof = Path()
                roof.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.42))
                roof.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.16))
                roof.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.42))
                context.fill(roof, with: .color(coral))
                context.fill(Path(CGRect(x: size.width * 0.32, y: size.height * 0.42, width: size.width * 0.36, height: size.height * 0.36)), with: .color(ink.opacity(0.85)))
            case .duck:
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.22, y: size.height * 0.36, width: size.width * 0.52, height: size.height * 0.4)), with: .color(coral))
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.48, y: size.height * 0.18, width: size.width * 0.3, height: size.height * 0.28)), with: .color(coral))
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.74, y: size.height * 0.3, width: size.width * 0.16, height: size.height * 0.1)), with: .color(ink))
            case .lantern:
                context.fill(Path(roundedRect: CGRect(x: size.width * 0.3, y: size.height * 0.22, width: size.width * 0.4, height: size.height * 0.56), cornerRadius: 10), with: .color(coral))
                context.stroke(Path(CGRect(x: size.width * 0.36, y: size.height * 0.08, width: size.width * 0.28, height: size.height * 0.12)), with: .color(ink), lineWidth: 2)
            case .place:
                // Packet fallback: generic place/pin sticker (not the elephant).
                var pin = Path()
                let radius = size.width * 0.28
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.38)
                pin.addArc(center: center, radius: radius, startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: false)
                pin.addQuadCurve(to: CGPoint(x: size.width * 0.5, y: size.height * 0.92), control: CGPoint(x: size.width * 0.86, y: size.height * 0.62))
                pin.addQuadCurve(to: CGPoint(x: center.x - radius * 0.78, y: center.y + radius * 0.42), control: CGPoint(x: size.width * 0.14, y: size.height * 0.62))
                pin.closeSubpath()
                context.fill(pin, with: .color(coral))
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.42, y: size.height * 0.28, width: size.width * 0.16, height: size.height * 0.16)), with: .color(cream))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClipTeardrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        path.addArc(center: center, radius: radius, startAngle: .degrees(210), endAngle: .degrees(-30), clockwise: false)
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 1, y: rect.midY + radius * 0.35)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius * 0.14, y: rect.minY + radius * 1.28),
            control: CGPoint(x: rect.minX + 1, y: rect.midY + radius * 0.35)
        )
        path.closeSubpath()
        return path
    }
}

struct ClipDoodlePin: View {
    var number: Int? = nil
    var outlined: Bool = false

    var body: some View {
        ZStack {
            ClipTeardrop()
                .fill(outlined ? ClipJournalPalette.cream : ClipJournalPalette.coral)
            ClipTeardrop()
                .stroke(outlined ? ClipJournalPalette.coral : ClipJournalPalette.cream, lineWidth: outlined ? 2.2 : 3)
            if let number {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(outlined ? ClipJournalPalette.coral : ClipJournalPalette.cream)
                    .offset(y: -3)
            } else {
                Circle()
                    .fill(ClipJournalPalette.cream)
                    .frame(width: 9, height: 9)
                    .offset(y: -3)
            }
        }
        .frame(width: ClipJournalLayout.pinWidth, height: ClipJournalLayout.pinHeight)
        .accessibilityHidden(true)
    }
}

struct ClipCircledNumber: View {
    let number: Int

    var body: some View {
        ZStack {
            ClipJitterCircle(seed: UInt64(number + 4))
                .stroke(ClipJournalPalette.coral, lineWidth: ClipJournalPalette.strokeWidth)
            Text("\(number)")
                .font(ClipJournalType.system(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ClipJournalPalette.coral)
        }
        .frame(width: ClipJournalLayout.numberCircle, height: ClipJournalLayout.numberCircle)
        .accessibilityHidden(true)
    }
}

struct ClipWashiNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(ClipJournalPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ClipWashiStrip()
                    .fill(ClipJournalPalette.kraft)
            }
    }
}

struct ClipWashiStrip: Shape {
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
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(ClipJournalPalette.cream)
            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
            .background(ClipJournalPalette.coral, in: Capsule())
            .overlay {
                ClipJitterCapsule(seed: 11)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: ClipJournalLayout.minTap)
    }
}

struct ClipJournalSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(ClipJournalPalette.ink)
            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
            .background(ClipJournalPalette.card, in: Capsule())
            .overlay {
                ClipJitterCapsule(seed: 13)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: ClipJournalLayout.minTap)
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
                    .fill(ClipJournalPalette.coral)
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
                .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                .underline()
                .foregroundStyle(ClipJournalPalette.ink)
                .frame(minHeight: ClipJournalLayout.minTap)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func clipJournalCard() -> some View {
        padding(ClipJournalLayout.cardPadding)
            .background(
                ClipJournalPalette.card,
                in: RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous)
            )
            .overlay {
                ClipJitterRoundedRect(radius: ClipJournalPalette.cardRadius, seed: 6)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
    }

    func clipJournalMapFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
            .overlay {
                ClipJitterRoundedRect(radius: ClipJournalPalette.cardRadius, seed: 7)
                    .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
            }
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
