#if !SAVVY_MAIN_APP || (DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW)
import SwiftUI

enum DateTheme {
#if SAVVY_MAIN_APP
    static let ink = CityMVPStyle.ink
    static let muted = CityMVPStyle.muted
    static let canvas = CityMVPStyle.canvas
    static let surface = CityMVPStyle.surface
    static let soft = CityMVPStyle.panel
    static let blue = CityMVPStyle.blue
    static let coral = CityMVPStyle.blue
    static let green = CityMVPStyle.blue
    static let action = CityMVPStyle.actionFill
#else
    static let ink = Color(red: 0.065, green: 0.075, blue: 0.10)
    static let muted = Color(red: 0.42, green: 0.43, blue: 0.46)
    static let canvas = Color(red: 0.965, green: 0.963, blue: 0.950)
    static let soft = Color(red: 0.947, green: 0.944, blue: 0.925)
    static let coral = Color(red: 0.953, green: 0.31, blue: 0.18)
    static let blue = Color(red: 0.20, green: 0.46, blue: 0.87)
    static let green = Color(red: 0.24, green: 0.44, blue: 0.34)
    static let surface = Color.white
    static let action = ink
#endif
}

struct DemoAvatar: View {
    let person: DemoParticipant
    var size: CGFloat = 34
    var body: some View {
        Text(person == .you ? "你" : "安")
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(DateTheme.ink)
            .frame(width: size, height: size)
            .background(person == .you ? Color(red: 0.77, green: 0.87, blue: 0.98)
                        : Color(red: 0.99, green: 0.79, blue: 0.65), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .accessibilityLabel(person == .you ? "你" : "小安，示範參加者")
    }
}

struct DemoPrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 12)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30).background(.white.opacity(0.15), in: Circle())
            }
            .padding(.horizontal, 18).frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(enabled ? DateTheme.action : DateTheme.muted.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct DemoPlaceIcon: View {
    let place: DemoPlace
    var size: CGFloat = 52
    var body: some View {
        Text(place.emoji).font(.system(size: size * 0.57))
            .frame(width: size, height: size)
            .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: size * 0.30))
            .accessibilityHidden(true)
    }
}

struct DemoPill: View {
    let text: String
    var tint: Color = DateTheme.muted
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.08), in: Capsule())
    }
}

extension View {
    func demoCard() -> some View {
        padding(18).background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DateTheme.ink.opacity(0.04)))
            .shadow(color: .black.opacity(0.075), radius: 18, x: 0, y: 6)
    }
}

#endif
