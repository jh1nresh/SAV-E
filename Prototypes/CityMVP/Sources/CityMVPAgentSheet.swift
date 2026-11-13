#if SAVVY_CITY_MVP
import SwiftUI

struct CityMVPAgentSheet: View {
    let places: [Place]
    let onOpen: (Place) -> Void
    var dismissOnOpen = true
    var opensSavedDetail = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @EnvironmentObject private var recommendations: CityMVPRecommendationStore
    @EnvironmentObject private var auth: PrivyAuthService
    @State private var input = ""
    @State private var friendsOnly = false
    @State private var appliedQuery = ""
    @State private var answer: [CityMVPAgentMemory]?
    @State private var selectedPlace: Place?
    @State private var showsAI = false
    @State private var pendingAIPlaceID: UUID?
    @State private var pendingAIGeneration: Int?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("A familiar place\nis a good start.", "從熟悉的地方，\n開始下一段路。"))
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Label(friendsOnly ? t("Local search · Copied recommendations", "本地搜尋 · 複製的推薦") : t("Preview · Saved-place search", "測試版 · 搜尋已確認收藏"), systemImage: friendsOnly ? "person.2" : "bookmark")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(CityMVPFormStyle.card, in: Capsule())
                    Text(friendsOnly ? t("Search the places, sender labels and reasons in recommendations you kept. Sender identities are not verified.", "搜尋已保留推薦中的地點、寄件者稱呼與推薦原因。寄件者身分尚未驗證。") : t("Find a confirmed save by name, area, or category.", "用店名、區域或類別，找回已確認的收藏。"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                    HStack(spacing: 8) {
                        searchMode(false, title: t("Saved places", "已收藏地點"))
                        searchMode(true, title: t("Friends’ picks", "朋友的推薦"))
                    }
                    Button(t("Ask Guide AI · choose what to share", "詢問 Guide AI · 選擇分享內容")) { showsAI = true }
                        .frame(minHeight: 44).accessibilityIdentifier("cityMVP.agent.ai")
                    if friendsOnly { friendResults }
                    if answer == nil && !friendsOnly {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            quickSearch(.food, emoji: "🍜")
                            quickSearch(.cafe, emoji: "☕️")
                            quickSearch(.bar, emoji: "🍸")
                            quickSearch(.attraction, emoji: "🏛️")
                        }
                    }
                    if let answer, !friendsOnly {
                        if answer.isEmpty {
                            Text(places.isEmpty
                                 ? t("No saved places yet. Add one from the map and try again.", "還沒有收藏。先從地圖收藏一個地點，再來問我。")
                                 : t("No confirmed matches. Try a shorter place or area name.", "找不到符合的已確認收藏。試試較短的店名或區域。"))
                                .accessibilityIdentifier("cityMVP.agent.empty")
                        }
                        ForEach(answer) { result in
                            Button {
                                guard let place = places.first(where: { $0.id.uuidString == result.id }) else { return }
                                focused = false
                                selectedPlace = place
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Map Stamp · Confirmed save", "Map Stamp · 已確認收藏"))
                                        .font(.caption).foregroundStyle(CityMVPFormStyle.muted)
                                    Text(result.name).font(.headline)
                                    Text(result.category)
                                        .font(.subheadline.weight(.medium)).foregroundStyle(CityMVPFormStyle.muted)
                                    if !result.address.isEmpty {
                                        Text(result.address).font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cityMVP.agent.result.\(result.id)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("Your friends. A local point of view.", "朋友的推薦，在地的視角。"))
                            .font(.headline)
                        Text(t("Open a saved place for its address, sources and recommendations you kept. Apple can translate pasted source text. Live friend connections and AI conversations are not connected yet.", "開啟收藏，可查看地址、來源與你保留的推薦說明；也可使用 Apple 翻譯貼上的原文。目前尚未連接即時朋友資料與 AI 對話。"))
                            .font(.footnote).foregroundStyle(CityMVPFormStyle.muted)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .background(CityMVPFormStyle.canvas)
            .foregroundStyle(CityMVPFormStyle.ink)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    TextField(friendsOnly ? t("Place, sender, or reason", "地點、寄件者或推薦原因") : t("Place, area, or category", "店名、區域或類別"), text: $input)
                        .focused($focused).submitLabel(.search).onSubmit(ask)
                        .accessibilityIdentifier("cityMVP.agent.input")
                    if !input.isEmpty {
                        Button {
                            input = ""; appliedQuery = ""; answer = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(t("Clear search", "清除搜尋"))
                            .accessibilityIdentifier("cityMVP.agent.clear")
                    }
                    Button(action: ask) {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(CityMVPFormStyle.ink, in: Circle())
                            .foregroundStyle(CityMVPFormStyle.canvas).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!friendsOnly && CityMVPAgentSearch.terms(input).isEmpty)
                    .accessibilityLabel(friendsOnly ? t("Search kept recommendations", "搜尋保留的推薦") : t("Search saved places", "搜尋收藏"))
                    .accessibilityIdentifier("cityMVP.agent.ask")
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 5)
                .background(CityMVPFormStyle.card, in: Capsule())
                .padding(12).background(CityMVPFormStyle.canvas)
            }
            .navigationTitle("SAV-E Guide")
            .navigationDestination(item: $selectedPlace) { place in
                CityMVPGuideBriefSheet(place: place, onOpen: { selected in
                    if dismissOnOpen { dismiss() }
                    onOpen(selected)
                }, opensSavedDetail: opensSavedDetail)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsAI, onDismiss: {
                let id = pendingAIPlaceID, generation = pendingAIGeneration
                pendingAIPlaceID = nil; pendingAIGeneration = nil
                selectedPlace = CityMVPGuideAIController.resolveHandoff(placeID: id, selectedGeneration: generation,
                    currentGeneration: auth.sessionGeneration, places: places)
            }) {
                CityMVPGuideAISelectionSheet(places: places) {
                    pendingAIPlaceID = $0.id; pendingAIGeneration = auth.sessionGeneration
                }
                    .presentationDetents([.large])
            }
            .onChange(of: auth.sessionGeneration) { _, _ in
                input = ""; appliedQuery = ""; answer = nil; selectedPlace = nil
                pendingAIPlaceID = nil; pendingAIGeneration = nil; showsAI = false; dismiss()
            }
            .onChange(of: places.map(\.id)) { _, current in
                if let selectedPlace, !current.contains(selectedPlace.id) { self.selectedPlace = nil }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("cityMVP.agent.done")
                }
            }
        }.tint(CityMVPFormStyle.ink)
    }

    private func quickSearch(_ category: PlaceCategory, emoji: String) -> some View {
        Button {
            input = category.displayName(language: language.language)
            ask()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(emoji).font(.title).accessibilityHidden(true)
                Text(category.displayName(language: language.language)).font(.headline)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("cityMVP.agent.category.\(category.rawValue)")
    }

    private func ask() {
        guard friendsOnly || !CityMVPAgentSearch.terms(input).isEmpty else { return }
        focused = false
        if friendsOnly { appliedQuery = input; return }
        // MapViewModel.places is the confirmed vault; review and discovery have separate stores.
        let memory = places.map {
            CityMVPAgentMemory(id: $0.id.uuidString, name: $0.name, address: $0.address,
                               category: $0.category.displayName(language: language.language), state: "confirmed")
        }
        answer = CityMVPAgentSearch.matches(input, in: memory)
    }

    private func searchMode(_ friends: Bool, title: String) -> some View {
        Button {
            friendsOnly = friends
            appliedQuery = input
            if !friends { answer = nil }
            focused = false
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(friendsOnly == friends ? CityMVPFormStyle.ink : CityMVPFormStyle.card, in: Capsule())
                .foregroundStyle(friendsOnly == friends ? CityMVPFormStyle.canvas : CityMVPFormStyle.ink)
                .contentShape(Capsule())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(friendsOnly == friends ? .isSelected : [])
            .accessibilityIdentifier(friends ? "cityMVP.agent.mode.friends" : "cityMVP.agent.mode.saved")
    }

    private var friendResults: some View {
        let matches = CityMVPRecommendationSearch.matches(appliedQuery, places: places, records: recommendations.records)
        return VStack(alignment: .leading, spacing: 12) {
            if recommendations.failure != nil {
                Text(t("Recommendation details are unavailable. Existing files have not been reset.", "暫時無法讀取推薦說明，既有檔案未被重設。"))
            }
            if matches.isEmpty {
                Text(t("No matching kept recommendations. Import a recommendation file from Friends’ picks in Passport, or try a shorter search.", "沒有符合的已保留推薦。可從 Passport 的朋友推薦匯入檔案，或試試較短的搜尋。"))
                    .accessibilityIdentifier("cityMVP.agent.friends.empty")
            }
            ForEach(matches) { match in
                if let place = places.first(where: { $0.id == match.placeID }) {
                    Button { focused = false; selectedPlace = place } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("Map Stamp · Confirmed save", "Map Stamp · 已確認收藏")).font(.caption)
                            Text(place.name).font(.headline)
                            if !place.address.isEmpty { Text(place.address).font(.subheadline) }
                            ForEach(match.matchingRecordIDs, id: \.self) { id in
                                if let source = recommendations.records.first(where: { $0.id == id }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.senderLabel).font(.subheadline.bold())
                                        Text(t("Copied sender label · identity not verified", "複製的寄件者稱呼 · 身分未驗證")).font(.caption)
                                        Text(source.reason).font(.subheadline)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 18))
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("cityMVP.agent.friendResult." + place.id.uuidString)
                }
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
