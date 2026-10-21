import CoreLocation
import MapKit
import SwiftUI

/// Product Map tab: default Apple MapKit + coral photo pins (HoP 2026-10-21).
/// P14: only confirmed saved Map Stamps get Savvy pins. Unsaved places stay
/// as Apple native POIs. Home peek stays tile-town. Shadows/springs stay on
/// pins, the callout, and the delayed camera move — not on the wordmark,
/// lenses, or locate control.
struct SaveMapPhotoPinsRoot: View {
    @ObservedObject var mapViewModel: MapViewModel
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    let onPlanAroundPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var locationService = LocationService.shared
    @ObservedObject private var visits = SavvyMapVisitStore.shared
    @State private var lens: SaveTileTownMapLens = .saved
    @State private var latitudeDelta: CLLocationDegrees = 0.04
    @State private var liveCamera = MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        distance: 4_000,
        heading: 0,
        pitch: 0
    )
    @State private var showsBadge = false
    @State private var pinPoint: CGPoint?
    @State private var session = SavvyMapCardSession()
    @State private var editingNote = false
    @State private var draftNote = ""
    @State private var badgeTick: Int = 0
    @State private var ignoreMapTapUntil = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                mapCanvas(in: geo)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    SaveDisplayTitle(text: "Savvy", pointSize: 28)
                        .padding(.horizontal, 16)
                        .padding(.top, AtlasMetrics.statusBarHeight)
                        .accessibilityIdentifier("map.wordmark")

                    lensRail
                        .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
                .allowsHitTesting(true)

                locateButton
                    .padding(.trailing, 14)
                    .padding(.top, AtlasMetrics.statusBarHeight + 58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if mapViewModel.showsLocationDeniedNotice {
                    VStack {
                        SaveLocationDeniedNotice(
                            onOpenSettings: openSystemSettings,
                            onDismiss: { mapViewModel.showsLocationDeniedNotice = false }
                        )
                        .padding(.top, AtlasMetrics.statusBarHeight + 12)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .zIndex(3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: lens) { _, newLens in
            if newLens == .friends {
                mapViewModel.selectSocialLens(.forYou)
            }
        }
        .onChange(of: mapViewModel.selectedPlace?.id) { _, id in
            if let id {
                openCard(for: id)
            } else if session.isOpen {
                collapseSelection(clearPlace: false)
            }
        }
        .onAppear {
            if let selected = mapViewModel.selectedPlace {
                session.select(selected.id)
            }
            fitCameraToVisiblePlacesIfNeeded()
        }
        .alert(
            languageSettings.localized(english: "My notes", traditionalChinese: "我的筆記"),
            isPresented: $editingNote
        ) {
            TextField(
                languageSettings.localized(english: "Write something…", traditionalChinese: "寫點什麼…"),
                text: $draftNote
            )
            Button(languageSettings.localized(english: "Save", traditionalChinese: "保存")) {
                Task { await saveNote() }
            }
            Button(languageSettings.localized(english: "Cancel", traditionalChinese: "取消"), role: .cancel) {}
        }
    }

    private func mapCanvas(in geo: GeometryProxy) -> some View {
        MapReader { proxy in
            Map(position: $mapViewModel.cameraPosition, selection: $mapViewModel.selectedMapFeature) {
#if DEBUG
                if ProcessInfo.processInfo.environment["SAVE_SKIP_LOCATION_PROMPT"] != "1"
                    && !ProcessInfo.processInfo.arguments.contains("--uitest-location-denied") {
                    UserAnnotation()
                }
#else
                UserAnnotation()
#endif

                ForEach(savvyPinPlaces) { place in
                    Annotation(
                        place.name,
                        coordinate: place.coordinate,
                        anchor: .bottom
                    ) {
                        SavvyMapPhotoPinView(
                            place: place,
                            showsBadge: showsBadge,
                            isVisited: isVisited(place),
                            isSelected: mapViewModel.selectedPlace?.id == place.id,
                            reduceMotion: reduceMotion
                        ) {
                            ignoreMapTapUntil = Date().addingTimeInterval(0.25)
                            mapViewModel.selectPlace(place)
                        }
                        .animation(
                            SavvyMapMotion.badge(reduceMotion: reduceMotion)
                                .delay(stagger(for: place, in: geo)),
                            value: showsBadge
                        )
                        .animation(SavvyMapMotion.badge(reduceMotion: reduceMotion), value: isVisited(place))
                    }
                }
            }
            .mapStyle(
                .standard(
                    elevation: .flat,
                    emphasis: .automatic,
                    pointsOfInterest: .all,
                    showsTraffic: false
                )
            )
            .mapFeatureSelectionDisabled { feature in
                feature.kind != .pointOfInterest
            }
            .mapControls {
                MapCompass()
            }
            .onChange(of: mapViewModel.selectedMapFeature) { _, feature in
                mapViewModel.selectMapFeature(feature)
            }
            .onMapCameraChange(frequency: .continuous) { context in
                latitudeDelta = context.region.span.latitudeDelta
                liveCamera = context.camera
                let nextBadge = SavvyMapZoomHysteresis.showsBadge(
                    latitudeDelta: latitudeDelta,
                    currentlyBadge: showsBadge
                )
                if nextBadge != showsBadge {
                    showsBadge = nextBadge
                    badgeTick += 1
                }
                if let selected = mapViewModel.selectedPlace {
                    pinPoint = proxy.convert(selected.coordinate, to: .local)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                mapViewModel.updateVisibleMapRegion(context.region)
            }
            .onTapGesture {
                guard Date() >= ignoreMapTapUntil, session.isOpen else { return }
                collapseSelection(clearPlace: true)
            }
            .accessibilityIdentifier("map.liveSurface")
            .overlay {
                if let place = savvyCardPlace {
                    let point = pinPoint ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.55)
                    SavvyMapPlaceCard(
                        visits: visits,
                        place: place,
                        userLocation: locationService.currentLocation,
                        isOpen: session.isOpen,
                        isFlipped: session.isFlipped,
                        reduceMotion: reduceMotion,
                        screenWidth: geo.size.width,
                        onFlip: flipCard,
                        onBeenHere: { Task { await markBeenHere(place) } },
                        onDirections: { openDirections(place) },
                        onOpenDetail: { presentation.onOpenPlace(place.id.uuidString) },
                        onEditNote: {
                            draftNote = place.userFacingNote ?? ""
                            editingNote = true
                        },
                        onCollapse: { collapseSelection(clearPlace: true) }
                    )
                    .position(
                        x: point.x,
                        y: point.y - SavvyMapPinMetrics.cardCenterOffsetY
                    )
                    .animation(SavvyMapMotion.cardOpen(reduceMotion: reduceMotion), value: session.isOpen)
                    .animation(
                        session.isFlipped
                            ? SavvyMapMotion.flipBack(reduceMotion: reduceMotion)
                            : SavvyMapMotion.flipFront(reduceMotion: reduceMotion),
                        value: session.isFlipped
                    )
                }
            }
        }
    }

    private var lensRail: some View {
        HStack(spacing: 8) {
            ForEach(SaveTileTownMapLens.allCases) { item in
                Button {
                    lens = item
                    if item != .saved, mapViewModel.selectedPlace != nil {
                        collapseSelection(clearPlace: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                        Text(item.title(language: languageSettings.language))
                    }
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(lens == item ? SaveAtlasPalette.coral : SaveAtlasPalette.forest)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                    .background(SaveAtlasPalette.paper, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(
                                lens == item ? SaveAtlasPalette.coral.opacity(0.55) : SaveAtlasPalette.kraft.opacity(0.7),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier)
                .accessibilityAddTraits(lens == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("map.lensRail")
    }

    private var locateButton: some View {
        Button {
            lens = .nearby
            Task { await mapViewModel.focusOnUserLocation() }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 48, height: 48)
                .background(SaveAtlasPalette.paper, in: Circle())
                .overlay {
                    Circle().stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(
            english: "Center map on current location",
            traditionalChinese: "將地圖移到目前位置"
        ))
        .accessibilityIdentifier("map.currentLocation")
    }

    /// P14: Savvy pins are confirmed Map Stamps only. Friends/social and
    /// unsaved candidates never become `SavvyMapPhotoPinView`s — Apple's
    /// native POI markers remain the only unsaved glyphs, and a POI tap
    /// goes through `selectMapFeature` into the existing save flow.
    private var savvyPinPlaces: [Place] {
        let confirmed = mapViewModel.places
        let lensPins: [Place]
        switch lens {
        case .saved:
            lensPins = confirmed.filter(\.isMapKitMappable)
        case .nearby:
            lensPins = SaveMapIntentFilter.places(
                confirmed,
                categories: [],
                intents: [.nearby],
                nearbyAnchor: locationService.currentLocation?.coordinate
                    ?? mapViewModel.nearbyFilterAnchor
            )
        case .friends:
            let social = mapViewModel.visibleSocialPlaces
            lensPins = SavvyMapStampPolicy.friendLensPins(
                confirmedPlaces: confirmed,
                socialPlaces: social.isEmpty ? mapViewModel.socialPlaces : social
            )
        }
        return SavvyMapStampPolicy.includingSelectedSavedPin(
            lensPins,
            selected: mapViewModel.selectedPlace,
            confirmedPlaces: confirmed
        )
    }

    private var savvyCardPlace: Place? {
        guard let place = mapViewModel.selectedPlace,
              SavvyMapStampPolicy.qualifiesForSavvyPin(
                place,
                confirmedPlaces: mapViewModel.places
              ) else {
            return nil
        }
        return place
    }

    private func isVisited(_ place: Place) -> Bool {
        place.status == .visited || visits.visitCount(for: place.id, fallbackVisited: false) > 0
    }

    private func stagger(for place: Place, in geo: GeometryProxy) -> TimeInterval {
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        let projected = CGPoint(
            x: center.x + CGFloat(place.longitude) * 8,
            y: center.y - CGFloat(place.latitude) * 8
        )
        let distance = hypot(projected.x - center.x, projected.y - center.y)
        _ = badgeTick
        return SavvyMapZoomHysteresis.staggerDelay(distanceFromCenter: distance)
    }

    private func openCard(for id: UUID) {
        let opening = !session.isOpen
        withAnimation(SavvyMapMotion.cardOpen(reduceMotion: reduceMotion)) {
            session.select(id)
        }
        guard opening, let place = mapViewModel.places.first(where: { $0.id == id })
                ?? mapViewModel.selectedPlace else { return }
        moveCamera(to: place)
    }

    private func moveCamera(to place: Place) {
        let delta = latitudeDelta > 0 ? latitudeDelta : 0.03
        let next = SavvyMapCameraFocus.camera(
            pin: place.coordinate,
            latitudeDelta: delta,
            current: liveCamera
        )
        let apply = {
            mapViewModel.cameraPosition = .camera(next)
        }
        if reduceMotion {
            apply()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + SavvyMapPinMetrics.cameraDelay) {
            withAnimation(SavvyMapMotion.camera) {
                apply()
            }
        }
    }

    private func flipCard() {
        withAnimation(
            session.isFlipped
                ? SavvyMapMotion.flipFront(reduceMotion: reduceMotion)
                : SavvyMapMotion.flipBack(reduceMotion: reduceMotion)
        ) {
            session.toggleFlip()
        }
    }

    private func collapseSelection(clearPlace: Bool) {
        let closingID = mapViewModel.selectedPlace?.id ?? session.placeID
        let plan = session.requestCollapse()
        switch plan {
        case .idle:
            break
        case .close:
            withAnimation(SavvyMapMotion.cardClose(reduceMotion: reduceMotion)) {
                session.finishCollapseAfterFlip()
            }
            finishClearingPlace(clearPlace, id: closingID)
        case .flipThenClose:
            if reduceMotion {
                withAnimation(SavvyMapMotion.reduceMotion) {
                    session.finishCollapseAfterFlip()
                }
                finishClearingPlace(clearPlace, id: closingID)
            } else {
                withAnimation(SavvyMapMotion.flipFront, completionCriteria: .logicallyComplete) {
                    session.isFlipped = false
                } completion: {
                    withAnimation(SavvyMapMotion.cardClose) {
                        session.finishCollapseAfterFlip()
                    }
                    finishClearingPlace(clearPlace, id: closingID)
                }
            }
        }
    }

    private func finishClearingPlace(_ clearPlace: Bool, id: UUID?) {
        guard clearPlace else { return }
        let delay = reduceMotion ? 0.26 : 0.50
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if mapViewModel.selectedPlace?.id == id || id == nil {
                onClearSelection()
            }
        }
    }

    private func markBeenHere(_ place: Place) async {
        visits.recordVisit(placeID: place.id)
        guard place.status != .visited else { return }
        var updated = place
        updated.status = .visited
        try? await mapViewModel.updatePlace(updated)
    }

    private func saveNote() async {
        guard var place = mapViewModel.selectedPlace else { return }
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        place.note = trimmed.isEmpty ? nil : trimmed
        try? await mapViewModel.updatePlace(place)
    }

    private func openDirections(_ place: Place) {
        guard let url = place.appleMapsURL else { return }
        UIApplication.shared.open(url)
    }

    private func fitCameraToVisiblePlacesIfNeeded() {
        let coordinates = savvyPinPlaces.map(\.coordinate)
        guard coordinates.count >= 1 else { return }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let spanLat = min(0.12, max(0.03, (maxLat - minLat) * 1.6 + 0.02))
        let spanLon = min(0.12, max(0.03, (maxLon - minLon) * 1.6 + 0.02))
        mapViewModel.cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
            )
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
