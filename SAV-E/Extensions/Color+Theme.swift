import SwiftUI
import UIKit

enum SaveTheme {
    enum Colors {
        static let nearBlack = Color(hex: "050403")
        static let cream = Color(hex: "FFF5E7")
        static let mint = Color(hex: "C8EBCF")
        static let amber = Color(hex: "FFD66B")
    }

    /// Shared spacing scale per DESIGN.md "Shape, Stroke, Spacing".
    /// Compact rows 8-10, cards 12-18, sheet sections 14-16.
    enum Spacing {
        /// Tight icon/text gaps inside chips and badges.
        static let xs: CGFloat = 4
        /// Compact row internal spacing.
        static let sm: CGFloat = 8
        /// Default card padding.
        static let md: CGFloat = 12
        /// Comfortable card / sheet section padding.
        static let lg: CGFloat = 16
        /// Large notebook or Passport panel padding.
        static let xl: CGFloat = 22
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

        /// Punchy rubber-stamp spring for the clue -> Map Stamp brand moment.
        static var stampSpring: Animation {
            .spring(response: 0.38, dampingFraction: 0.6)
        }
    }

    enum Typography {
        static let brandTitle = Font.system(size: 64, weight: .black, design: .rounded)
        static let entryTitle = Font.title3.weight(.black)
        static let cta = Font.caption.weight(.black)
        static let eyebrow = Font.caption2.weight(.black)
        /// Card titles per DESIGN.md: `.headline.weight(.black)`.
        static let cardTitle = Font.headline.weight(.black)
        /// Compact list-row titles.
        static let rowTitle = Font.subheadline.weight(.black)
        /// Section labels inside cards and panels.
        static let sectionLabel = Font.caption.weight(.black)
        /// Status stamps per DESIGN.md: `.caption2.weight(.black)`.
        static let stamp = Font.caption2.weight(.black)
        /// Supporting / muted copy.
        static let supporting = Font.caption.weight(.semibold)
    }
}

/// Centralized haptics so key SAV-E actions feel consistent.
/// `stamp()` is reserved for the save moment (clue -> Map Stamp).
@MainActor
enum SaveHaptics {
    static func stamp() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
    static let saveBlush = Color(light: "FFF6F8", dark: "281A20")
    static let saveLavender = Color(light: "DCC8FF", dark: "44345F")
    static let saveLeaf = Color(light: "D9F2C7", dark: "435F3D")
    static let saveBlueInk = Color(light: "315D76", dark: "BEE7F8")
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
                LinearGradient(
                    colors: [
                        Color.saveBlush.opacity(0.38),
                        Color.clear,
                        Color.saveSky.opacity(0.18),
                        Color.saveLeaf.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.26),
                        Color.clear,
                        Color.saveNotebookSpine.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
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
