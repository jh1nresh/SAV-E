#if SAVVY_CITY_MVP
import SwiftUI

/// Native-map artwork only. The caller owns selection, actions and place truth.
struct CityMVPStatePin: View {
    enum State {
        case review
        case search
        case shared

        fileprivate var symbol: String {
            switch self {
            case .review: "questionmark"
            case .search: "magnifyingglass"
            case .shared: "person.2.fill"
            }
        }
    }

    static let size: CGSize = CGSize(width: 140, height: 124)
    // The geographic contact ends the head; the caption extends below it.
    static let annotationAnchor = UnitPoint(x: 0.5, y: 72.0 / 124.0)

    let title: String
    let symbol: String
    let state: State
    let selected: Bool

    @Environment(\.appLanguageSettings) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, symbol: String, state: State, selected: Bool) {
        self.title = title
        self.symbol = symbol
        self.state = state
        self.selected = selected
    }

    var body: some View {
        VStack(spacing: 0) {
            CityPinArtwork(id: nil, title: title, symbol: symbol,
                           saved: false, selected: selected, titleOpacity: 0)
                .frame(width: Self.size.width, height: CityPinArtwork.height)
                .overlay(alignment: .bottom) {
                    stateBadge
                        .offset(x: selected ? 26 : 16, y: -2)
                        .animation(reduceMotion ? nil : .spring(CityPinArtwork.photoSpring), value: selected)
                }
            caption
                .frame(width: Self.size.width, height: 52, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(stateTitle)"))
    }

    private var stateBadge: some View {
        Image(systemName: state.symbol)
            .font(.system(size: state == .shared ? 9 : 11, weight: .bold))
            .foregroundStyle(CityMVPStyle.ink)
            .frame(width: 20, height: 20)
            .background(CityMVPStyle.surface, in: Circle())
            .overlay(Circle().strokeBorder(CityMVPStyle.ink.opacity(0.7), lineWidth: 1.1))
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CityMVPStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Label(stateTitle, systemImage: state.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CityMVPStyle.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(CityMVPStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(CityMVPStyle.rim, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
        .padding(.top, 2)
    }

    private var stateTitle: String {
        switch state {
        case .review:
            language.localized(english: "To confirm", traditionalChinese: "待確認")
        case .search:
            language.localized(english: "Not saved", traditionalChinese: "未收藏")
        case .shared:
            language.localized(english: "Shared", traditionalChinese: "分享地點")
        }
    }
}
#endif
