#if SAVVY_CITY_MVP
import SwiftUI

struct CityMVPAgentSheet: View {
    let places: [Place]
    let onOpen: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @State private var input = ""
    @State private var answer: [CityMVPAgentMemory]?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("Find a place you saved", "找回你收藏的地點"))
                        .font(.system(size: 26, weight: .bold))
                    Text(t("Search this test app’s confirmed saves by name, area, or category.", "用店名、區域或類別搜尋測試版裡已確認的收藏。"))
                        .font(.subheadline).foregroundStyle(CityMVPStyle.muted)
                    if let answer {
                        if answer.isEmpty {
                            Text(places.isEmpty
                                 ? t("No saved places yet. Add one from the map and try again.", "還沒有收藏。先從地圖收藏一個地點，再來問我。")
                                 : t("No confirmed matches. Try a shorter place or area name.", "找不到符合的已確認收藏。試試較短的店名或區域。"))
                                .accessibilityIdentifier("cityMVP.agent.empty")
                        }
                        ForEach(answer) { result in
                            Button {
                                guard let place = places.first(where: { $0.id.uuidString == result.id }) else { return }
                                dismiss()
                                onOpen(place)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Map Stamp · Confirmed save", "Map Stamp · 已確認收藏"))
                                        .font(.caption).foregroundStyle(CityMVPStyle.blue)
                                    Text(result.name).font(.headline)
                                    Text(result.category)
                                        .font(.subheadline.weight(.medium)).foregroundStyle(CityMVPStyle.muted)
                                    if !result.address.isEmpty {
                                        Text(result.address).font(.subheadline).foregroundStyle(CityMVPStyle.muted)
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CityMVPStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .background(CityMVPStyle.canvas)
            .foregroundStyle(CityMVPStyle.ink)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    TextField(t("Place, area, or category", "店名、區域或類別"), text: $input)
                        .focused($focused).submitLabel(.search).onSubmit(ask)
                        .accessibilityIdentifier("cityMVP.agent.input")
                    Button(action: ask) {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(CityMVPStyle.selected, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(CityMVPAgentSearch.terms(input).isEmpty)
                    .accessibilityLabel(t("Search saved places", "搜尋收藏"))
                    .accessibilityIdentifier("cityMVP.agent.ask")
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 5)
                .background(CityMVPStyle.panel, in: Capsule())
                .padding(12).background(CityMVPStyle.canvas)
            }
            .navigationTitle("SAV-E Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "完成")) { dismiss() }
                }
            }
        }
    }

    private func ask() {
        guard !CityMVPAgentSearch.terms(input).isEmpty else { return }
        focused = false
        // MapViewModel.places is the confirmed vault; review and discovery have separate stores.
        let memory = places.map {
            CityMVPAgentMemory(id: $0.id.uuidString, name: $0.name, address: $0.address,
                               category: $0.category.displayName(language: language.language), state: "confirmed")
        }
        answer = CityMVPAgentSearch.matches(input, in: memory)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
