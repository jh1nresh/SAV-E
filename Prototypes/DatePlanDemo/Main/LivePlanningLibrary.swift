#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI

@MainActor
struct LivePlanningLibraryView: View {
    let places: [Place]
    let isLoading: Bool
    let onOpen: (Place) -> Void
    let onCapture: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @State private var query = ""
    @State private var filter: LiveLibraryFilter = .all

    init(places: [Place], isLoading: Bool, onOpen: @escaping (Place) -> Void,
         onCapture: @escaping () -> Void) {
        self.places = places
        self.isLoading = isLoading
        self.onOpen = onOpen
        self.onCapture = onCapture
    }

    private var matches: [Place] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return places.filter { place in
            let statusMatches = filter == .all
                || (filter == .wantToGo && place.status == .wantToGo)
                || (filter == .visited && place.status == .visited)
            return statusMatches && (text.isEmpty
                || place.name.localizedStandardContains(text)
                || place.address.localizedStandardContains(text))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(DateTheme.muted)
                TextField(copy("Search name or address", "搜尋名稱或地址"), text: $query)
                    .font(.system(.body, design: .rounded))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).accessibilityIdentifier("live.library.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DateTheme.muted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel(copy("Clear search", "清除搜尋"))
                }
            }
            .padding(.leading, 16).padding(.trailing, 4).frame(minHeight: 52)
            .modifier(LiveLibraryCard())

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LiveLibraryFilter.allCases, id: \.self) { value in
                        Button { filter = value } label: {
                            Text(filterTitle(value)).font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .foregroundStyle(filter == value ? Color.white : DateTheme.ink)
                                .background(filter == value ? DateTheme.action : DateTheme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == value ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if isLoading {
                        ProgressView(copy("Loading saved places…", "載入收藏…"))
                            .font(.system(.subheadline, design: .rounded)).padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                    if matches.isEmpty && !isLoading {
                        emptyState
                    } else {
                        ForEach(matches) { place in
                            Button { onOpen(place) } label: {
                                LiveLibraryPlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("live.library.place.\(place.id.uuidString)")
                        }
                    }
                }.padding(.bottom, 8)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)

            Button(action: onCapture) {
                Label(copy("Add from a post or screenshot", "從貼文或截圖新增"), systemImage: "plus")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .foregroundStyle(Color.white).background(DateTheme.action, in: Capsule())
            }
            .buttonStyle(.plain).accessibilityIdentifier("live.library.add")
        }
        .foregroundStyle(DateTheme.ink)
        .accessibilityIdentifier("live.library")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: places.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(.title2, design: .rounded)).foregroundStyle(DateTheme.muted)
                .accessibilityHidden(true)
            Text(places.isEmpty
                 ? copy("Your collection starts here", "從第一個收藏開始")
                 : copy("No matching saved places", "沒有符合的收藏"))
                .font(.system(.headline, design: .rounded))
            Text(places.isEmpty
                 ? copy("Add a clue from a post or screenshot, then confirm the place.", "從貼文或截圖加入線索，再確認地點。")
                 : copy("Try another name, address or status.", "試試其他名稱、地址或收藏狀態。"))
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
            if !query.isEmpty || filter != .all {
                Button(copy("Clear filters", "清除篩選")) { query = ""; filter = .all }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44).foregroundStyle(DateTheme.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveLibraryCard())
    }

    private func filterTitle(_ value: LiveLibraryFilter) -> String {
        switch value {
        case .all: copy("All", "全部")
        case .wantToGo: copy("Want to go", "想去")
        case .visited: copy("Marked visited", "標記去過")
        }
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

@MainActor
struct LivePlanningPassportView: View {
    let places: [Place]
    let onOpenLibrary: () -> Void
    let onOpenAccount: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(places: [Place], onOpenLibrary: @escaping () -> Void, onOpenAccount: @escaping () -> Void) {
        self.places = places
        self.onOpenLibrary = onOpenLibrary
        self.onOpenAccount = onOpenAccount
    }

    private var visitedCount: Int { places.filter { $0.status == .visited }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.system(.largeTitle, design: .rounded)).foregroundStyle(DateTheme.blue)
                        .accessibilityHidden(true)
                    Text(copy("Your place archive", "你的地點檔案"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(copy("Saved places, including the ones still on your list.", "已收藏的地方，包含還沒出發的那些。"))
                        .font(.system(.body, design: .rounded)).foregroundStyle(DateTheme.muted)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 16) { counts }
                    } else {
                        HStack(alignment: .top, spacing: 16) { counts }
                    }
                    Text(copy("Visited counts reflect your saved status. Location is not verified here.",
                              "去過數量依收藏中的標記計算，未在此驗證到訪位置。"))
                        .font(.system(.caption, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveLibraryCard())

                archiveLink(title: copy("Open saved places", "查看收藏"),
                            detail: copy("Browse every place in your collection", "查看你存下的每個地方"),
                            icon: "tray", action: onOpenLibrary)
                    .accessibilityIdentifier("live.passport.library")
                archiveLink(title: copy("Account settings", "帳號設定"),
                            detail: copy("Profile, sign out and account controls", "個人資料、登出與帳號管理"),
                            icon: "person.crop.circle", action: onOpenAccount)
                    .accessibilityIdentifier("live.passport.account")
            }.padding(.vertical, 8)
        }
        .scrollIndicators(.hidden).foregroundStyle(DateTheme.ink)
        .accessibilityIdentifier("live.passport")
    }

    @ViewBuilder private var counts: some View {
        archiveCount(places.count, title: copy("Saved places", "已收藏"))
        archiveCount(visitedCount, title: copy("Marked visited", "標記去過"))
    }

    private func archiveCount(_ count: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func archiveLink(title: String, detail: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(.title3, design: .rounded))
                    .foregroundStyle(DateTheme.blue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.headline, design: .rounded))
                    Text(detail).font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DateTheme.muted).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16).modifier(LiveLibraryCard()).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

private enum LiveLibraryFilter: CaseIterable, Hashable { case all, wantToGo, visited }

@MainActor
private struct LiveLibraryPlaceRow: View {
    let place: Place
    @Environment(\.appLanguageSettings) private var language

    private var photoURL: URL? {
        place.businessPhotoURLStrings.lazy.compactMap(URL.init(string:)).compactMap { (url: URL) -> URL? in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return GooglePlacesPhotoSourceMarkMetrics.mapSafePhotoURL(url)
        }.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let url = photoURL {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { fallback }
                    }
                } else { fallback }
            }
            .frame(width: 58, height: 58).background(DateTheme.soft)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(place.name.isEmpty ? language.localized(english: "Untitled saved place", traditionalChinese: "未命名收藏") : place.name)
                    .font(.system(.headline, design: .rounded)).multilineTextAlignment(.leading)
                if !place.address.isEmpty {
                    Text(place.address).font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(DateTheme.muted).multilineTextAlignment(.leading)
                }
                Text(place.status == .visited
                     ? language.localized(english: "Saved · marked visited", traditionalChinese: "已收藏 · 標記去過")
                     : language.localized(english: "Saved · want to go", traditionalChinese: "已收藏 · 想去"))
                    .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(DateTheme.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold))
                .foregroundStyle(DateTheme.muted).padding(.top, 4).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(16).modifier(LiveLibraryCard()).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fallback: some View {
        Image(systemName: place.category.iconName)
            .font(.system(.title2, design: .rounded, weight: .medium))
            .foregroundStyle(DateTheme.blue).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveLibraryCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DateTheme.ink.opacity(0.06)))
    }
}
#endif
