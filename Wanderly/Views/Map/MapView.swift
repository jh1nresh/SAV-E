import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.filteredPlaces) { place in
                MapAnnotation(coordinate: place.coordinate) {
                    PlaceMapPin(place: place) {
                        viewModel.selectPlace(place)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            // Category filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        CategoryPill(
                            category: category,
                            isSelected: viewModel.selectedCategories.contains(category)
                        )
                        .onTapGesture {
                            viewModel.toggleCategory(category)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $viewModel.showBottomSheet) {
            if let place = viewModel.selectedPlace {
                PlaceBottomSheet(place: place)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            await viewModel.loadPlaces()
        }
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Image(systemName: place.category.iconName)
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.categoryColor(for: place.category))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color.categoryColor(for: place.category))
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }
        }
    }
}

#Preview {
    MapView()
}
