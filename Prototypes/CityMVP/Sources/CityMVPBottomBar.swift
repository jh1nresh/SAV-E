#if SAVVY_CITY_MVP
import SwiftUI

/// Map-first local navigation. Capture is a separate action, never a destination.
struct CityMVPBottomBar: View {
    let selection: SaveRootTab
    let onSelect: (SaveRootTab) -> Void
    let onSearch: () -> Void
    let onCapture: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        HStack(spacing: 9) {
            action("magnifyingglass", title: "搜尋 Search", action: onSearch)
            HStack(spacing: 0) {
                destination(.home, icon: "tray.fill", english: "Saved", chinese: "收藏")
                destination(.map, icon: "scope", english: "Map", chinese: "地圖")
                destination(.profile, icon: "person.crop.circle.fill", english: "Me", chinese: "個人")
            }
            .padding(4)
            .cityMVPGlass(in: Capsule())
            action("plus", title: "新增收藏 Add place", action: onCapture)
        }
        .foregroundStyle(CityMVPStyle.ink)
    }

    private func destination(_ tab: SaveRootTab, icon: String, english: String, chinese: String) -> some View {
        let active = selection == tab || (tab == .profile && selection == .friends)
        return Button { onSelect(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(language.localized(english: english, traditionalChinese: chinese))
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(active ? CityMVPStyle.selected : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cityMVP.tab.\(english.lowercased())")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func action(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 21, weight: .semibold))
                .frame(width: 48, height: 48).cityMVPGlass(in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }
}
#endif
