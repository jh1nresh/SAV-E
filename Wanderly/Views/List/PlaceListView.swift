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
                    SaveSearchResultsList(response: viewModel.saveSearchResponse)
                } else if viewModel.filteredPlaces.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: "No Memory Cards Found",
                        subtitle: "Try adjusting filters or save a Review clue as a memory card."
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
            }
            .background(SaveDottedBackground())
            .navigationTitle("Memory Cards")
            .searchable(text: $viewModel.searchText, prompt: "Search memory cards...")
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
        return "\(viewModel.filteredPlaces.count) memory cards"
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SaveSearchSectionView(section: response.fromYourSave)
                SaveSearchSectionView(section: response.newRecommendations)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(SaveDottedBackground())
    }
}

private struct SaveSearchSectionView: View {
    let section: SaveSearchSection

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
                    SaveSearchResultCard(result: result)
                }
            }
        }
    }
}

private struct SaveSearchResultCard: View {
    let result: SaveSearchResult

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

            if !result.missingInfo.isEmpty {
                Text("Missing: \(result.missingInfo.prefix(2).joined(separator: ", "))")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sourceURL = result.sourceURL, let url = URL(string: sourceURL) {
                Link(destination: url) {
                    Label("Open source", systemImage: "link")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                }
            } else if result.isRecommendationShell {
                Label("No place saved yet", systemImage: "sparkle.magnifyingglass")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa)
            }
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 18)
    }

    private var iconName: String {
        switch result.objectType {
        case .savedPlace: return "map.fill"
        case .pendingCandidate: return "checklist.unchecked"
        case .sourceOnlyClue: return "link"
        case .triedMemory: return "checkmark.seal.fill"
        case .review: return "text.bubble.fill"
        case .tripStop: return "route.fill"
        case .newRecommendation: return "sparkle.magnifyingglass"
        }
    }

    private var iconFill: Color {
        switch result.objectType {
        case .savedPlace, .triedMemory: return .saveMint
        case .pendingCandidate, .sourceOnlyClue: return .saveHoney
        case .review: return .saveSignal
        case .tripStop: return .saveSky
        case .newRecommendation: return .saveSky.opacity(0.72)
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
