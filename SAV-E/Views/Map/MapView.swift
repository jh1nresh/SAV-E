import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Map(position: $viewModel.cameraPosition, selection: $viewModel.selectedMapFeature) {
                    UserAnnotation()

                    ForEach(viewModel.filteredPlaces) { place in
                        Annotation("", coordinate: place.coordinate) {
                            PlaceMapPin(
                                place: place
                            ) {
                                viewModel.selectPlace(place)
                            }
                        }
                    }

                    ForEach(viewModel.reviewCandidatesOnMap) { candidate in
                        if let coordinate = candidate.coordinate {
                            Annotation("", coordinate: coordinate) {
                                ReviewCandidateMapPin(
                                    candidate: candidate
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

                    ForEach(viewModel.visibleSocialPlaces) { place in
                        Annotation("", coordinate: place.coordinate) {
                            SocialPlaceMapPin(
                                place: place
                            ) {
                                viewModel.selectSocialPlace(place)
                            }
                        }
                    }

                    if let polyline = viewModel.routePolyline {
                        MapPolyline(polyline)
                            .stroke(Color.saveCocoa, lineWidth: 3)
                    }
                }
                .mapStyle(.standard)
                .mapFeatureSelectionDisabled { feature in
                    feature.kind != .pointOfInterest
                }
                .mapControls {
                    MapCompass()
                }
                .onChange(of: viewModel.selectedMapFeature) { _, feature in
                    viewModel.selectMapFeature(feature)
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
            }
            .ignoresSafeArea()
        }
        .task {
            await viewModel.focusOnUserLocationOnLaunch()
        }
    }
}

private struct CurrentLocationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(controlFill)
                    .frame(width: 54, height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(controlStroke, lineWidth: 1)
                    )

                if isLocating {
                    ProgressView()
                        .tint(controlForeground)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(controlForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel("Center map on current location")
        .accessibilityHint("Moves the map back to where you are now")
    }

    private var controlFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.52) : Color.white.opacity(0.72)
    }

    private var controlStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.saveNotebookLine.opacity(0.26)
    }

    private var controlForeground: Color {
        colorScheme == .dark ? .white : .saveInk
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultPOIMarker(
                systemName: place.category.iconName,
                tint: place.category.mapMarkerTint,
                state: .saved
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name) Map Stamp")
    }
}

private struct SocialPlaceMapPin: View {
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultPOIMarker(
                systemName: place.category.iconName,
                tint: place.category.mapMarkerTint,
                state: .shared
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name) social place")
        .accessibilityHint(place.socialSignal?.displayText ?? "Opens a place from your social map")
    }
}

private struct ReviewCandidateMapPin: View {
    let candidate: PlaceReviewCandidate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DefaultPOIMarker(
                systemName: candidate.inferredCategory.iconName,
                tint: .saveHoney,
                state: .review
            )
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
            DefaultPOIMarker(
                systemName: candidate.category?.iconName ?? "mappin.circle.fill",
                tint: candidate.category?.mapMarkerTint ?? .saveSky,
                state: .publicResult
            )
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 10 : 0)
        .accessibilityLabel("\(candidate.title) Unsaved Candidate")
        .accessibilityHint("Opens this visible map place before saving it as a Map Stamp")
    }
}

private struct DefaultPOIMarker: View {
    var systemName: String
    var tint: Color
    var state: MapMarkerState

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().fill(tint.opacity(0.18)))
                .overlay(Circle().stroke(state.strokeColor, lineWidth: state.strokeWidth))
                .frame(width: 30, height: 30)

            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
        }
        .overlay(alignment: .bottomTrailing) {
            if let badgeSystemName = state.badgeSystemName {
                Image(systemName: badgeSystemName)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(state.badgeColor)
                    .background(Circle().fill(Color.white.opacity(0.94)))
                    .offset(x: 2, y: 2)
            }
        }
        .shadow(color: Color.black.opacity(0.16), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
    }
}

private enum MapMarkerState {
    case saved
    case shared
    case review
    case publicResult

    var strokeColor: Color {
        switch self {
        case .saved:
            return .saveSignal.opacity(0.74)
        case .shared:
            return .saveMint.opacity(0.74)
        case .review:
            return .saveHoney.opacity(0.80)
        case .publicResult:
            return Color.white.opacity(0.86)
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .saved, .shared: return 2
        case .review, .publicResult: return 1.6
        }
    }

    var badgeSystemName: String? {
        switch self {
        case .saved: return "checkmark.circle.fill"
        case .shared: return "person.2.circle.fill"
        case .review, .publicResult: return nil
        }
    }

    var badgeColor: Color {
        switch self {
        case .saved: return .saveSignal
        case .shared: return .saveMint
        case .review, .publicResult: return .clear
        }
    }
}

private extension PlaceCategory {
    var mapMarkerTint: Color {
        switch self {
        case .food: return .saveSignal
        case .cafe: return .saveCocoa
        case .bar: return .savePink
        case .attraction: return .saveHoney
        case .stay: return .saveSky
        case .shopping: return .saveMint
        }
    }
}

private extension PlaceReviewCandidate {
    var inferredCategory: PlaceCategory {
        PlaceCategory.inferred(from: ([name, address, city ?? ""] + evidence).joined(separator: " "))
    }

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
