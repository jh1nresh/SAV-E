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

    // Weight ladder — exactly one loud level per screen:
    //   black    → brand hero only (wordmark moments)
    //   bold     → titles, CTAs, stamps
    //   semibold → rows, section labels, eyebrows
    //   medium   → supporting / muted copy
    // When everything is black nothing is emphasized.
    enum Typography {
        static let brandTitle = Font.system(size: 64, weight: .black, design: .rounded)
        static let entryTitle = Font.title3.weight(.bold)
        static let cta = Font.caption.weight(.bold)
        static let eyebrow = Font.caption2.weight(.semibold)
        /// Card titles: the one bold element inside a card.
        static let cardTitle = Font.headline.weight(.bold)
        /// Compact list-row titles.
        static let rowTitle = Font.subheadline.weight(.semibold)
        /// Section labels inside cards and panels.
        static let sectionLabel = Font.caption.weight(.semibold)
        /// Status stamps — brand moment, keeps punch at tiny size.
        static let stamp = Font.caption2.weight(.bold)
        /// Supporting / muted copy.
        static let supporting = Font.caption.weight(.medium)
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
    static let saveCoralInk = Color(light: "9F523F", dark: "EE9C78")
    static let savePink = Color(light: "F6C1CB", dark: "96586B")
    static let saveBlush = Color(light: "FFF6F8", dark: "281A20")
    static let saveLavender = Color(light: "DCC8FF", dark: "44345F")
    static let saveLeaf = Color(light: "D9F2C7", dark: "435F3D")
    static let saveBlueInk = Color(light: "315D76", dark: "BEE7F8")
    static let saveNotebookBackground = Color(light: "FFF5E7", dark: "101419")
    static let saveNotebookPage = Color(light: "FFF0DC", dark: "1B2027")
    static let saveNotebookSpine = Color(light: "F6C181", dark: "7A5533")
    static let saveNotebookLine = Color(light: "3A2415", dark: "6E6257")

    // MARK: - Drawer surface (cream-notebook tint over the system blur)
    /// Adaptive tint laid over the drawer's material blur so the AI drawer
    /// reads as the cream notebook canvas instead of generic glass.
    static let saveDrawerSurface = Color(light: "FFF0DC", dark: "1B2027")
    /// Hairline stroke for drawer surfaces (search bar, nav header, glass edge).
    static let saveDrawerStroke = Color(light: "3A2415", dark: "F7EFE5")

    /// Notebook-friendly red/coral for error banners and destructive actions.
    /// Muted enough to sit on cream in light mode and stay readable in dark.
    static let saveError = Color(light: "C0392B", dark: "E88A7D")

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
        self.init(UIColor.adaptive(lightHex: lightHex, darkHex: darkHex))
    }
}

enum SaveAtlasPalette {
    static let canvas = Color(light: "FDF8F3", dark: "11161C")
    static let paper = Color(light: "FFFDF7", dark: "1B2027")
    static let forest = Color(light: "0E4A33", dark: "B9E0C9")
    static let ink = Color(light: "2E2117", dark: "FFF8ED")
    static let muted = Color(light: "62594F", dark: "CFC4B8")
    static let coral = Color(light: "F26B4A", dark: "D97861")
    static let mint = Color(light: "D6E8C4", dark: "4F7258")
    static let sky = Color(light: "B5E3F5", dark: "3F758B")
    static let lavender = Color(light: "E3D6F7", dark: "57466F")
    static let kraft = Color(light: "F0CFA1", dark: "71543C")
    static let honey = Color(light: "FFCC4F", dark: "A87328")
    static let line = Color(light: "A68F78", dark: "807365")
}

enum SaveAtlasType {
    static func display(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("AvenirNextCondensed-DemiBold", size: size, relativeTo: style)
    }

    static func strong(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("AvenirNextCondensed-Bold", size: size, relativeTo: style)
    }

    static func body(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("AvenirNextCondensed-Medium", size: size, relativeTo: style)
    }

    static func regular(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("AvenirNextCondensed-Regular", size: size, relativeTo: style)
    }

    static func editorial(_ size: CGFloat) -> Font {
        .custom("Georgia-Italic", size: size, relativeTo: .headline)
    }
}

private extension UIColor {
    nonisolated static func adaptive(lightHex: String, darkHex: String) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        }
    }

    nonisolated
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
    func saveAtlasPaper(radius: CGFloat, shadow: Bool = false) -> some View {
        background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.34), lineWidth: 1)
        }
        .shadow(
            color: shadow ? SaveAtlasPalette.ink.opacity(0.07) : .clear,
            radius: shadow ? 7 : 0,
            y: shadow ? 3 : 0
        )
    }

    /// Keeps list and form content on the SAV-E notebook canvas while leaving
    /// navigation and tab chrome to the system material.
    func saveNotebookListCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(SaveDottedBackground().ignoresSafeArea())
    }

    /// A readable notebook page for rows; content stays opaque enough to avoid
    /// competing with the canvas pattern beneath it.
    func saveNotebookListRow(opacity: Double = 0.94) -> some View {
        listRowBackground(Color.saveNotebookPage.opacity(opacity))
            .listRowSeparatorTint(Color.saveNotebookLine.opacity(0.18))
    }

    func saveNotebookPage(cornerRadius: CGFloat = 18) -> some View {
        background(Color.saveNotebookPage)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func saveNotebookSurface(
        cornerRadius: CGFloat = 16,
        fill: Color = .saveNotebookPage,
        opacity: Double = 0.76,
        strokeOpacity: Double = 0.35,
        lineWidth: CGFloat = 1
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
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
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

// MARK: - Illustrated Postcard Pocket

enum SavePostcardTicketStyle {
    case review
    case sourceClue
    case confirmed

    var fill: Color {
        switch self {
        case .review:
            return SaveAtlasPalette.sky.opacity(0.46)
        case .sourceClue:
            return SaveAtlasPalette.coral.opacity(0.23)
        case .confirmed:
            return SaveAtlasPalette.mint.opacity(0.52)
        }
    }

    var edge: Color {
        switch self {
        case .review:
            return Color.saveBlueInk.opacity(0.72)
        case .sourceClue:
            return SaveAtlasPalette.coral.opacity(0.82)
        case .confirmed:
            return SaveAtlasPalette.forest.opacity(0.72)
        }
    }

    var medallion: Color {
        switch self {
        case .review:
            return SaveAtlasPalette.sky
        case .sourceClue:
            return SaveAtlasPalette.coral.opacity(0.42)
        case .confirmed:
            return SaveAtlasPalette.mint
        }
    }

    var eyebrow: Color {
        switch self {
        case .review:
            return .saveBlueInk
        case .sourceClue:
            return SaveAtlasPalette.coral
        case .confirmed:
            return SaveAtlasPalette.forest
        }
    }

    var systemImage: String {
        switch self {
        case .review:
            return "camera"
        case .sourceClue:
            return "questionmark"
        case .confirmed:
            return "star.fill"
        }
    }
}

struct SavePostcardTicket: View {
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String
    let style: SavePostcardTicketStyle

    var body: some View {
        HStack(spacing: 11) {
            SavePostcardPerforatedMedallion(
                systemName: style.systemImage,
                tint: style.medallion,
                edge: style.edge
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow.uppercased())
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.65)
                    .foregroundStyle(style.eyebrow)

                Text(title)
                    .font(SaveAtlasType.strong(18, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(detail)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(actionTitle)
                .font(SaveAtlasType.display(13))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(minHeight: 38)
                .background(style.medallion.opacity(0.86), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(style.edge.opacity(0.54), lineWidth: 1)
                }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(5)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(style.fill)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    style.edge,
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.055), radius: 4, y: 2)
        .contentShape(Rectangle())
    }
}

struct SavePostcardPocketFooter: View {
    let title: String
    let subtitle: String
    let count: Int
    let countLabel: String
    let tint: Color

    var body: some View {
        Image("SavesEnvelope")
            .resizable()
            .scaledToFit()
            .overlay(alignment: .center) {
                HStack(spacing: 12) {
                    SavePostcardPostmark()

                    VStack(spacing: 4) {
                        Text(title)
                            .font(SaveAtlasType.editorial(19))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Text(subtitle)
                            .font(SaveAtlasType.regular(11))
                            .foregroundStyle(SaveAtlasPalette.muted)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: -2) {
                        Text("\(count)")
                            .font(SaveAtlasType.editorial(27))
                            .monospacedDigit()
                        Text(countLabel)
                            .font(SaveAtlasType.regular(9))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 64)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(count) \(countLabel)")
    }
}

struct SavePostcardMemoPeek: View {
    var width: CGFloat = 88

    var body: some View {
        Image("SavesMemoSorting")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

struct SavePostcardPerforatedMedallion: View {
    let systemName: String
    let tint: Color
    let edge: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(SaveAtlasPalette.forest)
            .frame(width: 49, height: 49)
            .background(tint, in: SavePostcardSealShape())
            .overlay {
                SavePostcardSealShape()
                    .stroke(
                        edge.opacity(0.74),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
            }
    }
}

struct SavePostcardPostmark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SaveAtlasPalette.line.opacity(0.70), lineWidth: 1)
                .frame(width: 46, height: 46)
            Image(systemName: "airplane")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.line)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(SaveAtlasPalette.line.opacity(0.58))
                        .frame(width: 24, height: 1)
                }
            }
            .offset(x: 20)
        }
        .frame(width: 64)
        .accessibilityHidden(true)
    }
}

struct SavePostcardScallopedRectangle: Shape {
    var depth: CGFloat = 4
    var pitch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = pitch / 2
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + depth))

        var x = rect.minX + radius
        while x < rect.maxX - radius {
            path.addQuadCurve(
                to: CGPoint(x: x + pitch, y: rect.minY + depth),
                control: CGPoint(x: x + radius, y: rect.minY - depth)
            )
            x += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + radius))
        var y = rect.minY + radius
        while y < rect.maxY - radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - depth, y: y + pitch),
                control: CGPoint(x: rect.maxX + depth, y: y + radius)
            )
            y += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - depth))
        x = rect.maxX - radius
        while x > rect.minX + radius {
            path.addQuadCurve(
                to: CGPoint(x: x - pitch, y: rect.maxY - depth),
                control: CGPoint(x: x - radius, y: rect.maxY + depth)
            )
            x -= pitch
        }

        path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - radius))
        y = rect.maxY - radius
        while y > rect.minY + radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + depth, y: y - pitch),
                control: CGPoint(x: rect.minX - depth, y: y - radius)
            )
            y -= pitch
        }

        path.closeSubpath()
        return path
    }
}

struct SavePostcardSealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2 - 2
        let steps = 96
        var path = Path()

        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2 - .pi / 2
            let radius = baseRadius + cos(angle * 16) * 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
