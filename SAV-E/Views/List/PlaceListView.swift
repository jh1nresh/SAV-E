import SwiftUI

struct PlaceListView: View {
    @StateObject private var viewModel = PlaceListViewModel()
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadPlacesTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    ForEach(PlaceFilter.allCases, id: \.self) { filter in
                        FilterNotebookTab(
                            title: filter.title(language: languageSettings.language),
                            isSelected: viewModel.filter == filter
                        ) {
                            SaveHaptics.select()
                            withAnimation(SaveTheme.Motion.standardSpring) {
                                viewModel.filter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, SaveTheme.Spacing.md)

                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SaveTheme.Spacing.sm) {
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            Button {
                                SaveHaptics.select()
                                withAnimation(SaveTheme.Motion.standardSpring) {
                                    if viewModel.selectedCategories.contains(category) {
                                        viewModel.selectedCategories.remove(category)
                                    } else {
                                        viewModel.selectedCategories.insert(category)
                                    }
                                }
                            } label: {
                                CategoryPill(
                                    category: category,
                                    isSelected: viewModel.selectedCategories.contains(category)
                                )
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, SaveTheme.Spacing.xs)
                }

                // Sort selector
                HStack {
                    Text(resultsCountLabel)
                        .font(.caption)
                        .foregroundColor(.saveMutedText)

                    Spacer()

                    Menu {
                        ForEach(PlaceSort.allCases, id: \.self) { sort in
                            Button(action: { viewModel.sort = sort }) {
                                Label(sort.title(language: languageSettings.language), systemImage: viewModel.sort == sort ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.sort.title(language: languageSettings.language))
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.saveCocoa)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                // List
                if isSearching {
                    SaveSearchResultsList(
                        response: viewModel.saveSearchResponse,
                        savingResultID: viewModel.savingResultID
                    ) { result in
                        Task {
                            await viewModel.saveMapCandidate(result)
                            if viewModel.saveCandidateError == nil {
                                SaveHaptics.stamp()
                            }
                        }
                    } onPlanAround: { result in
                        viewModel.planAround(result)
                    } onSearchPublicNearby: {
                        viewModel.searchPublicNearbyNow()
                    }
                } else if viewModel.filteredPlaces.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: languageSettings.localized(english: "No Map Stamps Yet", traditionalChinese: "還沒有地圖章"),
                        subtitle: languageSettings.localized(
                            english: "Confirm a Review Candidate to save it on your spatial memory canvas.",
                            traditionalChinese: "確認待確認地點後，就會存到你的私人地圖記憶裡。"
                        )
                    )
                } else {
                    List {
                        ForEach(viewModel.filteredPlaces) { place in
                            NavigationLink(value: place) {
                                PlaceCard(place: place)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                SavePlaceShareButton(content: .place(place)) {
                                    Label(languageSettings.localized(english: "Share", traditionalChinese: "分享"), systemImage: "square.and.arrow.up")
                                }
                                .tint(.saveSky)

                                Button {
                                    SaveHaptics.stamp()
                                    Task { await viewModel.markVisited(place) }
                                } label: {
                                    Label(languageSettings.localized(english: "Visited", traditionalChinese: "去過"), systemImage: "checkmark.circle.fill")
                                }
                                .tint(.saveSuccess)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { try? await viewModel.deletePlace(place) }
                                } label: {
                                    Label(languageSettings.localized(english: "Delete", traditionalChinese: "刪除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(SaveDottedBackground())
                    .animation(SaveTheme.Motion.standardSpring, value: viewModel.filteredPlaces)
                }

                if let deleteError = viewModel.deleteError {
                    Text(deleteError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if let saveCandidateError = viewModel.saveCandidateError {
                    Text(saveCandidateError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .background(SaveDottedBackground())
            .navigationTitle(languageSettings.localized(english: "Map Stamps", traditionalChinese: "地圖章"))
            .searchable(
                text: $viewModel.searchText,
                prompt: languageSettings.localized(
                    english: "Search Map Stamps, clues, or recommendations...",
                    traditionalChinese: "搜尋地圖章、線索或推薦..."
                )
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.prepareMapCandidatesIfNeeded()
            }
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place) {
                    try await viewModel.deletePlace(place)
                } onUpdateVisibility: { visibility in
                    try await viewModel.updatePlaceVisibility(place, visibility: visibility)
                }
            }
        }
        .task {
            startLoadPlacesTask()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            startLoadPlacesTask()
        }
        .onDisappear {
            loadPlacesTask?.cancel()
            loadPlacesTask = nil
        }
        .sheet(item: $viewModel.planAroundResult) { result in
            SavePlanAroundPreviewView(result: result)
                .presentationDetents([.medium, .large])
        }
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resultsCountLabel: String {
        if isSearching {
            let response = viewModel.saveSearchResponse
            let count = response.fromYourSave.results.count + response.newRecommendations.results.count
            switch languageSettings.language {
            case .english:
                return "\(count) \(count == 1 ? "result" : "results")"
            case .traditionalChinese:
                return "\(count) 筆結果"
            }
        }
        switch languageSettings.language {
        case .english:
            return "\(viewModel.filteredPlaces.count) Map Stamps"
        case .traditionalChinese:
            return "\(viewModel.filteredPlaces.count) 個地圖章"
        }
    }

    private func startLoadPlacesTask() {
        loadPlacesTask?.cancel()
        loadPlacesTask = Task {
            await viewModel.loadPlaces()
        }
    }
}

private struct SaveSearchResultsList: View {
    let response: SaveSearchResponse
    let savingResultID: String?
    let onSaveMapCandidate: (SaveSearchResult) -> Void
    let onPlanAround: (SaveSearchResult) -> Void
    let onSearchPublicNearby: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SaveSearchSectionView(
                    section: response.fromYourSave,
                    savingResultID: savingResultID,
                    onSaveMapCandidate: onSaveMapCandidate,
                    onPlanAround: onPlanAround,
                    onSearchPublicNearby: onSearchPublicNearby
                )
                SaveSearchSectionView(
                    section: response.newRecommendations,
                    savingResultID: savingResultID,
                    onSaveMapCandidate: onSaveMapCandidate,
                    onPlanAround: onPlanAround,
                    onSearchPublicNearby: onSearchPublicNearby
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(SaveDottedBackground())
    }
}

private struct SaveSearchSectionView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let section: SaveSearchSection
    let savingResultID: String?
    let onSaveMapCandidate: (SaveSearchResult) -> Void
    let onPlanAround: (SaveSearchResult) -> Void
    let onSearchPublicNearby: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                Text(section.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
            }

            if section.results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.emptyMessage ?? "No results yet.")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveCocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if section.showsNearbySearchAction {
                        Button {
                            onSearchPublicNearby()
                        } label: {
                            Label(
                                languageSettings.localized(
                                    english: "Search public nearby options",
                                    traditionalChinese: "搜尋附近公開選項"
                                ),
                                systemImage: "location.magnifyingglass"
                            )
                                .font(.caption2.weight(.black))
                                .foregroundColor(.saveInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.saveHoney)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .saveNotebookPage(cornerRadius: 14)
            } else {
                ForEach(section.results) { result in
                    SaveSearchResultCard(
                        result: result,
                        isSaving: savingResultID == result.id,
                        onSaveMapCandidate: onSaveMapCandidate,
                        onPlanAround: onPlanAround
                    )
                }
            }
        }
    }
}

private struct SaveSearchResultCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let result: SaveSearchResult
    let isSaving: Bool
    let onSaveMapCandidate: (SaveSearchResult) -> Void
    let onPlanAround: (SaveSearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 36, height: 36)
                    .background(iconFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(result.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                SaveSearchChip(text: result.objectType.displayName, fill: .saveHoney)
                SaveSearchChip(text: result.userState.displayName, fill: result.isRecommendationShell ? .saveSky : .saveMint)
                if let category = result.category {
                    SaveSearchChip(text: category.displayName, fill: .saveSignal)
                }
            }

            if result.rating != nil || result.reviewCount != nil {
                HStack(spacing: 6) {
                    if let rating = result.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                    if let reviewCount = result.reviewCount {
                        Label(languageSettings.localized(english: "\(reviewCount) reviews", traditionalChinese: "\(reviewCount) 則評論"), systemImage: "text.bubble.fill")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
            }

            if !result.missingInfo.isEmpty {
                Text(languageSettings.localized(
                    english: "Missing: \(result.missingInfo.prefix(2).joined(separator: ", "))",
                    traditionalChinese: "還缺：\(result.missingInfo.prefix(2).joined(separator: "、"))"
                ))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SaveAgentActionDrawerPreview(
                result: result,
                isSaving: isSaving,
                onSaveMapCandidate: onSaveMapCandidate,
                onPlanAround: onPlanAround
            )
            shareLink
            SaveEvidenceDrawerPreview(model: result.evidenceDrawer)
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 18)
    }

    @ViewBuilder
    private var shareLink: some View {
        SavePlaceShareButton(content: .searchResult(result)) {
            shareLabel
        }
    }

    private var shareLabel: some View {
        Label(languageSettings.localized(english: "Share", traditionalChinese: "分享"), systemImage: "square.and.arrow.up")
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.saveNotebookPage)
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.1))
            .clipShape(Capsule())
    }

    private var iconName: String {
        switch result.objectType {
        case .savedPlace: return "map.fill"
        case .pendingCandidate: return "checklist.unchecked"
        case .sourceOnlyClue: return "link"
        case .triedMemory: return "checkmark.seal.fill"
        case .review: return "text.bubble.fill"
        case .tripStop: return "route.fill"
        case .mapVisibleUnsavedPlace: return "mappin.and.ellipse"
        case .newRecommendation: return "sparkle.magnifyingglass"
        }
    }

    private var iconFill: Color {
        switch result.objectType {
        case .savedPlace, .triedMemory: return .saveMint
        case .pendingCandidate, .sourceOnlyClue: return .saveHoney
        case .review, .mapVisibleUnsavedPlace: return .saveSignal
        case .tripStop: return .saveSky
        case .newRecommendation: return .saveSky.opacity(0.72)
        }
    }
}

private struct SaveAgentActionDrawerPreview: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let result: SaveSearchResult
    let isSaving: Bool
    let onSaveMapCandidate: (SaveSearchResult) -> Void
    let onPlanAround: (SaveSearchResult) -> Void

    private var drawer: SaveAgentActionDrawerModel { result.agentDrawer }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(drawer.heading)
            }
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)

            Text(drawer.contextLine)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                actionView(drawer.primaryAction, isPrimary: true)

                ForEach(drawer.secondaryActions.prefix(2)) { action in
                    actionView(action, isPrimary: false)
                }
            }
        }
        .padding(10)
        .background(Color.saveSky.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func actionView(_ action: SaveAgentDrawerAction, isPrimary: Bool) -> some View {
        if isPrimary, action.kind == .savePlace, result.objectType == .mapVisibleUnsavedPlace {
            Button {
                onSaveMapCandidate(result)
            } label: {
                actionLabel(action, isPrimary: true)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        } else if action.kind == .planAround || action.kind == .recommendOrder {
            Button {
                onPlanAround(result)
            } label: {
                actionLabel(action, isPrimary: isPrimary)
            }
            .buttonStyle(.plain)
        } else if action.kind == .openSource, let sourceURL = result.sourceURL, let url = URL(string: sourceURL) {
            Link(destination: url) {
                actionLabel(action, isPrimary: isPrimary)
            }
        } else if action.kind != .none {
            actionLabel(action, isPrimary: isPrimary)
        } else if result.isRecommendationShell {
            Label(languageSettings.localized(english: "No place saved yet", traditionalChinese: "還沒有保存地點"), systemImage: "sparkle.magnifyingglass")
                .font(.caption.weight(.black))
                .foregroundColor(.saveCocoa)
        }
    }

    private func actionLabel(_ action: SaveAgentDrawerAction, isPrimary: Bool) -> some View {
        Label(isSaving && action.kind == .savePlace ? languageSettings.text(.saving) : action.label, systemImage: action.systemImage)
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.saveHoney : Color.saveNotebookPage)
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.1))
            .clipShape(Capsule())
    }
}

private struct SaveEvidenceDrawerPreview: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let model: SaveEvidenceDrawerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                Text(languageSettings.localized(english: "Evidence", traditionalChinese: "證據"))
                Spacer(minLength: 0)
                Text(localizedEvidenceText(model.confidenceLabel))
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)

            if let provenanceLabel = model.provenanceLabel {
                Text(localizedEvidenceText(provenanceLabel))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(model.evidenceAtoms.prefix(5)) { atom in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: iconName(for: atom.kind))
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(localizedEvidenceText(atom.label))
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveInk)
                        Text(localizedEvidenceValue(atom.value))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.saveMutedText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }

            if !model.missingFields.isEmpty {
                evidenceLine(
                    title: languageSettings.localized(english: "Missing", traditionalChinese: "還缺"),
                    value: model.missingFields.prefix(3).map(localizedEvidenceText).joined(separator: missingFieldsSeparator)
                )
            }

            if !model.recoveryQueries.isEmpty {
                evidenceLine(title: languageSettings.localized(english: "Next recovery", traditionalChinese: "下一步補線索"), value: model.recoveryQueries.prefix(2).joined(separator: " · "))
            }

            if let candidateExplanation = model.candidateExplanation {
                Text(localizedEvidenceText(candidateExplanation))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.88))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func evidenceLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingFieldsSeparator: String {
        languageSettings.language == .traditionalChinese ? "、" : ", "
    }

    private func iconName(for kind: SaveEvidenceAtomKind) -> String {
        switch kind {
        case .sourceURL: return "link"
        case .caption: return "text.quote"
        case .creator: return "person.crop.circle"
        case .venueHandle: return "at"
        case .address: return "mappin"
        case .city: return "building.2"
        case .coordinates: return "location"
        case .rating: return "star.fill"
        case .reviewCount: return "text.bubble"
        case .userNote: return "note.text"
        case .receipt: return "receipt"
        }
    }

    private func localizedEvidenceText(_ text: String) -> String {
        guard languageSettings.language == .traditionalChinese else { return text }
        if text.hasSuffix("% confidence") {
            return text.replacingOccurrences(of: "% confidence", with: "% 信心")
        }
        switch text {
        case "Clue from Instagram": return "來自 Instagram 的線索"
        case "Clue from Threads": return "來自 Threads 的線索"
        case "Clue from Xiaohongshu": return "來自小紅書的線索"
        case "Clue from Douyin": return "來自抖音的線索"
        case "Clue from TikTok": return "來自 TikTok 的線索"
        case "Clue from Google Maps": return "來自 Google Maps 的線索"
        case "Clue from Amap": return "來自高德地圖的線索"
        case "Clue from Baidu Maps": return "來自百度地圖的線索"
        case "Clue from Other": return "來自其他來源的線索"
        case "Source Clue": return "來源線索"
        case "Review Candidate; confirm before Map Stamp": return "待確認地點；確認後才會成為地圖章"
        case "Unsaved candidate; not a Map Stamp": return "未保存候選地點；還不是地圖章"
        case "Map Stamp saved in SAV-E": return "已保存到 SAV-E 的地圖章"
        case "Visited Map Stamp": return "去過的地圖章"
        case "Private review": return "私人評論"
        case "Trip stop": return "行程地點"
        case "Recommendation; no saved memory": return "推薦；尚未保存到記憶"
        case "Exact place unconfirmed": return "精確地點尚未確認"
        case "Candidate needs review": return "候選地點需要確認"
        case "Map evidence present": return "已有地圖證據"
        case "Map Stamp": return "地圖章"
        case "Review evidence": return "評論證據"
        case "Unsaved recommendation": return "未保存推薦"
        case "Source": return "來源"
        case "Platform": return "平台"
        case "Map label": return "地圖標籤"
        case "Address": return "地址"
        case "Coordinates": return "座標"
        case "Rating": return "評分"
        case "Reviews": return "評論數"
        case "State": return "狀態"
        case "Caption clue": return "文案線索"
        case "Creator/provenance": return "創作者／來源"
        case "Venue handle": return "店家帳號"
        case "Address clue": return "地址線索"
        case "Review count": return "評論數"
        case "Receipt": return "收據"
        case "Evidence": return "證據"
        case "exact venue", "exact place": return "精確地點"
        case "address", "verified address": return "已確認地址"
        case "coordinates": return "座標"
        case "verified source platform": return "已確認來源平台"
        case "SAV-E is preserving the source clue without creating a Map Stamp.": return "SAV-E 會先保存來源線索，不會直接做成地圖章。"
        case "This can become a Map Stamp only after the place evidence is confirmed.": return "地點證據確認後，才會變成地圖章。"
        case "This is an unsaved candidate, not a Map Stamp yet.": return "這是未保存候選地點，還不是地圖章。"
        case "This Map Stamp is already saved in SAV-E.": return "這個地圖章已經保存到 SAV-E。"
        case "This is a recommendation, not a saved memory. Choose a concrete place first.": return "這是推薦，不是已保存記憶。請先選一個明確地點。"
        default: return text
        }
    }

    private func localizedEvidenceValue(_ value: String) -> String {
        guard languageSettings.language == .traditionalChinese else { return value }
        switch value {
        case "Map result": return "地圖結果"
        case "present": return "已取得"
        case "Unsaved; not a Map Stamp": return "未保存；還不是地圖章"
        case "Saved Map Stamp": return "已保存地圖章"
        default: return value
        }
    }
}

private struct SavePlanAroundPreviewView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let result: SavePlanAroundResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch result {
                    case .draft(let draft):
                        draftView(draft)
                    case .blocked(let state):
                        blockedView(state)
                    }
                }
                .padding(16)
            }
            .background(SaveDottedBackground())
            .navigationTitle(languageSettings.localized(english: "Plan around this", traditionalChinese: "圍繞這裡規劃"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(languageSettings.localized(english: "Done", traditionalChinese: "完成")) { dismiss() }
                }
            }
        }
    }

    private func draftView(_ draft: SavePlanAroundDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SavePlanStopRow(stop: draft.anchor, titlePrefix: languageSettings.localized(english: "Anchor", traditionalChinese: "起點"))
            Text(draft.explanation)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

            planSection(title: languageSettings.localized(english: "Route draft", traditionalChinese: "路線草稿"), stops: draft.routeStops.dropFirst())
            planSection(title: languageSettings.localized(english: "From Map Stamps", traditionalChinese: "來自地圖章"), stops: draft.nearbySaved)
            planSection(title: languageSettings.localized(english: "Unsaved nearby candidates", traditionalChinese: "附近未保存候選地點"), stops: draft.newSuggestions)

            if !draft.routeNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(languageSettings.localized(english: "Route notes", traditionalChinese: "路線備註"))
                        .font(.headline.weight(.black))
                        .foregroundColor(.saveInk)
                    ForEach(draft.routeNotes, id: \.self) { note in
                        Text(note)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.saveCocoa)
                    }
                }
                .padding(12)
                .saveNotebookPage(cornerRadius: 16)
            }
        }
    }

    private func blockedView(_ state: SavePlanBlockedState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state.title, systemImage: "exclamationmark.triangle")
                .font(.headline.weight(.black))
                .foregroundColor(.saveInk)
            Text(state.message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.saveMutedText)
            if !state.missingInfo.isEmpty {
                Text(languageSettings.localized(
                    english: "Missing: \(state.missingInfo.joined(separator: ", "))",
                    traditionalChinese: "還缺：\(state.missingInfo.joined(separator: "、"))"
                ))
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa)
            }
        }
        .padding(14)
        .saveNotebookPage(cornerRadius: 18)
    }

    private func planSection<S: Sequence>(title: String, stops: S) -> some View where S.Element == SavePlanStop {
        let items = Array(stops)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(.saveInk)
            if items.isEmpty {
                Text(languageSettings.localized(english: "No routeable matches yet.", traditionalChinese: "還沒有可排入路線的符合地點。"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
            } else {
                ForEach(items) { stop in
                    SavePlanStopRow(stop: stop)
                }
            }
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 16)
    }
}

private struct SavePlanStopRow: View {
    let stop: SavePlanStop
    var titlePrefix: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 30, height: 30)
                .background(Color.saveHoney)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text([titlePrefix, stop.title].compactMap { $0 }.joined(separator: ": "))
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                if let subtitle = stop.subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .lineLimit(2)
                }
                Text([stop.distanceLabel, stop.reason].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconName: String {
        switch stop.source {
        case .anchor: return "mappin.and.ellipse"
        case .userSaved: return "map.fill"
        case .pendingCandidate: return "checklist.unchecked"
        case .unsavedMapCandidate: return "sparkle.magnifyingglass"
        }
    }
}

private struct SaveSearchChip: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill.opacity(0.82))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.2))
            .clipShape(Capsule())
    }
}

private struct FilterNotebookTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isSelected ? Color.saveHoney : Color.saveNotebookPage)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: isSelected ? 1.8 : 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // 34 pt visual, >= 44 pt touch target.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#Preview {
    PlaceListView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
