import SwiftUI

struct PlaceListView: View {
    @StateObject private var viewModel = PlaceListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadPlacesTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    ForEach(PlaceFilter.allCases, id: \.self) { filter in
                        FilterNotebookTab(
                            title: filter.rawValue,
                            isSelected: viewModel.filter == filter
                        ) {
                            viewModel.filter = filter
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            CategoryPill(
                                category: category,
                                isSelected: viewModel.selectedCategories.contains(category)
                            )
                            .onTapGesture {
                                if viewModel.selectedCategories.contains(category) {
                                    viewModel.selectedCategories.remove(category)
                                } else {
                                    viewModel.selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
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
                                Label(sort.rawValue, systemImage: viewModel.sort == sort ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.sort.rawValue)
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
                        Task { await viewModel.saveMapCandidate(result) }
                    } onPlanAround: { result in
                        viewModel.planAround(result)
                    }
                } else if viewModel.filteredPlaces.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: "No Map Stamps Yet",
                        subtitle: "Confirm a Review Candidate to save it on your spatial memory canvas."
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
                                ShareLink(item: place.saveShareURL ?? URL(string: "https://sav-e-app.vercel.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.saveSky)

                                Button {
                                    Task { await viewModel.markVisited(place) }
                                } label: {
                                    Label("Visited", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.saveSuccess)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { try? await viewModel.deletePlace(place) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(SaveDottedBackground())
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
            .navigationTitle("Map Stamps")
            .searchable(text: $viewModel.searchText, prompt: "Search Map Stamps, clues, or recommendations...")
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place) {
                    try await viewModel.deletePlace(place)
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
            return "\(count) \(count == 1 ? "result" : "results")"
        }
        return "\(viewModel.filteredPlaces.count) Map Stamps"
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SaveSearchSectionView(
                    section: response.fromYourSave,
                    savingResultID: savingResultID,
                    onSaveMapCandidate: onSaveMapCandidate,
                    onPlanAround: onPlanAround
                )
                SaveSearchSectionView(
                    section: response.newRecommendations,
                    savingResultID: savingResultID,
                    onSaveMapCandidate: onSaveMapCandidate,
                    onPlanAround: onPlanAround
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(SaveDottedBackground())
    }
}

private struct SaveSearchSectionView: View {
    let section: SaveSearchSection
    let savingResultID: String?
    let onSaveMapCandidate: (SaveSearchResult) -> Void
    let onPlanAround: (SaveSearchResult) -> Void

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
                Text(section.emptyMessage ?? "No results yet.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        Label("\(reviewCount) reviews", systemImage: "text.bubble.fill")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
            }

            if !result.missingInfo.isEmpty {
                Text("Missing: \(result.missingInfo.prefix(2).joined(separator: ", "))")
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
        if let url = result.saveShareURL {
            ShareLink(item: url, subject: Text(result.shareSubject), message: Text(result.shareText)) {
                shareLabel
            }
        } else {
            ShareLink(item: result.shareText, subject: Text(result.shareSubject)) {
                shareLabel
            }
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
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
        } else if action.kind == .planAround {
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
            Label("No place saved yet", systemImage: "sparkle.magnifyingglass")
                .font(.caption.weight(.black))
                .foregroundColor(.saveCocoa)
        }
    }

    private func actionLabel(_ action: SaveAgentDrawerAction, isPrimary: Bool) -> some View {
        Label(isSaving && action.kind == .savePlace ? "Saving..." : action.label, systemImage: action.systemImage)
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
    let model: SaveEvidenceDrawerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("Evidence")
                Spacer(minLength: 0)
                Text(model.confidenceLabel)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)

            if let provenanceLabel = model.provenanceLabel {
                Text(provenanceLabel)
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
                        Text(atom.label)
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveInk)
                        Text(atom.value)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.saveMutedText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }

            if !model.missingFields.isEmpty {
                evidenceLine(title: "Missing", value: model.missingFields.prefix(3).joined(separator: ", "))
            }

            if !model.recoveryQueries.isEmpty {
                evidenceLine(title: "Next recovery", value: model.recoveryQueries.prefix(2).joined(separator: " · "))
            }

            if let candidateExplanation = model.candidateExplanation {
                Text(candidateExplanation)
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
}

private struct SavePlanAroundPreviewView: View {
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
            .navigationTitle("Plan around this")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func draftView(_ draft: SavePlanAroundDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SavePlanStopRow(stop: draft.anchor, titlePrefix: "Anchor")
            Text(draft.explanation)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

            planSection(title: "Route draft", stops: draft.routeStops.dropFirst())
            planSection(title: "From Map Stamps", stops: draft.nearbySaved)
            planSection(title: "Unsaved nearby candidates", stops: draft.newSuggestions)

            if !draft.routeNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Route notes")
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
                Text("Missing: \(state.missingInfo.joined(separator: ", "))")
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
                Text("No routeable matches yet.")
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#Preview {
    PlaceListView()
}
