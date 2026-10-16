import SwiftUI

/// Production Home for the 2026-10-14 tile-town lock.
/// Resting chrome: Savvy + visible quiet pixel Trips/Saves/More + map peek +
/// clues bar + recent stamps. Waiting for review lives under More.
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
                // ReferenceViewport ignores the safe area. Friends/Passport
                // already sit on this 48pt band; 8pt left Saves/Trips under
                // the status bar so XCUITest saw them and coordinate taps missed.
                .padding(.top, AtlasMetrics.statusBarHeight)
                .zIndex(2)

            // Keep More in document flow. A full-view overlay fills the
            // ReferenceViewport and swallows header `home.saves` / `home.trips`
            // taps after XCUITest opens `home.more`.
            if showsMoreActions {
                moreActionsSheet
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .zIndex(2)
            }

            library
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveAtlasPalette.canvas)
    }

    /// Identifier lives on a sibling of the header, not the sole child of
    /// `home.root`. `.contain` is required so `home.search` stays a text field
    /// instead of combining into this container.
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
                SavePixelDisplayText(text: "Savvy", pointSize: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Open Savvy Passport", "開啟 Savvy 護照"))
            .accessibilityIdentifier("root.passport")

            Spacer(minLength: 8)

            headerIconButton(
                kind: .trips,
                label: localized("Trips", "行程"),
                identifier: "home.trips",
                action: presentation.onOpenTrips
            )
            headerIconButton(
                kind: .saves,
                label: localized("Manage saved places", "管理已存地點"),
                identifier: "home.saves",
                action: presentation.onOpenSaves
            )
            headerIconButton(
                kind: .more,
                label: localized("More Home actions", "更多首頁操作"),
                identifier: "home.more",
                action: { showsMoreActions.toggle() }
            )
        }
        .frame(minHeight: 48)
    }

    private func headerIconButton(
        kind: SavePixelChromeIconKind,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SavePixelChromeIcon(kind: kind, pointSize: 16)
                .frame(width: 44, height: 44)
                .background(SaveAtlasPalette.paper)
                .overlay {
                    Rectangle()
                        .stroke(SaveAtlasPalette.forest.opacity(0.28), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
    }

    /// In-window sheet so XCUITest can tap real 44pt buttons. SwiftUI Menu
    /// and confirmationDialog never put `home.trips` in the production tree.
    private var moreActionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            moreActionRow(
                title: localized("Trips", "行程"),
                systemImage: "point.3.connected.trianglepath.dotted",
                identifier: "home.more.trips"
            ) {
                showsMoreActions = false
                presentation.onOpenTrips()
            }
            moreActionRow(
                title: localized("Manage saved places", "管理已存地點"),
                systemImage: "slider.horizontal.3",
                identifier: "home.more.saves"
            ) {
                showsMoreActions = false
                presentation.onOpenSaves()
            }
            reviewQueuePreview
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 248)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 12, y: 6)
        .fixedSize(horizontal: false, vertical: true)
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SaveAtlasPalette.muted)
                .accessibilityHidden(true)
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
                emptyCaptureButton
                cluesBar
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
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("home.savedPlaces.empty")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
        }
    }

    private var emptyCaptureButton: some View {
        Button(action: presentation.onCapture) {
            Text(localized("Paste your first link", "貼上第一個連結"))
                .font(SaveAtlasType.strong(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Paste your first link", "貼上第一個連結"))
        .accessibilityIdentifier("home.empty.capture")
        .accessibilityAddTraits(.isButton)
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
                recentStamps
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
        }
    }

    private var peek: some View {
        ZStack(alignment: .bottomLeading) {
            SaveTileTownCanvas(
                pins: peekPins,
                onSelect: { id in presentation.onOpenPlace(id.uuidString) }
            )
            .frame(height: 350)
            .allowsHitTesting(false)
            .accessibilityIdentifier("home.tileTown")

            if let featured {
                Button { presentation.onOpenPlace(featured.id) } label: {
                    SaveTileTownPeekCard(
                        title: featured.name,
                        subtitle: localized("Map Stamp", "地圖章"),
                        photoURL: featured.photoURL ?? featured.photoURLs.first,
                        accessibilityNameID: "home.featuredName"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 290, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home.place.\(featured.id)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .background(SaveAtlasPalette.coral, in: SaveKraftTicketShape())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.review")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SaveAtlasPalette.kraft.opacity(0.38), in: SaveKraftTicketShape())
        .overlay {
            SaveKraftTicketShape()
                .stroke(SaveAtlasPalette.line.opacity(0.65), lineWidth: 1)
                .allowsHitTesting(false)
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
                .font(SaveAtlasType.strong(18))
                .foregroundStyle(SaveAtlasPalette.forest)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
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
            .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
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
