#if SAVVY_CITY_MVP
import SwiftUI
import UIKit

enum CityMVPStyle {
    static let nightPreference = "cityMVP.night"

    static let ink = Color(uiColor: adaptive(0x121726, 0xF2F6FF))
    static let muted = Color(uiColor: adaptive(0x575F73, 0xB2C2D7))
    static let canvas = Color(uiColor: adaptive(0xF5F7FF, 0x0D1728))
    static let surface = Color(uiColor: adaptive(0xFFFFFF, 0x202F45))
    static let panel = Color(uiColor: adaptive(0xE8F0FF, 0x182438))
    static let blue = Color(uiColor: adaptive(0x2159D4, 0xA1C9FF))
    static let selected = Color(uiColor: adaptive(0xC7E0FF, 0x31496D))
    static let actionFill = Color(uiColor: adaptive(0x121726, 0x225DB9))
    static let rim = Color(uiColor: adaptive(0xFFFFFF, 0x455978))
    static let glass = LinearGradient(colors: [surface, panel], startPoint: .top, endPoint: .bottom)

    static let pinInk = adaptive(0x172138, 0xF2F6FF)
    static let pinPanel = adaptive(0xF5FAFF, 0x1D2A40)
    static let pinSaved = adaptive(0x94C7FF, 0x385985)
    static let pinCandidate = adaptive(0xDEE6F8, 0x334560)

    // SwiftUI can resolve a UIKit dynamic color on its render thread.
    private nonisolated static func adaptive(_ day: UInt32, _ night: UInt32) -> UIColor {
        UIColor { @Sendable traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}

extension View {
    func cityMVPGlass<S: InsettableShape>(in shape: S) -> some View {
        background(CityMVPStyle.glass, in: shape)
            .overlay(shape.strokeBorder(CityMVPStyle.rim.opacity(0.72), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
    }
}
#endif
