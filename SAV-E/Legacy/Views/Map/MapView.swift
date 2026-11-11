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
#if SAVVY_CITY_MVP
    private struct CityMVPDestination {
        let id = UUID()
        let requestedAt = ContinuousClock().now
        let camera: MapCamera
        let animation: Animation?
        var started = false
    }

    @State private var cityMVPFrame: CityDistrictCamera?
    @State private var cityMVPSceneReady = false
    private var cityMVPRenderFrame: CityDistrictCamera? {
        cityMVPFrame?.withSceneReadiness(cityMVPSceneReady)
    }
    @State private var cityMVPRegistration: CityDistrictRegistration?
    @State private var cityMVPRegistrationFailed = false
    @State private var cityMVPRegistrationAttempt = 0
    @State private var cityMVPStyle = CityDistrictMapStyle.globe
    @State private var cityMVPStyleRevision = 0
    @State private var cityMVPAppliedStyleRevision = 0
    @State private var cityMVPStyleAppliedAt: ContinuousClock.Instant?
    @State private var cityMVPObservedCamera: MapCamera?
    @State private var cityMVPProjectionRefresh: Task<Void, Never>?
    @State private var cityMVPRegionUpdate: Task<Void, Never>?
    @State private var cityMVPDestination: CityMVPDestination?
    @State private var cityMVPDestinationPreparation: Task<Void, Never>?
#endif

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
#if SAVVY_CITY_MVP
        if let distance = viewModel.cameraPosition.camera?.distance {
            _cityMVPStyle = State(initialValue: CityDistrictMapStyle.globe.updated(for: distance))
        }
#endif
    }

    var body: some View {
#if SAVVY_CITY_MVP
        if displayedPlaces == nil {
            let frame = cityMVPRenderFrame
            let registration = cityMVPRegistration
            MapReader { proxy in
                CityMVPMapSurface(viewModel: viewModel, frame: frame, registration: registration,
                                  selectedPin: cityMVPSelectedPin, sceneReady: $cityMVPSceneReady,
                                  registrationFailed: cityMVPRegistrationFailed,
                                  retryRegistration: {
                                      cityMVPRegistrationFailed = false
                                      cityMVPRegistrationAttempt += 1
                                  }, navigate: navigateCityMVP) {
                    standardMap(proxy: proxy)
                }
            }
            .task(id: cityMVPRegistrationAttempt) {
                guard cityMVPRegistration == nil else { return }
                let registration = await CityDistrictRegistration.resolve()
                guard !Task.isCancelled else { return }
                cityMVPRegistration = registration
                cityMVPRegistrationFailed = registration == nil
            }
        } else {
            standardMap()
        }
#else
        standardMap()
#endif
    }

#if SAVVY_CITY_MVP
    private var cityMVPMapStyle: MapStyle {
        guard displayedPlaces == nil else { return .standard(elevation: .flat) }
        return cityMVPStyle == .globe ? .imagery(elevation: .realistic) : .standard(elevation: .flat)
    }

    private var cityMVPSelectedPin: CityMVPSelectedPin? {
        CityMVPSelectedPin(viewModel: viewModel, registration: cityMVPRegistration)
    }

    private var cityMVPCityHall: CityScenePlace? {
        CityMVPPlaceBridge.cityHallPlace(in: viewModel.places)
    }

    private var cityMVPContextPins: [CityDistrictCamera.Pin] {
        guard let registration = cityMVPRegistration else { return [] }
        return CityMVPPlaceBridge.contextPins(in: viewModel.places, registration: registration)
    }

    private func navigateCityMVP(to camera: MapCamera, animation: Animation?) {
        cityMVPDestinationPreparation?.cancel()
        let destination = CityMVPDestination(camera: camera, animation: animation)
        cityMVPDestination = destination
        let style = cityMVPStyle.updated(for: camera.distance)
        CityDistrictTrace.navigation("requested", style: style, distance: camera.distance)
        if style != cityMVPStyle {
            applyCityMVPStyle(style)
        } else if cityMVPStyleRevision == cityMVPAppliedStyleRevision {
            if let applied = cityMVPStyleAppliedAt, ContinuousClock().now < applied.advanced(by: .milliseconds(120)) {
                prepareCityMVPDestination()
            } else {
                startCityMVPDestination(destination)
            }
        }
    }

    private func applyCityMVPStyle(_ style: CityDistrictMapStyle) {
        cityMVPProjectionRefresh?.cancel()
        withTransaction(Transaction(animation: nil)) {
            cityMVPFrame = nil
            cityMVPStyle = style
            cityMVPStyleRevision += 1
        }
    }

    private func prepareCityMVPDestination() {
        guard let destination = cityMVPDestination, !destination.started,
              cityMVPStyleRevision == cityMVPAppliedStyleRevision else { return }
        cityMVPDestinationPreparation?.cancel()
        // Give the native style change time to publish its final camera before
        // writing a new target. New native samples extend the quiet period.
        let applied = cityMVPStyleAppliedAt ?? destination.requestedAt
        let deadline = min(ContinuousClock().now.advanced(by: .milliseconds(120)),
                           max(applied, destination.requestedAt).advanced(by: .milliseconds(750)))
        cityMVPDestinationPreparation = Task { @MainActor in
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            guard !Task.isCancelled else { return }
            startCityMVPDestination(destination)
        }
    }

    private func startCityMVPDestination(_ destination: CityMVPDestination) {
        guard cityMVPDestination?.id == destination.id, cityMVPDestination?.started == false else { return }
        cityMVPDestination?.started = true
        CityDistrictTrace.navigation("started", style: cityMVPStyle, distance: destination.camera.distance)
        withAnimation(destination.animation) {
            viewModel.cameraPosition = .camera(destination.camera)
        }
    }

    private func cancelCityMVPDestination() {
        cityMVPDestinationPreparation?.cancel()
        cityMVPDestination = nil
    }

    private func observeCityMVPCamera(_ camera: MapCamera, settled: Bool, proxy: MapProxy, viewport: CGSize) {
        cityMVPProjectionRefresh?.cancel()
        cityMVPObservedCamera = camera
        if let destination = cityMVPDestination {
            if !destination.started {
                prepareCityMVPDestination()
            } else if viewModel.cameraPosition.positionedByUser
                        || (settled && cityMVPStyle.updated(for: camera.distance) == cityMVPStyle) {
                cancelCityMVPDestination()
            }
        }
        let style = cityMVPStyle.observing(distance: camera.distance, settled: settled,
                                          hasDestination: cityMVPDestination != nil)
        if style != cityMVPStyle {
            applyCityMVPStyle(style)
            return
        }
        sampleCityMVPCamera(camera, proxy: proxy, viewport: viewport, canRefresh: true)
    }

    private func sampleCityMVPCamera(_ camera: MapCamera, proxy: MapProxy, viewport: CGSize, canRefresh: Bool) {
        guard cityMVPStyleRevision == cityMVPAppliedStyleRevision, viewport.width > 0, viewport.height > 0 else { return }
        let cityHallPin = camera.distance < 3_800 ? cityMVPRegistration.flatMap { registration in
            cityMVPCityHall.map { CityMVPPlaceBridge.contextPin(for: $0, registration: registration) }
        } : nil
        let sample = CityDistrictCamera(camera: camera, registration: cityMVPRegistration, style: cityMVPStyle,
                                        styleRevision: cityMVPStyleRevision, viewport: viewport,
                                        selectedPin: cityMVPSelectedPin?.anchor, cityHallPin: cityHallPin,
                                        contextPins: camera.distance < 3_800 ? cityMVPContextPins : [],
                                        traceCameraCenter: CityDistrictTrace.enabled) {
            proxy.convert($0, to: .named(CityDistrictCamera.space))
        }
        if canRefresh, sample.needsProjectionRefresh {
            if cityMVPFrame?.canRetainProjection(for: sample) != true { cityMVPFrame = sample }
            refreshCityMVPCamera(proxy: proxy, viewport: viewport)
        } else {
            cityMVPFrame = sample
        }
    }

    private func refreshCityMVPCamera(proxy: MapProxy, viewport: CGSize) {
        cityMVPProjectionRefresh?.cancel()
        guard cityMVPObservedCamera != nil else { return }
        // MapProxy conversion may be unavailable during the layout or style update.
        cityMVPProjectionRefresh = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(34)) }
            catch { return }
            guard !Task.isCancelled, let camera = cityMVPObservedCamera else { return }
            sampleCityMVPCamera(camera, proxy: proxy, viewport: viewport, canRefresh: false)
        }
    }
#endif

    private func rootMapBottomInset(safeArea: CGFloat) -> CGFloat {
#if SAVVY_CITY_MVP
        // The place panel may open during a pinch. Keep the native camera's
        // viewport fixed so that choosing a pin cannot move the map.
        return 96
#else
        return max(safeArea + (viewModel.selectedPlace == nil ? 148 : 240),
                   viewModel.selectedPlace == nil ? 160 : 252)
#endif
    }

    private func showsNativeSavedPin(_ place: Place) -> Bool {
#if SAVVY_CITY_MVP
        if displayedPlaces == nil {
            if cityMVPSelectedPin?.anchor.id == place.id.uuidString { return false }
            if let registration = cityMVPRegistration, let frame = cityMVPRenderFrame,
               CityMVPPlaceBridge.projectsSavedPin(place, in: frame, registration: registration) { return false }
        }
#endif
        return place.isMapKitMappable
    }

    private func showsNativeCandidatePin(_ candidate: SaveMapCandidate) -> Bool {
#if SAVVY_CITY_MVP
        if displayedPlaces == nil && cityMVPSelectedPin?.anchor.id == candidate.id { return false }
#endif
        return true
    }

    private func nativePinCoordinate(_ place: Place) -> CLLocationCoordinate2D {
#if SAVVY_CITY_MVP
        if displayedPlaces == nil, let registration = cityMVPRegistration,
           CityMVPPlaceBridge.hasBundledCoordinate(place) {
            return registration.mapCoordinate(place.coordinate)
        }
#endif
        return place.coordinate
    }

    private func standardMap(proxy: MapProxy? = nil) -> some View {
        GeometryReader { geo in
            let topChromeInset = max(geo.safeAreaInsets.top + 12, 62)
            // Root Map parks a 64pt search panel above the tab bar.
            // Trip Map crops MapView above its place card, so a short
            // trailing clearance is enough. Selection swaps the pill for a
            // taller place peek, so locate rises with that chrome.
            let isEmbeddedCrop = displayedPlaces != nil
            let bottomChromeInset = isEmbeddedCrop
                ? max(geo.safeAreaInsets.bottom + 18, 28)
                : rootMapBottomInset(safeArea: geo.safeAreaInsets.bottom)

            ZStack {
                Map(position: $viewModel.cameraPosition, selection: $viewModel.selectedMapFeature) {
#if DEBUG
                    if ProcessInfo.processInfo.environment["SAVE_SKIP_LOCATION_PROMPT"] != "1"
                        && !ProcessInfo.processInfo.arguments.contains("--uitest-location-denied") {
                        UserAnnotation()
                    }
#else
                    UserAnnotation()
#endif

#if SAVVY_CITY_MVP
                    if proxy != nil, let pin = cityMVPSelectedPin,
                       cityMVPRenderFrame?.ownsSelectedPin(pin.anchor) != true {
                        Annotation("", coordinate: pin.anchor.coordinate, anchor: .bottom) {
                            pin.artwork()
                        }
                    }

                    if proxy != nil, let frame = cityMVPRenderFrame, frame.distance < 3_800,
                       let registration = cityMVPRegistration, let cityHall = cityMVPCityHall,
                       cityMVPSelectedPin?.contextID != cityHall.id {
                        let pin = CityMVPPlaceBridge.contextPin(for: cityHall, registration: registration)
                        if !frame.ownsCityHallPin(pin) {
                            Annotation("", coordinate: pin.coordinate, anchor: .bottom) {
                                Button {
                                    CityMVPPlaceBridge.select(cityHall, in: viewModel)
                                } label: {
                                    CityPinArtwork(id: cityHall.id, title: cityHall.title, symbol: "building.columns",
                                                   saved: cityHall.isSaved, selected: false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(cityHall.title)
                                .accessibilityValue(cityHall.isSaved ? "Map Stamp" : "Unsaved place")
                                .accessibilityIdentifier("cityMVP.groundPin.\(cityHall.id)")
                            }
                        }
                    }
#endif

                    ForEach((displayedPlaces ?? viewModel.filteredPlaces).filter(showsNativeSavedPin)) { place in
                        Annotation("", coordinate: nativePinCoordinate(place)) {
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

                        ForEach(viewModel.visibleMapCandidates.filter(showsNativeCandidatePin)) { candidate in
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
#if SAVVY_CITY_MVP
                .mapStyle(cityMVPMapStyle)
#else
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
#endif
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: bottomChromeInset)
                        .allowsHitTesting(false)
                }
                .mapFeatureSelectionDisabled { feature in
#if SAVVY_CITY_MVP
                    feature.kind != .pointOfInterest || (displayedPlaces == nil && cityMVPRenderFrame?.showsStreetDetail == true)
#else
                    feature.kind != .pointOfInterest
#endif
                }
                .mapControls {
#if SAVVY_CITY_MVP
                    if displayedPlaces != nil { MapCompass() }
#else
                    MapCompass()
#endif
                }
                .onChange(of: viewModel.selectedMapFeature) { _, feature in
                    viewModel.selectMapFeature(feature)
                }
                .onMapCameraChange(frequency: proxy == nil ? .onEnd : .continuous) { context in
                    guard displayedPlaces == nil else { return }
#if SAVVY_CITY_MVP
                    if let proxy {
                        observeCityMVPCamera(context.camera, settled: false, proxy: proxy, viewport: geo.size)
                        cityMVPRegionUpdate?.cancel()
                        cityMVPRegionUpdate = Task { @MainActor in
                            do { try await Task.sleep(for: .milliseconds(200)) }
                            catch { return }
                            viewModel.updateVisibleMapRegion(context.region)
                        }
                        return
                    }
#endif
                    viewModel.updateVisibleMapRegion(context.region)
                }
#if SAVVY_CITY_MVP
                .onMapCameraChange(frequency: .onEnd) { context in
                    guard let proxy else { return }
                    observeCityMVPCamera(context.camera, settled: true, proxy: proxy, viewport: geo.size)
                }
                .onChange(of: cityMVPStyleRevision) { _, revision in
                    guard let proxy else { return }
                    cityMVPAppliedStyleRevision = revision
                    cityMVPStyleAppliedAt = ContinuousClock().now
                    CityDistrictTrace.navigation("style-applied", style: cityMVPStyle,
                                                 distance: cityMVPObservedCamera?.distance ?? -1)
                    refreshCityMVPCamera(proxy: proxy, viewport: geo.size)
                    prepareCityMVPDestination()
                }
                .onChange(of: viewModel.cameraPosition.positionedByUser) { _, positionedByUser in
                    guard proxy != nil, positionedByUser else { return }
                    cancelCityMVPDestination()
                }
                .onChange(of: cityMVPRegistration) { _, _ in
                    guard let proxy else { return }
                    cityMVPFrame = nil
                    refreshCityMVPCamera(proxy: proxy, viewport: geo.size)
                }
                .onChange(of: geo.size) { _, size in
                    guard let proxy else { return }
                    cityMVPFrame = nil
                    refreshCityMVPCamera(proxy: proxy, viewport: size)
                }
                .onChange(of: cityMVPSelectedPin?.anchor) { _, _ in
                    guard let proxy else { return }
                    refreshCityMVPCamera(proxy: proxy, viewport: geo.size)
                }
                .onChange(of: cityMVPContextPins) { _, _ in
                    guard let proxy, let camera = cityMVPObservedCamera, camera.distance < 3_800 else { return }
                    refreshCityMVPCamera(proxy: proxy, viewport: geo.size)
                }
                .onDisappear {
                    guard proxy != nil else { return }
                    cityMVPRegionUpdate?.cancel()
                    cityMVPProjectionRefresh?.cancel()
                    cancelCityMVPDestination()
                    cityMVPObservedCamera = nil
                    cityMVPFrame = nil
                }
#endif
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
#if SAVVY_CITY_MVP
                    .padding(.bottom, bottomChromeInset + (isEmbeddedCrop ? 0 : 32))
#else
                    .padding(.bottom, bottomChromeInset)
#endif
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
struct SaveLocationDeniedNotice: View {
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

struct ReviewCandidateMapPin: View {
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

struct UnsavedMapCandidatePin: View {
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

struct DefaultPOIMarker: View {
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

enum MapMarkerState: Equatable {
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

extension PlaceCategory {
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

extension PlaceReviewCandidate {
    var inferredCategory: PlaceCategory {
        PlaceCategory.inferred(from: ([name, address, city ?? ""] + evidence).joined(separator: " "))
    }

    var coordinate: CLLocationCoordinate2D? {
        guard hasReliableCoordinates, let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
