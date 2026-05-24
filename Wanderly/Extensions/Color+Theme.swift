import SwiftUI

extension Color {
    // MARK: - SAV-E Field Notebook Theme
    static let saveCream = Color(hex: "FFF7E8")
    static let saveMint = Color(hex: "B8F5C8")
    static let saveCocoa = Color(hex: "111111")
    static let saveHoney = Color(hex: "FFE24A")
    static let saveSky = Color(hex: "7EDAEF")
    static let saveInk = Color(hex: "111111")
    static let savePaper = Color(hex: "FFF0D6")
    static let saveLedger = Color(hex: "FFF7E8")
    static let saveSignal = Color(hex: "FF8A65")
    static let saveSuccess = Color(hex: "B8F5C8")
    static let saveCoral = Color(hex: "FF8A65")
    static let savePink = Color(hex: "FFD7E8")
    static let saveNotebookBackground = Color(hex: "FFF7E8")
    static let saveNotebookPage = Color(hex: "FFF0D6")
    static let saveNotebookSpine = Color(hex: "FFE24A")
    static let saveNotebookLine = Color(hex: "111111")

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
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
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
                            context.fill(Path(ellipseIn: rect), with: .color(Color.saveNotebookLine.opacity(0.08)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}
