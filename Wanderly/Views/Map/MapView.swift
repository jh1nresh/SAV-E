import SwiftUI
import MapKit

struct MapView: View {
    @State private var showProfile = false
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Map(position: $viewModel.cameraPosition) {
                    UserAnnotation()

                    ForEach(viewModel.filteredPlaces) { place in
                        Annotation("", coordinate: place.coordinate) {
                            PlaceMapPin(place: place) {
                                viewModel.selectPlace(place)
                            }
                        }
                    }
                    if let polyline = viewModel.routePolyline {
                        MapPolyline(polyline)
                            .stroke(Color.saveCocoa, lineWidth: 3)
                    }
                }
                .mapControls {
                    MapCompass()
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CurrentLocationButton(
                            isLocating: viewModel.isLocatingUser,
                            action: {
                                Task { await viewModel.focusOnUserLocation() }
                            }
                        )
                        .padding(.trailing, 18)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom + 96, 112))
                    }
                }

                TopNotebookNavBar(
                    selectedCategories: viewModel.selectedCategories,
                    reviewCount: viewModel.reviewCandidates.count,
                    onToggleCategory: { category in
                        viewModel.toggleCategory(category)
                    },
                    onOpenProfile: {
                        showProfile = true
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, geo.safeAreaInsets.top + 8)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(waitingClues: viewModel.reviewCandidates.count)
        }
        .task {
            await viewModel.focusOnUserLocationOnLaunch()
        }
    }
}

private struct TopNotebookNavBar: View {
    let selectedCategories: Set<PlaceCategory>
    let reviewCount: Int
    let onToggleCategory: (PlaceCategory) -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.black))
                Text("SAV-E")
                    .font(.caption.weight(.black))
                    .lineLimit(1)
            }
            .foregroundColor(.saveInk)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.saveHoney)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        CategoryPill(
                            category: category,
                            isSelected: selectedCategories.contains(category)
                        )
                        .onTapGesture { onToggleCategory(category) }
                    }
                }
                .padding(.vertical, 2)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            PassportNavButton(reviewCount: reviewCount, action: onOpenProfile)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PassportNavButton: View {
    let reviewCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.saveMint)
                    .frame(width: 42, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                    )

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 21, weight: .black))
                    .foregroundColor(.saveInk)

                if reviewCount > 0 {
                    Text("\(reviewCount)")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.saveHoney)
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())
                        .frame(maxWidth: 24)
                        .offset(x: 12, y: -12)
                }
            }
            .frame(width: 42, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open SAV-E Passport")
        .accessibilityValue(reviewCount > 0 ? "\(reviewCount) waiting clues" : "No waiting clues")
    }
}

private struct CurrentLocationButton: View {
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.saveNotebookPage)
                    .frame(width: 54, height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )

                if isLocating {
                    ProgressView()
                        .tint(.saveInk)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.saveInk)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel("Center map on current location")
        .accessibilityHint("Moves the map back to where you are now")
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    SaveEggBadge(state: .hatched(place.category), size: 42)

                    if place.status == .visited {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.saveSignal)
                            .background(Circle().fill(Color.saveNotebookPage))
                            .offset(x: 5, y: -5)
                    }
                }

                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color.saveStampColor(for: place.category))
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name) map stamp")
    }
}
