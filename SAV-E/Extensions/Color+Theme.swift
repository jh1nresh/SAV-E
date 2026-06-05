import SwiftUI
import UIKit

enum SaveTheme {
    enum Colors {
        static let nearBlack = Color(hex: "050403")
        static let cream = Color(hex: "FFF5E7")
        static let mint = Color(hex: "C8EBCF")
        static let amber = Color(hex: "FFD66B")
    }

    enum Motion {
        static let breathingDuration: TimeInterval = 2.8
        static let standardResponse: Double = 0.52
        static let standardDamping: Double = 0.86

        static var breathing: Animation {
            .easeInOut(duration: breathingDuration).repeatForever(autoreverses: true)
        }

        static var standardSpring: Animation {
            .spring(response: standardResponse, dampingFraction: standardDamping)
        }
    }

    enum Typography {
        static let brandTitle = Font.system(size: 64, weight: .black, design: .rounded)
        static let entryTitle = Font.title3.weight(.black)
        static let cta = Font.caption.weight(.black)
        static let eyebrow = Font.caption2.weight(.black)
    }
}

struct SaveBrandPrimaryButtonStyle: ButtonStyle {
    var fill: Color = SaveTheme.Colors.cream
    var foreground: Color = SaveTheme.Colors.nearBlack
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SaveTheme.Typography.cta)
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(fill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(SaveTheme.Motion.standardSpring, value: configuration.isPressed)
    }
}

extension Color {
    // MARK: - SAV-E Memo Scrapbook Theme
    static let saveCream = Color(light: "FFF5E7", dark: "15191F")
    static let saveMint = Color(light: "C8EBCF", dark: "4F7D5D")
    static let saveCocoa = Color(light: "3A2415", dark: "F7EFE5")
    static let saveHoney = Color(light: "FFD66B", dark: "986724")
    static let saveSky = Color(light: "8FCAEA", dark: "3F7F97")
    static let saveInk = Color(light: "3A2415", dark: "FFF8ED")
    static let saveMutedText = Color(light: "7A5D45", dark: "CFC4B8")
    static let saveDisabled = Color(light: "D7C0A6", dark: "4E4842")
    static let savePaper = Color(light: "FFF0DC", dark: "1B2027")
    static let saveLedger = Color(light: "FFF5E7", dark: "15191F")
    static let saveSignal = Color(light: "EE9C78", dark: "9F523F")
    static let saveSuccess = Color(light: "C8EBCF", dark: "4F7D5D")
    static let saveCoral = Color(light: "EE9C78", dark: "9F523F")
    static let savePink = Color(light: "F6C1CB", dark: "96586B")
    static let saveNotebookBackground = Color(light: "FFF5E7", dark: "101419")
    static let saveNotebookPage = Color(light: "FFF0DC", dark: "1B2027")
    static let saveNotebookSpine = Color(light: "F6C181", dark: "7A5533")
    static let saveNotebookLine = Color(light: "3A2415", dark: "6E6257")

    // MARK: - Category Colors
    static func categoryColor(for category: PlaceCategory) -> Color {
        saveStampColor(for: category)
    }

    static func saveStampColor(for category: PlaceCategory) -> Color {
        .saveHoney
    }

    static func saveStampForeground(for category: PlaceCategory) -> Color {
        .saveInk
    }

    // MARK: - Hex Initializer
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }

    init(light lightHex: String, dark darkHex: String) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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

extension View {
    func saveNotebookPage(cornerRadius: CGFloat = 18) -> some View {
        background(Color.saveNotebookPage)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func saveNotebookSurface(
        cornerRadius: CGFloat = 16,
        fill: Color = .saveNotebookPage,
        opacity: Double = 0.76,
        strokeOpacity: Double = 0.58,
        lineWidth: CGFloat = 1.2
    ) -> some View {
        background(fill.opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: lineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func saveOutlinedButton(
        fill: Color = .saveHoney,
        foreground: Color = .saveInk,
        cornerRadius: CGFloat = 14
    ) -> some View {
        font(.subheadline.weight(.black))
            .foregroundColor(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SaveIconTile: View {
    let systemName: String
    var size: CGFloat = 32
    var iconSize: CGFloat? = nil
    var fill: Color = .saveNotebookPage
    var foreground: Color = .saveCocoa
    var strokeOpacity: Double = 0.56
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize ?? size * 0.42, weight: .bold))
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? max(size * 0.28, 7)
    }
}

struct SaveDottedBackground: View {
    var body: some View {
        Color.saveNotebookBackground
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 18
                    for x in stride(from: CGFloat(8), through: size.width, by: spacing) {
                        for y in stride(from: CGFloat(8), through: size.height, by: spacing) {
                            let rect = CGRect(x: x, y: y, width: 2, height: 2)
                            context.fill(Path(ellipseIn: rect), with: .color(Color.saveNotebookLine.opacity(0.055)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}
