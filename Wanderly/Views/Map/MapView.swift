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
                            PlaceMapPin(
                                place: place,
                                isSelected: viewModel.selectedPlace?.id == place.id
                            ) {
                                viewModel.selectPlace(place)
                            }
                        }
                    }

                    ForEach(viewModel.reviewCandidatesOnMap) { candidate in
                        if let coordinate = candidate.coordinate {
                            Annotation("", coordinate: coordinate) {
                                ReviewCandidateMapPin(
                                    candidate: candidate,
                                    isSelected: viewModel.selectedReviewCandidate?.id == candidate.id
                                ) {
                                    viewModel.selectReviewCandidate(candidate)
                                }
                            }
                        }
                    }

                    ForEach(viewModel.visibleMapCandidates) { candidate in
                        Annotation("", coordinate: candidate.coordinate) {
                            UnsavedMapCandidatePin(
                                candidate: candidate,
                                isSelected: viewModel.selectedMapCandidate?.id == candidate.id
                            ) {
                                viewModel.selectMapCandidate(candidate)
                            }
                        }
                    }

                    if let polyline = viewModel.routePolyline {
                        MapPolyline(polyline)
                            .stroke(Color.saveCocoa, lineWidth: 3)
                    }
                }
                .mapStyle(.standard)
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

                CompactMapHeader(
                    reviewCount: viewModel.reviewCandidates.count,
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

private struct CompactMapHeader: View {
    let reviewCount: Int
    let onOpenProfile: () -> Void

    var body: some View {
        HStack {
            BrandMapChip()

            Spacer(minLength: 0)

            PassportNavButton(reviewCount: reviewCount, action: onOpenProfile)
        }
    }
}

private struct BrandMapChip: View {
    var body: some View {
        HStack(spacing: 6) {
            MemoMascotMark(size: 22, framed: false)
            Text("SAV-E")
                .font(.caption.weight(.black))
                .lineLimit(1)
        }
        .foregroundColor(.saveInk)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.saveNotebookPage.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct PassportNavButton: View {
    let reviewCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.saveCream)
                    .frame(width: 42, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                    )

                Image(systemName: "person.crop.circle")
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
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultMapPin(
                systemImage: place.category.iconName,
                fill: place.status == .visited ? .saveMint : .saveHoney,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name) Map Stamp")
    }
}

private struct ReviewCandidateMapPin: View {
    let candidate: PlaceReviewCandidate
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultMapPin(systemImage: "doc.text.magnifyingglass", fill: .saveSky, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.name) Review Candidate")
        .accessibilityHint("Opens the Review Candidate before saving it as a Map Stamp")
    }
}

private struct UnsavedMapCandidatePin: View {
    let candidate: SaveMapCandidate
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultMapPin(
                systemImage: candidate.category?.iconName ?? "mappin.and.ellipse",
                fill: .saveSignal,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.title) Unsaved Candidate")
        .accessibilityHint("Opens this visible map place before saving it as a Map Stamp")
    }
}

private struct DefaultMapPin: View {
    var systemImage: String
    var fill: Color
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: isSelected ? 31 : 24, height: isSelected ? 31 : 24)
                .overlay(
                    Circle()
                        .stroke(Color.saveNotebookPage, lineWidth: isSelected ? 3 : 2)
                )
                .overlay(
                    Circle()
                        .stroke(Color.saveNotebookLine.opacity(isSelected ? 0.86 : 0.48), lineWidth: 1)
                )
                .shadow(color: Color.saveCocoa.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 5 : 3, x: 0, y: isSelected ? 3 : 2)

            Image(systemName: systemImage)
                .font(.system(size: isSelected ? 13 : 10, weight: .black))
                .foregroundColor(.saveNotebookPage)
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
    }
}

private extension PlaceReviewCandidate {
    var coordinate: CLLocationCoordinate2D? {
        guard hasReliableCoordinates, let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension SaveMapCandidate {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
