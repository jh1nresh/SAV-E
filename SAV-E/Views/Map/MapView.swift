import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var viewModel: MapViewModel
    let shouldFocusOnUserLocationOnLaunch: Bool
    let displayedPlaces: [Place]?
    let showsAuxiliaryPins: Bool

    init(
        viewModel: MapViewModel,
        shouldFocusOnUserLocationOnLaunch: Bool,
        displayedPlaces: [Place]? = nil,
        showsAuxiliaryPins: Bool = true
    ) {
        self.viewModel = viewModel
        self.shouldFocusOnUserLocationOnLaunch = shouldFocusOnUserLocationOnLaunch
        self.displayedPlaces = displayedPlaces
        self.showsAuxiliaryPins = showsAuxiliaryPins
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Map(position: $viewModel.cameraPosition, selection: $viewModel.selectedMapFeature) {
                    UserAnnotation()

                    ForEach(displayedPlaces ?? viewModel.filteredPlaces) { place in
                        Annotation("", coordinate: place.coordinate) {
                            PlaceMapPin(
                                place: place,
                                isSelected: viewModel.selectedPlace?.id == place.id
                            ) {
                                viewModel.selectPlace(place)
                            }
                        }
                    }

                    if showsAuxiliaryPins {
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
                                SaveHaptics.tap()
                                Task { await viewModel.focusOnUserLocation() }
                            }
                        )
                        .padding(.trailing, 18)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom + 96, 112))
                    }
                }

                if let moment = viewModel.stampMoment {
                    VStack {
                        SaveStampMomentView(moment: moment)
                            .padding(.top, geo.safeAreaInsets.top + 18)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .id(moment.id)
                    .zIndex(2)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .onTapGesture {
                        withAnimation(SaveTheme.Motion.standardSpring) {
                            viewModel.stampMoment = nil
                        }
                    }
                    .task(id: moment.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        guard viewModel.stampMoment?.id == moment.id else { return }
                        withAnimation(SaveTheme.Motion.standardSpring) {
                            viewModel.stampMoment = nil
                        }
                    }
                }
            }
            .animation(SaveTheme.Motion.standardSpring, value: viewModel.stampMoment)
            .ignoresSafeArea()
        }
        .task(id: shouldFocusOnUserLocationOnLaunch) {
            guard shouldFocusOnUserLocationOnLaunch else { return }
            await viewModel.focusOnUserLocationOnLaunch()
        }
    }
}

private struct CurrentLocationButton: View {
    @Environment(\.appLanguageSettings) private var languageSettings
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
        .accessibilityLabel(languageSettings.localized(english: "Center map on current location", traditionalChinese: "將地圖移到目前位置"))
        .accessibilityHint(languageSettings.localized(english: "Moves the map back to where you are now", traditionalChinese: "把地圖移回你現在所在的位置"))
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
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            DefaultPOIMarker(
                systemName: place.category.iconName,
                tint: place.category.mapMarkerTint,
                state: .saved
            )
            .scaleEffect(isSelected ? 1.24 : 1)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.saveHoney.opacity(0.86), lineWidth: 3)
                        .frame(width: 46, height: 46)
                        .shadow(color: Color.saveHoney.opacity(0.28), radius: 5)
                }
            }
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 10 : 0)
        .accessibilityLabel(languageSettings.localized(english: "\(place.name) Map Stamp", traditionalChinese: "\(place.name) 地圖章"))
    }
}

private struct SocialPlaceMapPin: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            DefaultPOIMarker(
                systemName: place.category.iconName,
                tint: place.category.mapMarkerTint,
                state: .shared
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "\(place.name) social place", traditionalChinese: "\(place.name) 社交地點"))
        .accessibilityHint(place.socialSignal?.displayText ?? languageSettings.localized(english: "Opens a place from your social map", traditionalChinese: "打開社交地圖裡的地點"))
    }
}

private struct ReviewCandidateMapPin: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let candidate: PlaceReviewCandidate
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            DefaultPOIMarker(
                systemName: candidate.inferredCategory.iconName,
                tint: .saveSignal,
                state: .review
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "\(candidate.name) Review Candidate", traditionalChinese: "\(candidate.name) 待確認地點"))
        .accessibilityHint(languageSettings.localized(english: "Opens the Review Candidate before saving it as a Map Stamp", traditionalChinese: "先打開待確認地點，再存成地圖章"))
    }
}

private struct UnsavedMapCandidatePin: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let candidate: SaveMapCandidate
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            DefaultPOIMarker(
                systemName: candidate.category?.iconName ?? "mappin.circle.fill",
                tint: candidate.category?.mapMarkerTint ?? .saveCocoa,
                state: .publicResult
            )
            .scaleEffect(isSelected ? 1.18 : 1)
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 10 : 0)
        .accessibilityLabel(languageSettings.localized(english: "\(candidate.title) Unsaved Candidate", traditionalChinese: "\(candidate.title) 未保存候選地點"))
        .accessibilityHint(languageSettings.localized(english: "Opens this visible map place before saving it as a Map Stamp", traditionalChinese: "打開這個地圖候選地點，確認後再存成地圖章"))
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
        // Keep the 30 pt marker visual, but guarantee a >= 44 pt touch target.
        .frame(width: 44, height: 44)
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
            return .saveMint.opacity(0.74)
        case .shared:
            return .saveCocoa.opacity(0.74)
        case .review:
            return .saveSignal.opacity(0.80)
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
        case .saved: return .saveMint
        case .shared: return .saveCocoa
        case .review, .publicResult: return .clear
        }
    }
}

private extension PlaceCategory {
    var mapMarkerTint: Color {
        switch self {
        case .food: return .saveCocoa
        case .cafe: return .saveCocoa
        case .bar: return .saveCocoa
        case .attraction: return .saveCocoa
        case .stay: return .saveCocoa
        case .shopping: return .saveCocoa
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
