import SwiftUI

/// Home searches only this account's confirmed collection. Review stays a separate action.
struct SaveHomeMemoryView: View {
    let places: [Place]
    let reviewCounts: SaveHomeReviewCounts
    let hasLocation: Bool
    let onCapture: () -> Void
    let onOpenPlace: (Place) -> Void
    let onOpenSaves: () -> Void
    let onOpenTrips: () -> Void
    let onOpenPassport: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = SaveHomeSearch()
    @State private var keyboardTop: CGFloat?
    @FocusState private var isEditing: Bool

    private var usesStaticPresentation: Bool {
        if reduceMotion || voiceOver || typeSize.isAccessibilitySize { return true }
#if DEBUG
        if ReviewDemo.isOfflineUITestMode && ProcessInfo.processInfo.arguments.contains("--uitest-home-reduce-motion") { return true }
#endif
        return false
    }

    private var matches: [Place] { search.matchingPlaces(in: places) }

    var body: some View {
        GeometryReader { geometry in
            let global = geometry.frame(in: .global)
            let scale = max(global.width / max(geometry.size.width, 1), 0.1)
            let visibleHeight = keyboardTop.map {
                min(geometry.size.height, max(280, ($0 - global.minY) / scale))
            } ?? geometry.size.height
            VStack(alignment: .leading, spacing: 12) {
                header
                if !places.isEmpty { searchField }
                if !search.filters.isEmpty { filterChips }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if reviewCounts.total > 0 { reviewButton }
                        if places.isEmpty {
                            emptyCollection
                        } else {
                            if !usesStaticPresentation {
                                SaveHomeMemoryPile(
                                    places: places,
                                    liftedIDs: search.isActive ? Array(matches.prefix(3).map(\.id)) : [],
                                    isSearching: search.isActive,
                                    onOpenPlace: { place in
                                        isEditing = false
                                        onOpenPlace(place)
                                    }
                                )
                                // Keep the physics coordinate space fixed while revealing
                                // room above the pile for search previews.
                                .frame(height: 250)
                                .frame(height: search.isActive ? 250 : 140, alignment: .bottom)
                                .clipped()
                                .animation(.easeInOut(duration: 0.48), value: search.isActive)
                                .accessibilityIdentifier("home.memoryPile")
                            }
                            resultHeading
                            if matches.isEmpty {
                                emptyResults
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(matches) { place in
                                        resultCard(place, isFirst: place.id == matches.first?.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("home.savedPlaces")
            }
            .padding(.horizontal, 22)
            .padding(.top, 58)
            .padding(.bottom, keyboardTop == nil ? 100 : 12)
            .frame(width: geometry.size.width, height: visibleHeight, alignment: .top)
            .background(SaveAtlasPalette.canvas)
        }
        .background(SaveAtlasPalette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardTop = frame.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardTop = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            SaveAtlasBrandHeader(onOpenPassport: onOpenPassport) {
                Menu {
                    Button(action: onOpenSaves) { Label(localized("Manage saved places", "管理已存地點"), systemImage: "tray.full") }
                        .accessibilityIdentifier("home.saves")
                    Button(action: onOpenTrips) { Label(localized("Trips", "行程"), systemImage: "point.3.connected.trianglepath.dotted") }
                        .accessibilityIdentifier("home.trips")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(SaveAtlasPalette.paper, in: Circle())
                }
                .accessibilityLabel(localized("More Home actions", "更多首頁操作"))
                .accessibilityIdentifier("home.more")
            }
            Text(localized(places.count == 1 ? "1 confirmed place" : "\(places.count) confirmed places", "\(places.count) 個已確認地點"))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(SaveAtlasPalette.forest)
            TextField(localized("Find a memory…", "想找回哪個地方？"), text: $search.draft)
                .font(SaveAtlasType.body(16))
                .foregroundStyle(SaveAtlasPalette.ink)
                .focused($isEditing)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(commitFilter)
                .accessibilityIdentifier("home.search")
            if search.isActive {
                Button {
                    search.clear()
                    isEditing = false
                } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localized("Clear search", "清除搜尋"))
                .accessibilityIdentifier("home.search.clear")
            }
            Button(action: commitFilter) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(search.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(localized("Keep this filter", "保留這個條件"))
            .accessibilityIdentifier("home.search.commit")
        }
        .foregroundStyle(SaveAtlasPalette.forest)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(SaveAtlasPalette.line.opacity(0.4)) }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(search.filters, id: \.self) { filter in
                    Button {
                        search.removeFilter(filter)
                    } label: {
                        HStack(spacing: 8) {
                            Text(filterLabel(filter))
                            Image(systemName: "xmark").font(.caption.weight(.bold))
                        }
                        .font(SaveAtlasType.body(14))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(SaveAtlasPalette.kraft.opacity(0.45), in: Capsule())
                    }
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .accessibilityLabel(localized("Remove filter: \(filterLabel(filter))", "移除條件：\(filterLabel(filter))"))
                    .accessibilityIdentifier("home.filter.\(filter)")
                }
            }
        }
    }

    private var resultHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(search.isActive
                 ? localized(matches.count == 1 ? "1 place found" : "\(matches.count) places found", "找到 \(matches.count) 個地點")
                 : localized(hasLocation ? "Saved nearby" : "Recently saved", hasLocation ? "附近的收藏" : "最近收藏"))
                .font(SaveAtlasType.strong(18))
                .foregroundStyle(SaveAtlasPalette.forest)
                .accessibilityIdentifier("home.search.count")
            Text(search.isActive
                 ? localized("Add a city to narrow it down. Remove a filter to explore again.", "再加上城市縮小範圍，移除條件就能重新探索。")
                 : localized("Try “cafe”, then add a city. Watch your memories rise.", "試試「咖啡店」，再加上城市，讓收藏浮上來。"))
                .font(SaveAtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultCard(_ place: Place, isFirst: Bool) -> some View {
        Button { isEditing = false; onOpenPlace(place) } label: {
            HStack(alignment: .top, spacing: 14) {
                SaveHomeMemoryPhoto(place: place)
                    .frame(width: 70, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.name)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(isFirst ? "home.featuredName" : "home.name.\(place.id)")
                    Text(place.address)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(localized(place.status == .visited ? "Visited Map Stamp" : "Map Stamp", place.status == .visited ? "已造訪的地圖章" : "地圖章"), systemImage: "checkmark.seal.fill")
                        .font(SaveAtlasType.body(11))
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(SaveAtlasPalette.line.opacity(0.3)) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.place.\(place.id.uuidString)")
    }

    private var emptyCollection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 44)).foregroundStyle(SaveAtlasPalette.forest)
            Text(localized("A little collection of everywhere.", "把想去的地方，收進這裡。"))
                .font(SaveAtlasType.strong(26, relativeTo: .title2))
            Text(localized("Share a link. Confirm the place. Your first Map Stamp starts the collection.", "分享連結、確認地點，讓第一枚地圖章開始你的收藏。"))
                .font(SaveAtlasType.body(16))
            Button(action: onCapture) {
                Text(localized("Save your first place", "收藏第一個地點"))
                    .font(SaveAtlasType.strong(16))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("home.empty.capture")
        }
        .foregroundStyle(SaveAtlasPalette.ink)
        .padding(.vertical, 28)
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("No saved places match these filters.", "目前沒有符合這些條件的收藏。"))
                .font(SaveAtlasType.body(16))
            Button(localized("Clear filters", "清除條件")) { search.clear() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("home.search.reset")
        }
        .foregroundStyle(SaveAtlasPalette.forest)
        .accessibilityIdentifier("home.search.empty")
    }

    private var reviewButton: some View {
        Button(action: onOpenSaves) {
            HStack {
                Image(systemName: "questionmark.circle")
                VStack(alignment: .leading, spacing: 4) {
                    if reviewCounts.candidates > 0 {
                        Text(localized(
                            reviewCounts.candidates == 1 ? "1 Review Candidate" : "\(reviewCounts.candidates) Review Candidates",
                            "\(reviewCounts.candidates) 個待確認地點"
                        ))
                        .accessibilityIdentifier("home.review.candidates")
                    }
                    if reviewCounts.sources > 0 {
                        Text(localized(
                            reviewCounts.sources == 1 ? "1 Source Clue" : "\(reviewCounts.sources) Source Clues",
                            "\(reviewCounts.sources) 個來源線索"
                        ))
                        .accessibilityIdentifier("home.review.sources")
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(SaveAtlasType.body(14))
            .padding(14)
            .frame(minHeight: 48)
            .background(SaveAtlasPalette.sky.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        }
        .foregroundStyle(SaveAtlasPalette.ink)
        .accessibilityIdentifier("home.review")
    }

    private func filterLabel(_ value: String) -> String {
        if let category = PlaceCategory(rawValue: value) {
            return category == .cafe ? localized("Cafes", "咖啡店") : category.displayName(language: language.language)
        }
        if let english = SaveHomeSearch.cityLabel(for: value, traditionalChinese: false),
           let chinese = SaveHomeSearch.cityLabel(for: value, traditionalChinese: true) {
            return localized(english, chinese)
        }
        return value
    }

    private func commitFilter() {
        search.commitDraft()
        isEditing = false
        SaveHaptics.select()
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

/// Same distinction shown by the existing Saves queue.
struct SaveHomeReviewCounts: Equatable {
    let candidates: Int
    let sources: Int
    var total: Int { candidates + sources }

    init(_ items: [PlaceReviewCandidate]) {
        sources = items.filter { $0.status == "source_only" || !$0.hasReliableCoordinates }.count
        candidates = items.count - sources
    }
}

struct SaveHomeMemoryPhoto: View {
    let place: Place
    var loadsPhoto = true

    var body: some View {
        GeometryReader { geometry in
            CachedAsyncImage(url: loadsPhoto ? place.businessPhotoURLStrings.first.flatMap(URL.init(string:)) : nil) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        SaveAtlasPalette.mint
                        Image(systemName: place.category.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(SaveAtlasPalette.forest)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}
