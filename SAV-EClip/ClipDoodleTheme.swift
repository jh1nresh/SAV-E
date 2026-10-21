import CoreText
import SwiftUI
import UIKit

/// Clip Doodle v1 tokens. Values come from DESIGN.md (2026-10-21 App Clip
/// spec). They stay in sync with `SaveAtlasPalette` in
/// `SAV-E/Extensions/Color+Theme.swift` by table in DESIGN.md — the Clip
/// target cannot link the main app, and Color+Theme.swift pulls PlaceCategory.
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
    static let cardRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 1
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
    static let defaultElephant: CGFloat = 34
    static let rowMinHeight: CGFloat = 64
    static let numberCircle: CGFloat = 24
    static let numberToSticker: CGFloat = 8
    static let stickerToText: CGFloat = 12
    static let nameToMeta: CGFloat = 4
    static let minTap: CGFloat = 44
    static let buttonHeight: CGFloat = 48
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
}

enum ClipJournalType {
    static func rounded(
        _ size: CGFloat,
        weight: UIFont.Weight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded)
            ?? systemFont.fontDescriptor
        let roundedFont = UIFont(descriptor: descriptor, size: size)
        let scaledFont = UIFontMetrics(forTextStyle: style.uiTextStyle)
            .scaledFont(for: roundedFont)
        return Font(scaledFont)
    }

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

    private static let register: Void = {
        let url = Bundle.main.url(forResource: "Caveat-SemiBold", withExtension: "ttf", subdirectory: "DisplayFont")
            ?? Bundle.main.url(forResource: "Caveat-SemiBold", withExtension: "ttf")
        if let url {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// English titles use Caveat. zh-Hant titles use the system font so the
    /// Clip does not ship Iansui-SavvySubset.ttf (3.48 MB).
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        if ClipCopy.usesTraditionalChinese {
            return ClipJournalType.system(size, weight: .semibold, relativeTo: style)
        }
        _ = register
        let latin = UIFont(name: latinName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        return Font(UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: latin))
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
        Image("SavvyLogo")
            .resizable()
            .scaledToFit()
            .frame(height: ClipJournalLayout.wordmarkHeight)
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
                Capsule().stroke(ClipJournalPalette.line, lineWidth: ClipJournalPalette.strokeWidth)
            }
            .accessibilityHidden(true)
    }
}

struct ClipDisplayTitle: View {
    let text: String
    var pointSize: CGFloat = 28
    var relativeTo: Font.TextStyle = .title
    var color: Color = ClipJournalPalette.ink

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
                    let step: CGFloat = 10
                    let dot = ClipJournalPalette.line.opacity(0.18)
                    var x: CGFloat = 4
                    while x < size.width {
                        var y: CGFloat = 4
                        while y < size.height {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
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

enum ClipStickerKind: String {
    case noodle, coffee, temple, duck, lantern, elephant

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
        return .elephant
    }
}

struct ClipCategorySticker: View {
    let kind: ClipStickerKind
    var canvas: CGFloat = ClipJournalLayout.stickerCanvas
    var image: CGFloat = ClipJournalLayout.stickerImage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ClipJournalPalette.kraft)
            ClipStickerDrawing(kind: kind)
                .frame(width: image, height: image)
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
            switch kind {
            case .noodle:
                var bowl = Path()
                bowl.addEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.38, width: size.width * 0.76, height: size.height * 0.48))
                context.fill(bowl, with: .color(coral))
                var noodle = Path()
                noodle.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.42))
                noodle.addQuadCurve(to: CGPoint(x: size.width * 0.72, y: size.height * 0.48), control: CGPoint(x: size.width * 0.5, y: size.height * 0.18))
                noodle.addQuadCurve(to: CGPoint(x: size.width * 0.34, y: size.height * 0.58), control: CGPoint(x: size.width * 0.62, y: size.height * 0.72))
                context.stroke(noodle, with: .color(cream), lineWidth: 2.4)
            case .coffee:
                var cup = Path(roundedRect: CGRect(x: size.width * 0.22, y: size.height * 0.28, width: size.width * 0.46, height: size.height * 0.46), cornerRadius: 6)
                context.fill(cup, with: .color(coral))
                var handle = Path()
                handle.addArc(center: CGPoint(x: size.width * 0.72, y: size.height * 0.48), radius: size.width * 0.12, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
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
            case .elephant:
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.18, y: size.height * 0.22, width: size.width * 0.62, height: size.height * 0.52)), with: .color(coral))
                var trunk = Path()
                trunk.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.58))
                trunk.addQuadCurve(to: CGPoint(x: size.width * 0.16, y: size.height * 0.82), control: CGPoint(x: size.width * 0.08, y: size.height * 0.62))
                context.stroke(trunk, with: .color(ink), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.48, y: size.height * 0.4, width: size.width * 0.08, height: size.height * 0.1)), with: .color(cream))
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

    var body: some View {
        ZStack {
            ClipTeardrop()
                .fill(ClipJournalPalette.coral)
            ClipTeardrop()
                .stroke(ClipJournalPalette.cream, lineWidth: 3)
            if let number {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ClipJournalPalette.cream)
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

struct ClipJournalPrimaryButton: View {
    let title: String
    var systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(ClipJournalType.rounded(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(ClipJournalPalette.cream)
            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
            .background(ClipJournalPalette.coral, in: RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
            .contentShape(Rectangle())
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
            .font(ClipJournalType.rounded(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(ClipJournalPalette.ink)
            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
            .overlay {
                RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous)
                    .stroke(ClipJournalPalette.ink, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
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
            ClipStickerDrawing(kind: sticker)
                .frame(width: ClipJournalLayout.stateSticker, height: ClipJournalLayout.stateSticker)
            if !badge.isEmpty {
                ZStack {
                    Circle()
                        .fill(ClipJournalPalette.paper)
                    Circle()
                        .stroke(ClipJournalPalette.ink, lineWidth: 1.5)
                    Text(badge)
                        .font(ClipJournalType.rounded(16, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(ClipJournalPalette.coral)
                }
                .frame(width: ClipJournalLayout.stateBadge, height: ClipJournalLayout.stateBadge)
                .offset(x: 8, y: -4)
            }
        }
        .accessibilityHidden(true)
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
                RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous)
                    .stroke(ClipJournalPalette.line, lineWidth: ClipJournalPalette.strokeWidth)
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
