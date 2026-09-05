import SwiftUI
import MapKit

struct MapView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var viewModel: MapViewModel
    let shouldFocusOnUserLocationOnLaunch: Bool
    let displayedPlaces: [Place]?
    let showsAuxiliaryPins: Bool
    let numberedPlacePositions: [UUID: Int]
    let contextBadgeText: String?

    init(
        viewModel: MapViewModel,
        shouldFocusOnUserLocationOnLaunch: Bool,
        displayedPlaces: [Place]? = nil,
        showsAuxiliaryPins: Bool = true,
        numberedPlacePositions: [UUID: Int] = [:],
        contextBadgeText: String? = nil
    ) {
        self.viewModel = viewModel
        self.shouldFocusOnUserLocationOnLaunch = shouldFocusOnUserLocationOnLaunch
        self.displayedPlaces = displayedPlaces
        self.showsAuxiliaryPins = showsAuxiliaryPins
        self.numberedPlacePositions = numberedPlacePositions
        self.contextBadgeText = contextBadgeText
    }

    var body: some View {
        GeometryReader { geo in
            let topChromeInset = max(geo.safeAreaInsets.top + 12, 62)
            // Root Map parks a 72pt search panel above the tab bar.
            // Trip Map crops MapView above its place card, so a short
            // trailing clearance is enough. Selection swaps the pill for a
            // taller place peek, so locate rises with that chrome.
            let isEmbeddedCrop = displayedPlaces != nil
            let bottomChromeInset = isEmbeddedCrop
                ? max(geo.safeAreaInsets.bottom + 18, 28)
                : max(
                    geo.safeAreaInsets.bottom + (viewModel.selectedPlace == nil ? 156 : 240),
                    viewModel.selectedPlace == nil ? 168 : 252
                )

            ZStack {
                Map(position: $viewModel.cameraPosition, selection: $viewModel.selectedMapFeature) {
                    UserAnnotation()

                    ForEach((displayedPlaces ?? viewModel.filteredPlaces).filter(\.isMapKitMappable)) { place in
                        Annotation("", coordinate: place.coordinate) {
                            PlaceMapPin(
                                place: place,
                                isSelected: viewModel.selectedPlace?.id == place.id,
                                position: numberedPlacePositions[place.id]
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

                        ForEach(viewModel.visibleSocialPlaces) { place in
                            Annotation("", coordinate: place.coordinate) {
                                SocialPlaceMapPin(
                                    place: place,
                                    isSelected: viewModel.selectedSocialPlace?.id == place.id
                                ) {
                                    viewModel.selectSocialPlace(place)
                                }
                            }
                        }
                    }

                    if let polyline = viewModel.routePolyline {
                        MapPolyline(polyline)
                            .stroke(
                                SaveAtlasPalette.ink.opacity(0.76),
                                style: StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: [7, 5]
                                )
                            )
                    }
                }
                .mapStyle(
                    .standard(
                        elevation: .flat,
                        // Was `.muted` + `.saturation(0.78)` + `.contrast(0.96)`
                        // + a 0.06 canvas scrim on top. Those four greying
                        // layers multiplied, so parks, retail districts and POI
                        // glyphs all washed out to the same beige and the map
                        // read as one flat heavy block. Apple's own emphasis is
                        // the only tint layer now; brand tone comes from the
                        // markers and chrome, not from desaturating the basemap.
                        emphasis: .automatic,
                        // Native Apple Maps POIs stay visible: tapping one is
                        // the primary "save a place you can see" entry, and
                        // selectMapFeature depends on selectable POI features.
                        pointsOfInterest: .all,
                        showsTraffic: false
                    )
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: bottomChromeInset)
                        .allowsHitTesting(false)
                }
                .mapFeatureSelectionDisabled { feature in
                    feature.kind != .pointOfInterest
                }
                .mapControls {
                    MapCompass()
                }
                .onChange(of: viewModel.selectedMapFeature) { _, feature in
                    viewModel.selectMapFeature(feature)
                }
                .accessibilityIdentifier("map.liveSurface")
                .overlay(alignment: .bottomTrailing) {
                    CurrentLocationButton(
                        isLocating: viewModel.isLocatingUser,
                        action: {
                            SaveHaptics.tap()
                            Task { await viewModel.focusOnUserLocation() }
                        }
                    )
                    .accessibilityIdentifier("map.currentLocation")
                    .padding(.trailing, 16)
                    // Apple Maps / DESIGN.md: one-handed bottom-trailing locate,
                    // cleared above the floating search pill or place peek.
                    .padding(.bottom, bottomChromeInset)
                }
                .animation(SaveTheme.Motion.standardSpring, value: viewModel.selectedPlace?.id)

                if let contextBadgeText {
                    VStack {
                        AtlasMapContextBadge(text: contextBadgeText)
                            .accessibilityIdentifier("map.contextBadge")
                            .padding(.top, topChromeInset)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                }

                if let providerPlace = providerBackedPlaces.first {
                    Button {
                        viewModel.selectPlace(providerPlace)
                    } label: {
                        Label(
                            languageSettings.localized(
                                english: providerBackedPlaces.count == 1
                                    ? "1 saved Amap place"
                                    : "\(providerBackedPlaces.count) saved Amap places",
                                traditionalChinese: "已保存 \(providerBackedPlaces.count) 個高德地點"
                            ),
                            systemImage: "map.fill"
                        )
                        .font(SaveAtlasType.strong(11))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(SaveAtlasPalette.paper.opacity(0.96), in: Capsule())
                        .overlay(Capsule().stroke(SaveAtlasPalette.forest.opacity(0.34), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .padding(.bottom, bottomChromeInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .accessibilityIdentifier("map.providerBackedPlaces")
                }

                if let moment = viewModel.stampMoment {
                    VStack {
                        SaveStampMomentView(moment: moment)
                            .padding(.top, topChromeInset)
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

                // Spec P4: locate with denied/restricted permission surfaces
                // a recovery notice instead of silently doing nothing.
                if viewModel.showsLocationDeniedNotice {
                    VStack {
                        SaveLocationDeniedNotice(
                            onOpenSettings: openSystemSettings,
                            onDismiss: {
                                withAnimation(SaveTheme.Motion.standardSpring) {
                                    viewModel.showsLocationDeniedNotice = false
                                }
                            }
                        )
                        .padding(.top, topChromeInset)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .zIndex(2)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            .animation(SaveTheme.Motion.standardSpring, value: viewModel.stampMoment)
            .animation(SaveTheme.Motion.standardSpring, value: viewModel.showsLocationDeniedNotice)
            .ignoresSafeArea()
        }
        .task(id: shouldFocusOnUserLocationOnLaunch) {
            guard shouldFocusOnUserLocationOnLaunch else { return }
            await viewModel.focusOnUserLocationOnLaunch()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var providerBackedPlaces: [Place] {
        (displayedPlaces ?? viewModel.filteredPlaces).filter {
            !$0.isMapKitMappable && $0.providerMapDestinationURL != nil
        }
    }
}

/// Spec P4: Atlas-style notice with an Open Settings recovery path, shown
/// when locating fails because permission is denied or restricted.
private struct SaveLocationDeniedNotice: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 34, height: 34)
                    .background(SaveAtlasPalette.mint, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(
                        english: "Location is off for Savvy",
                        traditionalChinese: "Savvy 的定位權限已關閉"
                    ))
                    .font(SaveAtlasType.strong(16, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.forest)

                    Text(languageSettings.localized(
                        english: "Allow location in Settings to jump the map to where you are.",
                        traditionalChinese: "到「設定」開啟定位，地圖就能跳到你所在的位置。"
                    ))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 28, height: 28)
                        .background(SaveAtlasPalette.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Dismiss location notice",
                    traditionalChinese: "關閉定位提示"
                ))
                .accessibilityIdentifier("map.locationNotice.dismiss")
            }

            Button(action: onOpenSettings) {
                HStack {
                    Spacer()
                    Text(languageSettings.localized(
                        english: "Open Settings",
                        traditionalChinese: "打開設定"
                    ))
                    .font(SaveAtlasType.strong(15))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .frame(minHeight: 40)
                .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.locationNotice.openSettings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 340)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.locationNotice")
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
                if isLocating {
                    ProgressView()
                        .tint(controlForeground)
                } else {
                    // Apple Maps reference uses the filled location glyph in a
                    // frosted circular control above the search capsule.
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(controlForeground)
                }
            }
            .frame(width: 48, height: 48)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel(languageSettings.localized(english: "Center map on current location", traditionalChinese: "將地圖移到目前位置"))
        .accessibilityHint(languageSettings.localized(english: "Moves the map back to where you are now", traditionalChinese: "把地圖移回你現在所在的位置"))
    }

    private var controlForeground: Color {
        colorScheme == .dark ? .white : Color.primary.opacity(0.78)
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    var isSelected = false
    var position: Int?
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            Group {
                if let position {
                    TripMapOrderMarker(position: position)
                } else {
                    DefaultPOIMarker(
                        systemName: place.status == .visited ? "checkmark" : place.category.mapMarkerSymbol,
                        tint: SaveAtlasPalette.forest,
                        state: .saved,
                        isSelected: isSelected
                    )
                }
            }
            .scaleEffect(isSelected ? 1.08 : 1)
            .overlay {
                if isSelected {
                    // Map Stamp emphasis stays honey (DESIGN.md), on the
                    // Atlas palette.
                    Circle()
                        .stroke(SaveAtlasPalette.honey.opacity(0.86), lineWidth: 3)
                        .frame(width: 40, height: 40)
                        .shadow(color: SaveAtlasPalette.honey.opacity(0.28), radius: 5)
                }
            }
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 10 : 0)
        .accessibilityLabel(languageSettings.localized(english: "\(place.name) Map Stamp", traditionalChinese: "\(place.name) 地圖章"))
        .accessibilityIdentifier("map.pin.saved.\(place.id.uuidString)")
    }
}

private struct SocialPlaceMapPin: View {
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
                systemName: "person.2.fill",
                tint: place.category.mapMarkerTint,
                state: .shared,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "\(place.name) social place", traditionalChinese: "\(place.name) 社交地點"))
        .accessibilityHint(place.socialSignal?.displayText ?? languageSettings.localized(english: "Opens a place from your social map", traditionalChinese: "打開社交地圖裡的地點"))
        .accessibilityIdentifier("map.pin.social.\(place.id.uuidString)")
    }
}

private struct ReviewCandidateMapPin: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let candidate: PlaceReviewCandidate
    var isSelected = false
    let onTap: () -> Void

    var body: some View {
        Button {
            SaveHaptics.select()
            onTap()
        } label: {
            DefaultPOIMarker(
                systemName: candidate.inferredCategory.iconName,
                tint: SaveAtlasPalette.forest,
                state: .review,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "\(candidate.name) Review Candidate", traditionalChinese: "\(candidate.name) 待確認地點"))
        .accessibilityHint(languageSettings.localized(english: "Opens the Review Candidate before saving it as a Map Stamp", traditionalChinese: "先打開待確認地點，再存成地圖章"))
        .accessibilityIdentifier("map.pin.review.\(candidate.id.uuidString)")
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
                systemName: candidate.category?.mapMarkerSymbol ?? "mappin",
                tint: candidate.category?.mapMarkerTint ?? .saveCocoa,
                state: .publicResult,
                isSelected: isSelected
            )
            .scaleEffect(isSelected ? 1.18 : 1)
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 10 : 0)
        .accessibilityLabel(languageSettings.localized(english: "\(candidate.title) Unsaved Candidate", traditionalChinese: "\(candidate.title) 未保存候選地點"))
        .accessibilityHint(languageSettings.localized(english: "Opens this visible map place before saving it as a Map Stamp", traditionalChinese: "打開這個地圖候選地點，確認後再存成地圖章"))
        .accessibilityIdentifier("map.pin.unsaved.\(candidate.id)")
    }
}

private struct AtlasMapContextBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(SaveAtlasType.display(13))
        }
        .foregroundStyle(SaveAtlasPalette.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
        .background(SaveAtlasPalette.mint.opacity(0.94), in: Capsule())
        .overlay {
            Capsule()
                .stroke(SaveAtlasPalette.forest.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.08), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }
}

private struct TripMapOrderMarker: View {
    let position: Int

    var body: some View {
        Text("\(position)")
            .font(SaveAtlasType.strong(17))
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(width: 38, height: 38)
            .background(SaveAtlasPalette.coral, in: Circle())
            .overlay {
                Circle()
                    .stroke(SaveAtlasPalette.paper, lineWidth: 3)
            }
            .shadow(color: SaveAtlasPalette.ink.opacity(0.18), radius: 3, y: 2)
            .frame(width: 44, height: 44)
    }
}

private struct DefaultPOIMarker: View {
    var systemName: String
    var tint: Color
    var state: MapMarkerState
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(state == .saved ? SaveAtlasPalette.forest : SaveAtlasPalette.paper)
                .frame(width: markerSize, height: markerSize)
                .overlay {
                    Circle().stroke(
                        state == .saved ? SaveAtlasPalette.paper : state.strokeColor,
                        style: StrokeStyle(lineWidth: state == .saved ? 2 : 1.5, dash: state == .review ? [3, 2] : [])
                    )
                }
            Image(systemName: state == .review ? "questionmark" : systemName)
                .font(.system(size: isSelected ? 15 : 12, weight: .semibold))
                .foregroundStyle(state == .saved ? SaveAtlasPalette.paper : tint)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(isSelected ? 0.16 : 0.08), radius: 2, y: 1)
        // Every state keeps its symbol at rest and a 44pt touch region.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    private var markerSize: CGFloat {
        if isSelected { return 34 }
        return state == .saved ? 26 : 22
    }
}

private enum MapMarkerState: Equatable {
    case saved
    case shared
    case review
    case publicResult

    var strokeColor: Color {
        switch self {
        case .saved:
            return SaveAtlasPalette.mint
        case .shared:
            return SaveAtlasPalette.kraft
        case .review:
            return SaveAtlasPalette.sky
        case .publicResult:
            return SaveAtlasPalette.line
        }
    }
}

private extension PlaceCategory {
    var mapMarkerSymbol: String {
        self == .attraction ? "binoculars.fill" : iconName
    }

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
