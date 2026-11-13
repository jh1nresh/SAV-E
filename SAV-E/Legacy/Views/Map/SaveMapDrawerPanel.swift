import SwiftUI

/// One resizable drawer surface for the Map tab.
///
/// Search rests above the tab bar. All three stops resize the same paper
/// surface for search results and place details. Expanding never
/// presents a second layer. The embedded drawer intentionally doesn't use
/// sheet presentation modifiers because those can abort SwiftUI's presentation
/// coordinator when attached to an in-tree view.
struct SaveMapDrawerPanel<ExpandedContent: View>: View {
    @Binding var isExpanded: Bool
    @Binding var detent: PresentationDetent
    let mapStampCount: Int
    let showsCollapsedShelf: Bool
    /// Shelf tap focuses the editor. Drag and resize-handle taps do not.
    let onExpand: (_ focusesSearch: Bool) -> Void
    let onCollapse: () -> Void
    let onOpenPassport: () -> Void
    @ViewBuilder let expandedContent: () -> ExpandedContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tabBarClearance: CGFloat = 80
    private let collapsedHeight: CGFloat = 64
    @State private var collapsedDragConsumedTap = false
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            // Keep one view and coordinate space alive at every stage.
            // The root geometry already excludes the home indicator.
            let bottomClearance = max(0, tabBarClearance - proxy.safeAreaInsets.bottom)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if isExpanded || showsCollapsedShelf {
                    VStack(spacing: 0) {
                        resizeHandle
                        if isExpanded {
                            expandedContent()
                        } else {
                            SaveAtlasMapCommandShelf(
                                mapStampCount: mapStampCount,
                                onOpenAssistant: {
                                    guard !collapsedDragConsumedTap else { return }
                                    onExpand(true)
                                },
                                onOpenPassport: onOpenPassport
                            )
                            .padding(.horizontal, 12)
                            .simultaneousGesture(resizeGesture(stage: .collapsed))
                            Spacer(minLength: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .frame(height: panelHeight(totalHeight: proxy.size.height - bottomClearance), alignment: .top)
                    .background { drawerBackground }
                    // Keep the live editor unmasked during keyboard changes.
                    .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(drawerLine.opacity(0.3), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: drawerInk.opacity(0.10), radius: 12, y: 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Map search drawer")
                    .accessibilityValue(stage.accessibilityValue)
                    .accessibilityIdentifier(stage.accessibilityIdentifier)
                    .padding(.horizontal, stage == .collapsed ? proxy.size.width * 0.07 : 8)
                }
            }
            .padding(.bottom, bottomClearance)
        }
        .animation(reduceMotion ? nil : SaveTheme.Motion.standardSpring, value: isExpanded)
        .animation(reduceMotion ? nil : SaveTheme.Motion.standardSpring, value: detent)
    }

    @ViewBuilder private var drawerBackground: some View {
#if SAVVY_CITY_MVP
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(CityMVPFormStyle.canvas)
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(CityMVPFormStyle.card, lineWidth: 1))
#else
        if stage == .collapsed {
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(SaveAtlasPalette.paper)
        }
#endif
    }

    private var drawerLine: Color {
#if SAVVY_CITY_MVP
        CityMVPFormStyle.muted
#else
        SaveAtlasPalette.line
#endif
    }
    private var drawerInk: Color {
#if SAVVY_CITY_MVP
        CityMVPFormStyle.ink
#else
        SaveAtlasPalette.ink
#endif
    }

    private var stage: MapDrawerStage { isExpanded ? expandedStage : .collapsed }

    private var resizeHandle: some View {
        Capsule()
            .fill(drawerLine.opacity(0.48))
            .frame(width: 36, height: 4)
            .frame(height: stage == .collapsed ? 12 : 44)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(resizeGesture(stage: stage))
            .onTapGesture {
                if stage == .collapsed { onExpand(false) }
                else { cycleExpandedStage() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resize map search drawer")
            .accessibilityValue(stage.accessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: moveUp(from: stage)
                case .decrement: moveDown(from: stage)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("map.drawerPanel.handle")
    }

    /// One surface tracks the finger at every stop, including collapsed.
    /// The available height already excludes the keyboard and tab controls.
    private func panelHeight(totalHeight: CGFloat) -> CGFloat {
        let largeHeight = max(
            collapsedHeight,
            totalHeight - SaveTileTownProductLock.mapChromeHeight
        )
        let baseHeight: CGFloat
        switch stage {
        case .collapsed: baseHeight = collapsedHeight
        case .medium: baseHeight = min(largeHeight, max(240, totalHeight * 0.39))
        case .large: baseHeight = largeHeight
        }
        return min(largeHeight, max(collapsedHeight, baseHeight - dragTranslation))
    }

    private var expandedStage: MapDrawerStage {
        detent == .large ? .large : .medium
    }

    private func resizeGesture(stage: MapDrawerStage) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragTranslation) { value, state, transaction in
                transaction.animation = nil
                state = value.translation.height
            }
            .onChanged { value in
                guard stage == .collapsed,
                      abs(value.translation.height) >= 8
                else { return }
                collapsedDragConsumedTap = true
            }
            .onEnded { value in
                if stage == .collapsed {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        collapsedDragConsumedTap = false
                    }
                }

                let projectedTravel = value.predictedEndTranslation.height
                let actualTravel = value.translation.height
                let travel = abs(projectedTravel) > abs(actualTravel)
                    ? projectedTravel
                    : actualTravel

                guard abs(travel) >= 44 else { return }
                if travel < 0 {
                    moveUp(from: stage)
                } else {
                    moveDown(from: stage)
                }
            }
    }

    private func moveUp(from stage: MapDrawerStage) {
        switch stage {
        case .collapsed:
            onExpand(false)
        case .medium:
            withAnimation(reduceMotion ? nil : SaveTheme.Motion.standardSpring) {
                detent = .large
            }
        case .large:
            break
        }
    }

    private func moveDown(from stage: MapDrawerStage) {
        switch stage {
        case .collapsed:
            break
        case .medium:
            collapse()
        case .large:
            withAnimation(reduceMotion ? nil : SaveTheme.Motion.standardSpring) {
                detent = .medium
            }
        }
    }

    private func cycleExpandedStage() {
        if expandedStage == .large {
            moveDown(from: .large)
        } else {
            moveUp(from: .medium)
        }
    }

    private func collapse() {
        onCollapse()
    }
}

private enum MapDrawerStage {
    case collapsed
    case medium
    case large

    var accessibilityIdentifier: String {
        switch self {
        case .collapsed: "map.drawerPanel.collapsed"
        case .medium: "map.drawerPanel.medium"
        case .large: "map.drawerPanel.large"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .collapsed: "Collapsed"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// Search belongs to the map; planning conversations have their own surface.
struct SaveMapSearchContent: View {
    @ObservedObject var mapViewModel: MapViewModel
    let initialQuery: String
    let focusesSearch: Bool
    let preservesExactSearchClue: Bool
    let onClose: () -> Void
    let onOpenPlace: (Place) -> Void
    let onOpenCandidate: (SaveMapCandidate) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var searchRequestID = UUID()
    @FocusState private var isFocused: Bool

    private var savedResults: [Place] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return mapViewModel.filteredPlaces.filter {
            text.isEmpty
                || SaveSearchTextMatch.matchesSavedPlace($0.name, query: text)
                || SaveSearchTextMatch.matchesSavedPlace($0.address, query: text)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
#if SAVVY_CITY_MVP
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Where to?", "想去哪裡？")).font(.title.bold())
                    Text(localized("Find a place. Make it yours.", "找到地方，再決定是否收藏。"))
                        .font(.subheadline).foregroundStyle(CityMVPFormStyle.muted)
                }
                Spacer()
            }.foregroundStyle(CityMVPFormStyle.ink).padding(.horizontal, 24).padding(.bottom, 18)
#endif
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField(localized("Search places", "搜尋地點"), text: $query)
                    .font(searchFont(17))
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .accessibilityIdentifier("map.search.input")
                Button(action: submit) {
                    Image(systemName: "arrow.right").frame(width: 44, height: 44)
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(localized("Search map", "搜尋地圖"))
                .accessibilityIdentifier("map.search.submit")
                Button {
                    isFocused = false
                    onClose()
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localized("Close search", "關閉搜尋"))
                .accessibilityIdentifier("map.search.close")
            }
            .foregroundStyle(searchInk)
            .padding(.leading, 12)
            .background(searchSurface, in: Capsule())
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
#if SAVVY_CITY_MVP
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && submittedQuery.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(localized("Filter your saved places", "篩選你的收藏")).font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                categoryTile(.food, emoji: "🍜")
                                categoryTile(.cafe, emoji: "☕️")
                                categoryTile(.bar, emoji: "🍸")
                                categoryTile(.attraction, emoji: "🏛️")
                            }
                        }.padding(.bottom, 16)
                    }
#endif
                    HStack {
                        Text(localized("Your Map Stamps", "你的地圖章"))
                            .font(searchFont(15, strong: true))
                        Spacer()
                        Menu {
                            ForEach(SaveMapDrawerIntent.allCases) { intent in
                                Button {
                                    mapViewModel.toggleIntentFilter(intent)
                                } label: {
                                    Label(intent.chipLabel(language: languageSettings.language), systemImage: mapViewModel.selectedIntentFilters.contains(intent) ? "checkmark" : intent.systemImage)
                                }
                            }
                            Divider()
                            ForEach(PlaceCategory.allCases, id: \.self) { category in
                                Button {
                                    mapViewModel.toggleCategory(category)
                                } label: {
                                    Label(category.displayName(language: languageSettings.language), systemImage: mapViewModel.selectedCategories.contains(category) ? "checkmark" : "circle")
                                }
                            }
                        } label: {
                            Label(localized("Filters", "篩選"), systemImage: "line.3.horizontal.decrease")
                                .font(searchFont(14))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("map.search.filters")
                    }
                    ForEach(savedResults) { place in
                        Button {
                            isFocused = false
                            onOpenPlace(place)
                        } label: {
                            resultRow(place.name, detail: place.address, state: localized("Saved", "已存"), tint: searchSaved)
                        }
                        .accessibilityIdentifier("map.search.saved.\(place.id.uuidString)")
                    }
                    if savedResults.isEmpty {
                        Text(localized("No saved places match.", "沒有符合的已存地點。"))
                            .font(searchFont(14))
                            .foregroundStyle(searchMuted)
                    }
                    if !submittedQuery.isEmpty && submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text(localized("Map results · Not saved", "地圖結果 · 尚未儲存"))
                            .font(searchFont(15, strong: true))
                            .padding(.top, 12)
                        if mapViewModel.isLoadingMapCandidates {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        } else if mapViewModel.mapCandidates.isEmpty {
                            Text(
                                mapViewModel.mapSearchNeedsLocationHint
                                    ? localized(
                                        "Locate yourself or add a city to search this area.",
                                        "請先定位或加上城市，才能搜尋這個區域。"
                                    )
                                    : localized("No map results. Try a place name and city.", "沒有地圖結果，試試地點名稱加城市。")
                            )
                                .font(searchFont(14))
                                .foregroundStyle(searchMuted)
                        } else {
                            ForEach(mapViewModel.mapCandidates) { candidate in
                                Button {
                                    isFocused = false
                                    onOpenCandidate(candidate)
                                } label: {
                                    resultRow(candidate.title, detail: candidate.subtitle, state: localized("Not saved", "未儲存"), tint: searchCandidate)
                                }
                                .accessibilityIdentifier("map.search.candidate.\(candidate.id)")
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(searchInk)
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            // Clip only the scrolling rows, leaving the live editor outside
            // the mask. The enclosing panel supplies the rounded paper.
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                style: .continuous
            ))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.search.root")
        .onAppear {
            query = initialQuery
            submittedQuery = initialQuery
            isFocused = focusesSearch
        }
        .task(id: searchRequestID) {
            guard !submittedQuery.isEmpty else { return }
            await mapViewModel.searchMapPlaces(
                submittedQuery,
                preservesExactSearchClue: preservesExactSearchClue
            )
        }
    }

    private func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFocused = false
        submittedQuery = text
        searchRequestID = UUID()
    }

    private func resultRow(_ title: String, detail: String, state: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin")
                .frame(width: 36, height: 36)
                .background(tint, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(searchFont(17, strong: true))
                Text(detail).font(searchFont(13)).foregroundStyle(searchMuted)
                Text(state).font(searchFont(11)).foregroundStyle(searchMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, 8)
#if SAVVY_CITY_MVP
        .padding(.horizontal, 14)
        .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 22))
#endif
        .contentShape(Rectangle())
    }

    private func searchFont(_ size: CGFloat, strong: Bool = false) -> Font {
#if SAVVY_CITY_MVP
        let style: Font.TextStyle = size >= 17 ? .body : size >= 15 ? .subheadline : size >= 13 ? .footnote : .caption2
        return Font.system(style).weight(strong ? .semibold : .regular)
#else
        return strong ? SaveAtlasType.strong(size) : SaveAtlasType.body(size)
#endif
    }
#if SAVVY_CITY_MVP
    private var searchInk: Color { CityMVPFormStyle.ink }
    private var searchSurface: Color { CityMVPFormStyle.card }
    private var searchMuted: Color { CityMVPFormStyle.muted }
    private var searchSaved: Color { CityMVPFormStyle.canvas }
    private var searchCandidate: Color { CityMVPFormStyle.canvas }

    private func categoryTile(_ category: PlaceCategory, emoji: String) -> some View {
        let selected = mapViewModel.selectedCategories.contains(category)
        return Button { mapViewModel.toggleCategory(category) } label: {
            HStack(spacing: 12) {
                Text(emoji).font(.title2).accessibilityHidden(true)
                Text(category.displayName(language: languageSettings.language)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
            }.foregroundStyle(selected ? CityMVPFormStyle.canvas : CityMVPFormStyle.ink)
                .padding(14).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(selected ? CityMVPFormStyle.ink : CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 22))
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("cityMVP.search.category.\(category.rawValue)")
    }
#else
    private var searchInk: Color { SaveAtlasPalette.forest }
    private var searchSurface: Color { SaveAtlasPalette.canvas }
    private var searchMuted: Color { SaveAtlasPalette.muted }
    private var searchSaved: Color { SaveAtlasPalette.mint }
    private var searchCandidate: Color { SaveAtlasPalette.sky }
#endif

    private func localized(_ english: String, _ chinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: chinese)
    }
}
