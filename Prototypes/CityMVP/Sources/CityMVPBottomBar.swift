#if SAVVY_CITY_MVP
import SwiftUI

/// Map-first local navigation. Capture is a separate action, never a destination.
struct CityMVPBottomBar: View {
    static let height: CGFloat = 72
    static let horizontalInset: CGFloat = 20
    static let bottomClearance: CGFloat = 32

    let selection: SaveRootTab
    let onSelect: (SaveRootTab) -> Void
    let onSearch: () -> Void
    let onCapture: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        HStack(spacing: 10) {
            action("magnifyingglass", title: "搜尋 Search", action: onSearch)
            HStack(spacing: 0) {
                destination(.home, icon: "tray.fill", english: "Saved", chinese: "收藏")
                destination(.map, icon: "globe", english: "Map", chinese: "地圖")
                destination(.profile, icon: "book.closed.fill", english: "Passport", chinese: "護照")
            }
            .background {
                Color.clear.frame(height: 60).cityMVPGlass(in: Capsule())
            }
            action("plus", title: "新增收藏 Add place", action: onCapture)
        }
        .frame(height: Self.height)
        .foregroundStyle(CityMVPStyle.ink)
    }

    private func destination(_ tab: SaveRootTab, icon: String, english: String, chinese: String) -> some View {
        let active = selection == tab || (tab == .profile && selection == .friends)
        return Button { onSelect(tab) } label: {
            ZStack {
                if tab == .map {
                    Circle().fill(CityMVPStyle.glass)
                        .overlay(Circle().strokeBorder(active ? CityMVPStyle.selected : CityMVPStyle.rim,
                                                       lineWidth: active ? 2 : 1))
                        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                        .frame(width: Self.height, height: Self.height)
                } else if active {
                    Circle().fill(CityMVPStyle.selected).frame(width: 48, height: 48)
                }
                Image(systemName: icon)
                    .font(.system(size: tab == .map ? 29 : 24, weight: .medium))
                if active {
                    Circle().fill(CityMVPStyle.ink).frame(width: 3, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(CityMVPDockPressStyle())
        .accessibilityLabel(language.localized(english: english, traditionalChinese: chinese))
        .accessibilityIdentifier("cityMVP.tab.\(english.lowercased())")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func action(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium))
                .frame(width: 60, height: 60).cityMVPGlass(in: Circle())
        }
        .buttonStyle(CityMVPDockPressStyle()).accessibilityLabel(title)
    }
}

private struct CityMVPDockPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82),
                       value: configuration.isPressed)
    }
}
#endif
