import CoreText
import SwiftUI
import UIKit

/// Doodle v1 journal tokens for the App Clip. Mirrors `SaveAtlasPalette`,
/// `SaveDoodle`, `SaveDisplayType`, and `SaveLayout` from the main app so the
/// clip target stays standalone.
enum ClipJournalPalette {
    static let canvas = Color(light: "FFF9EB", dark: "1E1C19")
    static let paper = Color(light: "FFF9EB", dark: "1E1C19")
    static let forest = Color(light: "0E4A33", dark: "B9E0C9")
    static let ink = Color(light: "2F2E23", dark: "F4F1E4")
    static let muted = Color(light: "62594F", dark: "CFC4B8")
    static let coral = Color(light: "F26B4A", dark: "D97861")
    static let mint = Color(light: "D6E8C4", dark: "4F7258")
    static let sky = Color(light: "B5E3F5", dark: "3F758B")
    static let kraft = Color(light: "EADDC6", dark: "4A3F32")
    static let honey = Color(light: "FFCC4F", dark: "A87328")
    static let stroke = Color(light: "DCCFB9", dark: "4A443B")
    static let pencil = Color(light: "A39C8E", dark: "8A8478")
    static let washGreen = Color(light: "D3E4C1", dark: "3E5236")
    static let cardRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 1
}

enum ClipJournalLayout {
    static let screenMargin: CGFloat = 24
    static let minTap: CGFloat = 44
    static let buttonHeight: CGFloat = 48
    static let cardPadding: CGFloat = 16
}

enum ClipJournalType {
    static func display(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .title
    ) -> Font {
        ClipDisplayType.display(size, relativeTo: style)
    }

    static func strong(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .bold, relativeTo: style)
    }

    static func body(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .medium, relativeTo: style)
    }

    static func regular(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .regular, relativeTo: style)
    }

    private static func rounded(
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
}

enum ClipDisplayType {
    static let latinName = "Caveat-SemiBold"
    static let cjkName = "Iansui-Regular"

    private static let register: Void = {
        let files: [(String, String)] = [
            ("Caveat-SemiBold", "ttf"),
            ("Iansui-SavvySubset", "ttf"),
        ]
        for (name, ext) in files {
            let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "DisplayFont")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func display(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .title
    ) -> Font {
        Font(scaledFont(size: size, name: latinName, relativeTo: style))
    }

    private static func scaledFont(
        size: CGFloat,
        name: String,
        relativeTo style: Font.TextStyle
    ) -> UIFont {
        _ = register
        let latin = UIFont(name: name, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        var cascade: [UIFontDescriptor] = []
        if let cjk = UIFont(name: cjkName, size: size) {
            cascade.append(cjk.fontDescriptor)
        }
        if let pingFang = UIFont(name: "PingFangTC-Regular", size: size) {
            cascade.append(pingFang.fontDescriptor)
        }
        let font: UIFont
        if cascade.isEmpty {
            font = latin
        } else {
            let descriptor = latin.fontDescriptor.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontCascadeListAttribute as String): cascade,
            ])
            font = UIFont(descriptor: descriptor, size: size)
        }
        return UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: font)
    }
}

enum ClipCopy {
    static var usesTraditionalChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("zh-Hant")
            || preferred.hasPrefix("zh-TW")
            || preferred.hasPrefix("zh-HK")
            || preferred.hasPrefix("zh_TW")
            || preferred.hasPrefix("zh_HK")
    }

    static func text(_ english: String, _ traditionalChinese: String) -> String {
        usesTraditionalChinese ? traditionalChinese : english
    }
}

struct ClipDisplayTitle: View {
    let text: String
    var pointSize: CGFloat = 22
    var relativeTo: Font.TextStyle = .title

    var body: some View {
        Text(text)
            .font(ClipDisplayType.display(pointSize, relativeTo: relativeTo))
            .foregroundStyle(ClipJournalPalette.forest)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }
}

struct ClipDottedBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ClipJournalPalette.canvas
            .overlay {
                Image(colorScheme == .dark ? "PaperGrainDark" : "PaperGrain")
                    .resizable(resizingMode: .tile)
                    .allowsHitTesting(false)
            }
    }
}

struct ClipJournalChip: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(ClipJournalType.strong(12, relativeTo: .caption))
        .foregroundStyle(ClipJournalPalette.ink)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(ClipJournalPalette.kraft.opacity(0.55), in: Capsule())
        .overlay {
            Capsule().stroke(ClipJournalPalette.stroke, lineWidth: ClipJournalPalette.strokeWidth)
        }
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
            .font(ClipJournalType.strong(16, relativeTo: .headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.buttonHeight)
            .background(ClipJournalPalette.coral, in: RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func clipJournalPaper(radius: CGFloat = ClipJournalPalette.cardRadius) -> some View {
        background(
            ClipJournalPalette.paper,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(ClipJournalPalette.stroke, lineWidth: ClipJournalPalette.strokeWidth)
        }
    }
}

extension Color {
    init(light lightHex: String, dark darkHex: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(clipHex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }

    init(clipHex: String) {
        self.init(uiColor: UIColor(clipHex: clipHex))
    }
}

private extension UIColor {
    convenience init(clipHex: String) {
        let hex = clipHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
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
