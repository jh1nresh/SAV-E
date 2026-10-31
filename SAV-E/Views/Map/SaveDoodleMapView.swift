import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Native saved markers use coral (light `#F26B4A` / dark `#D97861`),
/// with `stampRed` once visited. Photo pins are deferred.
enum SaveDoodleMapPinStyle {
    enum Kind: String {
        case coralNumbered
        case appleDefault
    }

    static var current: Kind = .appleDefault
}

/// Native markers and Apple POIs share selection without custom hit-test overlays.
enum SaveDoodleNativeMapSelection: MapSelectable {
    case saved(UUID)
    case candidate(String)
    case nativeFeature(MapFeature?)

    init(_ feature: MapFeature?) { self = .nativeFeature(feature) }
    var feature: MapFeature? {
        if case .nativeFeature(let feature) = self { return feature }
        return nil
    }
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
        mapViewModel.selectMapCandidate(candidate, focusingCamera: false)
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
    // Camera gestures stay local: publishing every camera write invalidates the
    // root, drawer and all derived collection presentations while MapKit renders.
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastGestureCamera: MapCameraPosition?
    @State private var nativeMapSelection: SaveDoodleNativeMapSelection?
    @State private var showsCityPicker = false
    @State private var visitError: String?
    private static let collapsedChromeClearance: CGFloat = 160

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
                            withAnimation(reduceMotion ? nil : SaveTheme.Motion.standardSpring) {
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
                    }
                }
                .padding(.horizontal, SaveLayout.screenMargin)
                .allowsHitTesting(mapViewModel.selectedPlace != nil)
                .accessibilityHidden(mapViewModel.selectedPlace == nil)
            }
            .padding(.bottom, bottomChromeClearance)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onAppear {
            _ = onPlanAroundPlace
            mapViewModel.seedUITestUnsavedCandidateIfNeeded()
            selectParityPlaceIfNeeded()
            cameraPosition = mapViewModel.cameraPosition
            switch session.consumeMapEntry() {
            case .explicitCommand:
                session.mapHasEstablishedViewport = true
            case .changedFilters:
                onClearSelection()
                fitVisiblePlaces()
            case .restoreViewport:
                if session.shouldFitMapCollection(hasVisibleRegion: mapViewModel.visibleMapRegion != nil) {
                    fitVisiblePlaces(initialOpening: !session.mapFollowsHomeFilter)
                }
            }
            synchronizeNativeSavedSelection()
        }
        .onDisappear { session.recordMapFilters() }
        .onChange(of: mapViewModel.cameraPosition) { _, position in
            // A gesture publishes one snapshot on end. Do not feed that snapshot
            // back into MapKit; explicit commands still move the local camera.
            if position != lastGestureCamera {
                session.mapHasEstablishedViewport = true
                cameraPosition = position
            }
            lastGestureCamera = nil
        }
        .onChange(of: mapViewModel.places.map(\.id)) { _, _ in
            selectParityPlaceIfNeeded()
            synchronizeNativeSavedSelection()
            guard !session.mapHasEstablishedViewport, !cameraPosition.positionedByUser else { return }
            fitVisiblePlaces(initialOpening: !session.mapFollowsHomeFilter)
        }
        .onChange(of: mapViewModel.selectedPlace?.id) { _, _ in
            synchronizeNativeSavedSelection()
        }
        .onChange(of: mapViewModel.selectedMapCandidate?.id) { _, id in
            if id == nil, case .candidate? = nativeMapSelection { nativeMapSelection = nil }
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
                fitVisiblePlaces()
            }
        }
        .onChange(of: mapViewModel.selectedMapFeature) { _, feature in
            if feature == nil, case .nativeFeature? = nativeMapSelection { nativeMapSelection = nil }
            mapViewModel.selectMapFeature(feature)
        }
        .onChange(of: nativeMapSelection) { _, selection in
            switch selection {
            case .saved(let id):
                guard mapViewModel.selectedPlace?.id != id else { return }
                guard let place = mapViewModel.places.first(where: { $0.id == id }) else { return }
                mapViewModel.selectPlace(place)
            case .candidate(let id):
                guard let candidate = nativeUnsavedCandidates.first(where: { $0.id == id }) else { return }
                SaveDoodleMapUnsavedMarker.select(candidate, on: mapViewModel)
            case .nativeFeature(let feature):
                mapViewModel.selectedMapFeature = feature
            case nil: break
            }
        }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func synchronizeNativeSavedSelection() {
        // A Home handoff can select a stamp before Map exists. Tell MapKit
        // which native marker owns the card, including collocated places.
        if let selected = mapViewModel.selectedPlace,
           selected.isMapKitMappable,
           displayedListedPlaces.contains(where: { $0.place.id == selected.id }) {
            let selection = SaveDoodleNativeMapSelection.saved(selected.id)
            if nativeMapSelection != selection { nativeMapSelection = selection }
        } else if case .saved? = nativeMapSelection {
            nativeMapSelection = nil
        }
    }

    private var mapCanvas: some View {
        Map(position: $cameraPosition, selection: $nativeMapSelection) {
            UserAnnotation()

            if SaveDoodleMapPinStyle.current == .appleDefault {
                ForEach(Self.nativeSavedMarkers(displayedListedPlaces, selected: mapViewModel.selectedPlace)) { item in
                    if item.place.isMapKitMappable {
                        let state: SaveSearchObjectType = item.place.status == .visited ? .triedMemory : .savedPlace
                        let stateName = state.displayName(language: languageSettings.language)
                        // The marker title is the on-screen name. Status stays
                        // in accessibility so it is not drawn beside the pin.
                        Marker(coordinate: item.place.coordinate) {
                            Text(item.place.name)
                                .accessibilityLabel("\(item.place.name), \(stateName)")
                                .accessibilityValue(stateName)
                        }
                            .tint(item.place.status == .visited ? SaveDoodle.stampRed : SaveAtlasPalette.coral)
                            .tag(SaveDoodleNativeMapSelection.saved(item.place.id))
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
                let stateName = SaveSearchObjectType.mapVisibleUnsavedPlace.displayName(language: languageSettings.language)
                Marker(coordinate: candidate.coordinate) {
                    Text(candidate.title)
                        .accessibilityLabel("\(candidate.title), \(stateName)")
                        .accessibilityValue(stateName)
                }
                    .tag(SaveDoodleNativeMapSelection.candidate(candidate.id))
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
        // The root overlays its tab bar and collapsed search shelf. Give
        // MapKit their safe area so collection fitting keeps pins tappable.
        // Keep this constant when a place card replaces the shelf: changing
        // map insets on selection/dismissal would move the camera again.
        .safeAreaPadding(.bottom, Self.collapsedChromeClearance)
        .onMapCameraChange(frequency: .onEnd) { context in
            guard MapSearchGeography.isTrustworthyRegion(context.region) else { return }
            if cameraPosition.positionedByUser { session.mapHasEstablishedViewport = true }
            mapViewModel.updateVisibleMapRegion(context.region)
            let snapshot = MapCameraPosition.region(context.region)
            lastGestureCamera = snapshot
            mapViewModel.cameraPosition = snapshot
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
        .background {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .fill(SaveAtlasPalette.paper)
                .shadow(
                    color: SaveAtlasPalette.ink.opacity(SaveTheme.Elevation.cardOpacity),
                    radius: SaveTheme.Elevation.cardRadius,
                    y: SaveTheme.Elevation.cardY
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
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
        if !session.mapFollowsHomeFilter {
            return mapViewModel.places.enumerated().map { index, place in
                SaveDoodleListedPlace(place: place, index: index + 1, distance: nil)
            }
        }
        return SaveDoodleHomeCatalog.listedPlaces(
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
        return Self.collapsedChromeClearance
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
        }
    }

    private func stampAngle(for id: UUID) -> Double {
        var hasher = Hasher()
        hasher.combine(id)
        return Double(abs(hasher.finalize()) % 13) - 6
    }

    private func fitVisiblePlaces(initialOpening: Bool = false) {
        session.mapFollowsHomeFilter = !initialOpening
        // Show-on-Map for a collaborative list already aimed the camera.
        // A single mappable stop sets one routeCoordinate and no polyline.
        // Do not snap back to personal city stamps.
        if !mapViewModel.routeCoordinates.isEmpty {
            return
        }
        if let selected = mapViewModel.selectedPlace, selected.isMapKitMappable {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: selected.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
            session.mapHasEstablishedViewport = true
            return
        }
        if initialOpening {
            // First entry frames the entire saved collection. Late location
            // updates must not replace this viewport; locate is an explicit action.
            let pins = mapViewModel.places.filter(\.isMapKitMappable).map(\.coordinate)
            let fallback = locationService.isAuthorizationDenied ? nil : locationService.currentLocation?.coordinate
            cameraPosition = .region(Self.region(fitting: pins, fallback: fallback))
            session.mapHasEstablishedViewport = !pins.isEmpty
            return
        }
        let pins = cityOpeningPins()
        if !pins.isEmpty {
            cameraPosition = .region(Self.region(fitting: pins))
            session.mapHasEstablishedViewport = true
            return
        }
        if let fallback = cityOpeningFallback() {
            cameraPosition = .region(
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

    static func nativeSavedMarkers(
        _ places: [SaveDoodleListedPlace],
        selected: Place?
    ) -> [SaveDoodleListedPlace] {
        guard let selected, selected.isMapKitMappable,
              places.contains(where: { $0.id == selected.id }) else { return places }
        // MapKit enlarges the selected native marker. A second saved marker at
        // that exact coordinate must not peek out underneath it. Keep the saved
        // collection intact and restore those markers when the card closes.
        return places.filter { item in
            item.id == selected.id
                || item.place.latitude != selected.latitude
                || item.place.longitude != selected.longitude
        }
    }

    static func region(
        fitting coordinates: [CLLocationCoordinate2D],
        fallback: CLLocationCoordinate2D? = nil
    ) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: fallback ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
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
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 0.012), 180),
            longitudeDelta: min(max((maxLon - minLon) * 1.6, 0.012), 360)
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
