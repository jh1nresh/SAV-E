import SwiftUI

struct PlaceListView: View {
    @StateObject private var viewModel = PlaceListViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter tabs
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(PlaceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

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
                    Text("\(viewModel.filteredPlaces.count) places")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                        .foregroundColor(.wanderlyTerracotta)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                // List
                if viewModel.filteredPlaces.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: "No Places Found",
                        subtitle: "Try adjusting your filters or save a new place from any app."
                    )
                } else {
                    List {
                        ForEach(viewModel.filteredPlaces) { place in
                            NavigationLink(value: place) {
                                PlaceCard(place: place)
                            }
                            .listRowBackground(Color.wanderlyCream)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await viewModel.markVisited(place) }
                                } label: {
                                    Label("Visited", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.wanderlySage)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deletePlace(place) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.wanderlyCream)
                }
            }
            .background(Color.wanderlyCream)
            .navigationTitle("Places")
            .searchable(text: $viewModel.searchText, prompt: "Search places...")
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place)
            }
        }
        .task {
            await viewModel.loadPlaces()
        }
    }
}

#Preview {
    PlaceListView()
}
