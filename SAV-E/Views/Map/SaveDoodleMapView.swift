import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// HoP 298-2: coral numbered Savvy pins on saved places only.
/// Light `#F26B4A` / dark `#D97861`, white number, `stampRed` once visited.
/// Flip `current` to `.appleDefault` for unstyled Apple pins without
/// rewriting the Map surface, header, or place sheet.
enum SaveDoodleMapPinStyle {
    enum Kind: String {
        case coralNumbered
        case appleDefault
    }

    static var current: Kind = .coralNumbered
}

/// Peek-card / saved-pin open during Review exact-search.
/// ContentView and the Map sheet share this so a tap retires the clue
/// instead of skipping to a generic stamp open.
enum SaveDoodleMapPeekOpen {
    enum Outcome: Equatable {
        case openStamp(UUID)
        case resolvedStamp(UUID)
        case stayOnSearch
    }

    @MainActor
    static func perform(
        place: Place,
        mapViewModel: MapViewModel,
        isExactSearchSessionActive: Bool,
        exactSearchClueID: UUID?,
        restoreResolution: () -> Void,
        isCurrentRequest: () -> Bool
    ) async -> Outcome {
        guard isCurrentRequest() else { return .stayOnSearch }
        restoreResolution()
        let shouldResolve = isExactSearchSessionActive
            || mapViewModel.hasActiveExactSearchResolution
            || exactSearchClueID != nil
        guard shouldResolve else { return .openStamp(place.id) }
        restoreResolution()
        if let exactSearchClueID,
           let activeID = mapViewModel.activeExactSearchClueID,
           activeID != exactSearchClueID {
            return .stayOnSearch
        }
        let resolved = await mapViewModel.chooseSavedStampFromExactSearch(place)
        // Persistence may finish after the user closes or replaces this search.
        // Never let its completion navigate or clear the new UI session.
        guard isCurrentRequest() else { return .stayOnSearch }
        if let resolved {
            return .resolvedStamp(resolved.id)
        }
        return .stayOnSearch
    }
}

/// Unsaved `showMapCandidatesOnMap` Marker tap. Selecting the candidate
/// is what ContentView uses to reopen the receipt drawer.
enum SaveDoodleMapUnsavedMarker {
    @MainActor
    static func select(_ candidate: SaveMapCandidate, on mapViewModel: MapViewModel) {
        mapViewModel.selectMapCandidate(candidate)
    }
}

/// Product Map tab: default Apple MapKit (`.standard`, emphasis `.automatic`)
/// with native Apple tile colors. Saved places use Savvy pins;
/// unsaved keep the native Marker. No tile-town, no paper wash.
struct SaveDoodleMapView: View {
    @ObservedObject var mapViewModel: MapViewModel
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void
    let shouldFocusOnUserLocation: Bool

    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared
    @StateObject private var checkIns = SaveDoodleCheckInStore()
    @State private var showsCityPicker = false
    @State private var stampPulse = false
    @State private var visitError: String?

    var body: some View {
        let followsHomeFilter = session.mapFollowsHomeFilter
        return VStack(spacing: 0) {
            header(followsHomeFilter: followsHomeFilter)
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.xs)
                .padding(.bottom, SaveSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaveAtlasPalette.paper)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map.headerBand")

            ZStack(alignment: .top) {
                mapCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !providerBackedPlaces.isEmpty {
                    providerBackedPlacesControl
                }

                if mapViewModel.showsLocationDeniedNotice {
                    SaveLocationDeniedNotice(
                        onOpenSettings: openSystemSettings,
                        onDismiss: {
                            withAnimation(SaveTheme.Motion.standardSpring) {
                                mapViewModel.showsLocationDeniedNotice = false
                            }
                        }
                    )
                    .padding(.top, SaveSpace.sm)
                    .padding(.horizontal, SaveLayout.screenMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .background(SaveAtlasPalette.paper)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if mapViewModel.selectedPlace == nil {
                    HStack {
                        Spacer(minLength: 0)
                        locateButton
                    }
                    .padding(.horizontal, SaveLayout.screenMargin)
                }

                // Keep one card identity when switching pins. Replacing the card
                // would leave two actionable sheets during the removal transition.
                ZStack(alignment: .bottom) {
                    if let place = mapViewModel.selectedPlace {
                        placeSheet(place)
                            .transition(peekTransition)
                    }
                }
                .padding(.horizontal, SaveLayout.screenMargin)
                .allowsHitTesting(mapViewModel.selectedPlace != nil)
                .accessibilityHidden(mapViewModel.selectedPlace == nil)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.15)
                        : .spring(response: 0.38, dampingFraction: 0.78),
                    value: mapViewModel.selectedPlace != nil
                )
            }
            .padding(.bottom, bottomChromeClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            _ = onPlanAroundPlace
            mapViewModel.seedUITestUnsavedCandidateIfNeeded()
            selectParityPlaceIfNeeded()
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.places.map(\.id)) { _, _ in
            selectParityPlaceIfNeeded()
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.selectedPlace?.id) { _, _ in
            fitVisiblePlaces()
        }
        .onChange(of: session.lens) { _, _ in
            if followsHomeFilter {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: session.city) { _, _ in
            if followsHomeFilter {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: session.mapFollowsHomeFilter) { _, follows in
            if follows {
                onClearSelection()
            }
            fitVisiblePlaces()
        }
        .onChange(of: mapViewModel.selectedMapFeature) { _, feature in
            mapViewModel.selectMapFeature(feature)
        }
        .onChange(of: locationService.currentLocation?.coordinate.latitude) { _, _ in
            guard mapViewModel.selectedPlace == nil else { return }
            guard cityOpeningPins().isEmpty else { return }
            fitVisiblePlaces()
        }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
        .task(id: shouldFocusOnUserLocation) {
            guard shouldFocusOnUserLocation else { return }
            await mapViewModel.focusOnUserLocationOnLaunch()
            // Location request must not hide city stamps behind a tight
            // user-span. Refit so every saved pin in the city stays visible.
            fitVisiblePlaces()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var mapCanvas: some View {
        Map(position: $mapViewModel.cameraPosition, selection: $mapViewModel.selectedMapFeature) {
            UserAnnotation()

            if SaveDoodleMapPinStyle.current == .appleDefault {
                ForEach(displayedListedPlaces) { item in
                    if item.place.isMapKitMappable {
                        Marker(item.place.name, coordinate: item.place.coordinate)
                    }
                }
            } else {
                ForEach(displayedListedPlaces) { item in
                    if item.place.isMapKitMappable {
                        Annotation("", coordinate: item.place.coordinate, anchor: .bottom) {
                            SaveDoodleCoralPin(
                                index: item.index,
                                title: item.place.name,
                                visited: item.place.status == .visited,
                                isSelected: mapViewModel.selectedPlace?.id == item.place.id,
                                dimmed: mapViewModel.selectedPlace != nil
                                    && mapViewModel.selectedPlace?.id != item.place.id
                            ) {
                                mapViewModel.selectPlace(item.place)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                mapViewModel.selectedPlace?.id == item.place.id
                                    ? "Selected Map Stamp, \(item.place.name)"
                                    : "\(item.place.status == .visited ? "Visited Map Stamp" : "Map Stamp"), \(item.place.name)"
                            )
                            .accessibilityIdentifier("map.tilePin.\(item.place.id.uuidString)")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }

            ForEach(nativeUnsavedCandidates) { candidate in
                Marker(candidate.title, coordinate: candidate.coordinate)
                Annotation("", coordinate: candidate.coordinate, anchor: .bottom) {
                    Button {
                        SaveDoodleMapUnsavedMarker.select(candidate, on: mapViewModel)
                    } label: {
                        Color.clear.frame(width: 44, height: 56)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("map.unsaved.\(candidate.id)")
                    .accessibilityLabel(candidate.title)
                    .accessibilityAddTraits(.isButton)
                }
            }

            if let polyline = mapViewModel.routePolyline {
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
        .mapStyle(.standard(emphasis: .automatic))
        .mapFeatureSelectionDisabled { feature in
            feature.kind != .pointOfInterest
        }
        .mapControls {
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            mapViewModel.updateVisibleMapRegion(context.region)
        }
        .accessibilityIdentifier("map.liveSurface")
    }

    @ViewBuilder
    private func header(followsHomeFilter: Bool) -> some View {
        VStack(alignment: .leading, spacing: SaveSpace.sm) {
            Button { showsCityPicker = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: SaveSpace.tight) {
                    VStack(alignment: .leading, spacing: 0) {
                        SaveDisplayTitle(
                            text: cityTitle,
                            pointSize: 32,
                            relativeTo: .title,
                            locksPointSize: true
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(1)
                        .fixedSize(horizontal: false, vertical: true)
                        Capsule()
                            .fill(SaveAtlasPalette.coral)
                            .frame(height: 2)
                            .padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("▾")
                        .font(SaveAtlasType.body(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .frame(minHeight: SaveLayout.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                languageSettings.localized(english: "Choose city", traditionalChinese: "選擇城市")
                    + ", " + cityTitle
            )
            .accessibilityIdentifier("map.city")
            .accessibilityAddTraits(.isButton)

            HStack {
                Spacer(minLength: 0)
                eatGoRail
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityValue(followsHomeFilter ? "filtered" : "all")
    }

    private var eatGoRail: some View {
        HStack(spacing: SaveSpace.xs) {
            ForEach(SaveDoodleLens.allCases) { item in
                let selected = session.lens == item
                Button {
                    SaveHaptics.select()
                    session.lens = item
                    session.mapFollowsHomeFilter = true
                    onClearSelection()
                    fitVisiblePlaces()
                } label: {
                    Text(item.title(language: languageSettings.language))
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(selected ? Color.white : SaveAtlasPalette.ink)
                        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.chipHeight)
                        .padding(.horizontal, SaveSpace.md)
                        .background(
                            selected ? SaveAtlasPalette.coral : Color.clear,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    selected ? Color.clear : SaveAtlasPalette.ink,
                                    lineWidth: SaveAtlasPalette.strokeWidth
                                )
                        }
                        .frame(minHeight: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: SaveLayout.minTap)
                .accessibilityIdentifier(item.mapAccessibilityIdentifier)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.eatGo")
    }

    private var peekTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top)
                .combined(with: .offset(y: SaveSpace.sm))
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    private func placeSheet(_ place: Place) -> some View {
        let listed = displayedListedPlaces.first(where: { $0.place.id == place.id })
        let visited = place.status == .visited || checkIns.visitCount(for: place.id) > 0
        let checkedInToday = checkIns.hasCheckedInToday(placeID: place.id)
        return VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(SaveAtlasPalette.line)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Button(action: onClearSelection) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 28, height: 28)
                        .background(SaveAtlasPalette.paper, in: Circle())
                        .overlay {
                            Circle().stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
                        }
                        .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Close place card", traditionalChinese: "關閉地點卡片"
                ))
                .accessibilityIdentifier("map.peek.close")
            }

            HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
                Button {
                    presentation.onOpenPlace(place.id.uuidString)
                    onClearSelection()
                } label: {
                    HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
                        ZStack {
                            SaveDoodleSticker(
                                category: place.category,
                                placeName: place.name,
                                visited: visited,
                                pointSize: SaveLayout.passportSlot,
                                boxSize: SaveLayout.passportSlot
                            )
                            if visited {
                                Circle()
                                    .stroke(SaveDoodle.stampRed, lineWidth: 2)
                                    .frame(
                                        width: SaveLayout.passportSlot,
                                        height: SaveLayout.passportSlot
                                    )
                                    .rotationEffect(.degrees(stampAngle(for: place.id)))
                                    .scaleEffect(stampPulse ? 1 : 0.82)
                            }
                        }
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                            Text(place.name)
                                .font(SaveAtlasType.strong(20, relativeTo: .title3))
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("map.peek.name")
                            Text(metaText(for: place, listed: listed))
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.muted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("map.peek.subtitle")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.name)
                .accessibilityIdentifier("map.peek.card")
            }

            HStack(spacing: SaveSpace.sm) {
                Button {
                    SaveHaptics.tap()
                    openDirections(for: place)
                } label: {
                    Text(languageSettings.localized(english: "Directions", traditionalChinese: "導航"))
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                        .background(SaveAtlasPalette.coral, in: RoundedRectangle(
                            cornerRadius: SaveAtlasPalette.cardRadius,
                            style: .continuous
                        ))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.directions")

                if checkedInToday {
                    Button {
                        undoCheckIn(place)
                    } label: {
                        Text(languageSettings.localized(english: "Undo visit", traditionalChinese: "撤銷打卡"))
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                            .background(
                                SaveAtlasPalette.paper,
                                in: RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                                .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(checkIns.isPersisting(placeID: place.id))
                    .accessibilityIdentifier("map.card.beenHere.undo")
                } else {
                    Button {
                        performCheckIn(place)
                    } label: {
                        Text(languageSettings.localized(english: "I've been here", traditionalChinese: "我來過了"))
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                            .background(
                                SaveAtlasPalette.paper,
                                in: RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: SaveAtlasPalette.cardRadius,
                                    style: .continuous
                                )
                                .stroke(SaveAtlasPalette.ink, lineWidth: SaveAtlasPalette.strokeWidth)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(checkIns.isPersisting(placeID: place.id))
                    .accessibilityIdentifier("map.card.beenHere")
                }
                if let visitError {
                    Text(visitError)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("map.card.visitError")
                }
            }
            .padding(.top, SaveSpace.md)
        }
        .padding(.horizontal, SaveLayout.screenMargin)
        .padding(.bottom, SaveSpace.md)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
        .shadow(
            color: SaveAtlasPalette.ink.opacity(SaveTheme.Elevation.cardOpacity),
            radius: SaveTheme.Elevation.cardRadius,
            y: SaveTheme.Elevation.cardY
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.placeSheet")
        .accessibilityAction(.escape, onClearSelection)
    }

    private var locateButton: some View {
        Button {
            SaveHaptics.tap()
            Task { await mapViewModel.focusOnUserLocation() }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 48, height: 48)
                .background(SaveAtlasPalette.paper, in: Circle())
                .overlay {
                    Circle().stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(
            english: "Center map on current location",
            traditionalChinese: "將地圖移到目前位置"
        ))
        .accessibilityIdentifier("map.currentLocation")
    }

    private var cityPicker: some View {
        NavigationStack {
            List {
                if !locationService.isAuthorizationDenied {
                    Button {
                        session.city = .nearYou
                        session.mapFollowsHomeFilter = true
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text(languageSettings.localized(
                                english: "Near you (current location)",
                                traditionalChinese: "附近（目前位置）"
                            ))
                            Spacer()
                            if case .nearYou = session.city {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("map.city.nearYou")
                }
                ForEach(cityGroups) { group in
                    Button {
                        session.city = .city(group.id)
                        session.mapFollowsHomeFilter = true
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text("\(group.displayName(language: languageSettings.language)) \(group.count)")
                            Spacer()
                            if case .city(let id) = resolvedSelection, id == group.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("map.city.\(group.id)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SaveAtlasPalette.paper)
            .navigationTitle(languageSettings.localized(english: "City", traditionalChinese: "城市"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageSettings.localized(english: "Close", traditionalChinese: "關閉")) {
                        showsCityPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var displayedListedPlaces: [SaveDoodleListedPlace] {
        SaveDoodleHomeCatalog.listedPlaces(
            from: mapViewModel.places,
            lens: session.lens,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied,
            including: mapViewModel.selectedPlace
        )
    }

    /// HoP 298-10: unsaved search/POI results stay native Markers.
    /// Saved places never use this path — they keep the coral Savvy pin.
    private var nativeUnsavedCandidates: [SaveMapCandidate] {
        let savedIDs = Set(mapViewModel.places.map(\.id.uuidString))
        var seen = Set<String>()
        var result: [SaveMapCandidate] = []
        for candidate in mapViewModel.visibleMapCandidates + [mapViewModel.selectedMapCandidate].compactMap({ $0 }) {
            if savedIDs.contains(candidate.id) { continue }
            if mapViewModel.places.contains(where: { $0.matchesMapFeature(title: candidate.title, coordinate: candidate.coordinate) }) {
                continue
            }
            guard seen.insert(candidate.id).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private var resolvedSelection: SaveDoodleCitySelection {
        SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: mapViewModel.places)
    }

    private var cityTitle: String {
        switch resolvedSelection {
        case .nearYou:
            return languageSettings.localized(english: "Near you", traditionalChinese: "附近")
        case .city(let id):
            if let group = cityGroups.first(where: { $0.id == id }) {
                return group.displayName(language: languageSettings.language)
            }
            return SaveHomeSearch.cityLabel(
                for: id,
                traditionalChinese: languageSettings.language == .traditionalChinese
            ) ?? id
        }
    }

    private var bottomChromeClearance: CGFloat {
        if mapViewModel.selectedPlace != nil {
            // Search shelf is hidden. Sit the paper sheet on the 62pt tab bar.
            return AtlasTabBarMetrics.height + SaveSpace.md
        }
        // Locate must stay above the collapsed 64pt search shelf (test: maxY
        // <= shelf.minY - 4). Original clearance 160 clears that band.
        return 160
    }

    private func selectParityPlaceIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--uitest-map-place-selected") else { return }
        guard mapViewModel.selectedPlace == nil else { return }
        let taipei = mapViewModel.places.first { place in
            abs(place.latitude - 25.04) < 0.35 && abs(place.longitude - 121.56) < 0.35
        }
        mapViewModel.selectedPlace = taipei ?? mapViewModel.places.first
#endif
    }

    private func metaText(for place: Place, listed: SaveDoodleListedPlace?) -> String {
        let lens = SaveDoodleHomeCatalog.lens(for: place.category)
            .title(language: languageSettings.language)
        if let meters = listed?.distance {
            return "\(lens) · \(SaveDoodleHomeCatalog.distanceText(meters))"
        }
        if let area = SaveDoodleHomeCatalog.cityDisplayName(
            for: place,
            language: languageSettings.language
        ) {
            return "\(lens) · \(area)"
        }
        return lens
    }

    private func openDirections(for place: Place) {
        if let providerURL = place.providerMapDestinationURL {
            openURL(providerURL)
            return
        }
        NavigationService.navigate(to: place.coordinate, name: place.name, mode: .walking)
    }

    private func performCheckIn(_ place: Place) {
        var updated = place
        updated.status = .visited
        Task {
            let accepted = await checkIns.applyCheckIn(
                placeID: place.id,
                priorStatus: place.status
            ) {
                try await mapViewModel.updatePlace(updated)
            }
            guard accepted else {
                visitError = languageSettings.localized(
                    english: "Couldn’t update this place. Please try again.",
                    traditionalChinese: "暫時無法更新這個地點，請再試一次。"
                )
                return
            }
            visitError = nil
            SaveHaptics.stamp()
            stampPulse = false
            withAnimation(SaveTheme.Motion.stampSpring) {
                stampPulse = true
            }
        }
    }

    private func undoCheckIn(_ place: Place) {
        Task {
            let accepted = await checkIns.applyUndo(placeID: place.id) { restoreStatus in
                guard place.status != restoreStatus else { return }
                var updated = place
                updated.status = restoreStatus
                try await mapViewModel.updatePlace(updated)
            }
            guard accepted else {
                visitError = languageSettings.localized(
                    english: "Couldn’t undo this visit. Please try again.",
                    traditionalChinese: "暫時無法撤銷這次打卡，請再試一次。"
                )
                return
            }
            visitError = nil
            stampPulse = false
        }
    }

    private func stampAngle(for id: UUID) -> Double {
        var hasher = Hasher()
        hasher.combine(id)
        return Double(abs(hasher.finalize()) % 13) - 6
    }

    private func fitVisiblePlaces() {
        // Show-on-Map for a collaborative list already aimed the camera.
        // A single mappable stop sets one routeCoordinate and no polyline.
        // Do not snap back to personal city stamps.
        if !mapViewModel.routeCoordinates.isEmpty {
            return
        }
        if let selected = mapViewModel.selectedPlace, selected.isMapKitMappable {
            mapViewModel.cameraPosition = .region(
                MKCoordinateRegion(
                    center: selected.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
            return
        }
        let pins = cityOpeningPins()
        if !pins.isEmpty {
            mapViewModel.cameraPosition = .region(Self.region(fitting: pins))
            return
        }
        if let fallback = cityOpeningFallback() {
            mapViewModel.cameraPosition = .region(
                MKCoordinateRegion(
                    center: fallback,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }

    /// HoP 298-3 / 298-7: fit the same saved Eat/Go + city set Home lists.
    /// Unsaved candidates stay native Markers and are not in this fit.
    /// Never fit the worldwide set — that opens over Europe/Africa.
    private func cityOpeningPins() -> [CLLocationCoordinate2D] {
        let denied = locationService.isAuthorizationDenied
        let location = denied ? nil : locationService.currentLocation
        var selection = SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: denied
        )
        if case .nearYou = selection, location == nil {
            let newest = mapViewModel.places.sorted(by: SaveDoodleHomeCatalog.moreRecent).first
            if let newest, let id = SaveDoodleHomeCatalog.cityID(for: newest) {
                selection = .city(id)
            }
        }
        var coords: [CLLocationCoordinate2D] = []
        for place in SaveDoodleHomeCatalog.visiblePlaces(
            from: mapViewModel.places,
            lens: session.lens,
            selection: selection,
            location: location,
            locationDenied: denied
        ) where place.isMapKitMappable {
            coords.append(place.coordinate)
        }
        if !coords.isEmpty {
            return coords
        }
        guard let cityID = openingCityID(denied: denied, location: location) else {
            return addresslessOpeningPins(location: location)
        }
        return mapViewModel.places
            .filter { SaveDoodleHomeCatalog.cityID(for: $0) == cityID && $0.isMapKitMappable }
            .map(\.coordinate)
    }

    /// Coordinate-only imports have no city id. Fit the local cluster, or
    /// one fallback pin — never the worldwide set capped at 0.45°.
    private func addresslessOpeningPins(location: CLLocation?) -> [CLLocationCoordinate2D] {
        let mappable = mapViewModel.places.filter(\.isMapKitMappable)
        if let location {
            let nearby = mappable.filter {
                SaveDoodleHomeCatalog.distance(from: location, to: $0)
                    .map { $0 <= SaveDoodleHomeCatalog.nearbyRadius } ?? false
            }
            if !nearby.isEmpty {
                return nearby.map(\.coordinate)
            }
            if let nearest = mappable.min(by: { lhs, rhs in
                let left = SaveDoodleHomeCatalog.distance(from: location, to: lhs) ?? .infinity
                let right = SaveDoodleHomeCatalog.distance(from: location, to: rhs) ?? .infinity
                return left < right
            }) {
                return [nearest.coordinate]
            }
        }
        if let newest = mappable.sorted(by: SaveDoodleHomeCatalog.moreRecent).first {
            return [newest.coordinate]
        }
        return []
    }

    private func openingCityID(denied: Bool, location: CLLocation?) -> String? {
        let selection = SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: denied
        )
        switch selection {
        case .city(let id):
            return id
        case .nearYou:
            if let location {
                let nearest = mapViewModel.places
                    .compactMap { place -> (Place, CLLocationDistance)? in
                        guard let meters = SaveDoodleHomeCatalog.distance(from: location, to: place) else {
                            return nil
                        }
                        return (place, meters)
                    }
                    .min(by: { $0.1 < $1.1 })
                if let nearest, let id = SaveDoodleHomeCatalog.cityID(for: nearest.0) {
                    return id
                }
            }
            return mapViewModel.places.sorted(by: SaveDoodleHomeCatalog.moreRecent).first
                .flatMap { SaveDoodleHomeCatalog.cityID(for: $0) }
        }
    }

    private var providerBackedPlaces: [Place] {
        mapViewModel.places.filter {
            !$0.isMapKitMappable && $0.providerMapDestinationURL != nil
        }
    }

    @ViewBuilder
    private var providerBackedPlacesControl: some View {
        let chip = Label(
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

        Group {
            if providerBackedPlaces.count == 1, let place = providerBackedPlaces.first {
                Button {
                    mapViewModel.selectPlace(place)
                } label: {
                    chip
                }
            } else {
                Menu {
                    ForEach(providerBackedPlaces) { place in
                        Button(place.name) {
                            mapViewModel.selectPlace(place)
                        }
                        .accessibilityIdentifier("map.providerBackedPlaces.\(place.id.uuidString)")
                    }
                } label: {
                    chip
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, SaveLayout.screenMargin)
        .padding(.top, SaveSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("map.providerBackedPlaces")
    }

    private func cityOpeningFallback() -> CLLocationCoordinate2D? {
        let denied = locationService.isAuthorizationDenied
        let selection = SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: mapViewModel.places,
            locationDenied: denied
        )
        let cityID: String?
        switch selection {
        case .city(let id):
            cityID = id
        case .nearYou:
            if !denied, let coordinate = locationService.currentLocation?.coordinate {
                return coordinate
            }
            cityID = mapViewModel.places.compactMap { SaveDoodleHomeCatalog.cityID(for: $0) }.first
        }
        if let cityID {
            let inCity = mapViewModel.places.first {
                SaveDoodleHomeCatalog.cityID(for: $0) == cityID && $0.isMapKitMappable
            }
            if let inCity {
                return inCity.coordinate
            }
        }
        return locationService.currentLocation?.coordinate
    }

    private static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 0.012), 0.45),
            longitudeDelta: min(max((maxLon - minLon) * 1.6, 0.012), 0.45)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct SaveDoodleCoralPin: View {
    let index: Int
    let title: String
    let visited: Bool
    let isSelected: Bool
    let dimmed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                ZStack {
                    SaveDoodleLollipopShape()
                        .fill(pinColor)
                    Text("\(index)")
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(Color.white)
                        .offset(y: -stemHeight / 2)
                }
                .frame(width: headDiameter, height: pinHeight)

                if isSelected {
                    Text(title)
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .padding(.horizontal, SaveSpace.xs)
                        .padding(.vertical, SaveSpace.tight)
                        .background(SaveAtlasPalette.kraft, in: Capsule())
                        .lineLimit(1)
                        .offset(y: -(pinHeight + SaveSpace.tight))
                }
            }
            .opacity(dimmed ? 0.6 : 1)
            .animation(SaveTheme.Motion.standardSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap, alignment: .bottom)
        .contentShape(Rectangle())
    }

    private var pinColor: Color {
        visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral
    }

    private var headDiameter: CGFloat {
        isSelected ? 32 : 26
    }

    private var stemHeight: CGFloat {
        isSelected ? 12 : 10
    }

    private var pinHeight: CGFloat {
        headDiameter + stemHeight
    }
}

/// HoP 298-2: numbered coral lollipop. Fill stays solid when selected.
nonisolated struct SaveDoodleLollipopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let stemWidth = max(2.5, rect.width * 0.14)
        let stemHeight = max(8, rect.height * 0.28)
        let headDiameter = min(rect.width, rect.height - stemHeight)
        let radius = headDiameter / 2
        let center = CGPoint(x: rect.midX, y: radius)
        let halfStem = stemWidth / 2
        let attach = min(radius - 0.5, max(0, sqrt(max(0, radius * radius - halfStem * halfStem))))
        let start = Angle.radians(Double.pi - asin(Double(min(1, halfStem / max(radius, 0.1)))))
        let end = Angle.radians(asin(Double(min(1, halfStem / max(radius, 0.1)))))
        var path = Path()
        path.move(to: CGPoint(x: center.x - halfStem, y: rect.maxY))
        path.addLine(to: CGPoint(x: center.x - halfStem, y: center.y + attach))
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        path.addLine(to: CGPoint(x: center.x + halfStem, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
