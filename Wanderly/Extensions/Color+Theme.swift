import SwiftUI

extension Color {
    // MARK: - Wanderly Light Theme
    static let wanderlyCream = Color(hex: "FFF8F0")
    static let wanderlyTerracotta = Color(hex: "C75B39")
    static let wanderlySage = Color(hex: "A8B5A0")
    static let wanderlyCharcoal = Color(hex: "2C2C2E")

    // MARK: - Wanderly Dark Theme
    static let wanderlyDarkBackground = Color(hex: "1C1C1E")
    static let wanderlyAmber = Color(hex: "E8A87C")

    // MARK: - Semantic Colors
    static let wanderlyBackground = Color("WanderlyBackground")
    static let wanderlyAccent = Color("WanderlyAccent")
    static let wanderlySecondary = Color("WanderlySecondary")
    static let wanderlyText = Color("WanderlyText")

    // MARK: - Category Colors
    static func categoryColor(for category: PlaceCategory) -> Color {
        switch category {
        case .food: return .wanderlyTerracotta
        case .cafe: return Color(hex: "B07D62")
        case .bar: return Color(hex: "8B5E83")
        case .attraction: return Color(hex: "5B8FA8")
        case .stay: return .wanderlySage
        case .shopping: return Color(hex: "C4956A")
        }
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

// MARK: - View Modifier for Wanderly Theme

struct WanderlyCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.wanderlyCream)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func wanderlyCard() -> some View {
        modifier(WanderlyCardStyle())
    }
}
