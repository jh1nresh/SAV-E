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
    /// `focusesSearch` is true for a tap and false for a resize drag. Dragging
    /// the card shouldn't summon the keyboard; tapping the field should.
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
            // Expanded content is above root navigation, whose geometry already
            // excludes the home indicator; keep the same bottom edge as idle.
            let bottomClearance = max(0, tabBarClearance - (isExpanded ? proxy.safeAreaInsets.bottom : 0))
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
                .frame(maxWidth: .infinity)
                .frame(height: panelHeight(totalHeight: proxy.size.height - bottomClearance), alignment: .top)
                .background {
                    if stage == .collapsed {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.regularMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(SaveAtlasPalette.paper)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.3), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: SaveAtlasPalette.ink.opacity(0.10), radius: 12, y: 4)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Map search drawer")
                .accessibilityValue(stage.accessibilityValue)
                .accessibilityIdentifier(stage.accessibilityIdentifier)
                .padding(.horizontal, stage == .collapsed ? proxy.size.width * 0.07 : 8)
                .padding(.bottom, bottomClearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(reduceMotion ? nil : SaveTheme.Motion.standardSpring, value: isExpanded)
        .animation(reduceMotion ? nil : SaveTheme.Motion.standardSpring, value: detent)
    }

    private var stage: MapDrawerStage { isExpanded ? expandedStage : .collapsed }

    private var resizeHandle: some View {
        Capsule()
            .fill(SaveAtlasPalette.line.opacity(0.48))
            .frame(width: 36, height: 4)
            .frame(height: 12)
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
        let largeHeight = max(collapsedHeight, totalHeight - 12)
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
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
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
            text.isEmpty || $0.name.localizedStandardContains(text) || $0.address.localizedStandardContains(text)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField(localized("Search places", "搜尋地點"), text: $query)
                    .font(SaveAtlasType.body(17))
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
            .foregroundStyle(SaveAtlasPalette.forest)
            .padding(.leading, 12)
            .background(SaveAtlasPalette.canvas, in: Capsule())
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(localized("Your Map Stamps", "你的地圖章"))
                            .font(SaveAtlasType.strong(15))
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
                                .font(SaveAtlasType.body(14))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("map.search.filters")
                    }
                    ForEach(savedResults) { place in
                        Button {
                            isFocused = false
                            onOpenPlace(place)
                        } label: {
                            resultRow(place.name, detail: place.address, state: localized("Saved", "已存"), tint: SaveAtlasPalette.mint)
                        }
                        .accessibilityIdentifier("map.search.saved.\(place.id)")
                    }
                    if savedResults.isEmpty {
                        Text(localized("No saved places match.", "沒有符合的已存地點。"))
                            .font(SaveAtlasType.body(14))
                            .foregroundStyle(SaveAtlasPalette.muted)
                    }
                    if !submittedQuery.isEmpty && submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text(localized("Map results · Not saved", "地圖結果 · 尚未儲存"))
                            .font(SaveAtlasType.strong(15))
                            .padding(.top, 12)
                        if mapViewModel.isLoadingMapCandidates {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        } else if mapViewModel.mapCandidates.isEmpty {
                            Text(localized("No map results. Try a place name and city.", "沒有地圖結果，試試地點名稱加城市。"))
                                .font(SaveAtlasType.body(14))
                                .foregroundStyle(SaveAtlasPalette.muted)
                        } else {
                            ForEach(mapViewModel.mapCandidates) { candidate in
                                Button {
                                    isFocused = false
                                    onOpenCandidate(candidate)
                                } label: {
                                    resultRow(candidate.title, detail: candidate.subtitle, state: localized("Not saved", "未儲存"), tint: SaveAtlasPalette.sky)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SaveAtlasPalette.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.search.root")
        .onAppear {
            query = initialQuery
            submittedQuery = initialQuery
            isFocused = focusesSearch
        }
        .task(id: searchRequestID) {
            guard !submittedQuery.isEmpty else { return }
            await mapViewModel.searchMapPlaces(submittedQuery)
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
                Text(title).font(SaveAtlasType.strong(17))
                Text(detail).font(SaveAtlasType.body(13)).foregroundStyle(SaveAtlasPalette.muted)
                Text(state).font(SaveAtlasType.body(11)).foregroundStyle(SaveAtlasPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: chinese)
    }
}
