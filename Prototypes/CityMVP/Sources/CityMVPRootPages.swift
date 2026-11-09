#if SAVVY_CITY_MVP
import SwiftUI

struct CityMVPSavedPage: View {
    let places: [Place]
    let onOpen: (Place) -> Void
    let onReview: () -> Void
    let reviewCount: Int
    @Environment(\.appLanguageSettings) private var language
    @State private var query = ""

    var body: some View {
        CityMVPPage(title: label("Saved", "收藏"), subtitle: label("Your places", "你的地點")) {
            if !places.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    TextField(label("Filter saved places", "篩選收藏"), text: $query)
                }
                .padding(13).background(CityMVPStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            if reviewCount > 0 {
                Button(action: onReview) {
                    CityMVPPageRow(symbol: "tray", title: label("Needs review", "待確認"),
                                   subtitle: "\(reviewCount)", tint: CityMVPStyle.muted)
                }.buttonStyle(.plain)
            }
            if places.isEmpty {
                CityMVPPageRow(symbol: "bookmark", title: label("No saved places yet", "還沒有收藏"),
                               subtitle: label("Save a place from the map to find it here.", "在地圖收藏地點後，就會出現在這裡。"),
                               tint: CityMVPStyle.blue, showsChevron: false)
            }
            ForEach(places.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.address.localizedCaseInsensitiveContains(query) }) { place in
                Button { onOpen(place) } label: {
                    CityMVPPageRow(symbol: "mappin", title: place.name,
                                   subtitle: place.address.isEmpty ? place.category.displayName(language: language.language) : place.address,
                                   tint: CityMVPStyle.blue)
                }.buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("cityMVP.savedPage")
    }

    private func label(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

struct CityMVPMePage: View {
    let savedCount: Int
    let onTrips: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @State private var showsFriends = false

    var body: some View {
        CityMVPPage(title: label("Passport", "護照"), subtitle: label("Your Savvy map", "你的 Savvy 地圖")) {
            CityMVPPageRow(symbol: "person.crop.circle.fill", title: label("Local preview", "本地測試版"),
                           subtitle: label("\(savedCount) saved places", "\(savedCount) 個收藏"),
                           tint: CityMVPStyle.blue, showsChevron: false)
            Button { showsFriends = true } label: {
                CityMVPPageRow(symbol: "person.2", title: label("Friends", "朋友"),
                               subtitle: label("Shared recommendations", "朋友分享的推薦"), tint: CityMVPStyle.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cityMVP.passport.friends")
            Button(action: onTrips) {
                CityMVPPageRow(symbol: "suitcase", title: label("Trips", "行程"),
                               subtitle: label("Your trip plans", "你的旅行計畫"), tint: CityMVPStyle.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cityMVP.passport.trips")
        }
        .accessibilityIdentifier("cityMVP.passportPage")
        .sheet(isPresented: $showsFriends) { CityMVPFriendsSheet() }
    }

    private func label(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

struct CityMVPFriendsSheet: View {
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 56)).foregroundStyle(CityMVPStyle.ink)
                    .accessibilityHidden(true)
                Text(language.localized(english: "No friend recommendations yet", traditionalChinese: "還沒有朋友推薦"))
                    .font(.system(size: 25, weight: .bold))
                Text(language.localized(
                    english: "When friends share places, tap their avatar to see what they recommend. Places join your list after you save them.",
                    traditionalChinese: "朋友分享地點後，可以從頭像查看他的推薦。你確認收藏後，才會放進自己的清單。"
                ))
                .multilineTextAlignment(.center).foregroundStyle(CityMVPStyle.muted)
                Text(language.localized(
                    english: "Friends are offline in this preview",
                    traditionalChinese: "本地測試版尚未連接朋友資料"
                ))
                .font(.footnote).foregroundStyle(CityMVPStyle.muted)
                .accessibilityIdentifier("cityMVP.friends.offline")
            }
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CityMVPStyle.canvas)
            .navigationTitle(language.localized(english: "Friend recommendations", traditionalChinese: "朋友推薦"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.localized(english: "Done", traditionalChinese: "完成")) { dismiss() }
                        .accessibilityIdentifier("cityMVP.friends.done")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct CityMVPPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 36, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(CityMVPStyle.muted)
                    .padding(.bottom, 12)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 72).padding(.bottom, 120)
        }
        .background(CityMVPStyle.canvas)
        .foregroundStyle(CityMVPStyle.ink)
    }
}

private struct CityMVPPageRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint).frame(width: 42, height: 42)
                .background(CityMVPStyle.panel, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(CityMVPStyle.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(CityMVPStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(CityMVPStyle.muted)
            }
        }
        .padding(12)
        .background(CityMVPStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
    }
}
#endif
