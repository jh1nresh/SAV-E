import SwiftUI

/// Production Home for the 2026-10-14 tile-town lock.
/// Resting chrome: Savvy + map peek + clues bar + recent stamps.
/// Nearby / Saved / Friends chips stay off this surface (Map-only).
/// Quiet collection search remains so the private library is still findable.
struct SaveTileTownHomeView: View {
    @Environment(\.atlasPresentation) private var presentation
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var search = SaveHomeSearch()
    @State private var showsMoreActions = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)

            library
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveAtlasPalette.canvas)
        .overlay(alignment: .topTrailing) {
            if showsMoreActions {
                moreActionsSheet
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }
        }
    }

    /// Keep this identifier on an inner sibling of the header, not on the
    /// sole child of `home.root`. Nested `.contain` on that single child
    /// dropped `home.savedPlaces` and the More-menu actions from XCUITest.
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 10)

            if search.isActive {
                searchResults
            } else if showsEmptyHome {
                emptyHome
            } else {
                restingHome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.savedPlaces")
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: presentation.onOpenPassport) {
                Text("Savvy")
                    .font(SaveAtlasType.strong(32, relativeTo: .title))
                    .foregroundStyle(SaveAtlasPalette.forest)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Open Savvy Passport", "開啟 Savvy 護照"))
            .accessibilityIdentifier("root.passport")

            Spacer(minLength: 8)

            Button { showsMoreActions.toggle() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(width: 44, height: 44)
                    .background(SaveAtlasPalette.paper, in: Capsule())
                    .overlay {
                        Capsule().stroke(SaveAtlasPalette.line.opacity(0.34), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("More Home actions", "更多首頁操作"))
            .accessibilityIdentifier("home.more")
        }
        .frame(minHeight: 48)
    }

    /// In-window sheet so XCUITest can tap real 44pt buttons. SwiftUI Menu
    /// and confirmationDialog never put `home.trips` in the production tree.
    private var moreActionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            moreActionRow(
                title: localized("Trips", "行程"),
                systemImage: "point.3.connected.trianglepath.dotted",
                identifier: "home.trips"
            ) {
                showsMoreActions = false
                presentation.onOpenTrips()
            }
            moreActionRow(
                title: localized("Manage saved places", "管理已存地點"),
                systemImage: "slider.horizontal.3",
                identifier: "home.saves"
            ) {
                showsMoreActions = false
                presentation.onOpenSaves()
            }
        }
        .frame(width: 248)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.more.sheet")
    }

    private func moreActionRow(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SaveAtlasType.strong(16))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
    }

    private var showsEmptyHome: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-empty-home") {
            return true
        }
#endif
        return presentation.savedPlaces.isEmpty
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(SaveAtlasPalette.muted)
            TextField(localized("Search saved places", "搜尋已存地點"), text: $search.draft)
                .font(SaveAtlasType.body(17))
                .foregroundStyle(SaveAtlasPalette.ink)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
                .accessibilityIdentifier("home.search")
            if search.isActive {
                Button { search.clear(); isSearchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .foregroundStyle(SaveAtlasPalette.muted)
                .accessibilityLabel(localized("Clear search", "清除搜尋"))
                .accessibilityIdentifier("home.search.clear")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
        }
    }

    private var emptyHome: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                cluesBar
                reviewQueuePreview
                VStack(spacing: 10) {
                    Text(localized("No saved places yet", "還沒有已存地點"))
                        .font(SaveAtlasType.strong(18))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(localized(
                        "Paste a link. Confirm the place before adding it to your map.",
                        "貼上連結，確認地點後再加入你的地圖。"
                    ))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    Button(action: presentation.onCapture) {
                        Label(localized("Paste your first link", "貼上第一個連結"), systemImage: "link")
                            .font(SaveAtlasType.strong(16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("home.empty.capture")
                    .accessibilityAddTraits(.isButton)
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("home.savedPlaces.empty")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
    }

    private var restingHome: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(savedCountText)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .accessibilityIdentifier("home.search.count")
                peek
                cluesBar
                reviewQueuePreview
                recentStamps
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
    }

    private var peek: some View {
        ZStack(alignment: .bottomLeading) {
            SaveTileTownCanvas(
                pins: peekPins,
                onSelect: { id in presentation.onOpenPlace(id.uuidString) }
            )
            .frame(height: 220)
            .accessibilityIdentifier("home.tileTown")

            if let featured {
                Button { presentation.onOpenPlace(featured.id) } label: {
                    SaveTileTownPeekCard(
                        title: featured.name,
                        subtitle: featured.area,
                        photoURL: featured.photoURL ?? featured.photoURLs.first,
                        accessibilityNameID: "home.featuredName"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home.place.\(featured.id)")
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
        }
    }

    private var cluesBar: some View {
        HStack(spacing: 12) {
            Text(cluesHeadline)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: presentation.onReviewAll) {
                Text(localized("Review clues", "確認線索"))
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(SaveAtlasPalette.coral, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.review")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SaveAtlasPalette.kraft.opacity(0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.kraft.opacity(0.7), lineWidth: 1)
        }
        .accessibilityIdentifier("home.cluesBar")
    }

    @ViewBuilder
    private var reviewQueuePreview: some View {
        if let item = presentation.reviewItems.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localized("Waiting for review", "等待你確認"))
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Spacer()
                    Button(action: presentation.onReviewAll) {
                        Text(localized("View all", "查看全部"))
                            .font(SaveAtlasType.display(12))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.reviewAll")
                }
                Button { presentation.onOpenReview(item.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(width: 36, height: 36)
                            .background(
                                (item.kind == .sourceOnly ? SaveAtlasPalette.coral : SaveAtlasPalette.sky)
                                    .opacity(0.28),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.eyebrow)
                                .font(SaveAtlasType.strong(11))
                                .foregroundStyle(item.kind == .sourceOnly ? SaveAtlasPalette.coral : SaveAtlasPalette.forest)
                            Text(item.name)
                                .font(SaveAtlasType.strong(16))
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.actionTitle)
                            .font(SaveAtlasType.display(13))
                            .foregroundStyle(SaveAtlasPalette.ink)
                    }
                    .padding(12)
                    .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.reviewCandidate.\(item.id)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.reviewQueue")
        }
    }

    private var recentStamps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Recent stamps", "最近的地圖章"))
                .font(SaveAtlasType.strong(16))
                .foregroundStyle(SaveAtlasPalette.forest)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(presentation.savedPlaces.filter { $0.id != featured?.id }.prefix(6)) { place in
                        Button { presentation.onOpenPlace(place.id) } label: {
                            SaveKraftStamp(
                                title: place.name,
                                face: .photo(place.photoURL ?? place.photoURLs.first),
                                size: .recent,
                                accessibilityIdentifier: "home.recent.\(place.id)"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .accessibilityIdentifier("home.recentSaves")
    }

    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                Text(searchCountText)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home.search.count")
                if matchingPlaces.isEmpty {
                    Text(localized("No saved places match", "沒有符合的已存地點"))
                        .font(SaveAtlasType.body(16))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .padding(24)
                        .accessibilityIdentifier("home.search.empty")
                }
                ForEach(matchingPlaces) { place in
                    Button { presentation.onOpenPlace(place.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(SaveAtlasType.strong(18))
                                .foregroundStyle(SaveAtlasPalette.forest)
                            Text(place.area)
                                .font(SaveAtlasType.body(14))
                                .foregroundStyle(SaveAtlasPalette.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(12)
                        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.search.result.\(place.id)")
                }
            }
            .padding(16)
            .padding(.bottom, 96)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var featured: AtlasPlacePresentation? {
        presentation.savedPlaces.first
    }

    private var peekPins: [SaveTileTownPin] {
        presentation.savedPlaces.prefix(8).compactMap { place in
            guard let id = UUID(uuidString: place.id) else { return nil }
            return SaveTileTownPin(
                id: id,
                name: place.name,
                isSelected: place.id == featured?.id
            )
        }
    }

    private var matchingPlaces: [AtlasPlacePresentation] {
        presentation.savedPlaces.filter(search.matches)
    }

    private var cluesHeadline: String {
        let count = presentation.reviewCount
        if count == 0 {
            return localized("No clues waiting", "目前沒有待確認線索")
        }
        return languageSettings.language == .traditionalChinese
            ? "\(count) 個線索等待確認"
            : "\(count) clues waiting"
    }

    private var savedCountText: String {
        let count = presentation.savedPlaces.count
        switch languageSettings.language {
        case .english:
            return count == 1 ? "1 confirmed place" : "\(count) confirmed places"
        case .traditionalChinese:
            return "\(count) 個已確認地點"
        }
    }

    private var searchCountText: String {
        let count = matchingPlaces.count
        switch languageSettings.language {
        case .english:
            return count == 1 ? "1 place found" : "\(count) places found"
        case .traditionalChinese:
            return "找到 \(count) 個地點"
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}
