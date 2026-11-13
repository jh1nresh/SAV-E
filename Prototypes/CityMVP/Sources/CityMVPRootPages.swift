#if SAVVY_CITY_MVP
import SwiftUI

struct CityMVPSavedPage: View {
    let places: [Place]
    let onOpen: (Place) -> Void
    let onReview: () -> Void
    let reviewCount: Int
    let onAdd: () -> Void
    let onAsk: () -> Void
    let isActive: Bool
    var historyOwner: String? = nil
    var onHistory: (() -> Void)? = nil
    @State private var showsHistory = false
    @Environment(\.appLanguageSettings) private var language
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    private var matchingPlaces: [Place] {
        places.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            || $0.address.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        CityMVPPage(title: label("Saved", "收藏"), subtitle: label("Good places, chosen by you.", "你挑選的好地方，都在這裡。"), onAsk: { filterFocused = false; onAsk() }, isActive: isActive) {
            if !places.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    TextField(label("Filter saved places", "篩選收藏"), text: $query)
                        .focused($filterFocused)
                        .submitLabel(.search).onSubmit { filterFocused = false }
                        .accessibilityIdentifier("cityMVP.saved.filter")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(CityMVPFormStyle.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(label("Clear filter", "清除篩選"))
                            .accessibilityIdentifier("cityMVP.saved.clearFilter")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4).frame(minHeight: 52)
                .background(CityMVPFormStyle.card, in: Capsule())
            }
            if historyOwner != nil {
                Button { if let onHistory { onHistory() } else { showsHistory = true } } label: {
                    CityMVPPageRow(symbol: "clock.arrow.circlepath", title: label("Place history", "地點紀錄"),
                        subtitle: label("Earlier saves and visits", "過往保存與到訪"), tint: CityMVPFormStyle.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("main.saved.history")
            }
            if reviewCount > 0 {
                Button(action: onReview) {
                    CityMVPPageRow(symbol: "tray", title: label("Needs review", "待確認"),
                                   subtitle: "\(reviewCount)", tint: CityMVPFormStyle.ink)
                }.buttonStyle(.plain)
            }
            if places.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "bookmark").font(.system(size: 28, weight: .medium))
                        .frame(width: 64, height: 64)
                        .background(CityMVPFormStyle.canvas, in: Circle())
                    Text(label("Your next favorite\nstarts here.", "下一個喜歡的地方，\n從這裡開始。"))
                        .font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text(label("Bring a link, a screenshot, or a name. You'll confirm the place before it joins your map.", "帶來連結、截圖或名字。確認地點後，才會放進你的地圖。"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                    Button(action: onAdd) {
                        HStack {
                            Text(label("Add a place", "新增地點"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.font(.headline).foregroundStyle(CityMVPFormStyle.canvas).padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(CityMVPFormStyle.ink, in: Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("cityMVP.saved.add")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 30))
            }
            if !places.isEmpty && matchingPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label("No saved places match.", "沒有符合的收藏。"))
                        .font(.headline)
                    Text(label("Try another name or address, or clear the filter.", "試試其他名稱或地址，或清除篩選。"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("cityMVP.saved.noMatches")
            }
            ForEach(matchingPlaces) { place in
                Button { onOpen(place) } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let photo = CityPinArtwork.photo(for: CityMVPPlaceBridge.contextID(for: place)) {
                                Image(uiImage: photo.image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "bookmark.fill").font(.title2)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(CityMVPFormStyle.canvas)
                            }
                        }.frame(width: 60, height: 60).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(place.name).font(.headline)
                            Text(place.address.isEmpty ? place.category.displayName(language: language.language) : place.address)
                                .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted).lineLimit(2)
                            Text(label("Map Stamp · Saved", "Map Stamp · 已收藏")).font(.caption).foregroundStyle(CityMVPFormStyle.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.padding(16).background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain)
            }
            if !places.isEmpty {
                Text(label("\(places.count) saved places", "\(places.count) 個收藏"))
                    .font(.footnote).foregroundStyle(CityMVPFormStyle.muted).padding(.top, 8)
            }
        }
        .accessibilityIdentifier("cityMVP.savedPage")
        .sheet(isPresented: $showsHistory) {
            if let historyOwner { SavvyPlaceHistorySheet(ownerSubject: historyOwner, places: places) }
        }
        .onChange(of: isActive) { _, active in
            if !active { filterFocused = false }
        }
    }

    private func label(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

struct CityMVPMePage: View {
    let savedCount: Int
    let onTrips: () -> Void
    let onAsk: () -> Void
    var places: [Place] = []
    var onSaveFriendPlace: (Place) async throws -> Place = { _ in throw CocoaError(.featureUnsupported) }
    var selectedPlaceTitle: String? = nil
    var selectedPlaceSourceURL: String? = nil
    var historyOwner: String? = nil
    var isActive = true
    var onFriends: (() -> Void)? = nil
    var onInformation: (() -> Void)? = nil
    var onAccount: (() -> Void)? = nil
    @Environment(\.appLanguageSettings) private var language
    @State private var showsFriends = false
    @State private var showsMapInformation = false

    var body: some View {
        CityMVPPage(title: label("Passport", "護照"), subtitle: label("Your places. Your people.", "你的地方，你信任的人。"), onAsk: onAsk, isActive: isActive) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "book.closed").font(.system(size: 28, weight: .medium))
                    .frame(width: 64, height: 64).background(CityMVPFormStyle.canvas, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(label("\(savedCount) saved places", "\(savedCount) 個收藏")).font(.title2.bold())
                    Text(historyOwner == nil ? label("Local preview · account not connected", "本地測試版 · 尚未連接帳號") : label("Signed in · your saved places", "已登入 · 你的收藏"))
                        .font(.caption).foregroundStyle(CityMVPFormStyle.muted)
                }
                Spacer(minLength: 0)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 28))
                .padding(.bottom, 12)
            if let onAccount {
                Button(action: onAccount) {
                    CityMVPPageRow(symbol: "person.crop.circle", title: label("Account & settings", "帳號與設定"),
                        subtitle: label("Profile, language and privacy", "個人資料、語言與隱私"), tint: CityMVPFormStyle.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("main.passport.account")
            }
            Text(label("Make it yours", "照你的方式出發")).font(.title3.bold()).padding(.bottom, 2)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { if let onFriends { onFriends() } else { showsFriends = true } } label: {
                    CityMVPShortcut(emoji: "👋", title: label("Friends' picks", "朋友推薦"),
                                    subtitle: label("Shared by choice", "由朋友選擇分享"))
                }.buttonStyle(.plain).accessibilityIdentifier("cityMVP.passport.friends")
                Button(action: onTrips) {
                    CityMVPShortcut(emoji: "🧭", title: label("Trips", "行程"),
                                    subtitle: label("Your plans", "你的旅行計畫"))
                }.buttonStyle(.plain).accessibilityIdentifier("cityMVP.passport.trips")
            }.padding(.bottom, 12)
            Button { if let onInformation { onInformation() } else { showsMapInformation = true } } label: {
                CityMVPPageRow(symbol: "info.circle", title: label("Map & photo information", "地圖與照片資訊"),
                               subtitle: label("Sources and credits", "資料來源與署名"), tint: CityMVPFormStyle.ink)
            }.buttonStyle(.plain).accessibilityIdentifier("cityMVP.passport.mapInformation")
        }
        .accessibilityIdentifier("cityMVP.passportPage")
        .sheet(isPresented: $showsFriends) {
            CityMVPFriendExchangeSheet(places: places, onSave: onSaveFriendPlace)
        }
        .sheet(isPresented: $showsMapInformation) {
            CityMVPMapInformation(selectedPlaceTitle: selectedPlaceTitle, selectedPlaceSourceURL: selectedPlaceSourceURL)
        }
    }

    private func label(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

struct CityMVPMapInformation: View {
    let selectedPlaceTitle: String?
    let selectedPlaceSourceURL: String?

    private var selectedSource: URL? {
        guard selectedPlaceTitle != nil, let raw = selectedPlaceSourceURL,
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    private func t(_ en: String, _ zh: String) -> String { language.localized(english: en, traditionalChinese: zh) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let selectedSource, let selectedPlaceTitle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("Selected place source", "目前選取地點的來源")).font(.headline)
                            Text(selectedPlaceTitle).font(.subheadline)
                            Link(t("Open source", "開啟來源"), destination: selectedSource)
                                .frame(minHeight: 44, alignment: .leading)
                                .accessibilityIdentifier("cityMVP.mapInformation.selectedSource")
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                    }
                    Text(t("Maps", "地圖")).font(.title2.bold())
                    Text(t("Apple MapKit renders the world and Taipei map. The Shanghai Amap connection is not configured in this preview.", "世界與台北底圖使用 Apple MapKit。本測試版尚未設定上海高德連線。"))
                    Text(t("Apple Maps' regional data providers may vary. In China, Apple Maps uses Amap.", "Apple 地圖的資料供應商依地區而異；在中國使用高德地圖資料。"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                    Link(t("Apple Maps privacy & providers", "Apple 地圖隱私與資料供應商"),
                         destination: URL(string: "https://www.apple.com/legal/privacy/data/en/apple-maps/")!)
                        .frame(minHeight: 44, alignment: .leading)
                    Text(t("Xinyi 3D district", "信義 3D 街區")).font(.headline)
                    Text(t("Savvy's local 3D scene covers part of Xinyi. Geographic data: © OpenStreetMap contributors, ODbL.", "Savvy 本地 3D 場景涵蓋部分信義區。地理資料：© OpenStreetMap contributors，ODbL。"))
                    Link("OpenStreetMap · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .frame(minHeight: 44, alignment: .leading)
                    Text(t("Photos", "照片")).font(.title2.bold())
                    photo("Tower of Taipei 101", id: "landmark-101", sourceURL: "https://commons.wikimedia.org/wiki/File:Tower_of_Taipei_101.jpg", author: "AnthonySantiago101", license: "CC BY-SA 4.0", licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/")
                    photo("ATT 4 Fun Exterior view 201911", id: "way/234589397", sourceURL: "https://commons.wikimedia.org/wiki/File:ATT_4_Fun_Exterior_view_201911.jpg", author: "Wpcpey", license: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/")
                    Text(t("Photos were cropped and resized. The Taipei 101 thumbnail is distributed under CC BY-SA 4.0. Credits do not imply endorsement.", "照片經裁切與縮放。台北 101 縮圖依 CC BY-SA 4.0 授權散布；署名不代表作者推薦或背書。"))
                        .font(.footnote).foregroundStyle(CityMVPFormStyle.muted)
                }.padding(24)
            }.background(CityMVPFormStyle.canvas).foregroundStyle(CityMVPFormStyle.ink)
                .navigationTitle(t("Map & photo information", "地圖與照片資訊"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "完成")) { dismiss() }.accessibilityIdentifier("cityMVP.mapInformation.done")
                } }
        }.tint(CityMVPFormStyle.ink).presentationDetents([.large])
    }
    private func photo(_ title: String, id: String, sourceURL: String, author: String, license: String, licenseURL: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let photo = CityPinArtwork.photo(for: id) {
                Image(uiImage: photo.image).resizable().scaledToFill().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(author).font(.subheadline)
                    Link(t("Original photo", "原始照片"), destination: URL(string: sourceURL)!).frame(minHeight: 44, alignment: .leading)
                    Link(license, destination: URL(string: licenseURL)!).frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}

struct CityMVPFriendsSheet: View {
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dismiss) private var dismiss
    private func t(_ en: String, _ zh: String) -> String { language.localized(english: en, traditionalChinese: zh) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "person.2").font(.system(size: 28, weight: .medium))
                        .frame(width: 64, height: 64).background(CityMVPFormStyle.card, in: Circle())
                        .accessibilityHidden(true)
                    Text(t("Good places travel\nthrough good friends.", "好地方，\n從信任的朋友開始。"))
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(t("No friend recommendations yet", "還沒有朋友推薦")).font(.headline)
                    Text(t("Friends are offline in this preview", "本地測試版尚未連接朋友資料"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                        .accessibilityIdentifier("cityMVP.friends.offline")
                    VStack(alignment: .leading, spacing: 18) {
                        Text(t("When friends are connected", "連接朋友後的流程")).font(.headline)
                        friendStep("1", t("They share", "朋友分享"), t("Only recommendations and notes they choose to share.", "只使用朋友選擇分享的推薦與心得。"))
                        friendStep("2", t("You choose", "你來挑選"), t("Pick the people you trust and the places that interest you.", "挑選你信任的朋友，以及感興趣的地方。"))
                        friendStep("3", t("A guide helps", "導遊協助"), t("The planned Guide will explain the choices and help plan your route.", "規劃中的 Guide 會解釋地點資訊，並協助安排行程。"))
                    }.padding(20).background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 28))
                    Text(t("Shared is not saved. A friend's visit is not a recommendation. Your map changes only after you confirm a place.", "分享不等於收藏；朋友去過，也不代表推薦。你確認地點後，才會加入自己的地圖。"))
                        .font(.footnote).foregroundStyle(CityMVPFormStyle.muted)
                }.padding(24)
            }.foregroundStyle(CityMVPFormStyle.ink).background(CityMVPFormStyle.canvas)
                .navigationTitle(t("Friends' picks", "朋友推薦"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "完成")) { dismiss() }.accessibilityIdentifier("cityMVP.friends.done")
                } }
        }.tint(CityMVPFormStyle.ink).presentationDetents([.large])
    }

    private func friendStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.bold()).frame(width: 28, height: 28)
                .background(CityMVPFormStyle.canvas, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
            }
        }
    }
}

private struct CityMVPShortcut: View {
    let emoji: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emoji).font(.title).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(CityMVPFormStyle.muted)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
            .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct CityMVPPage<Content: View>: View {
    let title: String
    let subtitle: String
    let onAsk: () -> Void
    let isActive: Bool
    @Environment(\.appLanguageSettings) private var language
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                    .padding(.bottom, 12)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 72).padding(.bottom, 24)
        }
        .background(CityMVPFormStyle.canvas.ignoresSafeArea())
        .foregroundStyle(CityMVPFormStyle.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if isActive {
                    guideEntry
                } else {
                    Color.clear.frame(height: 60).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, CityMVPBottomBar.bottomClearance + CityMVPBottomBar.height + 16)
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isActive)
    }

    private var guideEntry: some View {
        Button(action: onAsk) {
            HStack(spacing: 12) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(CityMVPFormStyle.ink)
                    .frame(width: 44, height: 44)
                    .background(CityMVPFormStyle.canvas, in: Circle())
                    .accessibilityHidden(true)
                Text(language.localized(english: "Ask SAV-E", traditionalChinese: "詢問 SAV-E"))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(CityMVPFormStyle.canvas)
            }
            .padding(.leading, 8).padding(.trailing, 20).padding(.vertical, 8)
            .frame(minHeight: 60)
            .background(CityMVPFormStyle.ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cityMVP.guide.entry")
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
                .background(CityMVPFormStyle.canvas, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(CityMVPFormStyle.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(CityMVPFormStyle.muted)
            }
        }
        .padding(12)
        .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
    }
}
#endif
